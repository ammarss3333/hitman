-- GAME TIME: 1 game day = 2 real hours (7200 seconds)
-- This keeps players engaged without requiring 24h waits

-- ============================================================================
-- 1) work_shift — cooldown 24h → 2h, streak break 48h → 4h
-- ============================================================================
CREATE OR REPLACE FUNCTION work_shift()
RETURNS JSONB AS $$
DECLARE
  v_pid UUID := auth.uid();
  v_player players%ROWTYPE;
  v_job jobs%ROWTYPE;
  v_hours FLOAT;
  v_stat TEXT;
  v_cash INT; v_streak_bonus FLOAT;
  v_jp INT; v_stat_gain INT;
  v_new_streak INT;
BEGIN
  SELECT * INTO v_player FROM players WHERE id=v_pid FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'message','اللاعب غير موجود'); END IF;
  IF v_player.job_id IS NULL THEN RETURN jsonb_build_object('success',false,'message','ليس لديك وظيفة! اختر وظيفة أولاً'); END IF;
  IF v_player.in_jail AND v_player.jail_until > now() THEN RETURN jsonb_build_object('success',false,'message','لا يمكنك العمل وأنت في السجن'); END IF;
  IF v_player.in_hospital AND v_player.hospital_until > now() THEN RETURN jsonb_build_object('success',false,'message','لا يمكنك العمل وأنت في المستشفى'); END IF;

  SELECT * INTO v_job FROM jobs WHERE id=v_player.job_id;

  -- تبريد 2 ساعة (يوم لعبة)
  IF v_player.last_shift IS NOT NULL THEN
    v_hours := EXTRACT(EPOCH FROM (now()-v_player.last_shift))/3600;
    IF v_hours < 2 THEN
      RETURN jsonb_build_object('success',false,
        'message','وردية اليوم انتهت! الوردية القادمة بعد '||ROUND(2-v_hours,1)||' ساعة',
        'hours_left',2-v_hours);
    END IF;
  END IF;

  -- السلسلة: إن مرّ أكثر من 4 ساعات (فوّت يوم لعبة) تُعاد لـ 1، وإلا +1
  IF v_player.last_shift IS NOT NULL AND EXTRACT(EPOCH FROM (now()-v_player.last_shift))/3600 > 4 THEN
    v_new_streak := 1;
  ELSE
    v_new_streak := COALESCE(v_player.shift_streak,0) + 1;
  END IF;

  -- المكافآت: راتب أساسي × الدرجة + بونص سلسلة (5% لكل يوم، بحد أقصى 50%)
  v_streak_bonus := LEAST(v_new_streak * 0.05, 0.50);
  v_cash := ROUND(v_job.base_salary * v_player.job_level * (1 + v_streak_bonus));
  v_jp := v_player.job_level + 1;                     -- نقاط عمل
  v_stat_gain := 5 + (v_player.job_level * 2);        -- +7 درجة 1 … حتى +25 درجة 10
  v_stat := job_work_stat(v_player.job_id);

  UPDATE players SET
    cash = cash + v_cash,
    exp = exp + v_job.exp_per_day,
    job_points = job_points + v_jp,
    shift_streak = v_new_streak,
    last_shift = now(),
    last_active = now(),
    work_manual    = work_manual    + CASE WHEN v_stat='work_manual'    THEN v_stat_gain ELSE 0 END,
    work_intel     = work_intel     + CASE WHEN v_stat='work_intel'     THEN v_stat_gain ELSE 0 END,
    work_endurance = work_endurance + CASE WHEN v_stat='work_endurance' THEN v_stat_gain ELSE 0 END
  WHERE id=v_pid;

  PERFORM check_level_up(v_pid);

  INSERT INTO events(player_id,type,title,description,money_change,exp_change)
  VALUES(v_pid,'work_shift','🛠️ وردية عمل',
         'أنهيت وردية في '||v_job.name||' (سلسلة '||v_new_streak||' يوم لعبة)',
         v_cash, v_job.exp_per_day);

  RETURN jsonb_build_object(
    'success',true,
    'message','أنهيت وردية اليوم! 💪',
    'cash_earned',v_cash,
    'job_points_earned',v_jp,
    'streak',v_new_streak,
    'stat_gains',jsonb_build_object('stat',v_stat,'amount',v_stat_gain)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- 2) collect_salary — cooldown 24h → 2h
