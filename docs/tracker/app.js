'use strict';
const R=window.ArtReview,D=window.DevSearch,N=window.ArtAnimations,P=window.ArtPacks,A=window.ArtSearch,M=window.TrackerModel,$=id=>document.getElementById(id),catalog=window.TRACKER_DATA;
const copy=M.copy,UI_KEY='ashen-books-view-v2',OLD_KEY='ashen-progress-v1';
const allEntries=[...catalog.features.map(f=>({...f,book:'dev'})),...catalog.art.map(a=>({...a,book:'art'})),...(catalog.packs||[]).map(a=>({...a,book:'art'})),...(catalog.animation_clips||[]).map(a=>({...a,book:'art'})),...(catalog.animation_categories||[]).map(a=>({...a,book:'art'}))];
const index=new Map(allEntries.map(e=>[e.id,e]));
let reviewWorking=false,packWorking=false;
let relatedSearch={id:null,query:''};
let state={version:M.version,revision:0,items:{},history:[]},drafts=Object.create(null),online=false,saving=false,blocked=false,timer,book='dev',detailId=null,importDraft=null,importLegacy=null,pendingLegacy=null,limit=60;
let draftPackRevision=null;
const freshView=()=>D.defaults();
let views={dev:freshView(),art:A.defaults()};
try{const saved=JSON.parse(localStorage.getItem(UI_KEY)||'null');if(saved){book=saved.book==='art'?'art':'dev';views.dev=D.migrate(saved.views?.dev);views.art=saved.views&&Object.hasOwn(saved.views,'art')?A.migrate(saved.views.art):A.defaults();}}catch(e){}
let artMode='files',artViews={files:views.art,models:{...A.defaults(),origins:[]},ui:A.defaults(),duplicates:{...A.defaults(),origins:[],layout:'list'},approved:{...A.defaults(),origins:[]},scrap:{...A.defaults(),origins:[],layout:'list'}};
try{const saved=JSON.parse(localStorage.getItem(UI_KEY)||'null');if(saved?.artViews){for(const key of ['files','models','ui','duplicates','approved','scrap'])if(saved.artViews[key])artViews[key]=A.migrate(saved.artViews[key]);if(['files','models','ui','duplicates','approved','scrap'].includes(saved.artMode))artMode=saved.artMode;views.art=artViews[artMode];}}catch(e){}
const el=(tag,text,cls)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=text;if(cls)n.className=cls;return n;};
const items=()=>({...state.items,...drafts});
const rawGet=id=>index.get(id)||{id,title:'Missing catalog entry: '+id,book:id.startsWith('art:')?'art':'dev',missing:true,area:'Systems',topic:'Missing entries',kind:'Missing entries',sources:[]};
let trashRef=null,trashIds=new Set(),trashedSequences=new Set();
function removedIds(){if(trashRef!==state.trash){trashRef=state.trash;trashIds=R.hiddenIds(state);trashedSequences=new Set([...trashIds].map(id=>rawGet(id).preview?.sequence?.id).filter(Boolean));}return trashIds;}
function isTrashed(e){const ids=removedIds();return ids.has(e.id)||!!e.parent_id&&ids.has(e.parent_id);}
function get(id){let e=rawGet(id);const hidden=removedIds();if(!hidden.size)return e;
 if(e.preview?.kind==='sequence'&&trashedSequences.has(e.preview.sequence?.id)){const reason='This sequence contains a file in project Trash. Restore it before playback.';e={...e,preview:{...e.preview,status:'unavailable',reason},thumbnail:{status:'unavailable',reason}};}
 if(Array.isArray(e.members)&&!N.isCategory(e)){const members=e.members.filter(id=>!hidden.has(id)),cover=hidden.has(e.cover)?members[0]:e.cover;return {...e,members,cover,...(cover!==e.cover?{url:cover?rawGet(cover).url:'',image:!!cover&&rawGet(cover).image}:{})};}return e;
}
// Read one annotation directly; do not copy the entire project state per card.
const meta=e=>M.effective(e,{[e.id]:drafts[e.id]??state.items[e.id]});
const devIndexes=new Map(allEntries.filter(e=>e.book==='dev').map(e=>[e.id,D.indexEntry(e)]));
const artIndexes=new Map(allEntries.filter(e=>e.book==='art').map(e=>[e.id,A.indexEntry(e)]));
const isPack=e=>Array.isArray(e.members)&&!N.isCategory(e);
const title=e=>meta(e).display_name||e.title;
const canEdit=e=>online&&!blocked&&!reviewWorking&&!packWorking&&!isTrashed(e)&&e.identity_editable!==false;
const fileEntries=()=>entries('art').filter(e=>!N.isClip(e)&&!N.isCategory(e));
let animationProjection=null,artProjection=null,packEntry=null,packLimit=60,packReturnFocus=null,packSelection=null,packFilters=null;
let packVisibleIds=[],detailPack=null;
const detailFormDrafts=new Map();
let historyRef=null,activityCache=new Map();
function activity(){if(historyRef!==state.history){historyRef=state.history;activityCache=new Map();for(const h of state.history)if(h.at>(activityCache.get(h.id)||''))activityCache.set(h.id,h.at);}return activityCache;}
function entries(which=book){const known=allEntries.filter(e=>e.book===which&&!isTrashed(e)).map(e=>get(e.id));return known.concat(Object.keys(items()).filter(id=>!index.has(id)&&get(id).book===which&&!isTrashed(get(id))).map(get));}
function message(text){$('message').textContent=text;}
function saveStatus(text,error=false){$('save-state').textContent=text;$('save-state').classList.toggle('error',error);}
function sourceLink(title,path){const a=el('a',title);if(typeof path==='string'&&path&&!path.startsWith('/')&&!path.includes('\\')&&!path.split('/').includes('..')&&!/^[a-z]+:/i.test(path)){a.href='../../'+path.split('/').map(encodeURIComponent).join('/');a.target='_blank';a.rel='noopener';}return a;}
function optionList(select,values,first='All'){select.replaceChildren(new Option(first,''),...values.map(v=>new Option(v,v)));}
function progressLabel(p){return p.total?`${p.percent}% · ${p.done}/${p.total} checks`:'Not assessed';}
function progressNode(value){const box=el('div');const p=M.progress(value);box.append(el('span',progressLabel(p),'progress-text'));if(p.total){const bar=el('progress');bar.max=p.total;bar.value=p.done;bar.setAttribute('aria-label','Checklist completion');box.append(bar);}return box;}
function currentFilters(){const f=views[book];const keys=book==='art'?['search','view']:['search','view','area','topic','attention','priority'];for(const key of keys)f[key]=$(key).value;if(book==='dev')for(const key of ['status','assessment','tag','sort'])f[key]=$('dev-'+key).value;return f;}
function persistView(){try{localStorage.setItem(UI_KEY,JSON.stringify({book,views,artMode,artViews:{...artViews,[artMode]:views.art}}));}catch(e){}}
function rememberPosition(){views[book].scroll=window.scrollY;views[book].limit=limit;persistView();}
function setupFilters(){
 const art=book==='art',f=views[book];
 for(const label of document.querySelectorAll('.dev-filter'))label.hidden=art;for(const id of ['dev-navigation','dev-tools','active-dev-filters'])$(id).hidden=art;
 $('scrap-tools').hidden=!art||artMode!=='scrap';$('scrap-trash').hidden=!art||artMode!=='scrap';$('art-navigation').hidden=!art;$('animation-breadcrumb').hidden=!art||artMode!=='models';$('art-sidebar').hidden=!art;$('art-tools').hidden=!art;$('active-art-filters').hidden=!art;
 $('book-layout').classList.toggle('art-book-layout',art);
 $('view').replaceChildren(...(art?[['all','All entries'],['attention','Needs attention'],['recent','Recently changed'],['missing','Missing catalog entries']]:[['all','All entries'],['attention','Needs attention'],...M.statuses.map(s=>[s,s]),['unassessed','Not assessed'],['recent','Recently changed'],['missing','Missing catalog entries']]).map(([v,t])=>new Option(t,v)));
 $('search').value=f.search;$('view').value=f.view;
 $('search').placeholder=art?'Search assets, tags, clip names or notes…':'Search names, descriptions, tags or notes…';
 if(art){buildArtFilters();syncArtControls();return;}
 optionList($('area'),[...new Set(entries('dev').map(e=>e.area).filter(Boolean))].sort());$('area').value=f.area;
 setupTopics();optionList($('attention'),M.attentions);optionList($('priority'),M.priorities);
 for(const key of ['attention','priority'])$(key).value=f[key];
 optionList($('dev-status'),M.statuses,'All statuses');optionList($('dev-tag'),[...new Set(entries('dev').flatMap(D.tags))].sort(),'All tags');for(const key of ['status','assessment','tag','sort'])$('dev-'+key).value=f[key];
}
function setupTopics(){const f=views.dev;optionList($('topic'),[...new Set(entries('dev').filter(e=>!$('area').value||e.area===$('area').value).map(e=>e.topic).filter(Boolean))].sort());$('topic').value=f.topic;}
const baseArtGroups=[['art_tags','Tags'],['types','Type'],['collections','Collection'],['origins','Origin'],['roles','Reference role'],['statuses','Status'],['attention','Attention'],['priorities','Priority'],['review_labels','Review decision']];
function artGroups(){if(['scrap','approved'].includes(artMode))return baseArtGroups.filter(([key])=>key!=='review_labels');return ['models','duplicates'].includes(artMode)?[['start_states','Starts in'],['end_states','Ends in'],['duplicate_states','Comparison'],['naming_states','Naming review'],['animation_categories','Category'],['animation_tags','Animation tags'],['source_libraries','Source library'],['rigs','Rig'],['motion_modes','Motion'],['preview_states','Preview'],...baseArtGroups.filter(([key])=>!['types','collections','roles'].includes(key))]:baseArtGroups;}
function artOptions(){const list=['models','duplicates'].includes(artMode)?N.modelEntries(entries('art')):fileEntries();return {
 start_states:[...new Set(list.map(e=>e.start_state||'Unknown'))].sort(),end_states:[...new Set(list.map(e=>e.end_state||'Unknown'))].sort(),duplicate_states:[...new Set(list.map(e=>e.duplicate_status||'Not compared'))].sort(),naming_states:[...new Set(list.map(e=>e.naming_status||'needs_review'))].sort(),
 art_tags:artTagVocabulary(),review_labels:['Not decided',...M.reviewLabels],animation_categories:(catalog.animation_taxonomy?.categories||[]),animation_tags:[...new Set(list.flatMap(e=>N.labels(e,meta(e)).tags))].sort(),
 source_libraries:[...new Set(list.map(e=>e.source_library).filter(Boolean))].sort(),rigs:[...new Set(list.map(e=>e.rig).filter(Boolean))].sort(),motion_modes:['Root motion','In place','Unknown'],preview_states:['ready','unavailable','stale'],
 types:[...new Set(list.flatMap(A.types))].sort(),collections:[...new Set(list.flatMap(A.collections))].sort(),
 origins:['Project files','Third-party library'],roles:['Reference','Not a reference'],statuses:['Not set',...M.statuses],attention:M.attentions,priorities:M.priorities};}
