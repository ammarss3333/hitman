-- ============================================================================
-- 🛠️  ترقية نظام العمل والمهنة — "قاتل مأجور"
-- ----------------------------------------------------------------------------
-- نموذج مستوحى من Torn: ورديات يومية + إحصائيات عمل + نقاط عمل + ترقيات.
-- الحلقة اليومية الأساسية أصبحت work_shift() بدلاً من مجرّد قبض الراتب.
--
-- خريطة الوظيفة ← إحصائية العمل التي تنمّيها:
--   عمل يدوي  (work_manual)    : mechanic, driver
--   عمل ذهني  (work_intel)     : hacker, dealer
--   عمل بدني  (work_endurance) : guard, bodyguard, assassin
--
-- مثال على التقدّم (لاعب ملتزم يعمل وردية يومياً في وظيفة "حارس أمن"):
--   base_salary=800, الدرجة 1 → كل وردية ≈ 800$ + بونص سلسلة، +12 إحصائية بدنية، +2 نقطة عمل.
--   متطلبات الترقية للدرجة 2: work_endurance >= 50 و job_points >= 3.
--   بعد ~5 أيام: endurance≈60، نقاط≈10 → ترقية للدرجة 2 (تكلفة 3 نقاط).
--   متطلبات الدرجة 3: endurance>=100، نقاط>=6 … وهكذا.
--   خلال 1-2 أسبوع من العمل اليومي يصل اللاعب لدرجات متقدمة وتتراكم نقاط
--   تكفي لمتجر النقاط (تدريب الإحصائيات أو تعبئة الطاقة).
-- ============================================================================

-- 1) أعمدة اللاعب الجديدة ------------------------------------------------------
ALTER TABLE public.players ADD COLUMN IF NOT EXISTS job_points    INT DEFAULT 0;
ALTER TABLE public.players ADD COLUMN IF NOT EXISTS work_manual   INT DEFAULT 0;
ALTER TABLE public.players ADD COLUMN IF NOT EXISTS work_intel    INT DEFAULT 0;
ALTER TABLE public.players ADD COLUMN IF NOT EXISTS work_endurance INT DEFAULT 0;
ALTER TABLE public.players ADD COLUMN IF NOT EXISTS last_shift    TIMESTAMPTZ;
ALTER TABLE public.players ADD COLUMN IF NOT EXISTS shift_streak  INT DEFAULT 0;

-- دالة مساعدة: ترجع إحصائية العمل التي تنمّيها الوظيفة ---------------------------
CREATE OR REPLACE FUNCTION job_work_stat(p_job_id TEXT)
RETURNS TEXT AS $$
BEGIN
  RETURN CASE p_job_id
    WHEN 'mechanic'  THEN 'work_manual'
    WHEN 'driver'    THEN 'work_manual'
    WHEN 'hacker'    THEN 'work_intel'
    WHEN 'dealer'    THEN 'work_intel'
    WHEN 'guard'     THEN 'work_endurance'
    WHEN 'bodyguard' THEN 'work_endurance'
    WHEN 'assassin'  THEN 'work_endurance'
    ELSE 'work_manual'
  END;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- 2) RPC: وردية العمل اليومية --------------------------------------------------
CREATE OR REPLACE FUNCTION work_shift()
RETURNS JSONB AS $$
DECLARE
  v_pid UUID := auth.uid();
  v_player players%ROWTYPE;
  v_job jobs%ROWTYPE;
  v_hours FLOAT;
  v_stat TEXT;
  v_cash INT; v_streak_bonus FLOAT;
  v_jp INT; v_stat_gain INT;
  v_new_streak INT;
