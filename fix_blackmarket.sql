-- =====================================================
-- السوق السوداء – Black Market
-- =====================================================

-- جدول عروض السوق السوداء
CREATE TABLE IF NOT EXISTS public.black_market_items (
  id           UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  weapon_id    UUID REFERENCES public.weapons(id),
  discount_pct INTEGER DEFAULT 20,   -- نسبة الخصم من السعر الأصلي
  quantity     INTEGER DEFAULT 1,    -- الكمية المتاحة
  expires_at   TIMESTAMPTZ NOT NULL,
  created_at   TIMESTAMPTZ DEFAULT NOW()
);

-- =====================================================
-- سياسات أمان الصفوف (RLS)
-- =====================================================
ALTER TABLE public.black_market_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "bm_sel" ON public.black_market_items;
CREATE POLICY "bm_sel" ON public.black_market_items FOR SELECT USING (true);

DROP POLICY IF EXISTS "bm_ins" ON public.black_market_items;
CREATE POLICY "bm_ins" ON public.black_market_items FOR INSERT WITH CHECK (false);

DROP POLICY IF EXISTS "bm_upd" ON public.black_market_items;
CREATE POLICY "bm_upd" ON public.black_market_items FOR UPDATE WITH CHECK (false);

-- =====================================================
-- RPC: get_black_market
-- =====================================================
CREATE OR REPLACE FUNCTION public.get_black_market()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSONB;
BEGIN
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id',             bm.id,
      'weapon_id',      bm.weapon_id,
      'weapon_name',    w.name,
      'weapon_icon',    w.image,
      'weapon_type',    w.type,
      'attack_bonus',   w.attack_bonus,
      'defense_bonus',  w.defense_bonus,
      'level_required', w.level_required,
      'original_price', w.price,
      'discount_pct',   bm.discount_pct,
      'discounted_price', ROUND(w.price * (100 - bm.discount_pct) / 100.0)::INTEGER,
      'quantity',       bm.quantity,
      'expires_at',     bm.expires_at,
      'expires_in_sec', GREATEST(EXTRACT(EPOCH FROM (bm.expires_at - now()))::INTEGER, 0)
    ) ORDER BY bm.discount_pct DESC
  ), '[]'::JSONB) INTO v_result
  FROM black_market_items bm
  JOIN weapons w ON w.id = bm.weapon_id
  WHERE bm.expires_at > now()
    AND bm.quantity > 0;

  RETURN v_result;
END;
$$;

-- =====================================================
-- RPC: buy_black_market
-- =====================================================
CREATE OR REPLACE FUNCTION public.buy_black_market(p_item_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pid        UUID := auth.uid();
  v_player     players%ROWTYPE;
  v_bm         black_market_items%ROWTYPE;
  v_weapon     weapons%ROWTYPE;
  v_price_paid INTEGER;
BEGIN
  IF v_pid IS NULL THEN RETURN jsonb_build_object('success',false,'message','يجب تسجيل الدخول'); END IF;

  -- جلب العرض مع قفل الصف
  SELECT * INTO v_bm FROM black_market_items WHERE id = p_item_id FOR UPDATE;
  IF NOT FOUND               THEN RETURN jsonb_build_object('success',false,'message','العرض غير موجود'); END IF;
  IF v_bm.expires_at <= now() THEN RETURN jsonb_build_object('success',false,'message','انتهت صلاحية هذا العرض'); END IF;
  IF v_bm.quantity <= 0      THEN RETURN jsonb_build_object('success',false,'message','نفد المخزون'); END IF;

  SELECT * INTO v_weapon FROM weapons WHERE id = v_bm.weapon_id;
  SELECT * INTO v_player FROM players WHERE id = v_pid;

  IF v_player.level < v_weapon.level_required THEN
    RETURN jsonb_build_object('success',false,'message','تحتاج مستوى '||v_weapon.level_required||' للحصول على هذا السلاح');
  END IF;

  v_price_paid := ROUND(v_weapon.price * (100 - v_bm.discount_pct) / 100.0)::INTEGER;

  IF v_player.cash < v_price_paid THEN
    RETURN jsonb_build_object('success',false,'message','رصيدك غير كافٍ. تحتاج $'||v_price_paid);
  END IF;

  -- تنفيذ الصفقة بشكل ذري
  UPDATE black_market_items SET quantity = quantity - 1 WHERE id = p_item_id;
  UPDATE players              SET cash    = cash - v_price_paid WHERE id = v_pid;
  INSERT INTO inventory (player_id, weapon_id) VALUES (v_pid, v_bm.weapon_id);

  INSERT INTO events (player_id, type, title, description, money_change)
  VALUES (v_pid, 'black_market', '🕶️ شراء من السوق السوداء',
    'اشتريت '||v_weapon.name||' بسعر $'||v_price_paid||' (خصم '||v_bm.discount_pct||'%)',
    -v_price_paid);

  RETURN jsonb_build_object(
    'success',     true,
    'message',     'حصلت على '||v_weapon.name||' بسعر $'||v_price_paid||'!',
    'weapon_name', v_weapon.name,
    'price_paid',  v_price_paid,
    'discount_pct', v_bm.discount_pct
  );
END;
$$;

-- =====================================================
-- RPC: generate_black_market
-- =====================================================
CREATE OR REPLACE FUNCTION public.generate_black_market()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_active_count INTEGER;
  v_item_count   INTEGER;
  v_weapon_ids   UUID[];
  v_wid          UUID;
  v_discount     INTEGER;
  v_qty          INTEGER;
  v_hours        NUMERIC;
  v_expires      TIMESTAMPTZ;
  i              INTEGER;
BEGIN
  -- لا تولّد إذا كان هناك 3 عروض نشطة أو أكثر
  SELECT COUNT(*) INTO v_active_count
  FROM black_market_items
  WHERE expires_at > now() AND quantity > 0;

  IF v_active_count >= 3 THEN
    RETURN jsonb_build_object('success',false,'message','السوق السوداء ممتلئة حالياً','active',v_active_count);
  END IF;

  -- اختر 4-6 أسلحة عشوائية
  v_item_count := floor(random()*3 + 4)::INTEGER; -- 4 إلى 6

  SELECT ARRAY(
    SELECT id FROM weapons ORDER BY random() LIMIT v_item_count
  ) INTO v_weapon_ids;

  -- أضف صفوف السوق السوداء
  FOR i IN 1..array_length(v_weapon_ids,1) LOOP
    v_wid     := v_weapon_ids[i];
    v_discount := floor(random()*31 + 15)::INTEGER;  -- 15%–45% خصم
    v_qty      := floor(random()*4 + 1)::INTEGER;    -- 1–4 وحدات
    v_hours    := random()*4 + 4;                    -- 4–8 ساعات حقيقية
    v_expires  := now() + (v_hours || ' hours')::INTERVAL;

    INSERT INTO black_market_items (weapon_id, discount_pct, quantity, expires_at)
    VALUES (v_wid, v_discount, v_qty, v_expires);
  END LOOP;

  RETURN jsonb_build_object(
    'success',   true,
    'message',   'تم تحديث السوق السوداء بـ'||v_item_count||' عرض جديد',
    'new_items', v_item_count
  );
END;
$$;

NOTIFY pgrst, 'reload schema';
