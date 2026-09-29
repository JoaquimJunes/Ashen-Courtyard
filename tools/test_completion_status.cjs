// Completion intent and saves run against an isolated project and annotation file.
'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const {spawn}=require('node:child_process'),{chromium}=require('playwright');
const M=require('../docs/tracker/model.js'),root=path.resolve(__dirname,'..');
const fixture=fs.mkdtempSync(path.join(os.tmpdir(),'ashen-completion-status-')),tracker=path.join(fixture,'docs/tracker'),statePath=path.join(tracker,'tracking.json');
const artifacts=path.join(root,'.artifacts/tracker');fs.mkdirSync(artifacts,{recursive:true});
const source=JSON.parse(fs.readFileSync(path.join(root,'docs/tracker/catalog.json'),'utf8'));
function write(relative,value){const file=path.join(fixture,relative);fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,value);}
fs.mkdirSync(tracker,{recursive:true});
for(const name of fs.readdirSync(path.join(root,'docs/tracker')))if(/\.(js|css|html)$/.test(name)&&name!=='data.js')fs.copyFileSync(path.join(root,'docs/tracker',name),path.join(tracker,name));
const feature=(id,title)=>({...source.features[0],id,title,summary:'Disposable completion workflow fixture.',area:'Systems',topic:'Character architecture',checklist:[],sources:['docs/completion_fixture.md']});
const unassessed=feature('completion-unassessed','Unassessed development fixture'),review=feature('completion-review','Unchecked development fixture'),eligible=feature('completion-eligible','Ready development fixture');
const image=(id,title)=>({id:'art:'+id,title,path:'art_source/completion/'+id+'.png',url:'../../art_source/completion/'+id+'.png',kind:'Images',types:['Images'],collections:[],origin:'Project files',role:'',image:true,missing:false,clip_names:[],clip_status:'not_applicable'});
const artEmpty=image('completion-unassessed','Unassessed image fixture'),artReview=image('completion-review','Unchecked image fixture');
const task=(id,done)=>({id,text:'Review '+id,done,source:''});
const items={
 [unassessed.id]:{...M.defaults(unassessed),status:'In progress',note:'Keep the unassessed note.'},
 [review.id]:{...M.defaults(review),status:'Ready for review',attention:['Bug found','Needs testing'],priority:'High',note:'Keep the development review note.',checklist:[task('already verified',true),task('remaining behavior',false)]},
 [eligible.id]:{...M.defaults(eligible),status:'Ready for review',attention:['Needs improvement'],note:'Keep the ready review note.',checklist:[task('ready behavior',true)]},
 [artEmpty.id]:{...M.defaults(artEmpty),note:'Keep the unassessed image note.'},
 [artReview.id]:{...M.defaults(artReview),status:'In progress',attention:['Needs visual review'],review_label:'Approved',note:'Keep the image review note.',checklist:[task('image edges',false)]}
};
const catalog={features:[unassessed,review,eligible],art:[artEmpty,artReview],packs:[],animation_clips:[],animation_categories:[],animation_taxonomy:source.animation_taxonomy};
write('docs/tracker/catalog.json',JSON.stringify(catalog));write('docs/tracker/data.js','window.TRACKER_DATA='+JSON.stringify(catalog)+';\n');write('tools/art_animation_taxonomy.json',JSON.stringify(source.animation_taxonomy));
write('docs/completion_fixture.md','# Completion fixture\nExisting test evidence only.\n');
const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jP7sAAAAASUVORK5CYII=','base64');
for(const entry of [artEmpty,artReview])write(entry.path,png);
write('docs/tracker/tracking.json',JSON.stringify({version:M.version,revision:0,items,history:[]}));
let browser,server,page,url,log='',putRequests=0;const groups=[],errors=[];
const read=()=>JSON.parse(fs.readFileSync(statePath,'utf8'));
const row=e=>page.locator(`#results .entry[data-id="${e.id}"]`);
async function group(name,body){await body();groups.push(name);console.log('PASS '+name);}
async function saved(){await page.waitForFunction(()=>document.getElementById('save-state').textContent==='Saved to project');}
async function savedRecord(id,fields){await page.waitForFunction(async({id,fields})=>{const response=await fetch('/api/tracker');const state=await response.json();return Object.entries(fields).every(([field,value])=>JSON.stringify(state.items[id]?.[field])===JSON.stringify(value));},{id,fields});await saved();}
async function closeDetail(){await page.click('#close-detail');await page.locator('#detail').waitFor({state:'hidden'});}
async function open(e){await row(e).locator('h2 button').click();await page.locator('#detail').waitFor({state:'visible'});}
async function focused(selector){await page.waitForFunction(selector=>document.activeElement?.matches(selector),selector);}
async function noMutation(before,requests){await page.waitForTimeout(600);assert.deepEqual(read(),before);assert.equal(putRequests,requests,'Completion guidance must not save or check tasks');}
function preserved(e){const current=read().items[e.id];for(const field of ['attention','priority','note','review_label'])assert.deepEqual(current[field],items[e.id][field],`${e.title}: ${field} preserved`);}
(async()=>{try{
 server=spawn('python3',[path.join(__dirname,'serve_progress_tracker.py'),'--root',fixture,'--port','0'],{cwd:root,stdio:['ignore','pipe','pipe']});server.stderr.on('data',data=>log+=data);
 url=await new Promise((resolve,reject)=>{let output='';const timer=setTimeout(()=>reject(Error('Fixture startup failed: '+log)),10000);server.stdout.on('data',data=>{output+=data;const match=output.match(/Tracker: (http:\/\/127\.0\.0\.1:\d+)/);if(match){clearTimeout(timer);resolve(match[1]);}});server.once('exit',()=>{clearTimeout(timer);reject(Error('Fixture server exited: '+log));});});
 browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',args:['--no-sandbox']});page=await browser.newPage({viewport:{width:1100,height:900}});page.on('pageerror',error=>errors.push(error.message));page.on('request',request=>{if(request.method()==='PUT'&&request.url().endsWith('/api/tracker'))putRequests++;});await page.goto(url+'/docs/tracker/');await saved();
 await group('Dev quick completion with no checklist opens guidance without saving',async()=>{
  const before=read(),requests=putRequests,status=row(unassessed).getByRole('combobox',{name:'Status for '+unassessed.title});assert.equal(await status.locator('option[value="Completed"]').isDisabled(),false);await status.selectOption('Completed');await page.locator('#detail').waitFor({state:'visible'});
  assert.equal(await page.textContent('#detail-title'),unassessed.title);await focused('#detail .add-task input');assert.equal(await page.inputValue('#detail-status'),'In progress');assert.match(await page.textContent('#detail-completion-help'),/checklist|task/i);assert.match(await page.textContent('#completion-guidance'),/add|checklist|task/i);assert.equal(await page.locator('#detail .task-done').count(),0);await noMutation(before,requests);await closeDetail();
 });
 await group('Dev quick completion focuses the first unchecked task and retains prior checks',async()=>{
  const before=read(),requests=putRequests;await row(review).getByRole('combobox',{name:'Status for '+review.title}).selectOption('Completed');await page.locator('#detail').waitFor({state:'visible'});await focused('#detail .task-done:not(:checked)');
  assert.deepEqual(await page.locator('#detail .task-done').evaluateAll(tasks=>tasks.map(task=>task.checked)),[true,false]);assert.equal(await page.inputValue('#detail-status'),'Ready for review');assert.match(await page.textContent('#completion-guidance'),/remaining|unchecked|finish|check/i);await noMutation(before,requests);
 });
 await group('the last check needs a separate explicit Mark Completed action',async()=>{
  await page.getByRole('checkbox',{name:'Complete Review remaining behavior',exact:true}).check();await savedRecord(review.id,{status:'Ready for review',checklist:[task('already verified',true),task('remaining behavior',true)]});
  assert.equal(await page.locator('#mark-completed').isEnabled(),true);assert.equal(await page.locator('#mark-completed').textContent(),'Mark Completed');await page.click('#mark-completed');await savedRecord(review.id,{status:'Completed'});preserved(review);await closeDetail();
  await page.reload();await saved();assert.equal(await row(review).getByRole('combobox',{name:'Status for '+review.title}).inputValue(),'Completed');assert.deepEqual(read().items[review.id].attention,['Bug found','Needs testing']);
 });
 await group('an already eligible quick dropdown can save Completed directly',async()=>{
  await row(eligible).getByRole('combobox',{name:'Status for '+eligible.title}).selectOption('Completed');await savedRecord(eligible.id,{status:'Completed'});assert.equal(await page.locator('#detail').isVisible(),false);preserved(eligible);
 });
 await group('reopening a completed checklist requires confirmation and never re-completes automatically',async()=>{
  await open(review);const before=read(),requests=putRequests;page.once('dialog',dialog=>dialog.dismiss());await page.getByRole('checkbox',{name:'Complete Review remaining behavior',exact:true}).click();assert.equal(await page.getByRole('checkbox',{name:'Complete Review remaining behavior',exact:true}).isChecked(),true);await noMutation(before,requests);
  page.once('dialog',dialog=>{assert.match(dialog.message(),/Reopen.*In progress/);return dialog.accept();});await page.getByRole('checkbox',{name:'Complete Review remaining behavior',exact:true}).uncheck();await savedRecord(review.id,{status:'In progress',checklist:items[review.id].checklist});
  await page.selectOption('#detail-status','Completed');await focused('#detail .task-done:not(:checked)');assert.equal(await page.inputValue('#detail-status'),'In progress');await page.getByRole('checkbox',{name:'Complete Review remaining behavior',exact:true}).check();await savedRecord(review.id,{status:'In progress'});
  await page.click('#mark-completed');await savedRecord(review.id,{status:'Completed'});preserved(review);await closeDetail();
 });
 await group('Art detail gives missing-checklist guidance and leaves the image unassessed',async()=>{
  await page.click('[data-book="art"]');await page.click('#clear-filters');await open(artEmpty);const before=read(),requests=putRequests;assert.equal(await page.locator('#detail-status option[value="Completed"]').isDisabled(),false);await page.selectOption('#detail-status','Completed');await focused('#detail .add-task input');
  assert.equal(await page.inputValue('#detail-status'),'');assert.match(await page.textContent('#detail-completion-help'),/task|checklist/i);assert.match(await page.textContent('#completion-guidance'),/add|task|checklist/i);assert.equal(await page.locator('#detail .task-done').count(),0);await noMutation(before,requests);await closeDetail();
 });
 await group('Art completion keeps approval, flags and notes through failed-save retry',async()=>{
  await open(artReview);const before=read(),requests=putRequests;await page.selectOption('#detail-status','Completed');await focused('#detail .task-done:not(:checked)');await noMutation(before,requests);
  await page.getByRole('checkbox',{name:'Complete Review image edges',exact:true}).check();await savedRecord(artReview.id,{status:'In progress',checklist:[task('image edges',true)]});assert.equal(await page.inputValue('#detail-status'),'In progress');
  await page.route('**/api/tracker',route=>route.request().method()==='PUT'?route.fulfill({status:503,contentType:'application/json',body:JSON.stringify({code:'storage',error:'Simulated completion save failure'})}):route.continue());
  await page.click('#mark-completed');await page.waitForFunction(()=>document.getElementById('connection').textContent.includes('Simulated completion save failure'));assert.equal(read().items[artReview.id].status,'In progress');assert.deepEqual(read().items[artReview.id].checklist,[task('image edges',true)]);
  await page.unroute('**/api/tracker');await closeDetail();await page.getByRole('button',{name:'Retry saving',exact:true}).click();await savedRecord(artReview.id,{status:'Completed'});preserved(artReview);await page.reload();await saved();await open(artReview);assert.equal(await page.inputValue('#detail-status'),'Completed');preserved(artReview);await closeDetail();
 });
 assert.deepEqual(errors,[]);assert.deepEqual(read().items[unassessed.id],items[unassessed.id]);assert.deepEqual(read().items[artEmpty.id],items[artEmpty.id]);for(const entry of [artEmpty,artReview])assert.deepEqual(fs.readFileSync(path.join(fixture,entry.path)),png);
 fs.writeFileSync(path.join(artifacts,'completion-status-results.json'),JSON.stringify({passed:groups.length,groups,errors,isolated_project:true},null,2));console.log(`${groups.length} completion-status browser groups passed; all edits used disposable files.`);
}catch(error){if(page)await page.screenshot({path:path.join(artifacts,'completion-status-failure.png')}).catch(()=>{});fs.writeFileSync(path.join(artifacts,'completion-status-results.json'),JSON.stringify({passed:groups.length,groups,errors,failure:String(error),server_log:log.slice(-5000)},null,2));throw error;}
finally{await browser?.close();if(server&&server.exitCode===null){const stopped=new Promise(resolve=>server.once('exit',resolve));server.kill();await stopped;}fs.rmSync(fixture,{recursive:true,force:true});}})().catch(error=>{console.error(error);process.exitCode=1;});
