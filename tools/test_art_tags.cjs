// Subject-tag editing, migration and pack discovery use a disposable project.
'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const {spawn}=require('node:child_process'),{chromium}=require('playwright');
const M=require('../docs/tracker/model.js');
const root=path.resolve(__dirname,'..'),fixture=fs.mkdtempSync(path.join(os.tmpdir(),'ashen-art-tags-'));
const tracker=path.join(fixture,'docs/tracker');fs.mkdirSync(tracker,{recursive:true});
function write(name,data){const p=path.join(fixture,name);fs.mkdirSync(path.dirname(p),{recursive:true});fs.writeFileSync(p,data);}
for(const name of fs.readdirSync(path.join(root,'docs/tracker')))if(/\.(js|css|html)$/.test(name)&&name!=='data.js')fs.copyFileSync(path.join(root,'docs/tracker',name),path.join(tracker,name));
const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a6s8AAAAASUVORK5CYII=','base64');
const images=['alpha','beta','gamma'].map(name=>{const source=`art_source/${name}.png`;write(source,png);return {id:'art:'+name,title:name,path:source,kind:'Images',types:['Images'],origin:'Project files',image:true,url:'../../'+source,collections:[],clip_names:[]};});
const pack={id:'art:pack:pair',title:'Image pair',members:images.slice(0,2).map(e=>e.id),cover:images[0].id,kind:'Image packs',types:['Images'],origin:'Project files',collections:[],image:true,url:images[0].url};
const catalog={features:[],art:images,packs:[pack],animation_clips:[],animation_categories:[],animation_taxonomy:{categories:[],tags:[]}};
write('docs/tracker/catalog.json',JSON.stringify(catalog));write('docs/tracker/data.js','window.TRACKER_DATA='+JSON.stringify(catalog)+';');
write('tools/art_animation_taxonomy.json',JSON.stringify(catalog.animation_taxonomy));
const original={...M.defaults(images[0]),note:'Keep this note',review_label:'Approved',attention:['SPECIAL']};delete original.art_tags;
const legacy=JSON.stringify({version:4,revision:0,items:{'art:alpha':original},history:[]});write('docs/tracker/tracking.json',legacy);
let server,browser,page,url,port;const errors=[];
async function start(){
 server=spawn('python3',[path.join(__dirname,'serve_progress_tracker.py'),'--root',fixture,'--port',String(port||0)],{stdio:['ignore','pipe','pipe']});
 let log='';server.stderr.on('data',data=>log+=data);
 url=await new Promise((resolve,reject)=>{let output='';const timer=setTimeout(()=>reject(Error(log)),10000);server.stdout.on('data',data=>{output+=data;const m=output.match(/Tracker: (http:\/\/127\.0\.0\.1:(\d+))/);if(m){clearTimeout(timer);port=Number(m[2]);resolve(m[1]);}});server.once('exit',()=>{clearTimeout(timer);reject(Error(log));});});
}
async function stop(){if(server&&server.exitCode===null){const done=new Promise(r=>server.once('exit',r));server.kill();await done;}}
async function saved(){await page.waitForFunction(()=>document.getElementById('save-state').textContent==='Saved to project');}
async function data(){return (await page.request.get(url+'/api/tracker')).json();}
async function open(id){await page.locator(`#results .entry[data-id="${id}"] h2 button`).click();}
async function add(tag){await page.fill('#art-tag-input',tag);await page.getByRole('button',{name:'Add tag',exact:true}).click();}
async function rows(){return page.locator('#results .entry').evaluateAll(nodes=>nodes.map(n=>n.dataset.id));}
(async()=>{try{
 await start();browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',args:['--no-sandbox']});
 page=await browser.newPage({viewport:{width:1280,height:900}});page.on('pageerror',e=>errors.push(e.message));
 await page.goto(url+'/docs/tracker/');await saved();await page.click('[data-book="art"]');
 for(const tag of M.artTagSuggestions)assert.equal(await page.locator(`#art-filter-groups input[data-group="art_tags"][value="${tag}"]`).count(),1);
 assert.equal(fs.readFileSync(path.join(tracker,'tracking.json'),'utf8'),legacy,'Read-only migration leaves original bytes unchanged');
 await page.check('#show-individual-images');await open('art:alpha');
 await page.locator('.art-tag-choices').getByLabel('Combat',{exact:true}).check();await add('  Moon   Knights  ');await saved();
 let state=await data();assert.deepEqual(state.items['art:alpha'].art_tags,['Combat','Moon Knights']);
 for(const [key,value] of Object.entries(original))assert.deepEqual(state.items['art:alpha'][key],value);
 assert.equal(fs.readFileSync(path.join(tracker,'tracking.json.v4.bak'),'utf8'),legacy);
 const revision=state.revision;await add('moon knights');assert.match(await page.textContent('#art-tag-message'),/already/);assert.equal((await data()).revision,revision);
 await page.fill('#art-tag-input','x'.repeat(61));await page.getByRole('button',{name:'Add tag',exact:true}).click();assert.match(await page.textContent('#art-tag-message'),/60/);assert.equal((await data()).revision,revision);
 await page.click('#close-detail');await page.fill('#search','knights moon');assert.deepEqual(await rows(),['art:alpha']);
 await page.uncheck('#show-individual-images');assert.deepEqual(await rows(),[pack.id]);await open(pack.id);
 assert.equal(await page.locator('#pack-members .pack-member').count(),1);await page.getByRole('button',{name:'Show all images in this pack',exact:true}).click();
 await page.fill('#pack-search','Moon Knights');assert.equal(await page.locator('#pack-members .pack-member').count(),1);
 await page.click('#close-pack');await page.click('#clear-filters');await page.check('#show-individual-images');await open('art:beta');
 assert.equal(await page.locator('#art-tag-suggestions option[value="Moon Knights"]').count(),1,'Custom tags are reusable on other images');
 await add('moon knights');await saved();assert.deepEqual((await data()).items['art:beta'].art_tags,['Moon Knights']);await page.click('#close-detail');
 await page.locator('#art-filter-groups input[data-group="art_tags"][value="Moon Knights"]').check();assert.deepEqual((await rows()).sort(),['art:alpha','art:beta']);
 await page.reload();await saved();assert.deepEqual((await rows()).sort(),['art:alpha','art:beta']);
 await open('art:beta');await page.getByRole('button',{name:'Remove tag Moon Knights',exact:true}).click();await saved();await page.click('#close-detail');assert.deepEqual(await rows(),['art:alpha']);
 await page.click('#clear-filters');await page.check('#show-individual-images');await open('art:gamma');await add('<img onerror=alert(1)>');await saved();
 assert.equal(await page.locator('.art-tag-editor img').count(),0,'Custom tag text is not HTML');await page.getByRole('button',{name:'Remove tag <img onerror=alert(1)>',exact:true}).click();await saved();
 await page.locator('.art-tag-choices').getByLabel('Magic',{exact:true}).check();await saved();
 const screenshots=path.join(root,'.artifacts/tracker');fs.mkdirSync(screenshots,{recursive:true});
 await page.locator('.art-tag-editor').scrollIntoViewIfNeeded();await page.screenshot({path:path.join(screenshots,'art-tags-desktop.png')});
 await page.setViewportSize({width:390,height:844});await page.locator('.art-tag-editor').scrollIntoViewIfNeeded();
 assert(await page.locator('#detail').evaluate(n=>n.scrollWidth<=n.clientWidth),'Tag editor fits a narrow screen');await page.screenshot({path:path.join(screenshots,'art-tags-mobile.png')});
 await page.click('#close-detail');await stop();await start();await page.reload();await saved();
 assert.deepEqual((await data()).items['art:alpha'].art_tags,['Combat','Moon Knights']);assert.deepEqual((await data()).items['art:gamma'].art_tags,['Magic']);
 assert.deepEqual(errors,[]);for(const image of images)assert.deepEqual(fs.readFileSync(path.join(fixture,image.path)),png);
 console.log('PASS Art tags: presets, custom creation/reuse/removal, search, pack discovery, filter persistence, v4 migration/backup, restart, independent annotations, safe text and mobile layout.');
}finally{if(browser)await browser.close();await stop();fs.rmSync(fixture,{recursive:true,force:true});}})().catch(error=>{console.error(error);process.exitCode=1;});
