// Minimal single-track VP9 WebM muxer for this deterministic offline export.
// Matroska element IDs and SimpleBlock layout: https://www.matroska.org/technical/elements.html
const B=Buffer;
const bytes=id=>{let h=id.toString(16);if(h.length%2)h='0'+h;return B.from(h,'hex');};
function vint(n){for(let len=1;len<=8;len++){if(BigInt(n)<(1n<<BigInt(7*len))-1n){let value=BigInt(n)|(1n<<BigInt(7*len));const out=B.alloc(len);for(let i=len-1;i>=0;i--){out[i]=Number(value&255n);value>>=8n;}return out;}}throw Error('Element too large');}
function element(id,content){return B.concat([bytes(id),vint(content.length),content]);}
function uint(id,n){let h=BigInt(n).toString(16);if(h.length%2)h='0'+h;return element(id,B.from(h,'hex'));}
const string=(id,s)=>element(id,B.from(s));
const list=(id,children)=>element(id,B.concat(children));
function float(id,n){const b=B.alloc(8);b.writeDoubleBE(n);return element(id,b);}
function mux(frames,{width=1280,height=720,fps=60}={}){
  frames=[...frames].sort((a,b)=>a.timestamp-b.timestamp);
  if(frames.length!==600)throw Error(`Expected 600 encoded frames, got ${frames.length}`);
  frames.forEach((f,i)=>{if(Math.abs(f.timestamp-i*1e6/fps)>1)throw Error(`Invalid timestamp at ${i}`);});
  const header=list(0x1a45dfa3,[uint(0x4286,1),uint(0x42f7,1),uint(0x42f2,4),uint(0x42f3,8),string(0x4282,'webm'),uint(0x4287,4),uint(0x4285,2)]);
  const info=list(0x1549a966,[uint(0x2ad7b1,1000000),string(0x4d80,'Soul reference export'),string(0x5741,'Soul reference export'),float(0x4489,frames.length*1000/fps)]);
  const track=list(0x1654ae6b,[list(0xae,[uint(0xd7,1),uint(0x73c5,1),uint(0x83,1),uint(0x9c,0),string(0x86,'V_VP9'),uint(0x23e383,Math.round(1e9/fps)),list(0xe0,[uint(0xb0,width),uint(0xba,height)])])]);
  const clusters=[],positions=[];let position=info.length+track.length;
  for(let start=0;start<frames.length;start+=60){
    const time=Math.round(frames[start].timestamp/1000);
    const blocks=frames.slice(start,start+60).map(f=>{
      const prefix=B.alloc(4);prefix[0]=0x81;prefix.writeInt16BE(Math.round(f.timestamp/1000)-time,1);prefix[3]=f.type==='key'?0x80:0;
      return element(0xa3,B.concat([prefix,f.data]));
    });
    const cluster=list(0x1f43b675,[uint(0xe7,time),...blocks]);
    positions.push({time,position});clusters.push(cluster);position+=cluster.length;
  }
  const cues=list(0x1c53bb6b,positions.map(p=>list(0xbb,[uint(0xb3,p.time),list(0xb7,[uint(0xf7,1),uint(0xf1,p.position)])])));
  return B.concat([header,list(0x18538067,[info,track,...clusters,cues])]);
}
module.exports={mux};
