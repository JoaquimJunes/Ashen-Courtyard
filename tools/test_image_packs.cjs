// Image-pack acceptance against the existing catalog; all notes use temporary storage.
'use strict';
const {chromium} = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const {spawn} = require('node:child_process');
const root = path.resolve(__dirname, '..'), temp = fs.mkdtempSync(path.join(os.tmpdir(), 'ashen-image-packs-'));
let browser, server, page, url;
const catalog = JSON.parse(fs.readFileSync(path.join(root, 'docs/tracker/catalog.json'), 'utf8'));
const pack = catalog.packs.find(p => p.members.length === 600 && p.preview?.kind === 'sequence');
assert.ok(pack, 'Existing 600-frame documented pack must be indexed');
const member = catalog.art.find(a => a.id === pack.members.at(-1));
assert.ok(member);
const memberQuery = path.basename(member.path, '.png');
const childNote = 'Pack acceptance: turquoise edge needs checking';
const packNote = 'Pack acceptance: compare lantern evolution';
const errors = [], groups = [], requests = [];
const card = id => page.locator(`.entry[data-id="${id}"]`);
const facet = (group, value) => page.locator(`#art-filter-groups input[data-group="${group}"][value="${value}"]`);
async function group(name, body) { await body(); groups.push(name); console.log('PASS ' + name); }
async function state() { return page.request.get(url + '/api/tracker').then(r => r.json()); }
async function saved(id, field, value) {
  await page.waitForFunction(async ({id, field, value}) => {
    const data = await fetch('/api/tracker').then(r => r.json());
    return JSON.stringify(data.items[id]?.[field]) === JSON.stringify(value);
  }, {id, field, value});
  await page.waitForFunction(() => document.getElementById('save-state').textContent === 'Saved to project');
}
async function packOpen() { await card(pack.id).locator('.pack-open').click(); await page.locator('#pack-dialog').waitFor({state: 'visible'}); }
async function packClose() { await page.click('#close-pack'); await page.locator('#pack-dialog').waitFor({state: 'hidden'}); }