-- ============================================================================
CREATE OR REPLACE FUNCTION collect_salary()
RETURNS JSONB AS $$
DECLARE
  v_pid UUID := auth.uid();
  v_player players%ROWTYPE;
  v_job jobs%ROWTYPE;
  v_salary INT; v_hours FLOAT;
BEGIN
  SELECT * INTO v_player FROM players WHERE id=v_pid FOR UPDATE;
  IF v_player.job_id IS NULL THEN RETURN jsonb_build_object('success',false,'message','ليس لديك وظيفة'); END IF;
  SELECT * INTO v_job FROM jobs WHERE id=v_player.job_id;
  IF v_player.last_salary IS NOT NULL THEN
    v_hours := EXTRACT(EPOCH FROM (now()-v_player.last_salary))/3600;
    IF v_hours < 2 THEN RETURN jsonb_build_object('success',false,'message','يمكنك قبض راتبك بعد '||ROUND(2-v_hours,1)||' ساعة','hours_left',2-v_hours); END IF;
  END IF;
  v_salary := v_job.base_salary * v_player.job_level;
  UPDATE players SET cash=cash+v_salary, exp=exp+v_job.exp_per_day, last_salary=now() WHERE id=v_pid;
  PERFORM check_level_up(v_pid);
  INSERT INTO events(player_id,type,title,description,money_change,exp_change) VALUES(v_pid,'salary','💰 راتب يومي','حصلت على راتبك من '||v_job.name,v_salary,v_job.exp_per_day);
  RETURN jsonb_build_object('success',true,'salary',v_salary,'message','حصلت على راتبك: $'||v_salary||' 💰');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- 3) claim_daily_bonus — reset every 2h instead of midnight
-- ============================================================================
CREATE OR REPLACE FUNCTION claim_daily_bonus()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_pid   UUID := auth.uid();
  v_p     players%ROWTYPE;
  v_bonus INTEGER;
BEGIN
  SELECT * INTO v_p FROM players WHERE id = v_pid;

  -- يوم اللعبة = كل 2 ساعة (7200 ثانية)
  IF v_p.last_daily_bonus IS NOT NULL
     AND EXTRACT(EPOCH FROM (now() - v_p.last_daily_bonus)) < 7200 THEN
    RETURN jsonb_build_object('success',false,'message','⏰ عد بعد ساعتين لاستلام مكافأتك!');
  END IF;

  v_bonus := 1000 + (v_p.level * 500);

  UPDATE players SET
    cash             = cash + v_bonus,
    last_daily_bonus = NOW()
  WHERE id = v_pid;

  INSERT INTO events(player_id,type,title,description,money_change)
  VALUES(v_pid,'bonus','🎁 مكافأة يومية','مكافأة المستوى '||v_p.level,v_bonus);

  RETURN jsonb_build_object('success',true,'message','🎁 مكافأة يومية: +'||v_bonus||'$ 🎉','bonus',v_bonus);
END $$;

-- ============================================================================
-- 4) bump_daily — game day = floor(epoch / 7200) as BIGINT key
--    player_daily.day column is DATE; we add a companion game_day BIGINT column
--    so each 2-hour window is its own "day" without altering the original PK.
-- ============================================================================

-- Add game_day column if missing (bigint, represents 2-hour epoch slot)
ALTER TABLE public.player_daily ADD COLUMN IF NOT EXISTS game_day BIGINT;

-- Create unique index on (player_id, game_day) for ON CONFLICT support
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE tablename='player_daily' AND indexname='player_daily_pid_gday_key'
  ) THEN
    CREATE UNIQUE INDEX player_daily_pid_gday_key ON public.player_daily(player_id, game_day);
  END IF;
END $$;

CREATE OR REPLACE FUNCTION bump_daily(p_kind TEXT)
RETURNS JSONB AS $$
DECLARE
  v_pid UUID := auth.uid();
  v_gday BIGINT := floor(extract(epoch from now()) / 7200)::bigint;
