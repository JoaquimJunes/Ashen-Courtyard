const fs=require('node:fs/promises'),path=require('node:path'),http=require('node:http'),assert=require('node:assert/strict');
const {chromium}=require('playwright');
const root=path.resolve(__dirname,'..');
(async()=>{
  const server=http.createServer(async(req,res)=>{
    const pathname=new URL(req.url,'http://localhost').pathname;
    if(pathname==='/'){
      res.setHeader('Content-Type','text/html');res.end('<style>body{margin:0;background:#0c0e15}</style><video id="v" width="1280" height="720" src="/video.webm" muted></video><canvas id="c" width="1280" height="720" hidden></canvas>');
    }else if(pathname==='/video.webm'){
      const data=await fs.readFile(path.join(root,'soul-wisps-painted.webm'));
      res.setHeader('Content-Type','video/webm');res.setHeader('Accept-Ranges','bytes');
      if(req.headers.range){const match=/bytes=(\d+)-(\d*)/.exec(req.headers.range),start=Number(match[1]),end=match[2]?Number(match[2]):data.length-1;res.writeHead(206,{'Content-Range':`bytes ${start}-${end}/${data.length}`,'Content-Length':end-start+1});res.end(data.subarray(start,end+1));}
      else{res.setHeader('Content-Length',data.length);res.end(data);}
    }else{res.writeHead(404);res.end();}
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',args:['--no-sandbox']});
  try{
    const page=await browser.newPage({viewport:{width:1280,height:720}});await page.goto(`http://127.0.0.1:${server.address().port}`);
    await page.waitForFunction(()=>v.readyState>=2);
    const meta=await page.evaluate(()=>({duration:v.duration,width:v.videoWidth,height:v.videoHeight,error:v.error?.message||null}));
    assert.equal(meta.duration,10);assert.equal(meta.width,1280);assert.equal(meta.height,720);assert.equal(meta.error,null);
    const seeks=[];
    for(const [name,t] of [['burst',2.95],['settled',5.4],['below-full',9.2]]){
      await page.evaluate(time=>new Promise(resolve=>{v.onseeked=()=>resolve();v.currentTime=time;}),t);
      await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
      const snapshot=await page.evaluate(()=>{const ctx=c.getContext('2d');ctx.drawImage(v,0,0);return {png:c.toDataURL('image/png'),time:v.currentTime,quality:v.getVideoPlaybackQuality()};});
      assert.ok(Math.abs(snapshot.time-t)<.02);seeks.push({time:snapshot.time,quality:snapshot.quality});
      await fs.writeFile(path.join(root,'validation',`decoded-${name}.png`),Buffer.from(snapshot.png.split(',')[1],'base64'));
    }
    await page.evaluate(()=>{v.currentTime=0;return v.play();});await page.waitForTimeout(400);
    const advanced=await page.evaluate(()=>v.currentTime);assert.ok(advanced>0,'Video playback failed');await page.evaluate(()=>v.pause());
    const result={...meta,playbackAdvances:true,seekChecks:seeks};
    await fs.writeFile(path.join(root,'validation/playback.json'),JSON.stringify(result,null,2));console.log(result);
  }finally{await browser.close();server.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
