// Focused Dev book navigation/discovery checks; project tracking is never edited.
'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const {spawn}=require('node:child_process'),{pathToFileURL}=require('node:url'),{chromium}=require('playwright');
const M=require('../docs/tracker/model.js');
const root=path.resolve(__dirname,'..'),temp=fs.mkdtempSync(path.join(os.tmpdir(),'ashen-dev-book-'));
const statePath=path.join(temp,'tracking.json'),catalog=JSON.parse(fs.readFileSync(path.join(root,'docs/tracker/catalog.json'),'utf8'));
const features=catalog.features,byId=new Map(features.map(e=>[e.id,e]));
const checks=(count,done)=>Array.from({length:count},(_,i)=>({id:'browser-fixture-'+i,text:'Isolated browser fixture criterion '+i,done:i<done,source:''}));
const items={};
for(const [id,status,priority,list] of [
 ['shared-motion','Completed','High',checks(2,2)],['action-lifecycle','Deferred','Normal',checks(3,1)],
 ['character-resources','Planned','Low',[]],['item-inventory','In progress','Normal',checks(1,0)],
 ['equipment-loadouts','Ready for review','Normal',checks(1,1)]])items[id]={...M.defaults(byId.get(id)),status,priority,checklist:list};
items['shared-motion'].attention=['Bug found'];items['shared-motion'].note='Amber stairs — isolated saved note.';
fs.writeFileSync(statePath,JSON.stringify({version:M.version,revision:0,items,history:[]}));
const baseline=fs.readFileSync(statePath,'utf8');
let browser,server,page,url;const groups=[],errors=[],modelRequests=[];
const metadata=e=>M.effective(e,items);
const ids=()=>page.locator('#results .entry').evaluateAll(rows=>rows.map(row=>row.dataset.id));
async function group(name,body){await body();groups.push(name);console.log('PASS '+name);}
async function loaded(){await page.waitForFunction(()=>document.getElementById('save-state').textContent==='Saved to project');}
async function filters(){await page.locator('#dev-refine').evaluate(node=>{node.open=true;});}
async function clear(){await page.click('#clear-filters');await filters();}
async function expectIds(expected){assert.deepEqual((await ids()).sort(),[...expected].sort());}
async function chapterVisible(){assert.equal(await page.locator('#dev-navigation').isVisible(),true);for(const area of ['Systems','Gameplay','UI'])assert.equal(await page.locator(`[data-dev-area="${area}"]`).isVisible(),true);}
(async()=>{
 try{
  server=spawn('python3',[path.join(__dirname,'serve_progress_tracker.py'),'--port','0','--state',statePath],{cwd:root,stdio:['ignore','pipe','pipe']});
  let log='';server.stderr.on('data',data=>log+=data);
  url=await new Promise((resolve,reject)=>{let output='';const timer=setTimeout(()=>reject(Error('Tracker failed to start: '+log)),10000);server.stdout.on('data',data=>{output+=data;const match=output.match(/Tracker: (http:\/\/127\.0\.0\.1:\d+)/);if(match){clearTimeout(timer);resolve(match[1]);}});server.once('exit',()=>reject(Error('Tracker exited: '+log)));});
  browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',args:['--no-sandbox']});
  const context=await browser.newContext({viewport:{width:1280,height:900}});page=await context.newPage();
  page.on('pageerror',error=>errors.push(error.message));page.on('request',request=>{if(/\.(?:glb|gltf|fbx)(?:[?#]|$)/i.test(request.url()))modelRequests.push(request.url());});
  await page.goto(url+'/docs/tracker/');await loaded();
  await group('chapters stay visible above the existing compact feature list',async()=>{
   await chapterVisible();await expectIds(features.map(e=>e.id));
   assert.equal(await page.locator('#dev-sort').isVisible(),true);
   const totals=M.aggregate(features.filter(e=>e.area==='Systems'),items);
   const text=await page.locator('[data-dev-area="Systems"]').textContent();
   assert.ok(text.includes(`${totals.done}/${totals.total}`),'Chapter progress includes deferred checks');
   assert.ok(text.includes(`${totals.assessed}/${totals.count}`),'Chapter coverage exposes unassessed work');
  });
  await group('chapter, topic and tag navigation combine with removable chips',async()=>{
   await page.click('[data-dev-area="Systems"]');await expectIds(features.filter(e=>e.area==='Systems').map(e=>e.id));
   await page.click('[data-dev-topic="Items"]');await expectIds(features.filter(e=>e.area==='Systems'&&e.topic==='Items').map(e=>e.id));
   await page.locator('.dev-tag').filter({hasText:'Items and equipment'}).first().focus();await page.keyboard.press('Enter');
   assert.ok(await page.locator('#active-dev-filters button').count()>=3);
   assert.notEqual(await page.evaluate(()=>document.activeElement.tagName),'BODY','Keyboard tag selection must retain a usable focus target');
   await filters();assert.equal(await page.inputValue('#dev-tag'),'Items and equipment');
   await page.locator('#active-dev-filters button').filter({hasText:'Items and equipment'}).click();assert.equal(await page.inputValue('#dev-tag'),'');
   await clear();await expectIds(features.map(e=>e.id));
  });
  await group('empty search results retain navigation and clear filters',async()=>{
   await page.fill('#search','no_existing_feature_zzzz');assert.equal((await ids()).length,0);await chapterVisible();
   await clear();await expectIds(features.map(e=>e.id));
  });
  await group('all five statuses and independent quality, priority and assessment filters',async()=>{
   for(const status of M.statuses){await page.selectOption('#dev-status',status);await expectIds(features.filter(e=>metadata(e).status===status).map(e=>e.id));}
   await page.selectOption('#dev-status','Completed');await page.selectOption('#attention','Bug found');await page.selectOption('#priority','High');await page.selectOption('#dev-assessment','assessed');
   await expectIds(['shared-motion']);assert.equal(metadata(byId.get('shared-motion')).status,'Completed');
   await page.selectOption('#dev-assessment','unassessed');await expectIds([]);await chapterVisible();
   await clear();
  });
  await group('assessment totals and progress/priority sorts do not invent completion',async()=>{
   await page.selectOption('#dev-assessment','unassessed');await expectIds(features.filter(e=>!metadata(e).checklist.length).map(e=>e.id));
   await page.selectOption('#dev-assessment','');await page.selectOption('#dev-sort','priority');assert.equal((await ids())[0],'shared-motion');
   await page.selectOption('#dev-sort','progress');const ordered=(await ids()).map(id=>metadata(byId.get(id)));
   assert.ok(ordered[0].checklist.length&&ordered[0].checklist.every(c=>c.done));
   let unassessed=false;for(const record of ordered){if(!record.checklist.length)unassessed=true;else assert.equal(unassessed,false,'Assessed records precede unassessed records');}
   await clear();
  });
  await group('normalized unordered search finds titles, saved notes and source paths',async()=>{
   await page.selectOption('#dev-sort','relevance');await page.fill('#search','MOTION_shared');assert.equal((await ids())[0],'shared-motion');
   await page.fill('#search','STÁIRS_amber');await expectIds(['shared-motion']);
   const source=byId.get('shared-motion').sources[0];assert.equal(typeof source,'string');await page.fill('#search',source);assert.ok((await ids()).includes('shared-motion'));
   assert.equal(fs.readFileSync(statePath,'utf8'),baseline,'Browsing does not change tracking');assert.deepEqual(modelRequests,[],'Dev browsing does not fetch 3D assets');
   await clear();
  });
  await group('feature details separate recorded evidence from editable notes',async()=>{
   await page.fill('#search','Shared character motion');await page.locator('#results .entry[data-id="shared-motion"] h2 button').click();
   for(const heading of ['Overview','Documented implementation','Implementation notes & known limits','Completion checklist','Your notes'])assert.equal(await page.locator('#detail-body').getByRole('heading',{name:heading,exact:true}).count(),1,heading);
   const sourceLinks=page.locator('#detail-body details a');assert.ok(await sourceLinks.count());assert.ok((await sourceLinks.first().getAttribute('href')).startsWith('../../'));
   await page.fill('#entry-notes','Amber stairs — verified in an isolated browser test.');await page.click('#close-detail');await loaded();
   const state=JSON.parse(fs.readFileSync(statePath,'utf8'));assert.equal(state.items['shared-motion'].status,'Completed');assert.deepEqual(state.items['shared-motion'].attention,['Bug found']);
   assert.ok(state.history.some(event=>event.id==='shared-motion'&&event.fields.includes('note')));
   items['shared-motion']=state.items['shared-motion'];await clear();
  });
  await group('filters and sorting survive book switches and reload independently',async()=>{
   await page.click('[data-dev-area="Gameplay"]');await page.click('[data-dev-topic="Movement"]');await page.selectOption('#dev-sort','priority');await page.fill('#search','running');
   const before=await ids();await page.click('[data-book="art"]');await page.fill('#search','MainKnightReference');
   await page.click('[data-book="dev"]');assert.equal(await page.inputValue('#search'),'running');assert.equal(await page.inputValue('#dev-sort'),'priority');await expectIds(before);
   await page.reload();await loaded();await expectIds(before);await chapterVisible();assert.equal(await page.inputValue('#search'),'running');
   await page.click('[data-book="art"]');assert.equal(await page.inputValue('#search'),'MainKnightReference');await page.click('[data-book="dev"]');await clear();
  });
  await group('keyboard controls and narrow layouts retain readable navigation',async()=>{
   const chapter=page.locator('[data-dev-area="UI"]');await chapter.focus();await page.keyboard.press('Enter');await expectIds(features.filter(e=>e.area==='UI').map(e=>e.id));assert.equal(await page.evaluate(()=>document.activeElement.dataset.devArea),'UI');await clear();
   await page.locator('#dev-refine').evaluate(node=>{node.open=false;});await page.locator('#dev-refine summary').focus();await page.keyboard.press('Enter');assert.equal(await page.locator('#dev-refine').evaluate(node=>node.open),true);
   const screenshots=path.join(root,'.artifacts/tracker');fs.mkdirSync(screenshots,{recursive:true});
   await page.locator('#dev-refine').evaluate(node=>{node.open=false;});
   for(const width of [1280,390]){
    await page.setViewportSize({width,height:900});await page.evaluate(()=>window.scrollTo(0,0));await chapterVisible();assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'No horizontal page overflow');await page.screenshot({path:path.join(screenshots,`dev-book-${width}.png`)});
    await page.locator('#dev-navigation').evaluate(node=>window.scrollTo(0,node.getBoundingClientRect().top+scrollY-document.querySelector('body>nav').getBoundingClientRect().height-12));await page.screenshot({path:path.join(screenshots,`dev-book-navigation-${width}.png`)});
   }
   assert.equal(await page.locator('#dev-topics').isVisible(),false,'Mobile all-features browsing keeps shortcuts compact');
   await page.click('[data-dev-area="Gameplay"]');assert.equal(await page.locator('#dev-topics').isVisible(),true);
   await page.locator('[data-dev-topic="Movement"]').focus();await page.keyboard.press('Enter');assert.equal(await page.evaluate(()=>document.activeElement.dataset.devTopic),'Movement');
   await expectIds(features.filter(e=>e.area==='Gameplay'&&e.topic==='Movement').map(e=>e.id));
   await clear();await filters();assert.ok(await page.locator('#topic option[value="Movement"]').count(),'Refine retains every topic on mobile');
  });
  await group('static Dev book stays readable and clearly read-only',async()=>{
   const offline=await browser.newPage();await offline.goto(pathToFileURL(path.join(root,'docs/tracker/index.html')).href);
   assert.match(await offline.locator('#save-state').textContent(),/Read-only/);assert.equal(await offline.locator('#dev-navigation').isVisible(),true);
   assert.equal(await offline.locator('#results .entry select').first().isDisabled(),true);await offline.close();
  });
  assert.deepEqual(errors,[]);console.log(`${groups.length} Dev book browser groups passed.`);
 }finally{await browser?.close();if(server&&server.exitCode===null){const stopped=new Promise(resolve=>server.once('exit',resolve));server.kill();await stopped;}fs.rmSync(temp,{recursive:true,force:true});}
})().catch(error=>{console.error(error);process.exitCode=1;});
