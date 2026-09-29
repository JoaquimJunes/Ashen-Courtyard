// Whole-pack controls use the real saving service with isolated temporary metadata.
'use strict';
const {chromium}=require('playwright');
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const {spawn}=require('node:child_process'),M=require('../docs/tracker/model.js');
const root=path.resolve(__dirname,'..'),temp=fs.mkdtempSync(path.join(os.tmpdir(),'ashen-pack-editor-'));
const catalog=JSON.parse(fs.readFileSync(path.join(root,'docs/tracker/catalog.json'),'utf8'));
const pack=catalog.packs.find(e=>e.members.length===6)||catalog.packs.find(e=>e.members.length>1),member=catalog.art.find(e=>e.id===pack.members[0]);
const seededMember={...M.defaults(member),note:'Keep this individual note.',status:'Deferred',attention:['Needs testing'],display_name:'Individual image title',review_label:'Scrap',checklist:[{id:'individual-check',text:'Check the original image',done:false,source:''}]};
fs.writeFileSync(path.join(temp,'tracking.json'),JSON.stringify({version:M.version,revision:0,items:{[member.id]:seededMember},history:[]}));
const errors=[],groups=[],artifacts=path.join(root,'.artifacts/tracker');fs.mkdirSync(artifacts,{recursive:true});let server,browser,page,url;
async function start(){
 server=spawn('python3',[path.join(__dirname,'serve_progress_tracker.py'),'--port','0','--state',path.join(temp,'tracking.json')],{cwd:root,stdio:['ignore','pipe','pipe']});server.stderr.on('data',()=>{});
 url=await new Promise((resolve,reject)=>{let out='';const timer=setTimeout(()=>reject(Error('Server startup timeout')),10000);server.stdout.on('data',data=>{out+=data;const match=out.match(/http:\/\/127\.0\.0\.1:\d+/);if(match){clearTimeout(timer);resolve(match[0]);}});server.once('exit',code=>{clearTimeout(timer);reject(Error('Server exited '+code));});});
}
async function stop(){if(server&&server.exitCode===null){const done=new Promise(resolve=>server.once('exit',resolve));server.kill();await done;}}
async function state(){return page.request.get(url+'/api/tracker').then(r=>r.json());}
async function saved(id,field,value){await page.waitForFunction(async({id,field,value})=>{const s=await fetch('/api/tracker').then(r=>r.json());return JSON.stringify(s.items[id]?.[field])===JSON.stringify(value);},{id,field,value});await page.waitForFunction(()=>document.getElementById('save-state').textContent==='Saved to project');}
async function open(){await page.goto(url+'/docs/tracker/');await page.waitForFunction(()=>document.getElementById('save-state').textContent==='Saved to project');await page.click('[data-book=art]');await page.fill('#search',pack.title);await page.locator(`.entry[data-id="${pack.id}"] .pack-open`).click();}
async function writeChanges(changes){const current=await state(),response=await page.request.put(url+'/api/tracker',{data:{version:M.version,revision:current.revision,changes}});assert.equal(response.status(),200);return response.json();}
async function pending(){const download=page.waitForEvent('download');await page.click('#export');return JSON.parse(fs.readFileSync(await (await download).path()));}
async function group(name,run){await run();groups.push(name);console.log('PASS '+name);}
(async()=>{try{
 await start();browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH,args:['--no-sandbox']});page=await browser.newPage({viewport:{width:1179,height:958}});page.on('pageerror',e=>errors.push(e.message));await open();
 await group('One filtered whole-pack approval saves every member atomically and preserves individual metadata',async()=>{
  assert.match(await page.locator('#pack-editor').textContent(),/Whole pack/);
  await page.fill('#pack-search','Individual image title');assert.equal(await page.locator('#pack-members .pack-member').count(),1);
  const puts=[];const capture=request=>{if(request.url()===url+'/api/tracker'&&request.method()==='PUT')puts.push(request.postDataJSON());};page.on('request',capture);
  await page.selectOption('#pack-review-label','Approved');await saved(pack.id,'review_label','Approved');page.off('request',capture);
  assert.equal(puts.length,1,'Pack and all members must use one save request');assert.deepEqual(Object.keys(puts[0].changes).sort(),[pack.id,...pack.members].sort());
  const approved=await state();for(const id of [pack.id,...pack.members])assert.equal(approved.items[id].review_label,'Approved');
  assert.deepEqual(approved.items[member.id],{...seededMember,review_label:'Approved'});
  assert.equal(await page.getAttribute('#pack-review-label','data-state'),'approved');await page.fill('#pack-search','');
  await page.click('#pack-tags-toggle');await page.locator('#pack-tags').getByLabel('Needs improvement',{exact:true}).check();await saved(pack.id,'attention',['Needs improvement']);
  await page.click('#pack-notes-toggle');await page.fill('#pack-entry-notes','Review this pack together.');await saved(pack.id,'note','Review this pack together.');
  const data=await state();for(const id of pack.members)assert.deepEqual(data.items[id],approved.items[id],'Pack notes and tags must not cascade');
  await page.screenshot({path:path.join(artifacts,'pack-editor-desktop.png')});
 });
 await group('Autosaving notes and tags preserve an uncommitted pack rename',async()=>{
  await page.click('#pack-rename-toggle');await page.fill('#pack-display-name','Six stages — review pack');
  await page.fill('#pack-entry-notes','Review this pack together. Keep the proposed name.');await saved(pack.id,'note','Review this pack together. Keep the proposed name.');
  await page.locator('#pack-tags').getByLabel('Needs testing',{exact:true}).check();await saved(pack.id,'attention',['Needs improvement','Needs testing']);
  assert.equal(await page.inputValue('#pack-display-name'),'Six stages — review pack');assert.equal((await state()).items[pack.id].display_name,'');
  await page.fill('#pack-display-name','Invalid\u0001name');await page.getByRole('button',{name:'Save pack name',exact:true}).click();assert.equal(await page.inputValue('#pack-display-name'),'Invalid\u0001name','Validation failure must preserve the attempted rename');assert.equal((await state()).items[pack.id].display_name,'');
  await page.fill('#pack-display-name','Six stages — review pack');await page.getByRole('button',{name:'Save pack name',exact:true}).click();await saved(pack.id,'display_name','Six stages — review pack');assert.equal(await page.textContent('#pack-title'),'Six stages — review pack');
 });
 await group('Member edits and existing pack detail edits stay independent and synchronize',async()=>{
  await page.locator(`#pack-members .pack-member[data-id="${member.id}"]`).click();await page.fill('#entry-notes','Only this image needs checking.');await saved(member.id,'note','Only this image needs checking.');await page.click('#close-detail');
  assert.equal(await page.inputValue('#pack-entry-notes'),'Review this pack together. Keep the proposed name.');
  await page.locator('#pack-actions').getByRole('button',{name:'Pack details & notes',exact:true}).click();await page.selectOption('#art-review-label','Scrap');await saved(pack.id,'review_label','Scrap');await page.fill('#entry-notes','Updated from full pack details.');await saved(pack.id,'note','Updated from full pack details.');await page.click('#close-detail');
  assert.equal(await page.inputValue('#pack-review-label'),'Scrap');assert.equal(await page.getAttribute('#pack-review-label','data-state'),'scrap');assert.equal(await page.inputValue('#pack-entry-notes'),'Updated from full pack details.');
  for(const id of pack.members)assert.equal((await state()).items[id].review_label,'Approved','Scrap applies to the pack alone');
 });
 await group('Full details and inline reapproval cover independently changed members',async()=>{
  await page.locator('#pack-actions').getByRole('button',{name:'Pack details & notes',exact:true}).click();
  await page.selectOption('#art-review-label','');await saved(pack.id,'review_label','');for(const id of pack.members)assert.equal((await state()).items[id].review_label,'Approved','Resetting the pack must not reset members');
  await page.click('#approve-whole-pack');await saved(pack.id,'review_label','Approved');await page.click('#close-detail');
  await page.locator(`#pack-members .pack-member[data-id="${member.id}"]`).click();await page.selectOption('#art-review-label','Scrap');await saved(member.id,'review_label','Scrap');await page.click('#close-detail');
  assert.equal(await page.inputValue('#pack-review-label'),'Approved');await page.click('#pack-approve-all');await saved(member.id,'review_label','Approved');
  assert.equal((await state()).items[member.id].note,'Only this image needs checking.');
  await page.selectOption('#pack-review-label','Scrap');await saved(pack.id,'review_label','Scrap');
 });
 await group('Restart persistence, resetting the name and narrow keyboard layout',async()=>{
  await stop();await start();await open();assert.equal(await page.inputValue('#pack-review-label'),'Scrap');for(const id of pack.members)assert.equal((await state()).items[id].review_label,'Approved');
  await page.click('#pack-rename-toggle');assert.equal(await page.inputValue('#pack-display-name'),'Six stages — review pack');await page.getByRole('button',{name:'Reset pack name',exact:true}).click();await saved(pack.id,'display_name','');assert.equal(await page.textContent('#pack-title'),pack.title);
  await page.setViewportSize({width:390,height:850});await page.locator('#pack-tags-toggle').focus();await page.keyboard.press('Enter');assert.equal(await page.getAttribute('#pack-tags-toggle','aria-expanded'),'true');assert.equal(await page.locator('#pack-tags').getByLabel('Needs testing',{exact:true}).isChecked(),true);
  await page.click('#pack-notes-toggle');assert.equal(await page.inputValue('#pack-entry-notes'),'Updated from full pack details.');assert.ok(await page.locator('#pack-dialog').evaluate(n=>n.scrollWidth<=n.clientWidth),'Whole-pack controls fit a narrow screen');
  await page.locator('#pack-notes-toggle').hover();assert.ok(await page.locator('#pack-notes-toggle').evaluate(n=>{
   const style=getComputedStyle(n),luminance=color=>{const channels=color.match(/[\d.]+/g).slice(0,3).map(v=>{v=Number(v)/255;return v<=.04045?v/12.92:((v+.055)/1.055)**2.4;});return channels[0]*.2126+channels[1]*.7152+channels[2]*.0722;};
   const foreground=luminance(style.color),background=luminance(style.backgroundColor);return (Math.max(foreground,background)+.05)/(Math.min(foreground,background)+.05)>=4.5;
  }),'Expanded pack shortcuts retain readable text when hovered');
  await page.locator('#pack-dialog').evaluate(n=>{n.scrollTop=0;});await page.screenshot({path:path.join(artifacts,'pack-editor-mobile.png')});
 });
 await group('A failed bulk save persists nothing and retries all approval records together',async()=>{
  await page.setViewportSize({width:1179,height:958});await page.click('#close-pack');
  let current=await state();await writeChanges(Object.fromEntries([pack.id,...pack.members].map(id=>[id,{...current.items[id],review_label:''}])));await open();const before=await state();
  await page.route('**/api/tracker',route=>route.request().method()==='PUT'?route.fulfill({status:503,contentType:'application/json',body:'{"error":"Test disk unavailable"}'}):route.continue());
  await page.selectOption('#pack-review-label','Approved');await page.waitForFunction(()=>document.getElementById('save-state').textContent==='Save failed');
  assert.deepEqual(await state(),before,'A failed save cannot leave partly approved members');await page.click('#close-pack');const recovery=await pending();assert.deepEqual(Object.keys(recovery.pendingChanges).sort(),[pack.id,...pack.members].sort());
  await page.unroute('**/api/tracker');await page.getByRole('button',{name:'Retry saving',exact:true}).click();await saved(pack.id,'review_label','Approved');current=await state();for(const id of pack.members)assert.equal(current.items[id].review_label,'Approved');
 });
 await group('Conflicting approval retains the entire draft without overwriting a newer member note',async()=>{
  let current=await state();await writeChanges(Object.fromEntries([pack.id,...pack.members].map(id=>[id,{...current.items[id],review_label:''}])));await open();
  current=await state();await writeChanges({[member.id]:{...current.items[member.id],note:'Newer note from another tab'}});const before=await state();
  await page.selectOption('#pack-review-label','Approved');await page.waitForFunction(()=>document.getElementById('save-state').textContent==='Save failed');assert.match(await page.textContent('#connection'),/Another tab/);
  assert.deepEqual(await state(),before);await page.click('#close-pack');const recovery=await pending();assert.deepEqual(Object.keys(recovery.pendingChanges).sort(),[pack.id,...pack.members].sort());
  await page.evaluate(()=>window.onbeforeunload=null);await open();
 });
 await group('Approval includes all 600 frames beyond pagination and retains a missing member record',async()=>{
  await page.click('#close-pack');const largePack=catalog.packs.find(entry=>entry.members.length===600);assert.ok(largePack);
  const missingId=largePack.members.at(-1),missingEntry=catalog.art.find(entry=>entry.id===missingId),retained={...M.defaults(missingEntry),note:'Retain notes when this catalog file is unavailable.',attention:['Needs testing']};
  await writeChanges({[missingId]:retained});const missingCatalog={...catalog,art:catalog.art.filter(entry=>entry.id!==missingId)};
  await page.route('**/docs/tracker/data.js',route=>route.fulfill({contentType:'text/javascript',body:'window.TRACKER_DATA='+JSON.stringify(missingCatalog)+';'}));
  await page.route('**/api/tracker/packs',async route=>{const response=await route.fetch(),snapshot=await response.json();snapshot.catalog=missingCatalog;await route.fulfill({response,json:snapshot});});
  await page.reload();await page.waitForFunction(()=>document.getElementById('save-state').textContent==='Saved to project');await page.fill('#search',largePack.title);await page.locator(`.entry[data-id="${largePack.id}"] .pack-open`).click();
  assert.equal(await page.locator('#pack-members .pack-member').count(),60);assert.match(await page.textContent('#pack-more'),/539/,'The missing member is filtered out of visible Project files but still belongs to the pack');
  await page.selectOption('#pack-review-label','Approved');await saved(largePack.id,'review_label','Approved');const result=await state();for(const id of largePack.members)assert.equal(result.items[id].review_label,'Approved');assert.deepEqual(result.items[missingId],{...retained,review_label:'Approved'});
  assert.match(await page.textContent('#pack-approval-count'),/600\s*\/\s*600/);await page.click('#close-pack');await page.unroute('**/docs/tracker/data.js');await page.unroute('**/api/tracker/packs');await open();
 });
 await group('Read-only browsing exposes saved controls without permitting edits',async()=>{
  const offline=await browser.newPage();await offline.route('**/api/tracker',r=>r.abort());await offline.goto(url+'/docs/tracker/');await offline.click('[data-book=art]');await offline.fill('#search',pack.title);await offline.locator(`.entry[data-id="${pack.id}"] .pack-open`).click();
  assert.equal(await offline.locator('#pack-review-label').isDisabled(),true);await offline.click('#pack-notes-toggle');assert.equal(await offline.locator('#pack-entry-notes').isDisabled(),true);await offline.close();
 });
 assert.deepEqual(errors,[]);console.log(`Pack editor: ${groups.length} acceptance groups passed; real project metadata was untouched.`);
}finally{if(browser)await browser.close();await stop();fs.rmSync(temp,{recursive:true,force:true});}})().catch(e=>{console.error(e);process.exitCode=1;});
