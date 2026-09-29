// Local coordinates match the unchanged 530px painted frame. These layers share
// its shake/zoom transform; nothing here changes the heart-frame artwork.
const evolutionRunePaths = [
  [[-5,7],[1,-9],[6,-2],[-3,1],[4,7]],
  [[-4,9],[-4,-9],[5,-3],[-4,1],[5,8]],
  [[-5,-8],[1,-2],[6,-7],[0,9],[0,-9]],
  [[-5,4],[5,-5],[0,-9],[0,9],[6,2]],
  [[-6,1],[4,-7],[0,7],[-6,1],[1,0]],
  [[0,9],[0,-9],[-5,-3],[5,-3],[0,-9],[0,2],[4,2]],
  [[-4,-7],[6,1],[-4,7],[-4,-7],[0,1]],
];
const evolutionRimAnchors = [[108,91],[219,110],[234,187],[79,184]];
const evolutionCrystalAnchors = [[-.43,-.52],[0,-.65],[.43,-.52]];
let evolutionVisual;
const evolutionAura = new ManaEvolution.Aura(reduced);

function observeEvolution() {
  const resolved=ManaEvolution.resolve(s,soul.displayMana);
  evolutionVisual={...resolved,...evolutionAura.sample(resolved,soul.time)};
  return evolutionVisual;
}

function drawEvolutionGlyph(index,x,y,scale,emission) {
  c.save();c.translate(x,y);c.scale(scale,scale);c.lineCap='round';
  const points=evolutionRunePaths[index];
  // Engraving stays readable when the emitted light is off.
  line(points,'#160d25',3.8);
  line(points,emission?'#c793f5':'#68517e',1.9);
  if(emission){
    glow(()=>line(points,'#c982ff',2.6),5,'#9f49ed');
    line(points,'#eed2ff',1.15);
  }
  c.restore();
}

function drawEvolutionAura() {
  const v=evolutionVisual;if(!v||v.opacity<=.001)return;
  c.save();c.beginPath();c.rect(0,0,264,314);c.clip();
  // Each deterministic ribbon occupies a fixed emission site. On spending,
  // freeze the sites and dissolve existing ribbons; no new birth can wrap in.
  const time=v.emitting?v.effectAge:Math.max(0,v.effectAge-v.fadeAge);
  const angles=[-2.93,-2.48,-2.05,-1.57,-.97,.96,1.46,2.13,2.65];
  for(let i=0;i<angles.length;i++){
    const life=v.motion?(time/4+i*.173)%1:.32+(i%3)*.14;
    const alpha=v.opacity*(v.motion?Math.sin(life*Math.PI):.65);
    const angle=angles[i],radius=115+life*9;
    const points=[];
    for(let j=0;j<=7;j++){
      const u=j/7,a=angle+Math.sin(u*5+i*.8+time*.35)*.07;
      const r=radius+u*(14+life*8);
      points.push([155.5+Math.cos(a)*r,163+Math.sin(a)*r-u*6]);
    }
    const width=(1-life)*5.5+1.4;
    const left=points.map((p,j)=>[p[0]-Math.sin(angle)*width*(1-j/8),p[1]+Math.cos(angle)*width*(1-j/8)]);
    const right=points.map((p,j)=>[p[0]+Math.sin(angle)*width*(1-j/8),p[1]-Math.cos(angle)*width*(1-j/8)]).reverse();
    c.globalAlpha=alpha*.44;path(left.concat(right),'#7135a7');
    c.globalAlpha=alpha*.28;glow(()=>line(points,'#a45dea',3.6),11,'#762bc4');
    c.globalAlpha=alpha*.48;line(points.slice(2,6),'#ae76da',.8);
  }
  c.restore();
}

