const assert=require('node:assert/strict');
const M=require('../docs/tracker/model.js');
const versionThree=v=>Object.fromEntries(Object.entries(v).filter(([key])=>!['review_label','art_tags'].includes(key)));
const legacy=v=>Object.fromEntries(['status','attention','priority','note','checklist','related'].map(k=>[k,M.copy(v[k])]));
const feature={id:'walk',status:'Implemented',attention:'Bug correction',checklist:[{id:'a',text:'Check walking',done:false,source:'docs/CRAWLING.md'}]};
let v=M.defaults(feature);assert.equal(v.status,'Ready for review');assert.deepEqual(v.attention,['Bug found']);
assert.equal(M.defaults({id:'art:1'}).status,'');assert.equal(M.progress(M.defaults({id:'none'})).percent,null);
assert.throws(()=>M.validateMeta({...v,status:'Completed'}));v.checklist[0].done=true;v.status='Completed';M.validateMeta(v);assert.deepEqual(v.attention,['Bug found']);
const entries=[feature,{id:'two',status:'Partial'},{id:'deferred',status:'Planned',checklist:[{id:'b',text:'B',done:false,source:''}]}];
let agg=M.aggregate(entries,{walk:v,deferred:{...M.defaults(entries[2]),status:'Deferred'}});
assert.deepEqual(agg,{total:2,done:1,assessed:2,count:3,percent:50});assert.equal(M.aggregate([],{}).percent,null);
const many={checklist:Array.from({length:200},(_,i)=>({done:i<199}))};assert.equal(M.progress(many).percent,99);
let migrated=M.importChanges({version:1,tracking:{walk:{review:'Reviewed',note:'Keep me'},old:{review:'Bug found',note:'Missing'}}},entries,{});
assert.equal(migrated.walk.status,'Ready for review');assert.match(migrated.walk.note,/Keep me/);assert.match(migrated.walk.note,/Reviewed/);assert.equal(migrated.old.note.split('\n')[0],'Missing');assert.ok(migrated.old.attention.includes('Bug found'));
assert.equal(M.importChanges({version:1,tracking:{walk:{review:'Reviewed',note:'a'.repeat(10000)}}},entries,{}).walk.note.length,10000);
assert.throws(()=>M.importChanges({version:7,items:{}},entries,{}));assert.throws(()=>M.importChanges({version:2,items:{walk:{...legacy(v),status:'Invalid'}}},entries,{}));
assert.throws(()=>M.validateMeta({...v,checklist:[{id:'z',text:'Z',source:'../secret',done:true}]}));
assert.throws(()=>M.validateMeta({...v,checklist:[v.checklist[0],v.checklist[0]]}));
assert.deepEqual(feature.checklist[0].done,false,'Defaults must not mutate evidence');
const recovery=M.importChanges({version:2,hasUnsavedEdits:true,items:{walk:legacy(v)},pendingChanges:{newer:{...legacy(v),note:'Unsaved'}}},entries,{});assert.deepEqual(Object.keys(recovery),['newer']);assert.throws(()=>M.importChanges({version:2,hasUnsavedEdits:true,items:{walk:legacy(v)}},entries,{}));

