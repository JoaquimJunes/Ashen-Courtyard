// Destructive-path checks run exclusively against a disposable project copy.
'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os'),crypto=require('node:crypto');
const {spawn}=require('node:child_process'),{chromium}=require('playwright');
const M=require('../docs/tracker/model.js');
const root=path.resolve(__dirname,'..'),fixture=fs.mkdtempSync(path.join(os.tmpdir(),'ashen-scrap-fixture-'));
const tracker=path.join(fixture,'docs/tracker'),statePath=path.join(tracker,'tracking.json');
const sourceCatalog=JSON.parse(fs.readFileSync(path.join(root,'docs/tracker/catalog.json'),'utf8'));
const originalPNG=fs.readFileSync(path.join(root,'assets/third_party/dysfunctional_psx_starter/models/Props/Rocks/Textures/D_RockB.png'));
function write(relative,bytes){const target=path.join(fixture,relative);fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,bytes);}
fs.mkdirSync(tracker,{recursive:true});
for(const name of fs.readdirSync(path.join(root,'docs/tracker')))if(/\.(js|css|html)$/.test(name)&&name!=='data.js')fs.copyFileSync(path.join(root,'docs/tracker',name),path.join(tracker,name));
const identity=relative=>'art:'+crypto.createHash('sha256').update(relative).digest('hex').slice(0,24);
function imageEntry(key){const relative=`art_source/scrap_browser_fixture/${key}.png`;write(relative,originalPNG);return {id:identity(relative),title:'Scrap fixture '+key,path:relative,kind:'Images',types:['Images'],collections:[],origin:'Project files',role:'',image:true,url:'../../'+relative,clip_names:[],clip_status:'not_applicable',modified_at:'2026-01-01T00:00:00Z',missing:false};}
const first=imageEntry('first'),second=imageEntry('second'),protectedImage=imageEntry('protected');
write('assets/fixture_dependency.tscn',`[gd_scene load_steps=2 format=3]\n[ext_resource type="Texture2D" path="res://${protectedImage.path}" id="1"]\n[node name="Fixture"]\n`);
write('art_source/scrap_browser_fixture/pack.md','Disposable image-pack browser fixture.\n');
const pack={id:'art:pack:scrap-browser-pair',title:'Scrap fixture pack',kind:'Image packs',types:['Images'],collections:[],origin:'Project files',role:'',members:[first.id,second.id],cover:first.id,path:'art_source/scrap_browser_fixture/pack.md',sources:['art_source/scrap_browser_fixture/pack.md'],url:first.url,image:true,missing:false};
const feature={...sourceCatalog.features[0],id:'scrap-browser-feature'};
const catalog={features:[feature],art:[first,second,protectedImage],packs:[pack],animation_clips:[],animation_categories:[],animation_taxonomy:sourceCatalog.animation_taxonomy};
write('docs/tracker/catalog.json',JSON.stringify(catalog));write('docs/tracker/data.js','window.TRACKER_DATA='+JSON.stringify(catalog)+';\n');
write('tools/art_animation_taxonomy.json',JSON.stringify(sourceCatalog.animation_taxonomy));
const initialItems=Object.fromEntries([first,second,protectedImage,pack].map(entry=>[entry.id,{...M.defaults(entry),note:'Preserve fixture note: '+entry.title}]));
write('docs/tracker/tracking.json',JSON.stringify({version:M.version,revision:0,items:initialItems,history:[]}));
let browser,server,page,url,port;const groups=[],errors=[];
const rows=()=>page.locator('#results .entry');
const card=entry=>page.locator(`#results .entry[data-id="${entry.id}"]`);
async function group(name,body){await body();groups.push(name);console.log('PASS '+name);}
async function start(){
 server=spawn('python3',[path.join(__dirname,'serve_progress_tracker.py'),'--root',fixture,'--port',String(port||0)],{cwd:root,stdio:['ignore','pipe','pipe']});
 let log='';server.stderr.on('data',data=>log+=data);
 url=await new Promise((resolve,reject)=>{let output='';const timer=setTimeout(()=>reject(Error('Fixture server failed: '+log)),10000);server.stdout.on('data',data=>{output+=data;const match=output.match(/Tracker: (http:\/\/127\.0\.0\.1:(\d+))/);if(match){clearTimeout(timer);port=Number(match[2]);resolve(match[1]);}});server.once('exit',()=>reject(Error('Fixture server exited: '+log)));});
}
async function stop(){if(server&&server.exitCode===null){const stopped=new Promise(resolve=>server.once('exit',resolve));server.kill();await stopped;}}
async function saved(){await page.waitForFunction(()=>document.getElementById('save-state').textContent==='Saved to project');}
async function api(){const response=await page.request.get(url+'/api/tracker');assert.equal(response.status(),200);return response.json();}
async function prepare(ids){const state=await api();return page.request.post(url+'/api/tracker/scrap/prepare',{data:{version:5,revision:state.revision,ids}});}
function exists(entry){return fs.existsSync(path.join(fixture,entry.path));}
function unchanged(entry){assert.deepEqual(fs.readFileSync(path.join(fixture,entry.path)),originalPNG);}
async function open(entry){await card(entry).locator('h2 button').click();if(entry===pack)await page.locator('#pack-actions').getByRole('button',{name:'Pack details & notes',exact:true}).click();await page.locator('#detail').waitFor({state:'visible'});}
async function label(entry,value){
 await page.click('[data-art-mode="files"]');await page.click('#clear-filters');
 await page.locator('#show-individual-images').setChecked(entry!==pack);await open(entry);
 await page.selectOption('#art-review-label',value);await page.click('#close-detail');if(await page.locator('#pack-dialog').isVisible())await page.click('#close-pack');await saved();
}
async function scrap(){await page.click('[data-art-mode="scrap"]');await page.click('#clear-filters');if(await page.locator('#scrap-clear-selection').isEnabled())await page.click('#scrap-clear-selection');}
async function select(entry){await page.locator(`.scrap-select[data-id="${entry.id}"]`).check();}
async function confirmation(){await page.click('#scrap-delete');await page.locator('#scrap-confirm-dialog').waitFor({state:'visible'});}
async function confirmDelete(){await page.click('#scrap-confirm');await page.locator('#scrap-confirm-dialog').waitFor({state:'hidden'});}
async function restored(entry){await page.waitForFunction(id=>document.querySelector(`#results .entry[data-id="${id}"]`),entry.id);unchanged(entry);}
async function checks(){
 await group('review decisions are Art Book only and approval does not complete work',async()=>{
  await page.locator('#results .entry h2 button').first().click();assert.equal(await page.locator('#art-review-label').count(),0);await page.click('#close-detail');
  const state=await api(),bad={...M.defaults(feature),review_label:'Approved'};
  const response=await page.request.put(url+'/api/tracker',{data:{version:5,revision:state.revision,changes:{[feature.id]:bad}}});assert.equal(response.status(),400);
  await page.click('[data-book="art"]');await label(first,'Approved');
  const savedState=await api();assert.equal(savedState.items[first.id].review_label,'Approved');assert.equal(savedState.items[first.id].status,'');assert.deepEqual(savedState.items[first.id].checklist,[]);assert.equal(savedState.items[first.id].note,initialItems[first.id].note);
  assert.equal((await prepare([first.id])).status(),400,'Approved work cannot be moved to Trash');
  unchanged(first);assert.equal(fs.existsSync(path.join(fixture,'.artifacts/tracker-trash')),false);
 });
 await group('review filters include pack-approved members and approved containers protect them',async()=>{
  await page.locator('#art-filter-groups input[data-group="review_labels"][value="Approved"]').check();assert.equal(await rows().count(),1);assert.equal(await rows().first().getAttribute('data-id'),first.id);
  await label(pack,'Approved');assert.equal((await api()).items[second.id].review_label,'Approved','Whole-pack approval labels members');
  await page.click('[data-art-mode="approved"]');assert.deepEqual((await rows().evaluateAll(nodes=>nodes.map(n=>n.dataset.id))).sort(),[first.id,second.id,pack.id].sort(),'Approved view contains explicit decisions, including virtual entries');
  await label(first,'Scrap');const response=await prepare([first.id]);assert.equal(response.status(),400);assert.match((await response.json()).error,/Approved/);
  await label(pack,'Scrap');await label(second,'Scrap');await label(protectedImage,'Scrap');await scrap();
  assert.deepEqual((await rows().evaluateAll(nodes=>nodes.map(n=>n.dataset.id))).sort(),[first.id,second.id,protectedImage.id,pack.id].sort());
 });
 await group('red deletion control requires selection and cancel changes no files or notes',async()=>{
  assert.equal(await page.locator('#scrap-delete').isDisabled(),true);await select(first);
  const color=await page.locator('#scrap-delete').evaluate(node=>getComputedStyle(node).backgroundColor);const rgb=color.match(/\d+/g).map(Number);assert.ok(rgb[0]>rgb[1]&&rgb[0]>rgb[2],'Delete selected is visually red');
  const before=fs.readFileSync(statePath,'utf8');await confirmation();assert.match(await page.locator('#scrap-confirm-list').textContent(),new RegExp(first.path.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')));
  assert.equal(await page.evaluate(()=>document.activeElement.id),'scrap-cancel','Confirmation starts on the safe Cancel action');
  assert.match(await page.locator('#scrap-confirm-list').textContent(),/1 image pack/);
  fs.mkdirSync(path.join(root,'.artifacts/tracker'),{recursive:true});await page.screenshot({path:path.join(root,'.artifacts/tracker/scrap-confirm-desktop.png')});
  await page.setViewportSize({width:390,height:850});assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));await page.screenshot({path:path.join(root,'.artifacts/tracker/scrap-confirm-mobile.png')});
  assert.equal(exists(first),true);await page.click('#scrap-cancel');await page.waitForFunction(()=>document.activeElement.id==='scrap-delete');await page.setViewportSize({width:1280,height:900});assert.equal(fs.readFileSync(statePath,'utf8'),before);unchanged(first);unchanged(second);
 });
 await group('Godot references block a selected original without partial deletion',async()=>{
  await page.click('#scrap-clear-selection');await select(protectedImage);await page.click('#scrap-delete');
  await page.waitForFunction(()=>document.getElementById('scrap-message').textContent.includes('referenced'));
  assert.equal(await page.locator('#scrap-confirm-dialog').isVisible(),false);unchanged(protectedImage);unchanged(first);
 });
 await group('selection is locked during preparation and stale confirmation cannot delete',async()=>{
  await page.click('#scrap-clear-selection');await select(first);
  let release,arrived;const held=new Promise(resolve=>{release=resolve;}),reached=new Promise(resolve=>{arrived=resolve;});
  await page.route('**/api/tracker/scrap/prepare',async route=>{const response=await route.fetch();arrived();await held;await route.fulfill({response});});
  await page.click('#scrap-delete');await reached;assert.equal(await page.locator(`.scrap-select[data-id="${second.id}"]`).isDisabled(),true);release();await page.locator('#scrap-confirm-dialog').waitFor({state:'visible'});await page.unroute('**/api/tracker/scrap/prepare');
  const state=await api();const response=await page.request.put(url+'/api/tracker',{data:{version:5,revision:state.revision,changes:{[second.id]:{...state.items[second.id],note:'A newer independent note must survive'}}}});assert.equal(response.status(),200);
  await page.click('#scrap-confirm');await page.waitForFunction(()=>document.getElementById('scrap-confirm-message').textContent.includes('Nothing else'));
  unchanged(first);unchanged(second);assert.equal((await api()).items[second.id].note,'A newer independent note must survive');
  await page.click('#scrap-cancel');await page.click('#scrap-refresh');await saved();
 });
 let transaction;
 await group('confirmed file deletion moves only its original to recoverable project Trash',async()=>{
  await select(first);await confirmation();await confirmDelete();assert.equal(exists(first),false);unchanged(second);unchanged(protectedImage);
  const state=await api();assert.ok(state.trash.hidden_ids.includes(first.id));assert.equal(state.items[first.id].note,initialItems[first.id].note);assert.equal(state.items[first.id].review_label,'Scrap');
  const staleEdit=await page.request.put(url+'/api/tracker',{data:{version:5,revision:state.revision,changes:{[first.id]:{...state.items[first.id],review_label:'Approved',note:'Stale hidden-item edit'}}}});assert.equal(staleEdit.status(),409,'A stale tab cannot edit a hidden item before restoration');
  transaction=state.trash.transactions.find(tx=>tx.items.some(item=>item.id===first.id));assert.ok(transaction);
  assert.equal(await card(first).count(),0);assert.equal(await page.locator('#scrap-trash-list').getByText(/Invalid Date/).count(),0);
  // A remaining pack must use its surviving member as cover after a file moves.
  await page.waitForFunction(id=>{const image=document.querySelector(`#results .entry[data-id="${id}"] img`);return image?.complete&&image.naturalWidth>0;},pack.id);
  const response=await page.request.get(url+'/'+first.path);assert.equal(response.status(),404);
  const privateJournal=await page.request.get(url+'/.artifacts/tracker-trash/'+transaction.id+'/journal.json');assert.equal(privateJournal.status(),403);
 });
 await group('server restart retains Trash and restore refuses occupied source paths',async()=>{
  await stop();await start();await page.reload();await saved();assert.equal(exists(first),false);assert.ok((await api()).trash.hidden_ids.includes(first.id));
  write(first.path,Buffer.from('A new file at the original path'));
  await page.locator(`.trash-transaction[data-transaction="${transaction.id}"] .scrap-restore`).click();
  await page.waitForFunction(()=>/exists|occupied|overwrite/i.test(document.getElementById('scrap-message').textContent));
  assert.equal(fs.readFileSync(path.join(fixture,first.path),'utf8'),'A new file at the original path');assert.ok((await api()).trash.hidden_ids.includes(first.id));
  fs.unlinkSync(path.join(fixture,first.path));await page.locator(`.trash-transaction[data-transaction="${transaction.id}"] .scrap-restore`).click();await restored(first);
  const state=await api();assert.equal(state.trash.hidden_ids.includes(first.id),false);assert.equal(state.items[first.id].review_label,'Scrap');assert.equal(state.items[first.id].note,initialItems[first.id].note);
  assert.deepEqual(Buffer.from(await (await page.request.get(url+'/'+first.path)).body()),originalPNG);
 });
 await group('virtual pack deletion archives the entry while member images remain usable',async()=>{
  if(await page.locator('#scrap-clear-selection').isEnabled())await page.click('#scrap-clear-selection');await select(pack);await confirmation();assert.match(await page.locator('#scrap-confirm-list').textContent(),/Catalog entry only; source files retained/);await confirmDelete();unchanged(first);unchanged(second);
  const state=await api(),tx=state.trash.transactions.find(item=>item.items.some(entry=>entry.id===pack.id));assert.ok(tx);assert.equal(await card(pack).count(),0);
  await page.locator(`.trash-transaction[data-transaction="${tx.id}"] .scrap-restore`).click();await page.waitForFunction(id=>!!document.querySelector(`#results .entry[data-id="${id}"]`),pack.id);unchanged(first);unchanged(second);
  assert.equal((await api()).items[pack.id].note,initialItems[pack.id].note);
 });
 await group('review labels and restored original previews survive reload',async()=>{
  await page.reload();await saved();assert.equal((await api()).items[first.id].review_label,'Scrap');await label(first,'Approved');await page.reload();await saved();
  await page.click('[data-art-mode="files"]');await page.locator('#show-individual-images').check();await page.click('#clear-filters');
  await page.waitForFunction(id=>{const img=document.querySelector(`#results .entry[data-id="${id}"] img`);return img?.complete&&img.naturalWidth>0;},first.id);
  assert.equal((await api()).items[first.id].review_label,'Approved');assert.equal((await api()).items[first.id].status,'');
  unchanged(first);unchanged(second);unchanged(protectedImage);
 });
}
(async()=>{
 try{
  assert.ok(fixture.startsWith(os.tmpdir()+path.sep),'Never run deletion checks in the real project');
  await start();browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',args:['--no-sandbox']});
  page=await browser.newPage({viewport:{width:1280,height:900}});page.on('pageerror',error=>errors.push(error.message));
  await page.goto(url+'/docs/tracker/');await saved();await checks();assert.deepEqual(errors,[]);console.log(`${groups.length} Scrap browser groups passed.`);
 }finally{await browser?.close();await stop();fs.rmSync(fixture,{recursive:true,force:true});}
})().catch(error=>{console.error(error);process.exitCode=1;});
