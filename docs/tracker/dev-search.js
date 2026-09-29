/* Pure Dev book rules: generated evidence and editable tracking stay separate. */
(function(root){
'use strict';
const statuses=['Planned','In progress','Ready for review','Completed','Deferred'];
const sorts=['relevance','name','recent','attention','priority','progress'];
const cache=new WeakMap(),natural=new Intl.Collator(undefined,{numeric:true,sensitivity:'base'});
const text=value=>typeof value==='string'?value:'';
const strings=value=>Array.isArray(value)?value.filter(v=>typeof v==='string'):[];
const normalize=value=>text(value).normalize('NFKD').replace(/\p{M}/gu,'').toLowerCase().replace(/ß/g,'ss').replace(/ς/g,'σ').replace(/[_\p{Dash_Punctuation}\s]+/gu,' ').trim();
function defaults(){return {search:'',view:'all',area:'',topic:'',attention:'',priority:'',status:'',assessment:'',tag:'',sort:'relevance',scroll:0,limit:60};}
function migrate(value){
 const result=defaults();if(!value||typeof value!=='object'||Array.isArray(value))return result;
 for(const key of ['search','view','area','topic','attention','priority','status','assessment','tag'])if(typeof value[key]==='string')result[key]=value[key];
 if(sorts.includes(value.sort))result.sort=value.sort;else if(result.view==='recent')result.sort='recent';
 if(Number.isFinite(value.scroll)&&value.scroll>=0)result.scroll=value.scroll;
 if(Number.isFinite(value.limit)&&value.limit>0)result.limit=Math.max(1,Math.floor(value.limit));
 return result;
}
function tags(entry){return [...new Set(strings(entry.dev_tags).map(v=>v.trim()).filter(Boolean))];}
function indexEntry(entry){
 if(cache.has(entry))return cache.get(entry);
 const index={title:normalize(entry.title),summary:normalize(entry.summary),note:normalize(entry.note),tags:tags(entry).map(normalize).join(' '),
  context:[entry.area,entry.topic,entry.category,entry.subcategory].map(normalize).join(' '),
  sources:(entry.sources||[]).map(source=>typeof source==='string'?source:[source?.path,source?.title].filter(Boolean).join(' ')).map(normalize).join(' ')};
 cache.set(entry,index);return index;
}
function search(index,query,metadata={}){
 const tokens=[...new Set(normalize(query).split(' ').filter(Boolean))];if(!tokens.length)return {matches:true,score:0};
 const display=normalize(metadata.display_name),fields=[[display,14],[index.title,12],[index.summary,6],[index.tags,5],[index.context,4],[index.note+' '+normalize(metadata.note),3],[index.sources,1]];
 let score=0;for(const token of tokens){const points=fields.reduce((best,[value,weight])=>value.includes(token)?Math.max(best,weight):best,0);if(!points)return {matches:false,score:0};score+=points;}
 if(tokens.every(token=>display.includes(token)||index.title.includes(token)))score+=30;
 return {matches:true,score};
}
function timestamp(value){if(value&&typeof value==='object')return timestamp(value.at??value.timestamp??value.modified_at);if(typeof value==='number')return Number.isFinite(value)?value:0;const result=Date.parse(text(value));return Number.isFinite(result)?result:0;}
function latest(entry,activity){return Math.max(timestamp(entry.modified_at),timestamp(activity));}
function progress(entry,metadata){const checklist=Array.isArray(metadata.checklist)?metadata.checklist:Array.isArray(entry.checklist)?entry.checklist:[];const total=checklist.length,done=checklist.filter(c=>c?.done===true).length;return {total,done,ratio:total?done/total:null};}
function filter(entry,metadata={},filters=defaults(),latestActivity){
 const m=metadata||{},f=filters,p=progress(entry,m),attention=strings(m.attention);
 if(f.area&&f.area!==entry.area||f.topic&&f.topic!==entry.topic||f.attention&&!attention.includes(f.attention)||f.priority&&f.priority!==(m.priority||'Normal')||f.status&&f.status!==m.status||f.tag&&!tags(entry).includes(f.tag))return false;
 if(statuses.includes(f.view)&&f.view!==m.status||f.view==='attention'&&!attention.length||f.view==='missing'&&!entry.missing||f.view==='recent'&&!latest(entry,latestActivity)||f.view==='unassessed'&&p.total)return false;
 if(f.assessment==='unassessed'&&p.total||f.assessment==='assessed'&&!p.total||f.assessment==='complete_checks'&&(!p.total||p.done!==p.total)||f.assessment==='incomplete_checks'&&(!p.total||p.done===p.total))return false;
 return search(indexEntry(entry),f.search,m).matches;
}
function activityFor(activity,id){return activity instanceof Map?activity.get(id):activity?.[id];}
function sort(entries,filters=defaults(),{metadata=()=>({}),activity,indexes}={}){
 const values=new Map(entries.map(entry=>{const m=metadata(entry)||{};return [entry,{name:m.display_name||entry.title||'',score:search(indexes?.get(entry.id)||indexEntry(entry),filters.search,m).score,date:latest(entry,activityFor(activity,entry.id)),attention:strings(m.attention).length,priority:({High:0,Normal:1,Low:2})[m.priority]??1,progress:progress(entry,m).ratio}];}));
 return [...entries].sort((a,b)=>{const left=values.get(a),right=values.get(b);let difference=0;
  if(filters.sort==='recent')difference=right.date-left.date;
  else if(filters.sort==='attention')difference=right.attention-left.attention;
  else if(filters.sort==='priority')difference=left.priority-right.priority;
  else if(filters.sort==='progress')difference=left.progress===null?(right.progress===null?0:1):right.progress===null?-1:right.progress-left.progress;
  else if(filters.sort==='relevance'&&normalize(filters.search))difference=right.score-left.score;
  return difference||natural.compare(left.name,right.name)||natural.compare(a.title||'',b.title||'')||String(a.id||'').localeCompare(String(b.id||''));
 });
}
const api={defaults,migrate,filter,sort,tags,indexEntry};
if(typeof module!=='undefined'&&module.exports)module.exports=api;else root.DevSearch=api;
})(typeof window!=='undefined'?window:globalThis);
