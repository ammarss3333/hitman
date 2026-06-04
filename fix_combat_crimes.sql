-- =====================================================
-- ترقية ميكانيكا القتال والجرائم - قاتل مأجور
-- =====================================================
-- ملف ترحيل (migration) مستقل وقابل لإعادة التشغيل (idempotent).
-- انسخه والصقه في Supabase SQL Editor وشغّله.
-- يحتوي على:
--   1. إعادة كتابة attack_player بصيغة لوجستية واقعية.
--   2. نظام مهارة لكل جريمة + صعوبة تتدرج مع المستوى (perform_crime).
--   3. عقود الاغتيال (contracts) + RPC تنفيذ العقد.
-- جميع التعديلات على شكل CREATE OR REPLACE / IF NOT EXISTS.
-- =====================================================

-- =====================================================
-- 1) القتال - attack_player بصيغة لوجستية
-- =====================================================
-- القوة الهجومية = (strength*0.6 + fitness*0.4) * (1 + مضاعف السلاح 0..0.5)
-- القوة الدفاعية = (defense*0.6 + fitness*0.4) * (1 + مضاعف الدرع 0..0.5)
-- ratio = atk/(atk+def) ;  win = 1/(1+exp(-6*(ratio-0.5))) محصورة [0.05,0.95]
CREATE OR REPLACE FUNCTION attack_player(p_target_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_pid UUID := auth.uid();
  v_atk players%ROWTYPE;
  v_def players%ROWTYPE;
  v_wpn INT := 0; v_arm INT := 0;
  v_atk_mult FLOAT; v_def_mult FLOAT;
  v_atk_power FLOAT; v_def_power FLOAT;
  v_ratio FLOAT; v_chance FLOAT;
  v_atk_roll INT; v_def_roll INT;
  v_stolen INT := 0;
  v_wins BOOLEAN;
BEGIN
  SELECT * INTO v_atk FROM players WHERE id = v_pid FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'message','غير مصرح'); END IF;
  IF v_pid = p_target_id THEN RETURN jsonb_build_object('success',false,'message','لا يمكنك مهاجمة نفسك'); END IF;
  SELECT * INTO v_def FROM players WHERE id = p_target_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'message','اللاعب غير موجود'); END IF;
  IF (v_atk.in_jail AND v_atk.jail_until > now()) OR (v_atk.in_hospital AND v_atk.hospital_until > now()) THEN
    RETURN jsonb_build_object('success',false,'message','لا يمكنك القتال الآن'); END IF;
  IF v_atk.energy < 20 THEN RETURN jsonb_build_object('success',false,'message','تحتاج 20 طاقة للهجوم'); END IF;

  -- مجموع هجوم الأسلحة المجهّزة (غير الدروع) ومجموع دفاع دروع الخصم
  SELECT COALESCE(SUM(w.attack_bonus),0) INTO v_wpn
    FROM inventory i JOIN weapons w ON i.weapon_id=w.id
    WHERE i.player_id=v_pid AND i.equipped=true AND w.type!='armor';
  SELECT COALESCE(SUM(w.defense_bonus),0) INTO v_arm
    FROM inventory i JOIN weapons w ON i.weapon_id=w.id
    WHERE i.player_id=p_target_id AND i.equipped=true AND w.type='armor';

  -- تحويل قيم الأسلحة/الدروع (0..~65) إلى مضاعف 0..0.5
  v_atk_mult := LEAST(v_wpn::FLOAT / 130.0, 0.5);
  v_def_mult := LEAST(v_arm::FLOAT / 120.0, 0.5);

  v_atk_power := (v_atk.strength*0.6 + v_atk.fitness*0.4) * (1 + v_atk_mult);
  v_def_power := (v_def.defense*0.6 + v_def.fitness*0.4) * (1 + v_def_mult);

  v_ratio  := v_atk_power / GREATEST(v_atk_power + v_def_power, 0.0001);
  v_chance := 1.0 / (1.0 + exp(-6.0 * (v_ratio - 0.5)));
  v_chance := GREATEST(0.05, LEAST(0.95, v_chance));

  v_atk_roll := round(v_atk_power)::INT;
  v_def_roll := round(v_def_power)::INT;
  v_wins := random() < v_chance;

  UPDATE players SET energy = energy - 20 WHERE id = v_pid;

  IF v_wins THEN
    v_stolen := GREATEST(LEAST(floor(v_def.cash*0.1)::INT, 10000), 0);
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

  RETURN jsonb_build_object(
    'success',true,'attacker_wins',v_wins,
    'attacker_roll',v_atk_roll,'defender_roll',v_def_roll,
    'money_stolen',v_stolen,'attacker_name',v_atk.username,'defender_name',v_def.username,
    'win_chance',round(v_chance*100)::INT,
    'message',CASE WHEN v_wins THEN 'انتصرت وسرقت $'||v_stolen ELSE 'خسرت المعركة!' END);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- 2) نظام مهارة الجرائم + صعوبة متدرجة
