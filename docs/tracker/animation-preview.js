/* One disposable viewer, independent of editable tracker state. */
(() => {
  'use strict';
  const $ = id => document.getElementById('animation-' + id), dialog = $('dialog');
  let generation = 0, controller, player, entry, descriptor, clips = [], selected = null;
  let time = 0, duration = 0, playing = false, previousTick = 0, raf = 0, returnFocus, details, playAttempt = 0, loopRestart = false;
  const controls = () => dialog.querySelectorAll('[data-playback]');
  const format = value => Number(value || 0).toFixed(2) + ' s';
  function setMessage(text, error = false) { $('message').textContent = text; $('message').classList.toggle('error', error); }
  function sync() {
    $('play').textContent = playing ? 'Pause' : 'Play'; $('play').setAttribute('aria-pressed', String(playing));
    $('timeline').max = String(duration || 1); $('timeline').value = String(time);
    $('time').textContent = format(time) + ' / ' + format(duration);
    $('timeline').setAttribute('aria-valuetext', $('time').textContent);
    if (player?.frameCount) $('frame').textContent = `Frame ${Math.min(player.frameCount, Math.floor(time * player.fps + 1e-7) + 1)} / ${player.frameCount}`;
  }
  function pause() { playAttempt++; loopRestart = false; playing = false; cancelAnimationFrame(raf); raf = 0; player?.pause?.(); sync(); }
  function fail(error) {
    if (error?.name === 'AbortError') return;
    pause(); setMessage(error.message || String(error), true);
    controls().forEach(control => control.disabled = true);
  }
  function tick(now) {
    if (!playing || !player) return;
    if (loopRestart) { raf = requestAnimationFrame(tick); return; }
    const delta = Math.max(0, Math.min((now - previousTick) / 1000, 0.25)); previousTick = now;
    time = player.nativeClock ? player.time() : time + delta * Number($('speed').value);
    if (time >= duration - 1e-7) {
      if ($('loop').checked) {
        time = duration ? time % duration : 0; player.seek(time);
        if (player.nativeClock) {
          loopRestart = true; const token = generation, attempt = playAttempt;
          player.play(Number($('speed').value)).then(() => {
            if (token === generation && attempt === playAttempt) loopRestart = false;
          }, error => {
            if (token === generation && attempt === playAttempt) { loopRestart = false; fail(error); }
          });
        }
      }
      else { time = duration; if (!player.nativeClock) player.seek(time); pause(); return; }
    } else if (!player.nativeClock) player.seek(time);
    sync(); raf = requestAnimationFrame(tick);
  }
  async function play() {
    if (!player || !duration || $('play').disabled) return;
    const token = generation;
    if (playing) { pause(); return; }
    if (time >= duration) { time = 0; player.seek(time); }
    const attempt = ++playAttempt; playing = true; sync();
    try {
      if (player.play) await player.play(Number($('speed').value));
      if (token !== generation || attempt !== playAttempt) return;
      if (document.hidden) { pause(); return; }
      playing = true; previousTick = performance.now(); sync(); raf = requestAnimationFrame(tick);
    } catch (error) { if (token === generation && attempt === playAttempt) fail(error); }
  }
  function seek(value) { if (!player) return; pause(); time = Math.max(0, Math.min(duration, value)); player.seek(time); sync(); }
  function selectClip(id) {
    if (!player) return;
    const clip = clips.find(c => c.id === id);
    if (!clip) return;
    try {
      pause(); player.select(clip); selected = clip; duration = player.duration; time = 0;
      $('loop').checked = !!clip.loop; $('clips').value = clip.id;
      $('current').textContent = clip.name || 'Unnamed clip ' + (clip.index + 1); $('play').disabled = duration === 0; setMessage(duration === 0 ? 'Static pose · this clip has no elapsed motion.' : 'Ready · individual prepared clip.'); sync();
    } catch (error) { fail(error); }
  }
  function filterClips() {
    const tokens = $('search').value.toLocaleLowerCase().replace(/[_-]+/g, ' ').split(/\s+/).filter(Boolean);
    $('clips').replaceChildren();
    for (const clip of clips) {
      const text = clip.name.toLocaleLowerCase().replace(/[_-]+/g, ' ');
      if (!tokens.every(token => text.includes(token))) continue;
      $('clips').add(new Option((clip.name || 'Unnamed clip ' + (clip.index + 1)) + ' · ' + format(clip.duration), clip.id));
    }
    if (selected) $('clips').value = selected.id;
    $('clip-count').textContent = `${$('clips').options.length} / ${clips.length} clips`;
  }
  function release() {
    generation++; pause(); controller?.abort(); controller = null; player?.dispose(); player = null;
    $('viewport').replaceChildren(); selected = null; clips = []; entry = null;
  }
  function close() { release(); if (dialog.open) dialog.close(); }
  dialog.addEventListener('close', () => {
    // A queued native close event can arrive after a new preview opens.
    // It must never dispose that new generation or steal its focus.
    if (dialog.open) return;
    release(); if (returnFocus?.isConnected) returnFocus.focus({preventScroll: true});
  });
  $('close').onclick = close;
  $('details').onclick = () => { const callback = details; close(); callback?.(); };
  $('play').onclick = play; $('restart').onclick = () => seek(0);
  $('timeline').oninput = () => seek(Number($('timeline').value));
  $('speed').onchange = () => player?.rate?.(Number($('speed').value));
  $('previous-frame').onclick = () => seek((Math.floor(time * player.fps + 1e-7) - 1) / player.fps);
  $('next-frame').onclick = () => seek((Math.floor(time * player.fps + 1e-7) + 1) / player.fps);
  $('clips').onchange = () => selectClip($('clips').value); $('search').oninput = filterClips;
  for (const button of dialog.querySelectorAll('[data-camera]')) button.onclick = () => player?.orient(button.dataset.camera);
  for (const checkbox of dialog.querySelectorAll('[data-inspect]')) checkbox.onchange = () => player?.inspect(checkbox.dataset.inspect, checkbox.checked);
  $('background').onchange = () => { $('viewport').dataset.background = $('background').value; };
  dialog.addEventListener('keydown', event => {
    if (event.code === 'Space' && !['INPUT','SELECT','TEXTAREA','BUTTON'].includes(event.target.tagName)) { event.preventDefault(); play(); }
  });
  document.addEventListener('visibilitychange', () => { if (document.hidden) pause(); });
  window.addEventListener('pagehide', close);

  async function open(asset, clipName, onDetails) {
    const focused = document.activeElement;
    release(); returnFocus = focused; entry = asset; descriptor = asset.preview; details = onDetails;
    const token = generation; controller = new AbortController(); const signal = controller.signal;
    $('title').textContent = asset.title + ' — Animation preview';
    $('source').textContent = asset.path || '';
    $('model').textContent = descriptor?.model ? 'Model: ' + descriptor.model : '';
    const provenance = descriptor?.provenance;
    $('provenance').textContent = provenance?.label || ''; $('provenance').hidden = !provenance?.label;
    $('provenance').title = provenance ? [provenance.source_path, provenance.target_rig, provenance.profile_id, provenance.profile_version].filter(Boolean).join(' · ') : '';
    $('current').textContent = ''; $('search').value = ''; $('clips').replaceChildren(); $('clip-count').textContent = '';
    time = duration = 0; $('speed').value = '1'; $('loop').checked = false; $('frame').textContent = '';
    $('background').value = 'checker'; $('viewport').dataset.background = descriptor?.kind === 'sequence' ? 'checker' : 'dark';
    dialog.querySelector('.animation-layout').classList.toggle('animation-media', descriptor?.kind !== 'model');
    for (const checkbox of dialog.querySelectorAll('[data-inspect]')) checkbox.checked = false;
    controls().forEach(control => control.disabled = true);
    $('clip-picker').hidden = descriptor?.kind !== 'model'; $('inspection').hidden = descriptor?.kind !== 'model';
    $('sequence-controls').hidden = descriptor?.kind !== 'sequence'; $('background-label').hidden = descriptor?.kind !== 'sequence';
    $('help').textContent = descriptor?.kind === 'model' ? 'Drag to orbit · right-drag to pan · scroll to zoom · arrow keys on viewport to orbit' : 'Scrub the timeline to inspect a moment. Playback does not change your tracking notes.';
    sync(); setMessage('Loading preview…');
    if (!dialog.open) dialog.showModal(); $('close').focus();
    if (location.protocol === 'file:') { setMessage('Start the tracker at http://127.0.0.1:8765/docs/tracker/ to play animations. Static-file browsing remains available.', true); return; }
    if (asset.missing || !descriptor || descriptor.status !== 'ready') { setMessage(descriptor?.reason || 'Preview unavailable. Prepare the preview files and rebuild the catalog.', true); return; }
    try {
      const reportError = error => { if (token === generation) fail(error); };
      let loaded;
      if (descriptor.kind === 'model') {
        const module = await import('./preview-model.js'); if (token !== generation) return;
        loaded = await module.createModel($('viewport'), descriptor, signal, reportError);
      } else {
        const module = await import('./preview-media.js'); if (token !== generation) return;
        if (descriptor.kind === 'video') loaded = await module.createVideo($('viewport'), descriptor, signal, reportError);
        else if (descriptor.kind === 'sequence') loaded = await module.createSequence($('viewport'), descriptor, signal, reportError);
        else throw Error('This preview format is not supported.');
      }
      if (token !== generation) { loaded.dispose(); return; }
      player = loaded; controls().forEach(control => control.disabled = false);
      if (descriptor.kind === 'model') {
        clips = descriptor.clips || []; if (!clips.length) throw Error('No prepared clips are available.');
        filterClips(); selectClip((clips.find(clip => clip.name === clipName) || clips[0]).id);
      } else {
        duration = player.duration; time = descriptor.kind === 'sequence' ? (descriptor.sequence.start_frame || 0) / player.fps : 0;
        player.seek(time); $('current').textContent = descriptor.kind === 'sequence' ? 'Documented frame sequence' : 'Existing video';
        setMessage('Ready · existing animation.'); sync();
      }
    } catch (error) { if (token === generation) fail(error); }
  }
  window.ArtPreview = {open, close, diagnostics: () => ({open: dialog.open, playing, time, duration, kind: descriptor?.kind, ...(player?.diagnostics?.() || {})})};
})();