function drawEvolutionCircle() {
  const v=evolutionVisual,quarters=v?.profile.circleQuarters||0;if(!quarters)return;
  const emission=v.circleEmission;
  c.save();c.beginPath();c.rect(0,0,264,314);c.clip();
  const points=[],start=-Math.PI,steps=quarters*6;
  for(let i=0;i<=steps;i++){
    const a=start+i*Math.PI/12;
    points.push([155.5+Math.cos(a)*128,163+Math.sin(a)*128]);
  }
  line(points,'#180e28',3.0);line(points,emission?'#ba81ec':'#5b426f',1.2);
  if(emission){c.globalAlpha=.48;glow(()=>line(points,'#b581e5',1),5,'#9150d6');c.globalAlpha=1;}
  for(let i=0;i<steps;i+=3){
    const [x,y]=points[i];path([[x,y-3],[x+3,y],[x,y+3],[x-3,y]],null,emission?'#d0a8f2':'#725888',1);
  }
  if(v.profile.connectors){
    for(let i=0;i<24;i+=2){
      const a=start+i*Math.PI/12,b=a+Math.PI/12;
      line([[155.5+Math.cos(a)*128,163+Math.sin(a)*128],
        [155.5+Math.cos((a+b)/2)*122,163+Math.sin((a+b)/2)*122],
        [155.5+Math.cos(b)*128,163+Math.sin(b)*128]],emission?'#9672b5':'#41334f',.65);
    }
  }
  c.restore();
}

function drawEvolutionRimRunes() {
  if(!evolutionVisual)return;
  for(let i=0;i<evolutionVisual.profile.rimRunes;i++)
    drawEvolutionGlyph(i,...evolutionRimAnchors[i],1.05,evolutionVisual.runeEmission);
}

function drawEvolutionCrystalRunes() {
  if(!evolutionVisual)return;
  for(let i=0;i<evolutionVisual.profile.crystalRunes;i++)
    drawEvolutionGlyph(i+4,...evolutionCrystalAnchors[i],.016,evolutionVisual.runeEmission);
}

function setEvolutionLevel(level) {
  Object.assign(s,ManaEvolution.changeReserves(s,level));
  preset='';notice='';recovering=false;normalize();soul.reset();evolutionAura.reset();last=0;
  update();
}

// Render isolated, equal-fill snapshots with the same drawing code. The swap is
// synchronous and always restored; gallery snapshots never advance live resources.
function renderEvolutionSnapshot(target,level,{background='#101118',fill=1}={}) {
  if(!referenceFrame.naturalWidth)return;
  const live={s,soul,c,dead,evolutionVisual,renderScaleX,renderScaleY,flash};
  try{
    const profile=ManaEvolution.profileFor(level);
    s={...s,hearts:3,health:12,reserves:level,manaMax:profile.manaMax,mana:profile.manaMax*fill,
      reserveFill:Array.from({length:5},(_,i)=>i<level?.5:0)};
    soul=new SoulController(s,reduced);dead=false;flash=0;
    const resolved=ManaEvolution.resolve(s,soul.displayMana),aura=new ManaEvolution.Aura(reduced);
    aura.sample(resolved,0);evolutionVisual={...resolved,...aura.sample(resolved,2)};
    c=target.getContext('2d');renderScaleX=target.width/570;renderScaleY=target.height/340;
    c.setTransform(renderScaleX,0,0,renderScaleY,0,0);c.fillStyle=background;c.fillRect(0,0,570,340);
    c.translate(20,12);c.imageSmoothingEnabled=true;c.imageSmoothingQuality='high';drawReferenceAssembly();
  }finally{({s,soul,c,dead,evolutionVisual,renderScaleX,renderScaleY,flash}=live);}
}

function drawEvolutionGallery() {
  if(gallery.hidden||!referenceFrame.naturalWidth)return;
  gallery.querySelectorAll('canvas').forEach((target,level)=>{
    const width=target.getBoundingClientRect().width,density=Math.min(devicePixelRatio||1,3);
    target.width=Math.round(width*density);target.height=Math.round(width*340/570*density);
    renderEvolutionSnapshot(target,level,{background:s.previewBackground==='light'?'#b6b3aa':'#101118'});
  });
}
