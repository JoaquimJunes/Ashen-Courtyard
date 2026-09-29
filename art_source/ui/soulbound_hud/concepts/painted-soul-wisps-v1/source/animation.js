// Isolated offline animation compositor. Does not import or modify the HUD preview.
const WIDTH=1280,HEIGHT=720,FPS=60,FRAME_COUNT=600;
const canvas=document.getElementById('frame'),c=canvas.getContext('2d',{alpha:true});
const clamp=(x,a=0,b=1)=>Math.min(b,Math.max(a,x));
const ease=x=>{x=clamp(x);return x*x*(3-2*x);};
const mix=(a,b,x)=>a+(b-a)*x;
function poseAt(t){
  const s={time:t,phase:'empty',actual:0,display:0,reserve:300,aura:0,reach:0,glow:0,fade:0,eyes:0,transfer:0};
  if(t>=.5&&t<2.5){s.phase='refill';s.actual=s.display=(t-.5)*150;s.reserve=300-s.actual;s.transfer=1;}
  if(t>=2.5){
    s.actual=s.display=300;s.reserve=0;
    s.eyes=t<2.9?Math.sin(Math.PI*(t-2.5)/.4):0;
    if(t<2.95){const a=ease((t-2.5)/.45);Object.assign(s,{phase:'burst',aura:a,reach:mix(.15,1,a),glow:a});}
    else if(t<3.7){const a=ease((t-2.95)/.75);Object.assign(s,{phase:'gather',aura:mix(1,.72,a),reach:mix(1,.45,a),glow:mix(1,.5,a)});}
    else if(t<4.6){const a=ease((t-3.7)/.9);Object.assign(s,{phase:'settle',aura:mix(.72,.44,a),reach:mix(.45,.24,a),glow:mix(.5,.25,a)});}
    else Object.assign(s,{phase:'settled',aura:.44,reach:.24,glow:.25});
  }
  if(t>=6.6){
    s.actual=210;s.display=mix(300,210,ease((t-6.6)/.3));
    const f=ease((t-8.1)/.6);
    Object.assign(s,{phase:t<8.1?'linger':t<8.7?'dissolve':'below-full',aura:.44*(1-f),reach:.24+.22*f,glow:0,fade:f});
  }
  return s;
}
function makeCanvas(w,h){const v=document.createElement('canvas');v.width=w;v.height=h;return v;}
function load(src){return new Promise((resolve,reject)=>{const im=new Image();im.onload=()=>resolve(im);im.onerror=()=>reject(Error(src));im.src=src;});}
function shape(ctx,pts,fill){ctx.beginPath();pts.forEach((p,i)=>i?ctx.lineTo(...p):ctx.moveTo(...p));ctx.closePath();ctx.fillStyle=fill;ctx.fill();}
const layout={scale:.57,x:(1280-1671*.57)/2,y:146,cx:505,cy:510,rx:222,ry:213};
const reserveCenters=[[221,724,50],[347,818,52],[495,855,49],[647,818,52],[798,741,51]];
let layers,wispRenderer;
function extractLayers(stone,crystal){
  const base=makeCanvas(stone.width,stone.height),b=base.getContext('2d');b.drawImage(stone,0,0);
  const runes=makeCanvas(stone.width,stone.height),r=runes.getContext('2d');
  const data=b.getImageData(0,0,stone.width,stone.height),emission=r.createImageData(stone.width,stone.height);
  const spots=[[164,444,51,104],[538,166,57,87],[378,226,34,38],[308,291,27,37],[635,284,29,28],[741,375,30,44],[777,483,38,40],[763,597,34,45],[675,700,29,39],[511,766,41,30],[361,717,30,25],[257,585,30,38],[254,490,26,32]];
  for(let y=0;y<stone.height;y++)for(let x=0;x<stone.width;x++){
    const k=(y*stone.width+x)*4,a=data.data[k+3];if(!a)continue;
    // Separate the authored violet rune emission from the painted recesses.
    if(!spots.some(([cx,cy,rx,ry])=>((x-cx)/rx)**2+((y-cy)/ry)**2<1))continue;
    const red=data.data[k],green=data.data[k+1],blue=data.data[k+2];
    const m=clamp((blue-green-25)/70)*clamp((blue-100)/90);
    if(m===0)continue;
    emission.data[k]=red;emission.data[k+1]=green;emission.data[k+2]=blue;emission.data[k+3]=a*m;
    data.data[k]=red*(1-.68*m);data.data[k+1]=green*(1-.70*m);data.data[k+2]=blue*(1-.65*m);
  }
  b.putImageData(data,0,0);r.putImageData(emission,0,0);
  // Move the first painted reserve's contents into the animated fill layer.
  b.globalCompositeOperation='destination-out';b.beginPath();b.arc(221,724,52,0,Math.PI*2);b.fill();b.globalCompositeOperation='source-over';
  const orb=makeCanvas(480,480),o=orb.getContext('2d');
  o.drawImage(crystal,85,76,1080,1098,0,0,480,480);
  const eyes=makeCanvas(480,480),e=eyes.getContext('2d');
  for(const sign of [-1,1]){
    const points=[[sign*165,29],[sign*100,52],[sign*33,82],[sign*70,108],[sign*122,91]].map(([x,y])=>[x+240,y+240]);
    shape(e,points,'#130923');
    const inside=[[sign*151,46],[sign*83,71],[sign*43,80],[sign*77,100],[sign*116,85]].map(([x,y])=>[x+240,y+240]);
    shape(e,inside,'#f8eaff');
  }
  const liquid=makeCanvas(480,480),l=liquid.getContext('2d');l.drawImage(orb,0,0);
  l.globalCompositeOperation='source-atop';const shade=l.createLinearGradient(0,0,0,480);
  shade.addColorStop(0,'rgba(17,0,34,.77)');shade.addColorStop(.6,'rgba(30,0,61,.48)');shade.addColorStop(1,'rgba(78,4,150,.16)');
  l.fillStyle=shade;l.fillRect(0,0,480,480);
  return {stone:base,runes,crystal:orb,eyes,liquid};
}
function buildWisps(atlas){
  // GPU UV deformation keeps the generated painted texture, alpha and broad curls.
  const surface=makeCanvas(WIDTH,HEIGHT);
  const gl=surface.getContext('webgl',{alpha:true,premultipliedAlpha:true,preserveDrawingBuffer:true});
  if(!gl)throw Error('WebGL is required for painted wisp deformation');
  function shader(type,src){const s=gl.createShader(type);gl.shaderSource(s,src);gl.compileShader(s);if(!gl.getShaderParameter(s,gl.COMPILE_STATUS))throw Error(gl.getShaderInfoLog(s));return s;}
  const vs=shader(gl.VERTEX_SHADER,`attribute vec2 p;uniform vec2 center,size;uniform float angle;varying vec2 uv;void main(){uv=p*.5+.5;vec2 q=p*size*.5;float c=cos(angle),s=sin(angle);q=mat2(c,s,-s,c)*q+center;gl_Position=vec4(q/vec2(640.,360.)*vec2(1.,-1.)+vec2(-1.,1.),0.,1.);}`);
  const fs=shader(gl.FRAGMENT_SHADER,`precision highp float;varying vec2 uv;uniform sampler2D tex;uniform vec4 rect;uniform float time,seed,opacity,fray;
    float h(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
    float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(h(i),h(i+vec2(1,0)),f.x),mix(h(i+vec2(0,1)),h(i+vec2(1,1)),f.x),f.y);}
    void main(){vec2 q=uv;float envelope=sin(uv.y*3.14159)*sin(uv.x*3.14159);
      q.x+=envelope*(sin(uv.y*7.+time*1.8+seed)*.052+sin(uv.y*15.-time*1.3+seed)*.012);
      q.y+=envelope*cos(uv.x*8.+time*1.2+seed)*.030;
      vec4 color=texture2D(tex,rect.xy+q*rect.zw);
      float border=smoothstep(0.,.032,q.x)*smoothstep(0.,.032,q.y)*smoothstep(0.,.032,1.-q.x)*smoothstep(0.,.032,1.-q.y);
      float n=noise(q*12.+vec2(time*.12,-time*.2));
      float dissolve=1.-smoothstep(n-.1,n+.18,fray);
      float a=color.a*opacity*border*dissolve;
      gl_FragColor=vec4(color.rgb*a,a);
    }`);
  const program=gl.createProgram();gl.attachShader(program,vs);gl.attachShader(program,fs);gl.linkProgram(program);if(!gl.getProgramParameter(program,gl.LINK_STATUS))throw Error(gl.getProgramInfoLog(program));gl.useProgram(program);
  const buffer=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,buffer);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-1,-1,1,-1,-1,1,-1,1,1,-1,1,1]),gl.STATIC_DRAW);
  const attr=gl.getAttribLocation(program,'p');gl.enableVertexAttribArray(attr);gl.vertexAttribPointer(attr,2,gl.FLOAT,false,0,0);
  const texture=gl.createTexture();gl.bindTexture(gl.TEXTURE_2D,texture);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,gl.RGBA,gl.UNSIGNED_BYTE,atlas);
  const uniforms=Object.fromEntries(['center','size','angle','rect','time','seed','opacity','fray'].map(n=>[n,gl.getUniformLocation(program,n)]));
  gl.enable(gl.BLEND);gl.blendFunc(gl.ONE,gl.ONE_MINUS_SRC_ALPHA);gl.viewport(0,0,WIDTH,HEIGHT);
  // Only the two isolated right sprites are sampled; the left cells overlap.
  const rects=[[704/1330,4/1182,618/1330,606/1182],[814/1330,629/1182,492/1330,546/1182]];
  const specs=[
    {a:-2.78,h:280,w:220,turn:-.40,seed:2,tex:1},
    {a:-2.15,h:420,w:295,turn:-.22,seed:5,tex:0},
    {a:-1.52,h:470,w:310,turn:.06,seed:9,tex:1},
    {a:-.89,h:345,w:270,turn:.34,seed:13,tex:0},
    {a:2.85,h:250,w:210,turn:-1.0,seed:19,tex:0}
  ];
  return {surface,draw(s){
    gl.clearColor(0,0,0,0);gl.clear(gl.COLOR_BUFFER_BIT);if(s.aura<=.00001)return;
    gl.uniform1f(uniforms.time,s.time);gl.uniform1f(uniforms.fray,s.fade*.86);
    for(const [i,v] of specs.entries()){
      const growth=.40+s.reach*.60;
      const h=v.h*growth,w=v.w*(.61+.39*s.reach);
      const angle=v.turn+Math.sin(s.time*.65+v.seed)*.07;
      const anchor=[layout.cx+Math.cos(v.a)*310,layout.cy+Math.sin(v.a)*310];
      const x=anchor[0]+Math.sin(angle)*h*.29+Math.sin(s.time*1.05+v.seed)*(4+s.reach*8);
      const y=anchor[1]-h*.37+Math.cos(s.time*.91+v.seed)*7;
      gl.uniform2f(uniforms.center,layout.x+x*layout.scale,layout.y+y*layout.scale);
      gl.uniform2f(uniforms.size,w*layout.scale,h*layout.scale);
      gl.uniform1f(uniforms.angle,angle);gl.uniform4fv(uniforms.rect,rects[v.tex]);
      gl.uniform1f(uniforms.seed,v.seed);gl.uniform1f(uniforms.opacity,s.aura*(i===4?.57:.84));
      gl.drawArrays(gl.TRIANGLES,0,6);
    }
    gl.finish();
  }};
}
function drawCircle(s){
  const cx=layout.cx,cy=layout.cy,r=383;
  c.save();c.lineWidth=2.5;c.strokeStyle=`rgba(184,116,244,${.20+s.glow*.54})`;
  c.shadowColor='#ae4fff';c.shadowBlur=s.glow*11;
  for(const rad of [r,r-18]){
    c.beginPath();for(let i=0;i<=32;i++){const a=-Math.PI/2+i*Math.PI/16;const p=[cx+Math.cos(a)*rad,cy+Math.sin(a)*rad];i?c.lineTo(...p):c.moveTo(...p);}c.stroke();
  }
  c.shadowBlur=0;c.lineWidth=2.2;
  for(let i=0;i<12;i++){
    const a=i*Math.PI/6,x=cx+Math.cos(a)*r,y=cy+Math.sin(a)*r;
    c.beginPath();c.moveTo(x,y-7);c.lineTo(x+7,y);c.lineTo(x,y+7);c.lineTo(x-7,y);c.closePath();c.stroke();
  }
  c.restore();
}
function orbBoundary(){c.beginPath();c.ellipse(layout.cx,layout.cy,layout.rx,layout.ry,0,0,Math.PI*2);}
function liquidLevel(s){return layout.cy+layout.ry-2*layout.ry*s.display/300;}
function liquidPath(s){
  const y=liquidLevel(s),tilt=s.time>=6.6?Math.sin((s.time-6.6)*12)*Math.exp(-(s.time-6.6)*3.1)*17:0;
  c.beginPath();c.moveTo(layout.cx-layout.rx-3,layout.cy+layout.ry+4);
  for(let i=0;i<=64;i++){const u=i/64,x=layout.cx-layout.rx+2*layout.rx*u;const ripple=(Math.sin(s.time*4+u*11)+Math.sin(s.time*2-u*7))*(s.display>0&&s.display<300?1.8:0);c.lineTo(x,y+tilt*(u*2-1)+ripple);}
  c.lineTo(layout.cx+layout.rx+3,layout.cy+layout.ry+4);c.closePath();
}
function drawOrb(s){
  const x=layout.cx-layout.rx,y=layout.cy-layout.ry,w=layout.rx*2,h=layout.ry*2;
  c.save();orbBoundary();c.clip();
  c.fillStyle='#100a1c';c.fillRect(x,y,w,h);
  c.globalAlpha=.36;c.drawImage(layers.crystal,x,y,w,h);c.globalAlpha=1;
  if(s.display>0){
    c.save();liquidPath(s);c.clip();c.drawImage(layers.liquid,x,y,w,h);
    if(s.transfer){const g=c.createRadialGradient(layout.cx,layout.cy+layout.ry*.82,0,layout.cx,layout.cy+layout.ry*.82,layout.rx*.9);g.addColorStop(0,'rgba(159,59,239,.30)');g.addColorStop(1,'rgba(76,12,149,0)');c.fillStyle=g;c.fillRect(x,y,w,h);}
    c.globalAlpha=clamp((s.display/300-.30)/.15);c.shadowColor='#c584ff';c.shadowBlur=s.eyes*18;c.drawImage(layers.eyes,x,y,w,h);c.shadowBlur=0;c.globalAlpha=1;c.restore();
    if(s.display<299.999){
      const fy=liquidLevel(s),span=layout.rx*Math.sqrt(Math.max(0,1-((fy-layout.cy)/layout.ry)**2));
      c.beginPath();c.ellipse(layout.cx,fy,span,9+Math.sin(s.time*3)*1.5,0,0,Math.PI*2);
      c.fillStyle='rgba(60,19,97,.66)';c.fill();c.lineWidth=2.6;c.strokeStyle='rgba(171,96,236,.79)';c.stroke();
    }
  }
  // Painted facet lighting overlays the moving Soul and its meniscus.
  c.globalCompositeOperation='screen';c.globalAlpha=.20;c.drawImage(layers.crystal,x,y,w,h);
  c.restore();
}
function drawReserves(s){
  reserveCenters.forEach(([x,y,r],i)=>{
    const cover=r+8;
    c.save();c.beginPath();c.arc(x,y,cover,0,Math.PI*2);c.clip();c.fillStyle='#100c18';c.fillRect(x-cover,y-cover,cover*2,cover*2);
    if(i===0&&s.reserve>0){
      const fill=s.reserve/300,g=c.createLinearGradient(0,y-r,0,y+r);g.addColorStop(0,'#32113e');g.addColorStop(1,'#682399');c.fillStyle=g;c.fillRect(x-r,y+r-2*r*fill,r*2,r*2*fill);
      c.strokeStyle=`rgba(226,189,255,${.5+.5*fill})`;c.lineWidth=4.3;c.beginPath();c.moveTo(x,y-25);c.lineTo(x,y+25);c.lineTo(x+15,y+13);c.lineTo(x-13,y+13);c.lineTo(x+12,y-8);c.stroke();
    }
    c.restore();
  });
}
function transfer(s){
  if(!s.transfer)return;
  c.save();c.strokeStyle='rgba(152,77,231,.5)';c.lineWidth=2;c.shadowBlur=9;c.shadowColor='#9345e2';c.beginPath();c.arc(layout.cx,layout.cy,242,1.57,2.48);c.stroke();
  for(let j=0;j<4;j++){const a=2.48-((s.time*.7+j/4)%1)*.91;const x=layout.cx+Math.cos(a)*242,y=layout.cy+Math.sin(a)*242;c.beginPath();c.ellipse(x,y,4,7,a,0,Math.PI*2);c.fillStyle='#dca4ff';c.fill();}c.restore();
}
function render(t,{background=false,scale=1}={}){
  const s=poseAt(t);c.setTransform(1,0,0,1,0,0);c.clearRect(0,0,WIDTH,HEIGHT);
  if(background){c.fillStyle='#0c0e15';c.fillRect(0,0,WIDTH,HEIGHT);}
  c.save();if(scale!==1){c.translate(WIDTH*(1-scale)/2,HEIGHT*(1-scale)/2);c.scale(scale,scale);}
  wispRenderer.draw(s);c.drawImage(wispRenderer.surface,0,0);
  c.translate(layout.x,layout.y);c.scale(layout.scale,layout.scale);
  drawCircle(s);drawOrb(s);drawReserves(s);c.drawImage(layers.stone,0,0);
  c.save();c.globalCompositeOperation='screen';c.globalAlpha=.10+s.glow*.85;c.drawImage(layers.runes,0,0);c.restore();
  transfer(s);c.restore();
  return s;
}
window.ready=(async()=>{
  const [stone,crystal,wisps]=await Promise.all(['../assets/stone-generated.png','../assets/crystal-painted.png','../assets/soul-wisps-atlas.png'].map(load));
  layers=extractLayers(stone,crystal);wispRenderer=buildWisps(wisps);render(0);return true;
})();
window.render=render;window.poseAt=poseAt;window.exportLayers=()=>Object.fromEntries(Object.entries(layers).map(([k,v])=>[k,v.toDataURL('image/png')]));
