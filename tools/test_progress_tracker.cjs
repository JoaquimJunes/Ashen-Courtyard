// Run with Playwright in NODE_PATH; CHROMIUM_PATH optionally selects the browser.
const {chromium}=require('playwright'),assert=require('node:assert/strict'),path=require('node:path'),fs=require('node:fs'),os=require('node:os');
const {spawn}=require('node:child_process'),{pathToFileURL}=require('node:url');
const root=path.resolve(__dirname,'..'),temp=fs.mkdtempSync(path.join(os.tmpdir(),'ashen-books-test-'));
const statePath=path.join(temp,'tracking.json');let server,browser,port;
async function start(){
 if(!port){const s=require('node:net').createServer();await new Promise(r=>s.listen(0,'127.0.0.1',r));port=s.address().port;await new Promise(r=>s.close(r));}
 server=spawn('python3',[path.join(__dirname,'serve_progress_tracker.py'),'--port',String(port),'--state',statePath],{cwd:root,stdio:['ignore','pipe','pipe']});
 let log='';server.stderr.on('data',b=>log+=b);const url=`http://127.0.0.1:${port}`;
 for(let i=0;i<100;i++){try{const r=await fetch(url+'/api/tracker');if(r.ok)return url;}catch(e){}await new Promise(r=>setTimeout(r,50));}
 throw Error('Server failed: '+log);
}
async function stop(){if(server&&server.exitCode===null){const done=new Promise(r=>server.once('exit',r));server.kill();await done;}}
(async()=>{
 try{
  const url=await start();browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH,args:['--no-sandbox']});
  const context=await browser.newContext(),page=await context.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.addInitScript(()=>localStorage.setItem('ashen-progress-v1',JSON.stringify({running:{review:'Reviewed',note:'Keep my old review'}})));
  await page.goto(url+'/docs/tracker/');await page.waitForFunction(()=>document.getElementById('save-state').textContent==='Saved to project');
  assert.equal(await page.locator('h1').textContent(),'Dev book');assert.ok(await page.locator('.entry').count()>=40);
  await page.click('#migrate');await page.locator('#preview').waitFor({state:'visible'});assert.match(await page.locator('#preview-body').textContent(),/Keep my old review/);
  assert.equal(fs.existsSync(statePath),false,'Preview must not write');await page.click('#confirm-import');
  await page.waitForFunction(()=>document.getElementById('save-state').textContent==='Saved to project');
  assert.equal(await page.locator('#migration').isVisible(),false);
  let data=JSON.parse(fs.readFileSync(statePath));assert.equal(data.items.running.status,'Ready for review');assert.match(data.items.running.note,/Reviewed/);
  await page.fill('#search','Shared character motion');assert.ok(await page.locator('.entry').count()>=1);assert.equal(await page.locator('.entry').first().getAttribute('data-id'),'shared-motion');
  const row=page.locator('.entry').first(),id=await row.getAttribute('data-id');await row.locator('h2 button').click();
  await page.selectOption('#detail-status','Completed');
  assert.equal(await page.inputValue('#detail-status'),'Ready for review');
  assert.match(await page.textContent('#detail-completion-help'),/add at least one checklist task/);
  assert.equal(await page.getByRole('textbox',{name:'New checklist task',exact:true}).evaluate(n=>n===document.activeElement),true);
  await page.getByRole('textbox',{name:'New checklist task',exact:true}).fill('Existing behavior reviewed');await page.getByRole('button',{name:'Add task',exact:true}).click();
  await page.locator('.task-done').check();await page.selectOption('#detail-status','Completed');
  await page.locator('.flags').getByText('Bug found',{exact:true}).click();
  await page.fill('#entry-notes','Review <script>no execution</script>');await page.click('#close-detail');
  await page.waitForFunction(()=>document.getElementById('save-state').textContent==='Saved to project');
  data=JSON.parse(fs.readFileSync(statePath));assert.equal(data.items[id].status,'Completed');assert.deepEqual(data.items[id].attention,['Bug found']);assert.equal(data.items[id].checklist[0].done,true);
  await page.selectOption('#view','Completed');assert.equal(await page.locator('.entry').count(),1);
  await page.selectOption('#view','attention');assert.equal(await page.locator('.entry[data-id="'+id+'"]').count(),1);assert.ok(await page.locator('.entry').evaluateAll(rows=>rows.every(row=>row.querySelector('.badge.warn'))));
  await page.click('[data-book=art]');assert.equal(await page.locator('h1').textContent(),'Art Book');assert.ok(await page.locator('.entry').count()<=60);
  await page.fill('#search','MainKnightReference');assert.equal(await page.locator('.entry').count(),1);
  await page.waitForFunction(()=>document.querySelector('.entry img')?.naturalWidth>0);const artId=await page.locator('.entry').getAttribute('data-id');
  await page.locator('.entry h2 button').click();await page.locator('.relation-list label').filter({hasText:'Shared character motion'}).locator('input').check();await page.click('#close-detail');
  await page.waitForFunction(()=>document.getElementById('save-state').textContent==='Saved to project');assert.ok(JSON.parse(fs.readFileSync(statePath)).items[artId].related.includes(id));
  await page.click('[data-book=dev]');assert.equal(await page.inputValue('#search'),'Shared character motion');assert.equal(await page.inputValue('#view'),'attention');
  await page.locator('.entry[data-id="'+id+'"] h2 button').click();assert.match(await page.locator('#detail-body').textContent(),/MainKnightReference/);await page.click('#close-detail');
  const downloadPromise=page.waitForEvent('download');await page.click('#export');const backup=JSON.parse(fs.readFileSync(await (await downloadPromise).path()));assert.equal(backup.version,5);
  await page.setInputFiles('#import',{name:'bad.json',mimeType:'application/json',buffer:Buffer.from('{"version":99}')});assert.match(await page.locator('#message').textContent(),/rejected/);
  await page.setInputFiles('#import',{name:'backup.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(backup))});await page.locator('#preview').waitFor({state:'visible'});await page.click('#cancel-import');
  // Exported activity can exceed 4 MB while metadata stays small.
  const large={...backup,history:Array.from({length:450},()=>({at:new Date().toISOString(),id,fields:['note'],before:{...data.items[id],note:'x'.repeat(10000)},after:data.items[id]}))};
  await page.setInputFiles('#import',{name:'large-backup.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(large))});await page.locator('#preview').waitFor({state:'visible'});await page.click('#cancel-import');
  // Two tabs must not overwrite one another; a conflict retains the unsaved draft.
  const other=await context.newPage();await other.goto(url+'/docs/tracker/');await other.waitForFunction(()=>document.getElementById('save-state').textContent==='Saved to project');
  await page.locator('.entry[data-id="'+id+'"] select').selectOption('Deferred');await page.waitForFunction(()=>document.getElementById('save-state').textContent==='Saved to project');
  await other.fill('#search','Shared character motion');await other.selectOption('#view','all');await other.locator('.entry[data-id="'+id+'"] select').selectOption('In progress');
  await other.waitForFunction(()=>document.getElementById('save-state').textContent==='Save failed');assert.match(await other.locator('#connection').textContent(),/Another tab/);
  assert.equal(JSON.parse(fs.readFileSync(statePath)).items[id].status,'Deferred');
  const recoverDownload=other.waitForEvent('download');await other.click('#export');const recovery=JSON.parse(fs.readFileSync(await (await recoverDownload).path()));assert.equal(recovery.hasUnsavedEdits,true);assert.deepEqual(Object.keys(recovery.pendingChanges),[id]);
  assert.equal(await other.locator('.entry[data-id="'+id+'"] select').isDisabled(),true);
  await other.evaluate(()=>window.onbeforeunload=null);await other.close({runBeforeUnload:false});
  await stop();await start();await page.reload();await page.waitForFunction(()=>document.getElementById('save-state').textContent==='Saved to project');
  await page.selectOption('#view','all');assert.equal(await page.locator('.entry[data-id="'+id+'"] select').inputValue(),'Deferred');
  // Save failure also retains a draft and must never pretend to save.
  await page.route('**/api/tracker',route=>route.request().method()==='PUT'?route.fulfill({status:503,contentType:'application/json',body:'{"error":"Disk unavailable"}'}):route.continue());
  await page.locator('.entry[data-id="'+id+'"] select').selectOption('In progress');await page.waitForFunction(()=>document.getElementById('save-state').textContent==='Save failed');assert.match(await page.locator('#connection').textContent(),/Disk unavailable/);
  await page.unroute('**/api/tracker');await page.getByRole('button',{name:'Retry saving',exact:true}).click();await page.waitForFunction(()=>document.getElementById('save-state').textContent==='Saved to project');
  await page.click('#history');assert.ok(await page.locator('.history-event').count()>0);await page.click('#close-activity');
  await page.click('#clear-filters');
  await page.evaluate(()=>window.scrollTo(0,1000));await page.waitForFunction(()=>window.scrollY>=950);
  await page.click('[data-book=art]');await page.click('[data-book=dev]');await page.waitForFunction(()=>window.scrollY>=950);
  await page.keyboard.press('Tab');assert.ok(await page.evaluate(()=>document.activeElement!==document.body));
  for(const width of [1200,390]){await page.setViewportSize({width,height:850});assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));}
  await page.setViewportSize({width:1280,height:900});await page.evaluate(()=>window.scrollTo(0,0));fs.mkdirSync(path.join(root,'.artifacts/tracker'),{recursive:true});await page.screenshot({path:path.join(root,'.artifacts/tracker/dev-book.png')});
  await page.click('[data-book=art]');await page.fill('#search','MainKnightReference');await page.screenshot({path:path.join(root,'.artifacts/tracker/art-book.png')});
  const offline=await context.newPage();await offline.goto(pathToFileURL(path.join(root,'docs/tracker/index.html')).href);assert.match(await offline.locator('#save-state').textContent(),/Read-only/);assert.equal(await offline.locator('.entry select').first().isDisabled(),true);
  assert.deepEqual(errors,[]);console.log('Browser: both books, progress/completion, flags, links, migration, backups, conflicts, restart, failed saves, filters, offline and responsive checks passed.');
 }finally{if(browser)await browser.close();await stop();fs.rmSync(temp,{recursive:true,force:true});}
})().catch(e=>{console.error(e);process.exitCode=1;});
