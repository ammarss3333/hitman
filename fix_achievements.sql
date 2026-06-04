-- =====================================================
-- نظام الإنجازات – Achievement System
-- =====================================================

-- إضافة أعمدة التتبع التراكمي إلى جدول اللاعبين
ALTER TABLE public.players
  ADD COLUMN IF NOT EXISTS total_crimes          INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS total_attacks_won     INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS total_trains          INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS total_messages        INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS total_contracts_won   INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS total_cash_earned     INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS max_single_crime_cash INTEGER DEFAULT 0;

-- جدول الإنجازات
CREATE TABLE IF NOT EXISTS public.achievements (
  id              TEXT PRIMARY KEY,
  name            TEXT NOT NULL,
  description     TEXT,
  icon            TEXT DEFAULT '🏆',
  category        TEXT DEFAULT 'general', -- combat/crime/social/wealth/progression
  reward_cash     INTEGER DEFAULT 0,
  reward_stat     TEXT,    -- strength/fitness/defense/intelligence/labor or NULL
  reward_stat_val INTEGER  DEFAULT 0,
  rarity          TEXT DEFAULT 'common', -- common/rare/epic/legendary
  secret          BOOLEAN DEFAULT false  -- مخفي حتى الفتح
);

-- جدول إنجازات اللاعب
CREATE TABLE IF NOT EXISTS public.player_achievements (
  player_id      UUID REFERENCES public.players(id) ON DELETE CASCADE,
  achievement_id TEXT REFERENCES public.achievements(id),
  unlocked_at    TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (player_id, achievement_id)
);

-- =====================================================
-- سياسات أمان الصفوف (RLS)
-- =====================================================
ALTER TABLE public.achievements        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.player_achievements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ach_sel"  ON public.achievements;
CREATE POLICY "ach_sel" ON public.achievements FOR SELECT USING (true);

DROP POLICY IF EXISTS "pach_sel" ON public.player_achievements;
CREATE POLICY "pach_sel" ON public.player_achievements FOR SELECT
  USING (player_id = auth.uid());

DROP POLICY IF EXISTS "pach_ins" ON public.player_achievements;
CREATE POLICY "pach_ins" ON public.player_achievements FOR INSERT
  WITH CHECK (false); -- الإدراج فقط عبر الـ RPC (SECURITY DEFINER)

-- =====================================================
-- بيانات الإنجازات (30+ إنجاز)
-- =====================================================
INSERT INTO public.achievements
  (id, name, description, icon, category, reward_cash, reward_stat, reward_stat_val, rarity, secret)
VALUES

-- ── قتال (Combat) ─────────────────────────────────
('first_blood',     'أول دم',                 'نجح أول هجوم لك على لاعب آخر',                   '🔫', 'combat', 500,   NULL,           0, 'common',    false),
('serial_killer',   'القاتل المتسلسل',         'حقق 10 انتصارات في المعارك',                      '🔫', 'combat', 2000,  NULL,           0, 'rare',      false),
('unstoppable',     'لا يُوقف',                'حقق 25 انتصاراً في المعارك',                      '🔫', 'combat', 5000,  'strength',     2, 'epic',      false),
('ghost',           'الشبح',                   'حقق 50 انتصاراً في المعارك',                      '🔫', 'combat', 15000, 'strength',     5, 'legendary', false),
('sniper_elite',    'النخبة',                  'فز بـ5 عقود اغتيال',                             '🎯', 'combat', 3000,  'fitness',      1, 'rare',      false),
('war_machine',     'آلة الحرب',               'حقق 100 انتصار في المعارك',                       '⚔️', 'combat', 25000, 'strength',     8, 'legendary', false),
('silent_assassin', 'الاغتيال الصامت',         'أنهِ 10 عقود اغتيال',                            '🕵️', 'combat', 8000,  'defense',      2, 'epic',      true),

