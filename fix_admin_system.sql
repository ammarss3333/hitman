-- =====================================================
-- نظام المشرفين (Admins) + المسابقات + الإعلانات
-- شغّل هذا في Supabase → SQL Editor
--
-- الأمان: كل دوال المشرف تتحقق من صلاحية المستدعي على
-- مستوى قاعدة البيانات (is_admin) — لا يُوثَق أبداً بالمتصفح.
-- =====================================================

-- 1. أعمدة جديدة على اللاعبين
ALTER TABLE public.players ADD COLUMN IF NOT EXISTS is_admin   BOOLEAN DEFAULT FALSE;
ALTER TABLE public.players ADD COLUMN IF NOT EXISTS is_banned  BOOLEAN DEFAULT FALSE;
ALTER TABLE public.players ADD COLUMN IF NOT EXISTS ban_reason TEXT;

-- 2. دالة مساعدة: هل المستخدم الحالي مشرف؟
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT COALESCE((SELECT is_admin FROM public.players WHERE id = auth.uid()), false);
$$;

-- 3. جدول الإعلانات (يظهر لكل اللاعبين)
CREATE TABLE IF NOT EXISTS public.announcements (
  id          UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  title       TEXT NOT NULL,
  body        TEXT DEFAULT '',
  type        TEXT DEFAULT 'info',          -- info | warning | event | prize
  author_name TEXT,
  pinned      BOOLEAN DEFAULT FALSE,
  active      BOOLEAN DEFAULT TRUE,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.announcements ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "ann_read" ON public.announcements;
CREATE POLICY "ann_read" ON public.announcements FOR SELECT USING (true);

-- 4. جدول المسابقات
CREATE TABLE IF NOT EXISTS public.competitions (
  id           UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  title        TEXT NOT NULL,
  description  TEXT DEFAULT '',
  metric       TEXT DEFAULT 'cash',          -- cash | level | strength | exp | manual
  prize        INTEGER DEFAULT 0,
  prize2       INTEGER DEFAULT 0,
  prize3       INTEGER DEFAULT 0,
  status       TEXT DEFAULT 'active',        -- active | ended
  winner_id    UUID,
  winner_name  TEXT,
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  ends_at      TIMESTAMPTZ
);
ALTER TABLE public.competitions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "comp_read" ON public.competitions;
CREATE POLICY "comp_read" ON public.competitions FOR SELECT USING (true);

-- =====================================================
-- دوال المشرف (كلها تتحقق من is_admin أولاً)
-- =====================================================

-- منح/خصم المال (موجب = منحة، سالب = خصم)
CREATE OR REPLACE FUNCTION admin_give_cash(p_target UUID, p_amount INTEGER, p_reason TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_name TEXT; v_title TEXT;
BEGIN
  IF NOT is_admin() THEN RETURN jsonb_build_object('success',false,'message','🚫 غير مصرّح'); END IF;
  UPDATE players SET cash = cash + p_amount WHERE id = p_target RETURNING username INTO v_name;
  IF v_name IS NULL THEN RETURN jsonb_build_object('success',false,'message','لاعب غير موجود'); END IF;
  v_title := CASE WHEN p_amount >= 0 THEN '🎁 منحة إدارية' ELSE '⚠️ خصم إداري' END;
  INSERT INTO events(player_id,type,title,description,money_change)
  VALUES(p_target,'admin', v_title, COALESCE(p_reason,'إجراء إداري'), p_amount);
  RETURN jsonb_build_object('success',true,'message','تم تعديل رصيد '||v_name||' بمقدار '||p_amount);
END $$;

-- تعديل أي إحصائية/حقل رقمي (set مباشر)
CREATE OR REPLACE FUNCTION admin_set_stat(p_target UUID, p_field TEXT, p_value INTEGER)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_name TEXT;
BEGIN
  IF NOT is_admin() THEN RETURN jsonb_build_object('success',false,'message','🚫 غير مصرّح'); END IF;
  IF p_field NOT IN ('strength','fitness','defense','labor','intelligence',
                     'level','exp','points','cash','bank_balance',
                     'energy','max_energy','health','max_health',
                     'willpower','max_willpower') THEN
    RETURN jsonb_build_object('success',false,'message','حقل غير مسموح');
  END IF;
  EXECUTE format('UPDATE players SET %I = $1 WHERE id = $2', p_field)
    USING p_value, p_target;
  SELECT username INTO v_name FROM players WHERE id = p_target;
  IF v_name IS NULL THEN RETURN jsonb_build_object('success',false,'message','لاعب غير موجود'); END IF;
  INSERT INTO events(player_id,type,title,description)
  VALUES(p_target,'admin','🔧 تعديل إداري','تم تعيين '||p_field||' = '||p_value);
  RETURN jsonb_build_object('success',true,'message','تم تعيين '||p_field||' للاعب '||v_name||' إلى '||p_value);
END $$;

-- سجن / إطلاق سراح
CREATE OR REPLACE FUNCTION admin_set_jail(p_target UUID, p_jail BOOLEAN, p_minutes INTEGER DEFAULT 30)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_name TEXT;
BEGIN
  IF NOT is_admin() THEN RETURN jsonb_build_object('success',false,'message','🚫 غير مصرّح'); END IF;
  IF p_jail THEN
    UPDATE players SET in_jail=true, jail_until=NOW()+(p_minutes||' minutes')::INTERVAL
      WHERE id=p_target RETURNING username INTO v_name;
  ELSE
    UPDATE players SET in_jail=false, jail_until=NULL WHERE id=p_target RETURNING username INTO v_name;
  END IF;
  IF v_name IS NULL THEN RETURN jsonb_build_object('success',false,'message','لاعب غير موجود'); END IF;
  INSERT INTO events(player_id,type,title,description)
  VALUES(p_target,'admin', CASE WHEN p_jail THEN '⛓️ سجن إداري' ELSE '🕊️ إطلاق سراح' END,
         CASE WHEN p_jail THEN 'لمدة '||p_minutes||' دقيقة' ELSE 'بقرار إداري' END);
  RETURN jsonb_build_object('success',true,'message',
    CASE WHEN p_jail THEN 'تم سجن '||v_name ELSE 'تم إطلاق سراح '||v_name END);
END $$;

-- مشفى / شفاء
CREATE OR REPLACE FUNCTION admin_set_hospital(p_target UUID, p_hosp BOOLEAN, p_minutes INTEGER DEFAULT 30)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_name TEXT;
BEGIN
  IF NOT is_admin() THEN RETURN jsonb_build_object('success',false,'message','🚫 غير مصرّح'); END IF;
  IF p_hosp THEN
    UPDATE players SET in_hospital=true, hospital_until=NOW()+(p_minutes||' minutes')::INTERVAL, health=1
      WHERE id=p_target RETURNING username INTO v_name;
  ELSE
    UPDATE players SET in_hospital=false, hospital_until=NULL, health=max_health
      WHERE id=p_target RETURNING username INTO v_name;
  END IF;
  IF v_name IS NULL THEN RETURN jsonb_build_object('success',false,'message','لاعب غير موجود'); END IF;
  RETURN jsonb_build_object('success',true,'message',
    CASE WHEN p_hosp THEN 'تم إدخال '||v_name||' المشفى' ELSE 'تم شفاء '||v_name END);
END $$;

-- حظر / رفع الحظر
CREATE OR REPLACE FUNCTION admin_set_ban(p_target UUID, p_ban BOOLEAN, p_reason TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_name TEXT; v_admin BOOLEAN;
BEGIN
  IF NOT is_admin() THEN RETURN jsonb_build_object('success',false,'message','🚫 غير مصرّح'); END IF;
  SELECT is_admin INTO v_admin FROM players WHERE id=p_target;
  IF v_admin THEN RETURN jsonb_build_object('success',false,'message','لا يمكن حظر مشرف آخر'); END IF;
  UPDATE players SET is_banned=p_ban, ban_reason=CASE WHEN p_ban THEN p_reason ELSE NULL END
    WHERE id=p_target RETURNING username INTO v_name;
  IF v_name IS NULL THEN RETURN jsonb_build_object('success',false,'message','لاعب غير موجود'); END IF;
  RETURN jsonb_build_object('success',true,'message',
    CASE WHEN p_ban THEN '🔨 تم حظر '||v_name ELSE '✅ تم رفع الحظر عن '||v_name END);
END $$;

-- إعادة شحن طاقة/صحة/إرادة لاعب بالكامل
CREATE OR REPLACE FUNCTION admin_refill(p_target UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_name TEXT;
BEGIN
  IF NOT is_admin() THEN RETURN jsonb_build_object('success',false,'message','🚫 غير مصرّح'); END IF;
  UPDATE players SET energy=max_energy, health=max_health, willpower=max_willpower
    WHERE id=p_target RETURNING username INTO v_name;
  IF v_name IS NULL THEN RETURN jsonb_build_object('success',false,'message','لاعب غير موجود'); END IF;
  RETURN jsonb_build_object('success',true,'message','تم إنعاش '||v_name||' بالكامل ⚡');
END $$;

-- ترقية/تنزيل صلاحية مشرف
CREATE OR REPLACE FUNCTION admin_set_admin(p_target UUID, p_make_admin BOOLEAN)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_name TEXT;
BEGIN
  IF NOT is_admin() THEN RETURN jsonb_build_object('success',false,'message','🚫 غير مصرّح'); END IF;
  UPDATE players SET is_admin=p_make_admin WHERE id=p_target RETURNING username INTO v_name;
  IF v_name IS NULL THEN RETURN jsonb_build_object('success',false,'message','لاعب غير موجود'); END IF;
  RETURN jsonb_build_object('success',true,'message',
    CASE WHEN p_make_admin THEN '👑 '||v_name||' أصبح مشرفاً' ELSE 'تم سحب صلاحية الإشراف من '||v_name END);
END $$;

-- نشر إعلان عام
CREATE OR REPLACE FUNCTION admin_post_announcement(p_title TEXT, p_body TEXT, p_type TEXT DEFAULT 'info', p_pinned BOOLEAN DEFAULT FALSE)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_admin_name TEXT;
BEGIN
  IF NOT is_admin() THEN RETURN jsonb_build_object('success',false,'message','🚫 غير مصرّح'); END IF;
  SELECT username INTO v_admin_name FROM players WHERE id=auth.uid();
  INSERT INTO announcements(title,body,type,author_name,pinned)
  VALUES(p_title,p_body,COALESCE(p_type,'info'),v_admin_name,COALESCE(p_pinned,false));
  RETURN jsonb_build_object('success',true,'message','📢 تم نشر الإعلان');
END $$;

-- حذف إعلان
CREATE OR REPLACE FUNCTION admin_delete_announcement(p_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NOT is_admin() THEN RETURN jsonb_build_object('success',false,'message','🚫 غير مصرّح'); END IF;
  UPDATE announcements SET active=false WHERE id=p_id;
  RETURN jsonb_build_object('success',true,'message','تم حذف الإعلان');
END $$;

-- منح مكافأة لكل اللاعبين النشطين (هدية جماعية)
CREATE OR REPLACE FUNCTION admin_gift_all(p_amount INTEGER, p_reason TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_count INTEGER;
BEGIN
  IF NOT is_admin() THEN RETURN jsonb_build_object('success',false,'message','🚫 غير مصرّح'); END IF;
  UPDATE players SET cash = cash + p_amount WHERE is_banned = false;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  INSERT INTO events(player_id,type,title,description,money_change)
  SELECT id,'admin','🎁 هدية جماعية',COALESCE(p_reason,'هدية من الإدارة'),p_amount
  FROM players WHERE is_banned = false;
  INSERT INTO announcements(title,body,type,author_name,pinned)
  VALUES('🎁 هدية جماعية!', 'حصل جميع اللاعبين على $'||p_amount||'. '||COALESCE(p_reason,''),'prize',
         (SELECT username FROM players WHERE id=auth.uid()), false);
  RETURN jsonb_build_object('success',true,'message','تم منح '||v_count||' لاعب مبلغ '||p_amount);
END $$;

-- =====================================================
-- نظام المسابقات
-- =====================================================

-- إنشاء مسابقة
CREATE OR REPLACE FUNCTION admin_create_competition(
  p_title TEXT, p_desc TEXT, p_metric TEXT,
  p_prize INTEGER, p_prize2 INTEGER DEFAULT 0, p_prize3 INTEGER DEFAULT 0,
  p_hours INTEGER DEFAULT 24)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_admin_name TEXT;
BEGIN
  IF NOT is_admin() THEN RETURN jsonb_build_object('success',false,'message','🚫 غير مصرّح'); END IF;
  SELECT username INTO v_admin_name FROM players WHERE id=auth.uid();
  INSERT INTO competitions(title,description,metric,prize,prize2,prize3,ends_at)
  VALUES(p_title,p_desc,p_metric,p_prize,p_prize2,p_prize3,NOW()+(p_hours||' hours')::INTERVAL);
  INSERT INTO announcements(title,body,type,author_name,pinned)
  VALUES('🏆 مسابقة جديدة: '||p_title,
         p_desc||' — الجائزة الأولى $'||p_prize,'event',v_admin_name,true);
  RETURN jsonb_build_object('success',true,'message','🏆 تم إنشاء المسابقة');
END $$;

-- إنهاء مسابقة وتوزيع الجوائز تلقائياً حسب المقياس
CREATE OR REPLACE FUNCTION admin_end_competition(p_comp_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_comp competitions%ROWTYPE;
  v_col  TEXT;
  v_ids  UUID[];
  v_names TEXT[];
  v_prizes INTEGER[];
  i INTEGER;
BEGIN
  IF NOT is_admin() THEN RETURN jsonb_build_object('success',false,'message','🚫 غير مصرّح'); END IF;
  SELECT * INTO v_comp FROM competitions WHERE id=p_comp_id;
  IF v_comp.id IS NULL THEN RETURN jsonb_build_object('success',false,'message','مسابقة غير موجودة'); END IF;
  IF v_comp.status='ended' THEN RETURN jsonb_build_object('success',false,'message','المسابقة منتهية بالفعل'); END IF;

  IF v_comp.metric NOT IN ('cash','level','strength','exp') THEN
    -- مقياس يدوي: لا توزيع تلقائي
    UPDATE competitions SET status='ended' WHERE id=p_comp_id;
    RETURN jsonb_build_object('success',true,'message','تم إنهاء المسابقة (توزيع يدوي)');
  END IF;
  v_col := v_comp.metric;

  -- أفضل 3 لاعبين غير محظورين حسب المقياس
  EXECUTE format(
    'SELECT array_agg(id ORDER BY %I DESC), array_agg(username ORDER BY %I DESC)
     FROM (SELECT id, username, %I FROM players WHERE is_banned=false ORDER BY %I DESC LIMIT 3) s',
    v_col, v_col, v_col, v_col)
  INTO v_ids, v_names;

  v_prizes := ARRAY[v_comp.prize, v_comp.prize2, v_comp.prize3];

  IF v_ids IS NULL OR array_length(v_ids,1) IS NULL THEN
    UPDATE competitions SET status='ended' WHERE id=p_comp_id;
    RETURN jsonb_build_object('success',false,'message','لا يوجد لاعبون');
  END IF;

  FOR i IN 1..array_length(v_ids,1) LOOP
    IF v_prizes[i] > 0 THEN
      UPDATE players SET cash = cash + v_prizes[i] WHERE id = v_ids[i];
      INSERT INTO events(player_id,type,title,description,money_change)
      VALUES(v_ids[i],'prize','🏆 جائزة مسابقة: '||v_comp.title,
             'المركز '||i||' — جائزة $'||v_prizes[i], v_prizes[i]);
    END IF;
  END LOOP;

  UPDATE competitions SET status='ended', winner_id=v_ids[1], winner_name=v_names[1] WHERE id=p_comp_id;

  INSERT INTO announcements(title,body,type,author_name,pinned)
  VALUES('🏆 انتهت مسابقة '||v_comp.title,
         '🥇 الفائز: '||v_names[1]||' وحصل على $'||v_comp.prize||'! تهانينا 🎉','prize',
         (SELECT username FROM players WHERE id=auth.uid()), false);

  RETURN jsonb_build_object('success',true,'message','🥇 الفائز: '||v_names[1],'winner',v_names[1]);
END $$;

-- منح جائزة يدوية للاعب محدد (لمسابقات النوع manual)
CREATE OR REPLACE FUNCTION admin_award_player(p_comp_id UUID, p_target UUID, p_amount INTEGER)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_name TEXT; v_title TEXT;
BEGIN
  IF NOT is_admin() THEN RETURN jsonb_build_object('success',false,'message','🚫 غير مصرّح'); END IF;
  SELECT title INTO v_title FROM competitions WHERE id=p_comp_id;
  UPDATE players SET cash=cash+p_amount WHERE id=p_target RETURNING username INTO v_name;
  IF v_name IS NULL THEN RETURN jsonb_build_object('success',false,'message','لاعب غير موجود'); END IF;
  INSERT INTO events(player_id,type,title,description,money_change)
  VALUES(p_target,'prize','🏆 جائزة: '||COALESCE(v_title,'مسابقة'),'مكافأة إدارية', p_amount);
  UPDATE competitions SET winner_id=p_target, winner_name=v_name WHERE id=p_comp_id;
  RETURN jsonb_build_object('success',true,'message','🎉 تم منح '||v_name||' جائزة $'||p_amount);
END $$;

-- بحث اللاعبين للمشرف (يشمل الحقول الإدارية)
CREATE OR REPLACE FUNCTION admin_search_players(p_query TEXT DEFAULT '')
RETURNS TABLE(
  id UUID, username TEXT, avatar TEXT, level INTEGER, cash INTEGER,
  strength INTEGER, in_jail BOOLEAN, in_hospital BOOLEAN,
  is_admin BOOLEAN, is_banned BOOLEAN, city TEXT
) LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NOT is_admin() THEN RETURN; END IF;
  RETURN QUERY
    SELECT p.id,p.username,p.avatar,p.level,p.cash,p.strength,
           p.in_jail,p.in_hospital,p.is_admin,p.is_banned,p.city
    FROM players p
    WHERE p_query='' OR p.username ILIKE '%'||p_query||'%'
    ORDER BY p.level DESC LIMIT 50;
END $$;

-- =====================================================
-- 👑 عيّن نفسك أول مشرف — استبدل البريد ببريدك
-- =====================================================
UPDATE public.players SET is_admin = true
WHERE id = (SELECT id FROM auth.users WHERE email = 'ammarss333@gmail.com');

NOTIFY pgrst, 'reload schema';
