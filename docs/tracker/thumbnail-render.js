// Explicit offline capture page. The gallery never imports or executes this module.
import {createModel} from './preview-model.js';
import {localURL} from './preview-media.js';
const host = document.getElementById('frame');
let adapter, controller, failure;
function dispose() { controller?.abort(); adapter?.dispose(); adapter = null; host.replaceChildren(); }
function loaded(element) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(Error('First-frame decoding timed out.')), 30000);
    element.addEventListener(element instanceof HTMLVideoElement ? 'loadeddata' : 'load', () => { clearTimeout(timeout); resolve(); }, {once:true});
    element.addEventListener('error', () => { clearTimeout(timeout); reject(Error(element.error?.message || 'Cannot decode the first frame.')); }, {once:true});
  });
}
window.ThumbnailRenderer = {
  dispose,
  async load(descriptor) {
    dispose(); controller = new AbortController(); failure = null;
    adapter = await createModel(host, descriptor, controller.signal, error => { failure = error; });
  },
  model(clip) {
    if (failure) throw failure;
    if (!adapter) throw Error('Load the model before capturing a clip.');
    return {...adapter.snapshotFirstFrame(clip), empty:false};
  },
  async media(job) {
    dispose();
    const video = job.descriptor.kind === 'video';
    const element = document.createElement(video ? 'video' : 'img');
    if (video) { element.preload = 'auto'; element.muted = true; element.playsInline = true; }
    const promise = loaded(element); element.src = localURL(video ? job.descriptor.url : job.image);
    try {
      if (video) element.load();
      await promise;
      const width = video ? element.videoWidth : element.naturalWidth, height = video ? element.videoHeight : element.naturalHeight;
      if (!width || !height) throw Error('The first frame has no dimensions.');
      // loadeddata exposes the decoded initial frame at time zero; never play
      // or seek forward to obtain a more visible poster.
      if (video && element.currentTime !== 0) throw Error('The decoder did not provide time zero.');
      const canvas = document.createElement('canvas'); canvas.width = 384; canvas.height = 256; host.append(canvas);
      const context = canvas.getContext('2d', {willReadFrequently:true});
      const scale = Math.min(384 / width, 256 / height), w = width * scale, h = height * scale;
      context.drawImage(element, (384-w)/2, (256-h)/2, w, h);
      const pixels = context.getImageData(0, 0, 384, 256).data;
      let empty = true;
      for (let i=0; i<pixels.length; i+=4) if (pixels[i+3] && (pixels[i] > 1 || pixels[i+1] > 1 || pixels[i+2] > 1)) { empty = false; break; }
      return {png:canvas.toDataURL('image/png'), empty, time:0, source_width:width, source_height:height};
    } finally { if (video) { element.pause(); element.removeAttribute('src'); element.load(); } }
  }
};
