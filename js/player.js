// =====================================================
// إدارة بيانات اللاعب والتنقل
// =====================================================

let _player = null;
let _unreadCount = 0;

// تحميل بيانات اللاعب
async function loadPlayer(force = false) {
  if (_player && !force) return _player;
  try {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return null;

    // تجديد الطاقة
    await supabase.rpc('regen_energy');

    const { data, error } = await supabase
      .from('players')
      .select('*, gangs!gang_id(name, tag)')
      .eq('id', user.id)
      .single();

    if (error) throw error;
    _player = data;
    return data;
  } catch (e) {
    console.error('loadPlayer:', e);
    return null;
  }
}

// التحقق من تسجيل الدخول
async function requireAuth() {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) {
    window.location.href = BASE_PATH + 'index.html';
    return false;
  }
  return true;
}

// تسجيل الخروج
async function logout() {
  await supabase.auth.signOut();
  window.location.href = BASE_PATH + 'index.html';
}

// تحميل رصيد الرسائل
async function loadUnread() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return 0;
  const { count } = await supabase.from('messages').select('*', { count: 'exact', head: true })
    .eq('to_id', user.id).eq('read', false);
  _unreadCount = count || 0;
  return _unreadCount;
}

// قاعدة المسار
const BASE_PATH = (() => {
  const p = window.location.pathname;
  if (p.includes('/game/')) return '../';
  return '';
})();

// بناء الشريط الجانبي
async function buildNav(activePage) {
  const auth = await requireAuth();
  if (!auth) return;

  const player = await loadPlayer();
  if (!player) { logout(); return; }

  // حالة اللاعب
  let statusHtml = '';
  const now = new Date();
  if (player.in_jail && new Date(player.jail_until) > now) {
    const t = timeLeft(player.jail_until);
    statusHtml = `<div class="sb-status jail">⛓️ في السجن (${t})</div>`;
  } else if (player.in_hospital && new Date(player.hospital_until) > now) {
    const t = timeLeft(player.hospital_until);
    statusHtml = `<div class="sb-status hospital">🏥 في المشفى (${t})</div>`;
  } else {
    statusHtml = `<div class="sb-status online">🟢 نشط</div>`;
  }

  const unread = await loadUnread();

  const pages = [
    { icon: '🏠', label: 'الصفحة الرئيسية', href: 'home.html',        id: 'home' },
    { icon: '🌆', label: 'المدينة',           href: 'city.html',        id: 'city' },
    { icon: '🔪', label: 'الجرائم',           href: 'crimes.html',      id: 'crimes' },
    { icon: '💪', label: 'النادي الرياضي',    href: 'gym.html',         id: 'gym' },
    { icon: '💼', label: 'العمل',             href: 'work.html',        id: 'work' },
    { icon: '🏦', label: 'البنك',             href: 'bank.html',        id: 'bank' },
    { icon: '🔫', label: 'المستودع',          href: 'inventory.html',   id: 'inventory' },
    { icon: '💊', label: 'الصيدلية',          href: 'pharmacy.html',    id: 'pharmacy' },
    { icon: '🎰', label: 'الكازينو',          href: 'casino.html',      id: 'casino' },
    { icon: '⛓️', label: 'السجن',             href: 'jail.html',        id: 'jail' },
    { icon: '💀', label: 'العصابات',          href: 'gangs.html',       id: 'gangs' },
    { icon: '✉️', label: 'البريد',             href: 'messages.html',    id: 'messages', badge: unread > 0 ? unread : 0 },
    { icon: '📋', label: 'الأحداث',           href: 'events.html',      id: 'events' },
    { icon: '🏆', label: 'المشاهير',          href: 'leaderboard.html', id: 'leaderboard' },
    { icon: '🔍', label: 'البحث',             href: 'search.html',      id: 'search' },
  ];

  const cityInfo = CITIES[player.city] || { name: player.city, flag: '🌐' };
  const hp = pct(player.health, player.max_health);
  const en = pct(player.energy, player.max_energy);
  const wp = pct(player.willpower, player.max_willpower);

  const navHTML = `
    <div class="sb-head">
      <div class="logo">قاتل <span>مأجور</span></div>
      <div class="sb-player">
        <div class="sb-avatar">${player.avatar}</div>
        <div class="sb-name">${player.username}</div>
        <div class="sb-lvl">مستوى ${player.level} · ${cityInfo.flag} ${cityInfo.name}</div>
        <div class="sb-bars">
          <div class="sb-bar-row">❤️ <div class="sb-bar"><div class="sb-bar-fill hp" style="width:${hp}%"></div></div><span class="sb-bar-val">${player.health}/${player.max_health}</span></div>
          <div class="sb-bar-row">⚡ <div class="sb-bar"><div class="sb-bar-fill en" style="width:${en}%"></div></div><span class="sb-bar-val">${player.energy}/${player.max_energy}</span></div>
          <div class="sb-bar-row">🔥 <div class="sb-bar"><div class="sb-bar-fill wp" style="width:${wp}%"></div></div><span class="sb-bar-val">${player.willpower}/${player.max_willpower}</span></div>
        </div>
        <div class="sb-cash">💰 ${$$(player.cash)}</div>
      </div>
    </div>
    <nav class="sidebar-nav">
      <div class="nav-section">اللعبة</div>
      ${pages.map(p => `
        <a class="nav-link${activePage === p.id ? ' active' : ''}" href="${p.href}">
          <span class="ni">${p.icon}</span>
          ${p.label}
          ${p.badge ? `<span class="nb">${p.badge}</span>` : ''}
        </a>
      `).join('')}
    </nav>
    <div class="sb-foot">
      ${statusHtml}
      <div class="mt8 flex gap8">
        <button class="btn btn-ghost btn-sm" style="flex:1" onclick="window.location.href='profile.html?id=${player.id}'">👤 ملفي</button>
        <button class="btn btn-ghost btn-sm" onclick="logout()">خروج</button>
      </div>
    </div>
  `;

  // حقن في الشريط الجانبي
  const sidebar = document.getElementById('sidebar');
  if (sidebar) sidebar.innerHTML = navHTML;

  // زر الجوال
  document.getElementById('mob-toggle')?.addEventListener('click', () => {
    sidebar?.classList.toggle('open');
    document.getElementById('mob-overlay')?.classList.toggle('show');
  });
  document.getElementById('mob-overlay')?.addEventListener('click', () => {
    sidebar?.classList.remove('open');
    document.getElementById('mob-overlay')?.classList.remove('show');
  });

  return player;
}
