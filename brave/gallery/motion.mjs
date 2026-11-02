// A floating picture frame, with dust caught in a moving projector light.
export function mountArtworkMotion(artwork) {
  const canvas = artwork.querySelector('canvas');
  const context = canvas.getContext('2d');
  if (!context) return;
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const pointer = matchMedia('(hover: hover) and (pointer: fine)');
  let visible = true, frame = 0, last = 0, previous = 0, time = 0;
  let width = 1, height = 1, x = 0, y = 0, targetX = 0, targetY = 0;
  let accent, foreground;
  const particles = Array.from({length: 52}, () => ({
    x: Math.random(), y: Math.random(), radius: .55 + Math.random() * 1.25,
    speed: .012 + Math.random() * .02, phase: Math.random() * Math.PI * 2
  }));

  function colors() {
    const style = getComputedStyle(document.documentElement);
    accent = style.getPropertyValue('--accent').trim();
    foreground = style.getPropertyValue('--fg').trim();
  }
  colors();
  document.addEventListener('voluta-palette-change', colors);

  new ResizeObserver(entries => {
    const bounds = entries[0].contentRect;
    width = bounds.width;
    height = bounds.height;
    const scale = Math.min(devicePixelRatio || 1, 1.5);
    canvas.width = Math.round(width * scale);
    canvas.height = Math.round(height * scale);
    context.setTransform(scale, 0, 0, scale, 0, 0);
  }).observe(canvas.parentElement);

  function pose() {
    artwork.style.setProperty('--tilt-x', (-y * 3.5).toFixed(3) + 'deg');
    artwork.style.setProperty('--tilt-y', (x * 4).toFixed(3) + 'deg');
    artwork.style.setProperty('--light-x', (50 + x * 36).toFixed(2) + '%');
    artwork.style.setProperty('--light-y', (50 + y * 36).toFixed(2) + '%');
  }

  function tick(now) {
    frame = 0;
    if (document.hidden || reduced.matches || !visible) return;
    frame = requestAnimationFrame(tick);
    if (now - last < 1000 / 30) return;
    const delta = previous ? Math.min((now - previous) / 1000, .06) : 0;
    previous = last = now;
    time += delta;
    const ease = 1 - Math.exp(-delta * 8);
    x += (targetX - x) * ease;
    y += (targetY - y) * ease;
    pose();
    context.clearRect(0, 0, width, height);
    const beam = ((time / 9) % 1) * 1.8 - .4;
    particles.forEach((particle, index) => {
      particle.y = (particle.y - delta * particle.speed + 1) % 1;
      const px = (particle.x + Math.sin(time * .24 + particle.phase) * .035) * width;
      const py = particle.y * height;
      const distance = Math.abs(px / width - beam + (py / height - .5) * .24);
      const glow = Math.max(0, 1 - distance * 4);
      context.globalAlpha = .12 + glow * .7;
      context.fillStyle = index % 3 ? foreground : accent;
      context.beginPath();
      context.arc(px + x * 9, py + y * 6, particle.radius * (1 + glow * .5), 0, Math.PI * 2);
      context.fill();
    });
    context.globalAlpha = 1;
  }

  function resetPointer() { targetX = targetY = 0; }
  function update() {
    cancelAnimationFrame(frame);
    frame = previous = last = 0;
    resetPointer();
    if (reduced.matches) {
      x = y = 0;
      pose();
      context.clearRect(0, 0, width, height);
    }
    if (!document.hidden && !reduced.matches && visible) frame = requestAnimationFrame(tick);
  }
  artwork.addEventListener('pointermove', event => {
    if (!pointer.matches || reduced.matches || event.pointerType === 'touch') return;
    const rect = artwork.getBoundingClientRect();
    targetX = Math.max(-1, Math.min(1, (event.clientX - rect.left) / rect.width * 2 - 1));
    targetY = Math.max(-1, Math.min(1, (event.clientY - rect.top) / rect.height * 2 - 1));
  });
  artwork.addEventListener('pointerleave', resetPointer);
  window.addEventListener('blur', resetPointer);
  pointer.addEventListener('change', resetPointer);
  reduced.addEventListener('change', update);
  document.addEventListener('visibilitychange', update);
  new IntersectionObserver(entries => {
    visible = entries[0].isIntersecting;
    artwork.classList.toggle('artwork-out-of-view', !visible);
    update();
  }).observe(artwork);
}
