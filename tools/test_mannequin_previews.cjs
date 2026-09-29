// Retargeted preview acceptance. --staging inspects reviewed build artifacts before catalog promotion.
'use strict';
const {chromium} = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const {spawn} = require('node:child_process');
const root = path.resolve(__dirname, '..'), staging = process.argv.includes('--staging');
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'ashen-mannequin-preview-'));
const sourceCases = [
  ['walk', 'assets/animations/Mixamo/anim_mixamo_crouch_walk_left_v01.fbx'],
  ['sword', 'assets/animations/Mixamo/anim_mixamo_run_with_sword_v01.fbx'],
  ['casting', 'assets/animations/Mixamo/anim_mixamo_two_hand_spell_casting_v01.fbx'],
  ['crawl', 'assets/animations/Mixamo/anim_mixamo_crawling_v01.fbx']
];
let browser, server, page, url;
const errors = [], writes = [], groups = [];
const diag = () => page.evaluate(() => ArtPreview.diagnostics());
async function group(name, body) { await body(); groups.push(name); console.log('PASS ' + name); }
async function ready() {
  await page.waitForFunction(() => {
    const message = document.getElementById('animation-message');
    return message.classList.contains('error') || (!document.getElementById('animation-play').disabled && message.textContent.startsWith('Ready'));
  }, null, {timeout: 15000});
  assert.equal(await page.locator('#animation-message').evaluate(n => n.classList.contains('error')), false, await page.locator('#animation-message').textContent());
  assert.equal((await diag()).bones, 65, 'The active viewer must still own its 65-bone mannequin');
}
async function open(asset) {
  await page.evaluate(asset => { void ArtPreview.open(asset, asset.preview.clips[0].name); }, asset);
  await ready();
}
async function close() {
  await page.click('#animation-close');
  await page.waitForFunction(() => !document.getElementById('animation-dialog').open && !document.querySelector('#animation-viewport canvas'));
}
async function seek(value) {
  await page.locator('#animation-timeline').evaluate((input, value) => { input.value = String(value); input.dispatchEvent(new Event('input', {bubbles: true})); }, value);
}

