// =====================================================
// أدوات مساعدة مشتركة
// =====================================================

// تنسيق المبالغ المالية
function $$(n) {
  if (n === null || n === undefined) return '$0';
  return '$' + Number(n).toLocaleString('en');
}

// تنسيق الأرقام
function num(n) {
  if (n === null || n === undefined) return '0';
  return Number(n).toLocaleString('en');
}

// Toast notifications
let _toastCtr = 0;
function toast(msg, type = 'i', dur = 3500) {
  const icons = { s: '✅', e: '❌', w: '⚠️', i: 'ℹ️' };
  let c = document.getElementById('toasts');
  if (!c) {
    c = document.createElement('div');
    c.id = 'toasts';
    document.body.appendChild(c);
  }
  const t = document.createElement('div');
  t.className = `toast ${type}`;
  t.innerHTML = `<span>${icons[type] || 'ℹ️'}</span><span>${msg}</span>`;
  c.appendChild(t);
  setTimeout(() => {
    t.classList.add('out');
    setTimeout(() => t.remove(), 300);
  }, dur);
}

// Damage float animation
function dmgFloat(el, text, isPos = true) {
  const rect = el.getBoundingClientRect();
  const d = document.createElement('div');
  d.className = `dmg-float ${isPos ? 'pos' : 'neg'}`;
  d.textContent = text;
  d.style.left = (rect.left + rect.width / 2) + 'px';
  d.style.top = rect.top + 'px';
  document.body.appendChild(d);
  setTimeout(() => d.remove(), 1300);
}

// حساب نسبة البار
function pct(val, max) {
  if (!max) return 0;
  return Math.min(100, Math.max(0, (val / max) * 100));
}

// وقت متبقي
function timeLeft(until) {
  if (!until) return null;
  const diff = new Date(until) - new Date();
  if (diff <= 0) return null;
  const mins = Math.floor(diff / 60000);
  const secs = Math.floor((diff % 60000) / 1000);
  if (mins >= 60) {
    const h = Math.floor(mins / 60);
    const m = mins % 60;
    return `${h}س ${m}د`;
  }
  return mins > 0 ? `${mins}د ${secs}ث` : `${secs}ث`;
}

// تاريخ نسبي
function relTime(ts) {
  if (!ts) return '';
  const diff = (Date.now() - new Date(ts)) / 1000;
  if (diff < 60) return 'الآن';
  if (diff < 3600) return `${Math.floor(diff / 60)} دقيقة`;
  if (diff < 86400) return `${Math.floor(diff / 3600)} ساعة`;
  return `${Math.floor(diff / 86400)} يوم`;
}

// فتح مودال
function openModal(html) {
  closeModal();
  const ov = document.createElement('div');
  ov.className = 'overlay';
  ov.id = 'modal-overlay';
  ov.innerHTML = `<div class="modal">${html}</div>`;
  ov.addEventListener('click', e => { if (e.target === ov) closeModal(); });
  document.body.appendChild(ov);
}

function closeModal() {
  document.getElementById('modal-overlay')?.remove();
}

// مؤشر تحميل
function loading(container, text = 'جاري التحميل...') {
  if (typeof container === 'string') container = document.querySelector(container);
  if (container) container.innerHTML = `<div class="loading"><div class="spinner"></div><p>${text}</p></div>`;
}

// حالة فارغة
function emptyState(container, icon, text) {
  if (typeof container === 'string') container = document.querySelector(container);
  if (container) container.innerHTML = `<div class="empty"><div class="ei">${icon}</div><p>${text}</p></div>`;
}

// تشغيل مع تأكيد
async function confirm(msg, onYes) {
  openModal(`
    <div class="modal-hdr">
      <span class="modal-title">⚠️ تأكيد</span>
      <button class="modal-close" onclick="closeModal()">✕</button>
    </div>
    <p style="color:var(--text2);margin-bottom:18px;font-size:.9rem">${msg}</p>
    <div class="flex gap8">
      <button class="btn btn-r btn-full" id="confirm-yes">تأكيد</button>
      <button class="btn btn-ghost btn-full" onclick="closeModal()">إلغاء</button>
    </div>
  `);
  document.getElementById('confirm-yes').onclick = () => { closeModal(); onYes(); };
}

// تنسيق اسم الصفة
function statName(s) {
  const n = { strength: 'القوة', fitness: 'اللياقة', defense: 'الدفاع', labor: 'العمالة', intelligence: 'الذكاء' };
  return n[s] || s;
}

// تنسيق اسم المدينة
function cityName(c) {
  return CITIES[c]?.name || c;
}