BEGIN
  SELECT * INTO v_player FROM players WHERE id=v_pid FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'message','اللاعب غير موجود'); END IF;
  IF v_player.job_id IS NULL THEN RETURN jsonb_build_object('success',false,'message','ليس لديك وظيفة! اختر وظيفة أولاً'); END IF;
  IF v_player.in_jail AND v_player.jail_until > now() THEN RETURN jsonb_build_object('success',false,'message','لا يمكنك العمل وأنت في السجن'); END IF;
  IF v_player.in_hospital AND v_player.hospital_until > now() THEN RETURN jsonb_build_object('success',false,'message','لا يمكنك العمل وأنت في المستشفى'); END IF;

  SELECT * INTO v_job FROM jobs WHERE id=v_player.job_id;

  -- تبريد 24 ساعة
  IF v_player.last_shift IS NOT NULL THEN
    v_hours := EXTRACT(EPOCH FROM (now()-v_player.last_shift))/3600;
    IF v_hours < 24 THEN
      RETURN jsonb_build_object('success',false,
        'message','وردية اليوم انتهت! الوردية القادمة بعد '||ROUND(24-v_hours,1)||' ساعة',
        'hours_left',24-v_hours);
    END IF;
  END IF;

  -- السلسلة: إن مرّ أكثر من 48 ساعة (فوّت يوماً) تُعاد لـ 1، وإلا +1
  IF v_player.last_shift IS NOT NULL AND EXTRACT(EPOCH FROM (now()-v_player.last_shift))/3600 > 48 THEN
    v_new_streak := 1;
  ELSE
    v_new_streak := COALESCE(v_player.shift_streak,0) + 1;
  END IF;

  -- المكافآت: راتب أساسي × الدرجة + بونص سلسلة (5% لكل يوم، بحد أقصى 50%)
  v_streak_bonus := LEAST(v_new_streak * 0.05, 0.50);
  v_cash := ROUND(v_job.base_salary * v_player.job_level * (1 + v_streak_bonus));
  v_jp := v_player.job_level + 1;                     -- نقاط عمل
  v_stat_gain := 5 + (v_player.job_level * 2);        -- +7 درجة 1 … حتى +25 درجة 10
  v_stat := job_work_stat(v_player.job_id);

  UPDATE players SET
    cash = cash + v_cash,
    exp = exp + v_job.exp_per_day,
    job_points = job_points + v_jp,
    shift_streak = v_new_streak,
    last_shift = now(),
    last_active = now(),
    work_manual    = work_manual    + CASE WHEN v_stat='work_manual'    THEN v_stat_gain ELSE 0 END,
    work_intel     = work_intel     + CASE WHEN v_stat='work_intel'     THEN v_stat_gain ELSE 0 END,
    work_endurance = work_endurance + CASE WHEN v_stat='work_endurance' THEN v_stat_gain ELSE 0 END
  WHERE id=v_pid;

  PERFORM check_level_up(v_pid);

  INSERT INTO events(player_id,type,title,description,money_change,exp_change)
  VALUES(v_pid,'work_shift','🛠️ وردية عمل',
         'أنهيت وردية في '||v_job.name||' (سلسلة '||v_new_streak||' يوم)',
         v_cash, v_job.exp_per_day);

  RETURN jsonb_build_object(
    'success',true,
    'message','أنهيت وردية اليوم! 💪',
    'cash_earned',v_cash,
    'job_points_earned',v_jp,
    'streak',v_new_streak,
    'stat_gains',jsonb_build_object('stat',v_stat,'amount',v_stat_gain)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3) RPC: طلب ترقية ------------------------------------------------------------
CREATE OR REPLACE FUNCTION request_promotion()
RETURNS JSONB AS $$
DECLARE
  v_pid UUID := auth.uid();
  v_player players%ROWTYPE;
  v_job jobs%ROWTYPE;
  v_stat TEXT;
  v_have_stat INT;
  v_need_stat INT; v_need_jp INT;
  v_new_level INT;