assert.equal(M.version,5);
const art={id:'art:clip',animation_categories:['Combat'],animation_tags:['Sword attack'],title:'Original Sword A'};
const base=M.defaults(art),items={};
assert.equal(base.display_name,'');assert.equal(base.animation_categories,null);assert.equal(base.animation_tags,null);
assert.deepEqual(M.animationLabels(art,base),{animation_categories:['Combat'],animation_tags:['Sword attack']});
assert.equal(M.effective(art,items).animation_categories,null,'Reading inherited defaults must not freeze them into overrides');
const cleared={...base,animation_categories:[],animation_tags:[]};
assert.deepEqual(M.animationLabels(art,cleared),{animation_categories:[],animation_tags:[]});
const resolved=M.animationLabels(art,base);resolved.animation_tags.push('Blocking');assert.deepEqual(art.animation_tags,['Sword attack']);
const edited=M.validateMeta({...base,display_name:'  My 🗡 attack  ',animation_categories:['Combat','Movement'],animation_tags:['Sword attack']});
assert.equal(edited.display_name,'My 🗡 attack');assert.equal(art.title,'Original Sword A');assert.equal(art.id,'art:clip');
assert.equal(M.validateMeta({...base,display_name:'🗡'.repeat(200)}).display_name.length,400);
for(const display_name of ['x'.repeat(201),'line\nbreak','\ud800',5,null])assert.throws(()=>M.validateMeta({...base,display_name}));
for(const bad of [{animation_categories:'Combat'},{animation_categories:['Invalid']},{animation_categories:['Combat','Combat']},{animation_tags:['Flying']},{animation_tags:[{}]},{animation_tags:['Blocking','Blocking']}])assert.throws(()=>M.validateMeta({...base,...bad}));
assert.throws(()=>M.validateMeta(legacy(base)),'Version-three metadata must include the new fields');
const prior={...base,display_name:'Keep custom name',animation_categories:[],animation_tags:['Blocking']};
const legacyImport=M.importChanges({version:2,items:{[art.id]:{...legacy(base),note:'Old backup'},'art:missing':legacy(base)}},[art],{[art.id]:prior});
assert.equal(legacyImport[art.id].display_name,'Keep custom name');assert.deepEqual(legacyImport[art.id].animation_categories,[]);assert.deepEqual(legacyImport[art.id].animation_tags,['Blocking']);assert.equal(legacyImport[art.id].note,'Old backup');assert.equal(legacyImport['art:missing'].animation_tags,null);
const v3Import=M.importChanges({version:3,items:{[art.id]:{...versionThree(base),display_name:' New name ',animation_categories:['Movement'],animation_tags:[]}}},[art],{[art.id]:prior});
assert.equal(v3Import[art.id].display_name,'New name');assert.deepEqual(v3Import[art.id].animation_categories,['Movement']);assert.deepEqual(v3Import[art.id].animation_tags,[]);
assert.throws(()=>M.importChanges({version:2,items:{[art.id]:base}},[art],{}),'A version-two record cannot smuggle unrecognized fields');
assert.throws(()=>M.importChanges({version:3,items:{[art.id]:legacy(base)}},[art],{}));
const v1Import=M.importChanges({version:1,tracking:{[art.id]:{review:'Reviewed',note:'My review'}}},[art],{[art.id]:prior});
assert.equal(v1Import[art.id].display_name,'Keep custom name');assert.equal(v1Import[art.id].status,'');assert.deepEqual(v1Import[art.id].animation_categories,[]);
const v3Recovery=M.importChanges({version:3,hasUnsavedEdits:true,items:{walk:versionThree(v)},pendingChanges:{[art.id]:versionThree(prior)}},entries,{});assert.deepEqual(Object.keys(v3Recovery),[art.id]);
assert.throws(()=>M.importChanges({version:3,hasUnsavedEdits:true,items:{}},[],{}));
assert.deepEqual(M.reviewLabels,['Approved','Scrap']);assert.equal(base.review_label,'');
assert.equal(M.validateMeta({...base,status:'Planned',review_label:'Approved'},art.id).status,'Planned');
assert.equal(M.validateMeta({...base,review_label:'Scrap',attention:['Bug found']},art.id).review_label,'Scrap');
for(const review_label of ['approved','Scrapped',['Approved','Scrap'],true,null])assert.throws(()=>M.validateMeta({...base,review_label},art.id));
assert.throws(()=>M.validateMeta({...v,review_label:'Approved'},'walk'),/only in Art Book/);
const marked={...prior,review_label:'Scrap'};
for(const backup of [
 {version:1,tracking:{[art.id]:{review:'Reviewed',note:'Old notes'}}},
 {version:2,items:{[art.id]:legacy(base)}},
 {version:3,items:{[art.id]:versionThree(base)}}
])assert.equal(M.importChanges(backup,[art],{[art.id]:marked})[art.id].review_label,'Scrap');
const freshV3=M.importChanges({version:3,items:{[art.id]:versionThree(prior)}},[art],{});assert.equal(freshV3[art.id].review_label,'');assert.equal(freshV3[art.id].display_name,'Keep custom name');
for(const review_label of ['','Approved','Scrap'])assert.equal(M.importChanges({version:5,items:{[art.id]:{...base,review_label}}},[art],{[art.id]:marked})[art.id].review_label,review_label);
assert.throws(()=>M.importChanges({version:5,items:{walk:{...v,review_label:'Scrap'}}},entries,{}),/only in Art Book/);
assert.throws(()=>M.importChanges({version:5,items:{[art.id]:versionThree(base)}},[art],{}));
const v5Recovery=M.importChanges({version:5,hasUnsavedEdits:true,items:{[art.id]:base},pendingChanges:{[art.id]:marked}},[art],{});assert.equal(v5Recovery[art.id].review_label,'Scrap');
console.log('Model: workflow, checklist arithmetic, version 1/2/3/4/5 migration, inherited labels, display names, independent Art Book review labels and recovery validation passed.');

// Freeform Art Book tags survive older backup imports and stay independent.
assert.deepEqual(M.artTagSuggestions,['Combat','Magic','Clothing','Armor','Weapons','Items']);
const tagged={...M.defaults(art),art_tags:['Magic','Stone knights'],review_label:'Approved'};
assert.deepEqual(M.validateMeta({...tagged,art_tags:[' combat ','Stone  knights']},art.id).art_tags,['Combat','Stone knights']);
for(const art_tags of [null,'Combat',[''],['a\nline'],['\ud800'],['x'.repeat(61)],['Combat',' combat '],['Ａrmor','Armor'],Array.from({length:33},(_,i)=>String(i))])assert.throws(()=>M.validateMeta({...tagged,art_tags},art.id));
assert.throws(()=>M.validateMeta({...v,art_tags:['Combat']},'walk'));
const old4=Object.fromEntries(Object.entries(tagged).filter(([key])=>key!=='art_tags'));
assert.deepEqual(M.importChanges({version:4,items:{[art.id]:old4}},[art],{[art.id]:tagged})[art.id].art_tags,tagged.art_tags);
assert.deepEqual(M.importChanges({version:4,items:{[art.id]:old4}},[art],{})[art.id].art_tags,[]);
for(const backup of [{version:1,tracking:{[art.id]:{review:'Reviewed',note:''}}},{version:2,items:{[art.id]:legacy(tagged)}},{version:3,items:{[art.id]:versionThree(tagged)}}])assert.deepEqual(M.importChanges(backup,[art],{[art.id]:tagged})[art.id].art_tags,tagged.art_tags);
assert.deepEqual(M.importChanges({version:5,items:{[art.id]:{...tagged,art_tags:[]}}},[art],{[art.id]:tagged})[art.id].art_tags,[]);
const independent=M.defaults(art);independent.art_tags.push('Only here');assert.deepEqual(M.defaults(art).art_tags,[]);
console.log('Art tags: normalization, validation, independent defaults, v4 migration and preservation through older imports passed.');