-- ── جرائم (Crime) ─────────────────────────────────
('petty_thief',     'اللص الصغير',             'ارتكب 5 جرائم',                                   '🦹', 'crime',  300,   NULL,           0, 'common',    false),
('night_stalker',   'صياد الليل',              'ارتكب 20 جريمة',                                  '🦹', 'crime',  1000,  NULL,           0, 'common',    false),
('professional',    'المحترف',                 'ارتكب 50 جريمة',                                  '🦹', 'crime',  2500,  NULL,           0, 'rare',      false),
('crime_streak',    'سلسلة الجرائم',           'ارتكب 100 جريمة',                                 '🦹', 'crime',  8000,  'intelligence', 1, 'epic',      false),
('crime_lord',      'سيد الجريمة',             'ارتكب 200 جريمة',                                 '🦹', 'crime',  20000, 'intelligence', 3, 'legendary', false),
('heist_master',    'سيد السطو',               'اسرق أكثر من $5,000 في جريمة واحدة',             '🦹', 'crime',  5000,  NULL,           0, 'epic',      false),

-- ── ثروة (Wealth) ─────────────────────────────────
('penny_pincher',   'التاجر',                  'اجمع $100,000 إجمالاً',                           '💰', 'wealth', 2000,  NULL,           0, 'common',    false),
('first_million',   'المليونير',               'اجمع مليون دولار إجمالاً من الجرائم',             '💰', 'wealth', 10000, NULL,           0, 'epic',      false),
('tycoon',          'المغناط',                 'اجمع 5 مليون دولار إجمالاً',                      '💰', 'wealth', 50000, 'intelligence', 3, 'legendary', false),
('banker',          'المصرفي',                 'ادخر $500,000 في البنك',                          '💰', 'wealth', 3000,  NULL,           0, 'rare',      false),
('big_spender',     'المُبذّر',                'اشتر سلاحاً بـ$50,000 أو أكثر (رصيد نقدي)',      '💰', 'wealth', 5000,  NULL,           0, 'rare',      false),

-- ── تطور (Progression) ────────────────────────────
('level3',          'المبتدئ',                 'وصل مستوى 3',                                     '⭐', 'progression', 300,   NULL,       0, 'common',    false),
('level5',          'المحارب',                 'وصل مستوى 5',                                     '⭐', 'progression', 1000,  NULL,       0, 'common',    false),
('level10',         'القاتل المأجور',          'وصل مستوى 10',                                    '⭐', 'progression', 5000,  NULL,       0, 'rare',      false),
('level15',         'المحترف المتمرس',         'وصل مستوى 15',                                    '⭐', 'progression', 15000, 'defense',  3, 'epic',      false),
('level20',         'الأسطورة',                'وصل مستوى 20',                                    '⭐', 'progression', 30000, 'strength', 5, 'legendary', false),
('iron_will',       'إرادة فولاذية',           'تدرّب 50 مرة في النادي الرياضي',                 '💪', 'progression', 1500,  'fitness',  1, 'common',    false),
('gym_rat',         'هاوي الرياضة',            'تدرّب 100 مرة في النادي الرياضي',                '💪', 'progression', 3000,  'fitness',  3, 'rare',      false),
('titan',           'الجبار',                  'تدرّب 250 مرة في النادي الرياضي',                '💪', 'progression', 10000, 'fitness',  5, 'epic',      false),

-- ── اجتماعي (Social) ──────────────────────────────
('gang_member',     'عضو العصابة',             'انضم إلى عصابة',                                  '👥', 'social', 500,   NULL,           0, 'common',    false),
('gang_leader',     'قائد العصابة',            'أسّس عصابة خاصة بك',                             '👥', 'social', 2000,  NULL,           0, 'rare',      false),
('pen_pal',         'المراسل',                 'أرسل 20 رسالة إلى لاعبين آخرين',                  '✉️', 'social', 500,   NULL,           0, 'common',    false),
('networker',       'المتواصل',                'أرسل 50 رسالة إلى لاعبين آخرين',                  '✉️', 'social', 1500,  NULL,           0, 'rare',      false),
('lucky_devil',     'حظ الشيطان',              'إنجاز سري — اكشفه بنفسك',                        '🎰', 'social', 5000,  NULL,           0, 'rare',      true)

