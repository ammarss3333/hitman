-- ============================================================================
-- 🗂️  نظام مهام العمل المتنوّعة — "قاتل مأجور"
-- ----------------------------------------------------------------------------
-- جدول job_tasks   : تعريف المهام (3-4 مهام لكل وظيفة، تبريد 15-60 دقيقة)
-- جدول player_job_tasks : يتتبع آخر مرة نفّذ اللاعب كل مهمة
-- دالة do_job_task(p_task_id) : RPC تُنفّذ المهمة بعد التحقق من الشروط
-- ============================================================================

-- ============================================================
-- 1) جدول تعريف المهام
-- ============================================================
CREATE TABLE IF NOT EXISTS public.job_tasks (
  id               TEXT PRIMARY KEY,
  job_id           TEXT NOT NULL REFERENCES public.jobs(id) ON DELETE CASCADE,
  name             TEXT NOT NULL,
  description      TEXT NOT NULL,
  energy_cost      INT  NOT NULL DEFAULT 10,
  stat_key         TEXT NOT NULL,   -- إحصائية الشرط: strength/fitness/labor/intelligence
  min_stat         INT  NOT NULL DEFAULT 0,
  reward_cash      INT  NOT NULL DEFAULT 500,
  reward_jp        INT  NOT NULL DEFAULT 1,
  stat_gain_key    TEXT NOT NULL,   -- إحصائية التدريب: work_manual/work_intel/work_endurance
  stat_gain        INT  NOT NULL DEFAULT 3,
  cooldown_minutes INT  NOT NULL DEFAULT 30
);

-- ============================================================
-- 2) بيانات المهام (7 وظائف × 3-4 مهام)
-- ============================================================

-- ──────────────── حارس الأمن ────────────────
INSERT INTO public.job_tasks VALUES
  ('guard_patrol',   'guard', 'جولة الحراسة',       'طوف المنطقة وتحقق من النقاط الأمنية',              8,  'fitness',      10, 450,  1, 'work_endurance', 3, 20),
  ('guard_check',    'guard', 'فحص الأمن',           'راجع بروتوكولات الحماية وتقرير الحوادث',            10, 'intelligence', 5,  600,  1, 'work_endurance', 4, 30),
  ('guard_recruits', 'guard', 'تدريب المرتزقة',      'درّب مجنّدين جدد على تقنيات الحراسة القتالية',     14, 'strength',     15, 900,  2, 'work_endurance', 6, 45),
  ('guard_lockdown', 'guard', 'إغلاق الموقع',        'أحكم إغلاق المنطقة وأبلّغ عن المشبوهين',           12, 'fitness',      20, 750,  2, 'work_endurance', 5, 40)
ON CONFLICT (id) DO NOTHING;

-- ──────────────── سائق ────────────────
INSERT INTO public.job_tasks VALUES
  ('driver_quick',   'driver', 'توصيلة سريعة',      'وصّل الطرد في الوقت المحدد متجنباً نقاط التفتيش',   8,  'labor',        5,  500,  1, 'work_manual', 3, 20),
  ('driver_cargo',   'driver', 'نقل البضاعة',        'انقل شحنة ثقيلة عبر الطريق السريع',                10, 'labor',        10, 700,  1, 'work_manual', 4, 30),
  ('driver_race',    'driver', 'سباق المدينة',       'أثبت قدرتك في سباق ليلي بشوارع المدينة',           13, 'fitness',      15, 950,  2, 'work_manual', 6, 45),
  ('driver_escape',  'driver', 'مسار الهروب',        'تدرّب على مسارات الفرار الطارئة',                   11, 'intelligence', 8,  800,  2, 'work_manual', 5, 35)
ON CONFLICT (id) DO NOTHING;

-- ──────────────── ميكانيكي ────────────────
INSERT INTO public.job_tasks VALUES
  ('mech_repair',    'mechanic', 'إصلاح السيارة',     'أصلح أعطال المحرك والهيكل الخارجي',                 9,  'labor',        10, 550,  1, 'work_manual', 4, 25),
  ('mech_engine',    'mechanic', 'تعديل المحرك',      'طوّر أداء المحرك لتحسين القدرة والسرعة',            12, 'labor',        20, 800,  2, 'work_manual', 5, 35),
  ('mech_weapons',   'mechanic', 'فحص الأسلحة',       'افحص المركبات المسلحة وتأكد من جاهزية معداتها',    14, 'intelligence', 12, 950,  2, 'work_manual', 6, 45),
  ('mech_armor',     'mechanic', 'تركيب الدرع',       'ركّب تعزيزات حماية على مركبات العملاء الخاصين',    11, 'labor',        15, 700,  1, 'work_manual', 4, 30)
ON CONFLICT (id) DO NOTHING;

