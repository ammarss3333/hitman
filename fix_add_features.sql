-- =====================================================
-- ميزات جديدة: صيدلية + كازينو + مكافأة يومية
-- شغّل هذا في Supabase → SQL Editor
-- =====================================================

-- 1. حقل المكافأة اليومية
ALTER TABLE public.players ADD COLUMN IF NOT EXISTS last_daily_bonus TIMESTAMPTZ;

-- 2. دالة الصيدلية (استخدام منتج بالمعرّف)
CREATE OR REPLACE FUNCTION use_pharmacy_item(p_item_id TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_pid  UUID := auth.uid();
  v_p    players%ROWTYPE;
  v_price    INTEGER;
  v_etype    TEXT;
  v_evalue   INTEGER;
  v_name     TEXT;
BEGIN
  SELECT * INTO v_p FROM players WHERE id = v_pid;

  CASE p_item_id
    WHEN 'painkiller'    THEN v_price:=500;   v_etype:='health';    v_evalue:=25;  v_name:='مسكّن ألم';
    WHEN 'bandage'       THEN v_price:=1200;  v_etype:='health';    v_evalue:=35;  v_name:='ضمادة طبية';
    WHEN 'med_shot'      THEN v_price:=2500;  v_etype:='health';    v_evalue:=60;  v_name:='حقنة طبية';
    WHEN 'antibiotics'   THEN v_price:=6000;  v_etype:='health';    v_evalue:=100; v_name:='مضادات حيوية';
    WHEN 'energy_drink'  THEN v_price:=800;   v_etype:='energy';    v_evalue:=20;  v_name:='مشروب طاقة';
    WHEN 'protein_shake' THEN v_price:=2500;  v_etype:='energy';    v_evalue:=45;  v_name:='بروتين شيك';
    WHEN 'adrenaline'    THEN v_price:=9000;  v_etype:='energy';    v_evalue:=999; v_name:='حقنة أدرينالين';
    WHEN 'bail'          THEN v_price:=20000; v_etype:='jail';      v_evalue:=1;   v_name:='كفالة قانونية';
    WHEN 'vip_treatment' THEN v_price:=12000; v_etype:='hospital';  v_evalue:=1;   v_name:='علاج VIP';
    ELSE RETURN jsonb_build_object('success',false,'message','منتج غير معروف');
  END CASE;

  IF v_p.cash < v_price THEN
    RETURN jsonb_build_object('success',false,'message','رصيدك غير كافٍ – تحتاج $'||v_price);
  END IF;
  IF v_etype='jail'     AND NOT v_p.in_jail     THEN RETURN jsonb_build_object('success',false,'message','لست في السجن!'); END IF;
  IF v_etype='hospital' AND NOT v_p.in_hospital THEN RETURN jsonb_build_object('success',false,'message','لست في المشفى!'); END IF;

  UPDATE players SET cash = cash - v_price WHERE id = v_pid;

  IF    v_etype='health'   THEN UPDATE players SET health   = LEAST(max_health,   health   + v_evalue) WHERE id=v_pid;
  ELSIF v_etype='energy'   THEN UPDATE players SET energy   = LEAST(max_energy,   energy   + v_evalue) WHERE id=v_pid;
  ELSIF v_etype='jail'     THEN UPDATE players SET in_jail  = false, jail_until  = NULL              WHERE id=v_pid;
  ELSIF v_etype='hospital' THEN UPDATE players SET in_hospital=false,hospital_until=NULL             WHERE id=v_pid;
  END IF;

  INSERT INTO events(player_id,type,title,description,money_change)
  VALUES(v_pid,'pharmacy','💊 '||v_name,'تم استخدام '||v_name,-v_price);

  RETURN jsonb_build_object('success',true,'message','تم استخدام '||v_name||' ✅','effect',v_etype,'value',v_evalue);
END $$;

-- 3. آلة السلوتس (كازينو)
CREATE OR REPLACE FUNCTION play_slots(p_bet INTEGER)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_pid UUID := auth.uid();
  v_p   players%ROWTYPE;
  v_r1  INTEGER; v_r2 INTEGER; v_r3 INTEGER;
  v_win INTEGER := 0;
  v_mul NUMERIC := 0;
  v_msg TEXT    := 'لا يوجد تطابق ❌';
BEGIN
  SELECT * INTO v_p FROM players WHERE id = v_pid;
  IF v_p.cash < p_bet        THEN RETURN jsonb_build_object('success',false,'message','رصيدك غير كافٍ'); END IF;
  IF p_bet < 100             THEN RETURN jsonb_build_object('success',false,'message','الحد الأدنى للرهان $100'); END IF;
  IF p_bet > 100000          THEN RETURN jsonb_build_object('success',false,'message','الحد الأقصى $100,000'); END IF;

  UPDATE players SET cash = cash - p_bet WHERE id = v_pid;

  v_r1 := floor(random()*7)::INTEGER + 1;
  v_r2 := floor(random()*7)::INTEGER + 1;
  v_r3 := floor(random()*7)::INTEGER + 1;

  IF v_r1=v_r2 AND v_r2=v_r3 THEN
    CASE v_r1
      WHEN 7 THEN v_mul:=50; v_msg:='🎉 جاكبوت! ثلاثة سبعة!';
      WHEN 6 THEN v_mul:=20; v_msg:='💎 ثلاثة جواهر!';
      WHEN 5 THEN v_mul:=10; v_msg:='🎰 ثلاثة سلوتس!';
      ELSE        v_mul:=5;  v_msg:='⭐ ثلاثة متشابهة!';
    END CASE;
  ELSIF v_r1=v_r2 OR v_r2=v_r3 OR v_r1=v_r3 THEN
    v_mul := 2; v_msg := '✌️ زوج متشابه!';
  END IF;

  v_win := floor(p_bet * v_mul)::INTEGER;

  IF v_win > 0 THEN
    UPDATE players SET cash = cash + v_win WHERE id = v_pid;
    INSERT INTO events(player_id,type,title,description,money_change)
    VALUES(v_pid,'casino','🎰 '||v_msg,'ربحت $'||v_win||' في السلوتس',v_win-p_bet);
  ELSE
    INSERT INTO events(player_id,type,title,description,money_change)
    VALUES(v_pid,'casino','🎰 خسارة في السلوتس','خسرت $'||p_bet,-p_bet);
  END IF;

  RETURN jsonb_build_object(
    'success',true,'r1',v_r1,'r2',v_r2,'r3',v_r3,
    'win',v_win,'multiplier',v_mul,'net',v_win-p_bet,'message',v_msg
  );
END $$;

-- 4. لعبة النرد (كازينو)
CREATE OR REPLACE FUNCTION play_dice(p_bet INTEGER, p_choice TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_pid    UUID := auth.uid();
  v_p      players%ROWTYPE;
  v_roll   INTEGER;
  v_win    BOOLEAN := false;
  v_payout INTEGER := 0;
BEGIN
  SELECT * INTO v_p FROM players WHERE id = v_pid;
  IF v_p.cash < p_bet              THEN RETURN jsonb_build_object('success',false,'message','رصيدك غير كافٍ'); END IF;
  IF p_bet < 100                   THEN RETURN jsonb_build_object('success',false,'message','الحد الأدنى $100'); END IF;
  IF p_bet > 100000                THEN RETURN jsonb_build_object('success',false,'message','الحد الأقصى $100,000'); END IF;
  IF p_choice NOT IN ('high','low') THEN RETURN jsonb_build_object('success',false,'message','اختيار غير صحيح'); END IF;

  UPDATE players SET cash = cash - p_bet WHERE id = v_pid;

  v_roll := floor(random()*6)::INTEGER + 1;

  IF (p_choice='high' AND v_roll >= 4) OR (p_choice='low' AND v_roll <= 3) THEN
    v_win    := true;
    v_payout := floor(p_bet * 1.9)::INTEGER;
    UPDATE players SET cash = cash + v_payout WHERE id = v_pid;
    INSERT INTO events(player_id,type,title,description,money_change)
    VALUES(v_pid,'casino','🎲 فوز في النرد!','رقم '||v_roll||' – ربحت $'||v_payout,v_payout-p_bet);
  ELSE
    INSERT INTO events(player_id,type,title,description,money_change)
    VALUES(v_pid,'casino','🎲 خسارة في النرد','رقم '||v_roll||' – خسرت $'||p_bet,-p_bet);
  END IF;

  RETURN jsonb_build_object('success',true,'roll',v_roll,'win',v_win,'payout',v_payout,'net',v_payout-p_bet);
END $$;

-- 5. المكافأة اليومية
CREATE OR REPLACE FUNCTION claim_daily_bonus()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_pid   UUID := auth.uid();
  v_p     players%ROWTYPE;
  v_bonus INTEGER;
BEGIN
  SELECT * INTO v_p FROM players WHERE id = v_pid;

  IF v_p.last_daily_bonus IS NOT NULL
     AND v_p.last_daily_bonus::DATE >= CURRENT_DATE THEN
    RETURN jsonb_build_object('success',false,'message','⏰ عد غداً لاستلام مكافأتك!');
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

-- تحديث المخطط
NOTIFY pgrst, 'reload schema';
