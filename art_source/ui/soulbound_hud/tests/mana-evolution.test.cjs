const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const E=require('../src/mana-evolution.js');
const html=fs.readFileSync(path.join(__dirname,'../soulbound-crystal-hud-preview.html'),'utf8');
const code=html.slice(html.indexOf('    class SoulController'),html.indexOf('    // SOUL_CONTROLLER_END'));
const context={};vm.createContext(context);vm.runInContext(code+';this.SoulController=SoulController;',context);
const SoulController=context.SoulController;
let passed=0;
const close=(a,b)=>assert.ok(Math.abs(a-b)<1e-7,`${a} != ${b}`);
const test=(name,fn)=>{fn();passed++;console.log('PASS',name);};
const total=s=>s.mana+s.reserveFill.reduce((sum,x)=>sum+x*s.manaMax,0);
const make=(level=5,mana=300)=>({health:12,mana,manaMax:E.profileFor(level).manaMax,reserves:level,reserveFill:[0,0,0,0,0]});

test('six stages have exact capacities and cumulative readable ornaments',()=>{
  assert.deepEqual(E.profiles.map(p=>p.name),['Start','Restored','Awakening','Empowered','Ascendant','Strongest']);
  assert.deepEqual(E.profiles.map(p=>p.manaMax),[100,140,180,220,260,300]);
  assert.deepEqual(E.profiles.map(p=>p.rimRunes),[0,1,2,3,4,4]);
  assert.deepEqual(E.profiles.map(p=>p.crystalRunes),[0,0,0,1,2,3]);
  assert.deepEqual(E.profiles.map(p=>p.circleQuarters),[0,0,0,0,0,4]);
  assert.ok(Object.isFrozen(E.profiles)&&E.profiles.every(Object.isFrozen));
});
test('upgrades preserve absolute Soul and introduce empty reserves',()=>{
  let s=make(0,67);const original=s;
  for(let level=1;level<=5;level++){
    if(level>1)s.reserveFill[level-2]=.35;
    const before=total(s),old=s;s=E.changeReserves(s,level);
    close(total(s),before);close(s.mana,67);close(s.reserveFill[level-1],0);
    assert.equal(s.reserves,level);assert.notEqual(s,old);assert.notEqual(s.reserveFill,old.reserveFill);
  }
  assert.equal(original.manaMax,100);
});
test('manual downgrade clamps removed storage without creating Soul',()=>{
  const s=make();s.reserveFill=[1,.5,.2,.3,.1];const next=E.changeReserves(s,2);
  assert.equal(next.manaMax,180);assert.equal(next.mana,180);assert.ok(total(next)<=total(s));
  close(next.reserveFill[0],1);close(next.reserveFill[1],150/180);assert.deepEqual(next.reserveFill.slice(2),[0,0,0]);
});
test('invalid stage input fails before any live state is replaced',()=>{
  const s=make(),before=JSON.stringify(s);
  for(const level of [-1,6,1.2,NaN])assert.throws(()=>E.changeReserves(s,level),RangeError);
  assert.equal(JSON.stringify(s),before);
});
test('consumption and reserve exhaustion never downgrade appearance',()=>{
  const s=make();s.reserveFill=[.1,0,0,0,0];const c=new SoulController(s);
  c.tryCast(40);c.advance(3);assert.equal(E.resolve(s,c.displayMana).level,5);close(s.reserveFill[0],0);
});
test('full effect requires actual AND displayed mana, independently of stored reserves',()=>{
  const s=make();assert.equal(E.resolve(s,300).full,true);
  assert.equal(E.resolve(s,299).full,false);s.mana=299;assert.equal(E.resolve(s,300).full,false);
  s.mana=300;s.health=0;assert.equal(E.resolve(s,300).full,false);
});
test('start has no circle or aura even at full',()=>{
  const s=make(0,100),v=E.resolve(s,100),a=new E.Aura();
  assert.equal(v.profile.circleQuarters,0);assert.equal(a.sample(v,0).opacity,0);assert.equal(a.sample(v,2).emitting,false);
});
test('full presets and kill rewards activate aura without forging eye completion',()=>{
  const s=make(),c=new SoulController(s),a=new E.Aura();
  assert.ok(a.sample(E.resolve(s,c.displayMana),c.time).emitting);assert.equal(c.refillCompletedAt,null);
  c.tryCast(25);a.sample(E.resolve(s,c.displayMana),c.time);c.advance(.3);c.gain(25);
  assert.ok(a.sample(E.resolve(s,c.displayMana),c.time).emitting);assert.equal(c.refillCompletedAt,null);
});
test('reserve refill still provides its separate short eye cue',()=>{
  const s=make(5,250);s.reserveFill[0]=.5;const c=new SoulController(s),a=new E.Aura();
  a.sample(E.resolve(s,c.displayMana),0);c.advance(.5+50/150+.2);
  assert.ok(a.sample(E.resolve(s,c.displayMana),c.time).emitting);close(c.settling().eyes,1);
  c.advance(1);assert.ok(a.sample(E.resolve(s,c.displayMana),c.time).emitting);close(c.settling().eyes,0);
});
test('accepted casts stop emission immediately and residuals expire in .2 seconds',()=>{
  const s=make(),c=new SoulController(s),a=new E.Aura();a.sample(E.resolve(s,c.displayMana),0);c.advance(2);
  const full=a.sample(E.resolve(s,c.displayMana),c.time);assert.ok(c.tryCast(25));
  const spent=a.sample(E.resolve(s,c.displayMana),c.time);assert.equal(spent.emitting,false);close(spent.opacity,full.opacity);
  assert.equal(spent.runeEmission,0);c.advance(.1);close(a.sample(E.resolve(s,c.displayMana),c.time).opacity,full.opacity/2);
  c.advance(.1);close(a.sample(E.resolve(s,c.displayMana),c.time).opacity,0);close(s.mana,275);
});
test('failed casts preserve the aura and do not spend Soul',()=>{
  const s=make(),c=new SoulController(s),a=new E.Aura();a.sample(E.resolve(s,c.displayMana),0);c.advance(1);
  const before=a.sample(E.resolve(s,c.displayMana),c.time);assert.equal(c.tryCast(301),false);
  assert.deepEqual(a.sample(E.resolve(s,c.displayMana),c.time),before);close(s.mana,300);
});
test('breathing repeats every four seconds and agrees across frame rates',()=>{
  const v=E.resolve(make(),300),a=new E.Aura();const initial=a.sample(v,0);
  close(a.sample(v,2).breath,1);close(a.sample(v,4).opacity,initial.opacity);
  const values=[];
  for(const steps of [1,30,60,120]){const b=new E.Aura();b.sample(v,0);for(let i=1;i<=steps;i++)b.sample(v,1.3*i/steps);values.push(b.last.opacity);}
  values.forEach(x=>close(x,values[0]));
});
test('paused Soul time freezes breathing with no hidden catch-up',()=>{
  const s=make(),c=new SoulController(s),a=new E.Aura();a.sample(E.resolve(s,300),0);c.advance(1);
  const before=a.sample(E.resolve(s,300),c.time);c.setPaused(true);c.advance(15);
  assert.deepEqual(a.sample(E.resolve(s,300),c.time),before);c.setPaused(false);c.advance(.1);close(c.time,1.1);
});
test('death, reset and stage changes clear residual magic',()=>{
  const s=make(),a=new E.Aura();a.sample(E.resolve(s,300),0);a.sample(E.resolve(s,300),2);
  s.health=0;const dead=a.sample(E.resolve(s,300),2);assert.equal(dead.opacity,0);assert.equal(dead.emitting,false);
  s.health=12;s.mana=50;a.reset();assert.equal(a.sample(E.resolve(s,50),0).opacity,0);
  s.mana=300;a.sample(E.resolve(s,300),0);s.reserves=0;s.mana=100;
  assert.equal(a.sample(E.resolve(s,100),0).opacity,0);
});
test('reduced motion is a steady full glow and static aura',()=>{
  const v=E.resolve(make(),300),a=new E.Aura(true);const start=a.sample(v,0),later=a.sample(v,2);
  close(start.opacity,later.opacity);assert.equal(later.motion,false);assert.equal(later.effectAge,0);assert.equal(later.runeEmission,1);
});
test('post-upgrade automatic refill conserves Soul at the new capacity rate',()=>{
  const s=make(1,140);s.reserveFill[0]=.5;const before=total(s),next=E.changeReserves(s,2),c=new SoulController(next);
  close(next.mana,140);assert.equal(c.phase,'cooldown');c.advance(.5+40/90);
  close(next.mana,180);close(total(next),before);close(next.reserveFill[0]*180,30);close(next.reserveFill[1],0);
});
console.log(`${passed} mana evolution scenarios passed.`);