-- ──────────────── تاجر ────────────────
INSERT INTO public.job_tasks VALUES
  ('dealer_small',   'dealer', 'صفقة صغيرة',         'أتمم صفقة بضاعة في زقاق هادئ',                     7,  'intelligence', 5,  600,  1, 'work_intel', 3, 20),
  ('dealer_network', 'dealer', 'توسيع الشبكة',       'تواصل مع موزّعين جدد وابنِ علاقات موثوقة',          11, 'intelligence', 15, 850,  2, 'work_intel', 5, 35),
  ('dealer_launder', 'dealer', 'تبييض الأموال',      'مرّر المكاسب عبر قنوات مالية نظيفة',                13, 'intelligence', 20, 1100, 2, 'work_intel', 6, 50),
  ('dealer_supply',  'dealer', 'إدارة المخزون',      'تحقق من الكميات وجدّد الإمدادات بعيداً عن الأعين', 9,  'labor',        8,  650,  1, 'work_intel', 4, 25)
ON CONFLICT (id) DO NOTHING;

-- ──────────────── هاكر ────────────────
INSERT INTO public.job_tasks VALUES
  ('hack_simple',    'hacker', 'اختراق بسيط',        'تجاوز جدار حماية موقع حكومي منخفض الحماية',         8,  'intelligence', 10, 600,  1, 'work_intel', 4, 20),
  ('hack_data',      'hacker', 'سرقة بيانات',        'انتزع ملفات سرية من سيرفر شركة خاصة',              12, 'intelligence', 20, 900,  2, 'work_intel', 5, 35),
  ('hack_cameras',   'hacker', 'تعطيل الكاميرات',    'شوّش شبكة المراقبة قبيل عملية حساسة',              10, 'intelligence', 15, 750,  1, 'work_intel', 4, 30),
  ('hack_bank',      'hacker', 'اختراق مصرفي',       'انفذ إلى النظام المالي واستخرج بيانات الحسابات',    15, 'intelligence', 30, 1200, 3, 'work_intel', 7, 60)
ON CONFLICT (id) DO NOTHING;

-- ──────────────── حارس شخصي ────────────────
INSERT INTO public.job_tasks VALUES
  ('bg_vip',         'bodyguard', 'حماية VIP',        'رافق الشخصية الكبيرة في تنقلاتها اليومية',          10, 'strength',     15, 700,  1, 'work_endurance', 4, 30),
  ('bg_drill',       'bodyguard', 'تمرين قتالي',      'أجرِ تدريبات قتالية مع فريق الحماية',               13, 'fitness',      20, 850,  2, 'work_endurance', 5, 40),
  ('bg_convoy',      'bodyguard', 'مرافقة القافلة',   'أمّن قافلة المركبات في طريق خطر',                   15, 'strength',     25, 1050, 2, 'work_endurance', 7, 50),
  ('bg_threat',      'bodyguard', 'تقييم التهديدات',  'حلّل معلومات استخباراتية وقيّم مستوى الخطر',        9,  'intelligence', 10, 600,  1, 'work_endurance', 3, 25)
ON CONFLICT (id) DO NOTHING;

-- ──────────────── قاتل مأجور ────────────────
INSERT INTO public.job_tasks VALUES
  ('ass_surveil',    'assassin', 'مراقبة الهدف',      'ارصد تحركات الهدف وسجّل نمط حياته اليومي',          9,  'intelligence', 15, 750,  1, 'work_endurance', 4, 30),
  ('ass_cover',      'assassin', 'تنظيف الأثر',       'أزل أي دليل يربطك بالعملية الأخيرة',                11, 'intelligence', 20, 900,  2, 'work_endurance', 5, 35),
  ('ass_trap',       'assassin', 'إعداد الفخ',        'جهّز موقع الكمين وافحص خطة الإفلات',                14, 'strength',     25, 1100, 2, 'work_endurance', 6, 45),
  ('ass_contract',   'assassin', 'مراجعة العقد',      'قيّم تفاصيل العقد الجديد وفاوض على المبلغ',         8,  'intelligence', 10, 650,  1, 'work_endurance', 3, 20)
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- 3) جدول تتبع مهام اللاعبين
-- ============================================================
CREATE TABLE IF NOT EXISTS public.player_job_tasks (
  player_id  UUID  NOT NULL REFERENCES public.players(id) ON DELETE CASCADE,
  task_id    TEXT  NOT NULL REFERENCES public.job_tasks(id) ON DELETE CASCADE,
  last_done  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (player_id, task_id)
);

-- فهرس سريع للبحث بالـ player_id
CREATE INDEX IF NOT EXISTS idx_player_job_tasks_player
  ON public.player_job_tasks (player_id);

-- ============================================================
-- 4) RPC: تنفيذ مهمة عمل
-- ============================================================
CREATE OR REPLACE FUNCTION do_job_task(p_task_id TEXT)
RETURNS JSONB AS $$
DECLARE
  v_pid    UUID := auth.uid();
  v_player public.players%ROWTYPE;
  v_task   public.job_tasks%ROWTYPE;
  v_last   TIMESTAMPTZ;
  v_mins   FLOAT;
  v_stat   INT;
