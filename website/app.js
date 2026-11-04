const descriptions = {touchpad: 'Linkpad touchpad screen with a large gesture area and mouse buttons', remote: 'Linkpad remote screen with directional controls and volume buttons', keyboard: 'Linkpad keyboard screen with text input and shortcut keys'};
const screen = document.querySelector('#screen');
document.querySelectorAll('[data-mode]').forEach(button => button.addEventListener('click', () => {
  const mode = button.dataset.mode;
  screen.src = `assets/${mode}.png`;
  screen.alt = descriptions[mode];
  document.querySelectorAll('[data-mode]').forEach(item => item.setAttribute('aria-pressed', String(item === button)));
}));
fetch('release.json').then(response => { if (!response.ok) throw new Error('Release metadata unavailable'); return response.json(); }).then(release => {
  document.querySelectorAll('[data-version]').forEach(item => { item.textContent = release.version; });
  document.querySelectorAll('[data-download]').forEach(link => {
    const value = release.downloads?.[link.dataset.download];
    if (!value) return;
    const url = new URL(value);
    if (url.protocol === 'https:' && url.hostname === 'github.com' && url.pathname.startsWith('/shirishkoirala/linkpad/releases/download/')) link.href = url.href;
  });
}).catch(() => { /* The HTML contains working release links for offline previews. */ });
