// =====================================================
// نظام الأصوات – Web Audio API (لا يحتاج ملفات صوتية)
// =====================================================

const AudioCtx = window.AudioContext || window.webkitAudioContext;
let _ctx = null;
let _muted = localStorage.getItem('muted') === 'true';

function getCtx() {
  if (!_ctx) _ctx = new AudioCtx();
  return _ctx;
}

// تشغيل نغمة مخصصة
function playTone(freq, type='sine', dur=0.15, vol=0.3, delay=0) {
  if (_muted) return;
  try {
    const ctx = getCtx();
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.type = type;
    osc.frequency.setValueAtTime(freq, ctx.currentTime + delay);
    gain.gain.setValueAtTime(vol, ctx.currentTime + delay);
    gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + delay + dur);
    osc.start(ctx.currentTime + delay);
    osc.stop(ctx.currentTime + delay + dur + 0.05);
  } catch(e) {}
}

// --- مكتبة الأصوات ---

// ✅ نجاح (صوت صاعد مثير)
function sfxSuccess() {
  playTone(400, 'sine', 0.1, 0.25);
  playTone(600, 'sine', 0.1, 0.25, 0.1);
  playTone(800, 'sine', 0.15, 0.3, 0.2);
}

// ❌ فشل (صوت هابط)
function sfxFail() {
  playTone(400, 'sawtooth', 0.12, 0.2);
  playTone(280, 'sawtooth', 0.12, 0.2, 0.1);
  playTone(200, 'sawtooth', 0.15, 0.25, 0.22);
}

// ⚔️ هجوم – طلقة/ضربة
function sfxAttack() {
  // صوت انفجار قصير
  const ctx = getCtx();
  if (_muted) return;
  try {
    const buf = ctx.createBuffer(1, ctx.sampleRate * 0.3, ctx.sampleRate);
    const data = buf.getChannelData(0);
    for (let i = 0; i < data.length; i++) {
      data[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / data.length, 2);
    }
    const src = ctx.createBufferSource();
    const gain = ctx.createGain();
    const filter = ctx.createBiquadFilter();
    src.buffer = buf;
    filter.type = 'bandpass';
    filter.frequency.value = 800;
    filter.Q.value = 0.5;
    src.connect(filter);
    filter.connect(gain);
    gain.connect(ctx.destination);
    gain.gain.setValueAtTime(0.6, ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.3);
    src.start();
  } catch(e) {}
}

// 🏆 انتصار في المعركة
function sfxWin() {
  [523, 659, 784, 1047].forEach((f, i) => playTone(f, 'sine', 0.18, 0.35, i * 0.12));
}

// 💀 خسارة في المعركة
function sfxLose() {
  [400, 350, 280, 220].forEach((f, i) => playTone(f, 'sawtooth', 0.18, 0.25, i * 0.1));
}

// ⛓️ سجن
function sfxJail() {
  playTone(220, 'square', 0.08, 0.3);
  playTone(220, 'square', 0.08, 0.3, 0.12);
  playTone(165, 'square', 0.2, 0.35, 0.24);
}

// 🏥 مشفى
function sfxHospital() {
  playTone(880, 'sine', 0.4, 0.15);
  playTone(880, 'sine', 0.4, 0.15, 0.5);
}

// 💰 ربح مال
function sfxMoney() {
  playTone(1047, 'sine', 0.08, 0.2);
  playTone(1319, 'sine', 0.08, 0.2, 0.09);
  playTone(1568, 'sine', 0.12, 0.25, 0.18);
}

// 🎉 ارتقاء مستوى
function sfxLevelUp() {
  const notes = [523, 659, 784, 1047, 1319, 1568, 2093];
  notes.forEach((f, i) => playTone(f, 'sine', 0.2, 0.4, i * 0.08));
}

// 🔫 شراء سلاح
function sfxBuyWeapon() {
  sfxAttack();
  setTimeout(() => playTone(600, 'sine', 0.1, 0.2), 300);
}

// 💼 قبض راتب
function sfxSalary() {
  [440, 550, 660, 880].forEach((f, i) => playTone(f, 'triangle', 0.15, 0.3, i * 0.08));
}

// 💪 تدريب ناجح
function sfxTrain() {
  playTone(300, 'triangle', 0.1, 0.25);
  playTone(400, 'triangle', 0.1, 0.25, 0.12);
  playTone(500, 'triangle', 0.15, 0.3, 0.25);
}

// 🔔 إشعار/رسالة
function sfxNotify() {
  playTone(880, 'sine', 0.08, 0.2);
  playTone(1320, 'sine', 0.1, 0.2, 0.1);
}

// 🔘 نقر زر
function sfxClick() {
  playTone(600, 'sine', 0.05, 0.15);
}

// ============ زر كتم الصوت ============
function toggleMute() {
  _muted = !_muted;
  localStorage.setItem('muted', _muted);
  const btn = document.getElementById('mute-btn');
  if (btn) btn.textContent = _muted ? '🔇' : '🔊';
  if (!_muted) sfxClick();
}

// إضافة زر الكتم للصفحة
function addMuteButton() {
  const btn = document.createElement('button');
  btn.id = 'mute-btn';
  btn.textContent = _muted ? '🔇' : '🔊';
  btn.title = 'تشغيل/إيقاف الصوت';
  btn.style.cssText = `
    position:fixed;bottom:18px;left:18px;z-index:9000;
    background:var(--card);border:1px solid var(--border);
    border-radius:50%;width:40px;height:40px;
    font-size:1.1rem;cursor:pointer;
    display:flex;align-items:center;justify-content:center;
    transition:all .2s;box-shadow:0 2px 10px rgba(0,0,0,.3);
  `;
  btn.addEventListener('click', toggleMute);
  btn.addEventListener('mouseenter', () => btn.style.transform = 'scale(1.1)');
  btn.addEventListener('mouseleave', () => btn.style.transform = '');
  document.body.appendChild(btn);
}

// تفعيل AudioContext عند أول تفاعل
document.addEventListener('click', () => {
  if (!_ctx) getCtx();
}, { once: true });

document.addEventListener('DOMContentLoaded', addMuteButton);