function buildArtFilters(){
 const target=$('art-filter-groups'),options=artOptions();target.replaceChildren();
 for(const [key,title] of artGroups()){const field=el('fieldset'),legend=el('legend',title);field.append(legend);
  for(const value of [...new Set([...options[key],...views.art[key]])]){const label=el('label',undefined,'checklabel'),input=el('input');input.type='checkbox';input.dataset.group=key;input.value=value;input.checked=views.art[key].includes(value);
   input.onchange=()=>{const selected=new Set(views.art[key]);input.checked?selected.add(value):selected.delete(value);views.art[key]=[...selected];artFilterChanged();};label.append(input,document.createTextNode(animationLabel(value)));field.append(label);
  }target.append(field);
 }
}
function artFilterChanged(){limit=60;views.art.limit=60;syncArtControls();render();persistView();}
function syncArtControls(){
 const f=views.art;document.querySelectorAll('[data-art-mode]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.artMode===artMode)));$('show-individual-images').closest('label').hidden=artMode!=='files';$('art-sort').value=f.sort;$('show-individual-images').checked=!!f.individualImages;
 document.querySelectorAll('#art-filter-groups input').forEach(c=>c.checked=f[c.dataset.group].includes(c.value));
 document.querySelectorAll('[data-layout]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.layout===f.layout)));
 document.querySelectorAll('[data-shortcut]').forEach(b=>{b.hidden=artMode!=='files';b.setAttribute('aria-pressed',String((b.dataset.shortcut==='UI'?f.collections:f.types).includes(b.dataset.shortcut)));});
 $('show-duplicate-sources').closest('label').hidden=!['models','duplicates'].includes(artMode);$('show-duplicate-sources').checked=!!f.showDuplicateSources;
 const target=$('active-art-filters'),focusedIndex=[...target.querySelectorAll('button')].indexOf(document.activeElement);target.replaceChildren();
 const chip=(label,remove)=>{const button=el('button',label+' ×','filter-chip');button.setAttribute('aria-label','Remove '+label+' filter');button.onclick=remove;target.append(button);};
 for(const [key,title] of artGroups())for(const value of f[key])chip(title+': '+animationLabel(value),()=>{f[key]=f[key].filter(v=>v!==value);artFilterChanged();});
 if(f.search)chip('Search: '+f.search,()=>{$('search').value='';f.search='';artFilterChanged();});
 if(f.view!=='all')chip('View: '+$('view').selectedOptions[0]?.textContent,()=>{$('view').value='all';f.view='all';artFilterChanged();});
 if(!target.children.length)target.append(el('span','All assets · no active filters','muted'));
 if(focusedIndex>=0){const chips=target.querySelectorAll('button');(chips[Math.min(focusedIndex,chips.length-1)]||$('search')).focus({preventScroll:true});}
}
function clearFilters(){if(book==='art'){const old=views.art;views.art={...A.defaults(),origins:[],layout:old.layout,sort:old.sort,individualImages:old.individualImages,showDuplicateSources:old.showDuplicateSources,category_id:old.category_id,overviewScroll:old.overviewScroll};}else views.dev=freshView();limit=60;setupFilters();render();}
function artMatches(e){return A.search(artIndexes.get(e.id)||A.indexEntry(e),views.art.search,[meta(e).note,...meta(e).art_tags].join(' '),meta(e).display_name);}
function animationLabel(value){return ({verified_duplicate:'Verified duplicate',candidate:'Comparison pending',distinct_variant:'Distinct variation',derived:'Derived / runtime version',verified:'Reviewed name',source_name:'Source-named',needs_review:'Needs naming review'})[value]||value;}
function duplicateScrapEligibility(source){
 const parent=get(source.parent_id),keeper=source.duplicate_keeper_id?get(source.duplicate_keeper_id):null;
 const keeperParent=keeper?.parent_id?get(keeper.parent_id):null;
 const children=entries('art').filter(x=>N.isClip(x)&&x.parent_id===parent.id);
 const protectedWork=meta(parent).review_label==='Approved'||children.some(x=>meta(x).review_label==='Approved');
 if(protectedWork)return {eligible:false,reason:'Approved work is protected.'};
 if(!keeper||!keeperParent||keeper.missing||keeperParent.missing||isTrashed(keeper)||isTrashed(keeperParent))return {eligible:false,reason:'The proposed keeper is unavailable. Restore or choose a keeper before queuing another copy.'};
 if(children.length!==1)return {eligible:false,reason:'This source contains other clips or has an ambiguous identity and must be kept.'};
 const eligible=source.duplicate_status==='verified_duplicate'&&source.duplicate_file_eligible===true&&source.parent_id!==keeper.parent_id&&!source.missing&&!parent.missing&&!isTrashed(source)&&!isTrashed(parent)&&!source.duplicate_runtime_references?.length;
 return {eligible,reason:eligible?'':'Source safety checks are incomplete or references require this file.'};
}
function animationReviewControls(e,container,full=false){
 if(!N.isClip(e))return;
 if(e.naming_status==='needs_review')container.append(el('span','Needs naming review','badge warn'));
 if(e.transition_steps?.length)container.append(el('p',e.transition_steps.join(' → '),'animation-transition'));
 if(full){
  const evidence=el('details');evidence.append(el('summary','Naming evidence & original identifiers'));
  for(const text of [...(e.naming_evidence||[]),...(e.original_names||[]).map(x=>'Original name: '+x),...(e.original_paths||[]).map(x=>'Original path: '+x)])evidence.append(el('p',text,'path'));
  evidence.append(el('p',`Starts in: ${e.start_state||'Unknown'} · Ends in: ${e.end_state||'Unknown'}`));container.append(evidence);
 }
 if(!e.duplicate_status)return;
 container.append(el('span',animationLabel(e.duplicate_status),'badge'));
 const comparison=el('details',undefined,'animation-comparison');comparison.open=full||artMode==='duplicates';
 const sources=entries('art').filter(x=>N.isClip(x)&&(e.duplicate_group?x.duplicate_group===e.duplicate_group:x.id===e.id));
 comparison.append(el('summary',`${e.duplicate_status==='verified_duplicate'?'Source copies':'Compared sources'} (${sources.length})`));
 if(e.duplicate_reason)comparison.append(el('p',e.duplicate_reason));
 for(const text of e.duplicate_evidence||[])comparison.append(el('p',text,'path'));
 comparison.append(el('p','Each source keeps its own notes, status and approval.','path'));
 const keeper=e.duplicate_keeper_id?get(e.duplicate_keeper_id):{},keeperParent=keeper.parent_id;
 for(const source of sources){
  const row=el('div',undefined,'animation-source-row'),parent=get(source.parent_id),m=meta(source);
  const open=el('button',title(source));open.dataset.readonlyAction='true';open.onclick=()=>openDetail(source.id);
  row.append(open,el('p',source.path||source.id,'path'));
  if(source.duplicate_references?.length){const refs=el('details');refs.append(el('summary','Referenced by ('+source.duplicate_references.length+')'));for(const path of source.duplicate_references){const line=el('p');line.append(sourceLink(path,path));refs.append(line);}row.append(refs);}
  if(source.id===e.duplicate_keeper_id)row.append(el('span','Proposed keeper','badge'));
  if(m.review_label)row.append(reviewBadge(m.review_label));for(const flag of m.attention)row.append(el('span',flag,'badge warn'));
  if(full||artMode==='duplicates'){
   const file=el('button','Source file details');file.dataset.readonlyAction='true';file.onclick=()=>openDetail(parent.id);row.append(file);
   if(source.duplicate_status==='verified_duplicate'&&source.parent_id!==keeperParent){
    const safety=duplicateScrapEligibility(source),eligible=safety.eligible;
    const scrap=el('button',meta(parent).review_label==='Scrap'?'File marked Scrap':'Mark redundant file as Scrap');scrap.dataset.duplicateScrap=source.id;scrap.disabled=!canEdit(parent)||!eligible||meta(parent).review_label==='Scrap';
    scrap.onclick=()=>{if(!duplicateScrapEligibility(source).eligible||!canEdit(parent))return;if(!confirm(`Mark “${title(parent)}” as Scrap?\n\nIts file stays in place until you select it in Scrap and confirm moving it to Trash.`))return;change(parent.id,{review_label:'Scrap'});if(detailId)openDetail(detailId);};row.append(scrap);
    if(!eligible)row.append(el('p',safety.reason,'path'));
   }
  }
  comparison.append(row);
 }
 container.append(comparison);
}
function previewAction(e,container){
 if(!e.preview)return;
 if(e.preview.provenance?.label)container.append(el('p',e.preview.provenance.label,'clip-info'));
 const button=el('button',e.preview.status==='ready'?(isPack(e)?'Play animation':'Preview animation'):'Preview unavailable','animation-open');
 button.dataset.readonlyAction='true';button.onclick=()=>ArtPreview.open({...e,title:title(e)},e.source_clip?.name||null,()=>openDetail(e.id));container.append(button);
 if(e.preview.status!=='ready'&&e.preview.reason)container.append(el('p',e.preview.reason,'clip-info'));
}
function clipItem(e,name){
 const li=el('li');
 if(e.preview?.status==='ready'&&e.preview.kind==='model'){
  const button=el('button',name,'clip-play');button.dataset.readonlyAction='true';button.setAttribute('aria-label','Preview clip '+name);
  button.onclick=()=>ArtPreview.open({...e,title:title(e)},name,()=>openDetail(e.id));li.append(button);
 }else li.textContent=name;
 return li;
}
function clipSummary(e,container,full=false){
 if(N.isClip(e))return;
 if(e.clip_status==='not_applicable'||(!A.types(e).includes('Animations')&&!(full&&e.clip_status==='unavailable')))return;
 const names=e.clip_names||[],result=artMatches(e),matching=views.art.search?result.matchingClips:[];
 const p=el('p',e.clip_status==='unavailable'?'Clip names unavailable':names.length?names.length+' named clips':'No named clips in metadata','clip-info');container.append(p);
 const shown=matching.length?matching:(full?names:[]);
 if(shown.length){const list=el('ul',undefined,'clip-list');for(const name of (full?shown:shown.slice(0,3)))list.append(clipItem(e,name));container.append(list);if(!full&&shown.length>3)container.append(el('p','+'+(shown.length-3)+' more matching clips','clip-info'));}
 if(full&&matching.length&&matching.length<names.length){const rest=el('details');rest.append(el('summary','All '+names.length+' clip names'));const list=el('ul',undefined,'clip-list');names.forEach(name=>list.append(clipItem(e,name)));rest.append(list);container.append(rest);}
}
function renderPackMembers(){
 if(!packEntry)return;
 const focusedMember=document.activeElement.closest?.('#pack-members .pack-member')?.dataset.id;
 if(packFilters)packSelection=new Set(packEntry.members.map(get).filter(e=>A.filter(e,meta(e),packFilters,activity().get(e.id))).map(e=>e.id));
 const notice=$('pack-filter-notice');notice.replaceChildren();
 if(packFilters){notice.append(document.createTextNode('Showing images matching your Art Book filters. '));const all=el('button','Show all images in this pack');all.onclick=()=>{packFilters=null;packSelection=null;packLimit=60;renderPackMembers();};notice.append(all);}
 const query=$('pack-search').value;
 const members=packEntry.members.map(get).filter(e=>(!packSelection||packSelection.has(e.id))&&A.search(artIndexes.get(e.id)||A.indexEntry(e),query,[meta(e).note,...meta(e).art_tags].join(' '),meta(e).display_name).matches);
 packVisibleIds=members.map(e=>e.id);
 $('pack-count').textContent=`${members.length} of ${packEntry.members.length} images${packEntry.missing_count?' · '+packEntry.missing_count+' missing':''}`;
 $('pack-members').replaceChildren();$('pack-more').replaceChildren();
 for(const e of members.slice(0,packLimit)){
  const tile=el('div',undefined,'pack-member-tile');tile.dataset.id=e.id;const button=el('button',undefined,'pack-member');button.dataset.id=e.id;button.onclick=()=>openDetail(e.id,{packId:packEntry.id,ids:[...packVisibleIds]});
  if(e.image&&!e.missing){const img=el('img');img.src=e.url;img.loading='lazy';img.alt='';img.onerror=()=>{img.replaceWith(el('span','Image unavailable','asset-placeholder'));};button.append(img);}else button.append(el('span','Missing image — notes retained','asset-placeholder'));
  button.append(el('span',title(e)));const flags=meta(e).attention;if(flags.length)button.append(el('small',flags.join(' · ')));tile.append(button,packManager.removalControl(packEntry,e));$('pack-members').append(tile);
 }
 syncPackMemberReviews();
 if(!members.length)$('pack-members').append(el('p','No matching images in this pack.'));
 if(focusedMember){const replacement=[...$('pack-members').querySelectorAll('.pack-member')].find(n=>n.dataset.id===focusedMember);(replacement||$('pack-search')).focus({preventScroll:true});}
 if(members.length>packLimit){const more=el('button',`Show more images (${members.length-packLimit} remaining)`);more.onclick=()=>{const first=packLimit;packLimit+=60;renderPackMembers();$('pack-members').children[first]?.querySelector('.pack-member')?.focus({preventScroll:true});};$('pack-more').append(more);}
}
function syncPackMemberReviews(){
 for(const tile of document.querySelectorAll('#pack-members .pack-member')){
  const label=meta(get(tile.dataset.id)).review_label;let badge=tile.querySelector('.pack-member-review');
  if(!label){badge?.remove();continue;}
  if(!badge){badge=el('span',undefined,'pack-member-review');tile.append(badge);}badge.replaceChildren(reviewBadge(label));
 }
}
function openPack(e){
 if($('detail').open)$('detail').close();
 packEntry=get(e.id);packReturnFocus=document.activeElement;packLimit=60;packFilters=e.matching_member_ids?.length?copy(views.art):null;packSelection=null;
 $('pack-title').textContent=title(packEntry);$('pack-description').textContent=packEntry.description||'';$('pack-search').value='';
 const actions=$('pack-actions');actions.replaceChildren();const notes=el('button','Pack details & notes');notes.onclick=()=>openDetail(e.id);actions.append(notes);previewAction(packEntry,actions);
 packEditor.open(packEntry,$('pack-editor'));renderPackMembers();if(!$('pack-dialog').open)$('pack-dialog').showModal();$('pack-dialog').scrollTop=0;
}
function thumbnailNode(e,onClick,label=title(e)){
 const button=el('button',undefined,'image-button');button.setAttribute('aria-label','Preview '+label);button.onclick=onClick;
 const thumb=e.thumbnail,imageEntry=isPack(e)?get(e.cover):e;
 const animated=N.isClip(e)||isPack(e)&&e.preview||['model','video'].includes(e.preview?.kind);
 const imageURL=thumb?.status==='ready'?thumb.url:(!animated&&imageEntry.image&&!imageEntry.missing?imageEntry.url:null);
 if(imageURL){const img=el('img');img.src=imageURL;img.alt=label;img.loading='lazy';img.onerror=()=>{img.hidden=true;button.append(el('span','Thumbnail unavailable','asset-placeholder'));};button.append(img);}
 else button.append(el('span',e.missing?'Missing source':(N.isClip(e)||e.preview?'First-frame preview unavailable':A.types(e).join(' / ')),'asset-placeholder'));
 if(thumb?.status==='ready')button.append(el('span',thumb.empty?'First frame · empty / transparent':'First frame · 0.00 s','thumbnail-caption'));
 return button;
}
function renderCategoryCard(e){
 const card=el('article',undefined,'entry art animation-category'),cover=get(e.cover);card.dataset.id=e.id;
 card.append(thumbnailNode(cover,()=>openCategory(e.id),title(e)));
 const body=el('div',undefined,'art-card-body'),heading=el('h2'),button=el('button',title(e));button.onclick=()=>openCategory(e.id);heading.append(button);body.append(heading,el('p',`${e.matching_count} clips${e.unavailable_count?' · '+e.unavailable_count+' unavailable sources':''}`));
 const open=el('button','Open category','category-open');open.onclick=()=>openCategory(e.id);const notes=el('button','Category details','category-details');notes.onclick=()=>openDetail(e.id);body.append(open,notes);if(meta(e).review_label)body.append(reviewBadge(meta(e).review_label));for(const flag of meta(e).attention)body.append(el('span',flag,'badge warn'));card.append(body);return card;
}
function renderArtCard(e,m){
 if(N.isCategory(e)&&artMode==='models')return renderCategoryCard(e);
 const card=el('article',undefined,'entry art '+(views.art.layout==='list'?'art-list-row':''));card.dataset.id=e.id;
 const preview=thumbnailNode(e,()=>isPack(e)?openPack(e):openDetail(e.id));
 const body=el('div',undefined,'art-card-body');body.append(el('div',N.isClip(e)?'Model animation · '+(e.source_library||'Unknown library'):[...A.types(e),...A.collections(e)].join(' · '),'eyebrow'));
 const heading=el('h2'),open=el('button',title(e));open.onclick=()=>isPack(e)?openPack(e):openDetail(e.id);heading.append(open);body.append(heading);
 if(N.isClip(e)){
  const duration=e.source_clip?.duration;body.append(el('p',`${Number.isFinite(duration)?duration.toFixed(2)+' s':'Duration unavailable'} · ${e.rig||'Unknown rig'} · ${e.motion_mode||'Unknown'}`,'clip-info'));
  const tags=el('div',undefined,'animation-tags');for(const tag of N.labels(e,m).tags)tags.append(el('span',tag,'badge'));body.append(tags);
  animationReviewControls(e,body);
 }
 body.append(el('p',isPack(e)?`${e.members.length} images · Image pack`:e.path||e.id,'path'));
 if(e.thumbnail&&e.thumbnail.status!=='ready')body.append(el('p',e.thumbnail.reason||'First-frame thumbnail is not prepared.','clip-info'));
 if(isPack(e)){if(e.matching_member_ids?.length<e.members.length)body.append(el('p',e.matching_member_ids.length?`${e.matching_member_ids.length} matching images`:'Matched pack title, tags or notes','clip-info'));if(e.missing_count)body.append(el('span',`${e.missing_count} missing images`,'badge warn'));if(e.catalog_warning)body.append(el('p',e.catalog_warning,'note'));const packButton=el('button','Open pack','pack-open');packButton.onclick=()=>openPack(e);body.append(packButton);}
 const badges=el('div');for(const tag of m.art_tags)badges.append(el('span',tag,'badge art-tag'));if(m.review_label)badges.append(reviewBadge(m.review_label));badges.append(el('span',e.origin||'Saved metadata','badge'));if(e.role)badges.append(el('span',e.role,'badge'));if(m.status)badges.append(statusBadge(m.status));
 if(e.missing)badges.append(el('span','Missing source — notes retained','badge warn'));
 for(const flag of m.attention)badges.append(el('span',flag,'badge warn'));if(m.priority!=='Normal')badges.append(el('span',m.priority+' priority','badge'));
 body.append(badges);clipSummary(e,body);previewAction(e,body);if(m.checklist.length)body.append(progressNode(m));card.append(preview,body);return card;
}
function stateColor(node,value){node.classList.add('state-color');node.dataset.state=value?value.toLowerCase().replaceAll(' ','-'):'unset';return node;}
function reviewBadge(label){return stateColor(el('span',label,'badge review-'+label.toLowerCase()),label);}
function statusBadge(label){return stateColor(el('span',label,'badge'),label);}
function switchArtMode(mode){
 if(mode===artMode)return;review.clear();ArtPreview.close();if($('pack-dialog').open)$('pack-dialog').close();rememberPosition();artViews[artMode]=views.art;artMode=mode;views.art=artViews[mode];limit=views.art.limit;setupFilters();render();requestAnimationFrame(()=>window.scrollTo(0,views.art.scroll));
}
function openCategory(id){
 if($('detail').open)$('detail').close();views.art.overviewScroll=window.scrollY;views.art.category_id=id;limit=60;render();window.scrollTo(0,0);$('back-animation-categories')?.focus({preventScroll:true});rememberPosition();
}
function renderAnimationBreadcrumb(){
 const target=$('animation-breadcrumb');target.replaceChildren();if(book!=='art'||artMode!=='models'){target.hidden=true;return;}target.hidden=false;
 if(animationProjection?.category){const back=el('button','← Animation categories');back.id='back-animation-categories';back.onclick=()=>{const id=views.art.category_id;views.art.category_id='';limit=60;render();window.scrollTo(0,views.art.overviewScroll||0);[...document.querySelectorAll('.animation-category')].find(e=>e.dataset.id===id)?.querySelector('.category-open')?.focus({preventScroll:true});};target.append(back,el('strong',title(animationProjection.category)));}
 else target.append(el('p','Choose a category. A clip may belong to more than one category; the total counts it once.'));
}
function metric(title,value,caption){const n=el('div',undefined,'metric');n.append(el('div',title),el('strong',value),el('small',caption));return n;}
function renderSummary(filtered){const all=entries(),art=book==='art',saved=items();$('summary').replaceChildren();
 if(art&&artMode==='approved'){$('summary').append(metric('Approved work',filtered.length+' entries','Saved decisions · pack approval includes its images'));return;}
 if(art&&artMode==='scrap'){$('summary').append(metric('Scrap',all.filter(e=>meta(e).review_label==='Scrap').length+' items','Only confirmed selections move to Trash'),metric('Approved',all.filter(e=>meta(e).review_label==='Approved').length+' items','Protected from deletion'),metric('Project Trash',(state.trash?.hidden_ids?.length||0)+' entries','Recoverable files and catalog-only entries'));return;}
 if(art&&artMode==='duplicates'){$('summary').append(metric('Duplicate review',animationProjection.matchedClipCount+' compared motions',animationProjection.sourceClipCount+' source clips · no automatic deletion'),metric('Review safely','Compare, then choose','Notes and approval remain attached to each source'));return;}
 if(art&&artMode==='models'){$('summary').append(metric('Model animations',animationProjection.matchedClipCount+' motions',animationProjection.sourceClipCount+' source clips · '+animationProjection.unavailableFileCount+' unavailable sources'),metric('Browsing',animationProjection.category?title(animationProjection.category):'Category packs','Categories and tags are editable in details'),metric('Needs attention',String(N.modelEntries(all).filter(e=>meta(e).attention.length).length),'Clip flags stay separate from source files'));return;}
 if(art&&artMode==='ui'){$('summary').append(metric('UI animations',filtered.length+' entries','Documented sequences and videos · frames stay grouped'));return;}
 if(art){const files=fileEntries().filter(e=>!isPack(e)),packs=fileEntries().filter(isPack);$('summary').append(metric('Art Book',files.length+' files',packs.length+' image packs · original files retained'),metric('Current selection',artProjection?.matchedFileCount+' files',filtered.filter(isPack).length+' packs shown · '+filtered.filter(e=>!isPack(e)).length+' individual entries'),metric('Needs attention',String(all.filter(e=>meta(e).attention.length).length),'Separate flags for files and packs'));return;}
 const total=M.aggregate(all,saved),selected=M.aggregate(filtered,saved);
 $('summary').append(metric('Dev book · all work',progressLabel(total),`${total.assessed}/${total.count} features assessed · deferred work included`),metric('Current selection',progressLabel(selected),`${selected.assessed}/${selected.count} features assessed`),metric('Completed',`${all.filter(e=>meta(e).status==='Completed').length}/${all.length} features`,`${all.filter(e=>meta(e).attention.length).length} need attention`));
}
function completionHelp(m){
 const p=M.progress(m);
 if(!p.total)return 'To mark Completed, add at least one checklist task and check it after your review.';
 if(p.done<p.total)return `To mark Completed, finish the ${p.total-p.done} remaining checklist ${p.total-p.done===1?'task':'tasks'} (${p.done}/${p.total} checked).`;
 return m.status==='Completed'?'Completed · all checklist tasks are checked. Attention flags remain separate.':'All checklist tasks are checked. You can now mark this item Completed.';
}
function showCompletionChecklist(id){
 if(detailId!==id||!$('detail').open)openDetail(id);
 const target=document.querySelector('#detail .task-done:not(:checked)')||document.querySelector('#detail .add-task input');
 $('completion-guidance').scrollIntoView({block:'center'});
 target?.focus({preventScroll:true});
}
function requestCompletion(id){
 const e=get(id);if(!canEdit(e))return;const m=meta(e),p=M.progress(m);
 if(p.total&&p.done===p.total)change(id,{status:'Completed'});
 else showCompletionChecklist(id);
}
function statusSelect(e,m){
 const s=el('select',undefined,'state-bar');s.setAttribute('aria-label','Status for '+title(e));if(e.book==='art')s.add(new Option('Not set',''));for(const x of M.statuses)s.add(new Option(x,x));
 s.value=m.status;stateColor(s,m.status);s.disabled=!canEdit(e);
 s.onchange=()=>{const status=s.value;if(status==='Completed'){s.value=meta(e).status;requestCompletion(e.id);}else change(e.id,{status});};return s;
}
function render(){
 const f=currentFilters();persistView();let list;
 if(book==='art'){
  const dates=activity(),options={metadata:meta,activity:dates,indexes:artIndexes};
  if(artMode==='duplicates'){animationProjection=N.duplicateEntries(entries(),f,options);list=animationProjection.entries;}
  else if(artMode==='models'){animationProjection=N.project(entries(),(catalog.animation_categories||[]).filter(e=>!isTrashed(e)).map(e=>get(e.id)),f,options);list=animationProjection.entries;}
  else if(['scrap','approved'].includes(artMode)){list=A.sortEntries(entries().filter(e=>meta(e).review_label===(artMode==='scrap'?'Scrap':'Approved')&&A.filter(e,meta(e),f,dates.get(e.id))),f,options);}
  else if(artMode==='ui'){list=A.sortEntries(N.uiEntries(fileEntries()).filter(e=>A.filter(e,meta(e),f,dates.get(e.id))),f,options);}
  else{const art=fileEntries();artProjection=P.project(art.filter(e=>!isPack(e)),art.filter(isPack),f,options);list=artProjection.entries;}
  syncArtControls();
 }else list=D.sort(entries().filter(e=>D.filter(e,meta(e),f,activity().get(e.id))),f,{metadata:meta,activity:activity(),indexes:devIndexes});
 document.body.classList.toggle('art-book',book==='art');document.querySelector('h1').textContent=book==='dev'?'Dev book':'Art Book';$('book-description').textContent=book==='dev'?'Systems, gameplay and UI — from planned work to reviewed completion.':'Existing artistic work, source assets and references — organized in one place.';
 document.querySelectorAll('[data-book]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.book===book)));
 if(packEntry){$('pack-title').textContent=title(packEntry);packEditor.sync();syncPackMemberReviews();}renderSummary(list);renderAnimationBreadcrumb();if(book==='dev')renderDevNavigation();$('count').textContent=book==='art'&&artMode==='approved'?`${list.length} approved entries`:book==='art'&&artMode==='scrap'?`${list.length} scrapped items · ${Math.min(list.length,limit)} shown`:book==='art'&&artMode==='duplicates'?`${animationProjection.matchedClipCount} compared motions · ${animationProjection.sourceClipCount} source clips`:book==='art'&&artMode==='models'?`${animationProjection.matchedClipCount} motions · ${animationProjection.sourceClipCount} source clips · ${animationProjection.unavailableFileCount} unavailable sources${animationProjection.category?'':' · '+list.length+' category packs'}`:book==='art'&&artMode==='ui'?`${list.length} UI animation entries`:book==='art'?`${list.filter(isPack).length} packs + ${list.filter(e=>!isPack(e)).length} individual entries · ${artProjection.matchedFileCount} matching files`:`${list.length} features found${f.view==='recent'?' · newest changes first':''}`;
 $('results').className=book==='art'?(f.layout==='list'?'art-list':'art-grid'):'';$('results').replaceChildren();
 if(!list.length)$('results').append(el('p','No matching entries. Try clearing your filters.'));
 for(const e of list.slice(0,limit)){
  if(book==='art'){const card=renderArtCard(e,meta(e));const selection=packManager.selectionControl(e);if(selection)card.prepend(selection);if(artMode==='scrap')card.prepend(review.selectionControl(e));$('results').append(card);continue;}
  const m=meta(e),card=el('article',undefined,'entry '+(book==='art'?'art':'dev-row'));card.dataset.id=e.id;
  const body=el('div');body.append(el('div',book==='art'?e.kind:`${e.area} / ${e.topic}`,'eyebrow'));
  const h=el('h2'),open=el('button',title(e));open.onclick=()=>openDetail(e.id);h.append(open);body.append(h);
  body.append(el('p',e.summary||'Tracking retained; its catalog entry is unavailable.'));const tags=el('div',undefined,'dev-tags');for(const tag of D.tags(e)){const b=el('button',tag,'badge dev-tag');b.setAttribute('aria-label','Filter tag: '+tag);b.onclick=()=>setDevFilter('tag',tag);tags.append(b);}body.append(tags);
  if(e.missing)body.append(el('span','Missing source — notes retained','badge warn'));
  for(const flag of m.attention)body.append(el('span',flag,'badge warn'));
  if(m.priority!=='Normal')body.append(el('span',m.priority+' priority','badge'));
  card.append(body,progressNode(m));
  const quick=el('div',undefined,'quick'),label=el('label','Status');label.append(statusSelect(e,m));quick.append(label);
  const flags=el('button',m.attention.length?'Edit flags':'Add flag');flags.onclick=()=>{openDetail(e.id);document.querySelector('#detail-body .flags input')?.focus();};quick.append(flags);card.append(quick);$('results').append(card);
 }
 if(list.length>limit){const more=el('button',`Show more (${list.length-limit} remaining)`);more.onclick=()=>{limit+=60;rememberPosition();render();};$('results').append(more);}
 if(book==='art'&&artMode==='scrap')review.render(list,limit);
 $('import-button').disabled=!online||blocked||packWorking;$('migrate').disabled=!online||blocked||packWorking;packManager.sync();
}
function setDevFilter(key,value){
 const fromTag=document.activeElement?.classList.contains('dev-tag');views.dev[key]=views.dev[key]===value?'':value;if(key==='area'){views.dev.topic='';views.dev.tag='';}limit=60;setupFilters();render();persistView();if(fromTag)(document.querySelector('#active-dev-filters [aria-label="Remove Tag filter"]')||$('search')).focus({preventScroll:true});
}
function renderDevNavigation(){
 const all=entries('dev'),f=views.dev,saved=items(),chapters=$('dev-chapters'),topics=$('dev-topics');
 $('dev-navigation').classList.toggle('chapter-selected',!!f.area);
 const focused=document.activeElement,areaFocus=focused?.dataset.devArea,topicFocus=focused?.dataset.devTopic;chapters.replaceChildren();topics.replaceChildren();
 for(const area of ['', 'Systems','Gameplay','UI']){
  const rows=all.filter(e=>!area||e.area===area),p=M.aggregate(rows,saved),button=el('button',undefined,'dev-chapter');button.dataset.devArea=area;button.setAttribute('aria-pressed',String(f.area===area));button.append(el('strong',area||'All features'),el('span',rows.length+' features · '+p.assessed+'/'+p.count+' assessed'),el('small',progressLabel(p)));button.onclick=()=>setDevFilter('area',area);chapters.append(button);
 }
 const topicRows=all.filter(e=>!f.area||e.area===f.area);
 for(const topic of [...new Set(topicRows.map(e=>e.topic))].filter(Boolean).sort()){
  const rows=topicRows.filter(e=>e.topic===topic),p=M.aggregate(rows,saved),b=el('button',topic+' · '+rows.length,'topic-chip');b.dataset.devTopic=topic;b.setAttribute('aria-pressed',String(f.topic===topic));b.title=progressLabel(p)+' · '+p.assessed+'/'+p.count+' assessed';b.onclick=()=>setDevFilter('topic',topic);topics.append(b);
 }
 const target=$('active-dev-filters'),chipFocus=[...target.querySelectorAll('button')].indexOf(focused);target.replaceChildren();
 const names={search:'Search',view:'View',area:'Chapter',topic:'Topic',attention:'Attention',priority:'Priority',status:'Status',assessment:'Assessment',tag:'Tag'};
 for(const [key,label] of Object.entries(names)){if(!f[key]||(key==='view'&&f[key]==='all'))continue;const text=key==='assessment'?$('dev-assessment').selectedOptions[0]?.textContent:key==='view'?$('view').selectedOptions[0]?.textContent:f[key];const b=el('button',label+': '+text+' ×','filter-chip');b.setAttribute('aria-label','Remove '+label+' filter');b.onclick=()=>{f[key]=key==='view'?'all':'';if(key==='area')f.topic='';limit=60;setupFilters();render();};target.append(b);}
 if(!target.children.length)target.append(el('span','All features · choose a chapter, topic or search','muted'));
 if(areaFocus!==undefined)[...chapters.children].find(n=>n.dataset.devArea===areaFocus)?.focus({preventScroll:true});else if(topicFocus!==undefined)[...topics.children].find(n=>n.dataset.devTopic===topicFocus)?.focus({preventScroll:true});else if(chipFocus>=0)(target.querySelectorAll('button')[Math.min(chipFocus,target.children.length-1)]||$('search')).focus({preventScroll:true});
}
function blockedNotice(reason){const n=$('connection');n.hidden=false;n.replaceChildren(el('p',reason));const retry=el('button','Retry saving');retry.onclick=()=>{blocked=false;n.hidden=true;flush();};const reload=el('button','Reload project data');reload.onclick=()=>{if(!Object.keys(drafts).length||confirm('Discard unsaved edits and reload? Export a backup first to keep them.')){drafts=Object.create(null);blocked=false;connect();}};n.append(retry,reload);}
function change(id,patch){const e=get(id);if(!canEdit(e))return;
 // Stage the whole decision before exposing any draft. The existing PUT saves
 // all records atomically and rejects the entire batch on a revision conflict.
 const staged=Object.create(null),targets=[e,...(isPack(e)&&patch.review_label==='Approved'?[...new Set(e.members)].map(get):[])];
 try{for(const target of targets){if(!canEdit(target))throw Error('Cannot approve the whole pack: '+title(target)+' is not editable.');const next={...meta(target),...(target.id===id?patch:{review_label:'Approved'})};staged[target.id]=M.validateMeta(next,target.id);}}
 catch(err){message(err.message);packEditor.sync();updateDetailProgress();return;}
 if(!Object.keys(drafts).length)draftPackRevision=packManager.getRevision();
 Object.assign(drafts,staged);saveStatus('Unsaved changes');clearTimeout(timer);timer=setTimeout(flush,450);render();updateDetailProgress();
}
async function flush(){
 clearTimeout(timer);if(!online||blocked||saving||!Object.keys(drafts).length)return;
 const changes=copy(drafts);saving=true;saveStatus('Saving…');
 try{
  // Keep the membership revision from when these edits were staged, including
  // failed retries, so an old approval cannot silently target a changed pack.
  const payload=JSON.stringify({version:M.version,revision:state.revision,changes,...(draftPackRevision===null?{}:{pack_revision:draftPackRevision})});if(new Blob([payload]).size>64*1024*1024)throw Error('Pending edits exceed the 64 MiB save limit');
  const res=await fetch('/api/tracker',{method:'PUT',headers:{'Content-Type':'application/json'},body:payload});
  const data=await res.json();if(!res.ok)throw Error(['reload_required','pack_conflict'].includes(data.code)?data.error:res.status===409?'Another tab saved changes. Export your unsaved edits, then reload project data before merging.':data.error||'Save failed');
  state=data;for(const id of Object.keys(changes))if(JSON.stringify(drafts[id])===JSON.stringify(changes[id]))delete drafts[id];if(!Object.keys(drafts).length)draftPackRevision=null;
  saveStatus(Object.keys(drafts).length?'Unsaved changes':'Saved to project');
  if(!Object.keys(drafts).length&&pendingLegacy){try{localStorage.setItem('ashen-books-migrated-v1',pendingLegacy);}catch(e){}pendingLegacy=null;checkMigration();}
 }catch(err){blocked=true;saveStatus('Save failed',true);blockedNotice(err.message+' Your unsaved edits are still available to export.');}
 finally{saving=false;render();updateDetailProgress();if(!blocked&&Object.keys(drafts).length)timer=setTimeout(flush,50);}
}
async function connect(){
 online=false;saveStatus('Connecting…');
 try{if(!/^https?:$/.test(location.protocol))throw Error('Static copy');const res=await fetch('/api/tracker',{cache:'no-store'});if(!res.ok){let problem='Service unavailable';try{problem=(await res.json()).error||problem;}catch(e){}throw Error(problem);}const data=await res.json();if(data.version!==M.version||!data.items||!Array.isArray(data.history))throw Error('Unsupported service');state=data;online=true;blocked=false;$('connection').hidden=true;}
 catch(err){saveStatus('Read-only · service offline');$('connection').hidden=false;$('connection').replaceChildren(el('p','Read-only: '+err.message+'. Start the tracker service to edit: python3 tools/serve_progress_tracker.py --port 8765'));const retry=el('button','Reconnect');retry.onclick=connect;$('connection').append(retry);}
 await packManager.connect();setupFilters();render();if(detailId)openDetail(detailId);checkMigration();if(online)saveStatus('Saved to project');
}
async function preparePackChange(){
 while(saving)await new Promise(resolve=>setTimeout(resolve,25));
 if(Object.keys(drafts).length)await flush();
 if(!online||blocked||Object.keys(drafts).length)throw Error('Save your tracking edits successfully before changing packs. Your selection is kept.');
}
function installCatalog(next){
 Object.assign(catalog,next);
 allEntries.splice(0,allEntries.length,...next.features.map(e=>({...e,book:'dev'})),...[...next.art,...(next.packs||[]),...(next.animation_clips||[]),...(next.animation_categories||[])].map(e=>({...e,book:'art'})));
 index.clear();devIndexes.clear();artIndexes.clear();
 for(const e of allEntries){index.set(e.id,e);(e.book==='dev'?devIndexes:artIndexes).set(e.id,e.book==='dev'?D.indexEntry(e):A.indexEntry(e));}
 trashRef=null;
 if(packEntry){packEntry=get(packEntry.id);if(isPack(packEntry)){renderPackMembers();packEditor.sync();}else $('pack-dialog').close();}
 setupFilters();
}
function updateDetailProgress(){if(!detailId)return;const e=get(detailId),m=meta(e),n=$('detail-progress');if(!n)return;$('detail-title').textContent=title(e);$('detail-description').textContent=entryDescription(e);document.querySelectorAll('#detail-body input,#detail-body textarea,#detail-body select,#detail-body button').forEach(control=>{if(control.dataset.duplicateScrap){const source=get(control.dataset.duplicateScrap),parent=get(source.parent_id);control.disabled=!duplicateScrapEligibility(source).eligible||!canEdit(parent)||meta(parent).review_label==='Scrap';}else if(!control.hasAttribute('data-readonly-action'))control.disabled=!canEdit(e);});n.replaceChildren(progressNode(m));
 const status=$('detail-status');if(status){status.value=m.status;stateColor(status,m.status);status.disabled=!canEdit(e);}
 for(const id of ['detail-completion-help','completion-guidance'])if($(id))$(id).textContent=completionHelp(m);
 const reviewSelect=$('art-review-label');if(reviewSelect){reviewSelect.value=m.review_label;stateColor(reviewSelect,m.review_label);}
 if(isPack(e)&&$('approve-whole-pack')){const approved=e.members.filter(id=>meta(get(id)).review_label==='Approved').length;$('detail-pack-approval-count').textContent=`${approved}/${e.members.length} images approved`;$('approve-whole-pack').disabled=!canEdit(e)||(m.review_label==='Approved'&&approved===e.members.length);}
 if(m.checklist.length&&m.checklist.every(c=>c.done)&&!['Completed','Ready for review'].includes(m.status)){n.append(el('p','All checks are complete. Ready for review?'));const b=el('button','Mark Ready for review');b.disabled=!canEdit(e);b.onclick=()=>change(e.id,{status:'Ready for review'});n.append(b);}
 if(m.status!=='Completed'&&m.checklist.length&&m.checklist.every(c=>c.done)){const b=el('button','Mark Completed');b.id='mark-completed';b.disabled=!canEdit(e);b.onclick=()=>requestCompletion(e.id);n.append(b);}
}
function editChecklist(id,list){const m=meta(get(id));if(m.status==='Completed'&&(!list.length||list.some(c=>!c.done))){if(!confirm('This changes completed work. Reopen it as In progress?')){openDetail(id);return;}change(id,{checklist:list,status:'In progress'});}else change(id,{checklist:list});openDetail(id);}
function namingControls(e,body){
 const m=meta(e),section=el('section',undefined,'naming-controls');section.append(el('h3','Display name'));
 const form=el('form',undefined,'rename-form'),label=el('label','Rename display name'),input=el('input');input.id='display-name';input.value=title(e);input.maxLength=200;input.required=true;label.append(input);
 const save=el('button','Save name');save.type='submit';const reset=el('button','Reset to original name');reset.type='button';reset.onclick=()=>{change(e.id,{display_name:''});input.value=e.title;};
 form.onsubmit=event=>{event.preventDefault();const name=input.value.trim();if(name)change(e.id,{display_name:name===e.title?'':name});};form.append(label,save,reset);section.append(form,el('p','Catalog name: '+e.title,'path'));
 if(N.isClip(e)){section.append(el('p','Original clip: '+(e.source_clip?.name||'Unnamed')+' · Source: '+(e.path||e.parent_id),'path'));const parent=el('button','Source file details');parent.dataset.readonlyAction='true';parent.onclick=()=>openDetail(e.parent_id);section.append(parent);
  if(e.identity_editable===false)section.append(el('p',e.identity_reason||'Per-clip editing needs a unique, documented clip identity. You can edit the source file instead.','note'));
  const fields=el('div',undefined,'classification-fields'),labels=N.labels(e,m);
  for(const [key,heading,values,current] of [['animation_categories','Categories',catalog.animation_taxonomy?.categories||[],labels.categories],['animation_tags','Tags',catalog.animation_taxonomy?.tags||[],labels.tags]]){
   const field=el('fieldset');field.append(el('legend',heading));for(const value of values){const l=el('label',undefined,'checklabel'),c=el('input');c.type='checkbox';c.checked=current.includes(value);c.dataset.classification=key;c.value=value;c.onchange=()=>{const selected=[...field.querySelectorAll('input:checked')].map(n=>n.value);change(e.id,{[key]:selected});buildArtFilters();syncArtControls();};l.append(c,document.createTextNode(value));field.append(l);}fields.append(field);
  }
  const resetLabels=el('button','Reset to catalog classification');resetLabels.onclick=()=>{change(e.id,{animation_categories:null,animation_tags:null});buildArtFilters();openDetail(e.id);};section.append(fields,resetLabels,el('p','Categories and tags apply only to this clip. Empty categories appear under Unclassified.','path'));
 }
 if(N.isCategory(e)){section.append(el('p','Category notes and display names do not change the clips inside.','note'));const open=el('button','Open category');open.dataset.readonlyAction='true';open.onclick=()=>{if(book!=='art'){book='art';setupFilters();}switchArtMode('models');openCategory(e.id);};section.append(open);}
 body.append(section);
}
function entryDescription(e){
 const documented=[e.description,e.summary].find(value=>typeof value==='string'&&value.trim());
 let text=documented?.replace(/\s+/g,' ').trim();
 if(!text){
  if(N.isClip(e))text=`Animation clip “${e.source_clip?.name||'Unnamed'}” from ${e.parent_title||'its source file'}${e.source_library?' · '+e.source_library:''}.`;
  else if(N.isCategory(e))text='Model animation collection. Each clip keeps its own notes and review decision.';
  else if(isPack(e))text=`Image pack with ${e.members.length} individual files. Each image keeps its own notes and review decision.`;
  else{
   const kind=({'Interactive previews':'Interactive preview',Images:'Image',Textures:'Texture',Models:'3D model',Animations:'Animation asset',Videos:'Video','Design documents':'Design document','Maps & scenes':'Map or scene',Lore:'Lore document'})[e.kind]||e.kind||'Catalog entry';
   const extension=(e.path||'').match(/\.([a-z0-9]+)$/i)?.[1].toUpperCase();
   text=[kind,...A.collections(e),extension?extension+' file':'',e.origin].filter(Boolean).join(' · ')+'.';
  }
 }
 const brief=text.length>260?text.slice(0,257).replace(/\s+\S*$/,'')+'…':text;
 return brief+(e.missing?' Source unavailable; saved notes are retained.':'');
}
function relatedFeatureControls(e,body){
 if(relatedSearch.id!==e.id)relatedSearch={id:e.id,query:''};
 const section=el('section',undefined,'related-features'),heading=el('h3','Related features');heading.id='related-features-heading';
 section.setAttribute('aria-labelledby',heading.id);
 const toolbar=el('div',undefined,'relation-search'),label=el('label','Search related features'),search=el('input');
 search.type='search';search.id='related-feature-search';search.placeholder='Name, topic, tags or description…';search.value=relatedSearch.query;search.dataset.readonlyAction='true';
 search.setAttribute('aria-controls','related-feature-list');search.setAttribute('aria-describedby','related-feature-count');label.append(search);
 const clear=el('button','Clear search');clear.type='button';clear.dataset.readonlyAction='true';
 const count=el('p',undefined,'path');count.id='related-feature-count';count.setAttribute('role','status');
 const relations=el('div',undefined,'relation-list');relations.id='related-feature-list';
 const empty=el('p','No matching features. Try another word or clear the search.');empty.hidden=true;
 const rows=catalog.features.map(feature=>{
  const l=el('label',undefined,'checklabel'),c=el('input');c.type='checkbox';c.checked=meta(e).related.includes(feature.id);c.disabled=!canEdit(e);
  c.onchange=()=>{const ids=new Set(meta(e).related);c.checked?ids.add(feature.id):ids.delete(feature.id);change(e.id,{related:[...ids]});filter();};
  l.append(c,document.createTextNode(title(get(feature.id))));relations.append(l);return {feature,label:l};
 });
 function filter(){
  const filters={...D.defaults(),search:search.value};let found=0;
  for(const row of rows){row.label.hidden=!D.filter(row.feature,meta(get(row.feature.id)),filters);if(!row.label.hidden)found++;}
  count.textContent=`${found} of ${rows.length} features · ${meta(e).related.length} selected in total`;
  empty.hidden=found>0;clear.hidden=!search.value;relatedSearch.query=search.value;
 }
 search.oninput=filter;clear.onclick=()=>{search.value='';filter();search.focus();};
 relations.append(empty);toolbar.append(label,clear);section.append(heading,toolbar,count,relations);body.append(section);filter();
}
function resolveDetailPack(e,context){
 if(context===undefined&&detailId===e.id&&detailPack)context=detailPack;
 if(context===undefined){
  const pack=isPack(e)?e:packEntry?.members.includes(e.id)?get(packEntry.id):allEntries.find(p=>isPack(p)&&!isTrashed(p)&&p.members.includes(e.id));
  context=pack?{packId:pack.id,ids:packEntry?.id===pack.id&&$('pack-dialog').open?[...packVisibleIds]:[...pack.members]}:null;
 }
 if(!context)return null;
 const pack=get(context.packId);if(!isPack(pack)||isTrashed(pack))return null;
 const ids=[...new Set(context.ids)].filter(id=>pack.members.includes(id)&&!isTrashed(get(id)));
 if(!ids.length||!isPack(e)&&!ids.includes(e.id))return null;
 return {packId:pack.id,ids,current:isPack(e)?(ids.includes(e.cover)?e.cover:ids[0]):e.id};
}
function movePackImage(offset,focusId){
 if(!detailPack)return;
 const next=detailPack.ids[detailPack.ids.indexOf(detailPack.current)+offset];if(!next)return;
 const context=detailPack;openDetail(next,context);$('detail').scrollTop=0;
 const control=$(focusId);(control&&!control.disabled?control:$('pack-image-navigation')).focus({preventScroll:true});
}
function packImageControls(e,body){
 if(!detailPack)return;
 const context=detailPack,position=context.ids.indexOf(context.current),nav=el('div',undefined,'pack-image-navigation');
 nav.id='pack-image-navigation';nav.tabIndex=-1;nav.setAttribute('role','group');nav.setAttribute('aria-label','Image pack navigation');
 const previous=el('button','← Previous image'),next=el('button','Next image →'),count=el('span',`Image ${position+1} of ${context.ids.length}`);
 previous.id='previous-pack-image';next.id='next-pack-image';count.id='pack-image-position';count.setAttribute('role','status');
 for(const [button,offset,label] of [[previous,-1,'Previous image'],[next,1,'Next image']]){button.type='button';button.dataset.readonlyAction='true';button.setAttribute('aria-label',label);button.onclick=()=>movePackImage(offset,button.id);}
 previous.disabled=position===0;next.disabled=position===context.ids.length-1;nav.append(previous,count,next);body.append(nav);
 if(isPack(e)){
  const row=el('div',undefined,'pack-image-context'),details=el('button','Image details');details.id='pack-image-details';details.dataset.readonlyAction='true';
  details.onclick=()=>movePackImage(0,'pack-image-details');row.append(el('p','Preview: '+title(get(context.current))+'. Notes below apply to the pack.','path'),details);body.append(row);
 }else body.append(el('p','From '+title(get(context.packId))+' · Notes and review decisions apply to this image.','path'));
}
function artTagVocabulary(){
 const tags=new Map(M.artTagSuggestions.map(tag=>[M.artTagKey(tag),tag]));
 for(const value of Object.values(items()))for(const tag of value.art_tags||[])if(!tags.has(M.artTagKey(tag)))tags.set(M.artTagKey(tag),tag);
 return [...tags.values()].sort((a,b)=>a.localeCompare(b,undefined,{sensitivity:'base'}));
}
function artTagControls(e,body){
 const section=el('section',undefined,'art-tag-editor');section.setAttribute('aria-label','Art tags');
 section.append(el('h3','Tags'),el('p',isPack(e)?'Tags describe this pack. Tag individual images in Image details to find them separately.':'Choose topic tags or add your own. Tags are saved automatically and included in search.','path'));
 const choices=el('div',undefined,'art-tag-choices'),assigned=el('div',undefined,'art-tag-assigned'),form=el('form',undefined,'art-tag-form');
 const label=el('label','Add custom tag'),input=el('input'),suggestions=el('datalist'),add=el('button','Add tag'),notice=el('p',undefined,'path');
 input.id='art-tag-input';input.setAttribute('list','art-tag-suggestions');input.placeholder='Type a new tag or choose an existing one';input.maxLength=120;input.autocomplete='off';input.required=true;
 suggestions.id='art-tag-suggestions';notice.id='art-tag-message';notice.setAttribute('role','status');input.setAttribute('aria-describedby',notice.id);
 add.type='submit';label.append(input);form.append(label,add);section.append(choices,assigned,form,suggestions,notice);body.append(section);
 function setTags(tags){
  try{const next=M.validateMeta({...meta(e),art_tags:tags},e.id);change(e.id,{art_tags:next.art_tags});buildArtFilters();sync();return true;}
  catch(error){notice.textContent=error.message;return false;}
 }
 function sync(){
  const tags=meta(e).art_tags;choices.replaceChildren();assigned.replaceChildren();
  for(const tag of M.artTagSuggestions){const option=el('label',undefined,'checklabel'),check=el('input');check.type='checkbox';check.checked=tags.some(t=>M.artTagKey(t)===M.artTagKey(tag));check.disabled=!canEdit(e);
   check.onchange=()=>{notice.textContent='';setTags(check.checked?[...meta(e).art_tags,tag]:meta(e).art_tags.filter(t=>M.artTagKey(t)!==M.artTagKey(tag)));choices.querySelectorAll('input')[M.artTagSuggestions.indexOf(tag)]?.focus();};option.append(check,document.createTextNode(tag));choices.append(option);
  }
  for(const tag of tags){const remove=el('button',tag+' ×','badge art-tag');remove.type='button';remove.setAttribute('aria-label','Remove tag '+tag);remove.disabled=!canEdit(e);remove.onclick=()=>{if(setTags(meta(e).art_tags.filter(t=>t!==tag)))input.focus();};assigned.append(remove);}
  suggestions.replaceChildren(...artTagVocabulary().map(tag=>new Option(tag,tag)));input.disabled=add.disabled=!canEdit(e);
 }
 form.onsubmit=event=>{event.preventDefault();if(!canEdit(e))return;try{
  let tag=M.normalizeArtTag(input.value);tag=artTagVocabulary().find(t=>M.artTagKey(t)===M.artTagKey(tag))||tag;
  if(meta(e).art_tags.some(t=>M.artTagKey(t)===M.artTagKey(tag))){notice.textContent='This entry already has that tag.';return;}
  if(setTags([...meta(e).art_tags,tag])){notice.textContent='Added '+tag+'.';input.value='';input.focus();}
 }catch(error){notice.textContent=error.message;}};
 sync();
}
function openDetail(id,context){
 if(detailId&&detailId!==id){const name=$('display-name'),task=document.querySelector('#detail .add-task input');detailFormDrafts.set(detailId,{name:name&&name.value!==title(get(detailId))?name.value:null,task:task?.value||''});}
 const e=get(id);detailPack=resolveDetailPack(e,context);detailId=id;const m=meta(e),body=$('detail-body');$('detail-title').textContent=title(e);body.replaceChildren();
 packImageControls(e,body);
 const imageEntry=isPack(e)&&detailPack?get(detailPack.current):e;
 if(imageEntry.book==='art'&&imageEntry.image&&!imageEntry.missing){const img=el('img',undefined,'large-preview');img.src=imageEntry.url;img.alt=title(imageEntry);img.onerror=()=>img.replaceWith(el('p','Image unavailable — notes are retained.','asset-placeholder'));body.append(img);}
 else if(detailPack)body.append(el('p','Image unavailable — notes are retained.','asset-placeholder'));
 if(isPack(e)){body.append(el('p',`${e.members.length} images. Pack notes and flags do not change the individual images.`,'note'));const packButton=el('button','Open pack');packButton.dataset.readonlyAction='true';packButton.onclick=()=>{if($('pack-dialog').open)$('detail').close();else openPack(e);};body.append(packButton);}
 if(e.catalog_warning)body.append(el('p',e.catalog_warning,'note'));
 if(e.book==='art'&&!isPack(e)){const parents=allEntries.filter(p=>isPack(p)&&!isTrashed(p)&&p.members.includes(e.id));for(const parent of parents){const link=el('button','In pack: '+title(parent));link.dataset.readonlyAction='true';link.onclick=()=>{if(packEntry?.id===parent.id)$('detail').close();else openPack(parent);};body.append(link);}}
 if(e.missing)body.append(el('p','Source is missing from the latest catalog. Your saved metadata is retained.','note'));
 if(e.book==='art'){const label=el('label','Art review decision'),select=el('select');select.id='art-review-label';select.classList.add('state-bar');stateColor(select,m.review_label);select.add(new Option('Not decided',''));for(const value of M.reviewLabels)select.add(new Option(value,value));select.value=m.review_label;select.onchange=()=>change(e.id,{review_label:select.value});label.append(select);body.append(label,el('p',isPack(e)?'Approved also approves every image in this pack, including hidden search results. Scrap and Not decided change only the pack. Notes, tags and completion stay separate.':'Approved protects work. Scrap queues it for the separate deletion confirmation. These labels do not change completion or source files.','path'));
  if(isPack(e)){const approve=el('button','Approve whole pack'),count=el('p',undefined,'path');approve.id='approve-whole-pack';approve.onclick=()=>change(e.id,{review_label:'Approved'});count.id='detail-pack-approval-count';count.setAttribute('role','status');body.append(approve,count);}namingControls(e,body);artTagControls(e,body);}
 if(e.book==='art'){body.append(el('p',[...A.types(e),...A.collections(e)].join(' · ')));clipSummary(e,body,true);previewAction(e,body);if(e.modified_at)body.append(el('p',(isPack(e)?'Latest member modified: ':'File modified: ')+new Date(e.modified_at).toLocaleString(),'path'));}
 animationReviewControls(e,body,true);
 if(e.summary){if(e.book==='dev')body.append(el('h3','Overview'));body.append(el('p',e.summary));}
 if(e.book==='dev'){body.append(el('h3','Documented implementation'),el('p',(e.status||'Unavailable')+' · '+(e.attention||'No recorded attention'),'note'),el('p','This describes source evidence. Your tracking status and checklist are recorded separately.','path'));if(e.note)body.append(el('h3','Implementation notes & known limits'),el('p',e.note));const tags=el('p');for(const tag of D.tags(e))tags.append(el('span',tag,'badge'));body.append(tags);}
 const sources=el('details');sources.append(el('summary','Source evidence'));for(const p of e.sources||[e.path].filter(Boolean)){const line=el('p');line.append(sourceLink(p,p));sources.append(line);}body.append(sources);
 const grid=el('div',undefined,'edit-grid'),status=el('label','Tracking status'),select=statusSelect(e,m);select.id='detail-status';select.setAttribute('aria-describedby','detail-completion-help');const statusHelp=el('small',completionHelp(m),'path');statusHelp.id='detail-completion-help';status.append(select,statusHelp);
 const priority=el('label','Priority'),ps=el('select');M.priorities.forEach(p=>ps.add(new Option(p,p)));ps.value=m.priority;ps.disabled=!online||blocked;ps.onchange=()=>change(id,{priority:ps.value});priority.append(ps);grid.append(status,priority);body.append(grid);
 body.append(el('h3','Attention'));const flags=el('div',undefined,'flags');for(const flag of M.attentions){const l=el('label',undefined,'checklabel'),c=el('input');c.type='checkbox';c.checked=m.attention.includes(flag);c.disabled=!online||blocked;c.onchange=()=>{const a=new Set(meta(e).attention);c.checked?a.add(flag):a.delete(flag);change(id,{attention:[...a]});};l.append(c,document.createTextNode(flag));flags.append(l);}body.append(flags);
 body.append(el('h3','Completion checklist'));const guidance=el('p',completionHelp(m),'note');guidance.id='completion-guidance';guidance.setAttribute('role','status');body.append(guidance);const p=el('div');p.id='detail-progress';body.append(p);
 if(!m.checklist.length)body.append(el('p','Not assessed. Add tasks from an existing acceptance criterion or your own review; none will be assumed complete.'));
 for(const task of m.checklist){
  const row=el('div',undefined,'task'),done=el('input',undefined,'task-done');done.type='checkbox';done.checked=task.done;done.setAttribute('aria-label','Complete '+task.text);done.disabled=!online||blocked;done.onchange=()=>editChecklist(id,meta(e).checklist.map(c=>c.id===task.id?{...c,done:done.checked}:c));
  const content=el('div'),text=el('input');text.type='text';text.value=task.text;text.maxLength=2000;text.setAttribute('aria-label','Task text');text.disabled=!online||blocked;text.onchange=()=>editChecklist(id,meta(e).checklist.map(c=>c.id===task.id?{...c,text:text.value.trim(),done:false,source:''}:c));content.append(text);
  if(task.source)content.append(sourceLink('Acceptance source ↗',task.source));else content.append(el('small','User-authored task'));
  const remove=el('button','Remove');remove.disabled=!online||blocked;remove.onclick=()=>{if(confirm('Remove this checklist task?'))editChecklist(id,meta(e).checklist.filter(c=>c.id!==task.id));};row.append(done,content,remove);body.append(row);
 }
 const add=el('form',undefined,'add-task'),input=el('input');input.placeholder='Add a checklist task…';input.setAttribute('aria-label','New checklist task');input.maxLength=2000;input.required=true;input.disabled=!online||blocked;const button=el('button','Add task');button.type='submit';button.disabled=!online||blocked;add.append(input,button);add.onsubmit=ev=>{ev.preventDefault();if(!input.value.trim())return;editChecklist(id,[...meta(e).checklist,{id:'task-'+(crypto.randomUUID?crypto.randomUUID():Date.now()+'-'+Math.random().toString(16).slice(2)),text:input.value.trim(),done:false,source:''}]);};body.append(add);
 const notes=el('label','Notes'),area=el('textarea');area.id='entry-notes';area.maxLength=10000;area.value=m.note;area.disabled=!online||blocked;area.oninput=()=>change(id,{note:area.value});notes.append(area);body.append(el('h3','Your notes'),notes);
 if(e.book==='art'){
  relatedFeatureControls(e,body);
 }else{
  body.append(el('h3','Related art'));const linked=entries('art').filter(a=>meta(a).related.includes(id));if(!linked.length)body.append(el('p','No links yet. Link existing artwork from its Art Book entry.'));for(const a of linked){const b=el('button',title(a));b.onclick=()=>openDetail(a.id);body.append(b);}
 }
 const history=state.history.filter(h=>h.id===id);if(history.length){body.append(el('h3','Recent changes'));history.slice(-5).reverse().forEach(h=>body.append(historyNode(h)));}
 const pending=detailFormDrafts.get(id);if(pending){if(pending.name!==null&&$('display-name'))$('display-name').value=pending.name;input.value=pending.task;detailFormDrafts.delete(id);}
 updateDetailProgress();if(!$('detail').open)$('detail').showModal();
}
function historyNode(h){const n=el('div',undefined,'history-event'),time=el('time',new Date(h.at).toLocaleString());time.dateTime=h.at;n.append(time,el('div',title(get(h.id))),el('p',(h.fields||[]).map(f=>({display_name:'Display name',animation_categories:'Categories',animation_tags:'Animation tags',art_tags:'Tags',review_label:'Art review decision'}[f]||f)).join(', ')));return n;}
function showHistory(amount=200){if(typeof amount!=='number')amount=200;const target=$('activity-body');target.replaceChildren();if(!state.history.length)target.append(el('p','No project changes recorded yet.'));for(const h of [...state.history].reverse().slice(0,amount))target.append(historyNode(h));if(state.history.length>amount){const more=el('button','Show more activity');more.onclick=()=>showHistory(amount+200);target.append(more);}if(!$('activity').open)$('activity').showModal();}
function describeTracking(m){return ['Tags: '+((m.art_tags||[]).join(', ')||'None'),'Art review decision: '+(m.review_label||'Not decided'),'Display name: '+(m.display_name||'Catalog default'),'Categories: '+(m.animation_categories===null?'Catalog default':(m.animation_categories||[]).join(', ')),'Tags: '+(m.animation_tags===null?'Catalog default':(m.animation_tags||[]).join(', ')),'Status: '+(m.status||'Not set'),'Attention: '+(m.attention.join(', ')||'None'),'Priority: '+m.priority,'Progress: '+progressLabel(M.progress(m)),'Notes: '+(m.note||'—'),'Checklist:',...m.checklist.map(c=>(c.done?'☑ ':'☐ ')+c.text),'Related features: '+(m.related.map(id=>get(id).title).join(', ')||'None')].join('\n');}
function previewImport(data){
 if(!online||blocked){message('Connect to the tracker service before importing.');return;}
 try{const changes=M.importChanges(data,allEntries,items());if(new Blob([JSON.stringify({version:M.version,revision:state.revision,changes})]).size>64*1024*1024)throw Error('Imported metadata exceeds the 64 MiB save limit');importDraft=changes;importLegacy=null;try{const old=JSON.parse(localStorage.getItem(OLD_KEY)||'null');if(data.version===1&&JSON.stringify(old)===JSON.stringify(data.tracking))importLegacy=JSON.stringify(old);}catch(e){}const body=$('preview-body');body.replaceChildren(el('p',Object.keys(changes).length+' records to merge. '+(data.hasUnsavedEdits?'Recovering unsaved entries only; unrelated newer project records will be kept. ':'')+'Unknown IDs are retained as missing catalog entries. Existing project history is preserved; imported edits create new activity. The backup retains its original timeline.'));
 for(const [id,m] of Object.entries(changes)){const n=el('div',undefined,'import-item');n.append(el('strong',title(get(id))),el('p',`${m.status||'No status'} · ${progressLabel(M.progress(m))} · ${m.attention.join(', ')||'No attention flags'}`));const details=el('details');details.append(el('summary','Compare current and imported tracking'),el('pre','CURRENT\n'+describeTracking(meta(get(id)))+'\n\nIMPORTED\n'+describeTracking(m)));n.append(details);body.append(n);}
 $('confirm-import').disabled=!Object.keys(changes).length;if(!$('preview').open)$('preview').showModal();
 }catch(err){message('Import rejected: '+err.message);}
}
function checkMigration(){try{const old=localStorage.getItem(OLD_KEY);const migrated=old&&localStorage.getItem('ashen-books-migrated-v1')===JSON.stringify(JSON.parse(old));$('migration').hidden=!online||!old||migrated||sessionStorage.getItem('ashen-migration-dismissed')==='yes';}catch(e){}}
function exportBackup(){const data={...state,items:items(),exportedAt:new Date().toISOString(),hasUnsavedEdits:!!Object.keys(drafts).length,pendingChanges:copy(drafts)};const url=URL.createObjectURL(new Blob([JSON.stringify(data,null,2)],{type:'application/json'}));const a=el('a');a.href=url;a.download='ashen-tracking-v'+M.version+'.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}
for(const b of document.querySelectorAll('[data-book]'))b.onclick=()=>{if(book===b.dataset.book)return;ArtPreview.close();if($('pack-dialog').open)$('pack-dialog').close();rememberPosition();book=b.dataset.book;limit=views[book].limit;setupFilters();render();requestAnimationFrame(()=>window.scrollTo(0,views[book].scroll));};
for(const id of ['search','view','area','topic','attention','priority'])$(id).addEventListener(id==='search'?'input':'change',()=>{if(book==='art'&&id==='view'&&$('view').value==='recent')views.art.sort='recent';if(book==='dev'&&id==='view'&&$('view').value==='recent')$('dev-sort').value='recent';if(book==='dev'&&id==='area'){views[book].area=$('area').value;views[book].topic='';setupTopics();}limit=60;currentFilters();render();rememberPosition();});
for(const key of ['status','assessment','tag','sort'])$('dev-'+key).onchange=()=>{limit=60;currentFilters();render();persistView();};
$('clear-filters').onclick=clearFilters;$('clear-art-sidebar').onclick=clearFilters;
$('show-duplicate-sources').onchange=()=>{views.art.showDuplicateSources=$('show-duplicate-sources').checked;artFilterChanged();};
$('show-individual-images').onchange=()=>{views.art.individualImages=$('show-individual-images').checked;artFilterChanged();};
$('pack-search').oninput=()=>{packLimit=60;renderPackMembers();};
$('close-pack').onclick=()=>$('pack-dialog').close();
$('pack-dialog').addEventListener('close',()=>{const id=packEntry?.id;packEntry=null;packSelection=null;packFilters=null;packVisibleIds=[];packEditor.clear();$('pack-members').replaceChildren();if(document.activeElement?.matches('input,textarea,select'))return;const target=packReturnFocus?.isConnected&&packReturnFocus.getClientRects().length?packReturnFocus:[...document.querySelectorAll('#results .entry')].find(e=>e.dataset.id===id)?.querySelector('button');(target||$('search')).focus({preventScroll:true});});
document.querySelectorAll('[data-art-mode]').forEach(b=>b.onclick=()=>switchArtMode(b.dataset.artMode));
$('art-sort').onchange=()=>{views.art.sort=$('art-sort').value;artFilterChanged();};
document.querySelectorAll('[data-layout]').forEach(b=>b.onclick=()=>{views.art.layout=b.dataset.layout;syncArtControls();render();persistView();});
document.querySelectorAll('[data-shortcut]').forEach(b=>b.onclick=()=>{const value=b.dataset.shortcut;if(value==='Animations'&&artMode!=='files'){switchArtMode('models');return;}const key=value==='UI'?'collections':'types';views.art[key]=views.art[key].includes(value)?views.art[key].filter(x=>x!==value):[...views.art[key],value];artFilterChanged();});
$('open-art-filters').onclick=()=>{$('art-filter-dialog').append($('art-sidebar'));$('art-filter-dialog').showModal();};
$('close-art-filters').onclick=()=>$('art-filter-dialog').close();
$('art-filter-dialog').addEventListener('close',()=>{$('book-layout').prepend($('art-sidebar'));$('open-art-filters').focus();});
window.matchMedia('(min-width: 901px)').addEventListener('change',event=>{if(event.matches&&$('art-filter-dialog').open)$('art-filter-dialog').close();});
$('detail').addEventListener('keydown',event=>{
 if(!detailPack||event.defaultPrevented||event.altKey||event.ctrlKey||event.metaKey||event.shiftKey||event.target.closest('input,textarea,select,[contenteditable]:not([contenteditable="false"])'))return;
 if(event.key==='ArrowLeft'||event.key==='ArrowRight'){event.preventDefault();movePackImage(event.key==='ArrowLeft'?-1:1,event.key==='ArrowLeft'?'previous-pack-image':'next-pack-image');}
});
$('close-detail').onclick=()=>$('detail').close();$('detail').addEventListener('close',()=>{detailId=null;detailPack=null;detailFormDrafts.clear();flush();if(packEntry)renderPackMembers();});
$('history').onclick=showHistory;$('close-activity').onclick=()=>$('activity').close();
$('export').onclick=exportBackup;$('import-button').onclick=()=>$('import').click();
$('import').onchange=async e=>{try{const file=e.target.files[0];if(!file)return;if(file.size>72*1024*1024)throw Error('Backup exceeds 72 MiB');previewImport(JSON.parse(await file.text()));}catch(err){message('Import rejected: '+err.message);}finally{e.target.value='';}};
$('cancel-import').onclick=()=>{$('preview').close();importDraft=null;};
$('confirm-import').onclick=()=>{if(!importDraft||!online||blocked)return;if(!Object.keys(drafts).length)draftPackRevision=packManager.getRevision();Object.assign(drafts,importDraft);pendingLegacy=importLegacy;importLegacy=null;importDraft=null;$('preview').close();render();flush();};
$('migrate').onclick=()=>{try{previewImport({version:1,tracking:JSON.parse(localStorage.getItem(OLD_KEY)||'{}')});}catch(err){message('Previous notes could not be read: '+err.message);}};
$('dismiss-migration').onclick=()=>{try{sessionStorage.setItem('ashen-migration-dismissed','yes');}catch(e){}$('migration').hidden=true;};
window.addEventListener('beforeunload',e=>{rememberPosition();if(Object.keys(drafts).length||saving||packWorking){e.preventDefault();e.returnValue='';}});
let scrollTimer;window.addEventListener('scroll',()=>{clearTimeout(scrollTimer);scrollTimer=setTimeout(rememberPosition,150);},{passive:true});
const review=R.create({state:()=>state,ready:()=>online&&!blocked&&!saving&&!Object.keys(drafts).length,title,get,onBusy:value=>{reviewWorking=value;updateDetailProgress();},accept:next=>{state=next;},render,refresh:connect});
const packManager=window.PackManager.create({get,title,editable:()=>online&&!blocked&&!reviewWorking,prepare:preparePackChange,onBusy:value=>{packWorking=value;render();updateDetailProgress();},installCatalog,render,view:()=>({book,mode:artMode,individual:views.art.individualImages}),setIndividual:value=>{views.art.individualImages=value;syncArtControls();persistView();},openPack,isImage:e=>e.book==='art'&&e.image&&!isPack(e)&&!N.isClip(e)&&!e.missing&&!isTrashed(e)});
const packEditor=window.PackEditor.create({get,meta,title,canEdit,change});
setupFilters();render();connect().then(()=>{limit=views[book].limit;render();requestAnimationFrame(()=>window.scrollTo(0,views[book].scroll));});
