'use strict';
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const {spawn} = require('node:child_process');
const {chromium} = require('playwright');
const root = path.resolve(__dirname,'..');
const catalog = JSON.parse(fs.readFileSync(path.join(root,'docs/tracker/catalog.json'),'utf8'));
let server, browser;
const groups = [];
async function group(name, test) { await test(); groups.push(name); console.log('PASS '+name); }
(async () => {
  try {
    server = spawn('python3',['-u','-c',"import sys;sys.path.insert(0,'tools');from prepare_art_thumbnails import CaptureHandler;from http.server import ThreadingHTTPServer;from pathlib import Path;s=ThreadingHTTPServer(('127.0.0.1',0),CaptureHandler);s.root=Path.cwd();print(s.server_port);s.serve_forever()"],{cwd:root,stdio:['ignore','pipe','pipe']});
    const port = await new Promise((resolve,reject) => { const timeout=setTimeout(()=>reject(Error('Capture server did not start')),10000); server.stdout.once('data',data=>{clearTimeout(timeout);resolve(Number(String(data).trim()));});server.once('exit',()=>reject(Error('Capture server exited'))); });
    const base = `http://127.0.0.1:${port}`;
    browser = await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox','--enable-unsafe-swiftshader','--use-gl=angle','--use-angle=swiftshader','--disable-accelerated-video-decode']});
    const page = await browser.newPage({viewport:{width:384,height:256},deviceScaleFactor:1});
    await page.goto(base+'/docs/tracker/thumbnail-render.html');
    await page.waitForFunction(()=>!!window.ThumbnailRenderer);
    const snapshots=[];
    await group('exact native clip zero and distinct selection share one model load',async()=>{
      const asset=catalog.art.find(entry=>entry.preview?.status==='ready'&&entry.path.endsWith('.glb')&&entry.path.toLowerCase().includes('ual1'));
      assert.ok(asset,'Native UAL1 source exists');
      const requests=[];page.on('request',request=>{if(request.url().endsWith('.glb'))requests.push(request.url());});
      await page.evaluate(descriptor=>ThumbnailRenderer.load(descriptor),asset.preview);
      for(const clip of asset.preview.clips.slice(0,2)){
        const result=await page.evaluate(clip=>ThumbnailRenderer.model(clip),clip);
        assert.equal(result.time,0);assert.equal(result.clip,clip.export_name||clip.name||'animation_'+clip.index);
        assert.deepEqual(result.root_before,result.root_after);snapshots.push(result);
      }
      assert.equal(requests.length,1);
    });
    await group('converted crawling first pose uses finite skinned bounds',async()=>{
      const asset=catalog.art.find(entry=>entry.path==='assets/animations/Mixamo/anim_mixamo_crawling_v01.fbx');
      assert.equal(asset?.preview.status,'ready');
      await page.evaluate(descriptor=>ThumbnailRenderer.load(descriptor),asset.preview);
      const result=await page.evaluate(clip=>ThumbnailRenderer.model(clip),asset.preview.clips[0]);
      assert.equal(result.time,0);assert.deepEqual(result.root_before,result.root_after);
      assert.ok([...result.bounds.min,...result.bounds.max].every(Number.isFinite));
      assert.ok(result.bounds.max.some((value,index)=>value>result.bounds.min[index]));
      snapshots.push(result);
    });
    await group('snapshot PNG dimensions are exactly 384 by 256',async()=>{
      for(const result of snapshots){const png=Buffer.from(result.png.split(',')[1],'base64');assert.equal(png.readUInt32BE(16),384);assert.equal(png.readUInt32BE(20),256);assert.ok(png.length>2000);}
      for(const result of snapshots){
        const clearBorder=await page.evaluate(async png=>{const image=new Image();image.src=png;await image.decode();const c=document.createElement('canvas');c.width=384;c.height=256;const x=c.getContext('2d');x.drawImage(image,0,0);const p=x.getImageData(0,0,384,256).data;const background=[...p.slice(0,4)];for(let y=0;y<256;y++)for(let xx=0;xx<384;xx++)if(y<3||y>=253||xx<3||xx>=381)for(let k=0;k<4;k++)if(p[(y*384+xx)*4+k]!==background[k])return false;return true;},result.png);
        assert.equal(clearBorder,true,'Posed geometry must fit inside the thumbnail with a visible margin');
      }
      const destination=path.join(root,'.artifacts/tracker/thumbnail-first-frame.png');fs.mkdirSync(path.dirname(destination),{recursive:true});fs.writeFileSync(destination,Buffer.from(snapshots.at(-1).png.split(',')[1],'base64'));
    });
    await group('transparent UI frame stays transparent and is labeled empty',async()=>{
      const transparent=await page.evaluate(()=>{const c=document.createElement('canvas');c.width=8;c.height=8;return c.toDataURL('image/png').split(',')[1];});
      await page.route('**/test-transparent-frame.png',route=>route.fulfill({contentType:'image/png',body:Buffer.from(transparent,'base64')}));
      const result=await page.evaluate(()=>ThumbnailRenderer.media({descriptor:{kind:'sequence'},image:'/test-transparent-frame.png'}));
      assert.equal(result.empty,true);assert.equal(result.time,0);
      const alpha=await page.evaluate(async png=>{const image=new Image();image.src=png;await image.decode();const c=document.createElement('canvas');c.width=384;c.height=256;const x=c.getContext('2d');x.drawImage(image,0,0);return x.getImageData(100,100,1,1).data[3];},result.png);
      assert.equal(alpha,0);
    });
    await group('existing video uses decoded zero without playback',async()=>{
      const entry=catalog.art.find(e=>e.preview?.kind==='video'&&e.preview.status==='ready');assert.ok(entry);
      const result=await page.evaluate(descriptor=>ThumbnailRenderer.media({descriptor}),entry.preview);
      assert.equal(result.time,0);assert.ok(result.source_width>0);assert.ok(result.png.startsWith('data:image/png;base64,'));
    });
    await group('capture service rejects tracking reads and writes',async()=>{
      const response=await page.request.get(base+'/api/tracker');assert.equal(response.status(),404);
      const write=await page.request.put(base+'/api/tracker',{data:{}});assert.equal(write.status(),405);
    });
    console.log(`${groups.length} thumbnail browser groups passed.`);
  } finally {await browser?.close();server?.kill('SIGTERM');}
})().catch(error=>{console.error(error);process.exitCode=1;});