ON CONFLICT (id) DO UPDATE SET
  name            = EXCLUDED.name,
  description     = EXCLUDED.description,
  icon            = EXCLUDED.icon,
  category        = EXCLUDED.category,
  reward_cash     = EXCLUDED.reward_cash,
  reward_stat     = EXCLUDED.reward_stat,
  reward_stat_val = EXCLUDED.reward_stat_val,
  rarity          = EXCLUDED.rarity,
  secret          = EXCLUDED.secret;

-- =====================================================
-- RPC: check_achievements
-- =====================================================
CREATE OR REPLACE FUNCTION public.check_achievements(p_player_id UUID DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pid    UUID := COALESCE(p_player_id, auth.uid());
  v_player players%ROWTYPE;
  v_ach    achievements%ROWTYPE;
  v_newly  JSONB := '[]'::JSONB;
BEGIN
  IF v_pid IS NULL THEN RETURN '[]'; END IF;
  SELECT * INTO v_player FROM players WHERE id = v_pid;
  IF NOT FOUND THEN RETURN '[]'; END IF;

  FOR v_ach IN
    SELECT a.* FROM achievements a
    WHERE NOT EXISTS (
      SELECT 1 FROM player_achievements pa
      WHERE pa.player_id = v_pid AND pa.achievement_id = a.id
    )
  LOOP
    IF (
      -- قتال
      (v_ach.id = 'first_blood'     AND v_player.total_attacks_won  >= 1)   OR
      (v_ach.id = 'serial_killer'   AND v_player.total_attacks_won  >= 10)  OR
      (v_ach.id = 'unstoppable'     AND v_player.total_attacks_won  >= 25)  OR
      (v_ach.id = 'ghost'           AND v_player.total_attacks_won  >= 50)  OR
      (v_ach.id = 'war_machine'     AND v_player.total_attacks_won  >= 100) OR
      (v_ach.id = 'sniper_elite'    AND v_player.total_contracts_won >= 5)  OR
      (v_ach.id = 'silent_assassin' AND v_player.total_contracts_won >= 10) OR
      -- جرائم
      (v_ach.id = 'petty_thief'     AND v_player.total_crimes >= 5)   OR
      (v_ach.id = 'night_stalker'   AND v_player.total_crimes >= 20)  OR
      (v_ach.id = 'professional'    AND v_player.total_crimes >= 50)  OR
      (v_ach.id = 'crime_streak'    AND v_player.total_crimes >= 100) OR
      (v_ach.id = 'crime_lord'      AND v_player.total_crimes >= 200) OR
      (v_ach.id = 'heist_master'    AND v_player.max_single_crime_cash > 5000) OR
      -- ثروة
      (v_ach.id = 'penny_pincher'   AND v_player.total_cash_earned >= 100000)   OR
      (v_ach.id = 'first_million'   AND v_player.total_cash_earned >= 1000000)  OR
      (v_ach.id = 'tycoon'          AND v_player.total_cash_earned >= 5000000)  OR
      (v_ach.id = 'banker'          AND v_player.bank_balance      >= 500000)   OR
      (v_ach.id = 'big_spender'     AND v_player.cash              >= 50000)    OR
      -- تطور
      (v_ach.id = 'level3'          AND v_player.level >= 3)   OR
      (v_ach.id = 'level5'          AND v_player.level >= 5)   OR
      (v_ach.id = 'level10'         AND v_player.level >= 10)  OR
      (v_ach.id = 'level15'         AND v_player.level >= 15)  OR
      (v_ach.id = 'level20'         AND v_player.level >= 20)  OR
      (v_ach.id = 'iron_will'       AND v_player.total_trains >= 50)  OR
      (v_ach.id = 'gym_rat'         AND v_player.total_trains >= 100) OR
      (v_ach.id = 'titan'           AND v_player.total_trains >= 250) OR
      -- اجتماعي
      (v_ach.id = 'gang_member'     AND v_player.gang_id IS NOT NULL) OR
      (v_ach.id = 'gang_leader'     AND EXISTS (SELECT 1 FROM gangs WHERE leader_id = v_pid)) OR
      (v_ach.id = 'pen_pal'         AND v_player.total_messages >= 20) OR
      (v_ach.id = 'networker'       AND v_player.total_messages >= 50)
    ) THEN
      INSERT INTO player_achievements (player_id, achievement_id)
      VALUES (v_pid, v_ach.id)
      ON CONFLICT DO NOTHING;

      IF v_ach.reward_cash > 0 THEN
        UPDATE players SET cash = cash + v_ach.reward_cash WHERE id = v_pid;
      END IF;

      IF v_ach.reward_stat IS NOT NULL AND v_ach.reward_stat_val > 0 THEN
        CASE v_ach.reward_stat
          WHEN 'strength'     THEN UPDATE players SET strength     = strength     + v_ach.reward_stat_val WHERE id = v_pid;
          WHEN 'fitness'      THEN UPDATE players SET fitness      = fitness      + v_ach.reward_stat_val WHERE id = v_pid;
          WHEN 'defense'      THEN UPDATE players SET defense      = defense      + v_ach.reward_stat_val WHERE id = v_pid;
          WHEN 'intelligence' THEN UPDATE players SET intelligence = intelligence + v_ach.reward_stat_val WHERE id = v_pid;
          WHEN 'labor'        THEN UPDATE players SET labor        = labor        + v_ach.reward_stat_val WHERE id = v_pid;
          ELSE NULL;
        END CASE;
      END IF;

      INSERT INTO events (player_id, type, title, description, money_change)
      VALUES (
        v_pid,
        'achievement',
        v_ach.icon || ' إنجاز جديد: ' || v_ach.name,
        COALESCE(v_ach.description, '') ||
          CASE WHEN v_ach.reward_cash > 0 THEN ' (+$' || v_ach.reward_cash || ')' ELSE '' END,
        v_ach.reward_cash
      );

      v_newly := v_newly || jsonb_build_array(v_ach.id);
    END IF;
  END LOOP;

  RETURN v_newly;
END;
$$;

-- =====================================================
-- RPC: get_player_achievements
-- =====================================================
CREATE OR REPLACE FUNCTION public.get_player_achievements(p_player_id UUID DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pid   UUID := COALESCE(p_player_id, auth.uid());
  v_result JSONB;
BEGIN
  IF v_pid IS NULL THEN RETURN '{}'::JSONB; END IF;

  SELECT jsonb_build_object(
    'total_count',  COUNT(a.id),
    'earned_count', COUNT(pa.achievement_id),
    'total_cash',   COALESCE(SUM(a.reward_cash) FILTER (WHERE pa.achievement_id IS NOT NULL), 0),
    'achievements', jsonb_agg(
      jsonb_build_object(
        'id',              a.id,
        'name',            a.name,
        'description',     a.description,
        'icon',            a.icon,
        'category',        a.category,
        'reward_cash',     a.reward_cash,
        'reward_stat',     a.reward_stat,
        'reward_stat_val', a.reward_stat_val,
        'rarity',          a.rarity,
        'secret',          a.secret,
        'earned',          (pa.achievement_id IS NOT NULL),
        'unlocked_at',     pa.unlocked_at
      ) ORDER BY
        CASE WHEN pa.achievement_id IS NOT NULL THEN 0 ELSE 1 END,
        CASE a.rarity WHEN 'legendary' THEN 1 WHEN 'epic' THEN 2 WHEN 'rare' THEN 3 ELSE 4 END,
        a.id
    )
  ) INTO v_result
  FROM achievements a
  LEFT JOIN player_achievements pa
         ON pa.achievement_id = a.id AND pa.player_id = v_pid;

  RETURN v_result;
END;
$$;

-- =====================================================
-- Trigger: after_player_update → check_achievements
-- =====================================================
CREATE OR REPLACE FUNCTION public.trigger_check_achievements()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF (NEW.level                IS DISTINCT FROM OLD.level)                OR
     (NEW.total_crimes         IS DISTINCT FROM OLD.total_crimes)         OR
     (NEW.total_attacks_won    IS DISTINCT FROM OLD.total_attacks_won)    OR
     (NEW.total_contracts_won  IS DISTINCT FROM OLD.total_contracts_won)  OR
     (NEW.total_trains         IS DISTINCT FROM OLD.total_trains)         OR
     (NEW.total_messages       IS DISTINCT FROM OLD.total_messages)       OR
     (NEW.total_cash_earned    IS DISTINCT FROM OLD.total_cash_earned)    OR
     (NEW.max_single_crime_cash IS DISTINCT FROM OLD.max_single_crime_cash) OR
     (NEW.bank_balance         IS DISTINCT FROM OLD.bank_balance)         OR
     (NEW.gang_id              IS DISTINCT FROM OLD.gang_id)
  THEN
    PERFORM check_achievements(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS after_player_update ON public.players;
CREATE TRIGGER after_player_update
  AFTER UPDATE ON public.players
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_check_achievements();

-- =====================================================
-- تحديث الدوال الموجودة لتتبع الإحصائيات التراكمية
-- =====================================================

-- do_crime: يتتبع total_crimes, total_cash_earned, max_single_crime_cash
CREATE OR REPLACE FUNCTION public.do_crime(p_crime_id TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pid    UUID := auth.uid();
  v_player players%ROWTYPE;
  v_crime  crimes%ROWTYPE;
  v_roll   INTEGER;
  v_money  INTEGER;
BEGIN
  SELECT * INTO v_player FROM players WHERE id = v_pid;
  SELECT * INTO v_crime  FROM crimes  WHERE id = p_crime_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'message','الجريمة غير موجودة'); END IF;
  IF v_player.in_jail AND v_player.jail_until > now()
    THEN RETURN jsonb_build_object('success',false,'message','أنت في السجن!'); END IF;
  IF v_player.in_hospital AND v_player.hospital_until > now()
    THEN RETURN jsonb_build_object('success',false,'message','أنت في المشفى!'); END IF;
  IF v_player.energy < v_crime.energy_cost
    THEN RETURN jsonb_build_object('success',false,'message','طاقتك غير كافية. تحتاج '||v_crime.energy_cost||' طاقة'); END IF;
  IF v_player.level < v_crime.min_level
    THEN RETURN jsonb_build_object('success',false,'message','مستواك '||v_player.level||' غير كافٍ. تحتاج مستوى '||v_crime.min_level); END IF;

  UPDATE players SET energy = energy - v_crime.energy_cost WHERE id = v_pid;
  v_roll := floor(random() * 100 + 1);

  IF v_roll <= v_crime.success_rate THEN
    v_money := floor(random()*(v_crime.max_cash - v_crime.min_cash + 1) + v_crime.min_cash);
    UPDATE players SET
      cash                  = cash + v_money,
      exp                   = exp  + v_crime.base_exp,
      total_crimes          = total_crimes + 1,
      total_cash_earned     = total_cash_earned + v_money,
      max_single_crime_cash = GREATEST(max_single_crime_cash, v_money)
    WHERE id = v_pid;
    PERFORM check_level_up(v_pid);
    INSERT INTO events(player_id,type,title,description,money_change,exp_change)
    VALUES(v_pid,'crime_success','✅ جريمة ناجحة!','نجحت في '||v_crime.name||' وكسبت $'||v_money,v_money,v_crime.base_exp);
    RETURN jsonb_build_object('success',true,'message','نجحت في '||v_crime.name||'! كسبت $'||v_money,'money',v_money);

  ELSIF v_roll <= v_crime.success_rate + v_crime.jail_chance THEN
    UPDATE players SET
      in_jail      = true,
      jail_until   = now() + (v_crime.jail_time_minutes || ' minutes')::INTERVAL,
      total_crimes = total_crimes + 1
    WHERE id = v_pid;
    INSERT INTO events(player_id,type,title,description)
    VALUES(v_pid,'crime_jail','🚔 ألقي القبض عليك!','اعتُقلت أثناء '||v_crime.name||' وستبقى في السجن '||v_crime.jail_time_minutes||' دقيقة');
    RETURN jsonb_build_object('success',false,'message','ألقي القبض عليك! ستبقى في السجن '||v_crime.jail_time_minutes||' دقيقة','jailed',true);

  ELSE
    UPDATE players SET
      in_hospital    = true,
      hospital_until = now() + '10 minutes'::INTERVAL,
      health         = GREATEST(health - 20, 1),
      total_crimes   = total_crimes + 1
    WHERE id = v_pid;
    INSERT INTO events(player_id,type,title,description)
    VALUES(v_pid,'crime_hospital','🏥 أصبت بجروح!','تعرضت للإصابة أثناء '||v_crime.name);
    RETURN jsonb_build_object('success',false,'message','تعرضت للإصابة وأُنقلت للمشفى!','hospitalized',true);
  END IF;
END;
$$;

-- train: يتتبع total_trains
CREATE OR REPLACE FUNCTION public.train(p_stat TEXT, p_intensity TEXT DEFAULT 'normal')
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pid    UUID := auth.uid();
  v_player players%ROWTYPE;
  v_cost   INTEGER := CASE p_intensity WHEN 'hard' THEN 30 ELSE 20 END;
  v_gain   INTEGER := CASE p_intensity WHEN 'hard' THEN floor(random()*3+2)::INT ELSE floor(random()*2+1)::INT END;
BEGIN
  SELECT * INTO v_player FROM players WHERE id = v_pid;
  IF v_player.energy < v_cost THEN RETURN jsonb_build_object('success',false,'message','طاقتك غير كافية'); END IF;
  IF p_stat NOT IN ('strength','fitness','defense','intelligence','labor')
    THEN RETURN jsonb_build_object('success',false,'message','إحصائية غير صالحة'); END IF;

  UPDATE players SET energy = energy - v_cost, total_trains = total_trains + 1 WHERE id = v_pid;

  CASE p_stat
    WHEN 'strength'     THEN UPDATE players SET strength     = strength     + v_gain WHERE id = v_pid;
    WHEN 'fitness'      THEN UPDATE players SET fitness      = fitness      + v_gain WHERE id = v_pid;
    WHEN 'defense'      THEN UPDATE players SET defense      = defense      + v_gain WHERE id = v_pid;
    WHEN 'intelligence' THEN UPDATE players SET intelligence = intelligence + v_gain WHERE id = v_pid;
    WHEN 'labor'        THEN UPDATE players SET labor        = labor        + v_gain WHERE id = v_pid;
    ELSE NULL;
  END CASE;

  UPDATE players SET exp = exp + v_gain * 2 WHERE id = v_pid;
  PERFORM check_level_up(v_pid);
  INSERT INTO events(player_id,type,title,description,exp_change)
  VALUES(v_pid,'training','💪 تدريب ناجح!','تحسّنت '||p_stat||' بمقدار '||v_gain, v_gain*2);
  RETURN jsonb_build_object('success',true,'message','تحسّنت '||p_stat||' بمقدار '||v_gain,'gain',v_gain);
END;
$$;

-- send_message: يتتبع total_messages
CREATE OR REPLACE FUNCTION public.send_message(p_to_id UUID, p_subject TEXT, p_body TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pid    UUID := auth.uid();
  v_sender players%ROWTYPE;
  v_recip  players%ROWTYPE;
BEGIN
  SELECT * INTO v_sender FROM players WHERE id = v_pid;
  SELECT * INTO v_recip  FROM players WHERE id = p_to_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'message','اللاعب غير موجود'); END IF;
  IF p_to_id = v_pid  THEN RETURN jsonb_build_object('success',false,'message','لا يمكنك مراسلة نفسك'); END IF;
  IF length(trim(p_body)) < 1 THEN RETURN jsonb_build_object('success',false,'message','الرسالة فارغة'); END IF;

  INSERT INTO messages (from_id, to_id, from_name, to_name, subject, body)
  VALUES (v_pid, p_to_id, v_sender.username, v_recip.username, p_subject, p_body);

  UPDATE players SET total_messages = total_messages + 1 WHERE id = v_pid;

  RETURN jsonb_build_object('success',true,'message','تم إرسال الرسالة');
END;
$$;

-- attack: يتتبع total_attacks_won
CREATE OR REPLACE FUNCTION public.attack(p_target_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pid      UUID := auth.uid();
  v_attacker players%ROWTYPE;
  v_defender players%ROWTYPE;
  v_wpn      INTEGER := 0;
  v_arm      INTEGER := 0;
  v_att_roll INTEGER;
  v_def_roll INTEGER;
  v_stolen   INTEGER := 0;
  v_winner   UUID;
BEGIN
  SELECT * INTO v_attacker FROM players WHERE id = v_pid;
  SELECT * INTO v_defender FROM players WHERE id = p_target_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'message','اللاعب غير موجود'); END IF;
  IF p_target_id = v_pid THEN RETURN jsonb_build_object('success',false,'message','لا يمكنك مهاجمة نفسك'); END IF;
  IF v_attacker.energy < 20 THEN RETURN jsonb_build_object('success',false,'message','طاقتك غير كافية (تحتاج 20)'); END IF;
  IF v_attacker.in_jail     AND v_attacker.jail_until     > now() THEN RETURN jsonb_build_object('success',false,'message','أنت في السجن!'); END IF;
  IF v_attacker.in_hospital AND v_attacker.hospital_until > now() THEN RETURN jsonb_build_object('success',false,'message','أنت في المشفى!'); END IF;
  IF v_defender.in_jail     AND v_defender.jail_until     > now() THEN RETURN jsonb_build_object('success',false,'message','الهدف في السجن'); END IF;

  SELECT COALESCE(SUM(w.attack_bonus),0)  INTO v_wpn FROM inventory i JOIN weapons w ON i.weapon_id=w.id WHERE i.player_id=v_pid         AND i.equipped=true AND w.type!='armor';
  SELECT COALESCE(SUM(w.defense_bonus),0) INTO v_arm FROM inventory i JOIN weapons w ON i.weapon_id=w.id WHERE i.player_id=p_target_id   AND i.equipped=true AND w.type='armor';

  v_att_roll := floor(random()*100 + v_attacker.strength + v_wpn);
  v_def_roll := floor(random()*100 + v_defender.defense  + v_arm);

  UPDATE players SET energy = energy - 20 WHERE id = v_pid;

  IF v_att_roll >= v_def_roll THEN
    v_winner := v_pid;
    v_stolen := GREATEST(floor(v_defender.cash * 0.1)::INT, 0);
    UPDATE players SET cash = cash - v_stolen, health = GREATEST(health - floor(random()*20+5)::INT, 1) WHERE id = p_target_id;
    UPDATE players SET cash = cash + v_stolen, exp = exp + 30, total_attacks_won = total_attacks_won + 1 WHERE id = v_pid;
    PERFORM check_level_up(v_pid);
    INSERT INTO events(player_id,type,title,description,money_change,exp_change)
    VALUES(v_pid,'attack_win','⚔️ انتصرت!','هزمت '||v_defender.username||' وسرقت $'||v_stolen,v_stolen,30);
    INSERT INTO events(player_id,type,title,description,money_change)
    VALUES(p_target_id,'attack_loss','💀 هُزمت!',v_attacker.username||' هاجمك وسرق $'||v_stolen,-v_stolen);
  ELSE
    v_winner := p_target_id;
    INSERT INTO events(player_id,type,title,description)
    VALUES(v_pid,'attack_loss','❌ خسرت الهجوم','هاجمت '||v_defender.username||' لكنك خسرت');
  END IF;

  INSERT INTO attacks(attacker_id,defender_id,winner_id,attacker_name,defender_name,attacker_roll,defender_roll,money_stolen)
  VALUES(v_pid,p_target_id,v_winner,v_attacker.username,v_defender.username,v_att_roll,v_def_roll,v_stolen);

  RETURN jsonb_build_object(
    'success',      true,
    'won',          (v_winner = v_pid),
    'stolen',       v_stolen,
    'attacker_roll', v_att_roll,
    'defender_roll', v_def_roll,
    'message',      CASE WHEN v_winner = v_pid THEN 'انتصرت وسرقت $'||v_stolen ELSE 'خسرت الهجوم' END
  );
END;
$$;

NOTIFY pgrst, 'reload schema';