BEGIN
  IF v_pid IS NULL THEN RETURN jsonb_build_object('success',false,'message','غير مصرح'); END IF;

  INSERT INTO public.player_daily (player_id, day, game_day)
  VALUES (v_pid, CURRENT_DATE, v_gday)
  ON CONFLICT (player_id, game_day) DO NOTHING;

  CASE p_kind
    WHEN 'crime'  THEN UPDATE public.player_daily SET crimes_done  = crimes_done  + 1 WHERE player_id=v_pid AND game_day=v_gday;
    WHEN 'attack' THEN UPDATE public.player_daily SET attacks_done = attacks_done + 1 WHERE player_id=v_pid AND game_day=v_gday;
    WHEN 'train'  THEN UPDATE public.player_daily SET trains_done  = trains_done  + 1 WHERE player_id=v_pid AND game_day=v_gday;
    WHEN 'casino' THEN UPDATE public.player_daily SET casino_done  = casino_done  + 1 WHERE player_id=v_pid AND game_day=v_gday;
    ELSE RETURN jsonb_build_object('success',false,'message','نوع غير صحيح');
  END CASE;

  RETURN jsonb_build_object('success',true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- 5) get_daily — uses game_day
-- ============================================================================
CREATE OR REPLACE FUNCTION get_daily()
RETURNS JSONB AS $$
DECLARE
  v_pid UUID := auth.uid();
  v_gday BIGINT := floor(extract(epoch from now()) / 7200)::bigint;
  v_row public.player_daily%ROWTYPE;
BEGIN
  IF v_pid IS NULL THEN RETURN jsonb_build_object('success',false,'message','غير مصرح'); END IF;

  INSERT INTO public.player_daily (player_id, day, game_day)
  VALUES (v_pid, CURRENT_DATE, v_gday)
  ON CONFLICT (player_id, game_day) DO NOTHING;

  SELECT * INTO v_row FROM public.player_daily WHERE player_id=v_pid AND game_day=v_gday;

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

-- ============================================================================
-- 6) claim_task — uses game_day
-- ============================================================================
CREATE OR REPLACE FUNCTION claim_task(p_task_id TEXT)
RETURNS JSONB AS $$
DECLARE
  v_pid   UUID := auth.uid();
  v_gday  BIGINT := floor(extract(epoch from now()) / 7200)::bigint;
  v_row   public.player_daily%ROWTYPE;
  v_met   BOOLEAN := false;
  v_cash  INT := 0;
  v_exp   INT := 0;
  v_pts   INT := 0;
  v_title TEXT;
  v_reqs  TEXT[] := ARRAY['crimes3','attack1','train2','casino1'];
BEGIN
  IF v_pid IS NULL THEN RETURN jsonb_build_object('success',false,'message','غير مصرح'); END IF;

  INSERT INTO public.player_daily (player_id, day, game_day)
  VALUES (v_pid, CURRENT_DATE, v_gday)
  ON CONFLICT (player_id, game_day) DO NOTHING;

  SELECT * INTO v_row FROM public.player_daily WHERE player_id=v_pid AND game_day=v_gday FOR UPDATE;

  IF p_task_id = ANY(v_row.claimed_tasks) THEN
    RETURN jsonb_build_object('success',false,'message','تم استلام هذه المهمة مسبقاً');
  END IF;

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
      v_met := (v_reqs <@ v_row.claimed_tasks);
      v_cash := 5000;  v_exp := 50;  v_pts := 3;
      v_title := 'مكافأة إكمال كل المهام';
    ELSE
      RETURN jsonb_build_object('success',false,'message','مهمة غير معروفة');
  END CASE;

  IF NOT v_met THEN
    RETURN jsonb_build_object('success',false,'message','لم تكتمل شروط هذه المهمة بعد');
  END IF;

  UPDATE public.players
    SET cash = cash + v_cash, exp = exp + v_exp, points = points + v_pts
    WHERE id = v_pid;

  UPDATE public.player_daily
    SET claimed_tasks = array_append(claimed_tasks, p_task_id)
    WHERE player_id = v_pid AND game_day = v_gday;

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

-- ============================================================================
-- 7) check_login_streak — game_day replaces CURRENT_DATE comparisons
-- ============================================================================

-- Add column to track last login by game_day number
ALTER TABLE public.players ADD COLUMN IF NOT EXISTS last_login_gday BIGINT;

