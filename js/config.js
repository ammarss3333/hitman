// =====================================================
// إعدادات Supabase - استبدل القيم بقيمك الخاصة
// =====================================================
// 1. اذهب إلى https://supabase.com وأنشئ مشروعاً مجانياً
// 2. Project Settings > API > انسخ URL و anon key
// 3. استبدل القيمتين أدناه

const SUPABASE_URL = 'https://slhnvntvgsozplgepagr.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_Sb_7ImVHv_R_f-4FQiFbtw_4jO0gRY2';

// إنشاء العميل وتخزينه على window لتجنب تعارض الأسماء
// نستخدم sessionStorage بدلاً من localStorage لتجنب حجب المتصفح
window.supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: {
    storage: window.sessionStorage,
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: true
  }
});

// اختصار مريح
const supabase = window.supabase;

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
