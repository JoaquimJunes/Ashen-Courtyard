/* Animation views project existing sources into clips; no playback or saved-state writes. */
(function(root,factory){if(typeof module!=='undefined'&&module.exports)module.exports=factory(require('./art-search.js'));else root.ArtAnimations=factory(root.ArtSearch);})(typeof window!=='undefined'?window:globalThis,function(A){
'use strict';
const isClip=e=>e.id?.startsWith('art:clip:');
const isCategory=e=>e.id?.startsWith('art:category:');
const duplicateKey=e=>e.duplicate_status==='verified_duplicate'&&e.duplicate_group?e.duplicate_group:e.id;
function groupDuplicates(matches,all=matches,showSources=false){
 if(showSources)return matches;
 const groups=new Map();for(const entry of matches){const key=duplicateKey(entry);if(!groups.has(key))groups.set(key,[]);groups.get(key).push(entry);}
 return [...groups.values()].map(members=>{
  const first=members[0];if(duplicateKey(first)===first.id)return first;
  const representative=members.find(e=>e.id===e.duplicate_keeper_id)||first;
  return {...representative,duplicate_member_ids:all.filter(e=>duplicateKey(e)===duplicateKey(first)).map(e=>e.id),matching_duplicate_ids:members.map(e=>e.id)};
 });
}
function duplicateEntries(entries,filters,options={}){
 const list=modelEntries(entries).filter(e=>e.duplicate_status),date=e=>options.activity instanceof Map?options.activity.get(e.id):options.activity?.[e.id];
 const matches=list.filter(e=>A.filter(e,options.metadata?.(e)||{},filters,date(e)));
 return {entries:A.sortEntries(groupDuplicates(matches,list,filters.showDuplicateSources),filters,options),sourceClipCount:matches.length,matchedClipCount:new Set(matches.map(duplicateKey)).size};
}
function labels(e,m={}){const categories=Array.isArray(m.animation_categories)?m.animation_categories:e.animation_categories||[];return {categories:categories.length?categories:['Unclassified'],tags:Array.isArray(m.animation_tags)?m.animation_tags:e.animation_tags||[]};}
function modelEntries(entries){const parents=new Set(entries.filter(isClip).map(e=>e.parent_id));return entries.filter(e=>isClip(e)||(!isCategory(e)&&!Array.isArray(e.members)&&e.preview?.kind==='model'&&!parents.has(e.id))).map(e=>isClip(e)?e:{...e,animation_categories:['Unclassified'],animation_tags:[],unresolved_animation:true});}
function uiEntries(entries){const sequences=new Set(),result=[],byId=new Map(entries.map(e=>[e.id,e]));
 const packs=entries.filter(e=>Array.isArray(e.members)&&!isCategory(e)&&A.collections(e).includes('UI')&&(e.preview?.kind==='sequence'||e.preview_member)).map(e=>{
  if(e.preview?.kind==='sequence')return e;
  // preview_member is an explicit documented sequence relationship. Retain its
  // pack even if the first frame vanished or an older catalog lost the preview.
  const member=byId.get(e.preview_member),known=member?.preview?.kind==='sequence'?member.preview:e.members.map(id=>byId.get(id)?.preview).find(p=>p?.kind==='sequence');
  return {...e,preview:{status:'unavailable',kind:'sequence',reason:member?.preview?.reason||'The sequence preview needs to be rebuilt.',sequence:{id:known?.sequence?.id||e.id,start_frame:0}}};
 });
 const members=new Set(packs.flatMap(e=>e.members));
 // A documented sequence is one item even when its atlas/frames also reference it.
 for(const e of [...packs,...entries.filter(e=>!Array.isArray(e.members))]){
  if(!A.collections(e).includes('UI')||members.has(e.id)||!['sequence','video'].includes(e.preview?.kind))continue;
  const sequence=e.preview.sequence?.id;
  if(sequence&&sequences.has(sequence))continue;
  if(sequence)sequences.add(sequence);result.push(e);
 }return result;
}
function project(entries,categories,filters,{metadata=()=>({}),activity,indexes}={}){
 const list=modelEntries(entries),options={metadata,activity,indexes},date=e=>activity instanceof Map?activity.get(e.id):activity?.[e.id];
 const matches=e=>A.filter(e,metadata(e),filters,date(e));
 const categoryName=c=>c.category_label||c.title;
 const selected=categories.find(c=>c.id===filters.category_id);
 if(selected){const name=categoryName(selected),own=A.search(A.indexEntry(selected),filters.search,metadata(selected).note,metadata(selected).display_name).matches,clips=list.filter(e=>labels(e,metadata(e)).categories.includes(name)&&A.filter(e,metadata(e),own?{...filters,search:''}:filters,date(e)));return {entries:A.sortEntries(groupDuplicates(clips,list,filters.showDuplicateSources),filters,options),matchedClipCount:new Set(clips.filter(isClip).map(duplicateKey)).size,sourceClipCount:clips.filter(isClip).length,unavailableFileCount:clips.filter(e=>e.unresolved_animation).length,category:selected};}
 const cards=[];
 for(const category of categories){
  const name=categoryName(category),members=list.filter(e=>labels(e,metadata(e)).categories.includes(name));
  // Searching a category's own label/notes may reveal its matching members;
  // quality and library facets still apply independently to each clip.
  const own=A.search(A.indexEntry(category),filters.search,metadata(category).note,metadata(category).display_name).matches;
  const subset=members.filter(e=>own?A.filter(e,metadata(e),{...filters,search:''},date(e)):matches(e));
  if(!subset.length)continue;
  cards.push({...category,animation_category:true,members:members.map(e=>e.id),matching_member_ids:subset.map(e=>e.id),matching_count:new Set(subset.filter(isClip).map(duplicateKey)).size,matching_source_count:subset.filter(isClip).length,unavailable_count:subset.filter(e=>e.unresolved_animation).length,cover:subset.find(e=>e.thumbnail?.status==='ready')?.id||subset[0]?.id});
 }
 const unique=new Set(cards.flatMap(c=>c.matching_member_ids)),matched=list.filter(e=>unique.has(e.id)&&isClip(e));return {entries:cards,matchedClipCount:new Set(matched.map(duplicateKey)).size,sourceClipCount:matched.length,unavailableFileCount:list.filter(e=>unique.has(e.id)&&e.unresolved_animation).length,category:null};
}
return {isClip,isCategory,labels,modelEntries,uiEntries,project,groupDuplicates,duplicateEntries};
});
