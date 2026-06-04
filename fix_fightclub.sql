-- =====================================================
-- نادي القتال السري – Fight Club Feature
-- =====================================================

-- fight_events table
CREATE TABLE IF NOT EXISTS public.fight_events (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  fighter1_id UUID,           -- NULL = NPC
  fighter1_name TEXT NOT NULL,
  fighter1_power INTEGER DEFAULT 50,
  fighter2_id UUID,           -- NULL = NPC
  fighter2_name TEXT NOT NULL,
  fighter2_power INTEGER DEFAULT 50,
  status TEXT DEFAULT 'open', -- open/locked/finished
  winner_id UUID,
  winner_name TEXT,
  fight_at TIMESTAMPTZ NOT NULL,
  result_log TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- fight_bets table
CREATE TABLE IF NOT EXISTS public.fight_bets (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  fight_id UUID REFERENCES fight_events(id),
  player_id UUID REFERENCES players(id) ON DELETE CASCADE,
  fighter_pick INTEGER NOT NULL CHECK (fighter_pick IN (1,2)),
  amount INTEGER NOT NULL CHECK (amount >= 100),
  payout INTEGER,
  won BOOLEAN,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(fight_id, player_id)
);

-- RLS
ALTER TABLE public.fight_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fight_bets   ENABLE ROW LEVEL SECURITY;

-- Permissive SELECT policies
CREATE POLICY "fight_events_select" ON public.fight_events
  FOR SELECT USING (true);

CREATE POLICY "fight_bets_select" ON public.fight_bets
  FOR SELECT USING (true);

-- INSERT policy for bets (via RPC, plus direct insert for logged-in users)
CREATE POLICY "fight_bets_insert" ON public.fight_bets
  FOR INSERT WITH CHECK (auth.uid() = player_id);

-- =====================================================
-- RPC: place_fight_bet
-- =====================================================
CREATE OR REPLACE FUNCTION place_fight_bet(
  p_fight_id UUID,
  p_fighter  INT,
  p_amount   INT
)
RETURNS JSONB AS $$
DECLARE
  v_pid   UUID := auth.uid();
  v_fight fight_events%ROWTYPE;
  v_cash  INT;
BEGIN
  IF v_pid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'غير مصرح');
  END IF;

  SELECT * INTO v_fight FROM fight_events WHERE id = p_fight_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'القتال غير موجود');
  END IF;

  IF v_fight.status <> 'open' THEN
    RETURN jsonb_build_object('success', false, 'message', 'الرهانات مغلقة على هذا القتال');
  END IF;
  IF v_fight.fight_at <= now() + INTERVAL '1 minute' THEN
    RETURN jsonb_build_object('success', false, 'message', 'لقد أغلقت الرهانات — القتال على وشك البدء');
  END IF;

  IF p_fighter NOT IN (1, 2) THEN
    RETURN jsonb_build_object('success', false, 'message', 'اختيار غير صحيح');
  END IF;
  IF p_amount < 100 THEN
    RETURN jsonb_build_object('success', false, 'message', 'الحد الأدنى للرهان 100$');
  END IF;

  SELECT cash INTO v_cash FROM players WHERE id = v_pid FOR UPDATE;
  IF v_cash IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'حساب غير موجود');
  END IF;
  IF v_cash < p_amount THEN
    RETURN jsonb_build_object('success', false, 'message', 'رصيدك غير كافٍ');
  END IF;

  IF EXISTS (SELECT 1 FROM fight_bets WHERE fight_id = p_fight_id AND player_id = v_pid) THEN
    RETURN jsonb_build_object('success', false, 'message', 'لقد راهنت بالفعل على هذا القتال');
  END IF;

  UPDATE players SET cash = cash - p_amount WHERE id = v_pid;

  INSERT INTO fight_bets (fight_id, player_id, fighter_pick, amount)
  VALUES (p_fight_id, v_pid, p_fighter, p_amount);

  RETURN jsonb_build_object(
    'success', true,
    'message', 'تم قبول رهانك بنجاح!'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- RPC: resolve_fight
-- =====================================================
CREATE OR REPLACE FUNCTION resolve_fight(p_fight_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_fight         fight_events%ROWTYPE;
  v_f1_prob       FLOAT;
  v_rand          FLOAT;
  v_winner_pick   INT;
  v_winner_name   TEXT;
  v_winner_id     UUID;
  v_total_pot     BIGINT;
  v_winner_pot    BIGINT;
  v_loser_pot     BIGINT;
  v_house_cut     BIGINT;
  v_payout_pool   BIGINT;
  v_bet           fight_bets%ROWTYPE;
  v_payout        BIGINT;
  v_narrative     TEXT;
  v_idx           INT;
  v_narratives    TEXT[];
BEGIN
  SELECT * INTO v_fight FROM fight_events WHERE id = p_fight_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'القتال غير موجود');
  END IF;

  IF NOT (
    (SELECT is_admin()) OR v_fight.fight_at < now()
  ) THEN
    RETURN jsonb_build_object('success', false, 'message', 'غير مصرح بإنهاء هذا القتال بعد');
  END IF;

  IF v_fight.status = 'finished' THEN
    RETURN jsonb_build_object('success', false, 'message', 'القتال منتهٍ بالفعل');
  END IF;

  -- Power-based win probability for fighter 1, clamped 0.1–0.9
  v_f1_prob := 1.0 / (1.0 + exp(-0.03::FLOAT * (v_fight.fighter1_power - v_fight.fighter2_power)::FLOAT));
  v_f1_prob := GREATEST(0.1, LEAST(0.9, v_f1_prob));

  v_rand := random();
  IF v_rand < v_f1_prob THEN
    v_winner_pick := 1;
    v_winner_name := v_fight.fighter1_name;
    v_winner_id   := v_fight.fighter1_id;
  ELSE
    v_winner_pick := 2;
    v_winner_name := v_fight.fighter2_name;
    v_winner_id   := v_fight.fighter2_id;
  END IF;

  -- Dramatic Arabic narratives
  v_narratives := ARRAY[
    v_fight.fighter1_name || ' وقف في مواجهة ' || v_fight.fighter2_name || ' وسط صخب الحشد المتعطش للدماء. تبادل الاثنان ضربات قاسية هزّت الأرواح قبل الأجساد. في لحظة حاسمة، استجمع ' || v_winner_name || ' كل قواه وأطلق ضربة مدمرة أسقطت خصمه. ارتفعت صرخات النصر تملأ نادي القتال السري.',
    'انطلقت المعركة كالبرق بين ' || v_fight.fighter1_name || ' و' || v_fight.fighter2_name || '. الدم يسيل والعظام تئن تحت وطأة الضربات الموجعة. غير أن ' || v_winner_name || ' أثبت أنه الأشد فتكاً وأسرع ردة فعل. سقط الخاسر وسط صمت مفاجئ ثم تفجّر تصفيق الجمهور.',
    'حين التقى ' || v_fight.fighter1_name || ' بـ' || v_fight.fighter2_name || ' في الحلبة، توقف الزمن للحظة. تراشقا الضربات كالوحوش الكاسرة دون رحمة أو تراجع. ثم جاءت الضربة القاضية من ' || v_winner_name || ' كالصاعقة، فأرسلت المنافس إلى الأرض. استحوذ المنتصر على اللقب وسط هتافات المجانين.',
    v_fight.fighter1_name || ' مقابل ' || v_fight.fighter2_name || ' — معركة نادراً ما يشهدها هذا النادي. ضربات متبادلة، أنفاس متقطعة، وعيون تبحث عن نقطة ضعف. استغل ' || v_winner_name || ' لحظة تردد خصمه وأنهى المعركة بضربة مذهلة. الجمهور لم يصدق ما رأى.',
    'الحلبة تشبّعت بالعرق والدم حين اشتبك ' || v_fight.fighter1_name || ' مع ' || v_fight.fighter2_name || '. كل ضربة كانت تحمل ثقل يأس وغضب متراكمَين. في النهاية، ' || v_winner_name || ' رفع قبضته المضرّجة إعلاناً للنصر. هذه الليلة لن تُنسى في نادي القتال السري.'
  ];

  v_idx := 1 + (floor(random() * 5))::INT;
  IF v_idx > 5 THEN v_idx := 5; END IF;
  v_narrative := v_narratives[v_idx];

  -- Payout calculations
  SELECT COALESCE(SUM(amount), 0) INTO v_total_pot  FROM fight_bets WHERE fight_id = p_fight_id;
  SELECT COALESCE(SUM(amount), 0) INTO v_winner_pot FROM fight_bets WHERE fight_id = p_fight_id AND fighter_pick = v_winner_pick;
  v_loser_pot   := v_total_pot - v_winner_pot;
  v_house_cut   := floor(v_loser_pot * 0.1)::BIGINT;
  v_payout_pool := v_loser_pot - v_house_cut;

  FOR v_bet IN SELECT * FROM fight_bets WHERE fight_id = p_fight_id LOOP
    IF v_bet.fighter_pick = v_winner_pick THEN
      IF v_winner_pot > 0 THEN
        v_payout := v_bet.amount + floor(v_payout_pool * v_bet.amount::FLOAT / v_winner_pot)::BIGINT;
      ELSE
        v_payout := v_bet.amount;
      END IF;
      UPDATE fight_bets SET won = true,  payout = v_payout WHERE id = v_bet.id;
      UPDATE players     SET cash = cash + v_payout WHERE id = v_bet.player_id;
    ELSE
      UPDATE fight_bets SET won = false, payout = 0 WHERE id = v_bet.id;
    END IF;
  END LOOP;

  UPDATE fight_events
  SET status      = 'finished',
      winner_id   = v_winner_id,
      winner_name = v_winner_name,
      result_log  = v_narrative
  WHERE id = p_fight_id;

  RETURN jsonb_build_object(
    'success',     true,
    'winner_name', v_winner_name,
    'winner_pick', v_winner_pick,
    'result_log',  v_narrative,
    'message',     'انتهت المعركة! الفائز: ' || v_winner_name
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- RPC: get_fight_events
-- =====================================================
CREATE OR REPLACE FUNCTION get_fight_events()
RETURNS JSONB AS $$
DECLARE
  v_pid    UUID := auth.uid();
  v_result JSONB;
BEGIN
  SELECT jsonb_agg(
    jsonb_build_object(
      'id',            fe.id,
      'fighter1_name', fe.fighter1_name,
      'fighter1_power',fe.fighter1_power,
      'fighter1_id',   fe.fighter1_id,
      'fighter2_name', fe.fighter2_name,
      'fighter2_power',fe.fighter2_power,
      'fighter2_id',   fe.fighter2_id,
      'status',        fe.status,
      'winner_name',   fe.winner_name,
      'winner_id',     fe.winner_id,
      'fight_at',      fe.fight_at,
      'result_log',    fe.result_log,
      'created_at',    fe.created_at,
      'total_bet',     COALESCE(bets.total_bet,    0),
      'f1_bet_total',  COALESCE(bets.f1_bet_total, 0),
      'f2_bet_total',  COALESCE(bets.f2_bet_total, 0),
      'my_bet',        my_bet.my_bet_info
    )
    ORDER BY
      CASE fe.status WHEN 'open' THEN 0 WHEN 'locked' THEN 1 ELSE 2 END,
      fe.fight_at ASC
  )
  INTO v_result
  FROM fight_events fe
  LEFT JOIN LATERAL (
    SELECT
      SUM(amount)                                              AS total_bet,
      SUM(CASE WHEN fighter_pick = 1 THEN amount ELSE 0 END)  AS f1_bet_total,
      SUM(CASE WHEN fighter_pick = 2 THEN amount ELSE 0 END)  AS f2_bet_total
    FROM fight_bets WHERE fight_id = fe.id
  ) bets ON true
  LEFT JOIN LATERAL (
    SELECT jsonb_build_object(
      'amount',       fb.amount,
      'fighter_pick', fb.fighter_pick,
      'won',          fb.won,
      'payout',       fb.payout
    ) AS my_bet_info
    FROM fight_bets fb
    WHERE fb.fight_id = fe.id AND fb.player_id = v_pid
    LIMIT 1
  ) my_bet ON true
  WHERE
    fe.status IN ('open', 'locked') OR
    (fe.status = 'finished' AND fe.fight_at > now() - INTERVAL '24 hours');

  RETURN COALESCE(v_result, '[]'::JSONB);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- RPC: generate_npc_fights
-- =====================================================
CREATE OR REPLACE FUNCTION generate_npc_fights()
RETURNS JSONB AS $$
DECLARE
  v_open_count INT;
  v_npc_names  TEXT[] := ARRAY[
    'الذئب الرمادي', 'الظل', 'المرتزق', 'الفولاذ', 'العقرب',
    'الثعبان', 'الرصاصة', 'الجحيم', 'الضبع', 'الصخرة',
    'الخنجر', 'الرعد', 'الوحش', 'الدموي', 'الحديد'
  ];
  v_n1         TEXT;
  v_n2         TEXT;
  v_p1         INT;
  v_p2         INT;
  v_fight_time TIMESTAMPTZ;
  v_created    INT := 0;
  i            INT;
  v_used_names TEXT[] := '{}';
  v_pick       INT;
  v_total      INT;
BEGIN
  SELECT COUNT(*) INTO v_open_count FROM fight_events WHERE status = 'open';
  IF v_open_count >= 3 THEN
    RETURN jsonb_build_object('success', true, 'created', 0, 'message', 'يوجد عدد كافٍ من القتالات المفتوحة');
  END IF;

  v_total := array_length(v_npc_names, 1);

  FOR i IN 1..(3 + floor(random() * 3)::INT) LOOP
    -- Pick fighter 1
    LOOP
      v_pick := 1 + floor(random() * v_total)::INT;
      v_pick := LEAST(v_pick, v_total);
      v_n1   := v_npc_names[v_pick];
      EXIT WHEN NOT (v_n1 = ANY(v_used_names));
    END LOOP;
    v_used_names := array_append(v_used_names, v_n1);

    -- Pick fighter 2
    LOOP
      v_pick := 1 + floor(random() * v_total)::INT;
      v_pick := LEAST(v_pick, v_total);
      v_n2   := v_npc_names[v_pick];
      EXIT WHEN v_n2 <> v_n1 AND NOT (v_n2 = ANY(v_used_names));
    END LOOP;
    v_used_names := array_append(v_used_names, v_n2);

    -- Random power 30–120
    v_p1 := 30 + floor(random() * 91)::INT;
    v_p2 := 30 + floor(random() * 91)::INT;

    -- Stagger fight times over next ~6 hours
    v_fight_time := now()
      + (INTERVAL '30 minutes' * i)
      + (random() * INTERVAL '90 minutes')::INTERVAL;

    INSERT INTO fight_events (fighter1_name, fighter1_power, fighter2_name, fighter2_power, fight_at)
    VALUES (v_n1, v_p1, v_n2, v_p2, v_fight_time);

    v_created := v_created + 1;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'created', v_created, 'message', 'تم إنشاء ' || v_created || ' قتالات جديدة');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
