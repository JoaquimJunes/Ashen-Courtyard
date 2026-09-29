/* Pure tracker rules, shared by the browser and regression checks. */
(function(root){
'use strict';
const statuses=['Planned','In progress','Ready for review','Completed','Deferred'];
const attentions=['Bug found','Needs improvement','Needs testing','Needs visual review','Blocked','SPECIAL'];
const priorities=['High','Normal','Low'];
const reviewLabels=['Approved','Scrap'];
const version=5;
const artTagSuggestions=['Combat','Magic','Clothing','Armor','Weapons','Items'];
const taxonomy=typeof module!=='undefined'&&module.exports?require('../../tools/art_animation_taxonomy.json'):(root.TRACKER_DATA?.animation_taxonomy||{categories:[],tags:[]});
const legacyFields=['status','attention','priority','note','checklist','related'];
const newDefaults={display_name:'',animation_categories:null,animation_tags:null,review_label:'',art_tags:[]};
const versionThreeFields=[...legacyFields,'display_name','animation_categories','animation_tags'].sort().join(',');
const versionFourFields=[...legacyFields,'display_name','animation_categories','animation_tags','review_label'].sort().join(',');
const metadataFields=[...legacyFields,...Object.keys(newDefaults)].sort().join(',');
const copy=v=>JSON.parse(JSON.stringify(v));
function defaults(entry){
 const art=entry.book==='art'||entry.id.startsWith('art:');
 const status=art?'':({Implemented:'Ready for review',Partial:'In progress',Planned:'Planned'}[entry.status]||'Planned');
 const flag={Review:'Needs testing',Improvement:'Needs improvement','Bug correction':'Bug found'}[entry.attention];
 return {status,attention:flag?[flag]:[],priority:'Normal',note:'',checklist:copy(entry.checklist||[]),related:[],...copy(newDefaults)};
}
function normalizeArtTag(value){
 if(typeof value!=='string'||/[\x00-\x1f\x7f]/.test(value))throw Error('Tags must be text without control characters');
 const tag=value.normalize('NFKC').replace(/\s+/gu,' ').trim();
 if(!tag||[...tag].length>60)throw Error('Use between 1 and 60 characters per tag');
 for(const c of tag){const p=c.codePointAt(0);if(p>=0xd800&&p<=0xdfff)throw Error('Tags must contain valid Unicode');}
 return artTagSuggestions.find(s=>s.toLowerCase()===tag.toLowerCase())||tag;
}
const artTagKey=value=>normalizeArtTag(value).toLowerCase();
function validateArtTags(values,id){
 if(!Array.isArray(values)||values.length>32)throw Error('Use at most 32 tags per entry');
 if(values.length&&id!==undefined&&!id.startsWith('art:'))throw Error('Art tags are available only in Art Book');
 const tags=values.map(normalizeArtTag);
 if(new Set(tags.map(artTagKey)).size!==tags.length)throw Error('This entry already has that tag');
 return tags;
}
function effective(entry,items){return {...defaults(entry),...copy(items[entry.id]||{})};}
// Keep inherited labels separate from the stored null override, so saving a note
// does not accidentally freeze the current generated classification forever.
function animationLabels(entry,metadata){const result={};for(const field of ['animation_categories','animation_tags'])result[field]=copy(metadata[field]??entry[field]??[]);return result;}
function progress(item){const total=item.checklist.length,done=item.checklist.filter(c=>c.done).length;return {total,done,percent:total?(done===total?100:Math.min(99,Math.round(done*100/total))):null};}
function aggregate(entries,items){const result={total:0,done:0,assessed:0,count:entries.length,percent:null};for(const e of entries){const p=progress(effective(e,items));result.total+=p.total;result.done+=p.done;if(p.total)result.assessed++;}result.percent=result.total?(result.done===result.total?100:Math.min(99,Math.round(result.done*100/result.total))):null;return result;}
function validateMeta(v,id){
 if(!v||typeof v!=='object'||Array.isArray(v)||Object.keys(v).sort().join(',')!==metadataFields)throw Error('Invalid item fields');
 if(!['',...statuses].includes(v.status)||!priorities.includes(v.priority))throw Error('Invalid status or priority');
 if(!['',...reviewLabels].includes(v.review_label))throw Error('Review label must be Approved, Scrap or empty');
 if(v.review_label&&id!==undefined&&(typeof id!=='string'||!id.startsWith('art:')))throw Error('Approved and Scrap labels are available only in Art Book');
 if(!Array.isArray(v.attention)||v.attention.some(a=>!attentions.includes(a))||new Set(v.attention).size!==v.attention.length)throw Error('Invalid attention labels');
 if(typeof v.note!=='string'||v.note.length>10000)throw Error('Notes must be at most 10,000 characters');
 if(!Array.isArray(v.checklist)||v.checklist.length>200)throw Error('Invalid checklist');
 const ids=new Set();for(const c of v.checklist){
  if(!c||Object.keys(c).sort().join(',')!=='done,id,source,text'||typeof c.id!=='string'||!c.id||c.id.length>128||/[\x00-\x1f]/.test(c.id)||ids.has(c.id)||typeof c.text!=='string'||!c.text.trim()||c.text.length>2000||/[\x00-\x1f]/.test(c.text)||typeof c.done!=='boolean'||typeof c.source!=='string'||c.source.length>500)throw Error('Invalid checklist task');
  if(c.source&&(c.source.startsWith('/')||c.source.includes('\\')||c.source.split('/').some(p=>['','.','..','.git','.codex','.agents','.artifacts','.godot','__pycache__'].includes(p))||c.source.includes(':')||/[\x00-\x1f]/.test(c.source)))throw Error('Invalid source path');ids.add(c.id);
 }
 if(!Array.isArray(v.related)||v.related.length>200||new Set(v.related).size!==v.related.length||v.related.some(x=>typeof x!=='string'||!x.trim()||x.length>200||/[\x00-\x1f]/.test(x)||['__proto__','constructor','prototype'].includes(x)))throw Error('Invalid related features');
 if(v.status==='Completed'&&(!v.checklist.length||v.checklist.some(c=>!c.done)))throw Error('Completed requires a nonempty, fully checked checklist');
 if(typeof v.display_name!=='string'||/[\x00-\x1f]/.test(v.display_name))throw Error('Display name must be text without control characters');
 const name=v.display_name.trim();if([...name].length>200)throw Error('Display name must be at most 200 characters');
 // JSON permits lone surrogate escapes, but the UTF-8 service cannot save them.
 for(const character of name){const point=character.codePointAt(0);if(point>=0xd800&&point<=0xdfff)throw Error('Display name must contain valid Unicode');}
 for(const [field,labels] of [['animation_categories',taxonomy.categories],['animation_tags',taxonomy.tags]]){
  if(v[field]===null)continue;
  if(!Array.isArray(v[field])||v[field].some(label=>!labels.includes(label))||new Set(v[field]).size!==v[field].length)throw Error(field+' must contain unique supported labels');
 }
 return {...copy(v),display_name:name,art_tags:validateArtTags(v.art_tags,id)};
}
function importChanges(data,entries,items){
 if(!data||![1,2,3,4,version].includes(data.version))throw Error('Unsupported backup version');
 if(data.version>=2&&data.hasUnsavedEdits===true&&!data.pendingChanges)throw Error('This unsaved backup lacks a recovery patch. Compare it manually before importing.');
 const source=data.version===1?data.tracking:(data.hasUnsavedEdits===true?data.pendingChanges:data.items);
 if(!source||typeof source!=='object'||Array.isArray(source))throw Error('Invalid backup records');
 const changes=Object.create(null);
 for(const [id,value] of Object.entries(source)){
  if(!id.trim()||/[\x00-\x1f]/.test(id)||id.length>200||['__proto__','constructor','prototype'].includes(id))throw Error('Invalid item ID');
  if(data.version===version){changes[id]=validateMeta(value,id);continue;}
  if(data.version===4){
   if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).sort().join(',')!==versionFourFields)throw Error('Invalid version-four item fields');
   changes[id]=validateMeta({...value,art_tags:copy(items[id]?.art_tags??[])},id);continue;
  }
  if(data.version===3){
   if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).sort().join(',')!==versionThreeFields)throw Error('Invalid version-three item fields');
   changes[id]=validateMeta({...value,review_label:items[id]?.review_label??'',art_tags:copy(items[id]?.art_tags??[])},id);continue;
  }
  if(data.version===2){
   if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).sort().join(',')!==[...legacyFields].sort().join(','))throw Error('Invalid version-two item fields');
   // Older backups know nothing about current display names or classifications.
   // Preserve those explicit decisions when previewing their legacy fields.
   const overrides={};for(const field of Object.keys(newDefaults))overrides[field]=copy(items[id]?.[field]??newDefaults[field]);
   changes[id]=validateMeta({...value,...overrides},id);continue;
  }
  if(!value||!['Not reviewed','Reviewing','Needs improvement','Bug found','Reviewed'].includes(value.review)||typeof value.note!=='string'||value.note.length>10000)throw Error('Invalid legacy review');
  const entry=entries.find(e=>e.id===id)||{id,status:'Planned'};
  const m=effective(entry,items);m.note=value.note;
  if(value.review!=='Not reviewed'){const note=[m.note,'Previous review: '+value.review].filter(Boolean).join('\n');if(note.length<=10000)m.note=note;}
  const flag={'Needs improvement':'Needs improvement','Bug found':'Bug found'}[value.review];if(flag&&!m.attention.includes(flag))m.attention.push(flag);
  changes[id]=validateMeta(m,id);
 }
 return changes;
}
const api={version,taxonomy,statuses,attentions,priorities,reviewLabels,artTagSuggestions,normalizeArtTag,artTagKey,copy,defaults,effective,animationLabels,progress,aggregate,validateMeta,importChanges};
if(typeof module!=='undefined'&&module.exports)module.exports=api;else root.TrackerModel=api;
})(typeof window!=='undefined'?window:globalThis);