-- =====================================================
CREATE TABLE IF NOT EXISTS public.player_crime_skill (
  player_id UUID REFERENCES public.players(id) ON DELETE CASCADE,
  crime_id  TEXT REFERENCES public.crimes(id),
  skill     INT DEFAULT 0,
  attempts  INT DEFAULT 0,
  PRIMARY KEY (player_id, crime_id)
);
ALTER TABLE public.player_crime_skill ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "pcs_sel" ON public.player_crime_skill;
CREATE POLICY "pcs_sel" ON public.player_crime_skill FOR SELECT USING (player_id = auth.uid());

-- effectivePower = intelligence*0.4 + skill*6 + level*2
-- difficulty     = min_level*40 + level*1.5   (تتدرج مع المستوى)
-- success        = power/(power+difficulty) محصورة [0.02,0.95]
CREATE OR REPLACE FUNCTION perform_crime(p_crime_id TEXT)
RETURNS JSONB AS $$
DECLARE
  v_pid UUID := auth.uid();
  v_player players%ROWTYPE;
  v_crime crimes%ROWTYPE;
  v_skill INT := 0;
  v_power FLOAT; v_diff FLOAT; v_chance FLOAT;
  v_money INT; v_gain INT; v_exp INT;
  v_crit BOOLEAN := false;
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
    RETURN jsonb_build_object('success',false,'message','مستواك '||v_player.level||' غير كافٍ. تحتاج مستوى '||v_crime.min_level); END IF;
  IF v_player.energy < v_crime.energy_cost THEN
    RETURN jsonb_build_object('success',false,'message','طاقتك غير كافية. تحتاج '||v_crime.energy_cost); END IF;

  -- المهارة الحالية
  SELECT skill INTO v_skill FROM player_crime_skill WHERE player_id=v_pid AND crime_id=p_crime_id;
  IF v_skill IS NULL THEN v_skill := 0; END IF;

  v_power  := v_player.intelligence*0.4 + v_skill*6 + v_player.level*2;
  v_diff   := v_crime.min_level*40 + v_player.level*1.5;
  v_chance := v_power / GREATEST(v_power + v_diff, 0.0001);
  v_chance := GREATEST(0.02, LEAST(0.95, v_chance));

  -- خصم الطاقة وتسجيل المحاولة
  UPDATE players SET energy = energy - v_crime.energy_cost WHERE id = v_pid;
  INSERT INTO player_crime_skill(player_id,crime_id,attempts) VALUES(v_pid,p_crime_id,1)
    ON CONFLICT (player_id,crime_id) DO UPDATE SET attempts = player_crime_skill.attempts + 1;

  IF random() < v_chance THEN
    -- نجاح: زيادة المهارة (تتناقص قرب الحد ~100)
    v_gain := floor(random()*3)::INT + 1;
    IF v_skill >= 80 THEN v_gain := GREATEST(1, v_gain - 2);
    ELSIF v_skill >= 50 THEN v_gain := GREATEST(1, v_gain - 1); END IF;
    v_skill := LEAST(100, v_skill + v_gain);
    UPDATE player_crime_skill SET skill = v_skill WHERE player_id=v_pid AND crime_id=p_crime_id;

    -- المكافأة تتدرج مع الصعوبة
    v_money := floor(random()*(v_crime.base_money_max-v_crime.base_money_min)+v_crime.base_money_min)::INT;
    v_money := v_money + floor(v_diff*2)::INT;
    v_exp   := v_crime.base_exp;
    IF random() < 0.05 THEN v_crit := true; v_money := v_money*2; v_exp := v_exp*2; END IF;

    UPDATE players SET cash=cash+v_money, exp=exp+v_exp WHERE id=v_pid;
    PERFORM check_level_up(v_pid);
    INSERT INTO events(player_id,type,title,description,money_change,exp_change)
      VALUES(v_pid,'crime_success',
        CASE WHEN v_crit THEN '💥 ضربة معلم!' ELSE '✅ جريمة ناجحة!' END,
        'نجحت في '||v_crime.name||' وكسبت $'||v_money,v_money,v_exp);
    RETURN jsonb_build_object('success',true,'outcome','success','money_earned',v_money,'exp_earned',v_exp,
      'crit',v_crit,'new_skill',v_skill,'success_chance',round(v_chance*100)::INT,
      'message',CASE WHEN v_crit THEN '💥 ضربة معلم! ربحت $'||v_money ELSE 'نجحت! ربحت $'||v_money END);
  ELSE
    -- فشل: السجن/المشفى كما في المنطق الأصلي
    IF floor(random()*100)::INT < v_crime.jail_chance THEN
      UPDATE players SET in_jail=true, jail_until=now()+(v_crime.jail_time_minutes||' minutes')::INTERVAL WHERE id=v_pid;
      INSERT INTO events(player_id,type,title,description) VALUES(v_pid,'crime_jail','🚔 ألقي القبض عليك!','اعتُقلت أثناء '||v_crime.name||' وستبقى في السجن '||v_crime.jail_time_minutes||' دقيقة');
      RETURN jsonb_build_object('success',false,'outcome','jail','new_skill',v_skill,'success_chance',round(v_chance*100)::INT,'message','ألقت بك الشرطة في السجن لـ '||v_crime.jail_time_minutes||' دقيقة!');
    END IF;
    IF floor(random()*100)::INT < v_crime.hospital_chance THEN
      UPDATE players SET in_hospital=true, hospital_until=now()+(v_crime.hospital_time_minutes||' minutes')::INTERVAL, health=GREATEST(health-floor(random()*30+10)::INT,10) WHERE id=v_pid;
      INSERT INTO events(player_id,type,title,description) VALUES(v_pid,'crime_hospital','🏥 أصبت بجروح!','تعرضت للإصابة أثناء '||v_crime.name);
      RETURN jsonb_build_object('success',false,'outcome','hospital','new_skill',v_skill,'success_chance',round(v_chance*100)::INT,'message','أصبت بجروح وأُدخلت المشفى!');
    END IF;
    INSERT INTO events(player_id,type,title,description) VALUES(v_pid,'crime_fail','❌ جريمة فاشلة','فشلت في '||v_crime.name||' وأفلت بصعوبة');
    RETURN jsonb_build_object('success',false,'outcome',null,'new_skill',v_skill,'success_chance',round(v_chance*100)::INT,'message','فشلت في '||v_crime.name||'! حاول مجدداً');
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- 3) عقود الاغتيال
-- =====================================================
CREATE TABLE IF NOT EXISTS public.contracts (
  id          UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  title       TEXT NOT NULL,
  target_name TEXT,
  description TEXT,
  city        TEXT,
  difficulty  INT DEFAULT 50,
  reward      INT DEFAULT 1000,
  min_level   INT DEFAULT 1,
  req_strength INT DEFAULT 0,
  expires_at  TIMESTAMPTZ
);
ALTER TABLE public.contracts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "ctr_sel" ON public.contracts;
CREATE POLICY "ctr_sel" ON public.contracts FOR SELECT USING (true);

