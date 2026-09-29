/* Review decisions are metadata. Only the explicit confirmed Trash API moves files. */
(function(root){
'use strict';
const hiddenIds=state=>new Set(state?.trash?.hidden_ids||[]);
function create(h){
 const $=id=>document.getElementById(id),el=(tag,text,cls)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=text;if(cls)n.className=cls;return n;};
 let selected=new Set(),shown=[],prepared=null,busy=false,returnFocus=null;
 const setBusy=value=>{busy=value;h.onBusy?.(value);};
 const notice=text=>{$('scrap-message').textContent=text;};
 const transactions=()=>h.state().trash?.transactions||[];
 function sync(){
  $('scrap-delete').disabled=busy||!h.ready()||!selected.size;
  $('scrap-delete').textContent='Delete selected'+(selected.size?' ('+selected.size+')':'');
  $('scrap-selected').textContent=selected.size+' selected';
  $('scrap-select-all').disabled=busy||!h.ready()||!shown.length;
  $('scrap-clear-selection').disabled=!selected.size||busy;document.querySelectorAll('.scrap-restore').forEach(b=>b.disabled=busy||!h.ready());
  document.querySelectorAll('.scrap-select').forEach(c=>{c.checked=selected.has(c.dataset.id);c.disabled=busy||!h.ready();});
 }
 function render(list,limit){
  shown=list.slice(0,limit);const available=new Set(shown.map(e=>e.id));selected=new Set([...selected].filter(id=>available.has(id)));sync();renderTrash();
 }
 function selectionControl(entry){
  const label=el('label',undefined,'checklabel scrap-selection'),c=el('input');c.type='checkbox';c.className='scrap-select';c.dataset.id=entry.id;c.checked=selected.has(entry.id);c.disabled=busy||!h.ready();c.setAttribute('aria-label','Select '+h.title(entry));c.onchange=()=>{c.checked?selected.add(entry.id):selected.delete(entry.id);sync();};label.append(c,document.createTextNode('Select for deletion'));return label;
 }
 async function request(route,body){
  const response=await fetch('/api/tracker/scrap/'+route,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({version:root.TrackerModel.version,revision:h.state().revision,...body})});
  let data;try{data=await response.json();}catch(e){throw Error('The service did not return a readable result. Refresh Scrap before retrying.');}
  if(!response.ok)throw Error(data.error||'The operation failed. Refresh Scrap before retrying.');return data;
 }
 async function prepare(){
  if(!h.ready()||busy||!selected.size)return;returnFocus=document.activeElement;setBusy(true);sync();notice('Checking selected work…');
  try{
   const ids=[...selected];const result=await request('prepare',{ids});if(ids.length!==selected.size||ids.some(id=>!selected.has(id)))throw Error('Your selection changed. Check it again before deleting.');if(!h.ready())throw Error('Save your pending changes, then check this selection again.');
   prepared=result;$('scrap-confirm-list').replaceChildren();
   for(const item of result.items){const row=el('li');row.append(el('strong',h.title(h.get(item.id))||item.title||item.id),el('p',item.effect),el('p',item.path||'Catalog entry','path'));
    if(item.kind==='file'){row.append(el('p',`${item.bytes.toLocaleString()} bytes · recoverable source file`,'path'));const clips=item.affected_clips?.length||0,packs=item.affected_packs?.length||0;if(clips||packs)row.append(el('p',`Affected references: ${clips} clip${clips===1?'':'s'} · ${packs} image pack${packs===1?'':'s'}. Restore it to make that content available again.`,'note'));}
    for(const warning of item.warnings||[])row.append(el('p',warning,'note'));
    $('scrap-confirm-list').append(row);
   }
   $('scrap-confirm-message').textContent='';$('scrap-confirm').disabled=false;$('scrap-cancel').disabled=false;$('scrap-confirm-dialog').showModal();$('scrap-cancel').focus();notice('Selection checked. Nothing has been deleted yet.');
  }catch(error){prepared=null;notice(error.message);}finally{setBusy(false);sync();}
 }
 async function remove(){
  if(!prepared||busy)return;if(!h.ready()){ $('scrap-confirm-message').textContent='Save pending edits and check the selection again.';return;}
  setBusy(true);const token=prepared.token,revision=prepared.revision;$('scrap-confirm').disabled=true;$('scrap-cancel').disabled=true;$('scrap-confirm-message').textContent='Moving selected work to project Trash…';sync();
  try{const result=await request('delete',{token,revision,confirmed:true});h.accept({...result.state,trash:result.trash});selected.clear();prepared=null;$('scrap-confirm-dialog').close();notice('Selected work moved to project Trash. Restore it below if needed.');h.render();}
  catch(error){prepared=null;$('scrap-confirm-message').textContent=error.message+' Nothing else will be attempted automatically. Close this dialog and refresh Scrap before retrying.';}
  finally{setBusy(false);$('scrap-cancel').disabled=false;sync();}
 }
 function renderTrash(){
  const target=$('scrap-trash-list');target.replaceChildren();const rows=transactions();
  if(!rows.length){target.append(el('p','Project Trash is empty.'));return;}
  for(const transaction of rows){const row=el('article',undefined,'trash-transaction');row.dataset.transaction=transaction.id||transaction.transaction_id;
   row.append(el('strong',new Date(transaction.moved_at||transaction.at||transaction.created_at).toLocaleString()));
   const list=el('ul');for(const item of transaction.items||[])list.append(el('li',(h.title(h.get(item.id))||item.title)+(item.kind==='virtual'?' — catalog entry only':'')));row.append(list);
   const restore=el('button','Restore work');restore.className='scrap-restore';restore.disabled=busy||!h.ready();restore.onclick=async()=>{
    if(busy||!h.ready())return;setBusy(true);sync();renderTrash();notice('Restoring work…');
    try{const result=await request('restore',{transaction_id:transaction.id||transaction.transaction_id});h.accept({...result.state,trash:result.trash});notice('Restored. The Scrap label is retained; change it when you are ready.');}
    catch(error){notice(error.message);}finally{setBusy(false);h.render();}
   };row.append(restore);target.append(row);
  }
 }
 $('scrap-select-all').onclick=()=>{selected=new Set(shown.map(e=>e.id));sync();};$('scrap-clear-selection').onclick=()=>{selected.clear();sync();};$('scrap-delete').onclick=prepare;
 $('scrap-refresh').onclick=()=>{if(!h.ready()){notice('Save pending edits before refreshing.');return;}selected.clear();h.refresh();};
 $('scrap-cancel').onclick=()=>{if(!busy)$('scrap-confirm-dialog').close();};$('scrap-confirm').onclick=remove;
 $('scrap-confirm-dialog').addEventListener('cancel',e=>{if(busy)e.preventDefault();});
 $('scrap-confirm-dialog').addEventListener('close',()=>{prepared=null;const target=returnFocus?.isConnected&&!returnFocus.disabled?returnFocus:document.querySelector('#scrap-trash-list .scrap-restore:not(:disabled)')||$('search');target.focus({preventScroll:true});});
 return {render,selectionControl,clear:()=>{selected.clear();prepared=null;},sync};
}
const api={hiddenIds,create};if(typeof module!=='undefined'&&module.exports)module.exports=api;else root.ArtReview=api;
})(typeof window!=='undefined'?window:globalThis);