CREATE OR REPLACE FUNCTION check_login_streak()
RETURNS JSONB AS $$
DECLARE
  v_pid    UUID := auth.uid();
  v_player public.players%ROWTYPE;
  v_gday   BIGINT := floor(extract(epoch from now()) / 7200)::bigint;
  v_streak INT;
  v_cash   INT;
  v_pts    INT;
BEGIN
  IF v_pid IS NULL THEN RETURN jsonb_build_object('success',false,'message','غير مصرح'); END IF;

  SELECT * INTO v_player FROM public.players WHERE id=v_pid FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'message','غير مصرح'); END IF;

  -- سُجِّل هذا اليوم (اللعبة) بالفعل: لا مكافأة
  IF v_player.last_login_gday = v_gday THEN
    RETURN jsonb_build_object('success',true,'streak',COALESCE(v_player.login_streak,0),'already',true);
  END IF;

  -- حساب السلسلة: إن كان آخر دخول قبل يوم لعبة واحد بالضبط → +1، وإلا تبدأ من 1
  IF v_player.last_login_gday = v_gday - 1 THEN
    v_streak := COALESCE(v_player.login_streak,0) + 1;
  ELSE
    v_streak := 1;
  END IF;

  -- مكافأة متدرّجة ومُسقّفة: 500 لكل يوم لعبة بحد أقصى 7 أيام لعبة
  v_cash := LEAST(v_streak, 7) * 500;
  v_pts  := LEAST(CEIL(v_streak::FLOAT / 2)::INT, 5);

  UPDATE public.players
    SET login_streak    = v_streak,
        last_login_gday = v_gday,
        last_login_day  = CURRENT_DATE,
        cash            = cash + v_cash,
        points          = points + v_pts
    WHERE id = v_pid;

  INSERT INTO public.events (player_id, type, title, description, money_change)
  VALUES (v_pid, 'login_streak', '🔥 مكافأة الدخول اليومي',
          'سلسلة دخول ' || v_streak || ' يوم لعبة — حصلت على $' || v_cash || ' و' || v_pts || ' نقطة', v_cash);

  RETURN jsonb_build_object(
    'success', true,
    'streak', v_streak,
    'already', false,
    'reward', jsonb_build_object('cash',v_cash,'points',v_pts)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- 8) apply_bank_interest — once per game day (2h); rate 0.1667%/game-day
--    equivalent to 2%/24 real hours (12 game-days), keeping daily earnings equal
-- ============================================================================
CREATE OR REPLACE FUNCTION apply_bank_interest()
RETURNS JSONB AS $$
DECLARE
  v_pid UUID := auth.uid();
  v_player players%ROWTYPE;
  v_game_days FLOAT; v_interest INT;
BEGIN
  SELECT * INTO v_player FROM players WHERE id=v_pid FOR UPDATE;
  IF NOT v_player.has_bank_account OR v_player.bank_balance = 0 THEN RETURN jsonb_build_object('success',false); END IF;
  -- عدد أيام اللعبة المنقضية (يوم لعبة = 7200 ثانية)
  v_game_days := EXTRACT(EPOCH FROM (now() - v_player.bank_last_interest)) / 7200;
  IF v_game_days < 1 THEN RETURN jsonb_build_object('success',false,'game_days',v_game_days); END IF;
  -- 0.1667% لكل يوم لعبة ≈ 2% كل 24 ساعة حقيقية (12 يوم لعبة)
  v_interest := floor(v_player.bank_balance * 0.001667 * floor(v_game_days))::INT;
  IF v_interest > 0 THEN
    UPDATE players SET bank_balance=bank_balance+v_interest, bank_last_interest=now() WHERE id=v_pid;
    INSERT INTO events(player_id,type,title,description,money_change)
    VALUES(v_pid,'bank_interest','📈 فائدة بنكية','حصلت على فائدة 0.167%/يوم لعبة: $'||v_interest,v_interest);
  END IF;
  RETURN jsonb_build_object('success',true,'interest',v_interest);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Refresh grants
GRANT EXECUTE ON FUNCTION bump_daily(TEXT)        TO authenticated;
GRANT EXECUTE ON FUNCTION get_daily()             TO authenticated;
GRANT EXECUTE ON FUNCTION claim_task(TEXT)        TO authenticated;
GRANT EXECUTE ON FUNCTION check_login_streak()    TO authenticated;

NOTIFY pgrst, 'reload schema';
