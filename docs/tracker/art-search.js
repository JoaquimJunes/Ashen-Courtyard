/* Pure Art Book preferences, indexing, filtering, and ordering rules. */
(function(root){
'use strict';
const groups=['types','collections','origins','roles','statuses','attention','priorities','animation_categories','animation_tags','source_libraries','rigs','motion_modes','preview_states','review_labels','art_tags','start_states','end_states','duplicate_states','naming_states'];
const statuses=['Planned','In progress','Ready for review','Completed','Deferred'];
const cache=new WeakMap();
const natural=new Intl.Collator(undefined,{numeric:true,sensitivity:'base'});
const own=(object,key)=>Object.prototype.hasOwnProperty.call(object,key);
const strings=value=>Array.isArray(value)?[...new Set(value.filter(v=>typeof v==='string').map(v=>v.trim()).filter(Boolean))]:[];
const selection=value=>typeof value==='string'?strings([value]):strings(value);
function defaults(){return {search:'',view:'all',types:[],collections:[],origins:['Project files'],roles:[],statuses:[],attention:[],priorities:[],animation_categories:[],animation_tags:[],source_libraries:[],rigs:[],motion_modes:[],preview_states:[],review_labels:[],art_tags:[],start_states:[],end_states:[],duplicate_states:[],naming_states:[],category_id:'',overviewScroll:0,sort:'relevance',layout:'gallery',individualImages:false,showDuplicateSources:false,scroll:0,limit:60};}

// Absence means a new visit; an explicit legacy empty topic means all origins.
// Unknown string selections survive so the UI can display and remove them.
function migrate(value){
 const result=defaults();
 if(!value||typeof value!=='object'||Array.isArray(value))return result;
 for(const group of groups)if(own(value,group))result[group]=selection(value[group]);
 if(!own(value,'types')&&own(value,'area'))result.types=selection(value.area);
 if(own(value,'topic')&&!own(value,'origins')){
  result.origins=selection(value.topic).filter(v=>v!=='References');
  if(value.topic==='References'&&!own(value,'roles'))result.roles=['Reference'];
 }
 if(!own(value,'priorities')&&own(value,'priority'))result.priorities=selection(value.priority);
 if(typeof value.category_id==='string')result.category_id=value.category_id;
 if(Number.isFinite(value.overviewScroll)&&value.overviewScroll>=0)result.overviewScroll=value.overviewScroll;
 if(typeof value.search==='string')result.search=value.search;
 if(typeof value.view==='string'&&value.view.trim())result.view=value.view.trim();
 if(statuses.includes(result.view)){
  result.statuses=[...new Set([...result.statuses,result.view])];
  result.view='all';
 }
 if(result.view==='recent'&&!own(value,'sort'))result.sort='recent';
 if(['relevance','name','recent','modified','recently-changed','attention'].includes(value.sort))result.sort=value.sort;
 if(['gallery','list'].includes(value.layout))result.layout=value.layout;
 if(typeof value.individualImages==='boolean')result.individualImages=value.individualImages;
 if(typeof value.showDuplicateSources==='boolean')result.showDuplicateSources=value.showDuplicateSources;
 if(typeof value.scroll==='number'&&Number.isFinite(value.scroll)&&value.scroll>=0)result.scroll=value.scroll;
 if(typeof value.limit==='number'&&Number.isFinite(value.limit)&&value.limit>0)result.limit=Math.max(1,Math.floor(value.limit));
 return result;
}

function normalize(value){
 return (typeof value==='string'?value:'').normalize('NFKD').replace(/\p{M}/gu,'').toLowerCase().replace(/ß/g,'ss').replace(/ς/g,'σ').replace(/[_\p{Dash_Punctuation}\s]+/gu,' ').trim();
}
function types(entry){const values=strings(entry.types);return values.length?values:selection(entry.kind);}
function collections(entry){return strings(entry.collections);}

// Catalog entries are immutable during a page session. WeakMap caching avoids
// repeatedly normalizing long clip lists on every keystroke or sort comparison.
function indexEntry(entry){
 if(cache.has(entry))return cache.get(entry);
 const index={
  title:normalize(entry.title),path:normalize([entry.path,...strings(entry.original_paths)].join(' ')),note:normalize(entry.note),
  aliases:normalize([...strings(entry.original_names),...strings(entry.transition_steps),entry.start_state||'',entry.end_state||''].join(' ')),
  types:types(entry).map(normalize).join(' '),collections:collections(entry).map(normalize).join(' '),
  clips:strings(entry.clip_names).map(name=>({name,text:normalize(name)}))
 };
 index.clipText=index.clips.map(clip=>clip.text).join(' ');
 cache.set(entry,index);return index;
}

// Every token must occur somewhere; token order is irrelevant. Per-token field
// weights and whole-name bonuses rank titles/clips above note/path-only hits.
function search(index,query,note='',displayName=''){
 const display=normalize(displayName);
 const tokens=[...new Set(normalize(query).split(' ').filter(Boolean))];
 if(!tokens.length)return {matches:true,score:0,matchingClips:[]};
 const fields=[[display,14],[index.title,12],[index.clipText,10],[index.aliases||'',9],[normalize(note)+' '+index.note,5],[index.types,3],[index.collections,3],[index.path,1]];
 let score=0;
 for(const token of tokens){
  const weight=fields.reduce((best,[value,points])=>value.includes(token)?Math.max(best,points):best,0);
  if(!weight)return {matches:false,score:0,matchingClips:[]};
  score+=weight;
 }
 if(tokens.every(token=>index.title.includes(token)||display.includes(token)))score+=30;
 if(index.clips.some(clip=>tokens.every(token=>clip.text.includes(token))))score+=25;
 if(index.title===normalize(query))score+=10;
 return {matches:true,score,matchingClips:index.clips.filter(clip=>tokens.some(token=>clip.text.includes(token))).map(clip=>clip.name)};
}

function timestamp(value){
 if(value&&typeof value==='object')return timestamp(value.at??value.timestamp??value.modified_at);
 if(typeof value==='number')return Number.isFinite(value)?value:0;
 if(typeof value!=='string'||!value.trim())return 0;
 const date=Date.parse(value);return Number.isFinite(date)?date:0;
}
// Activity is an ISO string, epoch milliseconds, or a history item with `at`.
function latestTimestamp(entry,activity){return Math.max(timestamp(entry.modified_at),timestamp(activity));}
function matchesGroup(selected,values){return !selected?.length||selected.some(value=>values.includes(value));}
function metadataDefaults(metadata){
 const m=metadata||{};
 return {art_tags:strings(m.art_tags),review_label:typeof m.review_label==='string'?m.review_label:'',status:typeof m.status==='string'?m.status:'',attention:strings(m.attention),priority:typeof m.priority==='string'?m.priority:'Normal',note:typeof m.note==='string'?m.note:'',display_name:typeof m.display_name==='string'?m.display_name:'',animation_categories:m.animation_categories,animation_tags:m.animation_tags};
}
function animationLabels(entry,m){
 const categories=Array.isArray(m.animation_categories)?m.animation_categories:entry.animation_categories||[];
 const tags=Array.isArray(m.animation_tags)?m.animation_tags:entry.animation_tags||[];
 return {categories:categories.length?categories:Array.isArray(entry.animation_categories)||Array.isArray(m.animation_categories)?['Unclassified']:[],tags};
}
function filter(entry,metadata,filters=defaults(),latestActivity){
 const m=metadataDefaults(metadata),f=filters;
 if(!matchesGroup(f.types,types(entry))||!matchesGroup(f.collections,collections(entry))||!matchesGroup(f.origins,selection(entry.origin))||!matchesGroup(f.roles,[entry.role||'Not a reference'])||!matchesGroup(f.statuses,[m.status||'Not set'])||!matchesGroup(f.attention,m.attention)||!matchesGroup(f.priorities,[m.priority]))return false;
 if(!matchesGroup(f.review_labels,[m.review_label||'Not decided']))return false;
 if(!matchesGroup(strings(f.art_tags).map(normalize),m.art_tags.map(normalize)))return false;
 if(!matchesGroup(f.start_states,[entry.start_state||'Unknown'])||!matchesGroup(f.end_states,[entry.end_state||'Unknown'])||!matchesGroup(f.duplicate_states,[entry.duplicate_status||'Not compared'])||!matchesGroup(f.naming_states,[entry.naming_status||'needs_review']))return false;
 const {categories,tags}=animationLabels(entry,m);
 if(!matchesGroup(f.animation_categories,categories.length?categories:['Unclassified'])||!matchesGroup(f.animation_tags,tags)||!matchesGroup(f.source_libraries,[entry.source_library])||!matchesGroup(f.rigs,[entry.rig])||!matchesGroup(f.motion_modes,[entry.motion_mode||'Unknown'])||!matchesGroup(f.preview_states,[entry.preview?.status||'unavailable']))return false;
 if(f.view==='attention'&&!m.attention.length||f.view==='missing'&&!entry.missing||f.view==='recent'&&!latestTimestamp(entry,latestActivity))return false;
 return search(indexEntry(entry),f.search,[m.note,m.review_label,...m.art_tags,...tags,...categories].join(' '),m.display_name).matches;
}
function activityFor(activity,id){return activity instanceof Map?activity.get(id):activity&&own(activity,id)?activity[id]:undefined;}
function nameOrder(a,b){return natural.compare(a.title||'',b.title||'')||natural.compare(a.path||'',b.path||'')||String(a.path||'').localeCompare(String(b.path||''))||String(a.id||'').localeCompare(String(b.id||''));}

// Returns a new array. `metadata(entry)` supplies effective editable metadata;
// `activity` maps entry IDs to timestamps/history items, and optional `indexes`
// maps entry IDs to indexEntry results. Recent order uses file OR user changes.
function sortEntries(entries,filters=defaults(),{metadata=()=>({}),activity,indexes}={}){
 const f=filters,hasQuery=Boolean(normalize(f.search));
 const prepared=new Map(entries.map(entry=>{
  const m=metadataDefaults(metadata(entry));
  const index=indexes?.get(entry.id)||indexEntry(entry);
  const {categories,tags}=animationLabels(entry,m);
  return [entry,{score:f.sort==='relevance'&&hasQuery?search(index,f.search,[m.note,m.review_label,...m.art_tags,...tags,...categories].join(' '),m.display_name).score:0,attention:m.attention.length,date:latestTimestamp(entry,activityFor(activity,entry.id))}];
 }));
 const displayOrder=(a,b)=>natural.compare(metadata(a)?.display_name||a.title||'',metadata(b)?.display_name||b.title||'')||nameOrder(a,b);
 return [...entries].sort((a,b)=>{
  const left=prepared.get(a),right=prepared.get(b);
  if(['recent','modified','recently-changed'].includes(f.sort))return right.date-left.date||displayOrder(a,b);
  if(f.sort==='attention')return right.attention-left.attention||displayOrder(a,b);
  if(f.sort==='relevance'&&hasQuery)return right.score-left.score||displayOrder(a,b);
  return displayOrder(a,b);
 });
}
const api={defaults,migrate,normalize,indexEntry,search,filter,sortEntries,latestTimestamp,types,collections};
if(typeof module!=='undefined'&&module.exports)module.exports=api;else root.ArtSearch=api;
})(typeof window!=='undefined'?window:globalThis);
