-- =====================================================
-- نظام المدن والسفر والتجارة الإقليمية - قاتل مأجور
-- ملف ترحيل إجباري (idempotent) - شغّله في Supabase SQL Editor
-- يضيف: سوق محلي لكل مدينة، بضائع اللاعب، شراء/بيع للمراجحة (buy-low/sell-high)،
-- وتحسين السفر بتكلفة لكل مدينة.
-- =====================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =====================================================
-- جدول: السوق المحلي لكل مدينة
-- =====================================================
CREATE TABLE IF NOT EXISTS public.city_market (
  id          UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  city        TEXT NOT NULL,
  item_name   TEXT NOT NULL,
  icon        TEXT DEFAULT '📦',
  base_price  INTEGER NOT NULL,
  stock       INTEGER DEFAULT 100,
  restock_at  TIMESTAMPTZ DEFAULT NOW()
);

-- منع التكرار عند إعادة تشغيل الـ seed
CREATE UNIQUE INDEX IF NOT EXISTS city_market_city_item_uidx
  ON public.city_market (city, item_name);

ALTER TABLE public.city_market ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "cm_sel" ON public.city_market;
CREATE POLICY "cm_sel" ON public.city_market FOR SELECT USING (true);

-- =====================================================
-- جدول: بضائع اللاعب
-- =====================================================
CREATE TABLE IF NOT EXISTS public.player_goods (
  player_id UUID REFERENCES public.players(id) ON DELETE CASCADE,
  item_name TEXT NOT NULL,
  qty       INTEGER DEFAULT 0,
  PRIMARY KEY (player_id, item_name)
);

ALTER TABLE public.player_goods ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "pg_sel" ON public.player_goods;
CREATE POLICY "pg_sel" ON public.player_goods FOR SELECT USING (auth.uid() = player_id);

-- =====================================================
-- بيانات: بضائع إقليمية بأسعار مختلفة بين المدن (لإتاحة المراجحة)
-- نفس السلعة قد تُباع في عدة مدن بأسعار مختلفة: اشترِ رخيصاً وبِع غالياً.
-- =====================================================
INSERT INTO public.city_market (city, item_name, icon, base_price, stock) VALUES
  -- بيروت: مخدرات ومجوهرات
  ('beirut',   'حشيش لبناني',   '🌿', 1200, 80),
  ('beirut',   'ذهب',           '🪙', 5200, 50),
  ('beirut',   'سجائر مهربة',   '🚬', 400,  120),

  -- عمّان: أسواق رخيصة (أرخص نقطة شراء)
  ('amman',    'سجائر مهربة',   '🚬', 250,  150),
  ('amman',    'فوسفات',        '🧪', 800,  100),
  ('amman',    'حشيش لبناني',   '🌿', 1500, 60),

  -- دمشق: عقود وبضائع خطرة رخيصة المصدر
  ('damascus', 'آثار قديمة',    '🏺', 3000, 40),
  ('damascus', 'فوسفات',        '🧪', 600,  120),
  ('damascus', 'سلاح خفيف',     '🔫', 4000, 30),

  -- القاهرة: مدينة لا تنام، تجارة واسعة
  ('cairo',    'آثار قديمة',    '🏺', 4500, 35),
  ('cairo',    'قطن',           '🧵', 700,  140),
  ('cairo',    'سجائر مهربة',   '🚬', 600,  100),

  -- دبي: جنة الأثرياء (أغلى نقطة بيع)
  ('dubai',    'ذهب',           '🪙', 7000, 40),
  ('dubai',    'آثار قديمة',    '🏺', 6500, 25),
  ('dubai',    'قطن',           '🧵', 1400, 90),
  ('dubai',    'سلاح خفيف',     '🔫', 6500, 20)
ON CONFLICT DO NOTHING;

-- =====================================================
-- RPC: شراء سلعة من السوق المحلي
-- يجب أن يكون اللاعب في مدينة السوق، ويملك المال، ويتوفر المخزون.
-- =====================================================
CREATE OR REPLACE FUNCTION buy_good(p_market_id UUID, p_qty INT)
RETURNS JSONB AS $$
DECLARE
  v_pid    UUID := auth.uid();
  v_player players%ROWTYPE;
  v_m      city_market%ROWTYPE;
  v_total  INT;
BEGIN
  IF p_qty IS NULL OR p_qty < 1 THEN
    RETURN jsonb_build_object('success',false,'message','الكمية غير صحيحة');
  END IF;
  SELECT * INTO v_player FROM players WHERE id=v_pid FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'message','غير مصرح'); END IF;
  SELECT * INTO v_m FROM city_market WHERE id=p_market_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'message','السلعة غير موجودة'); END IF;
  IF v_player.city <> v_m.city THEN
    RETURN jsonb_build_object('success',false,'message','يجب أن تكون في مدينة هذا السوق للشراء');
  END IF;
  IF v_m.stock < p_qty THEN
    RETURN jsonb_build_object('success',false,'message','المخزون غير كافٍ (متوفر '||v_m.stock||')');
  END IF;
  v_total := v_m.base_price * p_qty;
  IF v_player.cash < v_total THEN
    RETURN jsonb_build_object('success',false,'message','رصيدك غير كافٍ. التكلفة $'||v_total);
  END IF;

  UPDATE players SET cash = cash - v_total WHERE id=v_pid;
  UPDATE city_market SET stock = stock - p_qty WHERE id=p_market_id;
  INSERT INTO player_goods(player_id,item_name,qty) VALUES(v_pid, v_m.item_name, p_qty)
    ON CONFLICT (player_id,item_name) DO UPDATE SET qty = player_goods.qty + EXCLUDED.qty;
  INSERT INTO events(player_id,type,title,description,money_change)
    VALUES(v_pid,'buy_good','🛒 شراء بضاعة','اشتريت '||p_qty||'× '||v_m.item_name||' من سوق '||v_m.city,-v_total);

  RETURN jsonb_build_object('success',true,'spent',v_total,
    'message','اشتريت '||p_qty||'× '||v_m.item_name||' بـ $'||v_total);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- RPC: بيع سلعة بسعر السوق في المدينة الحالية
