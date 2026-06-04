// =====================================================
// إعدادات Supabase - استبدل القيم بقيمك الخاصة
// =====================================================
// 1. اذهب إلى https://supabase.com وأنشئ مشروعاً مجانياً
// 2. Project Settings > API > انسخ URL و anon key
// 3. استبدل القيمتين أدناه

const SUPABASE_URL = 'https://slhnvntvgsozplgepagr.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_Sb_7ImVHv_R_f-4FQiFbtw_4jO0gRY2';

// مكتبة Supabase تنشئ متغيراً عاماً اسمه supabase.
// نأخذ نسخة من المكتبة أولاً ثم نستبدل window.supabase بالعميل.
// لا نستخدم "const supabase" لأنه يتعارض مع المتغير العام ويُعطّل الملف بالكامل.
var _sbLib = window.supabase;
window.supabase = _sbLib.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: {
    storage: window.sessionStorage,
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: true
  }
});
// الآن أي إشارة إلى "supabase" في باقي الملفات تشير إلى window.supabase (العميل).

// أسماء المدن
const CITIES = {
  beirut:   { name: 'بيروت',    flag: '🇱🇧', desc: 'عاصمة الجريمة',        bonus: 'crime_success',  bonusPct: 10, bonusLabel: '+10% نجاح الجرائم',  travelCost: 0,    specialty: 'القاعدة الرئيسية' },
  amman:    { name: 'عمّان',    flag: '🇯🇴', desc: 'مدينة الصفقات',        bonus: 'shop_discount',  bonusPct: 15, bonusLabel: '-15% أسعار المتجر',  travelCost: 1500, specialty: 'أسواق رخيصة' },
  damascus: { name: 'دمشق',     flag: '🇸🇾', desc: 'عش الدبابير',          bonus: 'attack_power',   bonusPct: 10, bonusLabel: '+10% قوة الهجوم',    travelCost: 2500, specialty: 'عقود خطيرة' },
  cairo:    { name: 'القاهرة',  flag: '🇪🇬', desc: 'المدينة التي لا تنام', bonus: 'exp_boost',      bonusPct: 20, bonusLabel: '+20% خبرة',          travelCost: 2000, specialty: 'فرص لا تنتهي' },
  dubai:    { name: 'دبي',      flag: '🇦🇪', desc: 'جنة الأثرياء',         bonus: 'bank_interest',  bonusPct: 5,  bonusLabel: '+ فائدة بنكية أعلى', travelCost: 5000, specialty: 'مال وفير' }
};

// أنواع الأسلحة
const WEAPON_TYPES = {
  melee:  { name: 'أسلحة بيضاء', icon: '🗡️' },
  pistol: { name: 'مسدسات',       icon: '🔫' },
  rifle:  { name: 'بنادق',        icon: '🎯' },
  armor:  { name: 'دروع',         icon: '🛡️' }
};
