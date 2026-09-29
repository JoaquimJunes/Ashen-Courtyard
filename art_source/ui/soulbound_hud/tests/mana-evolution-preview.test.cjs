const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {chromium}=require('playwright');
const root=path.resolve(__dirname,'..'),html=fs.readFileSync(path.join(root,'soulbound-crystal-hud-preview.html'),'utf8');
for(const name of ['mana-evolution','mana-evolution-renderer'])assert.ok(html.includes(fs.readFileSync(path.join(root,'src',name+'.js'),'utf8').trim()),`Rebuild embedded ${name}`);
(async()=>{
  const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH||undefined,args:['--no-sandbox']});
  try{
    const page=await browser.newPage({viewport:{width:1280,height:1100},deviceScaleFactor:1}),errors=[];
    page.on('pageerror',e=>errors.push(e.message));await page.setContent(html);
    await page.waitForFunction(()=>document.getElementById('soulbound-hud-review').hudReview.referenceFrame.naturalWidth>0);
    await page.evaluate(()=>document.getElementById('soulbound-hud-review').hudReview.setManualClock(true));
    const checks=await page.evaluate(()=>{
      const root=document.getElementById('soulbound-hud-review'),a=root.hudReview,s=a.state,c=a.soul,result=[];
      const near=(x,y)=>Math.abs(x-y)<1e-7,check=(name,value)=>result.push({name,passed:!!value});
      const total=()=>s.mana+s.reserveFill.reduce((sum,x)=>sum+x*s.manaMax,0);
      a.applyPreset('strongest');a.advance(2);let v=a.getEvolutionVisuals();
      check('Strongest full preset has added runes, complete circle and independent aura',v.level===5&&v.profile.rimRunes===4&&v.profile.crystalRunes===3&&v.profile.circleQuarters===4&&v.emitting&&c.settling().eyes===0&&!a.getSoulRefillVisuals().active);
      a.action('cast');v=a.getEvolutionVisuals();check('Cast cancels aura emission before the visible level falls',s.mana===275&&c.displayMana===300&&!v.emitting&&v.opacity>0&&v.runeEmission===0);
      a.advance(.2);check('Residual aura fades after 0.2 seconds',near(a.getEvolutionVisuals().opacity,0));
      a.advance(.1);a.advance(.5);check('Original drain and refill cooldown survive evolution',c.phase==='refilling'&&s.mana===275);
      a.advance(25/150+.2);check('Refill reactivates aura with the original separate eye cue',a.getEvolutionVisuals().emitting&&near(c.settling().eyes,1));
      a.advance(.5);check('Eyes settle while full aura remains',a.getEvolutionVisuals().emitting&&c.settling().eyes===0);
      const before=total(),age=a.getEvolutionVisuals().effectAge;c.tryCast(400);a.update();
      check('Failed cast preserves full aura and Soul',near(total(),before)&&a.getEvolutionVisuals().effectAge===age);
      a.applyPreset('gameplay');a.action('cast');a.advance(.3);
      const selector=root.querySelector('[data-evolution]');selector.value='1';selector.dispatchEvent(new Event('change'));
      check('Progression selector grants capacity but no Soul',s.manaMax===140&&s.mana===75&&s.reserves===1&&s.reserveFill[0]===0&&root.querySelector('[data-capacity]').textContent==='140');
      s.reserveFill[0]=.5;c.reset();a.update();const stored=total();
      selector.value='2';selector.dispatchEvent(new Event('change'));
      check('Existing partial reserves retain absolute Soul across upgrades',near(total(),stored)&&near(s.reserveFill[0]*180,70)&&s.reserveFill[1]===0&&c.phase==='cooldown');
      for(let level=0;level<=5;level++){
        a.setEvolutionLevel(level);check('Linked capacity at level '+level,s.manaMax===100+40*level&&a.getEvolutionVisuals().level===level);
      }
      a.applyPreset('strongest');s.mana=0;s.reserveFill=[0,0,0,0,0];c.reset();a.update();
      check('Exhausted Soul retains strongest ornaments',a.getEvolutionVisuals().level===5&&a.getEvolutionVisuals().profile.circleQuarters===4&&!a.getEvolutionVisuals().emitting);
      a.applyPreset('strongest');s.health=0;a.update();check('Death clears aura immediately',a.getEvolutionVisuals().opacity===0&&!a.getEvolutionVisuals().emitting);
      a.action('reset');check('Reset restores selected full preset',s.health===12&&s.mana===300&&a.getEvolutionVisuals().emitting);
      a.applyPreset('start');s.reserveFill=[0,0,0,0,0];s.mana=275;c.reset();a.update();a.action('gain');
      check('Kill reward can activate full aura without forging eye glow',s.mana===300&&a.getEvolutionVisuals().emitting&&c.refillCompletedAt===null);
      a.applyPreset('strongest');a.advance(2);
      const snapshot=JSON.stringify([s,c.phase,c.time,c.displayMana,a.getEvolutionVisuals()]);
      root.querySelector('[data-compare]').click();
      check('Comparison renders six isolated stages with no live-state mutations',root.querySelectorAll('[data-evolution-gallery] canvas').length===6&&JSON.stringify([s,c.phase,c.time,c.displayMana,a.getEvolutionVisuals()])===snapshot);
      const first=document.createElement('canvas'),last=document.createElement('canvas');first.width=last.width=570;first.height=last.height=340;
      a.renderEvolutionSnapshot(first,0);a.renderEvolutionSnapshot(last,5);
      const p=first.getContext('2d').getImageData(300,65,230,215).data,q=last.getContext('2d').getImageData(300,65,230,215).data;
      check('Health frame pixels are unchanged by maximum magic',p.every((value,i)=>value===q[i]));
      for(const background of ['#101118','#b6b3aa'])for(let level=0;level<=5;level++)a.renderEvolutionSnapshot(last,level,{background,fill:.5});
      check('Full and partial forms render on both backgrounds',last.getContext('2d').getImageData(0,0,1,1).data[3]===255);
      root.querySelector('[data-compare]').click();a.applyPreset('strongest');return result;
    });
    console.log(JSON.stringify(checks,null,2));assert.ok(checks.every(c=>c.passed));
    fs.mkdirSync(path.join(root,'.artifacts'),{recursive:true});
    await page.evaluate(()=>{const a=document.getElementById('soulbound-hud-review').hudReview;a.applyPreset('strongest');a.advance(2);});
    await page.locator('canvas').first().screenshot({path:path.join(root,'.artifacts/evolution-strongest-gameplay.png')});
    await page.click('[data-inspect]');
    await page.locator('canvas').first().screenshot({path:path.join(root,'.artifacts/evolution-strongest-closeup.png')});
    await page.click('summary');
    await page.selectOption('[data-background]','light');
    await page.locator('canvas').first().screenshot({path:path.join(root,'.artifacts/evolution-strongest-light.png')});
    await page.selectOption('[data-background]','courtyard');
    await page.click('summary');
    await page.evaluate(()=>document.getElementById('soulbound-hud-review').hudReview.applyPreset('start'));
    await page.locator('canvas').first().screenshot({path:path.join(root,'.artifacts/evolution-partial-closeup.png')});
    await page.click('[data-compare]');
    for(const width of [1280,1024,736,360,320]){
      await page.setViewportSize({width,height:1100});
      assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),`Evolution layout overflow at ${width}`);
    }
    await page.setViewportSize({width:1280,height:1100});
    await page.locator('[data-evolution-gallery]').screenshot({path:path.join(root,'.artifacts/evolution-comparison.png')});
    const strip=await page.evaluate(()=>{
      const a=document.getElementById('soulbound-hud-review').hudReview,out=document.createElement('canvas');out.width=3420;out.height=400;
      const ctx=out.getContext('2d');ctx.fillStyle='#101118';ctx.fillRect(0,0,out.width,out.height);
      for(let level=0;level<=5;level++){
        const tile=document.createElement('canvas');tile.width=570;tile.height=340;a.renderEvolutionSnapshot(tile,level);
        ctx.drawImage(tile,570*level,0);const p=a.ManaEvolution.profileFor(level);
        ctx.fillStyle='#dbc5ed';ctx.font='22px Georgia';ctx.textAlign='center';ctx.fillText(p.name,570*level+285,364);
        ctx.fillStyle='#a69cab';ctx.font='16px sans-serif';ctx.fillText(`${p.manaMax} Soul · ${level} reserves`,570*level+285,389);
      }
      return out.toDataURL('image/png').split(',')[1];
    });
    fs.writeFileSync(path.join(root,'.artifacts/evolution-six-stage-strip.png'),Buffer.from(strip,'base64'));
    const reduced=await browser.newPage({viewport:{width:1024,height:1100},reducedMotion:'reduce'});reduced.on('pageerror',e=>errors.push(e.message));await reduced.setContent(html);
    assert.ok(await reduced.evaluate(()=>{const a=document.getElementById('soulbound-hud-review').hudReview;a.setManualClock(true);a.applyPreset('strongest');const x=a.getEvolutionVisuals();a.advance(2);const y=a.getEvolutionVisuals();return x.opacity===y.opacity&&y.emitting&&!y.motion&&y.effectAge===0&&a.soul.settling().eyes===0;}),'Reduced-motion aura must stay static');
    assert.deepEqual(errors,[]);console.log(`${checks.length} evolution browser checks, both backgrounds, comparison strip, responsive layouts and reduced motion passed.`);
  }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
