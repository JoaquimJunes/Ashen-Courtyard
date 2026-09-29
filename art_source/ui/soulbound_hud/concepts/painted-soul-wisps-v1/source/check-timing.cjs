const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync(__dirname+'/animation.js','utf8');
const api={};vm.runInNewContext(source.slice(source.indexOf('const clamp='),source.indexOf('function makeCanvas'))+';this.sample=poseAt;',api);
const sample=api.sample;
for(let i=0;i<600;i++){
  const t=i/60,s=sample(t);
  assert.ok(Math.abs(s.actual+s.reserve-(t<6.6?300:210))<1e-7);
  assert.ok(s.actual>=0&&s.actual<=300&&s.reserve>=0&&s.reserve<=300);
  if(t<2.5||t>=8.7)assert.equal(s.aura,0);
  if(s.eyes>0)assert.equal(s.actual,300);
}
for(const [time,phase] of [[0,'empty'],[.5,'refill'],[2.5,'burst'],[2.95,'gather'],[3.7,'settle'],[4.6,'settled'],[6.6,'linger'],[8.1,'dissolve'],[8.7,'below-full']])assert.equal(sample(time).phase,phase);
assert.equal(sample(1.5).actual,150);assert.equal(sample(1.5).reserve,150);
assert.equal(sample(6.6).actual,210);assert.equal(sample(6.6).display,300);
assert.ok(Math.abs(sample(6.9).display-210)<1e-9);
console.log('All 600 sampled states preserve Soul; selected phase boundaries, main-only burst, eye timing and 0.3 s visual drain passed.');
