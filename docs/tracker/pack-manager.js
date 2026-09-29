/* User-created packs and membership edits are saved independently of annotations. */
(function(root){
'use strict';
const $=id=>document.getElementById(id);
const node=(tag,text,cls)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(cls)e.className=cls;return e;};
function create({get,title,editable,prepare,onBusy,installCatalog,render,view,setIndividual,openPack,isImage}){
 let revision=null,available=false,busy=false,selecting=false,previousIndividual=false,selected=new Set(),suggestions=[],candidate=[],candidateList=[],previewLimit=60;
 const allowed=()=>available&&!busy&&editable();
 function status(text,error=false){for(const id of ['pack-management-message','pack-action-message','create-pack-message','pack-suggestions-message']){const e=$(id);if(e){e.textContent=text;e.classList.toggle('error',error);}}}
 function sync(){
  const visible=view().book==='art'&&view().mode==='files';$('pack-management').hidden=!visible;
  $('refresh-auto-packs').disabled=!allowed();$('refresh-auto-packs').textContent=busy?'Working…':'Refresh auto packs';
  $('select-pack-images').disabled=!allowed();$('select-pack-images').setAttribute('aria-pressed',String(selecting));$('select-pack-images').textContent=selecting?'Finish selecting':'Select images';
  $('create-image-pack').hidden=!selecting;$('clear-pack-selection').hidden=!selecting;
  $('create-image-pack').disabled=!allowed()||selected.size<2;$('clear-pack-selection').disabled=busy||!selected.size;
  $('pack-selected-count').textContent=selecting?`${selected.size} images selected · selections stay across filters`:'';
  $('confirm-create-pack').disabled=!allowed()||candidate.length<2||!$('new-pack-title').value.trim();
  $('new-pack-title').disabled=busy;$('cancel-create-pack').disabled=busy;
  document.querySelectorAll('.pack-selection input').forEach(input=>{input.checked=selected.has(input.value);input.disabled=!allowed();});
  document.querySelectorAll('.remove-pack-member').forEach(button=>button.disabled=!allowed());
  document.querySelectorAll('.review-pack-suggestion').forEach(button=>button.disabled=!allowed());
  document.querySelectorAll('#new-pack-members input').forEach(input=>input.disabled=busy);
 }
 function accept(data){
  if(data.version!==1||!Number.isInteger(data.revision)||!Array.isArray(data.catalog?.packs)||!Array.isArray(data.catalog?.art))throw Error('Invalid pack service response. Existing data is unchanged.');
  revision=data.revision;suggestions=Array.isArray(data.suggestions)?data.suggestions:[];installCatalog(data.catalog);available=true;
 }
 async function connect(){
  available=false;
  if(!/^https?:$/.test(location.protocol)){status('Pack editing needs the localhost tracker service.');sync();return;}
  try{const response=await fetch('/api/tracker/packs',{cache:'no-store'});const data=await response.json().catch(()=>({}));if(!response.ok)throw Error(data.error||'Pack tools are unavailable. Restart the tracker service.');accept(data);status('Packs loaded from project.');}
  catch(error){status(error.message,true);}
  sync();
 }
 async function request(action,values={}){
  if(!allowed())return null;busy=true;onBusy(true);sync();status(action==='refresh'?'Refreshing documented packs and looking for suggestions…':'Saving pack changes…');
  try{
   await prepare();
   const response=await fetch('/api/tracker/packs/'+action,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({version:root.TrackerModel.version,revision,...values})});
   const data=await response.json().catch(()=>({}));
   if(!response.ok){if(response.status===409){await connect();throw Error('Packs changed in another tab. Your selection is kept; review it and try again.');}throw Error(data.error||'Pack changes could not be saved.');}
   accept(data);status('Pack changes saved to project.');return data;
  }catch(error){status(error.message,true);return null;}
  finally{busy=false;onBusy(false);sync();render();}
 }
 function selectionControl(e){
  if(!selecting||!isImage(e)||view().mode!=='files')return null;
  const label=node('label',undefined,'pack-selection checklabel'),input=node('input');input.type='checkbox';input.value=e.id;input.checked=selected.has(e.id);input.disabled=!allowed();input.setAttribute('aria-label','Select image: '+title(e));
  input.onchange=()=>{input.checked?selected.add(e.id):selected.delete(e.id);sync();};label.append(input,node('span','Select image'));return label;
 }
 function removalControl(pack,e){
  const button=node('button','×','remove-pack-member');button.type='button';button.title='Remove image from pack';button.setAttribute('aria-label','Remove '+title(e)+' from pack');button.disabled=!allowed();
  button.onclick=async event=>{event.stopPropagation();if(!allowed()||!confirm(`Remove “${title(e)}” from “${title(pack)}”?\n\nThis removes it from the pack only. Its original file, notes and approval are kept.`))return;
   const result=await request('remove',{pack_id:pack.id,member_id:e.id});if(result){status('Image removed from the pack. Its file and notes are kept.');$('pack-search').focus({preventScroll:true});}
  };return button;
 }
 function previewCandidate(){
  const target=$('new-pack-members');target.replaceChildren();$('new-pack-count').textContent=`${candidate.length} images · uncheck any image to leave it out`;
  for(const id of candidateList.slice(0,previewLimit)){
   const e=get(id),label=node('label',undefined,'new-pack-member'),input=node('input');input.type='checkbox';input.checked=candidate.includes(id);input.setAttribute('aria-label','Include '+title(e));input.disabled=busy;
   input.onchange=()=>{const chosen=new Set(candidate);input.checked?chosen.add(id):chosen.delete(id);candidate=candidateList.filter(value=>chosen.has(value));$('new-pack-count').textContent=`${candidate.length} images · uncheck any image to leave it out`;sync();};label.append(input);
   if(e.image&&!e.missing){const image=node('img');image.src=e.url;image.alt='';image.loading='lazy';image.onerror=()=>image.replaceWith(node('span','Image unavailable'));label.append(image);}
   label.append(node('span',title(e)));target.append(label);
  }
  if(candidateList.length>previewLimit){const more=node('button',`Show more images (${candidateList.length-previewLimit} remaining)`);more.type='button';more.onclick=()=>{previewLimit+=60;previewCandidate();};target.append(more);}
 }
 function createPreview(ids,name=''){
  if(!allowed())return;candidate=[...new Set(ids)].filter(id=>isImage(get(id)));candidateList=[...candidate];previewLimit=60;$('new-pack-title').value=name;status('Review the selection and give the pack a name.');previewCandidate();sync();
  if(!$('create-pack-dialog').open)$('create-pack-dialog').showModal();$('new-pack-title').focus();
 }
 function showSuggestions(){
  const list=$('pack-suggestions-list');list.replaceChildren();
  if(!suggestions.length)list.append(node('p','No new pack suggestions. Use Select images to create your own pack.'));
  for(const suggestion of suggestions){
   const card=node('article',undefined,'pack-suggestion');card.append(node('h3',suggestion.title),node('p',suggestion.reason||'Images grouped by their existing filenames and folder.'),node('p',`${suggestion.members.length} images`));
   const covers=node('div',undefined,'suggestion-images');for(const id of suggestion.members.slice(0,3)){const e=get(id);if(e.image&&!e.missing){const image=node('img');image.src=e.url;image.alt=title(e);image.loading='lazy';covers.append(image);}}
   const review=node('button','Review suggested pack','review-pack-suggestion');review.onclick=()=>createPreview(suggestion.members,suggestion.title);card.append(covers,review);list.append(card);
  }
  $('pack-suggestions-message').textContent='Suggestions create no packs until you review and save them.';sync();if(!$('pack-suggestions-dialog').open)$('pack-suggestions-dialog').showModal();
 }
 $('select-pack-images').onclick=()=>{if(!allowed())return;selecting=!selecting;if(selecting){previousIndividual=view().individual;setIndividual(true);}else{selected.clear();setIndividual(previousIndividual);}render();sync();};
 $('clear-pack-selection').onclick=()=>{selected.clear();sync();};
 $('create-image-pack').onclick=()=>createPreview([...selected]);
 $('refresh-auto-packs').onclick=async()=>{if(await request('refresh'))showSuggestions();};
 $('new-pack-title').oninput=sync;
 $('create-pack-form').onsubmit=async event=>{
  event.preventDefault();if(!allowed()||candidate.length<2)return;const ids=[...candidate],name=$('new-pack-title').value.trim();if(!name)return;
  const before=new Set((root.TRACKER_DATA.packs||[]).map(e=>e.id));
  const result=await request('create',{title:name,members:ids});if(!result)return;
  selected.clear();if(selecting)setIndividual(previousIndividual);selecting=false;$('create-pack-dialog').close();if($('pack-suggestions-dialog').open)$('pack-suggestions-dialog').close();
  const created=result.catalog.packs.find(e=>!before.has(e.id));render();sync();if(created)openPack(created);
 };
 $('cancel-create-pack').onclick=()=>{if(!busy)$('create-pack-dialog').close();};
 $('create-pack-dialog').addEventListener('cancel',event=>{if(busy)event.preventDefault();});
 $('close-pack-suggestions').onclick=()=>$('pack-suggestions-dialog').close();
 return {connect,sync,selectionControl,removalControl,isSelecting:()=>selecting,getRevision:()=>available?revision:null};
}
root.PackManager={create};
})(window);
