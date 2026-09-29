(function(){
  const root=document.getElementById('soul-wisps-motion-reference');
  const {sample,scenarios,timing}=SoulWispReference;
  const close=root.querySelector('[data-close]'),small=root.querySelector('[data-small]');
  const seek=root.querySelector('input[type=range]'),clock=root.querySelector('[data-clock]');
  const phase=root.querySelector('[data-phase]'),resource=root.querySelector('[data-resource]');
  const play=root.querySelector('[data-play]'),sequence=root.querySelector('[data-sequence]');
  const reduced=root.querySelector('[data-reduced]');
  const preference=matchMedia('(prefers-reduced-motion: reduce)');
  reduced.checked=preference.matches;
  const frame=new Image();
  frame.src='EMBED_FRAME';
  let t=0,kind='empty',playing=!preference.matches,last=0,visible=true,loaded=false;
  const drawClose=createSoulWispDrawing(close,frame),drawSmall=createSoulWispDrawing(small,frame);
  function render(){
    if(!loaded)return;
    const s=sample(t,kind),opts={reducedMotion:reduced.checked};
    drawClose(s,opts);drawSmall(s,{...opts,small:true});
    if(phase.textContent!==s.phase)phase.textContent=s.phase;
    resource.textContent=`${Math.round(s.actual*300)} / 300 Soul`;
    play.textContent=playing?'Pause':t>=scenarios[kind].duration?'Replay':'Play';
    seek.value=t;seek.setAttribute('aria-valuetext',`${t.toFixed(2)} seconds, ${s.phase}`);
    clock.textContent=t.toFixed(2)+' s';
  }
  function setTime(value){t=Math.max(0,Math.min(scenarios[kind].duration,value));last=0;render();}
  function replay(){t=0;playing=true;last=0;render();}
  play.addEventListener('click',()=>{if(t>=scenarios[kind].duration)replay();else{playing=!playing;last=0;render();}});
  root.querySelector('[data-replay]').addEventListener('click',replay);
  seek.addEventListener('input',()=>{playing=false;setTime(Number(seek.value));});
  sequence.addEventListener('change',()=>{kind=sequence.value;seek.max=scenarios[kind].duration;replay();});
  reduced.addEventListener('change',render);
  const resize=new ResizeObserver(render);resize.observe(close);resize.observe(small);
  const visibility=new IntersectionObserver(entries=>{visible=entries[0].isIntersecting;last=0;});visibility.observe(root);
  const onHidden=()=>{last=0;};document.addEventListener('visibilitychange',onHidden);
  function animation(now){
    if(!root.isConnected){resize.disconnect();visibility.disconnect();document.removeEventListener('visibilitychange',onHidden);return;}
    if(loaded&&playing&&visible&&!document.hidden){
      if(last)t=Math.min(scenarios[kind].duration,t+Math.min((now-last)/1000,.06));
      if(t>=scenarios[kind].duration)playing=false;
      render();last=now;
    }else last=0;
    requestAnimationFrame(animation);
  }
  frame.onload=()=>{loaded=true;render();};
  frame.onerror=()=>{phase.textContent='Frame artwork could not load';phase.setAttribute('role','alert');};
  requestAnimationFrame(animation);
  root.motionReference={sample,timing,scenarios,frame,setTime,pause(){playing=false;last=0;render();},
    getState(){return {t,kind,playing,visible,loaded,...sample(t,kind)};}};
})();
