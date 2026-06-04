-- =====================================================
-- حياة قاتل مأجور - قاعدة البيانات الكاملة
-- انسخ هذا الكود في Supabase SQL Editor وشغّله
-- =====================================================

-- ملحقات مطلوبة
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =====================================================
-- الجداول الأساسية
-- =====================================================

-- جدول اللاعبين
CREATE TABLE IF NOT EXISTS public.players (
  id UUID REFERENCES auth.users ON DELETE CASCADE PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  avatar TEXT DEFAULT '👤',
  level INTEGER DEFAULT 1,
  exp INTEGER DEFAULT 0,

  -- المال
  cash INTEGER DEFAULT 5000,
  bank_balance INTEGER DEFAULT 0,
  has_bank_account BOOLEAN DEFAULT FALSE,
  bank_last_interest TIMESTAMPTZ DEFAULT NOW(),

  -- الإحصائيات
  strength INTEGER DEFAULT 10,
  fitness INTEGER DEFAULT 10,
  defense INTEGER DEFAULT 10,
  labor INTEGER DEFAULT 10,
  intelligence INTEGER DEFAULT 10,

  -- الطاقة
  energy INTEGER DEFAULT 100,
  max_energy INTEGER DEFAULT 100,
  willpower INTEGER DEFAULT 100,
  max_willpower INTEGER DEFAULT 100,
  health INTEGER DEFAULT 100,
  max_health INTEGER DEFAULT 100,

  -- النقاط
  points INTEGER DEFAULT 50,

  -- الوضع
  city TEXT DEFAULT 'beirut',
  in_hospital BOOLEAN DEFAULT FALSE,
  hospital_until TIMESTAMPTZ,
  in_jail BOOLEAN DEFAULT FALSE,
  jail_until TIMESTAMPTZ,

  -- العمل
  job_id TEXT,
  job_level INTEGER DEFAULT 1,
  last_salary TIMESTAMPTZ,

  -- العصابة
  gang_id UUID,

  -- مواعيد
  last_energy_regen  TIMESTAMPTZ DEFAULT NOW(),
  last_active        TIMESTAMPTZ DEFAULT NOW(),
  last_daily_bonus   TIMESTAMPTZ,
  created_at         TIMESTAMPTZ DEFAULT NOW(),

  -- الإشراف
  is_admin   BOOLEAN DEFAULT FALSE,
  is_banned  BOOLEAN DEFAULT FALSE,
  ban_reason TEXT
);