(async () => {
  try {
    const catalog = JSON.parse(fs.readFileSync(path.join(root, 'docs/tracker/catalog.json'), 'utf8'));
    const report = staging ? JSON.parse(fs.readFileSync(path.join(root, 'docs/tracker/previews/staging-review/report.json'), 'utf8')) : null;
    const cases = sourceCases.map(([key, source]) => {
      const original = catalog.art.find(entry => entry.path === source);
      assert.ok(original, 'Catalog source exists: ' + source);
      const built = report?.results.find(result => result.source === source);
      const descriptor = staging ? {...built, kind: 'model', url: 'previews/staging-review/' + key + '.glb'} : original.preview;
      assert.equal(descriptor?.status, 'ready', 'Prepared mannequin preview required: ' + source);
      assert.equal(descriptor.provenance?.kind, 'retargeted_preview');
      assert.equal(descriptor.provenance.source_path, source);
      assert.equal(descriptor.provenance.target_rig, 'ual1_65_v1');
      assert.equal(descriptor.provenance.status, 'pending_visual_review');
      assert.ok(descriptor.clips.length > 0);
      return {key, asset: {...original, preview: descriptor}};
    });
    server = spawn('python3', [path.join(__dirname, 'serve_progress_tracker.py'), '--port', '0', '--state', path.join(temp, 'tracking.json')], {cwd: root, stdio: ['ignore', 'pipe', 'pipe']});
    server.stderr.on('data', () => {});
    url = await new Promise((resolve, reject) => {
      let output = ''; const timer = setTimeout(() => reject(Error('Server startup timeout')), 10000);
      server.stdout.on('data', data => { output += data; const match = output.match(/http:\/\/127\.0\.0\.1:\d+/); if (match) { clearTimeout(timer); resolve(match[0]); } });
      server.once('exit', code => { clearTimeout(timer); reject(Error('Server exited ' + code)); });
    });
    browser = await chromium.launch({headless: true, executablePath: process.env.CHROMIUM_PATH,
      args: ['--no-sandbox', '--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader', '--disable-accelerated-video-decode']});
    page = await browser.newPage({viewport: {width: 1440, height: 1080}});
    page.on('pageerror', error => errors.push(error.message));
    page.on('request', request => { if (request.method() === 'PUT') writes.push(request.url()); });
    await page.goto(url + '/docs/tracker/'); await page.waitForFunction(() => document.getElementById('save-state').textContent === 'Saved to project');
    const initialState = await page.request.get(url + '/api/tracker').then(r => r.json());
    const artifacts = path.join(root, '.artifacts/tracker/mannequin-representatives'); fs.mkdirSync(artifacts, {recursive: true});

    for (const {key, asset} of cases) await group(key + ': source clip, pending review, mannequin and preserved root motion', async () => {
      await open(asset);
      const clip = asset.preview.clips[0], current = await diag();
      assert.equal(current.playing, false); assert.equal(current.time, 0); assert.equal(current.bones, 65);
      assert.equal(current.clip, clip.export_name || clip.name);
      assert.equal(await page.locator('#animation-current').textContent(), clip.name);
      assert.ok(asset.preview.provenance.source_clips.some(source => source.name === clip.name && Math.abs(source.duration - current.duration) < 1e-5), 'The exact named source clip and duration remain visible');
      assert.equal(await page.locator('#animation-source').textContent(), asset.path);
      assert.match(await page.locator('#animation-model').textContent(), /UAL mannequin/);
      assert.match(await page.locator('#animation-provenance').textContent(), /Retargeted mannequin preview.*visual review pending/);
      assert.ok(current.renderer.geometries > 0);
      const middle = current.duration * 0.5;
      await seek(middle); const middleRoot = (await diag()).root;
      await page.locator('[data-inspect=follow]').check(); await seek(0); await seek(middle);
      const followedRoot = (await diag()).root;
      assert.ok(Math.hypot(...followedRoot.map((value, index) => value - middleRoot[index])) < 1e-6, 'Camera follow does not center or alter root movement');
      if (key === 'walk' || key === 'crawl') assert.ok(Math.hypot(...middleRoot.map((value, index) => value - current.root[index])) > 0.001, 'A moving source must retain its root displacement');
      await page.locator('[data-inspect=follow]').uncheck(); await page.click('[data-camera=side]');
      await page.screenshot({path: path.join(artifacts, key + (staging ? '-staging' : '') + '.png')});
      await page.click('#animation-play'); await page.waitForFunction(time => ArtPreview.diagnostics().time > time + 0.015, middle); await close();
    });

    await group('Immediate close and reopen cannot let an old dialog event erase the new viewer', async () => {
      await open(cases[0].asset);
      await page.evaluate(asset => { ArtPreview.close(); void ArtPreview.open(asset, asset.preview.clips[0].name); }, cases[1].asset);
      await ready();
      assert.equal(await page.locator('#animation-source').textContent(), cases[1].asset.path);
      assert.equal(await page.locator('#animation-viewport canvas').count(), 1);
      await page.click('#animation-play'); await page.waitForFunction(() => ArtPreview.diagnostics().time > 0.05); await close();
    });

    await group('Consecutive opens resolve to the most recent source without duplicate renderers', async () => {
      await page.evaluate(assets => {
        void ArtPreview.open(assets[0], assets[0].preview.clips[0].name);
        void ArtPreview.open(assets[1], assets[1].preview.clips[0].name);
      }, [cases[1].asset, cases[3].asset]);
      await ready();
      assert.equal(await page.locator('#animation-source').textContent(), cases[3].asset.path);
      assert.equal(await page.locator('#animation-viewport canvas').count(), 1);
      assert.ok(Math.abs((await diag()).duration - cases[3].asset.preview.clips[0].duration) < 1e-5); await close();
    });

    await group('Closing an actual pending fetch and reopening leaves the replacement alive', async () => {
      const pendingURL = new URL(cases[0].asset.preview.url, url + '/docs/tracker/').href;
      let resume, seen;
      const gate = new Promise(resolve => { resume = resolve; });
      const requested = new Promise(resolve => { seen = resolve; });
      await page.route(pendingURL, async route => { seen(); await gate; await route.continue().catch(() => {}); });
      await page.evaluate(asset => { void ArtPreview.open(asset, asset.preview.clips[0].name); }, cases[0].asset);
      await requested;
      await page.evaluate(asset => { ArtPreview.close(); void ArtPreview.open(asset, asset.preview.clips[0].name); }, cases[2].asset);
      await ready(); resume(); await page.unroute(pendingURL);
      await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
      assert.equal(await page.locator('#animation-source').textContent(), cases[2].asset.path);
      assert.equal((await diag()).bones, 65); assert.equal(await page.locator('#animation-viewport canvas').count(), 1);
      await page.click('#animation-play'); await page.waitForFunction(() => ArtPreview.diagnostics().time > 0.05); await close();
    });

    assert.deepEqual(errors, []); assert.deepEqual(writes, []);
    assert.deepEqual(await page.request.get(url + '/api/tracker').then(r => r.json()), initialState);
    assert.equal(fs.existsSync(path.join(temp, 'tracking.json')), false);
    console.log(`Mannequin previews: ${groups.length} acceptance groups passed (${staging ? 'staging artifacts' : 'final catalog'}); no tracking decisions changed.`);
  } catch (error) {
    if (page) console.error('Preview diagnostics:', await diag().catch(() => null), await page.locator('#animation-message').textContent().catch(() => ''));
    throw error;
  } finally {
    if (browser) await browser.close();
    if (server && server.exitCode === null) { const done = new Promise(resolve => server.once('exit', resolve)); server.kill(); await done; }
    fs.rmSync(temp, {recursive: true, force: true});
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