BEGIN
  -- ── 1. تحميل اللاعب ──────────────────────────────────────────────────────
  SELECT * INTO v_player FROM public.players WHERE id = v_pid FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'اللاعب غير موجود');
  END IF;

  -- ── 2. تحميل المهمة ──────────────────────────────────────────────────────
  SELECT * INTO v_task FROM public.job_tasks WHERE id = p_task_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'المهمة غير موجودة');
  END IF;

  -- ── 3. تحقق أن اللاعب يعمل في الوظيفة الصحيحة ──────────────────────────
  IF v_player.job_id IS DISTINCT FROM v_task.job_id THEN
    RETURN jsonb_build_object('success', false, 'message', 'هذه المهمة لا تنتمي لوظيفتك الحالية');
  END IF;

  -- ── 4. السجن / المستشفى ─────────────────────────────────────────────────
  IF v_player.in_jail AND v_player.jail_until > now() THEN
    RETURN jsonb_build_object('success', false, 'message', 'لا يمكنك العمل وأنت في السجن');
  END IF;
  IF v_player.in_hospital AND v_player.hospital_until > now() THEN
    RETURN jsonb_build_object('success', false, 'message', 'لا يمكنك العمل وأنت في المستشفى');
  END IF;

  -- ── 5. فحص التبريد ──────────────────────────────────────────────────────
  SELECT last_done INTO v_last
    FROM public.player_job_tasks
   WHERE player_id = v_pid AND task_id = p_task_id;

  IF v_last IS NOT NULL THEN
    v_mins := EXTRACT(EPOCH FROM (now() - v_last)) / 60;
    IF v_mins < v_task.cooldown_minutes THEN
      RETURN jsonb_build_object(
        'success',      false,
        'message',      'هذه المهمة في فترة التبريد! بعد ' || ROUND(v_task.cooldown_minutes - v_mins, 1) || ' دقيقة',
        'minutes_left', ROUND(v_task.cooldown_minutes - v_mins, 1)
      );
    END IF;
  END IF;

  -- ── 6. فحص الطاقة ───────────────────────────────────────────────────────
  IF v_player.energy < v_task.energy_cost THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'طاقتك غير كافية! تحتاج ' || v_task.energy_cost || ' (لديك ' || v_player.energy || ')'
    );
  END IF;

  -- ── 7. فحص الإحصائية المطلوبة ───────────────────────────────────────────
  v_stat := CASE v_task.stat_key
    WHEN 'strength'     THEN v_player.strength
    WHEN 'fitness'      THEN v_player.fitness
    WHEN 'labor'        THEN v_player.labor
    WHEN 'intelligence' THEN v_player.intelligence
    ELSE 0
  END;

  IF v_stat < v_task.min_stat THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'إحصائيتك غير كافية! تحتاج ' || v_task.stat_key || ' >= ' || v_task.min_stat
                 || ' (لديك ' || v_stat || ')'
    );
  END IF;

  -- ── 8. تطبيق المكافآت ───────────────────────────────────────────────────
  UPDATE public.players SET
    cash         = cash + v_task.reward_cash,
    energy       = energy - v_task.energy_cost,
    job_points   = job_points + v_task.reward_jp,
    last_active  = now(),
    -- تدريب إحصائية العمل
    work_manual     = work_manual     + CASE WHEN v_task.stat_gain_key = 'work_manual'     THEN v_task.stat_gain ELSE 0 END,
    work_intel      = work_intel      + CASE WHEN v_task.stat_gain_key = 'work_intel'      THEN v_task.stat_gain ELSE 0 END,
    work_endurance  = work_endurance  + CASE WHEN v_task.stat_gain_key = 'work_endurance'  THEN v_task.stat_gain ELSE 0 END
  WHERE id = v_pid;

  -- ── 9. تسجيل التبريد ────────────────────────────────────────────────────
  INSERT INTO public.player_job_tasks (player_id, task_id, last_done)
  VALUES (v_pid, p_task_id, now())
  ON CONFLICT (player_id, task_id) DO UPDATE SET last_done = now();

  -- ── 10. سجل الأحداث ─────────────────────────────────────────────────────
  INSERT INTO public.events (player_id, type, title, description, money_change)
  VALUES (v_pid, 'job_task', '⚡ مهمة عمل', 'أنجزت: ' || v_task.name, v_task.reward_cash);

  RETURN jsonb_build_object(
    'success',     true,
    'message',     'أنجزت المهمة بنجاح! 💪',
    'reward_cash', v_task.reward_cash,
    'reward_jp',   v_task.reward_jp,
    'stat_gained', jsonb_build_object(
      'key',    v_task.stat_gain_key,
      'amount', v_task.stat_gain
    )
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 5) منح صلاحيات القراءة لـ anon/authenticated على الجدولين
-- ============================================================
GRANT SELECT ON public.job_tasks TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.player_job_tasks TO authenticated;

NOTIFY pgrst, 'reload schema';