CREATE TABLE IF NOT EXISTS public.player_contracts (
  player_id    UUID REFERENCES public.players(id) ON DELETE CASCADE,
  contract_id  UUID REFERENCES public.contracts(id) ON DELETE CASCADE,
  status       TEXT DEFAULT 'completed',
  completed_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (player_id, contract_id)
);
ALTER TABLE public.player_contracts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "pctr_sel" ON public.player_contracts;
CREATE POLICY "pctr_sel" ON public.player_contracts FOR SELECT USING (player_id = auth.uid());

-- بذور العقود (ثابتة المعرّفات لتجنّب التكرار عند إعادة التشغيل)
INSERT INTO public.contracts (id,title,target_name,description,city,difficulty,reward,min_level,req_strength) VALUES
  ('11111111-1111-1111-1111-111111111101','سرقة جوّال زعيم حيّ','أبو سمرة','تصفية تاجر مخدرات صغير في زقاق خلفي','beirut',40,3000,1,10),
  ('11111111-1111-1111-1111-111111111102','تصفية مُبلّغ','الجاسوس وليد','أسكِت شاهداً قبل أن يدلي بشهادته','beirut',90,8000,4,40),
  ('11111111-1111-1111-1111-111111111103','اغتيال مرابٍ','حاج فؤاد','مُرابٍ يبتزّ نصف السوق، أنهِ أمره','amman',70,6500,3,30),
  ('11111111-1111-1111-1111-111111111104','تصفية مهرّب','نبيل الأسمر','مهرّب أسلحة باع لخصومك، صفِّ الحساب','amman',130,13000,6,70),
  ('11111111-1111-1111-1111-111111111105','اغتيال ضابط فاسد','الرائد سامر','ضابط يحمي عصابة منافسة، أزِله','damascus',180,20000,8,110),
  ('11111111-1111-1111-1111-111111111106','تصفية زعيم عصابة','الذئب','زعيم عصابة دمشق، عقد عالي الخطورة','damascus',260,32000,11,170),
  ('11111111-1111-1111-1111-111111111107','اغتيال رجل أعمال','باشا النيل','رجل أعمال يغسل أموال أعدائك في القاهرة','cairo',150,17000,7,90),
  ('11111111-1111-1111-1111-111111111108','الهدف الكبير','الشيخ المليونير','أخطر عقد على الإطلاق - تصفية قطب نفوذ في دبي','dubai',360,60000,14,220)
