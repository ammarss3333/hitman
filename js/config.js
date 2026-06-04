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

// أنواع الأسلحة (type = عمود DB)
const WEAPON_TYPES = {
  melee:  { name: 'أسلحة بيضاء', icon: '🗡️' },
  pistol: { name: 'مسدسات',       icon: '🔫' },
  rifle:  { name: 'بنادق',        icon: '🎯' },
  armor:  { name: 'دروع',         icon: '🛡️' }
};

// فئات الأسلحة (category = عمود DB موسع)
const WEAPON_CATEGORIES = {
  melee:   { name: 'أسلحة بيضاء', label: 'بيضاء',  icon: '🗡️',  color: '#e67e22' },
  pistol:  { name: 'مسدسات',       label: 'مسدس',   icon: '🔫',  color: '#3498db' },
  shotgun: { name: 'بنادق خردق',   label: 'خردق',   icon: '🎯',  color: '#9b59b6' },
  smg:     { name: 'رشاشات خفيفة', label: 'رشاش',   icon: '🔫',  color: '#1abc9c' },
  rifle:   { name: 'بنادق هجومية', label: 'هجومي',  icon: '🔫',  color: '#e74c3c' },
  sniper:  { name: 'قناصة',         label: 'قناص',   icon: '🎯',  color: '#f39c12' },
  armor:   { name: 'دروع',          label: 'درع',    icon: '🛡️', color: '#2ecc71' }
};

// نوع المدى
const RANGE_LABELS = {
  close:  { name: 'قريب',  color: '#e74c3c' },
  medium: { name: 'متوسط', color: '#f39c12' },
  long:   { name: 'بعيد',  color: '#2ecc71' }
};

// SVG silhouettes للأسلحة (data URIs مصغرة، أبيض/رمادي على شفاف)
const WEAPON_SVGS = {
  pistol: `data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 60 30'%3E%3Cpath d='M8 18 L8 10 L40 10 L40 8 L48 8 L52 10 L52 14 L44 14 L44 18 L36 18 L36 22 L20 22 L18 28 L12 28 L10 22 L8 22 Z' fill='%23ccc' stroke='%23888' stroke-width='1'/%3E%3Crect x='40' y='10' width='12' height='4' rx='1' fill='%23aaa'/%3E%3C/svg%3E`,
  rifle:  `data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 60 30'%3E%3Crect x='2' y='13' width='56' height='4' rx='1' fill='%23ccc' stroke='%23888' stroke-width='1'/%3E%3Crect x='4' y='10' width='30' height='3' rx='1' fill='%23aaa'/%3E%3Crect x='18' y='17' width='8' height='7' rx='1' fill='%23bbb'/%3E%3Crect x='26' y='14' width='4' height='6' rx='1' fill='%23999'/%3E%3C/svg%3E`,
  shotgun:`data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 60 30'%3E%3Crect x='2' y='12' width='52' height='6' rx='2' fill='%23ccc' stroke='%23888' stroke-width='1'/%3E%3Crect x='6' y='9' width='26' height='3' rx='1' fill='%23aaa'/%3E%3Crect x='14' y='18' width='10' height='7' rx='1' fill='%23bbb'/%3E%3Ccircle cx='55' cy='15' r='3' fill='%23999'/%3E%3C/svg%3E`,
  smg:    `data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 60 30'%3E%3Crect x='4' y='12' width='44' height='5' rx='1' fill='%23ccc' stroke='%23888' stroke-width='1'/%3E%3Crect x='6' y='9' width='20' height='3' rx='1' fill='%23aaa'/%3E%3Crect x='20' y='17' width='6' height='8' rx='1' fill='%23bbb'/%3E%3Crect x='28' y='14' width='3' height='5' rx='1' fill='%23999'/%3E%3Crect x='44' y='11' width='12' height='3' rx='1' fill='%23aaa'/%3E%3C/svg%3E`,
  sniper: `data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 60 30'%3E%3Crect x='1' y='13' width='58' height='4' rx='1' fill='%23ccc' stroke='%23888' stroke-width='1'/%3E%3Crect x='4' y='10' width='35' height='3' rx='1' fill='%23aaa'/%3E%3Crect x='18' y='17' width='7' height='8' rx='1' fill='%23bbb'/%3E%3Crect x='8' y='7' width='4' height='9' rx='1' fill='%23999'/%3E%3Crect x='10' y='5' width='8' height='3' rx='1' fill='%23888'/%3E%3C/svg%3E`,
  melee:  `data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 60 30'%3E%3Cpath d='M30 2 L34 20 L30 28 L26 20 Z' fill='%23ccc' stroke='%23888' stroke-width='1'/%3E%3Crect x='27' y='20' width='6' height='6' rx='1' fill='%23aaa'/%3E%3Cpath d='M26 20 L20 14 M34 20 L40 14' stroke='%23bbb' stroke-width='1.5'/%3E%3C/svg%3E`,
  armor:  `data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 60 30'%3E%3Cpath d='M15 4 L45 4 L50 10 L50 22 L30 28 L10 22 L10 10 Z' fill='none' stroke='%23ccc' stroke-width='2'/%3E%3Cpath d='M22 10 L38 10 L40 18 L30 22 L20 18 Z' fill='%23aaa' stroke='%23888' stroke-width='1'/%3E%3C/svg%3E`
};