BEGIN
  SELECT * INTO v_player FROM players WHERE id=v_pid FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'message','اللاعب غير موجود'); END IF;
  IF v_player.job_id IS NULL THEN RETURN jsonb_build_object('success',false,'message','ليس لديك وظيفة'); END IF;

  SELECT * INTO v_job FROM jobs WHERE id=v_player.job_id;
  IF v_player.job_level >= v_job.max_level THEN
    RETURN jsonb_build_object('success',false,'message','وصلت للدرجة القصوى في هذه الوظيفة 🏆');
  END IF;

  v_stat := job_work_stat(v_player.job_id);
  v_have_stat := CASE v_stat
    WHEN 'work_manual' THEN v_player.work_manual
    WHEN 'work_intel'  THEN v_player.work_intel
    ELSE v_player.work_endurance END;

  -- منحنى المتطلبات: إحصائية العمل >= الدرجة×50، ونقاط العمل >= الدرجة×3
  v_need_stat := v_player.job_level * 50;
  v_need_jp   := v_player.job_level * 3;

  IF v_have_stat < v_need_stat THEN
    RETURN jsonb_build_object('success',false,
      'message','تحتاج إحصائية عمل '||v_need_stat||' (لديك '||v_have_stat||')');
  END IF;
  IF v_player.job_points < v_need_jp THEN
    RETURN jsonb_build_object('success',false,
      'message','تحتاج '||v_need_jp||' نقطة عمل (لديك '||v_player.job_points||')');
  END IF;

  v_new_level := v_player.job_level + 1;
  UPDATE players SET job_level = v_new_level, job_points = job_points - v_need_jp WHERE id=v_pid;

  INSERT INTO events(player_id,type,title,description)
  VALUES(v_pid,'promotion','📈 ترقية!','ترقيت إلى الدرجة '||v_new_level||' في '||v_job.name);

  RETURN jsonb_build_object('success',true,
    'message','🎉 تهانينا! ترقيت إلى الدرجة '||v_new_level||' في '||v_job.name,
    'new_level',v_new_level);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4) RPC: متجر نقاط العمل ------------------------------------------------------
CREATE OR REPLACE FUNCTION spend_job_points(p_action TEXT, p_amount INT)
RETURNS JSONB AS $$
DECLARE
  v_pid UUID := auth.uid();
  v_player players%ROWTYPE;
  v_gain INT;
  v_refill INT;
BEGIN
  SELECT * INTO v_player FROM players WHERE id=v_pid FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'message','اللاعب غير موجود'); END IF;
  IF p_amount IS NULL OR p_amount < 1 THEN RETURN jsonb_build_object('success',false,'message','كمية غير صالحة'); END IF;
  IF v_player.job_points < p_amount THEN
    RETURN jsonb_build_object('success',false,'message','نقاط العمل غير كافية (لديك '||v_player.job_points||')');
  END IF;

  IF p_action IN ('train_manual','train_intel','train_endurance') THEN
    v_gain := p_amount * 10;   -- 1 نقطة = +10 إحصائية عمل
    UPDATE players SET
      job_points = job_points - p_amount,
      work_manual    = work_manual    + CASE WHEN p_action='train_manual'    THEN v_gain ELSE 0 END,
      work_intel     = work_intel     + CASE WHEN p_action='train_intel'     THEN v_gain ELSE 0 END,
      work_endurance = work_endurance + CASE WHEN p_action='train_endurance' THEN v_gain ELSE 0 END
    WHERE id=v_pid;
    RETURN jsonb_build_object('success',true,'message','حصلت على +'||v_gain||' إحصائية عمل 💪');

  ELSIF p_action = 'energy_refill' THEN
    -- 1 نقطة = +20 طاقة حتى الحد الأقصى
    v_refill := LEAST(p_amount * 20, v_player.max_energy - v_player.energy);
    IF v_refill <= 0 THEN RETURN jsonb_build_object('success',false,'message','طاقتك ممتلئة بالفعل'); END IF;
    -- نخصم النقاط بقدر ما استُهلك فعلياً (مقرّبة للأعلى)
    UPDATE players SET
      energy = LEAST(energy + v_refill, max_energy),
      job_points = job_points - CEIL(v_refill::FLOAT/20)::INT
    WHERE id=v_pid;
    RETURN jsonb_build_object('success',true,'message','تعبئة الطاقة +'||v_refill||' ⚡');

  ELSE
    RETURN jsonb_build_object('success',false,'message','إجراء غير معروف');
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

NOTIFY pgrst, 'reload schema';