ON CONFLICT (id) DO NOTHING;

-- attempt_contract
-- power = strength*0.6 + fitness*0.4 + (مجموع هجوم الأسلحة المجهّزة)
-- chance = clamp(power/(power+difficulty), 0.05, 0.95)
-- أمثلة حسابية (للتحقق من التوازن):
--   لاعب أقصى: strength 999, fitness 200, سلاح هجوم 65 => power ≈ 999*0.6+200*0.4+65 = 744
--     • عقد سهل  (diff 40):  744/(744+40)  ≈ 0.95 (مقصوص للسقف) -> موثوق
--     • عقد متوسط(diff 150): 744/(744+150) ≈ 0.83 -> صعب لكن عادل
--     • أصعب عقد (diff 360): 744/(744+360) ≈ 0.67 -> تحدٍّ حقيقي
--   لاعب مبتدئ: strength 50, fitness 20 => power ≈ 38
--     • عقد سهل  (diff 40):  38/(38+40) ≈ 0.49 -> مخاطرة
CREATE OR REPLACE FUNCTION attempt_contract(p_contract_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_pid UUID := auth.uid();
  v_player players%ROWTYPE;
  v_ctr contracts%ROWTYPE;
  v_wpn INT := 0;
  v_power FLOAT; v_chance FLOAT;
  v_win BOOLEAN;
  v_exp INT;
BEGIN
  SELECT * INTO v_player FROM players WHERE id=v_pid FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'message','غير مصرح'); END IF;
  SELECT * INTO v_ctr FROM contracts WHERE id=p_contract_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'message','العقد غير موجود'); END IF;
  IF (v_player.in_jail AND v_player.jail_until>now()) OR (v_player.in_hospital AND v_player.hospital_until>now()) THEN
    RETURN jsonb_build_object('success',false,'message','لا يمكنك تنفيذ عقود الآن'); END IF;
  IF EXISTS(SELECT 1 FROM player_contracts WHERE player_id=v_pid AND contract_id=p_contract_id AND status='completed') THEN
    RETURN jsonb_build_object('success',false,'message','لقد أنجزت هذا العقد بالفعل'); END IF;
  IF v_player.city <> v_ctr.city THEN
    RETURN jsonb_build_object('success',false,'message','يجب أن تكون في مدينة العقد أولاً'); END IF;
  IF v_player.level < v_ctr.min_level THEN
    RETURN jsonb_build_object('success',false,'message','تحتاج مستوى '||v_ctr.min_level); END IF;
  IF v_player.strength < v_ctr.req_strength THEN
    RETURN jsonb_build_object('success',false,'message','تحتاج قوة '||v_ctr.req_strength); END IF;
  IF v_player.energy < 25 THEN
    RETURN jsonb_build_object('success',false,'message','تحتاج 25 طاقة لتنفيذ العقد'); END IF;

  SELECT COALESCE(SUM(w.attack_bonus),0) INTO v_wpn
    FROM inventory i JOIN weapons w ON i.weapon_id=w.id
    WHERE i.player_id=v_pid AND i.equipped=true AND w.type!='armor';

  v_power  := v_player.strength*0.6 + v_player.fitness*0.4 + v_wpn;
  v_chance := v_power / GREATEST(v_power + v_ctr.difficulty, 0.0001);
  v_chance := GREATEST(0.05, LEAST(0.95, v_chance));

  UPDATE players SET energy = energy - 25 WHERE id=v_pid;
  v_win := random() < v_chance;

  IF v_win THEN
    v_exp := GREATEST(v_ctr.difficulty, 20);
    UPDATE players SET cash=cash+v_ctr.reward, exp=exp+v_exp WHERE id=v_pid;
    PERFORM check_level_up(v_pid);
    INSERT INTO player_contracts(player_id,contract_id,status,completed_at)
      VALUES(v_pid,p_contract_id,'completed',now())
      ON CONFLICT (player_id,contract_id) DO UPDATE SET status='completed', completed_at=now();
    INSERT INTO events(player_id,type,title,description,money_change,exp_change)
      VALUES(v_pid,'contract_done','🎯 عقد منجز!','نفّذت عقد "'||v_ctr.title||'" وحصلت على $'||v_ctr.reward,v_ctr.reward,v_exp);
    RETURN jsonb_build_object('success',true,'win',true,'reward',v_ctr.reward,
      'success_chance',round(v_chance*100)::INT,'message','نجح الاغتيال! حصلت على $'||v_ctr.reward);
  ELSE
    -- فشل: احتمال مشفى/سجن، لا مكافأة
    IF random() < 0.5 THEN
      UPDATE players SET in_hospital=true, hospital_until=now()+INTERVAL '40 minutes', health=GREATEST(health-floor(random()*30+15)::INT,5) WHERE id=v_pid;
      INSERT INTO events(player_id,type,title,description) VALUES(v_pid,'contract_fail','🏥 فشل العقد!','أصبت أثناء محاولة تنفيذ "'||v_ctr.title||'"');
      RETURN jsonb_build_object('success',true,'win',false,'reward',0,'success_chance',round(v_chance*100)::INT,'outcome','hospital','message','فشل الاغتيال وأصبت! نقلت للمشفى');
    ELSE
      UPDATE players SET in_jail=true, jail_until=now()+INTERVAL '40 minutes' WHERE id=v_pid;
      INSERT INTO events(player_id,type,title,description) VALUES(v_pid,'contract_fail','🚔 فشل العقد!','قُبض عليك أثناء محاولة تنفيذ "'||v_ctr.title||'"');
      RETURN jsonb_build_object('success',true,'win',false,'reward',0,'success_chance',round(v_chance*100)::INT,'outcome','jail','message','فشل الاغتيال وألقي القبض عليك!');
    END IF;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

NOTIFY pgrst, 'reload schema';
