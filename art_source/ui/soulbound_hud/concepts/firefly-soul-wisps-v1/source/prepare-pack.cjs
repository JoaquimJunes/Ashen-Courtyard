// Packaging only: ImageGen supplies the painted artwork. This script normalizes
// the canvas, copies a fixed approved HUD crop, and builds static review sheets.
const fs = require('node:fs');
const path = require('node:path');
const {execFileSync} = require('node:child_process');
const root = path.resolve(__dirname, '..');
const magick = (...args) => execFileSync('magick', args, {stdio:'inherit'});
const at = name => path.join(root,name);
const ids = ['02-burst','03-gather','04-settled-a','05-settled-b'];
magick(at('source/hud-holdout.svg'),'-alpha','off','-colorspace','Gray','-depth','8',at('source/hud-holdout.png'));
magick(at('source/hud-holdout.png'),'-alpha','off','-channel','RGB','-negate','+channel','-depth','8',at('source/wisp-visible-mask.png'));
magick('-size','1280x720','xc:black','-type','TrueColor','PNG24:'+at('images/01-empty.png'));
for (const id of ids) {
  // Identical transform for every pose; no auto-trim or subject recentering.
  magick(at('source/'+id+'-generated.png'),'-background','black','-alpha','remove',
    '-alpha','off','-filter','Lanczos','-resize','1152x648!',
    '-gravity','center','-extent','1280x720','+repage',
    '-type','TrueColor','PNG24:'+at('images/'+id+'.png'));
}
// A/B are idle poses: equalize energy so interpolation does not add a glow pulse.
const energy = id => {
  const file = at('source/'+id+'.mean');
  magick(at('images/'+id+'.png'),'-format','%[fx:mean]','info:'+file);
  const value = Number(fs.readFileSync(file,'utf8')); fs.unlinkSync(file); return value;
};
const gain = energy('04-settled-a') / energy('05-settled-b');
magick(at('images/05-settled-b.png'),'-evaluate','Multiply',String(gain),at('images/05-settled-b.png'));
// Unaltered geometry and artwork from panel 08 of the approved storyboard.
// This fixed below-full plate is only for alignment, not resource-state review.
magick(at('source/approved-keyframes.png'),'-crop','414x286+1258+520','+repage',
  '-filter','Lanczos','-resize','683x472!',at('source/fixed-hud-crop.png'));
magick('-size','1280x720','xc:#0b1015',at('source/fixed-hud-crop.png'),
  '-geometry','+216+176','-compose','over','-composite','+repage',at('review/fixed-hud-alignment-base.png'));
for (const id of ids) {
  // The precise stone-shaped mask belongs in compositing, not in Firefly's
  // upload frames: masking inputs would introduce artificial chopped tails.
  magick(at('images/'+id+'.png'),at('source/wisp-visible-mask.png'),
    '-geometry','+0+0','-compose','Multiply','-composite',at('review/'+id+'-occluded.png'));
  magick(at('review/fixed-hud-alignment-base.png'),at('review/'+id+'-occluded.png'),
    '-compose','screen','-composite','+repage',at('review/'+id+'-aligned.png'));
}
const headings = ['02 / BURST','03 / GATHER','04 / SETTLED A','05 / SETTLED B'];
for(let i=0;i<ids.length;i++) {
  magick(at('review/'+ids[i]+'-aligned.png'),'-resize','640x360!',
    '+repage','-background','#10131d','-gravity','south','-splice','0x44','+repage',
    '-font','DejaVu-Sans','-fill','#d8c6ff','-pointsize','20','-annotate','+0+12',headings[i],
    at('review/tile-'+i+'.png'));
}
magick(at('review/tile-0.png'),at('review/tile-1.png'),'+append',at('review/row-0.png'));
magick(at('review/tile-2.png'),at('review/tile-3.png'),'+append',at('review/row-1.png'));
magick(at('review/row-0.png'),at('review/row-1.png'),'-append','+repage',at('review/combined.png'));
magick('-size','1280x870','xc:#10131d',at('review/combined.png'),
  '-geometry','+0+62','-compose','over','-composite','+repage',
  '-gravity','northwest','-font','DejaVu-Sans','-fill','#ece6ff','-pointsize','23','-annotate','+28+19',
  'FIREFLY WISP ALIGNMENT / Same approved HUD in every panel',at('alignment-sheet.png'));
fs.unlinkSync(at('review/combined.png'));
for (let i=0;i<ids.length;i++) fs.unlinkSync(at('review/tile-'+i+'.png'));
for (let i=0;i<2;i++) fs.unlinkSync(at('review/row-'+i+'.png'));
console.log('Prepared five 1280x720 frames and fixed-HUD alignment sheet.');
