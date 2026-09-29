const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const html=fs.readFileSync(path.join(__dirname,'../soulbound-crystal-hud-preview.html'),'utf8');
const source=html.slice(html.indexOf('    class SoulController'),html.indexOf('    // SOUL_CONTROLLER_END'));
const context={};vm.createContext(context);vm.runInContext(source+';this.SoulController=SoulController;',context);
const SoulController=context.SoulController;
let passed=0;
function close(a,b){assert.ok(Math.abs(a-b)<1e-7,`${a} != ${b}`);}
function test(name,fn){fn();passed++;console.log('PASS',name);}
function make(overrides={},reduced=false){const s={health:12,mana:50,manaMax:100,reserves:5,reserveFill:[1,1,1,0,0],...overrides};return [s,new SoulController(s,reduced)];}
const total=s=>s.mana+s.reserveFill.reduce((a,b)=>a+b*s.manaMax,0);

test('initial half vessel: 0.5 second wait, 1 second transfer',()=>{
  const [s,c]=make();c.advance(.499);close(s.mana,50);c.advance(.001);assert.equal(c.phase,'refilling');close(s.mana,50);
  c.advance(.5);close(s.mana,75);close(s.reserveFill[0],.75);c.advance(.5);close(s.mana,100);close(s.reserveFill[0],.5);close(total(s),350);assert.equal(c.phase,'idle');
});
test('cast pays once; 0.3 drain then 0.5 cooldown then 0.5 refill',()=>{
  const [s,c]=make({mana:100});assert.ok(c.tryCast(25));close(s.mana,75);close(c.displayMana,100);
  c.advance(.15);close(c.displayMana,87.5);close(s.mana,75);c.advance(.15);close(c.displayMana,75);assert.equal(c.phase,'cooldown');
  c.advance(.5);assert.equal(c.phase,'refilling');close(s.reserveFill[0],1);c.advance(.5);close(s.mana,100);close(s.reserveFill[0],.75);close(total(s),375);
});
test('successful cast interrupts transfer immediately and retains partial reserves',()=>{
  const [s,c]=make();c.advance(.9);close(s.mana,70);close(s.reserveFill[0],.8);assert.ok(c.tryCast(25));assert.equal(c.source,-1);close(s.mana,45);
  c.advance(.8);close(s.mana,45);close(s.reserveFill[0],.8);c.advance(.1);close(s.mana,50);close(s.reserveFill[0],.75);
});
test('insufficient cast does not consume reserves, reset timers, or queue',()=>{
  const [s,c]=make({mana:0});c.advance(.2);const remaining=c.remaining;assert.equal(c.tryCast(25),false);close(c.remaining,remaining);
  c.advance(.4);close(s.mana,5);assert.equal(c.tryCast(25),false);assert.equal(c.phase,'refilling');c.advance(.4);close(s.mana,25);close(total(s),300);assert.equal(c.phase,'refilling');
});
test('partial vessels combine left to right without another delay',()=>{
  const [s,c]=make({mana:0,reserves:3,reserveFill:[.1,.15,.05,0,0]});c.advance(.7);close(s.reserveFill[0],0);assert.equal(c.source,1);
  c.advance(.4);close(s.mana,30);close(total(s),30);assert.equal(c.phase,'idle');assert.ok(s.reserveFill.every(v=>v===0));
});
test('rapid casts retarget the visible level without snapping',()=>{
  const [s,c]=make({mana:100});c.tryCast(25);c.advance(.12);const visible=c.displayMana;c.tryCast(25);close(c.displayMana,visible);close(s.mana,50);
  c.advance(.3);close(c.displayMana,50);c.advance(.499);close(s.mana,50);c.advance(.001);assert.equal(c.phase,'refilling');close(total(s),350);
});
test('kill reward during every phase preserves totals and does not restart cooldown',()=>{
  for(const age of [0,.15,.4,.9]){
    const [s,c]=make({mana:100});c.tryCast(40);c.advance(age);const before=total(s),phase=c.phase,remaining=c.remaining;
    const gained=c.gain(10);close(total(s),before+gained);if(phase==='draining'||phase==='cooldown')close(c.remaining,remaining);
    c.advance(3);close(c.displayMana,s.mana);close(total(s),before+10);
  }
});
test('kill reward fills main and reserves left to right, capped without creation',()=>{
  const [s,c]=make({mana:90,reserves:3,reserveFill:[.9,.2,0,0,0]});close(c.gain(35),35);close(s.mana,100);close(s.reserveFill[0],1);close(s.reserveFill[1],.35);assert.equal(c.phase,'idle');
  close(c.gain(1000),165);close(total(s),400);close(c.gain(5),0);
});
test('no unlocked reserves means no automatic resource creation',()=>{
  const [s,c]=make({mana:100,reserves:0,reserveFill:[0,0,0,0,0]});c.tryCast(25);c.advance(60);close(s.mana,75);close(c.displayMana,75);assert.equal(c.phase,'idle');
});
test('death, reset, and hidden time cannot leak transfers',()=>{
  const [s,c]=make();c.advance(.7);const before=total(s);c.setPaused(true);const frozen=s.mana;c.advance(20);close(s.mana,frozen);c.setPaused(false);c.advance(.1);close(s.mana,frozen+5);
  s.health=0;c.advance(2);close(total(s),before);assert.equal(c.phase,'idle');assert.equal(c.source,-1);const dead=s.mana;c.advance(10);close(s.mana,dead);assert.equal(c.tryCast(25),false);
  s.health=12;s.mana=50;s.reserveFill=[1,1,1,0,0];c.reset();assert.equal(c.phase,'cooldown');close(c.remaining,.5);close(c.displayMana,50);close(c.tilt,0);
});
test('timing, quantities, and oscillator agree at 30, 60, 120 FPS and one large step',()=>{
  const runs=[];
  for(const steps of [1,30,60,120]){const [s,c]=make({mana:100});c.tryCast(40);for(let i=0;i<steps;i++)c.advance(1.2/steps);runs.push([s.mana,s.reserveFill[0],c.displayMana,c.tilt,c.velocity]);}
  for(const result of runs)result.forEach((v,i)=>close(v,runs[0][i]));close(runs[0][0],80);
});
test('reduced motion changes no resource timing and produces no moving surface',()=>{
  const [s,c]=make({mana:100},true);c.tryCast(25);c.advance(.15);close(c.displayMana,87.5);close(c.surfaceOffset(.5,.5),0);close(c.tilt,0);c.advance(1.15);close(s.mana,100);
});
test('slosh is transient and zero at empty/full boundaries',()=>{
  const [,c]=make({mana:100});c.tryCast(25);c.advance(.1);assert.ok(Math.abs(c.tilt)>.05);close(c.surfaceOffset(.5,0),0);close(c.surfaceOffset(.5,1),0);c.advance(4);assert.ok(Math.abs(c.tilt)<1e-6);
});
test('long randomized casting and rewards conserve every accepted point',()=>{
  const [s,c]=make({mana:100});let expected=total(s),seed=17;
  for(let i=0;i<1000;i++){
    seed=(seed*1664525+1013904223)>>>0;const choice=seed%5;
    if(choice<2){const cost=choice?40:25;if(c.tryCast(cost))expected-=cost;}
    else if(choice===2)expected+=c.gain(35);
    c.advance((seed%41)/100);close(total(s),expected);
    assert.ok(s.mana>=0&&s.mana<=100+1e-9);assert.ok(s.reserveFill.every(v=>v>=0&&v<=1+1e-9));assert.ok(c.displayMana>=0&&c.displayMana<=100+1e-9);
  }
});
test('completed refill gives one brief eye pulse and one fading ripple',()=>{
  const [s,c]=make();assert.equal(c.settling().active,false);c.advance(1.5);
  assert.equal(c.phase,'idle');close(s.mana,100);assert.equal(c.settling().active,true);close(c.settling().eyes,0);
  const completedAt=c.refillCompletedAt;c.advance(.2);close(c.settling().eyes,1);const ripple=c.settling().ripple;
  c.advance(.2);close(c.settling().eyes,0);assert.ok(c.settling().ripple<ripple);c.advance(.201);
  assert.equal(c.settling().active,false);c.advance(5);close(c.refillCompletedAt,completedAt);close(total(s),350);
});
test('full preset, exhausted reserves, and direct rewards do not fake a refill completion',()=>{
  for(const overrides of [{mana:100},{mana:0,reserveFill:[.1,0,0,0,0]}]){
    const [,c]=make(overrides);c.advance(5);assert.equal(c.refillCompletedAt,null);assert.equal(c.settling().active,false);
  }
  const [,c]=make();c.advance(.6);c.gain(100);assert.equal(c.refillCompletedAt,null);
});
test('failed cast preserves settling, accepted cast cancels it immediately',()=>{
  const [s,c]=make();c.advance(1.7);assert.equal(c.tryCast(101),false);close(c.settling().eyes,1);
  assert.equal(c.tryCast(25),true);close(s.mana,75);assert.equal(c.refillCompletedAt,null);assert.equal(c.settling().active,false);
  c.advance(1.5);close(c.settling().eyes,1);close(s.mana,100);
});
test('settling pauses with the preview and clears on reset or death',()=>{
  const [s,c]=make();c.advance(1.7);const before=c.settling();c.setPaused(true);c.advance(20);assert.deepEqual(c.settling(),before);
  c.setPaused(false);c.advance(.1);assert.ok(c.settling().ripple<before.ripple);c.reset();assert.equal(c.refillCompletedAt,null);
  c.tryCast(25);c.advance(1.5);assert.equal(c.settling().active,true);s.health=0;c.reconcile();assert.equal(c.settling().active,false);assert.equal(c.refillCompletedAt,null);
});
test('completion timing is identical at 30, 60, 120 FPS and across a large step',()=>{
  const results=[];
  for(const steps of [1,30,60,120]){const [,c]=make();for(let i=0;i<steps;i++)c.advance(1.7/steps);results.push([c.refillCompletedAt,c.settling().eyes,c.settling().ripple]);}
  results.forEach(r=>r.forEach((v,i)=>close(v,results[0][i])));close(results[0][0],1.5);close(results[0][1],1);
});
test('reduced motion completes transfer without eye pulses or settling ripples',()=>{
  const [s,c]=make({},true);c.advance(1.7);close(s.mana,100);close(s.reserveFill[0],.5);
  assert.equal(c.settling().active,false);close(c.settling().eyes,0);close(c.settling().ripple,0);
});
console.log(`${passed} Soul controller scenarios passed.`);
