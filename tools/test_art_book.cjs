// Browser acceptance for Art Book discovery; all saves use temporary state.
const {chromium}=require('playwright'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const {spawn}=require('node:child_process');
const root=path.resolve(__dirname,'..'),temp=fs.mkdtempSync(path.join(os.tmpdir(),'ashen-art-book-'));
let browser,server;
(async()=>{
 try{
  server=spawn('python3',[path.join(__dirname,'serve_progress_tracker.py'),'--port','0','--state',path.join(temp,'tracking.json')],{cwd:root,stdio:['ignore','pipe','pipe']});
  server.stderr.on('data',()=>{});
  const url=await new Promise((resolve,reject)=>{let text='';const timer=setTimeout(()=>reject(Error('Server startup timeout')),10000);server.stdout.on('data',data=>{text+=data;const m=text.match(/http:\/\/127\.0\.0\.1:\d+/);if(m){clearTimeout(timer);resolve(m[0]);}});server.once('exit',code=>{clearTimeout(timer);reject(Error('Server exited '+code));});});
  browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH,args:['--no-sandbox']});
  const ctx=await browser.newContext({viewport:{width:1360,height:950}}),page=await ctx.newPage(),errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  await page.goto(url+'/docs/tracker/');await page.waitForFunction(()=>document.getElementById('save-state').textContent==='Saved to project');
  await page.click('[data-book=art]');
  assert.ok(await page.locator('#art-sidebar').isVisible());assert.ok(await page.locator('#active-art-filters').textContent().then(t=>t.includes('Origin: Project files')));
  assert.equal(await page.locator('.entry select').count(),0,'Art cards must not contain editing controls');
  assert.ok(await page.locator('.entry').count()>0);
  await page.click('[data-shortcut=Textures]');assert.ok(await page.locator('.entry').count()>0);
  const ids=await page.locator('.entry').evaluateAll(nodes=>nodes.map(n=>n.dataset.id));
  assert.ok(await page.evaluate(ids=>ids.every(id=>{const a=TRACKER_DATA.art.find(a=>a.id===id),p=TRACKER_DATA.packs?.find(p=>p.id===id);return a?a.types.includes('Textures'):p?.members.some(member=>TRACKER_DATA.art.find(a=>a.id===member)?.types.includes('Textures'));}),ids));
  // A second type broadens that group, while UI narrows across groups.
  await page.click('[data-shortcut=Animations]');await page.click('[data-shortcut=UI]');
  let visible=await page.locator('.entry').evaluateAll(ns=>ns.map(n=>n.dataset.id));assert.ok(visible.length>0);
  assert.ok(await page.evaluate(ids=>ids.every(id=>{const a=TRACKER_DATA.art.find(a=>a.id===id),p=TRACKER_DATA.packs?.find(p=>p.id===id);const match=a=>a?.collections.includes('UI')&&a.types.some(t=>['Textures','Animations'].includes(t));return a?match(a):p?.members.some(member=>match(TRACKER_DATA.art.find(a=>a.id===member)));}),visible));
  await page.getByRole('button',{name:'Remove Type: Textures filter',exact:true}).click();assert.equal(await page.locator('#art-filter-groups input[value=Textures]').isChecked(),false);
  assert.ok(await page.evaluate(()=>document.getElementById('active-art-filters').contains(document.activeElement)||document.activeElement.id==='search'),'Removing a chip retains keyboard focus');
  await page.click('#clear-filters');
  assert.equal(await page.locator('#art-filter-groups input[value="Project files"]').isChecked(),false,'Clear filters explicitly includes all origins');
  await page.click('[data-shortcut=Animations]');await page.fill('#search','regular sword');
  assert.ok(await page.locator('.entry').count()>0);assert.match(await page.locator('#results').textContent(),/Sword_Regular|sword_regular/i);
  const results1=await page.locator('.entry').evaluateAll(ns=>ns.map(n=>n.dataset.id).sort());
  await page.fill('#search','SWORD_regular');assert.deepEqual(await page.locator('.entry').evaluateAll(ns=>ns.map(n=>n.dataset.id).sort()),results1);
  const before=await page.locator('.entry').count();await page.locator('.entry h2 button').first().click();assert.ok(await page.locator('#detail-body .clip-list li').count()>0);await page.click('#close-detail');assert.equal(await page.locator('.entry').count(),before,'Clips stay in one parent card');
  const requests=[];page.on('request',r=>requests.push(r.url()));await page.fill('#search','sword regular');await page.selectOption('#art-sort','recent');await page.click('[data-layout=list]');
  assert.equal(await page.locator('#results').getAttribute('class'),'art-list');assert.ok(!requests.some(u=>/\.(glb|gltf|fbx|tres|res)(?:\?|$)/i.test(u)),'Search must not load animation/model resources');
  const saved=await page.evaluate(()=>JSON.parse(localStorage.getItem('ashen-books-view-v2')).views.art);assert.equal(saved.layout,'list');assert.equal(saved.sort,'recent');
  await page.click('[data-book=dev]');await page.fill('#search','crawling');await page.click('[data-book=art]');assert.equal(await page.inputValue('#search'),'sword regular');assert.equal(await page.inputValue('#art-sort'),'recent');
  await page.reload();await page.waitForFunction(()=>document.querySelector('h1').textContent==='Art Book');assert.equal(await page.locator('#results').getAttribute('class'),'art-list');assert.equal(await page.inputValue('#search'),'sword regular');
  await page.click('#clear-filters');await page.click('[data-shortcut=UI]');await page.click('[data-layout=gallery]');await page.selectOption('#art-sort','name');
  fs.mkdirSync(path.join(root,'.artifacts/tracker'),{recursive:true});await page.screenshot({path:path.join(root,'.artifacts/tracker/art-filters-desktop.png')});
  await page.setViewportSize({width:390,height:850});assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
  await page.click('#open-art-filters');await page.locator('#art-filter-dialog').waitFor({state:'visible'});
  await page.locator('#art-filter-groups input[value="Images"]').check();await page.keyboard.press('Escape');await page.locator('#art-filter-dialog').waitFor({state:'hidden'});
  assert.equal(await page.evaluate(()=>document.activeElement.id),'open-art-filters');assert.ok(await page.locator('#active-art-filters').textContent().then(t=>t.includes('Type: Images')));
  await page.click('#open-art-filters');await page.click('#close-art-filters');await page.click('[data-layout=list]');assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
  await page.screenshot({path:path.join(root,'.artifacts/tracker/art-filters-mobile.png')});
  // Legacy preferences explicitly selected all origins; do not impose the new default.
  const legacy=await browser.newContext({viewport:{width:1200,height:900}});await legacy.addInitScript(()=>localStorage.setItem('ashen-books-view-v2',JSON.stringify({book:'art',views:{art:{search:'MainKnightReference',area:'Images',topic:'',view:'all',attention:'',priority:'',scroll:0,limit:60}}})));
  const old=await legacy.newPage();await old.goto(url+'/docs/tracker/');await old.waitForFunction(()=>document.getElementById('save-state').textContent==='Saved to project');
  assert.equal(await old.locator('#art-filter-groups input[value="Project files"]').isChecked(),false);assert.equal(await old.locator('#art-filter-groups input[value=Images]').isChecked(),true);assert.equal(await old.locator('.entry').count(),1);
  assert.deepEqual(errors,[]);console.log('Art Book browser: defaults, overlapping types/UI, chips, clip search, sorting, no model loads, layout persistence, legacy preferences, mobile drawer and keyboard checks passed.');
 }finally{if(browser)await browser.close();if(server&&server.exitCode===null){const done=new Promise(r=>server.once('exit',r));server.kill();await done;}fs.rmSync(temp,{recursive:true,force:true});}
})().catch(e=>{console.error(e);process.exitCode=1;});
