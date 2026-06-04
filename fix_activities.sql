-- =====================================================
-- نظام المهام اليومية + سلسلة تسجيل الدخول (قاتل مأجور)
-- نظام التفاعل اليومي: يمنح اللاعبين سبباً لتسجيل الدخول وإنجاز الأهداف كل يوم
-- انسخ هذا الملف بالكامل في Supabase SQL Editor وشغّله (idempotent)
-- =====================================================

-- =====================================================
-- 1) جدول تتبّع التقدّم اليومي
-- =====================================================
CREATE TABLE IF NOT EXISTS public.player_daily (
  player_id     UUID NOT NULL REFERENCES public.players(id) ON DELETE CASCADE,
  day           DATE NOT NULL DEFAULT CURRENT_DATE,
  crimes_done   INT  NOT NULL DEFAULT 0,
  attacks_done  INT  NOT NULL DEFAULT 0,
  trains_done   INT  NOT NULL DEFAULT 0,
  casino_done   INT  NOT NULL DEFAULT 0,
  claimed_tasks TEXT[] NOT NULL DEFAULT '{}',
  PRIMARY KEY (player_id, day)
);

ALTER TABLE public.player_daily ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "pd_sel" ON public.player_daily;
CREATE POLICY "pd_sel" ON public.player_daily
  FOR SELECT USING (player_id = auth.uid());

-- =====================================================
-- 2) أعمدة سلسلة تسجيل الدخول على جدول اللاعبين
-- =====================================================
ALTER TABLE public.players ADD COLUMN IF NOT EXISTS login_streak  INT DEFAULT 0;
ALTER TABLE public.players ADD COLUMN IF NOT EXISTS last_login_day DATE;

-- =====================================================
-- 3) RPC: زيادة عدّاد يومي (يُستدعى من صفحات اللعبة لاحقاً)
--    p_kind ∈ ('crime','attack','train','casino')
-- =====================================================
CREATE OR REPLACE FUNCTION bump_daily(p_kind TEXT)
RETURNS JSONB AS $$
DECLARE v_pid UUID := auth.uid();
BEGIN
  IF v_pid IS NULL THEN RETURN jsonb_build_object('success',false,'message','غير مصرح'); END IF;

  INSERT INTO public.player_daily (player_id, day)
  VALUES (v_pid, CURRENT_DATE)
  ON CONFLICT (player_id, day) DO NOTHING;

  CASE p_kind
    WHEN 'crime'  THEN UPDATE public.player_daily SET crimes_done  = crimes_done  + 1 WHERE player_id=v_pid AND day=CURRENT_DATE;
    WHEN 'attack' THEN UPDATE public.player_daily SET attacks_done = attacks_done + 1 WHERE player_id=v_pid AND day=CURRENT_DATE;
    WHEN 'train'  THEN UPDATE public.player_daily SET trains_done  = trains_done  + 1 WHERE player_id=v_pid AND day=CURRENT_DATE;
    WHEN 'casino' THEN UPDATE public.player_daily SET casino_done  = casino_done  + 1 WHERE player_id=v_pid AND day=CURRENT_DATE;
    ELSE RETURN jsonb_build_object('success',false,'message','نوع غير صحيح');
  END CASE;

  RETURN jsonb_build_object('success',true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- 4) RPC: جلب عدّادات اليوم الحالي (ينشئ صف اليوم إن لم يوجد)
-- =====================================================
CREATE OR REPLACE FUNCTION get_daily()
RETURNS JSONB AS $$
DECLARE
  v_pid UUID := auth.uid();
  v_row public.player_daily%ROWTYPE;
BEGIN
  IF v_pid IS NULL THEN RETURN jsonb_build_object('success',false,'message','غير مصرح'); END IF;

  INSERT INTO public.player_daily (player_id, day)
  VALUES (v_pid, CURRENT_DATE)
  ON CONFLICT (player_id, day) DO NOTHING;

  SELECT * INTO v_row FROM public.player_daily WHERE player_id=v_pid AND day=CURRENT_DATE;

  RETURN jsonb_build_object(
    'success', true,
    'crimes_done',  v_row.crimes_done,
    'attacks_done', v_row.attacks_done,
    'trains_done',  v_row.trains_done,
    'casino_done',  v_row.casino_done,
    'claimed_tasks', to_jsonb(v_row.claimed_tasks)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- 5) RPC: استلام مكافأة مهمة يومية
--    المكافآت معرّفة في الخادم حسب p_task_id (لا نثق بمبالغ العميل)
--    المهام:
--      crimes3  : ارتكب 3 جرائم        (crimes_done  >= 3)
--      attack1  : نفّذ هجوماً           (attacks_done >= 1)
--      train2   : تدرّب مرتين           (trains_done  >= 2)
--      casino1  : جرّب حظك في الكازينو  (casino_done  >= 1)
--      allbonus : أكمل كل المهام        (تم استلام الأربع السابقة)
-- =====================================================
CREATE OR REPLACE FUNCTION claim_task(p_task_id TEXT)
RETURNS JSONB AS $$
DECLARE
  v_pid   UUID := auth.uid();
  v_row   public.player_daily%ROWTYPE;
  v_met   BOOLEAN := false;
  v_cash  INT := 0;
  v_exp   INT := 0;
  v_pts   INT := 0;
  v_title TEXT;
  v_reqs  TEXT[] := ARRAY['crimes3','attack1','train2','casino1'];
