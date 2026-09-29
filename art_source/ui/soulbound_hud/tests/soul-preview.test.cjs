const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {chromium}=require('playwright');
const artifacts=path.join(__dirname,'../.artifacts');fs.mkdirSync(artifacts,{recursive:true});
const fragment=fs.readFileSync(path.join(__dirname,'../soulbound-crystal-hud-preview.html'),'utf8');
(async()=>{
  const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH||undefined,args:['--no-sandbox']});
  try{
    const page=await browser.newPage({viewport:{width:1024,height:1100}}),errors=[];
    page.on('pageerror',e=>errors.push(e.message));
    await page.setContent(fragment);
    await page.evaluate(()=>{const api=document.getElementById('soulbound-hud-review').hudReview;api.setManualClock(true);api.applyPreset('start');});
    await page.waitForFunction(()=>document.getElementById('soulbound-hud-review').hudReview.referenceFrame.naturalWidth>0);
    const results=await page.evaluate(()=>{
      const root=document.getElementById('soulbound-hud-review'),api=root.hudReview,s=api.state,c=api.soul,checks=[];
      const check=(ok,name)=>checks.push({name,passed:!!ok}),near=(a,b)=>Math.abs(a-b)<1e-6;
      check(c.phase==='cooldown'&&s.reserves===5,'Reference starts with automatic cooldown');
      api.advance(.8);check(near(s.mana,195)&&near(s.reserveFill[0],.85),'Live preview transfers at 150 Soul per second');
      root.querySelector('[data-action="cast"]').click();check(near(s.mana,170)&&c.phase==='draining'&&c.source===-1,'Cast button stops flow and pays once');
      const visible=c.displayMana;api.advance(.1);check(c.displayMana<visible&&c.displayMana>s.mana&&Math.abs(c.tilt)>.05,'Level drops gradually with slosh');
      api.advance(.7);check(c.phase==='refilling'&&near(s.mana,170),'Cooldown begins after visual drain');
      api.advance(.2);check(near(s.mana,200),'Refill resumes after interrupted cycle');
      root.querySelector('[data-action="spell"]').click();root.querySelector('[data-action="cast"]').click();check(near(s.mana,160),'Selected spell pays its own 40-point cost');
      s.mana=10;c.reset();api.advance(.5);const held=s.reserveFill[0];root.querySelector('[data-action="cast"]').click();check(c.phase==='refilling'&&near(s.reserveFill[0],held),'Unaffordable attempt leaves refill running');
      api.advance(.2);check(near(s.mana,40),'Failed cast is not queued');
      root.querySelector('[data-action="reset"]').click();check(s.mana===150&&c.phase==='cooldown'&&s.charges===3,'Reset restores selected preset and animation state');
      const manaField=root.querySelector('[data-field="mana"]');manaField.value=20;manaField.dispatchEvent(new Event('input'));check(s.mana===20&&c.displayMana===20&&near(c.remaining,.5),'Manual edits clear old animation and restart eligibility');
      api.advance(.6);const frozen=s.mana;
      Object.defineProperty(document,'hidden',{configurable:true,value:true});document.dispatchEvent(new Event('visibilitychange'));api.advance(8);check(s.mana===frozen&&c.paused,'Hidden preview freezes resource transfer');
      Object.defineProperty(document,'hidden',{configurable:true,value:false});document.dispatchEvent(new Event('visibilitychange'));api.advance(.1);check(near(s.mana,frozen+15),'Visible preview resumes without hidden catch-up');
      const healthField=root.querySelector('[data-field="health"]');healthField.value=0;healthField.dispatchEvent(new Event('input'));const deadMana=s.mana;api.advance(3);check(s.mana===deadMana&&c.phase==='idle','Death clears flow and stops transfer');
      root.querySelector('[data-action="reset"]').click();check(s.health===12&&s.mana===150,'Reset restores alive state');
      root.querySelector('[data-preset="gameplay"]').click();api.action('cast');api.advance(2);check(s.reserves===0&&s.mana===75,'Gameplay start never gains Soul without reserves');
      api.applyPreset('start');api.advance(.85);check(root.querySelector('[data-readout]').textContent.includes('202.5'),'Readout reflects actual continuous transfer');
      check(api.staminaFills(125,4).join(',')==='1,1,1,1,1,0,0,0','Outer stamina still drains first');
      api.applyPreset('gold');check(s.health===65&&s.hearts===20,'Gold overlay preset remains intact');
      api.applyPreset('start');s.health=1;s.flasks=1;api.action('flask');check(s.flasks===0&&near(s.health,7.6),'Flask exhaustion still works');
      api.applyPreset('start');return checks;
    });
    console.log(JSON.stringify(results,null,2));assert.ok(results.every(x=>x.passed));
    assert.ok(await page.evaluate(()=>{
      const a=document.getElementById('soulbound-hud-review').hudReview;
      for(let source=0;source<5;source++){
        a.applyPreset('start');a.state.reserveFill=[0,0,0,0,0];a.state.reserveFill[source]=1;a.soul.reset();a.advance(.7);
        const v=a.getSoulRefillVisuals(),network=a.soulCrackNetworks[source];
        if(!v.active||!v.motion||v.source!==source||network.total<=0||!network.seams.some(s=>s.branch))return false;
        if(!network.points.every(p=>p.every(Number.isFinite)&&p[0]>0&&p[0]<280&&p[1]>160&&p[1]<290))return false;
        if(Math.abs(network.points.at(-1)[0]-156.2)>.001||network.points.at(-1)[1]!==232)return false;
        a.action('cast');if(a.getSoulRefillVisuals().active)return false;
      }
      a.applyPreset('start');a.advance(1.7);
      if(a.getSoulRefillVisuals().active||!a.soul.settling().active||Math.abs(a.soul.settling().eyes-1)>1e-6)return false;
      a.action('cast');if(a.soul.settling().active)return false;
      a.applyPreset('start');return true;
    }),'Crack routes, transfer interruption, or completion cue failed');
    await page.evaluate(()=>{document.getElementById('soulbound-hud-review').style.display='none';});
    await page.waitForFunction(()=>document.getElementById('soulbound-hud-review').hudReview.soul.paused);
    assert.ok(await page.evaluate(()=>{const a=document.getElementById('soulbound-hud-review').hudReview,before=a.state.mana;a.advance(10);return before===a.state.mana;}),'Collapsed preview did not pause');
    await page.evaluate(()=>{document.getElementById('soulbound-hud-review').style.display='';});
    await page.waitForFunction(()=>!document.getElementById('soulbound-hud-review').hudReview.soul.paused);
    await page.click('[data-inspect]');
    await page.evaluate(()=>document.getElementById('soulbound-hud-review').hudReview.advance(.75));
    await page.locator('#soulbound-hud-review').screenshot({path:path.join(artifacts,'soul-refill-closeup.png')});
    await page.evaluate(()=>{const a=document.getElementById('soulbound-hud-review').hudReview;a.action('cast');a.advance(.11);});
    await page.locator('#soulbound-hud-review').screenshot({path:path.join(artifacts,'soul-drain-closeup.png')});
    // Eye pixels must disappear with the displayed liquid; timing stays deterministic.
    const eyePixels=()=>page.evaluate(()=>{const canvas=document.querySelector('canvas'),sx=canvas.width/1280,sy=canvas.height/720;const pixels=canvas.getContext('2d').getImageData(Math.round(330*sx),Math.round(365*sy),Math.round(215*sx),Math.round(53*sy)).data;let n=0;for(let i=0;i<pixels.length;i+=4)if(pixels[i]>195&&pixels[i+1]>190&&pixels[i+2]>210)n++;return n/(sx*sy);});
    const eyeBrightness=()=>page.evaluate(()=>{const canvas=document.querySelector('canvas'),sx=canvas.width/1280,sy=canvas.height/720;const pixels=canvas.getContext('2d').getImageData(Math.round(330*sx),Math.round(365*sy),Math.round(215*sx),Math.round(53*sy)).data;let n=0;for(let i=0;i<pixels.length;i+=4)n+=pixels[i]+pixels[i+1]+pixels[i+2];return n/(sx*sy);});
    await page.evaluate(()=>{const a=document.getElementById('soulbound-hud-review').hudReview;a.applyPreset('start');a.advance(1.7);});
    const brightEyes=await eyeBrightness();
    await page.locator('#soulbound-hud-review').screenshot({path:path.join(artifacts,'soul-settling-closeup.png')});
    await page.evaluate(()=>document.getElementById('soulbound-hud-review').hudReview.advance(.6));
    const settledEyes=await eyeBrightness();assert.ok(brightEyes>settledEyes*1.015,`Eyes did not brighten: ${brightEyes} versus ${settledEyes}`);
    await page.locator('#soulbound-hud-review').screenshot({path:path.join(artifacts,'soul-settled-closeup.png')});
    await page.evaluate(()=>{const a=document.getElementById('soulbound-hud-review').hudReview;a.applyPreset('start');});
    const fullEyes=await eyePixels();
    await page.evaluate(()=>{const a=document.getElementById('soulbound-hud-review').hudReview;a.state.mana=0;a.state.reserves=0;a.state.reserveFill=[0,0,0,0,0];a.soul.reset();a.update();});
    const emptyEyes=await eyePixels();assert.ok(fullEyes>500&&emptyEyes===0,`Eye clipping: ${fullEyes} full, ${emptyEyes} empty`);
    await page.locator('#soulbound-hud-review').screenshot({path:path.join(artifacts,'soul-empty-closeup.png')});
    await page.click('[data-inspect]');
    await page.evaluate(()=>{const a=document.getElementById('soulbound-hud-review').hudReview;a.applyPreset('start');a.advance(.8);});
    await page.locator('#soulbound-hud-review').screenshot({path:path.join(artifacts,'soul-refill-gameplay.png')});
    for(const width of [1024,736,360,320]){
      await page.setViewportSize({width,height:1100});
      assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),`Overflow at ${width}`);
    }
    await page.locator('#soulbound-hud-review').screenshot({path:path.join(artifacts,'soul-refill-mobile.png')});
    // Real RAF playback must progress independently of deterministic testing hooks.
    await page.locator('.stage canvas').scrollIntoViewIfNeeded();
    await page.waitForFunction(()=>!document.getElementById('soulbound-hud-review').hudReview.soul.paused);
    await page.evaluate(()=>{const a=document.getElementById('soulbound-hud-review').hudReview;a.applyPreset('start');a.setManualClock(false);});
    // Browser scheduling may be delayed during screenshots; exact timing is tested by the controller suite.
    await page.waitForFunction(()=>{const a=document.getElementById('soulbound-hud-review').hudReview;return Math.abs(a.state.mana-300)<1e-7&&a.soul.phase==='idle';},null,{timeout:5000});
    const reduced=await browser.newPage({viewport:{width:1024,height:1000},reducedMotion:'reduce'});reduced.on('pageerror',e=>errors.push(e.message));await reduced.setContent(fragment);
    assert.ok(await reduced.evaluate(()=>{const a=document.getElementById('soulbound-hud-review').hudReview;a.setManualClock(true);a.applyPreset('start');a.action('cast');a.advance(.15);return a.soul.reducedMotion&&a.soul.tilt===0&&a.soul.displayMana===137.5&&a.soul.surfaceOffset(.5,.5)===0;}),'Reduced motion changed timing or retained movement');
    assert.ok(await reduced.evaluate(()=>{const a=document.getElementById('soulbound-hud-review').hudReview;a.applyPreset('start');a.advance(.8);const v=a.getSoulRefillVisuals();a.advance(.9);return v.active&&!v.motion&&v.time===0&&a.state.mana===300&&!a.soul.settling().active;}),'Reduced motion retained moving flow or completion pulse');
    const retina=await browser.newPage({viewport:{width:1024,height:1100},deviceScaleFactor:2});retina.on('pageerror',e=>errors.push(e.message));await retina.setContent(fragment);
    await retina.evaluate(()=>{const a=document.getElementById('soulbound-hud-review').hudReview;a.setManualClock(true);a.applyPreset('start');a.advance(.8);});
    for(const width of [1024,736,360]){
      await retina.setViewportSize({width,height:1100});
      await retina.waitForFunction(()=>{const canvas=document.querySelector('canvas'),rect=canvas.getBoundingClientRect();return canvas.width===Math.round(rect.width*2)&&canvas.height===Math.round(rect.height*2);});
      assert.ok(await retina.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'High-density layout overflow');
      if(width===1024){
        await retina.locator('#soulbound-hud-review').screenshot({path:path.join(artifacts,'soul-stone-hires-gameplay.png')});
        await retina.click('[data-inspect]');
        await retina.locator('#soulbound-hud-review').screenshot({path:path.join(artifacts,'soul-stone-hires-closeup.png')});
      }
    }
    assert.deepEqual(errors,[]);console.log('Browser interactions, real-time playback, reduced motion, all four widths, and high-density resizing passed.');
  }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
