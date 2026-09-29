// Reference-only drawing fork of the reviewed crystal and stone. No game state.
function createSoulWispDrawing(canvas,referenceFrame){
  const c=canvas.getContext('2d');
  const clamp=(n,a=0,b=1)=>Math.max(a,Math.min(b,n));
  let renderScaleX=1,tick=0,reduced=false,pose=null;
  const soul={
    surfaceOffset(x,amount){
      if(reduced)return 0;
      const kick=Math.exp(-pose.dropAge*3)*.12;
      return Math.sin(tick*3.6+x*7)*.012+Math.sin(pose.dropAge*13)*x*kick;
    },
    settling(){return {eyes:pose.eye};}
  };
  function arc(x,y,r,a,b,color,width){c.beginPath();c.arc(x,y,r,a,b);c.strokeStyle=color;c.lineWidth=width;c.stroke();}
  function drawSoulInletLight(){
    if(!pose.refilling)return;
    const g=c.createRadialGradient(0,.86,0,0,.86,.65);
    g.addColorStop(0,'rgba(160,78,247,.25)');g.addColorStop(1,'rgba(65,14,145,0)');
    c.fillStyle=g;c.fillRect(-1,-1,2,2);
  }
  function drawSoulSpiral(){}
  function drawSoulSettling(){}
    function path(points,fill,stroke=null,width=1) { c.beginPath(); points.forEach((p,i)=>i?c.lineTo(...p):c.moveTo(...p));c.closePath();if(fill){c.fillStyle=fill;c.fill();}if(stroke){c.strokeStyle=stroke;c.lineWidth=width;c.stroke();} }
    function line(points,color,width=1) {c.beginPath();points.forEach((p,i)=>i?c.lineTo(...p):c.moveTo(...p));c.strokeStyle=color;c.lineWidth=width;c.lineJoin='miter';c.miterLimit=2;c.stroke();}
    function circle(x,y,r,fill,stroke=null,w=1) {c.beginPath();c.arc(x,y,r,0,Math.PI*2);if(fill){c.fillStyle=fill;c.fill();}if(stroke){c.strokeStyle=stroke;c.lineWidth=w;c.stroke();}}
    function poly(x,y,r,n=16,offset=-Math.PI/2) {return Array.from({length:n},(_,i)=>[x+Math.cos(offset+i*Math.PI*2/n)*r,y+Math.sin(offset+i*Math.PI*2/n)*r]);}
    function text(words,x,y,size=15,color='#e0ddcc',align='left') {c.font=`${size}px Georgia, serif`;c.textAlign=align;c.fillStyle=color;c.shadowColor='#000';c.shadowBlur=3*renderScaleX;c.fillText(words,x,y);c.shadowBlur=0;}
    function glow(fn,strength=7,color='#9167ed') {c.save();c.shadowBlur=strength*renderScaleX;c.shadowColor=color;fn();c.restore();}
    function glyph(x,y,k,scale=1,lit=true) {
      const shapes=[[[0,9],[0,-9],[7,-4],[0,1],[-5,-4]], [[-5,7],[3,-8],[3,8],[-4,1],[6,-4]], [[0,9],[0,-9],[-6,-3],[0,2],[6,-4]], [[-6,-7],[0,-2],[6,-7],[0,8],[0,-2]], [[-6,5],[6,-5],[0,-8],[0,9]], [[0,-9],[0,9],[6,3],[0,-2],[-5,3]]];
      c.save();c.translate(x,y);c.scale(scale,scale);const pts=shapes[k%shapes.length];line(pts,'#0a0911',4);if(lit)glow(()=>line(pts,'#c5a4ff',1.5),7);else line(pts,'#62606b',1);c.restore();
    }

    const heartParts=[ [[-14,-5],[-8,-12],[-3,-12],[-1,-8],[-1,-1],[-14,-1]], [[1,-8],[3,-12],[8,-12],[14,-5],[14,-1],[1,-1]], [[-14,1],[-1,1],[-1,14]], [[1,1],[14,1],[1,14]] ];
    function heart(x,y,base,gold) {
      c.save();c.translate(x,y);
      path([[-15.5,-5],[-9,-14],[-3,-14],[0,-10],[3,-14],[9,-14],[15.5,-5],[15.5,1],[0,17],[-15.5,1]],'#1a0712','#08080b',1);
      heartParts.forEach((p,i)=>{
        const b=clamp(base-i,0,1),g=clamp(gold-i,0,1);
        path(p,'#29282c','#53464c',.6);
        if(b>0){c.save();c.beginPath();p.forEach((v,j)=>j?c.lineTo(...v):c.moveTo(...v));c.closePath();c.clip();c.fillStyle=['#fa3150','#ff2146','#a20a27','#df163b'][i];c.fillRect(-17,17-34*b,34,34*b);c.restore();}
        if(g>0){c.save();c.beginPath();p.forEach((v,j)=>j?c.lineTo(...v):c.moveTo(...v));c.closePath();c.clip();c.fillStyle=['#e1ae42','#ffda7a','#a77128','#c98a32'][i];c.fillRect(-17,17-34*g,34,34*g);c.restore();}
        if(b>0||g>0){
          const mid=p.reduce((acc,v)=>[acc[0]+v[0]/p.length,acc[1]+v[1]/p.length],[0,0]);
          for(let j=0;j<p.length;j++){path([p[j],p[(j+1)%p.length],mid],j%3===0?'rgba(255,224,209,.20)':j%3===1?'rgba(22,4,18,.20)':'rgba(255,255,255,.025)');}
        }
      });line([[-14,-5],[-8,-12],[-3,-12]],gold>0?'#ffe6a7':base>0?'#ff7289':'#72626a',1);
      c.restore();
    }

    function drawReferenceReserve(x,y,amount,index){
      c.save();c.translate(x,y);c.scale(1.47,1.47);
      c.shadowColor='rgba(6,3,12,.85)';c.shadowBlur=3*renderScaleX;
      path(poly(0,0,18,14),'#201b26','#09070d',1.4);c.shadowBlur=0;
      circle(0,0,15.8,'#49434e','#9b919e',1.15);
      // Painted rim highlights; the reserve interior stays flat.
      for(let i=0;i<8;i++){
        const a=-Math.PI/2+i*Math.PI/4;
        arc(0,0,15.2,a+.05,a+.65,i<3?'#726975':'#343039',1.6);
      }
      circle(0,0,12.9,'#100b17','#17111f',2);
      c.save();c.beginPath();c.arc(0,0,11.7,0,Math.PI*2);c.clip();
      if(amount>0){
        const g=c.createLinearGradient(0,-12,0,12);g.addColorStop(0,'#211134');g.addColorStop(.6,'#401779');g.addColorStop(1,'#6028a6');
        c.fillStyle=g;c.fillRect(-13,12-24*amount,26,24*amount);
        if(amount<.98)line([[-12,12-24*amount],[12,12-24*amount]],'#b569f7',.8);
      }
      c.restore();
      if(amount>0){
        c.globalAlpha=.65+.35*amount;
        const runes=[[[0,-8],[0,8],[5,5],[-5,5],[4,-3],[0,-1]], [[-2,-9],[-2,8],[-2,0],[5,-5],[4,1],[-2,4]], [[-1,-8],[-1,8],[-1,-1],[5,-5],[-1,2],[5,5]]];
        const points=runes[index%3];
        line(points,'#1a0b2e',3.8);
        glow(()=>line(points,'#e0b9ff',1.7),4,'#b269ff');
        circle(-3,-8,.9,'#e3c3ff');
      }
      c.restore();
    }

    const unit=v=>{const m=Math.hypot(...v)||1;return v.map(n=>n/m);};
    const dot=(a,b)=>a.reduce((v,n,i)=>v+n*b[i],0);
    const sphereRing=(n,r,offset)=>Array.from({length:n},(_,i)=>{
      const a=offset+i*Math.PI*2/n;
      return [Math.cos(a)*r,Math.sin(a)*r,Math.sqrt(1-r*r)];
    });
    const crystalMesh=(()=>{
      const edge=sphereRing(16,1,-Math.PI/2),middle=sphereRing(8,.72,-Math.PI/2+Math.PI/8),core=sphereRing(4,.29,-Math.PI/2+.5);
      // Stagger the interior planes while keeping a clean, spherical outline.
      middle.forEach((v,i)=>{const r=.69+Math.sin(i*2.7)*.045,a=Math.atan2(v[1],v[0]);v[0]=Math.cos(a)*r;v[1]=Math.sin(a)*r;v[2]=Math.sqrt(1-r*r);});
      const faces=[];
      function face(a,b,d){
        const u=b.map((n,i)=>n-a[i]),v=d.map((n,i)=>n-a[i]);
        let normal=unit([u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]]);
        if(!normal.every(Number.isFinite)||normal[2]<=1e-8)throw new Error('Invalid crystal face winding');
        // Inverse-transpose correction for the slightly taller displayed sphere.
        const shadingNormal=unit([normal[0],normal[1]/1.045,normal[2]]);
        faces.push({points:[a,b,d],normal,shadingNormal,center:a.map((n,i)=>(n+b[i]+d[i])/3)});
      }
      function join(outer,inner){
        inner.forEach((m,i)=>{const a=outer[2*i],b=outer[(2*i+1)%outer.length],d=outer[(2*i+2)%outer.length],next=inner[(i+1)%inner.length];face(a,b,m);face(b,d,m);face(d,next,m);});
      }
      join(edge,middle);join(middle,core);face(core[0],core[1],core[2]);face(core[0],core[2],core[3]);
      return {faces,edge};
    })();
    let crystalLight=unit([-.65,-.85,.95]),pointerLight=null,inspectCrystal=false;
    const lightChoices={'upper-left':[-.65,-.85,.95],'upper-right':[.85,-.5,.95],front:[0,-.12,1.4]};
    function crystalColor(face,wet,power){
      // Interior pigment and Soul emission belong behind the transparent shell.
      const glowAtBase=wet?Math.pow(Math.max(0,face.center[1]),.75):0;
      const pigment=wet?[9,1,23]:[6,3,15];
      return `rgb(${pigment.map((v,i)=>Math.round(clamp(v+glowAtBase*[30,1,67][i]+(wet?power*[1,1,4][i]:0),0,255))).join(',')})`;
    }
    function drawCrystalLighting(){
      // One front-glass pass spans the entire facet, regardless of the liquid level.
      // Add light without painting opaque triangles over the contents.
      const half=unit([crystalLight[0],crystalLight[1],crystalLight[2]*.78]);
      c.save();c.globalCompositeOperation='lighter';
      for(const face of crystalMesh.faces){
        const diffuse=Math.pow(Math.max(0,dot(face.shadingNormal,crystalLight)),1.45);
        const spec=Math.pow(Math.max(0,dot(face.shadingNormal,half)),38);
        const edge=Math.pow(1-face.shadingNormal[2],2);
        const light=[31,10,58].map((v,i)=>Math.round(diffuse*v+spec*[99,48,142][i]+edge*[11,8,20][i]));
        // No stroke: adjacent additive faces must not brighten their shared seams twice.
        path(face.points,`rgb(${light.join(',')})`);
      }
      c.restore();
    }
    function crystalPath(points){c.beginPath();points.forEach((p,i)=>i?c.lineTo(p[0],p[1]):c.moveTo(p[0],p[1]));c.closePath();}
    function liquidSurfacePoint(x,amount,side=1){
      const surface=1-2*amount,span=Math.sqrt(Math.max(0,1-surface*surface));
      // A shallow projected disc contracts naturally at the sphere's poles.
      const depth=.10*Math.sqrt(Math.max(0,span*span-x*x))*Math.min(1,amount*12,(1-amount)*12);
      return [x,surface+soul.surfaceOffset(x,amount)+side*depth];
    }
    function liquidContour(surface){
      const amount=(1-surface)/2,points=[[-1.06,1.6]];
      for(let i=0;i<=28;i++){
        const x=-1.06+i*2.12/28;
        points.push(liquidSurfacePoint(x,amount));
      }
      points.push([1.06,1.6]);return points;
    }
    function drawLiquidSurface(amount){
      if(amount<=0||amount>=1)return;
      const surface=1-2*amount,span=Math.sqrt(Math.max(0,1-surface*surface));
      const front=[],back=[];
      for(let i=0;i<=12;i++){
        const x=-span+2*span*i/12;
        front.push(liquidSurfacePoint(x,amount));back.push(liquidSurfacePoint(x,amount,-1));
      }
      c.save();
      // Broad, quiet reflections keep the top liquid-like while the orb stays faceted.
      c.save();crystalPath(back.concat([...front].reverse()));c.clip();
      const shade=c.createLinearGradient(0,surface-.10*span,0,surface+.10*span);
      shade.addColorStop(0,'#120524');shade.addColorStop(.55,'#230c43');shade.addColorStop(1,'#351855');
      c.fillStyle=shade;c.fillRect(-1.1,-1.3,2.2,2.6);
      const reflectionAlpha=.045+Math.max(0,-crystalLight[1])*.05;
      path([back[0],back[5],front[4]],`rgba(161,109,213,${reflectionAlpha})`);
      path([back[5],back[9],front[10],front[4]],'rgba(35,8,64,.12)');
      path([back[9],front[12],front[10]],`rgba(161,109,213,${reflectionAlpha*.65})`);
      c.restore();
      // The far edge recedes; a thin luminous near lip catches the light.
      line(back,'rgba(69,32,109,.65)',.014);
      line(front,'rgba(20,3,49,.72)',.050);
      line(front,'rgba(108,40,181,.65)',.034);
      line(front,'#8254be',.015);
      const reflection=crystalLight[0]<0?front.slice(2,6):front.slice(7,11);
      line(reflection,'rgba(188,147,235,.52)',.010);
      c.restore();
    }
    function drawVessel(x,y,r,amount,power,eyes){
      c.save();c.translate(x,y);c.scale(r,r*1.045);
      const boundary=crystalMesh.edge;
      path(boundary,'#090812','#060509',.055);
      crystalPath(boundary);c.clip();
      const renderFaces=wet=>crystalMesh.faces.forEach(face=>{
        const color=crystalColor(face,wet,power);
        path(face.points,color,color,.009);
      });
      renderFaces(false);
      const surface=1-2*amount,water=liquidContour(surface);
      if(amount>0){
        c.save();crystalPath(water);c.clip();renderFaces(true);
        drawSoulInletLight(amount);
        drawSoulSpiral(amount);
        drawSoulSettling();
        c.restore();
        drawLiquidSurface(amount);
        if(eyes&&amount>.3){
          c.save();crystalPath(water);c.clip();c.globalAlpha=clamp((amount-.3)/.15,0,1);
          const eyeY=.28,brighten=amount>=1-1e-9?soul.settling().eyes:0;
          const eyeColor=`rgb(${248+Math.round(brighten*7)},${234+Math.round(brighten*21)},255)`;
          path([[-.77,eyeY-.22],[-.46,eyeY-.13],[-.14,eyeY+.015],[-.31,eyeY+.19],[-.57,eyeY+.12]],'#130826');
          path([[.77,eyeY-.22],[.46,eyeY-.13],[.14,eyeY+.015],[.31,eyeY+.19],[.57,eyeY+.12]],'#130826');
          const paintEyes=()=>{
            path([[-.71,eyeY-.12],[-.38,eyeY+.035],[-.20,eyeY+.047],[-.36,eyeY+.16],[-.54,eyeY+.09]],eyeColor);
            path([[.71,eyeY-.12],[.38,eyeY+.035],[.20,eyeY+.047],[.36,eyeY+.16],[.54,eyeY+.09]],eyeColor);
          };
          // The eyes remain visible in the Soul, but only completing a refill emits light.
          if(brighten>0)glow(paintEyes,brighten*(18+power*2),'#d3a8ff');
          else paintEyes();
          c.restore();
        }
      }
      // Draw the shell's lighting last, above the meniscus, Soul effects, and eyes.
      // The approved reference leaves the crystal free of inscriptions.
      drawCrystalLighting();
      c.restore();
    }
  const center=[155.5,163];
  function magicCircle(){
    const a=.19+.58*pose.light;
    const ring=poly(...center,126,24);
    glow(()=>{
      line([...ring,ring[0]],`rgba(191,130,252,${a})`,1.4);
      const inner=poly(...center,117,24);line([...inner,inner[0]],`rgba(173,103,237,${a*.65})`,.85);
      for(let i=0;i<24;i++){
        const v=ring[i],angle=i*Math.PI/12-Math.PI/2;
        if(i%3===0){path([[v[0],v[1]-4],[v[0]+4,v[1]],[v[0],v[1]+4],[v[0]-4,v[1]]],null,`rgba(218,170,255,${a})`,1.2);}
        else line([v,[v[0]-Math.cos(angle)*4,v[1]-Math.sin(angle)*4]],`rgba(194,140,239,${a*.8})`,.8);
      }
    },pose.light*5,'#9e46f1');
  }
  function carvedRunes(){
    // Engraved recess, lower cut edge, then a narrow luminous core in the cut.
    const marks=[[104,82,-.55],[204,86,.65],[230,121,1.08],[238,169,1.47],[212,221,2.3],[162,244,3.05],[110,231,3.6],[75,192,4.2]];
    const shapes=[[[0,-6],[0,6],[-4,1],[4,-2],[0,-6]], [[-4,-5],[0,5],[4,-5],[0,-1],[-4,-5]], [[0,-6],[0,6],[4,0],[0,-3],[-4,0]]];
    for(let i=0;i<marks.length;i++){
      const [x,y,r]=marks[i];c.save();c.translate(x,y);c.rotate(r);const p=shapes[i%3];
      line(p,'#121016',3.8);c.translate(.7,.8);line(p,'#817183',1.1);c.translate(-.7,-.8);
      line(p,'#392643',1.8);
      const a=.24+.69*pose.light;
      glow(()=>line(p,`rgba(216,149,255,${a})`,1.05),pose.light*3,'#ad58ed');
      c.restore();
    }
  }
  const wispSpecs=[
    {a:-2.95,length:86,side:-1,seed:.4,width:6},
    {a:-2.43,length:126,side:1,seed:2.1,width:8},
    {a:-1.95,length:144,side:-1,seed:4.5,width:9},
    {a:-1.43,length:149,side:1,seed:6.1,width:8},
    {a:-.92,length:126,side:-1,seed:8.2,width:7},
    {a:-.55,length:86,side:1,seed:3.1,width:6},
    {a:2.6,length:67,side:-1,seed:9.3,width:5}
  ];
  function wispPoints(spec,branch=0){
    const time=reduced?0:tick, a=spec.a;
    const origin=[center[0]+Math.cos(a)*100,center[1]+Math.sin(a)*100];
    // A moving hook-shaped path gives each Soul a hollow curl and tapered tail.
    const angle=a+spec.side*.32+Math.sin(time*.77+spec.seed)*.1;
    const direction=[Math.cos(angle),Math.sin(angle)-.4];
    const len=spec.length*(.22+pose.height*.83);
    const side=[-direction[1],direction[0]], points=[];
    for(let i=0;i<=44;i++){
      const u=i/44;
      const curl=Math.sin(u*4.8+time*1.1+spec.seed)*Math.sin(Math.PI*u)*len*.23;
      // The head loops in a small, asymmetric orbit instead of flickering vertically.
      const hook=Math.max(0,(u-.64)/.36),ha=hook*3.9+time*.9+spec.seed;
      const reach=u*len-(1-Math.cos(hook*3.3))*len*.13;
      const cross=curl+Math.sin(ha)*hook*len*.23*spec.side+Math.sin(u*9-time*1.8+branch)*branch*2.3;
      points.push([origin[0]+direction[0]*reach+side[0]*cross,
        origin[1]+direction[1]*reach+side[1]*cross]);
    }
    return points;
  }
  function ribbon(points,width,alpha,offset=0){
    const left=[],right=[];
    for(let i=0;i<points.length;i++){
      const p=points[i],prev=points[Math.max(0,i-1)],next=points[Math.min(points.length-1,i+1)];
      const d=Math.hypot(next[0]-prev[0],next[1]-prev[1])||1;
      const nx=-(next[1]-prev[1])/d,ny=(next[0]-prev[0])/d,u=i/(points.length-1);
      const taper=Math.pow(Math.sin(Math.PI*u),.7)*(1-.38*u);
      const torn=.72+.28*Math.sin(u*17+tick*1.7+offset);
      const w=width*taper*torn;
      left.push([p[0]+nx*(w+offset),p[1]+ny*(w+offset)]);
      right.push([p[0]+nx*(offset-w*.25),p[1]+ny*(offset-w*.25)]);
    }
    const g=c.createLinearGradient(points[0][0],points[0][1],points.at(-1)[0],points.at(-1)[1]);
    g.addColorStop(0,`rgba(76,8,156,${alpha*.03})`);
    g.addColorStop(.4,`rgba(132,32,242,${alpha*.45})`);
    g.addColorStop(.85,`rgba(176,74,255,${alpha})`);
    g.addColorStop(1,`rgba(219,148,255,${alpha*.1})`);
    path([...left,...right.reverse()],g);
  }
  function soulAura(){
    if(pose.aura<.001)return;
    c.save();
    // A soft compositional boundary keeps the health icons clear without clipping curls.
    const motion=reduced?0:tick;
    for(let i=0;i<wispSpecs.length;i++){
      const spec=wispSpecs[i];
      const points=wispPoints(spec),opacity=pose.aura*(.82+.18*Math.sin(motion*.8+spec.seed));
      const fade=1-pose.fray;
      const headIndex=35+Math.round(Math.sin(motion*1.15+spec.seed)*3),head=points[headIndex];
      const glowSize=(13+pose.height*9)*fade;
      c.globalCompositeOperation='lighter';
      if(glowSize>.01){
        const halo=c.createRadialGradient(...head,0,...head,glowSize);
        halo.addColorStop(0,`rgba(161,34,255,${opacity*.38})`);halo.addColorStop(1,'rgba(95,9,215,0)');
        c.fillStyle=halo;c.fillRect(head[0]-glowSize,head[1]-glowSize,glowSize*2,glowSize*2);
      }
      ribbon(points,spec.width*(1+pose.height*.75),opacity*.54,0);
      ribbon(wispPoints(spec,1),spec.width*.3,opacity*.55,3+pose.fray*8);
      ribbon(wispPoints(spec,2),spec.width*.13,opacity*.65,-4-pose.fray*10);
      const tail=points.slice(Math.round(pose.fray*25),headIndex+1);
      line(tail,`rgba(173,75,249,${opacity*.4})`,1.1+pose.height*.6);
      // Comet core with a pointed sweep; no face or literal fire tongue.
      if(fade>.01){
        const ahead=points[headIndex+1],rotation=Math.atan2(ahead[1]-head[1],ahead[0]-head[0]);
        c.save();c.translate(...head);c.rotate(rotation);c.scale(fade,fade);
        c.beginPath();c.moveTo(-13,0);c.bezierCurveTo(-5,-2.6,-3,-5.8,2,-4.2);
        c.bezierCurveTo(8,-2.5,7,3.8,2,4.4);c.bezierCurveTo(-3,5,-5,1.3,-13,0);
        c.fillStyle=`rgba(188,103,255,${opacity*.78})`;c.shadowBlur=6*renderScaleX;c.shadowColor='#b63eff';c.fill();c.shadowBlur=0;
        c.beginPath();c.ellipse(1,0,3,1.45,-.3,0,Math.PI*2);c.fillStyle=`rgba(244,213,255,${opacity*.87})`;c.fill();c.restore();
      }
      for(let j=0;j<3;j++){
        const u=((motion*.14+spec.seed*.17+j/3)%1),p=points[Math.min(43,Math.floor(u*44))];
        const alpha=opacity*.4*Math.sin(u*Math.PI);
        path([[p[0]-3-j,p[1]-5-j*2],[p[0]-1-j,p[1]-9-j*2],[p[0]+1-j,p[1]-6-j*2]],`rgba(173,74,240,${alpha})`);
      }
    }
    c.restore();
  }
  function refillFlow(){
    if(!pose.refilling)return;
    const amount=reduced?.25:.55;
    const points=[];
    for(let i=0;i<=24;i++){
      const angle=2.48-i/24*.91;
      points.push([center[0]+Math.cos(angle)*88,center[1]+Math.sin(angle)*88]);
    }
    glow(()=>line(points,`rgba(154,76,221,${amount})`,1),4,'#9b48ef');
    if(!reduced){
      for(let j=0;j<3;j++){
        const p=((tick*.7+j/3)%1)*24,k=Math.floor(p),mix=p-k;
        const a=points[k],b=points[Math.min(k+1,24)];
        glow(()=>circle(a[0]+(b[0]-a[0])*mix,a[1]+(b[1]-a[1])*mix,1.8,'#d3a3ff'),4,'#bb71ff');
      }
    }
  }
  function assembly(){
    soulAura();magicCircle();
    drawVessel(...center,77,pose.fill,1,true);
    c.drawImage(referenceFrame,0,0,530,referenceFrame.naturalHeight*530/referenceFrame.naturalWidth);
    drawVessel(...center,73,pose.fill,1,true);
    carvedRunes();
    for(let i=0;i<3;i++){c.save();c.translate(294+i*63,150);c.scale(1.63,1.63);heart(0,0,4,0);c.restore();}
    const reserves=[[69,228],[105,263],[152,280],[203,267],[246,236]];
    reserves.forEach(([x,y],i)=>drawReferenceReserve(x,y,i===0?pose.reserve:0,i));
    refillFlow();
  }
  return function render(next,{small=false,reducedMotion=false}={}){
    pose=next;tick=next.t;reduced=reducedMotion;
    if(reduced){pose={...next,height:.22,fray:0,aura:Math.min(next.aura,.48),light:next.full?.27:0,eye:0};tick=0;}
    const width=canvas.clientWidth,dpr=Math.min(devicePixelRatio||1,3),height=small?234:width*.69;
    if(canvas.width!==Math.round(width*dpr)||canvas.height!==Math.round(height*dpr)){
      canvas.width=Math.round(width*dpr);canvas.height=Math.round(height*dpr);canvas.style.height=height+'px';
    }
    c.setTransform(dpr,0,0,dpr,0,0);c.clearRect(0,0,width,height);
    const scale=small?Math.min(.49,(width-32)/560):width/660;
    renderScaleX=scale*dpr;c.translate(small?Math.max(14,(width-280)/2):width*.06,small?68:height*.2);c.scale(scale,scale);
    assembly();
  };
}
