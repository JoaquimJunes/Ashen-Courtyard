// Pack edits use a disposable project, original PNG fixtures and annotation file.
'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const {spawn}=require('node:child_process'),{createHash}=require('node:crypto'),{pathToFileURL}=require('node:url'),{chromium}=require('playwright');
const M=require('../docs/tracker/model.js'),root=path.resolve(__dirname,'..');
const fixture=fs.mkdtempSync(path.join(os.tmpdir(),'ashen-pack-management-')),tracker=path.join(fixture,'docs/tracker');
const statePath=path.join(tracker,'tracking.json'),packPath=path.join(tracker,'pack_edits.json');
const artifacts=path.join(root,'.artifacts/tracker');fs.mkdirSync(artifacts,{recursive:true});
const groups=[],errors=[];let browser,server,page,url,log='',manualId,acceptedId;
const sha=value=>createHash('sha256').update(value).digest('hex');
const read=file=>JSON.parse(fs.readFileSync(file,'utf8'));
function write(relative,value){const file=path.join(fixture,relative);fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,value);}
fs.mkdirSync(tracker,{recursive:true});
for(const name of fs.readdirSync(path.join(root,'docs/tracker')))if(/\.(js|css|html)$/.test(name)&&name!=='data.js')fs.copyFileSync(path.join(root,'docs/tracker',name),path.join(tracker,name));
const relative=['declared/plate_01.png','declared/plate_02.png','declared/plate_03.png','manual/alpha.png','manual/beta.png','suggestions/study_01.png','suggestions/study_02.png','suggestions/study_03.png'];
const members=relative.map(name=>{const file='art_source/pack_management/'+name;return {id:'art:'+sha(file).slice(0,24),title:path.basename(name,'.png').replaceAll('_',' '),path:file,url:'../../'+file,kind:'Images',types:['Images'],collections:[],origin:'Project files',role:'',image:true,missing:false,clip_names:[],clip_status:'not_applicable'};});
const pack={id:'art:pack:management-fixture',title:'Documented fixture pack',description:'Existing ordered fixture images.',kind:'Image packs',types:['Images'],collections:[],origin:'Project files',origins:['Project files'],role:'',members:members.slice(0,3).map(e=>e.id),member_paths:Object.fromEntries(members.slice(0,3).map(e=>[e.id,e.path])),cover:members[0].id,url:members[0].url,image:true,missing:false,missing_count:0,sources:['art_source/pack_management/README.md']};
const vocabulary=read(path.join(root,'tools/art_animation_taxonomy.json'));
const catalog={features:[],art:members,packs:[pack],animation_clips:[],animation_categories:[],animation_taxonomy:vocabulary};
const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jP7sAAAAASUVORK5CYII=','base64');
for(const member of members)write(member.path,png);
write('docs/tracker/catalog.json',JSON.stringify(catalog));write('docs/tracker/data.js','window.TRACKER_DATA='+JSON.stringify(catalog)+';\n');
write('docs/tracker/features.json','[]');write('docs/tracker/checklist_seeds.json','{}');write('tools/art_animation_taxonomy.json',JSON.stringify(vocabulary));
write('art_source/pack_management/README.md','# Fixture\nDocumented ordered plates one through three.\n');
write('tools/art_image_packs.json',JSON.stringify({version:1,packs:[{key:'management-fixture',title:pack.title,description:pack.description,members:members.slice(0,3).map(e=>e.path),cover:members[0].path,sources:pack.sources,evidence:[{path:pack.sources[0],contains:'Documented ordered plates one through three.'}]}]}));
const initialState={version:M.version,revision:1,items:{[members[3].id]:{...M.defaults(members[3]),note:'Preserve this image note.',review_label:'Approved'},[pack.id]:{...M.defaults(pack),note:'Preserve the documented pack note.'}},history:[]};
write('docs/tracker/tracking.json',JSON.stringify(initialState));
const trackingHash=sha(fs.readFileSync(statePath)),originalHashes=new Map(members.map(e=>[e.path,sha(fs.readFileSync(path.join(fixture,e.path)))]));
async function group(name,body){await body();groups.push(name);console.log('PASS '+name);}
async function stopServer(){if(server&&server.exitCode===null){const stopped=new Promise(resolve=>server.once('exit',resolve));server.kill();await stopped;}}
async function startServer(){server=spawn('python3',[path.join(__dirname,'serve_progress_tracker.py'),'--root',fixture,'--port','0'],{cwd:root,stdio:['ignore','pipe','pipe']});server.stderr.on('data',data=>log+=data);url=await new Promise((resolve,reject)=>{let output='';const timer=setTimeout(()=>reject(Error('Fixture startup failed: '+log)),10000);server.stdout.on('data',data=>{output+=data;const match=output.match(/Tracker: (http:\/\/127\.0\.0\.1:\d+)/);if(match){clearTimeout(timer);resolve(match[1]);}});server.once('exit',()=>{clearTimeout(timer);reject(Error('Fixture server exited: '+log));});});}
async function ready(target=page){await target.waitForFunction(()=>document.getElementById('save-state').textContent==='Saved to project'&&!document.getElementById('select-pack-images').disabled);}
async function packs(){const response=await page.request.get(url+'/api/tracker/packs');assert.equal(response.status(),200);return response.json();}
const card=id=>page.locator(`#results .entry[data-id="${id}"]`);
const memberTile=id=>page.locator(`#pack-members .pack-member-tile`).filter({has:page.locator(`.pack-member[data-id="${id}"]`)});
const selector=index=>page.getByRole('checkbox',{name:'Select image: '+members[index].title,exact:true});
async function art(){await page.click('[data-book="art"]');await page.click('#clear-filters');await ready();}
async function openPack(id){await card(id).locator('.pack-open').click();await page.locator('#pack-dialog').waitFor({state:'visible'});}
async function closePack(){if(await page.locator('#pack-dialog').isVisible())await page.click('#close-pack');}
async function selectManual(){await page.click('#select-pack-images');assert.equal(await page.locator('#show-individual-images').isChecked(),true);await page.fill('#search','alpha');await selector(3).check();await page.fill('#search','beta');await selector(4).check();assert.match(await page.textContent('#pack-selected-count'),/2 images selected/);await page.fill('#search','');}
function originalsUntouched(){assert.equal(sha(fs.readFileSync(statePath)),trackingHash,'Pack changes must not write annotations or approval');for(const [relative,hash] of originalHashes)assert.equal(sha(fs.readFileSync(path.join(fixture,relative))),hash,'Original image bytes preserved: '+relative);}
(async()=>{try{
 await startServer();browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',args:['--no-sandbox']});
 page=await browser.newPage({viewport:{width:1179,height:958}});page.on('pageerror',error=>errors.push(error.message));await page.goto(url+'/docs/tracker/');await art();
 await group('selection survives filters; review and cancel write no pack',async()=>{
  await selectManual();await page.click('#create-image-pack');await page.locator('#create-pack-dialog').waitFor({state:'visible'});assert.equal(await page.locator('#new-pack-members input').count(),2);
  await page.fill('#new-pack-title','My selected images');await page.getByRole('checkbox',{name:'Include beta',exact:true}).uncheck();assert.equal(await page.locator('#confirm-create-pack').isDisabled(),true);await page.getByRole('checkbox',{name:'Include beta',exact:true}).check();
  await page.click('#cancel-create-pack');assert.equal(fs.existsSync(packPath),false);assert.equal(await selector(3).isChecked(),true);assert.equal(await selector(4).isChecked(),true);
  await page.click('#clear-pack-selection');assert.match(await page.textContent('#pack-selected-count'),/0 images selected/);assert.equal(await page.locator('#create-image-pack').isDisabled(),true);
  await selector(3).focus();await page.keyboard.press('Space');await selector(4).check();await page.click('#create-image-pack');await page.fill('#new-pack-title','My selected images');
 });
 await group('failed saves preserve the named preview and image selection',async()=>{
  await page.route('**/api/tracker/packs/create',route=>route.fulfill({status:503,contentType:'application/json',body:JSON.stringify({error:'Simulated full disk',code:'storage'})}));
  await page.click('#confirm-create-pack');await page.waitForFunction(()=>document.getElementById('create-pack-message').textContent.includes('Simulated full disk'));
  assert.equal(await page.locator('#create-pack-dialog').isVisible(),true);assert.equal(await page.inputValue('#new-pack-title'),'My selected images');assert.equal(await page.locator('#new-pack-members input:checked').count(),2);assert.match(await page.textContent('#pack-selected-count'),/2 images selected/);assert.equal(fs.existsSync(packPath),false);await page.unroute('**/api/tracker/packs/create');
 });
 await group('conflicts retain selection and a reviewed retry creates the pack',async()=>{
  const before=await packs(),other=await page.request.post(url+'/api/tracker/packs/create',{data:{version:5,revision:before.revision,title:'Other tab pack',members:[members[1].id,members[2].id]}});assert.equal(other.status(),200);
  await page.click('#confirm-create-pack');await page.waitForFunction(()=>document.getElementById('create-pack-message').textContent.includes('changed in another tab'));
  assert.equal(await page.locator('#create-pack-dialog').isVisible(),true);assert.equal(await page.locator('#new-pack-members input:checked').count(),2);assert.equal(await page.inputValue('#new-pack-title'),'My selected images');
  await page.click('#confirm-create-pack');await page.locator('#create-pack-dialog').waitFor({state:'hidden'});await page.locator('#pack-dialog').waitFor({state:'visible'});
  const snapshot=await packs(),created=snapshot.catalog.packs.find(p=>p.title==='My selected images');manualId=created.id;assert.deepEqual(created.members,members.slice(3,5).map(e=>e.id));assert.equal(created.pack_source,'custom');assert.equal(created.cover,members[3].id);assert.equal(await page.locator('#pack-members .pack-member').count(),2);originalsUntouched();
 });
 await group('cancelled removal preserves cover; confirmed removal changes membership only',async()=>{
  const remove=page.getByRole('button',{name:'Remove alpha from pack',exact:true}),before=read(packPath);
  page.once('dialog',dialog=>dialog.dismiss());await remove.click();assert.deepEqual(read(packPath),before);assert.equal(await page.locator('#pack-members .pack-member').count(),2);
  page.once('dialog',dialog=>{assert.match(dialog.message(),/original file, notes and approval are kept/);return dialog.accept();});await remove.click();await page.waitForFunction(()=>document.getElementById('pack-members').querySelectorAll('.pack-member').length===1);
  const changed=(await packs()).catalog.packs.find(p=>p.id===manualId);assert.deepEqual(changed.members,[members[4].id]);assert.equal(changed.cover,members[4].id);assert.equal(changed.member_count,1);
  assert.equal(await page.locator('.remove-pack-member').evaluateAll(buttons=>buttons.every(button=>!button.closest('.pack-member'))),true,'Removal controls must be siblings, not nested buttons');originalsUntouched();await closePack();
  await openPack(pack.id);page.once('dialog',dialog=>dialog.accept());await page.getByRole('button',{name:'Remove plate 01 from pack',exact:true}).click();await page.waitForFunction(()=>document.getElementById('pack-members').querySelectorAll('.pack-member').length===2);assert.deepEqual(read(packPath).excluded_members[pack.id],[members[0].id]);await closePack();
 });
 await group('refresh keeps custom packs and exclusions; suggestions require explicit review',async()=>{
  const before=await packs();await page.click('#refresh-auto-packs');await page.locator('#pack-suggestions-dialog').waitFor({state:'visible'});
  const after=await packs();assert.equal(after.catalog.packs.length,before.catalog.packs.length);assert.deepEqual(after.catalog.packs.find(p=>p.id===manualId).members,[members[4].id]);assert.deepEqual(after.catalog.packs.find(p=>p.id===pack.id).members,[members[1].id,members[2].id]);
  assert.equal(after.suggestions.some(s=>s.members.includes(members[0].id)),false,'Excluded images must not be automatically suggested again');
  const suggestion=page.locator('.pack-suggestion').filter({hasText:'study — numbered images'});assert.equal(await suggestion.count(),1);await suggestion.getByRole('button',{name:'Review suggested pack',exact:true}).click();
  assert.equal(await page.inputValue('#new-pack-title'),'study — numbered images');assert.equal(await page.locator('#new-pack-members input:checked').count(),3);await page.click('#cancel-create-pack');assert.equal((await packs()).catalog.packs.length,before.catalog.packs.length);originalsUntouched();
  await suggestion.getByRole('button',{name:'Review suggested pack',exact:true}).click();await page.fill('#new-pack-title','Reviewed study images');await page.click('#confirm-create-pack');await page.locator('#create-pack-dialog').waitFor({state:'hidden'});await page.locator('#pack-suggestions-dialog').waitFor({state:'hidden'});
  const accepted=(await packs()).catalog.packs.find(p=>p.title==='Reviewed study images');acceptedId=accepted.id;assert.equal(accepted.pack_source,'custom');assert.deepEqual(accepted.members,members.slice(5).map(e=>e.id));assert.equal(read(statePath).items[accepted.id],undefined,'Creating a pack does not approve it or its members');await closePack();
 });
 await group('keyboard and mobile controls remain separate and fit the screen',async()=>{
  await openPack(pack.id);await page.screenshot({path:path.join(artifacts,'pack-management-desktop.png')});await page.setViewportSize({width:390,height:850});
  assert.equal(await page.locator('.pack-member-tile button button').count(),0);assert.ok(await page.locator('#pack-dialog').evaluate(node=>node.scrollWidth<=node.clientWidth+1));assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
  const remove=page.getByRole('button',{name:'Remove plate 02 from pack',exact:true});await remove.focus();assert.equal(await remove.evaluate(node=>document.activeElement===node),true);page.once('dialog',dialog=>dialog.dismiss());await page.keyboard.press('Enter');assert.equal(await page.locator('#pack-members .pack-member').count(),2);
  await page.screenshot({path:path.join(artifacts,'pack-management-mobile.png')});await page.locator('#close-pack').focus();await page.keyboard.press('Escape');await page.locator('#pack-dialog').waitFor({state:'hidden'});
 });
 await group('server restart retains custom membership and original annotations',async()=>{
  const expected=read(packPath);await stopServer();await startServer();await page.goto(url+'/docs/tracker/');await art();const snapshot=await packs();assert.deepEqual(read(packPath),expected);assert.deepEqual(snapshot.catalog.packs.find(p=>p.id===manualId).members,[members[4].id]);assert.deepEqual(snapshot.catalog.packs.find(p=>p.id===acceptedId).members,members.slice(5).map(e=>e.id));assert.deepEqual(snapshot.catalog.packs.find(p=>p.id===pack.id).members,[members[1].id,members[2].id]);originalsUntouched();
 });
 await group('static browsing disables pack mutations while preserving member navigation',async()=>{
  const offline=await browser.newPage({viewport:{width:390,height:850}});offline.on('pageerror',error=>errors.push(error.message));await offline.goto(pathToFileURL(path.join(tracker,'index.html')).href);await offline.click('[data-book="art"]');await offline.click('#clear-filters');assert.match(await offline.textContent('#save-state'),/Read-only/);assert.equal(await offline.locator('#refresh-auto-packs').isDisabled(),true);assert.equal(await offline.locator('#select-pack-images').isDisabled(),true);
  await offline.locator(`#results .entry[data-id="${pack.id}"] .pack-open`).click();assert.equal(await offline.locator('.remove-pack-member').evaluateAll(buttons=>buttons.every(button=>button.disabled)),true);await offline.locator('#pack-members .pack-member').first().click();assert.equal(await offline.locator('#detail').isVisible(),true);await offline.close();originalsUntouched();
 });
 await group('stale whole-pack approval and retry cannot approve removed members',async()=>{
  const stale=await browser.newPage();stale.on('pageerror',error=>errors.push(error.message));await stale.goto(url+'/docs/tracker/');await ready(stale);await stale.click('[data-book="art"]');await stale.click('#clear-filters');
  await stale.locator(`#results .entry[data-id="${pack.id}"] .pack-open`).click();
  const snapshot=await packs();const removed=await page.request.post(url+'/api/tracker/packs/remove',{data:{version:5,revision:snapshot.revision,pack_id:pack.id,member_id:members[1].id}});assert.equal(removed.status(),200);
  await stale.click('#pack-approve-all');await stale.waitForFunction(()=>document.getElementById('save-state').textContent==='Save failed');
  assert.match(await stale.textContent('#connection'),/pack.*changed|changed.*pack/i);originalsUntouched();
  await stale.click('#close-pack');const retryResponse=stale.waitForResponse(response=>response.url().endsWith('/api/tracker')&&response.request().method()==='PUT');
  await stale.getByRole('button',{name:'Retry saving',exact:true}).click();assert.equal((await retryResponse).status(),409);originalsUntouched();await stale.close();
 });
 assert.deepEqual(errors,[]);fs.writeFileSync(path.join(artifacts,'pack-management-results.json'),JSON.stringify({passed:groups.length,groups,errors,originals_unchanged:true,annotations_unchanged:true},null,2));console.log(`${groups.length} pack-management browser groups passed; all edits used disposable files.`);
}catch(error){if(page)await page.screenshot({path:path.join(artifacts,'pack-management-failure.png')}).catch(()=>{});fs.writeFileSync(path.join(artifacts,'pack-management-results.json'),JSON.stringify({passed:groups.length,groups,errors,failure:String(error),server_log:log.slice(-5000)},null,2));throw error;}
finally{await browser?.close();await stopServer();fs.rmSync(fixture,{recursive:true,force:true});}})().catch(error=>{console.error(error);process.exitCode=1;});
