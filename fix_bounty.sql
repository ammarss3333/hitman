-- =====================================================
-- لوحة المطلوبين – Bounty Board
-- =====================================================

-- جدول المكافآت
CREATE TABLE IF NOT EXISTS public.bounties (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  poster_id UUID REFERENCES players(id) ON DELETE CASCADE,
  poster_name TEXT,
  target_id UUID REFERENCES players(id) ON DELETE CASCADE,
  target_name TEXT,
  amount INTEGER NOT NULL CHECK (amount >= 1000),
  expires_at TIMESTAMPTZ NOT NULL,
  claimed_by UUID REFERENCES players(id),
  claimed_at TIMESTAMPTZ,
  status TEXT DEFAULT 'active', -- active/claimed/expired
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE bounties ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "b_sel" ON bounties;
CREATE POLICY "b_sel" ON bounties FOR SELECT USING (true);

DROP POLICY IF EXISTS "b_ins" ON bounties;
CREATE POLICY "b_ins" ON bounties FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "b_upd" ON bounties;
CREATE POLICY "b_upd" ON bounties FOR UPDATE USING (true);

-- =====================================================
-- RPC: post_bounty
-- =====================================================
CREATE OR REPLACE FUNCTION post_bounty(p_target_id UUID, p_amount INT, p_hours INT)
RETURNS JSONB AS $$
DECLARE
  v_pid UUID := auth.uid();
  v_poster players%ROWTYPE;
  v_target players%ROWTYPE;
BEGIN
  SELECT * INTO v_poster FROM players WHERE id = v_pid FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'message','غير مصرح'); END IF;

  IF v_pid = p_target_id THEN
    RETURN jsonb_build_object('success',false,'message','لا يمكنك وضع مكافأة على نفسك');
  END IF;

  IF p_amount < 1000 THEN
    RETURN jsonb_build_object('success',false,'message','الحد الأدنى للمكافأة هو $1,000');
  END IF;

  IF p_hours < 1 OR p_hours > 48 THEN
    RETURN jsonb_build_object('success',false,'message','المدة يجب أن تكون بين 1 و 48 ساعة');
  END IF;

  IF v_poster.cash < p_amount THEN
    RETURN jsonb_build_object('success',false,'message','رصيدك غير كافٍ');
  END IF;

  SELECT * INTO v_target FROM players WHERE id = p_target_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success',false,'message','اللاعب المستهدف غير موجود');
  END IF;

  -- خصم المبلغ من الناشر
  UPDATE players SET cash = cash - p_amount WHERE id = v_pid;

  -- إدراج المكافأة
  INSERT INTO bounties (poster_id, poster_name, target_id, target_name, amount, expires_at, status)
  VALUES (v_pid, v_poster.username, p_target_id, v_target.username, p_amount,
          now() + (p_hours || ' hours')::INTERVAL, 'active');

  -- حدث للناشر
  INSERT INTO events(player_id, type, title, description, money_change)
  VALUES (v_pid, 'bounty_posted', '🎯 نشرت مكافأة رأس',
          'وضعت مكافأة $' || p_amount || ' على رأس ' || v_target.username,
          -p_amount);

  RETURN jsonb_build_object('success',true,'message','تم نشر المكافأة! $' || p_amount || ' على رأس ' || v_target.username);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- RPC: get_bounties
-- =====================================================
CREATE OR REPLACE FUNCTION get_bounties()
RETURNS JSONB AS $$
DECLARE
  v_rows JSONB;
BEGIN
  SELECT jsonb_agg(row_to_json(q) ORDER BY q.amount DESC)
  INTO v_rows
  FROM (
    SELECT
      b.id,
      b.poster_id,
      b.poster_name,
      b.target_id,
      b.target_name,
      b.amount,
      b.expires_at,
      b.claimed_by,
      b.claimed_at,
      b.status,
      b.created_at,
      p.level AS target_level,
      p.avatar AS target_avatar,
      (p.last_action_at > now() - INTERVAL '30 minutes') AS target_online,
      c.username AS claimed_by_name
    FROM bounties b
    JOIN players p ON p.id = b.target_id
    LEFT JOIN players c ON c.id = b.claimed_by
    WHERE b.status = 'active' AND b.expires_at > now()
    ORDER BY b.amount DESC
    LIMIT 50
  ) q;

  RETURN COALESCE(v_rows, '[]'::JSONB);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- RPC: attack_player (modified – with bounty claim)
-- =====================================================
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
  v_bounty_id UUID;
  v_bounty_amount INT := 0;
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

    -- فحص المكافآت النشطة على المدافع
    SELECT id, amount INTO v_bounty_id, v_bounty_amount
    FROM bounties
    WHERE target_id = p_target_id AND status = 'active' AND expires_at > now()
    ORDER BY amount DESC
    LIMIT 1;

    IF v_bounty_id IS NOT NULL THEN
      -- استلام المكافأة
      UPDATE bounties
      SET status = 'claimed', claimed_by = v_pid, claimed_at = now()
      WHERE id = v_bounty_id;

      UPDATE players SET cash = cash + v_bounty_amount WHERE id = v_pid;

      INSERT INTO events(player_id, type, title, description, money_change)
      VALUES (v_pid, 'bounty_claimed', '🎯 جمعت مكافأة رأس!',
              'جمعت مكافأة $' || v_bounty_amount || ' على رأس ' || v_def.username,
              v_bounty_amount);
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
    'success',true,
    'attacker_wins',v_wins,
    'attacker_roll',v_atk_roll,
    'defender_roll',v_def_roll,
    'money_stolen',v_stolen,
    'attacker_name',v_atk.username,
    'defender_name',v_def.username,
    'bounty_claimed',v_bounty_amount,
    'message',CASE WHEN v_wins THEN 'انتصرت وسرقت $'||v_stolen ELSE 'خسرت المعركة!' END
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- RPC: cancel_bounty
-- =====================================================
CREATE OR REPLACE FUNCTION cancel_bounty(p_bounty_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_pid UUID := auth.uid();
  v_bounty bounties%ROWTYPE;
  v_refund INT;
BEGIN
  SELECT * INTO v_bounty FROM bounties WHERE id = p_bounty_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'message','المكافأة غير موجودة'); END IF;
  IF v_bounty.poster_id <> v_pid THEN RETURN jsonb_build_object('success',false,'message','لا يمكنك إلغاء مكافأة لم تنشرها'); END IF;
  IF v_bounty.status <> 'active' THEN RETURN jsonb_build_object('success',false,'message','لا يمكن إلغاء هذه المكافأة'); END IF;

  -- استرجاع 90% (رسوم 10%)
  v_refund := floor(v_bounty.amount * 0.9)::INT;

  UPDATE bounties SET status = 'expired' WHERE id = p_bounty_id;
  UPDATE players SET cash = cash + v_refund WHERE id = v_pid;

  INSERT INTO events(player_id, type, title, description, money_change)
  VALUES (v_pid, 'bounty_cancelled', '❌ ألغيت مكافأة رأس',
          'ألغيت مكافأة على ' || v_bounty.target_name || ' واسترددت $' || v_refund || ' (بعد رسوم 10%)',
          v_refund);

  RETURN jsonb_build_object('success',true,'refund',v_refund,'message','تم الإلغاء. استرددت $' || v_refund);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

NOTIFY pgrst, 'reload schema';