BEGIN
  IF v_pid IS NULL THEN RETURN jsonb_build_object('success',false,'message','غير مصرح'); END IF;

  INSERT INTO public.player_daily (player_id, day)
  VALUES (v_pid, CURRENT_DATE)
  ON CONFLICT (player_id, day) DO NOTHING;

  SELECT * INTO v_row FROM public.player_daily WHERE player_id=v_pid AND day=CURRENT_DATE FOR UPDATE;

  IF p_task_id = ANY(v_row.claimed_tasks) THEN
    RETURN jsonb_build_object('success',false,'message','تم استلام هذه المهمة مسبقاً');
  END IF;

  -- تعريف الشرط والمكافأة لكل مهمة (في الخادم)
  CASE p_task_id
    WHEN 'crimes3' THEN
      v_met := v_row.crimes_done >= 3;  v_cash := 3000;  v_exp := 30;  v_pts := 1;
      v_title := 'مهمة: ارتكب 3 جرائم';
    WHEN 'attack1' THEN
      v_met := v_row.attacks_done >= 1; v_cash := 2500;  v_exp := 25;  v_pts := 1;
      v_title := 'مهمة: نفّذ هجوماً';
    WHEN 'train2' THEN
      v_met := v_row.trains_done >= 2;  v_cash := 2000;  v_exp := 20;  v_pts := 1;
      v_title := 'مهمة: تدرّب مرتين';
    WHEN 'casino1' THEN
      v_met := v_row.casino_done >= 1;  v_cash := 1500;  v_exp := 15;  v_pts := 1;
      v_title := 'مهمة: جرّب حظك في الكازينو';
    WHEN 'allbonus' THEN
      v_met := (v_reqs <@ v_row.claimed_tasks); -- كل المهام الأربع مستلَمة
      v_cash := 5000;  v_exp := 50;  v_pts := 3;
      v_title := 'مكافأة إكمال كل المهام';
    ELSE
      RETURN jsonb_build_object('success',false,'message','مهمة غير معروفة');
  END CASE;

  IF NOT v_met THEN
    RETURN jsonb_build_object('success',false,'message','لم تكتمل شروط هذه المهمة بعد');
  END IF;

  -- منح المكافأة
  UPDATE public.players
    SET cash = cash + v_cash, exp = exp + v_exp, points = points + v_pts
    WHERE id = v_pid;

  UPDATE public.player_daily
    SET claimed_tasks = array_append(claimed_tasks, p_task_id)
    WHERE player_id = v_pid AND day = CURRENT_DATE;

  PERFORM check_level_up(v_pid);

  INSERT INTO public.events (player_id, type, title, description, money_change, exp_change)
  VALUES (v_pid, 'daily_task', '🎯 مهمة يومية مكتملة', v_title || ' (+$' || v_cash || ', +' || v_exp || ' خبرة)', v_cash, v_exp);

  RETURN jsonb_build_object(
    'success', true,
    'message', 'حصلت على $' || v_cash || ' و' || v_exp || ' خبرة!',
    'reward', jsonb_build_object('cash',v_cash,'exp',v_exp,'points',v_pts)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- 6) RPC: فحص/تحديث سلسلة تسجيل الدخول اليومية
--    المكافأة تتدرّج مع السلسلة لكنها مُسقّفة (غير إجبارية)
-- =====================================================
CREATE OR REPLACE FUNCTION check_login_streak()
RETURNS JSONB AS $$
DECLARE
  v_pid    UUID := auth.uid();
  v_player public.players%ROWTYPE;
  v_streak INT;
  v_cash   INT;
  v_pts    INT;
BEGIN
  IF v_pid IS NULL THEN RETURN jsonb_build_object('success',false,'message','غير مصرح'); END IF;

  SELECT * INTO v_player FROM public.players WHERE id=v_pid FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'message','غير مصرح'); END IF;

  -- سُجِّل اليوم بالفعل: لا مكافأة
  IF v_player.last_login_day = CURRENT_DATE THEN
    RETURN jsonb_build_object('success',true,'streak',COALESCE(v_player.login_streak,0),'already',true);
  END IF;

  -- حساب السلسلة الجديدة
  IF v_player.last_login_day = CURRENT_DATE - 1 THEN
    v_streak := COALESCE(v_player.login_streak,0) + 1;
  ELSE
    v_streak := 1;
  END IF;

  -- مكافأة متدرّجة ومُسقّفة: 500 لكل يوم بحد أقصى 7 أيام (سقف $3500) + نقطة لكل يومين
  v_cash := LEAST(v_streak, 7) * 500;
  v_pts  := LEAST(CEIL(v_streak::FLOAT / 2)::INT, 5);

  UPDATE public.players
    SET login_streak = v_streak,
        last_login_day = CURRENT_DATE,
        cash = cash + v_cash,
        points = points + v_pts
    WHERE id = v_pid;

  INSERT INTO public.events (player_id, type, title, description, money_change)
  VALUES (v_pid, 'login_streak', '🔥 مكافأة الدخول اليومي',
          'سلسلة دخول ' || v_streak || ' يوم — حصلت على $' || v_cash || ' و' || v_pts || ' نقطة', v_cash);

  RETURN jsonb_build_object(
    'success', true,
    'streak', v_streak,
    'already', false,
    'reward', jsonb_build_object('cash',v_cash,'points',v_pts)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- صلاحيات التنفيذ
-- =====================================================
GRANT EXECUTE ON FUNCTION bump_daily(TEXT)        TO authenticated;
GRANT EXECUTE ON FUNCTION get_daily()             TO authenticated;
GRANT EXECUTE ON FUNCTION claim_task(TEXT)        TO authenticated;
GRANT EXECUTE ON FUNCTION check_login_streak()    TO authenticated;

NOTIFY pgrst, 'reload schema';
