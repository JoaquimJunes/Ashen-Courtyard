// Real asset/browser acceptance. Tracker writes are isolated in a temporary directory.
const {chromium} = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const {pathToFileURL} = require('node:url');
const {spawn} = require('node:child_process');
const root = path.resolve(__dirname, '..');
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'ashen-animation-preview-'));
const artifacts = path.join(root, '.artifacts/tracker');
const gpuArgs = ['--no-sandbox', '--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader', '--disable-accelerated-video-decode'];
let browser, server, page, url;
const errors = [], groups = [];

async function group(name, run) {
  await run(); groups.push(name); console.log('PASS ' + name);
}
const diagnostics = () => page.evaluate(() => ArtPreview.diagnostics());
async function ready() {
  await page.waitForFunction(() => {
    const message = document.getElementById('animation-message');
    return message.classList.contains('error') || message.textContent.startsWith('Static pose') || (!document.getElementById('animation-play').disabled && message.textContent.startsWith('Ready'));
  }, null, {timeout: 45000});
  assert.equal(await page.locator('#animation-message').evaluate(n => n.classList.contains('error')), false,
    await page.locator('#animation-message').textContent());
}
async function open(asset, clipName) {
  await page.evaluate(({asset, clipName}) => { void ArtPreview.open(asset, clipName); }, {asset, clipName});
  await ready();
}
async function close() {
  await page.click('#animation-close');
  await page.waitForFunction(() => !document.getElementById('animation-dialog').open && document.getElementById('animation-viewport').children.length === 0);
  assert.equal((await diagnostics()).playing, false);
}
async function seek(time) {
  await page.locator('#animation-timeline').evaluate((node, value) => { node.value = String(value); node.dispatchEvent(new Event('input', {bubbles: true})); }, time);
}
function assetWhere(catalog, predicate, label) {
  const asset = catalog.art.find(a => predicate(a) && a.preview?.status === 'ready');
  assert.ok(asset, 'Prepared catalog entry required: ' + label);
  return asset;
}

