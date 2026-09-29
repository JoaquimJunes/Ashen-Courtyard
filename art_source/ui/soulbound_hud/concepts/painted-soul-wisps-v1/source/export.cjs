const fs=require('node:fs/promises'),path=require('node:path'),assert=require('node:assert/strict');
const http=require('node:http');
const {chromium}=require('playwright');
const {mux}=require('./webm.cjs');
const root=path.resolve(__dirname,'..');
const writePNG=(filename,uri)=>fs.writeFile(filename,Buffer.from(uri.split(',')[1],'base64'));
(async()=>{
  const server=http.createServer(async(req,res)=>{
    const relative=decodeURIComponent(new URL(req.url,'http://localhost').pathname);
    const filename=path.resolve(root,'.'+relative);
    if(!filename.startsWith(root+path.sep)){res.writeHead(403);res.end();return;}
    try{res.setHeader('Content-Type',filename.endsWith('.js')?'text/javascript':filename.endsWith('.png')?'image/png':'text/html');res.end(await fs.readFile(filename));}catch{res.writeHead(404);res.end();}
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',args:['--no-sandbox','--enable-unsafe-swiftshader']});
  try{
    const page=await browser.newPage({viewport:{width:1280,height:720},deviceScaleFactor:1}),errors=[];
    page.on('pageerror',e=>errors.push(e.message));
    await page.goto(`http://127.0.0.1:${server.address().port}/source/render.html`);await page.evaluate(()=>window.ready);
    const layers=await page.evaluate(()=>window.exportLayers());
    for(const [name,uri] of Object.entries(layers))await writePNG(path.join(root,'assets',name+'-layer.png'),uri);
    const times={empty:0,refill:1.9,burst:2.94,gather:3.35,settled:5.4,linger:7.4,dissolve:8.4,'below-full':9.2};
    const poses=[];
    for(const [name,time] of Object.entries(times)){
      const out=await page.evaluate(t=>{const state=render(t,{background:true});return {state,png:canvas.toDataURL('image/png')};},time);
      poses.push(out.state);await writePNG(path.join(root,'validation',`${name}-dark.png`),out.png);
    }
    await writePNG(path.join(root,'validation/gameplay-size.png'),await page.evaluate(()=>{render(2.94,{background:true,scale:.38});return canvas.toDataURL('image/png');}));
    await writePNG(path.join(root,'validation/alpha-light-background.png'),await page.evaluate(()=>{render(2.94);c.save();c.globalCompositeOperation='destination-over';c.fillStyle='#e4e0db';c.fillRect(0,0,1280,720);c.restore();return canvas.toDataURL('image/png');}));
    await fs.writeFile(path.join(root,'validation/keyframes.json'),JSON.stringify(poses,null,2));
    if(process.argv.includes('--stills')){assert.deepEqual(errors,[]);console.log('Painted layers and eight key poses rendered.');return;}
    await page.exposeFunction('saveFrame',async(i,uri)=>writePNG(path.join(root,'frames',`soul-${String(i).padStart(4,'0')}.png`),uri));
    await page.exposeFunction('progress',n=>console.log(`Rendered ${n}/600 transparent frames`));
    const encoded=await page.evaluate(async()=>{
      const config={codec:'vp09.00.31.08',width:1280,height:720,bitrate:16000000,framerate:60,latencyMode:'quality',hardwareAcceleration:'prefer-software'};
      if(!(await VideoEncoder.isConfigSupported(config)).supported)throw Error('VP9 encoding configuration unsupported');
      const chunks=[];let encodingError=null;
      const encoder=new VideoEncoder({output(chunk){const d=new Uint8Array(chunk.byteLength);chunk.copyTo(d);chunks.push({timestamp:chunk.timestamp,type:chunk.type,data:d});},error(e){encodingError=e;}});
      encoder.configure(config);
      for(let i=0;i<600;i++){
        const t=i/60;render(t);await saveFrame(i,canvas.toDataURL('image/png'));
        // Composite charcoal behind the exact transparent frame used for delivery.
        c.save();c.globalCompositeOperation='destination-over';c.fillStyle='#0c0e15';c.fillRect(0,0,1280,720);c.restore();
        const frame=new VideoFrame(canvas,{timestamp:Math.round(i*1e6/60),duration:Math.round((i+1)*1e6/60)-Math.round(i*1e6/60)});
        encoder.encode(frame,{keyFrame:i%60===0});frame.close();
        if(i%30===29)await encoder.flush();
        if(encodingError)throw encodingError;
        if(i%60===59)await progress(i+1);
      }
      await encoder.flush();encoder.close();
      function base64(bytes){let s='';for(let i=0;i<bytes.length;i+=0x4000)s+=String.fromCharCode(...bytes.subarray(i,i+0x4000));return btoa(s);}
      return chunks.map(k=>({...k,data:base64(k.data)}));
    });
    const frames=encoded.map(k=>({...k,data:Buffer.from(k.data,'base64')}));
    const webm=mux(frames);await fs.writeFile(path.join(root,'soul-wisps-painted.webm'),webm);
    await fs.writeFile(path.join(root,'validation/encoding.json'),JSON.stringify({width:1280,height:720,fps:60,duration:10,codec:'VP9',frames:frames.length,audioTracks:0,bytes:webm.length,firstTimestamp:frames[0].timestamp,lastTimestamp:frames.at(-1).timestamp,browserErrors:errors},null,2));
    assert.deepEqual(errors,[]);console.log(`Saved video: ${webm.length} bytes; ${frames.length} encoded frames.`);
  }finally{await browser.close();server.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
