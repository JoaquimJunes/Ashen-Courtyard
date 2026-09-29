// Detail-panel interaction checks use a disposable project and saved metadata.
'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const {spawn}=require('node:child_process'),{pathToFileURL}=require('node:url'),{chromium}=require('playwright');
const M=require('../docs/tracker/model.js');
const root=path.resolve(__dirname,'..'),fixture=fs.mkdtempSync(path.join(os.tmpdir(),'ashen-detail-fixture-'));
const tracker=path.join(fixture,'docs/tracker'),statePath=path.join(tracker,'tracking.json');
const source=JSON.parse(fs.readFileSync(path.join(root,'docs/tracker/catalog.json'),'utf8'));
function write(relative,value){const dest=path.join(fixture,relative);fs.mkdirSync(path.dirname(dest),{recursive:true});fs.writeFileSync(dest,value);}
fs.mkdirSync(tracker,{recursive:true});
for(const name of fs.readdirSync(path.join(root,'docs/tracker')))if(/\.(js|css|html)$/.test(name)&&name!=='data.js')fs.copyFileSync(path.join(root,'docs/tracker',name),path.join(tracker,name));
const motion={...source.features[0],id:'detail-motion',title:'Shared character motion',summary:'Responsive slope locomotion.',topic:'Movement',dev_tags:['Motion controls']};
const magic={...source.features[0],id:'detail-magic',title:'Elemental casting',summary:'Aim and release spells.',topic:'Magic',dev_tags:['Spell preparation']};
const first={id:'art:detail-preview',title:'Detail fixture HUD',path:'art_source/detail_fixture/hud.html',kind:'Interactive previews',types:['Interactive previews'],collections:['UI'],origin:'Project files',role:'',image:false,url:'../../art_source/detail_fixture/hud.html',clip_names:[],clip_status:'not_applicable',missing:false,description:'Interactive fixture showing health and stamina controls.'};
const second={...first,id:'art:detail-document',title:'Detail fixture notes',path:'art_source/detail_fixture/notes.md',url:'../../art_source/detail_fixture/notes.md',kind:'Design documents',types:['Design documents'],collections:[],description:undefined};
const catalog={features:[motion,magic],art:[first,second],packs:[],animation_clips:[],animation_categories:[],animation_taxonomy:source.animation_taxonomy};
write(first.path,'<!doctype html><title>Fixture HUD</title>');write(second.path,'# Fixture notes\n');
write('docs/tracker/catalog.json',JSON.stringify(catalog));write('docs/tracker/data.js','window.TRACKER_DATA='+JSON.stringify(catalog)+';\n');
write('tools/art_animation_taxonomy.json',JSON.stringify(source.animation_taxonomy));
const initial={...M.defaults(first),related:[motion.id],status:'In progress',note:'Keep this independent fixture note.',checklist:[{id:'fixture-check',text:'Fixture acceptance',done:true,source:''}]};
write('docs/tracker/tracking.json',JSON.stringify({version:M.version,revision:0,items:{[first.id]:initial},history:[]}));
let browser,server,page,url;const groups=[],errors=[];let saves=0;
const card=entry=>page.locator(`#results .entry[data-id="${entry.id}"]`);
async function group(name,body){await body();groups.push(name);console.log('PASS '+name);}
async function saved(){await page.waitForFunction(()=>document.getElementById('save-state').textContent==='Saved to project');}
async function open(entry,target=page){await target.locator(`#results .entry[data-id="${entry.id}"] h2 button`).click();await target.locator('#detail').waitFor({state:'visible'});}
async function search(query,target=page){await target.fill('#related-feature-search',query);}
async function visibleRelations(target=page){return target.locator('.relation-list label:visible').allTextContents();}
async function color(selector){return page.locator(selector).evaluate(node=>getComputedStyle(node).borderLeftColor);}
const rgb=value=>value.match(/\d+/g).map(Number);
(async()=>{
 try{
  server=spawn('python3',[path.join(__dirname,'serve_progress_tracker.py'),'--root',fixture,'--port','0'],{cwd:root,stdio:['ignore','pipe','pipe']});
  let log='';server.stderr.on('data',data=>log+=data);
  url=await new Promise((resolve,reject)=>{let output='';const timer=setTimeout(()=>reject(Error('Fixture server failed: '+log)),10000);server.stdout.on('data',data=>{output+=data;const match=output.match(/Tracker: (http:\/\/127\.0\.0\.1:\d+)/);if(match){clearTimeout(timer);resolve(match[1]);}});server.once('exit',()=>reject(Error('Fixture server exited: '+log)));});
  browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',args:['--no-sandbox']});
  page=await browser.newPage({viewport:{width:1179,height:958}});page.on('pageerror',error=>errors.push(error.message));page.on('request',request=>{if(request.method()==='PUT'&&request.url().endsWith('/api/tracker'))saves++;});
  await page.goto(url+'/docs/tracker/');await saved();await page.click('[data-book="art"]');await page.click('#clear-filters');
  await group('descriptions follow the selected file without changing its name',async()=>{
   await open(first);assert.equal(await page.textContent('#detail-title'),first.title);assert.equal(await page.textContent('#detail-description'),first.description);
   assert.equal(await page.locator('#detail').getAttribute('aria-describedby'),'detail-description');
   await page.click('#close-detail');await open(second);const description=await page.textContent('#detail-description');assert.ok(description.trim());assert.notEqual(description,first.description);assert.match(description,/document|markdown|MD/i);
   await page.click('#close-detail');await open(first);
  });
  await group('related-feature search matches normalized words and preserves hidden selections',async()=>{
   const before=fs.readFileSync(statePath,'utf8'),beforeSaves=saves;
   for(const query of ['MOTION_shared','locomotion slope','controls motion']){await search(query);assert.deepEqual(await visibleRelations(),[motion.title]);}
   await search('PREPARATION_spell');assert.deepEqual(await visibleRelations(),[magic.title]);assert.equal(await page.locator('.relation-list input:checked').count(),1,'Filtering retains the hidden checked relation');
   await search('zzzz_unmatched');assert.deepEqual(await visibleRelations(),[]);assert.match(await page.textContent('#related-feature-count'),/0/);assert.match(await page.textContent('#related-feature-count'),/1.*selected/i);
   await page.waitForTimeout(600);assert.equal(saves,beforeSaves,'Searching does not save tracking');assert.equal(fs.readFileSync(statePath,'utf8'),before);
   await search('casting');await page.locator('.relation-list label:visible input').check();await saved();assert.match(await page.textContent('#related-feature-count'),/2.*selected/i);
   await search('');assert.equal(await page.locator('.relation-list input:checked').count(),2);
   const state=JSON.parse(fs.readFileSync(statePath,'utf8'));assert.deepEqual(state.items[first.id].related.sort(),[motion.id,magic.id].sort());assert.equal(state.items[first.id].note,initial.note);
  });
  await group('relations survive reload and changing queries never clears a selection',async()=>{
   await page.click('#close-detail');await page.reload();await saved();await open(first);assert.equal(await page.locator('.relation-list input:checked').count(),2);
   await search('slope');await page.locator('.relation-list label:visible input').uncheck();await saved();await search('casting');assert.equal(await page.locator('.relation-list label:visible input').isChecked(),true);
   await search('');assert.equal(await page.locator('.relation-list input:checked').count(),1);assert.deepEqual(JSON.parse(fs.readFileSync(statePath,'utf8')).items[first.id].related,[magic.id]);
  });
  await group('review and tracking controls retain labels and visible state colors',async()=>{
   const review=page.locator('#art-review-label');await review.selectOption('Approved');assert.equal(await review.getAttribute('data-state'),'approved');const green=rgb(await color('#art-review-label'));assert.ok(green[1]>green[0]&&green[1]>green[2],'Approved has a green bar');
   await review.selectOption('Scrap');assert.equal(await review.getAttribute('data-state'),'scrap');const yellow=rgb(await color('#art-review-label'));assert.ok(yellow[0]>yellow[2]&&yellow[1]>yellow[2],'Scrap has a yellow bar');
   const colors=new Set();for(const status of M.statuses){await page.selectOption('#detail-status',status);assert.equal(await page.locator('#detail-status').getAttribute('data-state'),status.toLowerCase().replace(/ /g,'-'));assert.equal(await page.inputValue('#detail-status'),status);colors.add(await color('#detail-status'));}
   assert.equal(colors.size,M.statuses.length,'Tracking states have distinguishable colored bars');await saved();await page.click('#close-detail');await page.click('[data-art-mode="scrap"]');
   const red=rgb(await page.locator('#scrap-delete').evaluate(node=>getComputedStyle(node).backgroundColor));assert.ok(red[0]>red[1]&&red[0]>red[2],'Delete stays red');await card(first).locator('h2 button').click();
  });
  await group('keyboard search and narrow detail layouts remain usable',async()=>{
   await page.setViewportSize({width:390,height:850});await page.locator('#related-feature-search').focus();await page.keyboard.type('casting');assert.deepEqual(await visibleRelations(),[magic.title]);await page.keyboard.press('Tab');
   assert.notEqual(await page.evaluate(()=>document.activeElement.tagName),'BODY');assert.ok(await page.locator('#detail').evaluate(node=>node.scrollWidth<=node.clientWidth+1),'Detail content does not overflow horizontally');
   assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
   const output=path.join(root,'.artifacts/tracker');fs.mkdirSync(output,{recursive:true});await page.screenshot({path:path.join(output,'detail-search-mobile.png')});
   await page.locator('#detail').evaluate(node=>{node.scrollTop=0;});await page.screenshot({path:path.join(output,'detail-status-mobile.png')});
   await page.setViewportSize({width:1179,height:958});await page.screenshot({path:path.join(output,'detail-status-desktop.png')});
  });
  await group('static read-only details still allow relationship discovery',async()=>{
   const offline=await browser.newPage();await offline.goto(pathToFileURL(path.join(tracker,'index.html')).href);assert.match(await offline.textContent('#save-state'),/Read-only/);await offline.click('[data-book="art"]');await offline.click('#clear-filters');await open(first,offline);
   assert.equal(await offline.locator('#related-feature-search').isEnabled(),true);await search('slope',offline);assert.deepEqual(await visibleRelations(offline),[motion.title]);assert.equal(await offline.locator('.relation-list label:visible input').isDisabled(),true);await offline.close();
  });
  assert.deepEqual(errors,[]);console.log(`${groups.length} detail-panel browser groups passed.`);
 }finally{await browser?.close();if(server&&server.exitCode===null){const stopped=new Promise(resolve=>server.once('exit',resolve));server.kill();await stopped;}fs.rmSync(fixture,{recursive:true,force:true});}
})().catch(error=>{console.error(error);process.exitCode=1;});
