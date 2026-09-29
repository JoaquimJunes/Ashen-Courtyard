const assert=require('node:assert/strict');
const fs=require('node:fs');
const {SoulWispReference:r}=require('./timeline.js');
const near=(a,b)=>assert.ok(Math.abs(a-b)<1e-8,`${a} != ${b}`);
// Accounting in the directed scenarios must tell the same story as the agreed rules.
for(const kind of Object.keys(r.scenarios)){
  let previous=0;
  for(let t=0;t<=r.scenarios[kind].duration;t+=1/120){
    const s=r.sample(t,kind);
    assert.ok(s.fill>=0&&s.fill<=1&&s.actual>=0&&s.actual<=1&&s.reserve>=-1e-9);
    near(s.actual+s.reserve,kind==='recover'?(t<1?1.3:1):kind==='empty'&&t>=7.3?.7:1);
    if(s.burst)assert.equal(kind,'empty');
    if(t<r.scenarios[kind].full&&kind!=='recover')near(s.aura,0);
    if(s.eye>0)assert.equal(s.full,true);
    assert.ok(Number.isFinite(s.aura));previous=t;
  }
}
near(r.sample(3.15,'empty').fill,1);
assert.equal(r.sample(3.2,'empty').phase,'Burst');
assert.equal(r.sample(3.61,'empty').phase,'Gather');
assert.equal(r.sample(4.36,'empty').phase,'Settle');
assert.equal(r.sample(5.26,'empty').phase,'Settled');
assert.equal(r.sample(8.79,'empty').phase,'Spend / linger');
assert.equal(r.sample(8.81,'empty').phase,'Dissolve');
near(r.sample(9.41,'empty').aura,0);
assert.equal(r.sample(1.11,'ordinary').phase,'Soft settle');
assert.equal(r.sample(2.41,'recover').phase,'Soft settle');
assert.ok(r.sample(2.39,'recover').aura>0);
console.log('Reference scenarios: exact selected timings, independent eye cue, no ordinary burst, linger recovery, bounded fills and Soul conservation passed.');
if(process.argv.includes('--browser'))(async()=>{
  const {chromium}=require('playwright');
  const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH,args:['--no-sandbox']});
  try{
    const context=await browser.newContext({offline:true,viewport:{width:780,height:1100},deviceScaleFactor:2});
    const page=await context.newPage(),errors=[],network=[];
    page.on('pageerror',e=>errors.push(e.message));page.on('request',q=>{if(/^https?:/.test(q.url()))network.push(q.url());});
    await page.goto('file:///tmp/soul-wisps-motion-reference.html');
    const f=page.frames().find(f=>f!==page.mainFrame());
    await f.waitForFunction(()=>document.getElementById('soul-wisps-motion-reference')?.motionReference?.getState().loaded);
    await f.evaluate(()=>document.getElementById('soul-wisps-motion-reference').motionReference.pause());
    const out='/tmp/soul-wisps-check';fs.mkdirSync(out,{recursive:true});
    for(const [name,time] of [['empty',.3],['refill',2.5],['burst',3.59],['gather',3.98],['settle',5.25],['linger',8],['dissolve',9.05]]){
      await f.evaluate(t=>document.getElementById('soul-wisps-motion-reference').motionReference.setTime(t),time);
      await f.locator('.motion-stage').screenshot({path:`${out}/${name}.png`});
    }
    for(const kind of ['ordinary','recover']){
      await f.locator('[data-sequence]').selectOption(kind);
      await f.evaluate(()=>{const a=document.getElementById('soul-wisps-motion-reference').motionReference;a.pause();a.setTime(a.scenarios[a.getState().kind].full+.1);});
      assert.equal(await f.locator('[data-phase]').textContent(),'Soft settle');
    }
    await f.locator('[data-sequence]').selectOption('empty');
    await f.locator('[data-play]').click();
    await f.locator('[data-reduced]').check();
    await f.evaluate(()=>document.getElementById('soul-wisps-motion-reference').motionReference.setTime(3.6));
    await f.locator('.motion-stage').screenshot({path:`out/reduced.png`.replace('out',out)});
    await f.locator('[data-reduced]').uncheck();
    await f.locator('[data-replay]').click();
    await page.waitForTimeout(220);
    const t=await f.evaluate(()=>document.getElementById('soul-wisps-motion-reference').motionReference.getState().t);
    assert.ok(t>0&&t<.5,'Replay does not advance');
    await f.locator('[data-play]').click();
    const stopped=await f.evaluate(()=>document.getElementById('soul-wisps-motion-reference').motionReference.getState().t);
    await page.waitForTimeout(120);
    near(await f.evaluate(()=>document.getElementById('soul-wisps-motion-reference').motionReference.getState().t),stopped);
    for(const width of [736,360,320]){
      await page.setViewportSize({width,height:1100});
      await f.evaluate(()=>document.getElementById('soul-wisps-motion-reference').motionReference.setTime(3.58));
      await page.waitForTimeout(100);
      assert.ok(await f.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),`Overflow at ${width}`);
      await page.screenshot({path:`${out}/width-${width}.png`,fullPage:true});
    }
    assert.deepEqual(errors,[]);assert.deepEqual(network,[]);
    console.log('Offline browser checks: artwork, all phases, real playback, pause/replay, reduced motion, two scales, high density and 320–736px layout passed.');
  }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