(async () => {
  try {
    server = spawn('python3', [path.join(__dirname, 'serve_progress_tracker.py'), '--port', '0', '--state', path.join(temp, 'tracking.json')], {cwd: root, stdio: ['ignore', 'pipe', 'pipe']});
    server.stderr.on('data', () => {});
    url = await new Promise((resolve, reject) => {
      let output = ''; const timer = setTimeout(() => reject(Error('Server startup timeout')), 10000);
      server.stdout.on('data', data => { output += data; const match = output.match(/http:\/\/127\.0\.0\.1:\d+/); if (match) { clearTimeout(timer); resolve(match[0]); } });
      server.once('exit', code => { clearTimeout(timer); reject(Error('Server exited ' + code)); });
    });
    browser = await chromium.launch({headless: true, executablePath: process.env.CHROMIUM_PATH, args: ['--no-sandbox']});
    const context = await browser.newContext({viewport: {width: 1440, height: 1000}});
    page = await context.newPage(); page.on('pageerror', error => errors.push(error.message));
    page.on('request', request => requests.push({url: request.url(), method: request.method()}));
    await page.goto(url + '/docs/tracker/');
    await page.waitForFunction(() => document.getElementById('save-state').textContent === 'Saved to project');
    await page.click('[data-book=art]');

    await group('Documented images group by default without loading whole sequences', async () => {
      assert.equal(await page.locator('#show-individual-images').isChecked(), false);
      await page.fill('#search', pack.title); await card(pack.id).waitFor();
      assert.equal(await card(member.id).count(), 0);
      assert.match(await card(pack.id).textContent(), /600 images/);
      assert.ok(!requests.some(r => /\.(glb|gltf|fbx|tres)(?:\?|$)|\/previews\/sequences\/|\/preview-(model|media)\.js/i.test(r.url)), 'Pack browsing must not load animation models, players or sequence manifests');
      const loadedFrames = new Set(requests.filter(r => /\/frames\/soul-\d+\.png/.test(r.url)).map(r => r.url));
      assert.ok(loadedFrames.size < 10, 'A collapsed pack loads a cover, not hundreds of frames');
      assert.equal((await state()).revision, 0);
    });

    await group('Pack browsing is paginated, searchable and opens original file details', async () => {
      await packOpen(); assert.equal(await page.locator('#pack-members .pack-member').count(), 60);
      assert.match(await page.locator('#pack-count').textContent(), /600 of 600 images/);
      await page.locator('#pack-more button').click(); assert.equal(await page.locator('#pack-members .pack-member').count(), 120);
      await page.fill('#pack-search', memberQuery); assert.equal(await page.locator('#pack-members .pack-member').count(), 1);
      assert.equal(await page.locator('#pack-members .pack-member').getAttribute('data-id'), member.id);
      await page.locator('#pack-members .pack-member').click();
      assert.equal(await page.locator('#detail-title').textContent(), member.title);
      await page.fill('#entry-notes', childNote); await saved(member.id, 'note', childNote);
      await page.selectOption('#detail-status', 'Planned'); await saved(member.id, 'status', 'Planned');
      await page.locator('#detail-body').getByLabel('Bug found', {exact: true}).check();
      await saved(member.id, 'attention', ['Bug found']);
      await page.keyboard.press('Escape'); await page.locator('#detail').waitFor({state: 'hidden'});
      assert.equal(await page.locator('#pack-dialog').isVisible(), true);
      assert.match(await page.locator('#pack-members').textContent(), /Bug found/, 'Member attention refreshes immediately after closing its editor');
      assert.equal(await page.evaluate(() => document.activeElement.closest('.pack-member')?.dataset.id), member.id,
        'Refreshing pack tiles after closing details returns focus to the same original image');
      await packClose();
    });

    await group('Member notes and flags filter to one matching file inside its pack', async () => {
      await page.fill('#search', 'turquoise edge checking'); await card(pack.id).waitFor();
      assert.match(await card(pack.id).textContent(), /1 matching images/);
      assert.match(await page.locator('#count').textContent(), /1 matching files/);
      await packOpen(); assert.equal(await page.locator('#pack-members .pack-member').count(), 1);
      assert.equal(await page.locator('#pack-members .pack-member').getAttribute('data-id'), member.id);
      assert.match(await page.locator('#pack-members').textContent(), /Bug found/);
      await page.getByRole('button', {name: 'Show all images in this pack', exact: true}).click();
      assert.equal(await page.locator('#pack-members .pack-member').count(), 60);
      await packClose();
      await page.fill('#search', ''); await facet('attention', 'Bug found').check();
      assert.equal(await page.locator('.entry').count(), 1); assert.match(await page.locator('#count').textContent(), /1 matching files/);
    });

    await group('Pack notes and workflow decisions remain separate from file records', async () => {
      await packOpen(); await page.locator('#pack-actions').getByRole('button', {name: 'Pack details & notes', exact: true}).click();
      assert.equal(await page.locator('#detail-title').textContent(), pack.title);
      await page.fill('#entry-notes', packNote); await saved(pack.id, 'note', packNote);
      await page.selectOption('#detail-status', 'Deferred'); await saved(pack.id, 'status', 'Deferred');
      await page.locator('#detail-body').getByLabel('Needs improvement', {exact: true}).check();
      await saved(pack.id, 'attention', ['Needs improvement']);
      await page.click('#close-detail'); await packClose();
      const data = await state(); assert.deepEqual(Object.keys(data.items).sort(), [member.id, pack.id].sort());
      assert.equal(data.items[member.id].note, childNote); assert.equal(data.items[member.id].status, 'Planned');
      assert.deepEqual(data.items[member.id].attention, ['Bug found']);
      await page.click('#clear-filters'); await page.fill('#search', 'compare lantern evolution');
      assert.equal(await page.locator('.entry').count(), 1); assert.equal(await card(pack.id).count(), 1);
      assert.match(await page.locator('#count').textContent(), /0 matching files/);
      await packOpen(); assert.equal(await page.locator('#pack-members .pack-member').count(), 60, 'Own pack-note matches still allow browsing all members'); await packClose();
      await page.fill('#search', ''); await facet('statuses', 'Deferred').check(); await facet('attention', 'Bug found').check();
      assert.equal(await page.locator('.entry').count(), 0, 'Pack Deferred cannot combine with child Bug found');
      await facet('statuses', 'Deferred').uncheck(); await facet('statuses', 'Planned').check();
      assert.equal(await page.locator('.entry').count(), 1); assert.match(await page.locator('#count').textContent(), /1 matching files/);
    });

    await group('Individual-image preference survives reload and preserves original IDs', async () => {
      await page.locator('#show-individual-images').check(); assert.equal(await card(pack.id).count(), 0); assert.equal(await card(member.id).count(), 1);
      await page.reload(); await page.waitForFunction(() => document.getElementById('save-state').textContent === 'Saved to project');
      assert.equal(await page.locator('#show-individual-images').isChecked(), true); assert.equal(await card(member.id).count(), 1);
      assert.equal(await facet('attention', 'Bug found').isChecked(), true);
      await page.click('[data-book=dev]'); await page.fill('#search', 'movement'); await page.click('[data-book=art]');
      assert.equal(await page.locator('#show-individual-images').isChecked(), true); assert.equal(await card(member.id).count(), 1);
      await card(member.id).locator('h2 button').click();
      await page.locator('#detail-body').getByRole('button', {name: 'In pack: ' + pack.title, exact: true}).click();
      await page.locator('#pack-dialog').waitFor({state: 'visible'});
      assert.equal(await page.locator('#detail').isVisible(), false, 'A member editor must close before opening its parent pack');
      await page.fill('#pack-search', memberQuery); await page.locator('#pack-members .pack-member').click();
      await page.locator('#entry-notes').focus();
      assert.equal(await page.evaluate(() => document.activeElement.id), 'entry-notes', 'Reopened member details are above the pack and can receive keyboard input');
      assert.equal(await page.inputValue('#entry-notes'), childNote); await page.click('#close-detail'); await packClose();
      await page.locator('#show-individual-images').uncheck(); assert.equal(await card(pack.id).count(), 1);
    });

    await group('Pack sequence playback uses existing frames without changing notes', async () => {
      const before = await state(); await page.click('#clear-filters'); await page.fill('#search', pack.title); await packOpen();
      await page.locator('#pack-actions .animation-open').click();
      await page.waitForFunction(() => !document.getElementById('animation-play').disabled || document.getElementById('animation-message').classList.contains('error'));
      assert.equal(await page.locator('#animation-message').evaluate(n => n.classList.contains('error')), false, await page.locator('#animation-message').textContent());
      assert.equal(await page.evaluate(() => ArtPreview.diagnostics().kind), 'sequence');
      assert.equal(await page.evaluate(() => ArtPreview.diagnostics().time), 0);
      await page.click('#animation-play'); await page.waitForFunction(() => ArtPreview.diagnostics().time > 0.05);
      await page.click('#animation-close'); await page.locator('#animation-dialog').waitFor({state: 'hidden'});
      assert.equal(await page.locator('#pack-dialog').isVisible(), true); assert.deepEqual(await state(), before); await packClose();
    });

    await group('Keyboard access, narrow layout and pack navigation remain usable', async () => {
      const artifacts = path.join(root, '.artifacts/tracker'); fs.mkdirSync(artifacts, {recursive: true});
      await page.screenshot({path: path.join(artifacts, 'image-packs-desktop.png')});
      await card(pack.id).locator('.pack-open').focus(); await page.keyboard.press('Enter');
      await page.locator('#pack-dialog').waitFor({state: 'visible'});
      await page.setViewportSize({width: 390, height: 850});
      assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
      assert.ok(await page.locator('#pack-dialog').evaluate(n => n.scrollWidth <= n.clientWidth));
      await page.fill('#pack-search', memberQuery); await page.screenshot({path: path.join(artifacts, 'image-packs-mobile.png')});
      // A search input consumes Escape to clear itself; test modal cancellation
      // from a neutral keyboard target instead of overriding native input behavior.
      await page.locator('#close-pack').focus(); await page.keyboard.press('Escape'); await page.locator('#pack-dialog').waitFor({state: 'hidden'});
      assert.equal(await page.evaluate(() => document.activeElement.classList.contains('pack-open')), true);
      await page.click('#open-art-filters'); await page.locator('#art-filter-dialog').waitFor({state: 'visible'}); await page.click('#close-art-filters');
      await page.setViewportSize({width: 1440, height: 1000});
    });

    await group('A missing member keeps its original record and saved notes', async () => {
      const fixture = structuredClone(catalog), missing = fixture.art.find(a => a.id === member.id);
      missing.missing = true; fixture.packs.find(p => p.id === pack.id).missing_count = 1;
      const other = await browser.newContext({viewport: {width: 1200, height: 900}}), missingPage = await other.newPage();
      await missingPage.route('**/docs/tracker/data.js', route => route.fulfill({contentType: 'application/javascript', body: 'window.TRACKER_DATA = ' + JSON.stringify(fixture) + ';'}));
      // Connected browsing replaces the static catalog with saved membership.
      // Keep the missing-file fixture consistent at both catalog entry points.
      await missingPage.route('**/api/tracker/packs', async route => {
        const response = await route.fetch(), snapshot = await response.json();
        snapshot.catalog = fixture;
        await route.fulfill({response, json: snapshot});
      });
      await missingPage.goto(url + '/docs/tracker/'); await missingPage.waitForFunction(() => document.getElementById('save-state').textContent === 'Saved to project');
      await missingPage.click('[data-book=art]'); await missingPage.fill('#search', pack.title);
      await missingPage.locator(`.entry[data-id="${pack.id}"] .pack-open`).click();
      await missingPage.fill('#pack-search', memberQuery);
      assert.match(await missingPage.locator('#pack-members').textContent(), /Missing image.*notes retained/);
      await missingPage.locator('#pack-members .pack-member').click();
      assert.equal(await missingPage.inputValue('#entry-notes'), childNote);
      assert.match(await missingPage.locator('#detail-body').textContent(), /saved metadata is retained/);
      await other.close();
    });

    assert.deepEqual(errors, []);
    assert.deepEqual(JSON.parse(fs.readFileSync(path.join(root, 'docs/tracker/catalog.json'), 'utf8')).art.map(a => a.id), catalog.art.map(a => a.id), 'Browsing never rewrites file IDs');
    console.log(`Image packs: ${groups.length} acceptance groups passed; isolated pack/member notes persisted independently.`);
  } finally {
    if (browser) await browser.close();
    if (server && server.exitCode === null) { const done = new Promise(resolve => server.once('exit', resolve)); server.kill(); await done; }
    fs.rmSync(temp, {recursive: true, force: true});
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
