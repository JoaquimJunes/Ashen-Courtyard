// Directed motion reference only. This is not the gameplay/resource controller.
(function(scope){
  const timing=Object.freeze({burst:.45,gather:.75,settle:.9,linger:1.5,fade:.6});
  const clamp=(n,a=0,b=1)=>Math.max(a,Math.min(b,n));
  const smooth=n=>{n=clamp(n);return n*n*(3-2*n);};
  const lerp=(a,b,n)=>a+(b-a)*n;
  const scenarios=Object.freeze({
    empty:{label:'Empty → full → spend',duration:11.3,full:3.15,cast:7.3},
    ordinary:{label:'Ordinary refill',duration:5.4,full:1.1,cast:Infinity},
    recover:{label:'Recover during linger',duration:6.2,full:2.4,cast:1}
  });
  function sample(time,kind='empty'){
    const scene=scenarios[kind]||scenarios.empty,t=clamp(time,0,scene.duration);
    const s={t,phase:'Empty',fill:0,actual:0,reserve:1,aura:0,height:0,light:0,fray:0,eye:0,refilling:false,burst:false,dropAge:99};
    let afterFull=t-scene.full;
    if(kind==='empty'){
      s.fill=s.actual=clamp((t-1.15)/2);s.reserve=1-s.actual;
      s.phase=t<.65?'Empty':t<1.15?'Refill cooldown':'Refill';
      s.refilling=t>=1.15&&t<scene.full;
      if(t>=scene.full){
        s.fill=s.actual=1;s.reserve=0;
        if(afterFull<timing.burst){
          const k=smooth(afterFull/timing.burst);
          Object.assign(s,{phase:'Burst',burst:true,aura:k,height:lerp(.2,1,k),light:k});
        }else if(afterFull<timing.burst+timing.gather){
          const k=smooth((afterFull-timing.burst)/timing.gather);
          Object.assign(s,{phase:'Gather',aura:lerp(1,.7,k),height:lerp(1,.45,k),light:lerp(1,.55,k)});
        }else if(afterFull<timing.burst+timing.gather+timing.settle){
          const k=smooth((afterFull-timing.burst-timing.gather)/timing.settle);
          Object.assign(s,{phase:'Settle',aura:lerp(.7,.48,k),height:lerp(.45,.23,k),light:lerp(.55,.27,k)});
        }else Object.assign(s,{phase:'Settled',aura:.48,height:.23,light:.27});
      }
      if(t>=scene.cast){
        const age=t-scene.cast;s.actual=.7;s.fill=lerp(1,.7,smooth(age/.3));s.dropAge=age;
        const f=smooth((age-timing.linger)/timing.fade);
        Object.assign(s,{phase:age<timing.linger?'Spend / linger':age<timing.linger+timing.fade?'Dissolve':'Below full',
          aura:.48*(1-f),height:.23+.25*f,light:0,fray:f});
      }
    }else if(kind==='ordinary'){
      s.fill=s.actual=.7+clamp((t-.5)/2,0,.3);s.reserve=1-s.actual;
      s.phase=t<.5?'Refill cooldown':'Refill';s.refilling=t>=.5&&t<scene.full;
      if(t>=scene.full){
        s.fill=s.actual=1;s.reserve=0;
        const k=smooth(afterFull/timing.settle);
        Object.assign(s,{phase:afterFull<timing.settle?'Soft settle':'Settled',aura:lerp(0,.48,k),height:lerp(.36,.23,k),light:.27*k});
      }
    }else{
      Object.assign(s,{phase:'Settled',fill:1,actual:1,reserve:.3,aura:.48,height:.23,light:.27});
      if(t>=scene.cast&&t<scene.full){
        const age=t-scene.cast,received=clamp((age-.8)/2,0,.3);
        s.actual=.7+received;s.fill=age<.3?lerp(1,.7,smooth(age/.3)):s.actual;
        s.reserve=.3-received;s.phase=age<.8?'Spend / linger':'Refill / linger';s.refilling=age>=.8;s.light=0;s.dropAge=age;
      }
      if(t>=scene.full){
        s.fill=s.actual=1;s.reserve=0;
        const k=smooth(afterFull/timing.settle);
        Object.assign(s,{phase:afterFull<timing.settle?'Soft settle':'Settled',aura:.48+.1*Math.sin(k*Math.PI),height:.23+.1*Math.sin(k*Math.PI),light:.27*k});
      }
    }
    // Only a refill-completion cue; independent of the longer aura sequence.
    if(t>=scene.full&&afterFull<.4&&s.actual>=1)s.eye=Math.sin(Math.PI*clamp(afterFull/.4));
    s.full=s.actual>=1-1e-9&&s.fill>=1-1e-9;
    return s;
  }
  scope.SoulWispReference={timing,scenarios,sample,smooth};
})(typeof module!=='undefined'?module.exports:globalThis);
