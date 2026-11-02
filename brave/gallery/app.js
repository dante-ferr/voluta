import { DEFAULT_LINKS, address, shortcut, safeLinks, framePath } from './logic.mjs';

const $ = id => document.getElementById(id);
let links = DEFAULT_LINKS;
let paletteVersion = '';
let wallpaperVersion = '';
const extension = globalThis.chrome?.storage?.local;

async function loadLinks() {
  try {
    const value = extension ? (await chrome.storage.local.get('links')).links : JSON.parse(localStorage.getItem('voluta.gallery.links'));
    links = safeLinks(value);
  } catch { links = safeLinks(null); }
  renderLinks();
}

async function saveLinks() {
  if (extension) await chrome.storage.local.set({ links });
  else localStorage.setItem('voluta.gallery.links', JSON.stringify(links));
  renderLinks();
}

function navigate(url) {
  if (globalThis.chrome?.tabs?.update) chrome.tabs.update({ url });
  else location.assign(url);
}

function renderLinks() {
  const list = $('shortcuts');
  const editable = $('editable-shortcuts');
  list.replaceChildren();
  editable.replaceChildren();
  links.forEach((link, index) => {
    const anchor = document.createElement('a');
    anchor.className = 'place';
    anchor.textContent = link.name;
    anchor.href = link.url;
    anchor.addEventListener('click', event => {
      if (event.button === 0 && !event.metaKey && !event.ctrlKey && !event.shiftKey) {
        event.preventDefault();
        navigate(link.url);
      }
    });
    list.append(anchor);
    const row = document.createElement('li');
    const label = document.createElement('span');
    label.textContent = link.name;
    const remove = document.createElement('button');
    remove.type = 'button';
    remove.className = 'quiet-button';
    remove.textContent = 'Remove';
    remove.setAttribute('aria-label', 'Remove ' + link.name);
    remove.addEventListener('click', async () => { links.splice(index, 1); await saveLinks(); });
    row.append(label, remove);
    editable.append(row);
  });
}

function clock() {
  const now = new Date();
  $('clock').textContent = new Intl.DateTimeFormat(undefined, { hour: '2-digit', minute: '2-digit', hour12: false }).format(now);
  $('clock').dateTime = now.toISOString();
  $('year').textContent = now.getFullYear();
  $('date').textContent = new Intl.DateTimeFormat(undefined, { weekday: 'long', day: 'numeric', month: 'long' }).format(now);
}

async function refreshPalette() {
  if (document.hidden) return;
  try {
    const response = await fetch('generated/palette.json', { cache: 'no-store' });
    if (!response.ok) return;
    const packet = await response.json();
    if (packet.version === paletteVersion) return;
    if (!packet.colors || !Object.values(packet.colors).every(color => /^#[\da-f]{6}$/i.test(color))) return;
    for (const key of ['bg', 'fg', 'accent', 'muted', 'line', 'raised']) {
      if (!packet.colors[key]) return;
    }
    for (const [key, value] of Object.entries(packet.colors)) {
      if (['bg', 'fg', 'accent', 'muted', 'line', 'raised'].includes(key)) document.documentElement.style.setProperty('--' + key, value);
    }
    if (packet.wallpaper && /^wallpaper\.(jpg|jpeg|png|webp|avif|gif)$/.test(packet.wallpaper)) {
      $('wallpaper').hidden = false;
      if (packet.wallpaperVersion !== wallpaperVersion) {
        const image = $('wallpaper');
        image.src = 'generated/' + packet.wallpaper + '?v=' + encodeURIComponent(packet.wallpaperVersion);
        wallpaperVersion = packet.wallpaperVersion;
      }
    } else {
      $('wallpaper').hidden = true;
    }
    for (const ornament of document.querySelectorAll('.ornament')) {
      const path = ornament.getAttribute('src').split('?')[0];
      ornament.src = path + '?v=' + encodeURIComponent(packet.version);
    }
    paletteVersion = packet.version;
  } catch { /* Keep the current artwork while palette publication is in flight. */ }
}

$('search-form').addEventListener('submit', event => {
  event.preventDefault();
  const text = $('query').value.trim();
  if (!text) return;
  const url = address(text);
  if (url) navigate(url);
  else if (globalThis.chrome?.search?.query) chrome.search.query({ text, disposition: 'CURRENT_TAB' });
  else $('page-status').textContent = 'Search uses your browser’s default engine when installed as a New Tab page.';
});
$('edit-shortcuts').addEventListener('click', () => { $('shortcut-error').textContent = ''; $('shortcut-dialog').showModal(); });
$('close-dialog').addEventListener('click', () => $('shortcut-dialog').close());
$('shortcut-form').addEventListener('submit', async event => {
  event.preventDefault();
  try {
    if (links.length >= 12) throw new Error('Keep up to 12 shortcuts. Remove one before adding another.');
    const added = shortcut($('shortcut-name').value, $('shortcut-url').value);
    links.push(added);
    await saveLinks();
    $('shortcut-name').value = '';
    $('shortcut-url').value = '';
    $('shortcut-error').textContent = 'Shortcut added.';
  } catch (error) { $('shortcut-error').textContent = error.message; }
});

const artwork = document.querySelector('.artwork');
new ResizeObserver(() => {
  const { width, height } = artwork.getBoundingClientRect();
  const frame = artwork.querySelector('svg');
  frame.setAttribute('viewBox', `0 0 ${width} ${height}`);
  frame.querySelector('.outer-edge').setAttribute('d', framePath(width, height));
  frame.querySelector('.travelling-edge').setAttribute('d', framePath(width, height));
  frame.querySelector('.inner-edge').setAttribute('d', framePath(width, height, 8));
}).observe(artwork);

function visibility() {
  document.body.classList.toggle('page-hidden', document.hidden);
  if (!document.hidden) { clock(); refreshPalette(); }
}
document.addEventListener('visibilitychange', visibility);
if (extension && chrome.storage.onChanged) chrome.storage.onChanged.addListener((changes, area) => {
  if (area === 'local' && changes.links) { links = safeLinks(changes.links.newValue); renderLinks(); }
});
visibility();
clock();
loadLinks();
setInterval(clock, 30000);
setInterval(refreshPalette, 4000);
