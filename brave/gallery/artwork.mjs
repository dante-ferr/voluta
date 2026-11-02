// Image files stay in this browser profile, outside the extension's managed files.
const DATABASE = 'voluta-gallery';
const STORE = 'preferences';
export const IMAGE_LIMIT = 64 * 1024 * 1024;
const IMAGE_TYPES = new Set(['image/png', 'image/jpeg', 'image/webp', 'image/avif', 'image/gif']);

export function validateImage(file) {
  if (!file || !IMAGE_TYPES.has(file.type)) throw new Error('Choose a PNG, JPEG, WebP, AVIF or GIF image.');
  if (!file.size || file.size > IMAGE_LIMIT) throw new Error('Choose an image smaller than 64 MiB.');
}

function database() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DATABASE, 1);
    request.onupgradeneeded = () => request.result.createObjectStore(STORE);
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

export async function readArtwork() {
  const db = await database();
  try {
    return await new Promise((resolve, reject) => {
      const transaction = db.transaction(STORE, 'readonly');
      const request = transaction.objectStore(STORE).get('artwork');
      request.onsuccess = () => resolve(request.result || { mode: 'wallpaper' });
      transaction.onerror = () => reject(transaction.error);
    });
  } finally { db.close(); }
}

export async function writeArtwork(value) {
  if (!['wallpaper', 'custom'].includes(value.mode)) throw new Error('Choose an artwork source.');
  if (value.image) validateImage(value.image);
  if (value.mode === 'custom' && !value.image) throw new Error('Choose an image first.');
  const db = await database();
  try {
    await new Promise((resolve, reject) => {
      const transaction = db.transaction(STORE, 'readwrite');
      transaction.objectStore(STORE).put(value, 'artwork');
      transaction.oncomplete = resolve;
      transaction.onabort = () => reject(transaction.error || new Error('Artwork could not be saved.'));
      transaction.onerror = () => reject(transaction.error);
    });
  } finally { db.close(); }
}
