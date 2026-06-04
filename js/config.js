// =====================================================
// إعدادات Supabase - استبدل القيم بقيمك الخاصة
// =====================================================
// 1. اذهب إلى https://supabase.com وأنشئ مشروعاً مجانياً
// 2. Project Settings > API > انسخ URL و anon key
// 3. استبدل القيمتين أدناه

const SUPABASE_URL = 'https://YOUR_PROJECT_ID.supabase.co';
const SUPABASE_ANON_KEY = 'YOUR_ANON_KEY_HERE';

// عند الانتهاء من إعداد Supabase، أيضاً:
// - شغّل supabase_schema.sql في SQL Editor
// - فعّل Email Auth في Authentication > Providers

const supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: {
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: true
  }
});

// أسماء المدن
const CITIES = {
  beirut:   { name: 'بيروت',    flag: '🇱🇧', desc: 'عاصمة الجريمة' },
  amman:    { name: 'عمّان',    flag: '🇯🇴', desc: 'مدينة الصفقات' },
  damascus: { name: 'دمشق',     flag: '🇸🇾', desc: 'عش الدبابير' },
  cairo:    { name: 'القاهرة',  flag: '🇪🇬', desc: 'المدينة التي لا تنام' },
  dubai:    { name: 'دبي',      flag: '🇦🇪', desc: 'جنة الأثرياء' }
};

// أنواع الأسلحة
const WEAPON_TYPES = {
  melee:  { name: 'أسلحة بيضاء', icon: '🗡️' },
  pistol: { name: 'مسدسات',       icon: '🔫' },
  rifle:  { name: 'بنادق',        icon: '🎯' },
  armor:  { name: 'دروع',         icon: '🛡️' }
};