(async () => {
  try {
    const catalog = JSON.parse(fs.readFileSync(path.join(root, 'docs/tracker/catalog.json'), 'utf8'));
    const ual = assetWhere(catalog, a => a.path === 'assets/third_party/quaternius/UAL1_Standard.glb', 'UAL1');
    const rm = assetWhere(catalog, a => a.path.endsWith('/ual2/UAL2_Standard_RM.glb'), 'UAL2 root motion');
    const sequence = assetWhere(catalog, a => a.preview?.kind === 'sequence' && a.preview.sequence.start_frame === 0, 'first UI frame');
    const video = assetWhere(catalog, a => a.preview?.kind === 'video', 'existing video');
    const walk = ual.preview.clips.find(c => /^Walk(?:_Loop)?$/.test(c.name));
    assert.ok(walk, 'Actual Walk clip must be catalogued');
    server = spawn('python3', [path.join(__dirname, 'serve_progress_tracker.py'), '--port', '0', '--state', path.join(temp, 'tracking.json')], {cwd: root, stdio: ['ignore', 'pipe', 'pipe']});
    server.stderr.on('data', () => {});
    url = await new Promise((resolve, reject) => {
      let output = ''; const timer = setTimeout(() => reject(Error('Server startup timeout')), 10000);
      server.stdout.on('data', data => { output += data; const match = output.match(/http:\/\/127\.0\.0\.1:\d+/); if (match) { clearTimeout(timer); resolve(match[0]); } });
      server.once('exit', code => { clearTimeout(timer); reject(Error('Server exited ' + code)); });
    });
    browser = await chromium.launch({headless: true, executablePath: process.env.CHROMIUM_PATH, args: gpuArgs});
    const context = await browser.newContext({viewport: {width: 1440, height: 1000}});
    page = await context.newPage(); page.on('pageerror', error => errors.push(error.message));
    const requests = []; page.on('request', request => requests.push({url: request.url(), method: request.method()}));
    await page.goto(url + '/docs/tracker/');
    await page.waitForFunction(() => document.getElementById('save-state').textContent === 'Saved to project');
    const stateBefore = await page.request.get(url + '/api/tracker').then(r => r.json());

    await group('Search stays metadata-only; clip button opens the chosen UAL clip paused', async () => {
      await page.click('[data-book=art]'); await page.click('#clear-filters');
      await page.fill('#search', 'UAL1 Standard');
      const card = page.locator('.entry').filter({has: page.locator('p.path', {hasText: ual.path})});
      await card.locator('h2 button').click();
      assert.ok(!requests.some(r => /\.(glb|gltf|fbx|tres)(?:\?|$)/i.test(r.url)), 'Search/detail must not fetch animation files');
      await page.locator('#detail').getByRole('button', {name: 'Preview clip ' + walk.name, exact: true}).click();
      await ready();
      let d = await diagnostics(); assert.equal(d.playing, false); assert.equal(d.time, 0); assert.equal(d.clip, walk.export_name || walk.name); assert.ok(d.bones >= 65);
      assert.equal(await page.locator('#animation-viewport canvas').count(), 1);
      assert.ok(d.renderer.geometries > 0, 'A real skinned mesh must be rendered');
    });

    await group('Play, pause, seek, rate, loop, restart and switching clips', async () => {
      await page.click('#animation-play'); await page.waitForFunction(() => ArtPreview.diagnostics().time > 0.12);
      await page.click('#animation-play'); const paused = (await diagnostics()).time;
      await page.waitForTimeout(100); assert.equal((await diagnostics()).time, paused);
      await seek(0.2); assert.ok(Math.abs((await diagnostics()).time - 0.2) < 0.002);
      await page.selectOption('#animation-speed', '2'); await page.click('#animation-play');
      await page.waitForFunction(() => ArtPreview.diagnostics().time > 0.35); await page.click('#animation-play');
      const duration = (await diagnostics()).duration;
      await page.locator('#animation-loop').check(); await seek(duration - 0.03); await page.click('#animation-play');
      await page.waitForFunction(() => { const d = ArtPreview.diagnostics(); return d.playing && d.time < d.duration / 2; });
      await page.locator('#animation-loop').uncheck(); await seek(duration - 0.03); await page.click('#animation-play');
      await page.waitForFunction(() => !ArtPreview.diagnostics().playing); assert.equal((await diagnostics()).time, duration);
      await page.click('#animation-restart'); assert.equal((await diagnostics()).time, 0);
      await page.click('#animation-play');
      const idle = ual.preview.clips.find(c => /^Idle(?:_Loop)?$/.test(c.name)); assert.ok(idle);
      await page.selectOption('#animation-clips', idle.id);
      const d = await diagnostics(); assert.equal(d.clip, idle.export_name || idle.name); assert.equal(d.time, 0); assert.equal(d.playing, false);
      await page.fill('#animation-search', 'sword idle');
      assert.ok(await page.locator('#animation-clips option').count() > 0);
      assert.ok((await page.locator('#animation-clips').textContent()).toLowerCase().includes('sword_idle'));
      await page.fill('#animation-search', '');
    });

    await group('Bones, wireframe, grid, camera and responsive rendered screenshots', async () => {
      fs.mkdirSync(artifacts, {recursive: true});
      const before = await page.locator('#animation-viewport').screenshot();
      for (const name of ['bones', 'wireframe', 'grid']) await page.locator(`[data-inspect=${name}]`).check();
      await page.click('[data-camera=side]');
      const after = await page.locator('#animation-viewport').screenshot();
      assert.notDeepEqual(after, before, 'Inspection controls must change rendered pixels');
      await page.locator('#animation-viewport canvas').focus(); await page.keyboard.press('ArrowLeft');
      await page.click('[data-camera=front]'); await page.click('[data-camera=back]'); await page.click('[data-camera=reset]');
      await page.screenshot({path: path.join(artifacts, 'animation-preview-desktop.png')});
      await page.setViewportSize({width: 390, height: 850});
      assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
      assert.ok(await page.locator('#animation-dialog').evaluate(n => n.scrollWidth <= n.clientWidth));
      await page.screenshot({path: path.join(artifacts, 'animation-preview-mobile.png')});
      await page.setViewportSize({width: 1440, height: 1000});
    });

    await group('Hidden page pauses and close releases the viewport without editing metadata', async () => {
      await page.click('#animation-play');
      await page.evaluate(() => { Object.defineProperty(document, 'hidden', {configurable: true, value: true}); document.dispatchEvent(new Event('visibilitychange')); });
      assert.equal((await diagnostics()).playing, false);
      await page.evaluate(() => { delete document.hidden; document.dispatchEvent(new Event('visibilitychange')); });
      assert.equal((await diagnostics()).playing, false, 'Visibility restore must not autoplay');
      await close();
      assert.equal(await page.locator('#detail').isVisible(), true);
      assert.equal(await page.evaluate(() => document.activeElement.getAttribute('aria-label')), 'Preview clip ' + walk.name);
      await page.click('#close-detail');
      assert.deepEqual(await page.request.get(url + '/api/tracker').then(r => r.json()), stateBefore);
    });

    await group('Root motion is preserved with and without camera following', async () => {
      const clip = rm.preview.clips.find(c => /ClimbUp.*1m/i.test(c.name)); assert.ok(clip);
      await open(rm, clip.name); const start = (await diagnostics()).root;
      await seek(Math.min(0.5, (await diagnostics()).duration * 0.6)); const end = (await diagnostics()).root;
      assert.ok(Math.hypot(...end.map((v, i) => v - start[i])) > 0.02, 'Root-motion clip must move its root');
      await page.locator('[data-inspect=follow]').check(); await seek(0);
      await seek(Math.min(0.5, (await diagnostics()).duration * 0.6));
      const followed = (await diagnostics()).root; assert.ok(Math.hypot(...followed.map((v, i) => v - end[i])) < 1e-6, 'Camera follow must not rewrite root motion');
      await close();
    });

    await group('A zero-duration pose remains inspectable without playback', async () => {
      // Static vendor poses may be removed from the project. This routed fixture
      // contains one triangle and one constant key, and never writes game assets.
      const fixtureURL = url + '/docs/tracker/static-pose-fixture.gltf';
      const bytes = Buffer.from(new Float32Array([0,0,0, 1,0,0, 0,1,0, 0, 0,0,0]).buffer);
      const gltf = {asset:{version:'2.0'},scene:0,scenes:[{nodes:[0]}],nodes:[{name:'Fixture',mesh:0}],
        meshes:[{primitives:[{attributes:{POSITION:0}}]}],
        buffers:[{byteLength:bytes.length,uri:'data:application/octet-stream;base64,'+bytes.toString('base64')}],
        bufferViews:[{buffer:0,byteOffset:0,byteLength:36},{buffer:0,byteOffset:36,byteLength:4},{buffer:0,byteOffset:40,byteLength:12}],
        accessors:[{bufferView:0,componentType:5126,count:3,type:'VEC3',min:[0,0,0],max:[1,1,0]},
          {bufferView:1,componentType:5126,count:1,type:'SCALAR',min:[0],max:[0]},
          {bufferView:2,componentType:5126,count:1,type:'VEC3'}],
        animations:[{name:'StaticPose',samplers:[{input:1,output:2,interpolation:'LINEAR'}],channels:[{sampler:0,target:{node:0,path:'translation'}}]}]};
      await page.route(fixtureURL, route => route.fulfill({contentType:'model/gltf+json',body:JSON.stringify(gltf)}));
      const clip = {id:'StaticPose',name:'StaticPose',index:0,duration:0,loop:false};
      const asset = {id:'art:test-static-pose',title:'Static pose fixture',path:'docs/tracker/static-pose-fixture.gltf',
        preview:{status:'ready',kind:'model',url:fixtureURL,model:'Disposable fixture',clips:[clip]}};
      await open(asset, clip.name);
      assert.equal((await diagnostics()).duration, 0); assert.equal((await diagnostics()).playing, false);
      assert.equal(await page.locator('#animation-play').isDisabled(), true);
      assert.match(await page.locator('#animation-message').textContent(), /Static pose/);
      await page.click('[data-camera=side]'); await page.locator('[data-inspect=wireframe]').check(); await close();
      await page.unroute(fixtureURL);
    });

    if (!process.env.PREVIEW_SKIP_DERIVED) await group('Prepared runtime and FBX clips use their actual exported bindings', async () => {
      for (const source of ['assets/animations/ual/anim_ual_native_actions_library_v01.tres', 'assets/animations/ual/anim_ual_mixamo_crawling_library_v01.tres', 'assets/animations/anim_legacy_knight_crouch_idle_v01.tres']) {
        const asset = assetWhere(catalog, a => a.path === source, source);
        const clip = asset.preview.clips.find(c => /spell.*idle/i.test(c.name)) || asset.preview.clips[0];
        await open(asset, clip.name); const d = await diagnostics();
        assert.equal(d.clip, clip.export_name || clip.name); assert.ok(d.bones > 0);
        await seek(d.duration / 2); assert.ok((await diagnostics()).time > 0); await close();
      }
      const fbx = assetWhere(catalog, a => a.path.endsWith('/Apple/Apple.fbx'), 'FBX with its own visible model');
      const clip = fbx.preview.clips[0]; await open(fbx, clip.name);
      assert.equal((await diagnostics()).clip, clip.export_name || clip.name);
      assert.ok((await diagnostics()).renderer.geometries > 0); await close();
      // Skeleton-only Mixamo sources now use an explicitly prepared retargeted
      // mannequin preview. Provenance must distinguish it from native playback.
      const sourceOnly = catalog.art.find(a => a.path === 'assets/animations/Mixamo/anim_mixamo_crawling_v01.fbx');
      assert.equal(sourceOnly.preview.status, 'ready');
      assert.equal(sourceOnly.preview.provenance.kind, 'retargeted_preview');
      assert.equal(sourceOnly.preview.provenance.status, 'pending_visual_review');
      await open(sourceOnly, sourceOnly.preview.clips[0].name);
      assert.equal((await diagnostics()).bones, 65);
      assert.match(await page.locator('#animation-provenance').textContent(), /Retargeted mannequin preview.*visual review pending/);
      await close();
    });

    await group('Closing a pending model and opening another cannot revive stale content', async () => {
      const pendingURL = new URL(ual.preview.url, url + '/docs/tracker/').href;
      let releaseRequest; const gate = new Promise(resolve => { releaseRequest = resolve; });
      let requested; const started = new Promise(resolve => { requested = resolve; });
      await page.route(pendingURL, async route => { requested(); await gate; await route.continue().catch(() => {}); });
      await page.evaluate(asset => { void ArtPreview.open(asset); }, ual);
      await started; await close();
      await open(rm, rm.preview.clips[0].name); releaseRequest(); await page.unroute(pendingURL);
      await page.waitForTimeout(100); assert.equal((await diagnostics()).clip, rm.preview.clips[0].export_name || rm.preview.clips[0].name);
      assert.equal(await page.locator('#animation-viewport canvas').count(), 1); await close();
    });

    await group('Documented UI sequence preserves transparency, steps frames and scrubs', async () => {
      await open(sequence); assert.equal((await diagnostics()).playing, false);
      assert.match(await page.locator('#animation-frame').textContent(), /^Frame 1 \/ /);
      await page.click('#animation-next-frame'); assert.match(await page.locator('#animation-frame').textContent(), /^Frame 2 \/ /);
      await page.click('#animation-previous-frame'); assert.match(await page.locator('#animation-frame').textContent(), /^Frame 1 \/ /);
      await seek(0.5); assert.ok((await diagnostics()).time >= 0.499);
      await page.selectOption('#animation-background', 'light'); assert.equal(await page.locator('#animation-viewport').getAttribute('data-background'), 'light');
      assert.ok(await page.locator('#animation-viewport canvas').evaluate(canvas => {
        const pixels = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data;
        for (let i = 3; i < pixels.length; i += 4) if (pixels[i] < 255) return true;
        return false;
      }), 'Frames must retain alpha instead of a baked background');
      await page.click('#animation-play'); await page.waitForFunction(() => ArtPreview.diagnostics().time > 0.6); await close();
    });

    await group('Missing first and later frames show a persistent actionable failure', async () => {
      const manifestURL = url + '/docs/tracker/test-sequence-fixture.json';
      const frameURL = new URL(sequence.url, url + '/docs/tracker/').href;
      const missing = url + '/docs/tracker/no-such-test-frame.png';
      await page.route(missing, route => route.fulfill({status: 404, body: ''}));
      for (const firstMissing of [true, false]) {
        await page.route(manifestURL, route => route.fulfill({contentType: 'application/json', body: JSON.stringify({fps: 2, frames: firstMissing ? [missing, frameURL] : [frameURL, missing]})}));
        const fixture = {...sequence, preview: {...sequence.preview, sequence: {...sequence.preview.sequence, frames_url: manifestURL, fps: 2, start_frame: 0}}};
        await page.evaluate(asset => { void ArtPreview.open(asset); }, fixture);
        if (!firstMissing) { await ready(); await page.click('#animation-next-frame'); }
        await page.waitForFunction(() => document.getElementById('animation-message').textContent.includes('missing'));
        await page.waitForTimeout(50);
        assert.match(await page.locator('#animation-message').textContent(), /missing/i);
        assert.equal(await page.locator('#animation-play').isDisabled(), true);
        await close(); await page.unroute(manifestURL);
      }
      await page.unroute(missing);
    });

    await group('Existing video can play, change rate and seek through byte-range serving', async () => {
      await open(video); const d = await diagnostics(); assert.equal(d.playing, false); assert.ok(d.duration > 0);
      await page.selectOption('#animation-speed', '0.5'); await page.click('#animation-play');
      await page.waitForFunction(() => ArtPreview.diagnostics().time > 0.08 || document.querySelector('#animation-viewport video').error);
      assert.equal(await page.locator('#animation-viewport video').evaluate(v => v.error?.message || null), null);
      await seek(d.duration / 2);
      await page.waitForFunction(target => Math.abs(document.querySelector('#animation-viewport video').currentTime - target) < 0.02, d.duration / 2);
      assert.equal(await page.locator('#animation-viewport video').evaluate(v => v.playbackRate), 0.5); await close();
    });

    await group('A rejected old video loop restart cannot disable a replacement preview', async () => {
      await open(video); await page.locator('#animation-loop').check(); await page.click('#animation-play');
      await page.waitForFunction(() => ArtPreview.diagnostics().time > 0.05 || document.querySelector('#animation-viewport video').error);
      assert.equal(await page.locator('#animation-viewport video').evaluate(v => v.error?.message || null), null);
      // Patch only this video instance after its first real play succeeds. The
      // next play call belongs to automatic loop restart and remains pending
      // until a different preview has finished loading.
      await page.locator('#animation-viewport video').evaluate(video => {
        window.previewLoopRestartCalls = 0;
        video.play = () => {
          window.previewLoopRestartCalls++;
          return new Promise((resolve, reject) => { window.rejectOldPreviewLoop = reject; });
        };
        video.currentTime = video.duration;
      });
      await page.waitForFunction(() => window.previewLoopRestartCalls === 1);
      await open(ual, walk.name);
      await page.evaluate(() => {
        window.rejectOldPreviewLoop(Error('Forced delayed failure from closed video'));
        delete window.rejectOldPreviewLoop;
      });
      assert.equal((await diagnostics()).clip, walk.export_name || walk.name);
      assert.match(await page.locator('#animation-message').textContent(), /^Ready/);
      assert.equal(await page.locator('#animation-play').isDisabled(), false);
      assert.equal(await page.locator('#animation-timeline').isDisabled(), false);
      assert.equal(await page.locator('#animation-viewport canvas').count(), 1);
      await page.click('#animation-play'); await page.waitForFunction(() => ArtPreview.diagnostics().time > 0.05); await close();
    });

    await group('Unavailable graphics and static-file browsing give useful guidance', async () => {
      const disabled = await browser.newContext();
      await disabled.addInitScript(() => {
        const original = HTMLCanvasElement.prototype.getContext;
        HTMLCanvasElement.prototype.getContext = function (name, ...args) { return /webgl/i.test(name) ? null : original.call(this, name, ...args); };
      });
      const noGL = await disabled.newPage(); await noGL.goto(url + '/docs/tracker/');
      await noGL.evaluate(asset => { void ArtPreview.open(asset); }, ual);
      await noGL.waitForFunction(() => document.getElementById('animation-message').textContent.includes('WebGL'));
      assert.equal(await noGL.locator('#animation-play').isDisabled(), true); assert.equal(await noGL.locator('#animation-viewport canvas').count(), 0);
      await disabled.close();
      const local = await browser.newPage(); await local.goto(pathToFileURL(path.join(root, 'docs/tracker/index.html')).href);
      await local.evaluate(asset => { void ArtPreview.open(asset); }, ual);
      assert.match(await local.locator('#animation-message').textContent(), /Start the tracker.*127\.0\.0\.1/);
      assert.equal(await local.locator('#animation-play').isDisabled(), true); await local.close();
    });

    assert.deepEqual(errors, [], 'No unhandled browser exceptions');
    assert.equal(requests.filter(r => r.method === 'PUT').length, 0, 'Preview controls must never write tracking decisions');
    assert.deepEqual(await page.request.get(url + '/api/tracker').then(r => r.json()), stateBefore);
    assert.equal(fs.existsSync(path.join(temp, 'tracking.json')), false);
    console.log(`Animation preview: ${groups.length} acceptance groups passed. Screenshots: .artifacts/tracker/animation-preview-{desktop,mobile}.png (Chromium software WebGL).`);
  } catch (error) {
    if (page) console.error('Preview state:', await diagnostics().catch(() => null), await page.locator('#animation-message').textContent().catch(() => ''));
    throw error;
  } finally {
    if (browser) await browser.close();
    if (server && server.exitCode === null) { const done = new Promise(resolve => server.once('exit', resolve)); server.kill(); await done; }
    fs.rmSync(temp, {recursive: true, force: true});
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