-- إن كانت المدينة الحالية تتاجر بالسلعة → السعر الكامل (مراجحة مربحة).
-- وإلا → سعر أساسي مخفّض (50% من أعلى سعر معروف للسلعة).
-- =====================================================
CREATE OR REPLACE FUNCTION sell_good(p_item_name TEXT, p_qty INT)
RETURNS JSONB AS $$
DECLARE
  v_pid    UUID := auth.uid();
  v_player players%ROWTYPE;
  v_have   INT;
  v_price  INT;
  v_earned INT;
  v_local  BOOLEAN := false;
BEGIN
  IF p_qty IS NULL OR p_qty < 1 THEN
    RETURN jsonb_build_object('success',false,'message','الكمية غير صحيحة');
  END IF;
  SELECT * INTO v_player FROM players WHERE id=v_pid FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'message','غير مصرح'); END IF;

  SELECT qty INTO v_have FROM player_goods WHERE player_id=v_pid AND item_name=p_item_name;
  IF v_have IS NULL OR v_have < p_qty THEN
    RETURN jsonb_build_object('success',false,'message','لا تملك كمية كافية من '||p_item_name);
  END IF;

  -- سعر السوق في المدينة الحالية إن وُجد
  SELECT base_price INTO v_price FROM city_market
    WHERE city=v_player.city AND item_name=p_item_name;
  IF v_price IS NOT NULL THEN
    v_local := true;
  ELSE
    -- لا تتاجر هذه المدينة بالسلعة: سعر مخفّض = 50% من أعلى سعر معروف
    SELECT GREATEST(floor(MAX(base_price)*0.5)::INT, 1) INTO v_price
      FROM city_market WHERE item_name=p_item_name;
    IF v_price IS NULL THEN v_price := 1; END IF;
  END IF;

  v_earned := v_price * p_qty;
  UPDATE player_goods SET qty = qty - p_qty WHERE player_id=v_pid AND item_name=p_item_name;
  DELETE FROM player_goods WHERE player_id=v_pid AND item_name=p_item_name AND qty <= 0;
  UPDATE players SET cash = cash + v_earned WHERE id=v_pid;
  INSERT INTO events(player_id,type,title,description,money_change)
    VALUES(v_pid,'sell_good','💰 بيع بضاعة','بعت '||p_qty||'× '||p_item_name||' بـ $'||v_earned||
      CASE WHEN v_local THEN ' في سوقها المحلي' ELSE ' (بسعر مخفّض)' END, v_earned);

  RETURN jsonb_build_object('success',true,'earned',v_earned,'local',v_local,
    'message','بعت '||p_qty||'× '||p_item_name||' وكسبت $'||v_earned||
      CASE WHEN v_local THEN '' ELSE ' (سعر مخفّض - هذه المدينة لا تتاجر بها)' END);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- RPC: السفر لمدينة (محسّن) - بتكلفة لكل مدينة
-- التكاليف: beirut 0, amman 1500, cairo 2000, damascus 2500, dubai 5000
-- يُمنع السفر أثناء السجن أو المشفى.
-- =====================================================
CREATE OR REPLACE FUNCTION travel_to_city(p_city TEXT)
RETURNS JSONB AS $$
DECLARE
  v_pid    UUID := auth.uid();
  v_player players%ROWTYPE;
  v_cost   INT;
BEGIN
  SELECT * INTO v_player FROM players WHERE id=v_pid FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'message','غير مصرح'); END IF;
  IF NOT (p_city IN ('beirut','amman','damascus','cairo','dubai')) THEN
    RETURN jsonb_build_object('success',false,'message','مدينة غير صالحة');
  END IF;
  IF v_player.city = p_city THEN
    RETURN jsonb_build_object('success',false,'message','أنت بالفعل في هذه المدينة');
  END IF;
  IF v_player.in_jail AND v_player.jail_until > now() THEN
    RETURN jsonb_build_object('success',false,'message','لا يمكنك السفر وأنت في السجن!');
  END IF;
  IF v_player.in_hospital AND v_player.hospital_until > now() THEN
    RETURN jsonb_build_object('success',false,'message','لا يمكنك السفر وأنت في المشفى!');
  END IF;

  v_cost := CASE p_city
    WHEN 'beirut'   THEN 0
    WHEN 'amman'    THEN 1500
    WHEN 'cairo'    THEN 2000
    WHEN 'damascus' THEN 2500
    WHEN 'dubai'    THEN 5000
    ELSE 2000
  END;

  IF v_player.cash < v_cost THEN
    RETURN jsonb_build_object('success',false,'message','تحتاج $'||v_cost||' للسفر');
  END IF;

  UPDATE players SET city=p_city, cash=cash-v_cost WHERE id=v_pid;
  INSERT INTO events(player_id,type,title,description,money_change)
    VALUES(v_pid,'travel','✈️ سافرت لمدينة جديدة','انتقلت إلى '||p_city||
      CASE WHEN v_cost>0 THEN ' بتكلفة $'||v_cost ELSE '' END, -v_cost);

  RETURN jsonb_build_object('success',true,'city',p_city,'cost',v_cost,
    'message','وصلت بنجاح!'||CASE WHEN v_cost>0 THEN ' (تكلفة $'||v_cost||')' ELSE '' END||' ✈️');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
NOTIFY pgrst, 'reload schema';
