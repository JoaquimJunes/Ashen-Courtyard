import * as THREE from './vendor/three/build/three.module.js';
import {GLTFLoader} from './vendor/three/examples/jsm/loaders/GLTFLoader.js';
import {OrbitControls} from './vendor/three/examples/jsm/controls/OrbitControls.js';
import {localURL} from './preview-media.js';

function disposeTree(root) {
  const geometries = new Set(), materials = new Set(), textures = new Set(), images = new Set();
  root.traverse(node => {
    if (node.geometry) geometries.add(node.geometry);
    for (const material of [node.material].flat().filter(Boolean)) {
      materials.add(material);
      for (const value of Object.values(material)) if (value?.isTexture) textures.add(value);
    }
    node.skeleton?.dispose();
  });
  for (const texture of textures) { if (texture.source?.data) images.add(texture.source.data); texture.dispose(); }
  for (const image of images) image.close?.();
  for (const geometry of geometries) geometry.dispose();
  for (const material of materials) material.dispose();
}

// Fetch all glTF dependencies ourselves, so close cancels every network request.
async function loadGLTF(url, signal) {
  const source = localURL(url), response = await fetch(source, {signal});
  if (!response.ok) throw Error(`Model preview is missing (${response.status}). Rebuild previews.`);
  const data = await response.arrayBuffer(), view = new DataView(data);
  let document, binary = null;
  if (data.byteLength >= 12 && view.getUint32(0, true) === 0x46546c67) {
    if (view.getUint32(4, true) !== 2 || view.getUint32(8, true) !== data.byteLength) throw Error('Invalid GLB header.');
    for (let offset = 12; offset + 8 <= data.byteLength;) {
      const length = view.getUint32(offset, true), type = view.getUint32(offset + 4, true); offset += 8;
      if (offset + length > data.byteLength) throw Error('Invalid GLB chunk.');
      if (type === 0x4e4f534a) document = JSON.parse(new TextDecoder().decode(data.slice(offset, offset + length)).replace(/\0+$/, ''));
      if (type === 0x004e4942) binary = data.slice(offset, offset + length);
      offset += length;
    }
  } else document = JSON.parse(new TextDecoder().decode(data));
  if (!document || document.asset?.version !== '2.0') throw Error('Only glTF 2.0 previews are supported.');
  const blobs = [], manager = new THREE.LoadingManager();
  const owned = new Set();
  const blobURL = value => { const valueURL = URL.createObjectURL(value); blobs.push(valueURL); owned.add(valueURL); return valueURL; };
  try {
    // Decompression extensions require extra decoders; fail instead of dropping geometry.
    const unsupported = (document.extensionsRequired || []).filter(name => !['KHR_materials_unlit','KHR_texture_transform','KHR_mesh_quantization','KHR_lights_punctual','KHR_materials_emissive_strength','KHR_materials_ior','KHR_materials_specular','KHR_materials_clearcoat','KHR_materials_transmission','KHR_materials_volume','KHR_materials_sheen','KHR_materials_iridescence','KHR_materials_anisotropy'].includes(name));
    if (unsupported.length) throw Error('Unsupported glTF extension: ' + unsupported.join(', '));
    for (const item of [...(document.buffers || []), ...(document.images || [])]) {
      if (item.uri) {
        if (/^data:/i.test(item.uri)) continue;
        const dependency = localURL(new URL(item.uri, source).href);
        const result = await fetch(dependency, {signal});
        if (!result.ok) throw Error('A model dependency is missing: ' + new URL(dependency).pathname);
        item.uri = blobURL(await result.blob());
      } else if ((document.buffers || []).includes(item) && binary) item.uri = blobURL(new Blob([binary]));
    }
    manager.setURLModifier(value => {
      if (owned.has(value) || /^data:/i.test(value) || (value.startsWith('blob:') && new URL(value).origin === location.origin)) return value;
      throw Error('Unprepared model dependency: ' + value);
    });
    const result = await new GLTFLoader(manager).parseAsync(JSON.stringify(document), '');
    if (signal.aborted) { (result.scenes || [result.scene]).forEach(disposeTree); throw new DOMException('Closed', 'AbortError'); }
    return result;
  } finally { blobs.forEach(value => URL.revokeObjectURL(value)); }
}

