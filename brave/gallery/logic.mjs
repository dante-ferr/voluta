export const DEFAULT_LINKS = [
  { name: 'Bookmarks', url: 'chrome://bookmarks/' },
  { name: 'History', url: 'chrome://history/' },
  { name: 'Downloads', url: 'chrome://downloads/' }
];

export function address(value) {
  const text = value.trim();
  if (!text || /\s/.test(text)) return null;
  const explicit = /^[a-z][a-z\d+.-]*:\/\//i.test(text);
  const local = /^(localhost|127\.0\.0\.1)(:|\/|$)/.test(text);
  const candidate = explicit ? text : local ? 'http://' + text : 'https://' + text;
  try {
    const url = new URL(candidate);
    if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password) return null;
    if (!explicit && !url.hostname.includes('.') && url.hostname !== 'localhost') return null;
    return url.href;
  } catch { return null; }
}

export function shortcut(name, value) {
  const clean = name.trim();
  const url = address(value);
  if (!clean || clean.length > 40 || !url) throw new Error('Enter a name and a valid web address.');
  return { name: clean, url };
}

export function safeLinks(value) {
  if (!Array.isArray(value)) return DEFAULT_LINKS.map(link => ({ ...link }));
  return value.slice(0, 12).filter(link => link && typeof link.name === 'string' && link.name.trim() &&
    typeof link.url === 'string' && (address(link.url) || DEFAULT_LINKS.some(item => item.url === link.url)))
    .map(link => ({ name: link.name.slice(0, 40), url: address(link.url) || link.url }));
}

export function framePath(width, height, inset = 1) {
  const left = inset, top = inset, right = width - inset, bottom = height - inset;
  const cut = 26, step = 9;
  return `M${left + cut} ${top}H${right - cut}V${top + step}H${right - step}V${top + cut}H${right}V${bottom - cut}H${right - step}V${bottom - step}H${right - cut}V${bottom}H${left + cut}V${bottom - step}H${left + step}V${bottom - cut}H${left}V${top + cut}H${left + step}V${top + step}H${left + cut}Z`;
}
