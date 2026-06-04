-- =====================================================
-- تصحيح: رفع حدود GREATEST/LEAST عن دوال المشرف
-- هذا الملف مستقل — شغّله إذا كنت قد نفّذت fix_admin_system.sql
-- مسبقاً وتريد فقط تحديث الدوال الثلاث.
-- آمن للتشغيل أكثر من مرة (CREATE OR REPLACE).
-- =====================================================

-- 1. admin_give_cash — يسمح بأرصدة سالبة (خصم إداري كامل)
CREATE OR REPLACE FUNCTION admin_give_cash(p_target UUID, p_amount INTEGER, p_reason TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_name TEXT; v_title TEXT;
BEGIN
  IF NOT is_admin() THEN RETURN jsonb_build_object('success',false,'message','🚫 غير مصرّح'); END IF;
  -- بدون GREATEST: المشرف يستطيع تعيين رصيد سالب إذا أراد
  UPDATE players SET cash = cash + p_amount WHERE id = p_target RETURNING username INTO v_name;
  IF v_name IS NULL THEN RETURN jsonb_build_object('success',false,'message','لاعب غير موجود'); END IF;
  v_title := CASE WHEN p_amount >= 0 THEN '🎁 منحة إدارية' ELSE '⚠️ خصم إداري' END;
  INSERT INTO events(player_id,type,title,description,money_change)
  VALUES(p_target,'admin', v_title, COALESCE(p_reason,'إجراء إداري'), p_amount);
  RETURN jsonb_build_object('success',true,'message','تم تعديل رصيد '||v_name||' بمقدار '||p_amount);
END $$;

-- 2. admin_set_stat — يسمح بأي قيمة بما فيها الصفر والأرقام الكبيرة
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
  -- بدون GREATEST: المشرف يستطيع تعيين أي قيمة مباشرةً
  EXECUTE format('UPDATE players SET %I = $1 WHERE id = $2', p_field)
    USING p_value, p_target;
  SELECT username INTO v_name FROM players WHERE id = p_target;
  IF v_name IS NULL THEN RETURN jsonb_build_object('success',false,'message','لاعب غير موجود'); END IF;
  INSERT INTO events(player_id,type,title,description)
  VALUES(p_target,'admin','🔧 تعديل إداري','تم تعيين '||p_field||' = '||p_value);
  RETURN jsonb_build_object('success',true,'message','تم تعيين '||p_field||' للاعب '||v_name||' إلى '||p_value);
END $$;

-- 3. admin_gift_all — هدية/خصم جماعي بلا حد أدنى
CREATE OR REPLACE FUNCTION admin_gift_all(p_amount INTEGER, p_reason TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_count INTEGER;
BEGIN
  IF NOT is_admin() THEN RETURN jsonb_build_object('success',false,'message','🚫 غير مصرّح'); END IF;
  -- بدون GREATEST: ينطبق التعديل كاملاً حتى لو أصبح الرصيد سالباً
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

NOTIFY pgrst, 'reload schema';
