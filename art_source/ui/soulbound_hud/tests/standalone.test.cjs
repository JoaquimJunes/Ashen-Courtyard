const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {pathToFileURL}=require('node:url');
const {chromium}=require('playwright');
const root=path.resolve(__dirname,'..');
(async()=>{
  const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH||undefined,args:['--no-sandbox']});
  try{
    const context=await browser.newContext({offline:true,viewport:{width:1100,height:1100}});
    const page=await context.newPage(),errors=[],remoteRequests=[];
    page.on('pageerror',e=>errors.push(e.message));
    page.on('request',request=>{if(/^https?:/.test(request.url()))remoteRequests.push(request.url());});
    await page.goto(pathToFileURL(path.join(root,'index.html')).href);
    const frame=page.frames().find(f=>f!==page.mainFrame());assert.ok(frame,'Standalone iframe missing');
    await frame.waitForFunction(()=>document.getElementById('soulbound-hud-review')?.hudReview?.referenceFrame.naturalWidth===1633);
    const fragment=fs.readFileSync(path.join(root,'soulbound-crystal-hud-preview.html'),'utf8');
    assert.ok((await page.locator('iframe').getAttribute('srcdoc')).includes(fragment),'Export differs from editable source; rebuild it');
    await frame.locator('.stage canvas').scrollIntoViewIfNeeded();
    await frame.waitForFunction(()=>!document.getElementById('soulbound-hud-review').hudReview.soul.paused);
    await frame.evaluate(()=>{const a=document.getElementById('soulbound-hud-review').hudReview;a.setManualClock(true);a.applyPreset('start');a.advance(1.5);});
    await frame.click('[data-action="cast"]');
    const castState=await frame.evaluate(()=>{const a=document.getElementById('soulbound-hud-review').hudReview;return {mana:a.state.mana,phase:a.soul.phase,paused:a.soul.paused};});
    assert.ok(Math.abs(castState.mana-275)<1e-7&&castState.phase==='draining',`Offline cast failed: ${JSON.stringify(castState)}`);
    await frame.click('[data-inspect]');
    assert.equal(await frame.locator('[data-inspect]').getAttribute('aria-pressed'),'true');
    for(const width of [1100,736,360]){
      await page.setViewportSize({width,height:1100});
      await frame.waitForFunction(()=>{const canvas=document.querySelector('canvas');return canvas.width===Math.round(canvas.getBoundingClientRect().width);});
      assert.ok(await frame.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),`Standalone overflow at ${width}`);
    }
    await page.setViewportSize({width:1100,height:1100});
    await frame.evaluate(()=>{const a=document.getElementById('soulbound-hud-review').hudReview;a.applyPreset('start');a.advance(.8);});
    await frame.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
    assert.ok(await frame.evaluate(()=>{const root=document.getElementById('soulbound-hud-review');return root.getBoundingClientRect().width===innerWidth&&root.querySelector('.review-tools').getBoundingClientRect().width===innerWidth;}),'Frame did not expand after mobile resize');
    fs.mkdirSync(path.join(root,'.artifacts'),{recursive:true});
    await page.screenshot({path:path.join(root,'.artifacts/standalone-offline.png'),fullPage:true});
    // Also inspect the actual fresh-open experience independently of resize tests.
    await page.reload();
    const fresh=page.frames().find(f=>f!==page.mainFrame());
    await fresh.waitForFunction(()=>document.getElementById('soulbound-hud-review')?.hudReview?.referenceFrame.naturalWidth===1633);
    await fresh.waitForFunction(()=>!document.getElementById('soulbound-hud-review').hudReview.soul.paused);
    await fresh.evaluate(()=>{const a=document.getElementById('soulbound-hud-review').hudReview;a.setManualClock(true);a.applyPreset('start');a.advance(.8);});
    await fresh.click('[data-inspect]');
    await page.screenshot({path:path.join(root,'.artifacts/standalone-offline-fresh.png'),fullPage:true});
    assert.deepEqual(remoteRequests,[],'Offline export attempted network access');assert.deepEqual(errors,[]);
    console.log('Standalone offline load, source parity, embedded art, controls, and responsive layout passed.');
  }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
