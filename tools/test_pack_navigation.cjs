// Pack review navigation uses a disposable catalog and metadata file throughout.
'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const {spawn}=require('node:child_process'),{pathToFileURL}=require('node:url'),{chromium}=require('playwright');
const M=require('../docs/tracker/model.js');
const root=path.resolve(__dirname,'..'),fixture=fs.mkdtempSync(path.join(os.tmpdir(),'ashen-pack-navigation-'));
const tracker=path.join(fixture,'docs/tracker'),statePath=path.join(tracker,'tracking.json');
const source=JSON.parse(fs.readFileSync(path.join(root,'docs/tracker/catalog.json'),'utf8'));
function write(relative,value){const file=path.join(fixture,relative);fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,value);}
fs.mkdirSync(tracker,{recursive:true});
for(const name of fs.readdirSync(path.join(root,'docs/tracker')))if(/\.(js|css|html)$/.test(name)&&name!=='data.js')fs.copyFileSync(path.join(root,'docs/tracker',name),path.join(tracker,name));
const selected=new Set([59,60,64]);
const members=Array.from({length:65},(_,index)=>({
 id:'art:pack-navigation-'+index,title:(selected.has(index)?'Selected':'Context')+' frame '+String(index+1).padStart(2,'0'),
 path:'art_source/pack_navigation/frame_'+String(index+1).padStart(2,'0')+'.png',
 url:'../../art_source/pack_navigation/frame_'+String(index+1).padStart(2,'0')+'.png',
 kind:'Images',types:['Images'],collections:[],origin:'Project files',role:'',image:true,
 missing:index===2,clip_names:[],clip_status:'not_applicable'
}));
const pack={id:'art:pack:navigation-fixture',title:'Navigation fixture pack',description:'A disposable ordered review fixture.',kind:'Image packs',types:['Images'],collections:[],origin:'Project files',origins:['Project files'],role:'',members:members.map(entry=>entry.id),cover:members[0].id,url:members[0].url,image:true,missing:false,missing_count:1,sources:[]};
const catalog={features:[],art:members,packs:[pack],animation_clips:[],animation_categories:[],animation_taxonomy:source.animation_taxonomy};
const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jP7sAAAAASUVORK5CYII=','base64');
for(const entry of members)if(!entry.missing)write(entry.path,png);
write('docs/tracker/catalog.json',JSON.stringify(catalog));write('docs/tracker/data.js','window.TRACKER_DATA='+JSON.stringify(catalog)+';\n');
write('tools/art_animation_taxonomy.json',JSON.stringify(source.animation_taxonomy));
write('docs/tracker/tracking.json',JSON.stringify({version:M.version,revision:0,items:{},history:[]}));
let browser,server,page,url,saves=0;const groups=[],errors=[];
const readState=()=>JSON.parse(fs.readFileSync(statePath,'utf8'));
const tile=(index,target=page)=>target.locator(`#pack-members .pack-member[data-id="${members[index].id}"]`);
const card=(target=page)=>target.locator(`#results .entry[data-id="${pack.id}"]`);
async function group(name,body){await body();groups.push(name);console.log('PASS '+name);}
async function saved(){await page.waitForFunction(()=>document.getElementById('save-state').textContent==='Saved to project');}
async function openPack(target=page){await card(target).locator('.pack-open').click();await target.locator('#pack-dialog').waitFor({state:'visible'});}
async function position(index,total=members.length,target=page){assert.equal((await target.textContent('#pack-image-position')).trim(),`Image ${index} of ${total}`);}
async function closeDetail(target=page){await target.click('#close-detail');await target.locator('#detail').waitFor({state:'hidden'});}
async function memberTitle(index,target=page){assert.equal(await target.textContent('#detail-title'),members[index].title);}
async function saveField(id,field,value){await page.waitForFunction(async({id,field,value})=>{const data=await fetch('/api/tracker').then(r=>r.json());return JSON.stringify(data.items[id]?.[field])===JSON.stringify(value);},{id,field,value});await saved();}
(async()=>{
 try{
  server=spawn('python3',[path.join(__dirname,'serve_progress_tracker.py'),'--root',fixture,'--port','0'],{cwd:root,stdio:['ignore','pipe','pipe']});
  let log='';server.stderr.on('data',data=>log+=data);
  url=await new Promise((resolve,reject)=>{let output='';const timer=setTimeout(()=>reject(Error('Fixture startup failed: '+log)),10000);server.stdout.on('data',data=>{output+=data;const match=output.match(/Tracker: (http:\/\/127\.0\.0\.1:\d+)/);if(match){clearTimeout(timer);resolve(match[1]);}});server.once('exit',()=>reject(Error('Fixture server exited: '+log)));});
  browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',args:['--no-sandbox']});
  page=await browser.newPage({viewport:{width:1179,height:958}});page.on('pageerror',error=>errors.push(error.message));page.on('request',request=>{if(request.method()==='PUT'&&request.url().endsWith('/api/tracker'))saves++;});
  await page.goto(url+'/docs/tracker/');await saved();await page.click('[data-book="art"]');await page.click('#clear-filters');
  await group('pack covers navigate in manifest order without changing metadata',async()=>{
   await openPack();await page.getByRole('button',{name:'Pack details & notes',exact:true}).click();
   assert.equal(await page.textContent('#detail-title'),pack.title);await position(1);assert.equal(await page.locator('#previous-pack-image').isDisabled(),true);
   assert.equal(await page.locator('#next-pack-image').getAttribute('aria-label'),'Next image');
   const before=readState(),beforeSaves=saves;
   await page.click('#next-pack-image');await memberTitle(1);await position(2);
   await page.click('#previous-pack-image');await memberTitle(0);await position(1);
   await page.locator('#close-detail').focus();await page.keyboard.press('ArrowLeft');await memberTitle(0);await position(1);
   await page.waitForTimeout(600);assert.equal(saves,beforeSaves);assert.deepEqual(readState(),before,'Navigation does not create tracking activity');await closeDetail();
  });
  await group('arrow navigation crosses pagination and never wraps past the final image',async()=>{
   assert.equal(await page.locator('#pack-members .pack-member').count(),60);await tile(59).click();await position(60);
   await page.click('#next-pack-image');await memberTitle(60);await position(61);
   for(let index=61;index<65;index++){await page.locator('#close-detail').focus();await page.keyboard.press('ArrowRight');await memberTitle(index);await position(index+1);}
   assert.equal(await page.locator('#next-pack-image').isDisabled(),true);await page.keyboard.press('ArrowRight');await memberTitle(64);await position(65);
   await page.keyboard.press('ArrowLeft');await memberTitle(63);await position(64);await closeDetail();
   assert.equal(await page.locator('#pack-members .pack-member').count(),60,'Reviewing hidden pages does not expand the grid');
   assert.equal(await page.evaluate(()=>document.activeElement.closest('.pack-member')?.dataset.id),members[59].id,'Closing returns to the originally opened grid tile');
  });
  await group('filtered navigation keeps one snapshot through edits and editor re-renders',async()=>{
   await page.fill('#pack-search','selected');assert.equal(await page.locator('#pack-members .pack-member').count(),3);await tile(59).click();await position(1,3);
   await page.getByRole('textbox',{name:'New checklist task',exact:true}).fill('Inspect fixture edges');await page.getByRole('button',{name:'Add task',exact:true}).click();
   await position(1,3);await page.getByRole('checkbox',{name:'Complete Inspect fixture edges',exact:true}).check();await position(1,3);
   await page.locator('#display-name').fill('Renamed fixture image');await page.getByRole('button',{name:'Save name',exact:true}).click();await position(1,3);
   await page.click('#next-pack-image');await memberTitle(60);await position(2,3);await page.click('#next-pack-image');await memberTitle(64);await position(3,3);assert.equal(await page.locator('#next-pack-image').isDisabled(),true);
   await closeDetail();assert.equal(await page.inputValue('#pack-search'),'selected');assert.equal(await page.locator('#pack-members .pack-member').count(),3,'Original filename remains searchable after renaming');
   assert.equal(await page.evaluate(()=>document.activeElement.closest('.pack-member')?.dataset.id),members[59].id);await saveField(members[59].id,'display_name','Renamed fixture image');
   assert.deepEqual(readState().items[members[59].id].checklist.map(task=>[task.text,task.done]),[['Inspect fixture edges',true]]);
  });
  await group('notes and input keys stay with the image being edited',async()=>{
   await page.fill('#pack-search','');await tile(0).click();await page.locator('#entry-notes').fill('Only the first image receives this note.');
   await page.keyboard.press('ArrowRight');await memberTitle(0);await position(1);await page.locator('#display-name').fill('Unsaved first-image title');await page.keyboard.press('ArrowRight');await memberTitle(0);
   await page.getByRole('textbox',{name:'New checklist task',exact:true}).fill('Unsubmitted first-image task');
   await page.locator('#detail-status').focus();await page.keyboard.press('ArrowLeft');await memberTitle(0);
   await page.click('#next-pack-image');await memberTitle(1);assert.equal(await page.inputValue('#entry-notes'),'');assert.equal(await page.inputValue('#display-name'),members[1].title);assert.equal(await page.getByRole('textbox',{name:'New checklist task',exact:true}).inputValue(),'');
   await page.click('#previous-pack-image');await memberTitle(0);assert.equal(await page.inputValue('#display-name'),'Unsaved first-image title');assert.equal(await page.getByRole('textbox',{name:'New checklist task',exact:true}).inputValue(),'Unsubmitted first-image task');
   await page.click('#next-pack-image');await saveField(members[0].id,'note','Only the first image receives this note.');assert.equal(readState().items[members[0].id].display_name,'');assert.deepEqual(readState().items[members[0].id].checklist,[]);
   assert.equal(readState().items[members[1].id],undefined,'Navigation does not save the previous image edits to the next image');
   await closeDetail();await page.getByRole('button',{name:'Pack details & notes',exact:true}).click();await page.locator('#entry-notes').fill('Only the pack receives this note.');
   await page.click('#next-pack-image');await memberTitle(1);assert.equal(await page.inputValue('#entry-notes'),'');await saveField(pack.id,'note','Only the pack receives this note.');
   assert.equal(readState().items[members[0].id].note,'Only the first image receives this note.');assert.equal(readState().items[members[1].id],undefined);await closeDetail();
  });
  await group('missing images remain navigable and show their own unavailable state',async()=>{
   await tile(1).click();await page.click('#next-pack-image');await memberTitle(2);await position(3);assert.match(await page.textContent('#detail-body'),/missing|unavailable/i);
   assert.equal(await page.locator('#detail-body img.large-preview').count(),0,'A missing image never retains the previous file preview');
   await page.click('#next-pack-image');await memberTitle(3);await position(4);assert.equal(await page.locator('#detail-body img.large-preview').count(),1);await closeDetail();
  });
  await group('mobile review controls fit and Escape restores the pack browser',async()=>{
   await page.fill('#pack-search','selected');await tile(60).click();await position(2,3);
   const artifacts=path.join(root,'.artifacts/tracker');fs.mkdirSync(artifacts,{recursive:true});await page.screenshot({path:path.join(artifacts,'pack-navigation-desktop.png')});
   await page.setViewportSize({width:390,height:850});assert.ok(await page.locator('#detail').evaluate(node=>node.scrollWidth<=node.clientWidth+1));assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
   assert.equal(await page.getByRole('button',{name:'Previous image',exact:true}).isVisible(),true);assert.equal(await page.getByRole('button',{name:'Next image',exact:true}).isVisible(),true);
   await page.click('#next-pack-image');await position(3,3);await page.screenshot({path:path.join(artifacts,'pack-navigation-mobile.png')});
   await page.locator('#close-detail').focus();await page.keyboard.press('Escape');await page.locator('#detail').waitFor({state:'hidden'});assert.equal(await page.locator('#pack-dialog').isVisible(),true);assert.equal(await page.inputValue('#pack-search'),'selected');
   assert.equal(await page.evaluate(()=>document.activeElement.closest('.pack-member')?.dataset.id),members[60].id);await page.click('#close-pack');await saved();
  });
  await group('static read-only browsing supports pack arrows without enabling editing',async()=>{
   const offline=await browser.newPage({viewport:{width:390,height:850}});offline.on('pageerror',error=>errors.push(error.message));
   await offline.goto(pathToFileURL(path.join(tracker,'index.html')).href);assert.match(await offline.textContent('#save-state'),/Read-only/);await offline.click('[data-book="art"]');await offline.click('#clear-filters');await openPack(offline);await tile(0,offline).click();
   await position(1,65,offline);assert.equal(await offline.locator('#next-pack-image').isEnabled(),true);assert.equal(await offline.locator('#entry-notes').isDisabled(),true);
   await offline.click('#next-pack-image');await memberTitle(1,offline);await position(2,65,offline);assert.equal(await offline.locator('#previous-pack-image').isEnabled(),true);await offline.close();
  });
  assert.deepEqual(errors,[]);console.log(`${groups.length} pack-navigation browser groups passed; all edits used disposable files.`);
 }finally{await browser?.close();if(server&&server.exitCode===null){const stopped=new Promise(resolve=>server.once('exit',resolve));server.kill();await stopped;}fs.rmSync(fixture,{recursive:true,force:true});}
})().catch(error=>{console.error(error);process.exitCode=1;});
