// Media adapters are loaded only after an explicit preview request.
export function localURL(value) {
  const url = new URL(value, document.baseURI);
  if (!['http:', 'https:'].includes(url.protocol) || url.origin !== location.origin || url.username || url.password)
    throw Error('Preview dependencies must be served by this local tracker.');
  return url.href;
}

export async function createVideo(host, descriptor, signal, onError) {
  const video = document.createElement('video');
  video.playsInline = true;
  video.preload = 'metadata';
  video.setAttribute('aria-label', 'Animation video');
  host.append(video);
  const dispose = () => { video.pause(); video.removeAttribute('src'); video.load(); video.remove(); };
  signal.addEventListener('abort', dispose, {once: true});
  try {
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => finish(Error('Video loading timed out. Close and retry.')), 30000);
      const abort = () => finish(new DOMException('Closed', 'AbortError'));
      function finish(error) {
        clearTimeout(timeout);
        video.onloadedmetadata = video.onerror = null;
        signal.removeEventListener('abort', abort);
        error ? reject(error) : resolve();
      }
      video.onloadedmetadata = () => finish();
      video.onerror = () => finish(Error('This video is missing or its format is not supported by your browser.'));
      signal.addEventListener('abort', abort, {once: true});
      video.src = localURL(descriptor.url);
      video.load();
    });
    if (!Number.isFinite(video.duration) || video.duration <= 0) throw Error('Video has no valid duration.');
    video.onerror = () => { if (!signal.aborted) onError(Error('Video playback failed: the file is missing or its codec is unsupported.')); };
    return {
      duration: video.duration, nativeClock: true,
      seek: time => { const target = Math.min(time, video.duration); if (Math.abs(video.currentTime - target) > 0.0005) video.currentTime = target; },
      play: async rate => { video.playbackRate = rate; await video.play(); },
      pause: () => video.pause(), time: () => video.currentTime,
      rate: rate => { video.playbackRate = rate; },
      dispose
    };
  } catch (error) { dispose(); throw error; }
}

export async function createSequence(host, descriptor, signal, onError) {
  const sequence = descriptor.sequence;
  const response = await fetch(localURL(sequence.frames_url), {signal});
  if (!response.ok) throw Error('The frame sequence manifest is missing. Rebuild previews.');
  const manifest = await response.json();
  const frames = manifest.frames;
  const fps = Number(manifest.fps ?? sequence.fps);
  if (!Array.isArray(frames) || !frames.length || !Number.isFinite(fps) || fps <= 0 || fps > 240)
    throw Error('This frame sequence has invalid timing or no frames.');
  const urls = frames.map(localURL);
  const canvas = document.createElement('canvas');
  canvas.setAttribute('aria-label', 'Transparent animation frames');
  host.append(canvas);
  const ctx = canvas.getContext('2d'), cache = new Map();
  let wanted = -1, shown = -1, loading = false, disposed = false, lastError = null;
  // Eight decoded frames cap memory independently of sequence length.
  async function bitmap(index) {
    if (cache.has(index)) {
      const value = cache.get(index); cache.delete(index); cache.set(index, value); return value;
    }
    const result = await fetch(urls[index], {signal});
    if (!result.ok) throw Error(`Frame ${index + 1}/${frames.length} is missing (${result.status}).`);
    const image = await createImageBitmap(await result.blob());
    if (disposed || signal.aborted) { image.close(); throw new DOMException('Closed', 'AbortError'); }
    cache.set(index, image);
    while (cache.size > 8) { const oldest = cache.keys().next().value; cache.get(oldest).close(); cache.delete(oldest); }
    return image;
  }
  async function paint() {
    if (loading || disposed) return;
    loading = true;
    try {
      while (!disposed && shown !== wanted) {
        const index = wanted, image = await bitmap(index);
        if (disposed) break;
        // Show the completed frame even if playback has advanced; then catch up.
        if (canvas.width !== image.width || canvas.height !== image.height) { canvas.width = image.width; canvas.height = image.height; }
        ctx.clearRect(0, 0, canvas.width, canvas.height); ctx.drawImage(image, 0, 0); shown = index;
      }
    } catch (error) { lastError = error; if (error.name !== 'AbortError') onError(error); }
    finally { loading = false; }
  }
  const adapter = {
    duration: frames.length / fps, fps, frameCount: frames.length,
    seek(time) { wanted = Math.min(frames.length - 1, Math.max(0, Math.floor(time * fps + 1e-7))); return paint(); },
    dispose() { disposed = true; for (const value of cache.values()) value.close(); cache.clear(); canvas.remove(); }
  };
  signal.addEventListener('abort', () => adapter.dispose(), {once: true});
  await adapter.seek((sequence.start_frame || 0) / fps);
  if (lastError) { adapter.dispose(); throw lastError; }
  return adapter;
}
