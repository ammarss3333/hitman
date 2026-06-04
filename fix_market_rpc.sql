-- =====================================================
-- RPC: buy_from_market
-- شراء سلاح من السوق بشكل ذري (atomic transaction)
-- =====================================================

CREATE OR REPLACE FUNCTION public.buy_from_market(p_market_id UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pid       UUID;
  v_listing   RECORD;
  v_buyer     RECORD;
BEGIN
  -- تحديد هوية المشتري من الجلسة الحالية
  v_pid := auth.uid();
  IF v_pid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'غير مصرح لك بهذه العملية');
  END IF;

  -- قفل سجل السوق لمنع التزامن
  SELECT m.id, m.seller_id, m.inventory_id, m.price, m.weapon_name
    INTO v_listing
    FROM public.market m
   WHERE m.id = p_market_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'العرض غير موجود أو تم بيعه بالفعل');
  END IF;

  -- لا يمكن شراء قطعتك الخاصة
  IF v_listing.seller_id = v_pid THEN
    RETURN jsonb_build_object('success', false, 'message', 'لا يمكنك شراء عرضك الخاص');
  END IF;

  -- جلب بيانات المشتري مع قفل الصف
  SELECT id, cash
    INTO v_buyer
    FROM public.players
   WHERE id = v_pid
     FOR UPDATE;

  IF v_buyer.cash < v_listing.price THEN
    RETURN jsonb_build_object('success', false, 'message', 'رصيدك غير كافٍ لإتمام هذه الصفقة');
  END IF;

  -- قفل سجل البائع وإضافة المبلغ
  UPDATE public.players
     SET cash = cash + v_listing.price
   WHERE id = v_listing.seller_id;

  -- خصم المبلغ من المشتري
  UPDATE public.players
     SET cash = cash - v_listing.price
   WHERE id = v_pid;

  -- نقل ملكية السلاح للمشتري
  UPDATE public.inventory
     SET player_id  = v_pid,
         for_sale   = false,
         sale_price = null,
         equipped   = false
   WHERE id = v_listing.inventory_id;

  -- حذف إعلان السوق
  DELETE FROM public.market
   WHERE id = p_market_id;

  -- تسجيل حدث الشراء للمشتري
  INSERT INTO public.events (player_id, type, title, description, money_change)
  VALUES (
    v_pid,
    'market_buy',
    '🛒 شراء من السوق',
    'اشتريت ' || v_listing.weapon_name || ' بسعر $' || v_listing.price,
    -v_listing.price
  );

  RETURN jsonb_build_object('success', true, 'message', 'تم شراء ' || v_listing.weapon_name || ' بنجاح!');

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'message', 'حدث خطأ أثناء الشراء: ' || SQLERRM);
END;
$$;

-- منح صلاحية التنفيذ للمستخدمين المصادق عليهم
GRANT EXECUTE ON FUNCTION public.buy_from_market(UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';