export async function createModel(host, descriptor, signal, onError) {
  let renderer;
  try { renderer = new THREE.WebGLRenderer({antialias: true, alpha: false}); }
  catch { throw Error('3D preview needs WebGL 2. Enable browser graphics acceleration or use another browser.'); }
  let model, mixer, action, controls, observer, disposed = false, skeleton;
  let otherScenes = [];
  const scene = new THREE.Scene();
  scene.background = new THREE.Color('#121914');
  const camera = new THREE.PerspectiveCamera(40, 1, 0.01, 10000);
  renderer.setPixelRatio(Math.min(devicePixelRatio || 1, 2));
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.domElement.setAttribute('aria-label', '3D animation viewport: drag to orbit, right-drag to pan, scroll to zoom');
  renderer.domElement.tabIndex = 0;
  host.append(renderer.domElement);
  const ambient = new THREE.HemisphereLight(0xf2eedf, 0x555d62, 2.5);
  const light = new THREE.DirectionalLight(0xffffff, 3); light.position.set(3, 6, 4);
  scene.add(ambient, light);
  let radius = 1, baseCenter = new THREE.Vector3(), rootBone, previousRoot, follow = false;
  const draw = () => { if (!disposed && model) renderer.render(scene, camera); };
  const dispose = () => {
    if (disposed) return; disposed = true;
    observer?.disconnect(); controls?.dispose(); mixer?.stopAllAction();
    if (model) mixer?.uncacheRoot(model);
    disposeTree(scene); otherScenes.forEach(disposeTree); otherScenes = []; renderer.dispose(); renderer.forceContextLoss(); renderer.domElement.remove();
  };
  signal.addEventListener('abort', dispose, {once: true});
  try {
    const gltf = await loadGLTF(descriptor.url, signal);
    if (disposed) { (gltf.scenes || [gltf.scene]).forEach(disposeTree); throw new DOMException('Closed', 'AbortError'); }
    model = gltf.scene; otherScenes = (gltf.scenes || []).filter(value => value !== model); scene.add(model);
    const box = new THREE.Box3().setFromObject(model), size = box.getSize(new THREE.Vector3());
    if (box.isEmpty() || !Number.isFinite(size.length())) throw Error('This preview has no visible model geometry.');
    baseCenter = box.getCenter(new THREE.Vector3()); radius = Math.max(size.length() / 2, 0.1);
    controls = new OrbitControls(camera, renderer.domElement); controls.target.copy(baseCenter);
    controls.minDistance = radius * 0.05; controls.maxDistance = radius * 40; controls.addEventListener('change', draw);
    const grid = new THREE.GridHelper(radius * 6, 20, 0x838c72, 0x3b463c);
    grid.position.set(baseCenter.x, box.min.y, baseCenter.z); grid.visible = false; scene.add(grid);
    skeleton = new THREE.SkeletonHelper(model); skeleton.visible = false; skeleton.material.depthTest = false; skeleton.renderOrder = 9; scene.add(skeleton);
    const candidates = []; model.traverse(node => { if (node.isBone) candidates.push(node); });
    rootBone = candidates.find(node => /^root$/i.test(node.name)) || candidates.find(node => /^(pelvis|hips|mixamorigHips)$/i.test(node.name)) || candidates[0] || model;
    function orient(view = 'reset') {
      const target = follow ? rootBone.getWorldPosition(new THREE.Vector3()) : baseCenter;
      controls.target.copy(target);
      const direction = view === 'front' ? [0, 0, 1] : view === 'side' ? [1, 0, 0] : view === 'back' ? [0, 0, -1] : [1, 0.55, 1.5];
      camera.position.copy(target).add(new THREE.Vector3(...direction).normalize().multiplyScalar(radius * 3.4));
      camera.near = Math.max(radius / 1000, 0.001); camera.far = radius * 1000; camera.updateProjectionMatrix(); controls.update(); draw();
    }
    function resize() { const {width, height} = host.getBoundingClientRect(); if (!width || !height || disposed) return; renderer.setSize(width, height, false); camera.aspect = width / height; camera.updateProjectionMatrix(); draw(); }
    observer = new ResizeObserver(resize); observer.observe(host);
    renderer.domElement.addEventListener('webglcontextlost', event => { event.preventDefault(); if (!disposed) onError(Error('Graphics context was lost. Close and reopen the preview.')); });
    renderer.domElement.addEventListener('keydown', event => {
      if (!['ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(event.key)) return;
      event.preventDefault();
      const offset = camera.position.clone().sub(controls.target), spherical = new THREE.Spherical().setFromVector3(offset);
      if (event.key === 'ArrowLeft') spherical.theta -= 0.12;
      if (event.key === 'ArrowRight') spherical.theta += 0.12;
      if (event.key === 'ArrowUp') spherical.phi -= 0.12;
      if (event.key === 'ArrowDown') spherical.phi += 0.12;
      spherical.makeSafe(); camera.position.copy(controls.target).add(offset.setFromSpherical(spherical)); controls.update();
    });
    mixer = new THREE.AnimationMixer(model);
    const adapter = {
      duration: 0,
      select(clip) {
        mixer.stopAllAction();
        const selected = gltf.animations[clip.index];
        if (!selected || selected.name !== (clip.export_name || clip.name || 'animation_' + clip.index)) throw Error('The prepared clip no longer matches its catalog entry. Rebuild previews.');
        if (!Number.isFinite(selected.duration) || selected.duration < 0) throw Error('Clip duration is invalid.');
        if (Math.abs(selected.duration - clip.duration) > 0.001) throw Error('Clip timing differs from the catalog. Rebuild previews.');
        // Reset the skeleton before switching, including bones untouched by the next clip.
        model.traverse(node => { if (node.isSkinnedMesh) node.skeleton.pose(); });
        action = mixer.clipAction(selected); action.reset().setLoop(THREE.LoopOnce, 1); action.clampWhenFinished = true; action.play();
        this.duration = selected.duration; previousRoot = null; this.seek(0);
      },
      seek(time) {
        if (!action || disposed) return;
        action.paused = false; action.enabled = true; mixer.setTime(Math.min(this.duration, Math.max(0, time))); model.updateMatrixWorld(true);
        const position = rootBone.getWorldPosition(new THREE.Vector3());
        if (follow && previousRoot) { const delta = position.clone().sub(previousRoot); camera.position.add(delta); controls.target.add(delta); controls.update(); }
        previousRoot = position; draw();
      },
      inspect(kind, enabled) {
        if (kind === 'bones') skeleton.visible = enabled;
        if (kind === 'grid') grid.visible = enabled;
        if (kind === 'follow') follow = enabled;
        if (kind === 'wireframe') model.traverse(node => { for (const material of [node.material].flat().filter(Boolean)) material.wireframe = enabled; });
        draw();
      },
      // Offline thumbnail capture only: fit the evaluated pose, never translate
      // its root or advance time to choose a more attractive frame.
      snapshotFirstFrame(clip) {
        follow = false; skeleton.visible = false; grid.visible = false;
        model.traverse(node => { for (const material of [node.material].flat().filter(Boolean)) material.wireframe = false; });
        this.select(clip);
        const originalRoot = rootBone.getWorldPosition(new THREE.Vector3());
        model.traverse(node => { if (node.isSkinnedMesh) node.skeleton.update(); });
        const bounds = new THREE.Box3().setFromObject(model, true);
        if (bounds.isEmpty() || !Number.isFinite(bounds.getSize(new THREE.Vector3()).length())) throw Error('The first pose has no finite visible bounds.');
        const target = bounds.getCenter(new THREE.Vector3());
        const direction = new THREE.Vector3(1, 0.55, 1.5).normalize();
        const right = new THREE.Vector3().crossVectors(camera.up, direction).normalize();
        const up = new THREE.Vector3().crossVectors(direction, right).normalize();
        const vertical = Math.tan(THREE.MathUtils.degToRad(camera.fov / 2)), horizontal = vertical * camera.aspect;
        let distance = 0;
        for (const x of [bounds.min.x, bounds.max.x]) for (const y of [bounds.min.y, bounds.max.y]) for (const z of [bounds.min.z, bounds.max.z]) {
          const delta = new THREE.Vector3(x, y, z).sub(target), depth = delta.dot(direction);
          distance = Math.max(distance, depth + Math.abs(delta.dot(right)) * 1.12 / horizontal, depth + Math.abs(delta.dot(up)) * 1.12 / vertical);
        }
        distance = Math.max(distance, 0.1);
        controls.target.copy(target); camera.position.copy(target).addScaledVector(direction, distance);
        camera.near = Math.max(distance / 10000, 0.00001); camera.far = distance * 10000;
        camera.updateProjectionMatrix(); controls.update(); draw();
        return {png: renderer.domElement.toDataURL('image/png'), time: action.time,
          root_before: originalRoot.toArray(), root_after: rootBone.getWorldPosition(new THREE.Vector3()).toArray(),
          bounds: {min: bounds.min.toArray(), max: bounds.max.toArray()}, clip: action.getClip().name};
      },
      orient, dispose,
      // Read-only diagnostics used by integration tests; no game state is exposed.
      diagnostics: () => ({bones: candidates.length, clip: action?.getClip().name, root: rootBone.getWorldPosition(new THREE.Vector3()).toArray(), renderer: renderer.info.memory})
    };
    resize(); orient(); return adapter;
  } catch (error) { dispose(); throw error; }
}
