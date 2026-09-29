// One browser and one model load per source. Outputs go to an unpublished staging directory.
'use strict';
const fs = require('node:fs'), path = require('node:path');
const {chromium} = require('playwright');
async function capture({jobs, url, output, executable}) {
  const browser = await chromium.launch({executablePath:executable || '/usr/bin/chromium', headless:true,
    args:['--no-sandbox','--enable-unsafe-swiftshader','--use-gl=angle','--use-angle=swiftshader','--disable-accelerated-video-decode']});
  const results = [];
  try {
    const page = await browser.newPage({viewport:{width:384,height:256},deviceScaleFactor:1});
    // No external connections or tracker writes are needed to produce thumbnails.
    await page.route('**/*', route => {
      const request = route.request();
      if (new URL(request.url()).origin !== new URL(url).origin || !['GET','HEAD'].includes(request.method())) return route.abort();
      return route.continue();
    });
    await page.goto(url); await page.waitForFunction(() => !!window.ThumbnailRenderer);
    let loadedModel = null;
    for (const job of jobs) {
      try {
        if (job.descriptor.kind === 'model' && loadedModel !== job.descriptor.url) {
          await page.evaluate(descriptor => ThumbnailRenderer.load(descriptor), job.descriptor);
          loadedModel = job.descriptor.url;
        }
        const frame = await page.evaluate(job => job.descriptor.kind === 'model' ? ThumbnailRenderer.model(job.clip) : ThumbnailRenderer.media(job), job);
        if (job.descriptor.kind !== 'model') loadedModel = null;
        if (frame.time !== 0 || (frame.root_before && JSON.stringify(frame.root_before) !== JSON.stringify(frame.root_after))) throw Error('Capture changed the first-frame pose or root.');
        const png = Buffer.from(frame.png.replace(/^data:image\/png;base64,/, ''), 'base64');
        const filename = path.basename(job.output); fs.writeFileSync(path.join(output, filename), png);
        delete frame.png; results.push({id:job.id,status:'ready',filename,...frame});
      } catch (error) {
        loadedModel = null; await page.evaluate(() => ThumbnailRenderer.dispose()).catch(() => {});
        results.push({id:job.id,status:'error',reason:String(error.message).slice(0,1200)});
      }
      if (results.length % 25 === 0) console.log(`Captured ${results.length}/${jobs.length} thumbnails`);
    }
  } finally { await browser.close(); }
  return results;
}
module.exports = {capture};
if (require.main === module) {
  const [jobPath, resultPath] = process.argv.slice(2);
  capture(JSON.parse(fs.readFileSync(jobPath,'utf8'))).then(results => fs.writeFileSync(resultPath,JSON.stringify(results)), error => { console.error(error); process.exitCode=1; });
}
