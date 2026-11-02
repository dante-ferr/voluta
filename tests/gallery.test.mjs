import test from 'node:test';
import assert from 'node:assert/strict';
import { address, shortcut, safeLinks, DEFAULT_LINKS, framePath } from '../brave/gallery/logic.mjs';

test('addresses reject executable schemes, credentials and search phrases', () => {
  for (const value of ['javascript:alert(1)', 'data:text/html,hi', 'file:///etc/passwd', 'https://user:secret@example.com', 'a search phrase']) {
    assert.equal(address(value), null, value);
  }
  assert.equal(address('example.com/path'), 'https://example.com/path');
  assert.equal(address('localhost:3000'), 'http://localhost:3000/');
  assert.equal(address('example.com:8080'), 'https://example.com:8080/');
});

test('shortcut storage is bounded and restores only supported destinations', () => {
  assert.deepEqual(safeLinks(null), DEFAULT_LINKS);
  assert.deepEqual(safeLinks([]), []);
  assert.equal(safeLinks(Array(20).fill({name:'Example',url:'example.com'})).length, 12);
  assert.deepEqual(safeLinks([{name:'Unsafe',url:'javascript:alert(1)'}, ...DEFAULT_LINKS]), DEFAULT_LINKS);
  assert.deepEqual(shortcut('  Example  ', 'example.com'), {name:'Example',url:'https://example.com/'});
  assert.throws(() => shortcut('', 'example.com'));
  assert.throws(() => shortcut('a'.repeat(41), 'example.com'));
});

test('frames adapt to the panel bounds with a separate inset surround', () => {
  assert.match(framePath(500, 400), /^M27 1H473/);
  assert.match(framePath(500, 400, 8), /^M34 8H466/);
  assert.match(framePath(300, 700), /V673/);
});

test('custom artwork accepts supported local images with a bounded size', async () => {
  const { validateImage, IMAGE_LIMIT } = await import('../brave/gallery/artwork.mjs');
  for (const type of ['image/png', 'image/jpeg', 'image/webp', 'image/avif', 'image/gif']) {
    assert.doesNotThrow(() => validateImage({type, size: 128}));
  }
  for (const file of [null, {type:'text/html',size:100}, {type:'image/svg+xml',size:100}, {type:'image/png',size:0}, {type:'image/png',size:IMAGE_LIMIT+1}]) {
    assert.throws(() => validateImage(file));
  }
});