-- جدول العصابات
CREATE TABLE IF NOT EXISTS public.gangs (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  name TEXT UNIQUE NOT NULL,
  tag TEXT UNIQUE NOT NULL,
  description TEXT DEFAULT '',
  leader_id UUID REFERENCES public.players(id),
  vice_leader_id UUID REFERENCES public.players(id),
  level INTEGER DEFAULT 1,
  exp INTEGER DEFAULT 0,
  respect INTEGER DEFAULT 0,
  cash INTEGER DEFAULT 0,
  max_members INTEGER DEFAULT 5,
  city TEXT DEFAULT 'beirut',
  logo TEXT DEFAULT '💀',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- جدول الإعلانات
CREATE TABLE IF NOT EXISTS public.announcements (
  id          UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  title       TEXT NOT NULL,
  body        TEXT DEFAULT '',
  type        TEXT DEFAULT 'info',
  author_name TEXT,
  pinned      BOOLEAN DEFAULT FALSE,
  active      BOOLEAN DEFAULT TRUE,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.announcements ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "ann_read" ON public.announcements;
CREATE POLICY "ann_read" ON public.announcements FOR SELECT USING (true);

-- جدول المسابقات
CREATE TABLE IF NOT EXISTS public.competitions (
  id           UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  title        TEXT NOT NULL,
  description  TEXT DEFAULT '',
  metric       TEXT DEFAULT 'cash',
  prize        INTEGER DEFAULT 0,
  prize2       INTEGER DEFAULT 0,
  prize3       INTEGER DEFAULT 0,
  status       TEXT DEFAULT 'active',
  winner_id    UUID,
  winner_name  TEXT,
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  ends_at      TIMESTAMPTZ
);
ALTER TABLE public.competitions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "comp_read" ON public.competitions;
CREATE POLICY "comp_read" ON public.competitions FOR SELECT USING (true);

-- ربط gang_id في جدول اللاعبين بجدول العصابات (مفتاح خارجي)
-- هذا ضروري حتى يتعرف Supabase/PostgREST على العلاقة players -> gangs
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'players_gang_id_fkey'
  ) THEN
    ALTER TABLE public.players
      ADD CONSTRAINT players_gang_id_fkey
      FOREIGN KEY (gang_id) REFERENCES public.gangs(id) ON DELETE SET NULL;
  END IF;
END $$;

-- أعضاء العصابات
CREATE TABLE IF NOT EXISTS public.gang_members (
  gang_id UUID REFERENCES public.gangs(id) ON DELETE CASCADE,
  player_id UUID REFERENCES public.players(id) ON DELETE CASCADE,
  role TEXT DEFAULT 'member',
  joined_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (gang_id, player_id)
);

-- الأسلحة المتاحة في المتجر
CREATE TABLE IF NOT EXISTS public.weapons (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  name TEXT NOT NULL,
  type TEXT NOT NULL,
  attack_bonus INTEGER DEFAULT 0,
  defense_bonus INTEGER DEFAULT 0,
  image TEXT DEFAULT '🔫',
  price INTEGER DEFAULT 1000,
  level_required INTEGER DEFAULT 1
);

-- مخزون اللاعب
CREATE TABLE IF NOT EXISTS public.inventory (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  player_id UUID REFERENCES public.players(id) ON DELETE CASCADE,
  weapon_id UUID REFERENCES public.weapons(id),
  equipped BOOLEAN DEFAULT FALSE,
  for_sale BOOLEAN DEFAULT FALSE,
  sale_price INTEGER,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- سوق الأسلحة
CREATE TABLE IF NOT EXISTS public.market (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  seller_id UUID REFERENCES public.players(id),
  inventory_id UUID REFERENCES public.inventory(id) ON DELETE CASCADE,
  weapon_id UUID REFERENCES public.weapons(id),
  price INTEGER NOT NULL,
  seller_name TEXT,
  weapon_name TEXT,
  weapon_image TEXT,
  weapon_attack INTEGER DEFAULT 0,
  weapon_defense INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- الجرائم
CREATE TABLE IF NOT EXISTS public.crimes (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  min_level INTEGER DEFAULT 1,
  base_money_min INTEGER DEFAULT 100,
  base_money_max INTEGER DEFAULT 500,
  base_exp INTEGER DEFAULT 10,
  energy_cost INTEGER DEFAULT 10,
  jail_chance INTEGER DEFAULT 10,
  hospital_chance INTEGER DEFAULT 5,
  jail_time_minutes INTEGER DEFAULT 30,
  hospital_time_minutes INTEGER DEFAULT 20,
  image TEXT DEFAULT '🔪'
);

-- الوظائف
CREATE TABLE IF NOT EXISTS public.jobs (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  base_salary INTEGER DEFAULT 500,
  strength_req INTEGER DEFAULT 0,
  intelligence_req INTEGER DEFAULT 0,
  labor_req INTEGER DEFAULT 0,
  exp_per_day INTEGER DEFAULT 20,
  max_level INTEGER DEFAULT 10,
  image TEXT DEFAULT '💼'
);

-- دورات التدريب
CREATE TABLE IF NOT EXISTS public.courses (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  duration_days INTEGER DEFAULT 1,
  cost INTEGER DEFAULT 1000,
  strength_gain INTEGER DEFAULT 0,
  fitness_gain INTEGER DEFAULT 0,
  defense_gain INTEGER DEFAULT 0,
  labor_gain INTEGER DEFAULT 0,
  intelligence_gain INTEGER DEFAULT 0,
  level_required INTEGER DEFAULT 1,
  image TEXT DEFAULT '📚'
);

-- دورات اللاعب النشطة
CREATE TABLE IF NOT EXISTS public.player_courses (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  player_id UUID REFERENCES public.players(id) ON DELETE CASCADE,
  course_id TEXT REFERENCES public.courses(id),
  started_at TIMESTAMPTZ DEFAULT NOW(),
  ends_at TIMESTAMPTZ NOT NULL,
  completed BOOLEAN DEFAULT FALSE
);

-- سجل الهجمات
CREATE TABLE IF NOT EXISTS public.attacks (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  attacker_id UUID REFERENCES public.players(id),
  defender_id UUID REFERENCES public.players(id),
  winner_id UUID REFERENCES public.players(id),
  attacker_name TEXT,
  defender_name TEXT,
  attacker_roll INTEGER,
  defender_roll INTEGER,
  money_stolen INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- الرسائل
CREATE TABLE IF NOT EXISTS public.messages (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  from_id UUID REFERENCES public.players(id),
  to_id UUID REFERENCES public.players(id),
  from_name TEXT,
  subject TEXT NOT NULL,
  body TEXT NOT NULL,
  read BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- سجل الأحداث
CREATE TABLE IF NOT EXISTS public.events (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  player_id UUID REFERENCES public.players(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  money_change INTEGER DEFAULT 0,
  exp_change INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- العقارات
CREATE TABLE IF NOT EXISTS public.properties (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  city TEXT NOT NULL,
  type TEXT DEFAULT 'apartment',
  price INTEGER NOT NULL,
  daily_income INTEGER DEFAULT 0,
  image TEXT DEFAULT '🏠'
);

-- عقارات اللاعب
CREATE TABLE IF NOT EXISTS public.player_properties (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  player_id UUID REFERENCES public.players(id),
  property_id TEXT REFERENCES public.properties(id),
  last_collected TIMESTAMPTZ DEFAULT NOW(),
  purchased_at TIMESTAMPTZ DEFAULT NOW()
);

-- الأسهم
CREATE TABLE IF NOT EXISTS public.stocks (
  id TEXT PRIMARY KEY,
  company TEXT NOT NULL,
  symbol TEXT UNIQUE NOT NULL,
  price DECIMAL DEFAULT 100,
  change_percent DECIMAL DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- أسهم اللاعب
CREATE TABLE IF NOT EXISTS public.player_stocks (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  player_id UUID REFERENCES public.players(id),
  stock_id TEXT REFERENCES public.stocks(id),
  shares INTEGER DEFAULT 0,
  avg_buy_price DECIMAL DEFAULT 0,
  UNIQUE(player_id, stock_id)
);

-- =====================================================
-- بيانات افتراضية
-- =====================================================

INSERT INTO public.crimes VALUES
  ('pickpocket',   'سرقة المارة',      'سرق محفظة أحد المارة في الشارع',       1,  200,  800,  15, 10,  8, 3,  30,  15, '👜'),
  ('carjack',      'سرقة سيارة',       'سرق سيارة من موقف السيارات',            3,  500,  2000, 25, 15, 15, 5,  60,  30, '🚗'),
  ('shoplifting',  'سرقة من متجر',     'سرق بضائع من محل تجاري',               2,  300,  1200, 18, 12, 12, 4,  45,  20, '🏪'),
  ('robbery',      'سطو مسلح',         'سطا على محل تجاري بالسلاح',            5,  1000, 5000, 40, 20, 20, 10, 120, 60, '🔫'),
  ('kidnapping',   'خطف رهينة',        'اختطف شخصاً للحصول على فدية',          8,  2000, 10000,60, 25, 25, 15, 180, 90, '🎯'),
  ('bank_robbery', 'سطو على بنك',      'نفّذ سطواً على أحد البنوك',            10, 5000, 20000,70, 30, 28, 18, 240, 120,'💰'),
  ('assassination','اغتيال مأجور',     'نفّذ عقداً للاغتيال',                  12, 8000, 30000,80, 35, 30, 20, 360, 180,'🔪')
ON CONFLICT DO NOTHING;

INSERT INTO public.jobs VALUES
  ('guard',     'حارس أمن',       'حارس في إحدى المنشآت',           800,  5,  0,  5,  30,  10, '🛡️'),
  ('driver',    'سائق خاص',       'سائق لأحد الشخصيات المهمة',      1200, 0,  0,  10, 40,  10, '🚗'),
  ('mechanic',  'ميكانيكي',       'صيانة السيارات والمركبات',        1000, 0,  0,  15, 35,  10, '🔧'),
  ('dealer',    'تاجر سلاح',      'بيع الأسلحة في السوق السوداء',   2000, 10, 5,  10, 50,  10, '💼'),
  ('hacker',    'قرصان إلكتروني', 'اختراق الأنظمة الأمنية',         2500, 0,  20, 5,  60,  10, '💻'),
  ('bodyguard', 'حارس شخصي',      'حماية شخصية للأثرياء',           3000, 20, 10, 10, 80,  10, '🕵️'),
  ('assassin',  'قاتل مأجور',     'تنفيذ عقود الاغتيال',            5000, 30, 20, 20, 120, 10, '🎯')
ON CONFLICT DO NOTHING;

INSERT INTO public.courses VALUES
  ('boxing',       'تدريب الملاكمة',    'تحسين القوة والياقة البدنية',  1, 2000, 3, 3, 0, 0, 0, 1, '🥊'),
  ('weapons',      'تدريب على الأسلحة', 'تحسين القوة والدفاع',         2, 3000, 5, 0, 5, 0, 0, 3, '🔫'),
  ('martial_arts', 'فنون القتال',       'تحسين جميع الإحصائيات القتالية',3,5000,5, 5, 7, 5, 0, 5, '🥋'),
  ('hacking',      'تدريب القرصنة',     'تحسين الذكاء بشكل كبير',      2, 4000, 5, 0, 0, 0, 8, 4, '💻'),
  ('leadership',   'تدريب القيادة',     'تحسين العمالة والذكاء',       3, 6000, 7, 0, 0, 3, 5, 6, '👑'),
  ('stealth',      'تدريب التخفي',      'تحسين اللياقة والدفاع',       4, 8000, 7, 0, 5, 6, 2, 8, '🥷')
ON CONFLICT DO NOTHING;

INSERT INTO public.weapons VALUES
  (uuid_generate_v4(), 'سكين',            'melee',  5,  0,  '🔪', 500,   1),
  (uuid_generate_v4(), 'هراوة',           'melee',  8,  3,  '🏏', 800,   1),
  (uuid_generate_v4(), 'مطواة',           'melee',  12, 0,  '🗡️', 1500,  2),
  (uuid_generate_v4(), 'مسدس',            'pistol', 15, 0,  '🔫', 3000,  2),
  (uuid_generate_v4(), 'مسدس مكتوم',     'pistol', 20, 0,  '🔫', 6000,  4),
  (uuid_generate_v4(), 'بندقية خردق',    'rifle',  28, 0,  '🎯', 8000,  4),
  (uuid_generate_v4(), 'كلاشنكوف',       'rifle',  42, 0,  '🔫', 15000, 6),
  (uuid_generate_v4(), 'بندقية قنص',     'rifle',  65, 0,  '🎯', 30000, 8),
  (uuid_generate_v4(), 'سترة واقية',     'armor',  0,  20, '🛡️', 5000,  3),
  (uuid_generate_v4(), 'درع كامل',       'armor',  0,  40, '🛡️', 20000, 6),
  (uuid_generate_v4(), 'درع خاص',        'armor',  0,  60, '🛡️', 50000, 9)
ON CONFLICT DO NOTHING;

INSERT INTO public.properties VALUES
  ('apt_beirut',     'شقة في بيروت',   'beirut',   'apartment', 50000,   500,  '🏠'),
  ('villa_beirut',   'فيلا في بيروت',  'beirut',   'villa',     200000,  2000, '🏰'),
  ('ware_beirut',    'مستودع بيروت',   'beirut',   'warehouse', 80000,   800,  '🏭'),
  ('apt_amman',      'شقة في عمان',    'amman',    'apartment', 40000,   400,  '🏠'),
  ('villa_amman',    'فيلا في عمان',   'amman',    'villa',     170000,  1700, '🏰'),
  ('apt_damascus',   'شقة في دمشق',   'damascus', 'apartment', 35000,   350,  '🏠'),
  ('villa_damascus', 'فيلا في دمشق',  'damascus', 'villa',     150000,  1500, '🏰'),
  ('apt_cairo',      'شقة في القاهرة','cairo',    'apartment', 45000,   450,  '🏠'),
  ('villa_dubai',    'فيلا في دبي',   'dubai',    'villa',     500000,  5000, '🏰')
ON CONFLICT DO NOTHING;

INSERT INTO public.stocks VALUES
  ('bnk',  'بنك المدينة',             'BNK',  150, 2.5),
  ('oil',  'شركة النفط الوطنية',      'OIL',  280, -1.2),
  ('tech', 'تكنولوجيا المستقبل',      'TECH', 95,  5.1),
  ('arms', 'شركة الأسلحة الدفاعية',  'ARMS', 420, 0.8),
  ('real', 'العقارات الذهبية',        'REAL', 180, -0.5)
ON CONFLICT DO NOTHING;

-- =====================================================
-- وظائف قاعدة البيانات (منطق اللعبة)
-- =====================================================

-- التحقق من ارتقاء المستوى
CREATE OR REPLACE FUNCTION check_level_up(p_player_id UUID)
RETURNS VOID AS $$
DECLARE v_player players%ROWTYPE;
BEGIN
  SELECT * INTO v_player FROM players WHERE id = p_player_id;
  WHILE v_player.exp >= v_player.level * 100 LOOP
    UPDATE players
    SET exp = exp - (level * 100), level = level + 1,
        max_energy = max_energy + 10, max_willpower = max_willpower + 5,
        energy = LEAST(energy + 20, max_energy + 10)
    WHERE id = p_player_id;
    SELECT * INTO v_player FROM players WHERE id = p_player_id;
    INSERT INTO events (player_id, type, title, description)
    VALUES (p_player_id, 'level_up', '🎉 ارتقيت مستوى جديد!', 'وصلت إلى المستوى ' || v_player.level);
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- تجديد الطاقة
CREATE OR REPLACE FUNCTION regen_energy()
RETURNS VOID AS $$
DECLARE
  v_player players%ROWTYPE;
  v_hours FLOAT;
  v_eg INT; v_wg INT;
BEGIN
  SELECT * INTO v_player FROM players WHERE id = auth.uid() FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;
  v_hours := EXTRACT(EPOCH FROM (now() - v_player.last_energy_regen)) / 3600;
  v_eg := LEAST(FLOOR(v_hours * 10)::INT, v_player.max_energy - v_player.energy);
  v_wg := LEAST(FLOOR(v_hours * 2)::INT, v_player.max_willpower - v_player.willpower);
  IF v_eg > 0 OR v_wg > 0 THEN
    UPDATE players SET
      energy = LEAST(energy + v_eg, max_energy),
      willpower = LEAST(willpower + v_wg, max_willpower),
      last_energy_regen = now(), last_active = now()
    WHERE id = auth.uid();
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- تنفيذ جريمة
CREATE OR REPLACE FUNCTION perform_crime(p_crime_id TEXT)
RETURNS JSONB AS $$
DECLARE
  v_pid UUID := auth.uid();
  v_player players%ROWTYPE;
  v_crime crimes%ROWTYPE;
  v_jail_roll INT; v_hosp_roll INT;
  v_money INT;
BEGIN
  SELECT * INTO v_player FROM players WHERE id = v_pid FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'message','غير مصرح'); END IF;
  IF v_player.in_jail AND v_player.jail_until > now() THEN
    RETURN jsonb_build_object('success',false,'message','أنت في السجن!'); END IF;
  IF v_player.in_hospital AND v_player.hospital_until > now() THEN
    RETURN jsonb_build_object('success',false,'message','أنت في المشفى!'); END IF;
  SELECT * INTO v_crime FROM crimes WHERE id = p_crime_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'message','الجريمة غير موجودة'); END IF;
  IF v_player.level < v_crime.min_level THEN
    RETURN jsonb_build_object('success',false,'message','مستواك ' || v_player.level || ' غير كافٍ. تحتاج مستوى ' || v_crime.min_level); END IF;
  IF v_player.energy < v_crime.energy_cost THEN
    RETURN jsonb_build_object('success',false,'message','طاقتك غير كافية. تحتاج ' || v_crime.energy_cost); END IF;
  UPDATE players SET energy = energy - v_crime.energy_cost WHERE id = v_pid;
  v_jail_roll := floor(random() * 100)::INT;
  v_hosp_roll := floor(random() * 100)::INT;
  IF v_jail_roll < v_crime.jail_chance THEN
    UPDATE players SET in_jail=true, jail_until=now()+(v_crime.jail_time_minutes||' minutes')::INTERVAL WHERE id=v_pid;
    INSERT INTO events(player_id,type,title,description) VALUES(v_pid,'crime_jail','🚔 ألقي القبض عليك!','اعتُقلت أثناء '||v_crime.name||' وستبقى في السجن '||v_crime.jail_time_minutes||' دقيقة');
    RETURN jsonb_build_object('success',false,'outcome','jail','message','ألقت بك الشرطة في السجن لـ '||v_crime.jail_time_minutes||' دقيقة!');
  END IF;
  IF v_hosp_roll < v_crime.hospital_chance THEN
    UPDATE players SET in_hospital=true, hospital_until=now()+(v_crime.hospital_time_minutes||' minutes')::INTERVAL, health=GREATEST(health-floor(random()*30+10)::INT,10) WHERE id=v_pid;
    INSERT INTO events(player_id,type,title,description) VALUES(v_pid,'crime_hospital','🏥 أصبت بجروح!','تعرضت للإصابة أثناء '||v_crime.name);
    RETURN jsonb_build_object('success',false,'outcome','hospital','message','أصبت بجروح وأُدخلت المشفى!');
  END IF;
  v_money := floor(random()*(v_crime.base_money_max-v_crime.base_money_min)+v_crime.base_money_min)::INT;
  UPDATE players SET cash=cash+v_money, exp=exp+v_crime.base_exp WHERE id=v_pid;
  PERFORM check_level_up(v_pid);
  INSERT INTO events(player_id,type,title,description,money_change,exp_change) VALUES(v_pid,'crime_success','✅ جريمة ناجحة!','نجحت في '||v_crime.name||' وكسبت $'||v_money,v_money,v_crime.base_exp);
  RETURN jsonb_build_object('success',true,'outcome','success','money_earned',v_money,'exp_earned',v_crime.base_exp,'message','نجحت! ربحت $'||v_money);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- التدريب في النادي
CREATE OR REPLACE FUNCTION train_stat(p_stat TEXT, p_energy INT)
RETURNS JSONB AS $$
DECLARE
  v_pid UUID := auth.uid();
  v_player players%ROWTYPE;
  v_gain INT;
BEGIN
  SELECT * INTO v_player FROM players WHERE id = v_pid FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'message','غير مصرح'); END IF;
  IF v_player.in_jail AND v_player.jail_until > now() THEN RETURN jsonb_build_object('success',false,'message','أنت في السجن!'); END IF;
  IF v_player.in_hospital AND v_player.hospital_until > now() THEN RETURN jsonb_build_object('success',false,'message','أنت في المشفى!'); END IF;
  IF v_player.energy < p_energy THEN RETURN jsonb_build_object('success',false,'message','طاقتك غير كافية'); END IF;
  IF v_player.willpower < 1 THEN RETURN jsonb_build_object('success',false,'message','إرادتك منهكة، استرح أولاً'); END IF;
  IF p_energy < 1 THEN RETURN jsonb_build_object('success',false,'message','أدخل كمية طاقة صحيحة'); END IF;
  v_gain := GREATEST(FLOOR(p_energy::FLOAT / 10)::INT, 1);
  CASE p_stat
    WHEN 'strength'     THEN UPDATE players SET strength=strength+v_gain, energy=energy-p_energy, willpower=willpower-1 WHERE id=v_pid;
    WHEN 'fitness'      THEN UPDATE players SET fitness=fitness+v_gain, energy=energy-p_energy, willpower=willpower-1 WHERE id=v_pid;
    WHEN 'defense'      THEN UPDATE players SET defense=defense+v_gain, energy=energy-p_energy, willpower=willpower-1 WHERE id=v_pid;
    WHEN 'labor'        THEN UPDATE players SET labor=labor+v_gain, energy=energy-p_energy, willpower=willpower-1 WHERE id=v_pid;
    WHEN 'intelligence' THEN UPDATE players SET intelligence=intelligence+v_gain, energy=energy-p_energy, willpower=willpower-1 WHERE id=v_pid;
    ELSE RETURN jsonb_build_object('success',false,'message','صفة غير صحيحة');
  END CASE;
  INSERT INTO events(player_id,type,title,description,exp_change) VALUES(v_pid,'training','💪 تدريب ناجح!','تحسّنت '||p_stat||' بمقدار '||v_gain,v_gain*2);
  RETURN jsonb_build_object('success',true,'stat',p_stat,'gain',v_gain,'message','تحسّنت '||p_stat||' بمقدار '||v_gain||' نقطة');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- هجوم على لاعب
CREATE OR REPLACE FUNCTION attack_player(p_target_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_pid UUID := auth.uid();
  v_atk players%ROWTYPE;
  v_def players%ROWTYPE;
  v_atk_power INT; v_def_power INT;
  v_atk_roll INT; v_def_roll INT;
  v_stolen INT;
  v_wins BOOLEAN;
  v_wpn INT := 0; v_arm INT := 0;
BEGIN
  SELECT * INTO v_atk FROM players WHERE id = v_pid FOR UPDATE;
  SELECT * INTO v_def FROM players WHERE id = p_target_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'message','اللاعب غير موجود'); END IF;
  IF v_pid = p_target_id THEN RETURN jsonb_build_object('success',false,'message','لا يمكنك مهاجمة نفسك'); END IF;
  IF v_atk.in_jail OR v_atk.in_hospital THEN RETURN jsonb_build_object('success',false,'message','لا يمكنك القتال الآن'); END IF;
  IF v_atk.energy < 20 THEN RETURN jsonb_build_object('success',false,'message','تحتاج 20 طاقة للهجوم'); END IF;
  SELECT COALESCE(SUM(w.attack_bonus),0) INTO v_wpn FROM inventory i JOIN weapons w ON i.weapon_id=w.id WHERE i.player_id=v_pid AND i.equipped=true AND w.type!='armor';
  SELECT COALESCE(SUM(w.defense_bonus),0) INTO v_arm FROM inventory i JOIN weapons w ON i.weapon_id=w.id WHERE i.player_id=p_target_id AND i.equipped=true AND w.type='armor';
  v_atk_power := v_atk.strength + v_atk.level*2 + v_wpn;
  v_def_power := v_def.defense + v_def.level*2 + v_arm;
  v_atk_roll := floor(random()*v_atk_power*2+v_atk_power)::INT;
  v_def_roll := floor(random()*v_def_power*2+v_def_power)::INT;
  v_wins := v_atk_roll > v_def_roll;
  UPDATE players SET energy=energy-20 WHERE id=v_pid;
  IF v_wins THEN
    v_stolen := LEAST(floor(v_def.cash*0.1)::INT, 10000);
    v_stolen := GREATEST(v_stolen, 0);
    UPDATE players SET cash=cash-v_stolen, health=GREATEST(health-floor(random()*20+5)::INT,1) WHERE id=p_target_id;
    UPDATE players SET cash=cash+v_stolen, exp=exp+30 WHERE id=v_pid;
    PERFORM check_level_up(v_pid);
    IF (SELECT health FROM players WHERE id=p_target_id) <= 5 THEN
      UPDATE players SET in_hospital=true, hospital_until=now()+INTERVAL '30 minutes', health=50 WHERE id=p_target_id;
    END IF;
  ELSE
    UPDATE players SET health=GREATEST(health-floor(random()*15+5)::INT,1) WHERE id=v_pid;
    UPDATE players SET exp=exp+10 WHERE id=p_target_id;
  END IF;
  INSERT INTO attacks(attacker_id,defender_id,winner_id,attacker_name,defender_name,attacker_roll,defender_roll,money_stolen)
  VALUES(v_pid,p_target_id,CASE WHEN v_wins THEN v_pid ELSE p_target_id END,v_atk.username,v_def.username,v_atk_roll,v_def_roll,CASE WHEN v_wins THEN v_stolen ELSE 0 END);
  INSERT INTO events(player_id,type,title,description,money_change,exp_change) VALUES
    (v_pid,CASE WHEN v_wins THEN 'attack_win' ELSE 'attack_loss' END,
     CASE WHEN v_wins THEN '✅ انتصرت في المعركة!' ELSE '❌ خسرت المعركة!' END,
     CASE WHEN v_wins THEN 'هاجمت '||v_def.username||' وسرقت $'||v_stolen ELSE 'هاجمت '||v_def.username||' وخسرت' END,
     CASE WHEN v_wins THEN v_stolen ELSE 0 END,
     CASE WHEN v_wins THEN 30 ELSE 5 END),
    (p_target_id,CASE WHEN v_wins THEN 'defense_loss' ELSE 'defense_win' END,
     CASE WHEN v_wins THEN '⚔️ تعرضت لهجوم وخسرت!' ELSE '🛡️ تعرضت لهجوم وانتصرت!' END,
     CASE WHEN v_wins THEN v_atk.username||' هاجمك وسرق $'||v_stolen ELSE v_atk.username||' هاجمك وصددته' END,
     CASE WHEN v_wins THEN -v_stolen ELSE 0 END,
     CASE WHEN NOT v_wins THEN 10 ELSE 0 END);
  RETURN jsonb_build_object('success',true,'attacker_wins',v_wins,'attacker_roll',v_atk_roll,'defender_roll',v_def_roll,'money_stolen',v_stolen,'attacker_name',v_atk.username,'defender_name',v_def.username,'message',CASE WHEN v_wins THEN 'انتصرت وسرقت $'||v_stolen ELSE 'خسرت المعركة!' END);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- فتح حساب بنكي
CREATE OR REPLACE FUNCTION open_bank_account()
RETURNS JSONB AS $$
DECLARE v_pid UUID := auth.uid(); v_player players%ROWTYPE;
BEGIN
  SELECT * INTO v_player FROM players WHERE id=v_pid FOR UPDATE;
  IF v_player.has_bank_account THEN RETURN jsonb_build_object('success',false,'message','لديك حساب بنكي بالفعل'); END IF;
  IF v_player.cash < 15000 THEN RETURN jsonb_build_object('success',false,'message','تحتاج $15,000 لفتح حساب بنكي'); END IF;
  UPDATE players SET cash=cash-15000, has_bank_account=true WHERE id=v_pid;
  INSERT INTO events(player_id,type,title,description,money_change) VALUES(v_pid,'bank_open','🏦 فتح حساب بنكي','فتحت حساباً في بنك المدينة',-15000);
  RETURN jsonb_build_object('success',true,'message','تم فتح حسابك البنكي!');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- إيداع في البنك
CREATE OR REPLACE FUNCTION bank_deposit(p_amount INT)
RETURNS JSONB AS $$
DECLARE
  v_pid UUID := auth.uid();
  v_player players%ROWTYPE;
  v_fee INT; v_dep INT;
BEGIN
  SELECT * INTO v_player FROM players WHERE id=v_pid FOR UPDATE;
  IF NOT v_player.has_bank_account THEN RETURN jsonb_build_object('success',false,'message','لا يوجد لك حساب بنكي'); END IF;
  IF p_amount <= 0 THEN RETURN jsonb_build_object('success',false,'message','المبلغ غير صحيح'); END IF;
  IF v_player.cash < p_amount THEN RETURN jsonb_build_object('success',false,'message','رصيدك النقدي غير كافٍ'); END IF;
  v_fee := LEAST(floor(p_amount*0.15)::INT, 3000);
  v_dep := p_amount - v_fee;
  UPDATE players SET cash=cash-p_amount, bank_balance=bank_balance+v_dep WHERE id=v_pid;
  INSERT INTO events(player_id,type,title,description,money_change) VALUES(v_pid,'bank_deposit','💳 إيداع بنكي','أودعت $'||p_amount||' (رسوم: $'||v_fee||')',-p_amount);
  RETURN jsonb_build_object('success',true,'deposited',v_dep,'fee',v_fee,'message','تم الإيداع: $'||v_dep||' (رسوم البنك: $'||v_fee||')');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- سحب من البنك
CREATE OR REPLACE FUNCTION bank_withdraw(p_amount INT)
RETURNS JSONB AS $$
DECLARE v_pid UUID := auth.uid(); v_player players%ROWTYPE;
BEGIN
  SELECT * INTO v_player FROM players WHERE id=v_pid FOR UPDATE;
  IF NOT v_player.has_bank_account THEN RETURN jsonb_build_object('success',false,'message','لا يوجد لك حساب بنكي'); END IF;
  IF p_amount <= 0 THEN RETURN jsonb_build_object('success',false,'message','المبلغ غير صحيح'); END IF;
  IF v_player.bank_balance < p_amount THEN RETURN jsonb_build_object('success',false,'message','رصيدك في البنك غير كافٍ'); END IF;
  UPDATE players SET cash=cash+p_amount, bank_balance=bank_balance-p_amount WHERE id=v_pid;
  INSERT INTO events(player_id,type,title,description,money_change) VALUES(v_pid,'bank_withdraw','💸 سحب بنكي','سحبت $'||p_amount||' من البنك',p_amount);
  RETURN jsonb_build_object('success',true,'amount',p_amount,'message','تم السحب: $'||p_amount);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- فائدة البنك
CREATE OR REPLACE FUNCTION apply_bank_interest()
RETURNS JSONB AS $$
DECLARE
  v_pid UUID := auth.uid();
  v_player players%ROWTYPE;
  v_days FLOAT; v_interest INT;
BEGIN
  SELECT * INTO v_player FROM players WHERE id=v_pid FOR UPDATE;
  IF NOT v_player.has_bank_account OR v_player.bank_balance = 0 THEN RETURN jsonb_build_object('success',false); END IF;
  v_days := EXTRACT(EPOCH FROM (now() - v_player.bank_last_interest)) / 86400;
  IF v_days < 1 THEN RETURN jsonb_build_object('success',false,'days',v_days); END IF;
  v_interest := floor(v_player.bank_balance * 0.02 * floor(v_days))::INT;
  IF v_interest > 0 THEN
    UPDATE players SET bank_balance=bank_balance+v_interest, bank_last_interest=now() WHERE id=v_pid;
    INSERT INTO events(player_id,type,title,description,money_change) VALUES(v_pid,'bank_interest','📈 فائدة بنكية','حصلت على فائدة 2% يومياً: $'||v_interest,v_interest);
  END IF;
  RETURN jsonb_build_object('success',true,'interest',v_interest);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- التقدم لوظيفة
CREATE OR REPLACE FUNCTION apply_for_job(p_job_id TEXT)
RETURNS JSONB AS $$
DECLARE v_pid UUID := auth.uid(); v_player players%ROWTYPE; v_job jobs%ROWTYPE;
BEGIN
  SELECT * INTO v_player FROM players WHERE id=v_pid;
  SELECT * INTO v_job FROM jobs WHERE id=p_job_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'message','الوظيفة غير موجودة'); END IF;
  IF v_player.strength < v_job.strength_req THEN RETURN jsonb_build_object('success',false,'message','تحتاج قوة '||v_job.strength_req||' (لديك '||v_player.strength||')'); END IF;
  IF v_player.intelligence < v_job.intelligence_req THEN RETURN jsonb_build_object('success',false,'message','تحتاج ذكاء '||v_job.intelligence_req||' (لديك '||v_player.intelligence||')'); END IF;
  IF v_player.labor < v_job.labor_req THEN RETURN jsonb_build_object('success',false,'message','تحتاج عمالة '||v_job.labor_req||' (لديك '||v_player.labor||')'); END IF;
  UPDATE players SET job_id=p_job_id, job_level=1, last_salary=NULL WHERE id=v_pid;
  RETURN jsonb_build_object('success',true,'message','تم تعيينك في وظيفة '||v_job.name||'! 🎉');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- قبض الراتب
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
    IF v_hours < 24 THEN RETURN jsonb_build_object('success',false,'message','يمكنك قبض راتبك بعد '||ROUND(24-v_hours,1)||' ساعة','hours_left',24-v_hours); END IF;
  END IF;
  v_salary := v_job.base_salary * v_player.job_level;
  UPDATE players SET cash=cash+v_salary, exp=exp+v_job.exp_per_day, last_salary=now() WHERE id=v_pid;
  PERFORM check_level_up(v_pid);
  INSERT INTO events(player_id,type,title,description,money_change,exp_change) VALUES(v_pid,'salary','💰 راتب يومي','حصلت على راتبك من '||v_job.name,v_salary,v_job.exp_per_day);
  RETURN jsonb_build_object('success',true,'salary',v_salary,'message','حصلت على راتبك: $'||v_salary||' 💰');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- شراء سلاح
CREATE OR REPLACE FUNCTION buy_weapon(p_weapon_id UUID)
RETURNS JSONB AS $$
DECLARE v_pid UUID := auth.uid(); v_player players%ROWTYPE; v_weapon weapons%ROWTYPE;
BEGIN
  SELECT * INTO v_player FROM players WHERE id=v_pid FOR UPDATE;
  SELECT * INTO v_weapon FROM weapons WHERE id=p_weapon_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'message','السلاح غير موجود'); END IF;
  IF v_player.level < v_weapon.level_required THEN RETURN jsonb_build_object('success',false,'message','تحتاج مستوى '||v_weapon.level_required); END IF;
  IF v_player.cash < v_weapon.price THEN RETURN jsonb_build_object('success',false,'message','رصيدك غير كافٍ'); END IF;
  UPDATE players SET cash=cash-v_weapon.price WHERE id=v_pid;
  INSERT INTO inventory(player_id,weapon_id) VALUES(v_pid,p_weapon_id);
  INSERT INTO events(player_id,type,title,description,money_change) VALUES(v_pid,'buy_weapon','🔫 شراء سلاح','اشتريت '||v_weapon.name,-v_weapon.price);
  RETURN jsonb_build_object('success',true,'message','تم شراء '||v_weapon.name||' بنجاح!');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- تجهيز/خلع سلاح
CREATE OR REPLACE FUNCTION toggle_equip(p_inv_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_pid UUID := auth.uid();
  v_inv inventory%ROWTYPE;
  v_weapon weapons%ROWTYPE;
  v_new BOOLEAN;
BEGIN
  SELECT * INTO v_inv FROM inventory WHERE id=p_inv_id AND player_id=v_pid;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'message','العنصر غير موجود في مخزونك'); END IF;
  SELECT * INTO v_weapon FROM weapons WHERE id=v_inv.weapon_id;
  v_new := NOT v_inv.equipped;
  IF v_new AND v_weapon.type!='armor' THEN
    UPDATE inventory i SET equipped=false FROM weapons w WHERE i.weapon_id=w.id AND i.player_id=v_pid AND w.type!='armor' AND i.id!=p_inv_id;
  END IF;
  IF v_new AND v_weapon.type='armor' THEN
    UPDATE inventory i SET equipped=false FROM weapons w WHERE i.weapon_id=w.id AND i.player_id=v_pid AND w.type='armor' AND i.id!=p_inv_id;
  END IF;
  UPDATE inventory SET equipped=v_new WHERE id=p_inv_id;
  RETURN jsonb_build_object('success',true,'equipped',v_new,'message',CASE WHEN v_new THEN 'تم تجهيز '||v_weapon.name ELSE 'تم خلع '||v_weapon.name END);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- إنشاء عصابة
CREATE OR REPLACE FUNCTION create_gang(p_name TEXT, p_tag TEXT, p_desc TEXT)
RETURNS JSONB AS $$
DECLARE v_pid UUID := auth.uid(); v_player players%ROWTYPE; v_gid UUID;
BEGIN
  SELECT * INTO v_player FROM players WHERE id=v_pid FOR UPDATE;
  IF v_player.gang_id IS NOT NULL THEN RETURN jsonb_build_object('success',false,'message','أنت بالفعل عضو في عصابة'); END IF;
  IF v_player.cash < 50000 THEN RETURN jsonb_build_object('success',false,'message','تحتاج $50,000 لإنشاء عصابة'); END IF;
  IF length(p_name)<3 THEN RETURN jsonb_build_object('success',false,'message','اسم العصابة قصير جداً'); END IF;
  INSERT INTO gangs(name,tag,description,leader_id,city) VALUES(p_name,upper(p_tag),p_desc,v_pid,v_player.city) RETURNING id INTO v_gid;
  UPDATE players SET cash=cash-50000, gang_id=v_gid WHERE id=v_pid;
  INSERT INTO gang_members(gang_id,player_id,role) VALUES(v_gid,v_pid,'leader');
  RETURN jsonb_build_object('success',true,'gang_id',v_gid,'message','تم إنشاء عصابة '||p_name||' بنجاح! 🎉');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- الانضمام لعصابة
CREATE OR REPLACE FUNCTION join_gang(p_gang_id UUID)
RETURNS JSONB AS $$
DECLARE v_pid UUID := auth.uid(); v_player players%ROWTYPE; v_gang gangs%ROWTYPE; v_cnt INT;
BEGIN
  SELECT * INTO v_player FROM players WHERE id=v_pid FOR UPDATE;
  SELECT * INTO v_gang FROM gangs WHERE id=p_gang_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'message','العصابة غير موجودة'); END IF;
  IF v_player.gang_id IS NOT NULL THEN RETURN jsonb_build_object('success',false,'message','أنت بالفعل عضو في عصابة'); END IF;
  SELECT COUNT(*) INTO v_cnt FROM gang_members WHERE gang_id=p_gang_id;
  IF v_cnt >= v_gang.max_members THEN RETURN jsonb_build_object('success',false,'message','العصابة ممتلئة'); END IF;
  UPDATE players SET gang_id=p_gang_id WHERE id=v_pid;
  INSERT INTO gang_members(gang_id,player_id,role) VALUES(p_gang_id,v_pid,'member');
  RETURN jsonb_build_object('success',true,'message','انضممت لعصابة '||v_gang.name||'! 🤝');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- مغادرة العصابة
CREATE OR REPLACE FUNCTION leave_gang()
RETURNS JSONB AS $$
DECLARE v_pid UUID := auth.uid(); v_player players%ROWTYPE; v_gang gangs%ROWTYPE;
BEGIN
  SELECT * INTO v_player FROM players WHERE id=v_pid FOR UPDATE;
  IF v_player.gang_id IS NULL THEN RETURN jsonb_build_object('success',false,'message','لست عضواً في أي عصابة'); END IF;
  SELECT * INTO v_gang FROM gangs WHERE id=v_player.gang_id;
  IF v_gang.leader_id=v_pid THEN RETURN jsonb_build_object('success',false,'message','القائد لا يمكنه المغادرة. انقل القيادة أو حلّ العصابة أولاً'); END IF;
  DELETE FROM gang_members WHERE gang_id=v_player.gang_id AND player_id=v_pid;
  UPDATE players SET gang_id=NULL WHERE id=v_pid;
  RETURN jsonb_build_object('success',true,'message','غادرت عصابة '||v_gang.name);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- إرسال رسالة
CREATE OR REPLACE FUNCTION send_message(p_to TEXT, p_subject TEXT, p_body TEXT)
RETURNS JSONB AS $$
DECLARE v_pid UUID := auth.uid(); v_tid UUID; v_from_name TEXT;
BEGIN
  SELECT id INTO v_tid FROM players WHERE username=p_to;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'message','اللاعب غير موجود'); END IF;
  IF v_pid=v_tid THEN RETURN jsonb_build_object('success',false,'message','لا يمكنك مراسلة نفسك'); END IF;
  SELECT username INTO v_from_name FROM players WHERE id=v_pid;
  INSERT INTO messages(from_id,to_id,from_name,subject,body) VALUES(v_pid,v_tid,v_from_name,p_subject,p_body);
  RETURN jsonb_build_object('success',true,'message','تم إرسال الرسالة! ✉️');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- السفر لمدينة
CREATE OR REPLACE FUNCTION travel_to_city(p_city TEXT)
RETURNS JSONB AS $$
DECLARE v_pid UUID := auth.uid(); v_player players%ROWTYPE;
BEGIN
  SELECT * INTO v_player FROM players WHERE id=v_pid FOR UPDATE;
  IF v_player.city=p_city THEN RETURN jsonb_build_object('success',false,'message','أنت بالفعل في هذه المدينة'); END IF;
  IF NOT (p_city IN ('beirut','amman','damascus','cairo','dubai')) THEN RETURN jsonb_build_object('success',false,'message','مدينة غير صالحة'); END IF;
  IF v_player.cash < 2000 THEN RETURN jsonb_build_object('success',false,'message','تحتاج $2,000 للسفر'); END IF;
  UPDATE players SET city=p_city, cash=cash-2000 WHERE id=v_pid;
  RETURN jsonb_build_object('success',true,'city',p_city,'message','وصلت إلى المدينة الجديدة! ✈️');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- نقاط مقابل مال
CREATE OR REPLACE FUNCTION spend_points(p_action TEXT, p_amount INT)
RETURNS JSONB AS $$
DECLARE v_pid UUID := auth.uid(); v_player players%ROWTYPE; v_cost INT;
BEGIN
  SELECT * INTO v_player FROM players WHERE id=v_pid FOR UPDATE;
  CASE p_action
    WHEN 'energy' THEN v_cost := p_amount;
      IF v_player.points < v_cost THEN RETURN jsonb_build_object('success',false,'message','نقاطك غير كافية'); END IF;
      UPDATE players SET points=points-v_cost, energy=LEAST(energy+p_amount*10,max_energy) WHERE id=v_pid;
      RETURN jsonb_build_object('success',true,'message','تم تعبئة '||(p_amount*10)||' طاقة');
    WHEN 'cash' THEN v_cost := p_amount;
      IF v_player.points < v_cost THEN RETURN jsonb_build_object('success',false,'message','نقاطك غير كافية'); END IF;
      UPDATE players SET points=points-v_cost, cash=cash+p_amount*1000 WHERE id=v_pid;
      RETURN jsonb_build_object('success',true,'message','حصلت على $'||(p_amount*1000));
    ELSE RETURN jsonb_build_object('success',false,'message','إجراء غير صحيح');
  END CASE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- Row Level Security
-- =====================================================
ALTER TABLE players ENABLE ROW LEVEL SECURITY;
ALTER TABLE gangs ENABLE ROW LEVEL SECURITY;
ALTER TABLE gang_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE market ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE events ENABLE ROW LEVEL SECURITY;
ALTER TABLE attacks ENABLE ROW LEVEL SECURITY;
ALTER TABLE player_courses ENABLE ROW LEVEL SECURITY;
ALTER TABLE player_properties ENABLE ROW LEVEL SECURITY;
ALTER TABLE player_stocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE weapons ENABLE ROW LEVEL SECURITY;
ALTER TABLE crimes ENABLE ROW LEVEL SECURITY;
ALTER TABLE jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE courses ENABLE ROW LEVEL SECURITY;
ALTER TABLE properties ENABLE ROW LEVEL SECURITY;
ALTER TABLE stocks ENABLE ROW LEVEL SECURITY;

-- سياسات الأمن
DROP POLICY IF EXISTS "p_sel" ON players;
CREATE POLICY "p_sel" ON players FOR SELECT USING (true);
DROP POLICY IF EXISTS "p_ins" ON players;
CREATE POLICY "p_ins" ON players FOR INSERT WITH CHECK (auth.uid()=id);
DROP POLICY IF EXISTS "p_upd" ON players;
CREATE POLICY "p_upd" ON players FOR UPDATE USING (auth.uid()=id);

DROP POLICY IF EXISTS "g_sel" ON gangs;
CREATE POLICY "g_sel" ON gangs FOR SELECT USING (true);
DROP POLICY IF EXISTS "g_ins" ON gangs;
CREATE POLICY "g_ins" ON gangs FOR INSERT WITH CHECK (true);
DROP POLICY IF EXISTS "g_upd" ON gangs;
CREATE POLICY "g_upd" ON gangs FOR UPDATE USING (auth.uid()=leader_id);

DROP POLICY IF EXISTS "gm_sel" ON gang_members;
CREATE POLICY "gm_sel" ON gang_members FOR SELECT USING (true);
DROP POLICY IF EXISTS "gm_ins" ON gang_members;
CREATE POLICY "gm_ins" ON gang_members FOR INSERT WITH CHECK (true);
DROP POLICY IF EXISTS "gm_del" ON gang_members;
CREATE POLICY "gm_del" ON gang_members FOR DELETE USING (true);

DROP POLICY IF EXISTS "inv_sel" ON inventory;
CREATE POLICY "inv_sel" ON inventory FOR SELECT USING (auth.uid()=player_id);
DROP POLICY IF EXISTS "inv_ins" ON inventory;
CREATE POLICY "inv_ins" ON inventory FOR INSERT WITH CHECK (auth.uid()=player_id);
DROP POLICY IF EXISTS "inv_upd" ON inventory;
CREATE POLICY "inv_upd" ON inventory FOR UPDATE USING (auth.uid()=player_id);

DROP POLICY IF EXISTS "mkt_sel" ON market;
CREATE POLICY "mkt_sel" ON market FOR SELECT USING (true);
DROP POLICY IF EXISTS "mkt_ins" ON market;
CREATE POLICY "mkt_ins" ON market FOR INSERT WITH CHECK (true);
DROP POLICY IF EXISTS "mkt_del" ON market;
CREATE POLICY "mkt_del" ON market FOR DELETE USING (auth.uid()=seller_id);

DROP POLICY IF EXISTS "msg_sel" ON messages;
CREATE POLICY "msg_sel" ON messages FOR SELECT USING (auth.uid()=from_id OR auth.uid()=to_id);
DROP POLICY IF EXISTS "msg_ins" ON messages;
CREATE POLICY "msg_ins" ON messages FOR INSERT WITH CHECK (true);
DROP POLICY IF EXISTS "msg_upd" ON messages;
CREATE POLICY "msg_upd" ON messages FOR UPDATE USING (auth.uid()=to_id);

DROP POLICY IF EXISTS "evt_sel" ON events;
CREATE POLICY "evt_sel" ON events FOR SELECT USING (auth.uid()=player_id);
DROP POLICY IF EXISTS "atk_sel" ON attacks;
CREATE POLICY "atk_sel" ON attacks FOR SELECT USING (auth.uid()=attacker_id OR auth.uid()=defender_id);
DROP POLICY IF EXISTS "pc_sel" ON player_courses;
CREATE POLICY "pc_sel" ON player_courses FOR SELECT USING (auth.uid()=player_id);
DROP POLICY IF EXISTS "pp_sel" ON player_properties;
CREATE POLICY "pp_sel" ON player_properties FOR SELECT USING (auth.uid()=player_id);
DROP POLICY IF EXISTS "ps_sel" ON player_stocks;
CREATE POLICY "ps_sel" ON player_stocks FOR SELECT USING (auth.uid()=player_id);

DROP POLICY IF EXISTS "wpn_sel" ON weapons;
CREATE POLICY "wpn_sel" ON weapons FOR SELECT USING (true);
DROP POLICY IF EXISTS "crm_sel" ON crimes;
CREATE POLICY "crm_sel" ON crimes FOR SELECT USING (true);
DROP POLICY IF EXISTS "job_sel" ON jobs;
CREATE POLICY "job_sel" ON jobs FOR SELECT USING (true);
DROP POLICY IF EXISTS "crs_sel" ON courses;
CREATE POLICY "crs_sel" ON courses FOR SELECT USING (true);
DROP POLICY IF EXISTS "prp_sel" ON properties;
CREATE POLICY "prp_sel" ON properties FOR SELECT USING (true);
DROP POLICY IF EXISTS "stk_sel" ON stocks;
CREATE POLICY "stk_sel" ON stocks FOR SELECT USING (true);

-- =====================================================
-- Trigger: إنشاء ملف اللاعب عند التسجيل
-- =====================================================
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.players (id, username)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'username', split_part(NEW.email,'@',1)))
  ON CONFLICT DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();
