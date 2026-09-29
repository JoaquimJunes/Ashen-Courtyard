/* Approval includes all images; other pack metadata stays independent. */
(function(root){
'use strict';
function element(tag,text,className){const node=document.createElement(tag);if(text!==undefined)node.textContent=text;if(className)node.className=className;return node;}
function create({get,meta,title,canEdit,change}){
 let entryId=null,host=null,controls=null,nameDirty=false;
 function entry(){return entryId?get(entryId):null;}
 function patch(values){const e=entry();if(e&&canEdit(e))change(e.id,values);}
 function disclosure(label,id,container){
  const button=element('button',label);button.type='button';button.id=id+'-toggle';button.setAttribute('aria-controls',id);button.setAttribute('aria-expanded','false');
  const panel=element('div',undefined,'pack-editor-section');panel.id=id;panel.hidden=true;
  button.onclick=()=>{panel.hidden=!panel.hidden;button.setAttribute('aria-expanded',String(!panel.hidden));if(!panel.hidden)panel.querySelector('input:not(:disabled),textarea:not(:disabled)')?.focus();};
  container.append(panel);return {button,panel};
 }
 function open(e,container){
  clear();entryId=e.id;host=container;
  const section=element('section',undefined,'whole-pack-editor');section.setAttribute('aria-labelledby','pack-editor-heading');
  const heading=element('h3','Whole pack');heading.id='pack-editor-heading';
  const explanation=element('p','Approving the pack approves every image, including images hidden by filters. Tags, name, notes, Scrap and Not decided apply only to the pack.','path');
  const toolbar=element('div',undefined,'pack-editor-toolbar'),reviewLabel=element('label','Art review decision'),review=element('select',undefined,'state-color state-bar');review.id='pack-review-label';
  review.add(new Option('Not decided',''));for(const label of root.TrackerModel.reviewLabels)review.add(new Option(label,label));
  review.onchange=()=>patch({review_label:review.value});reviewLabel.append(review);toolbar.append(reviewLabel);
  const approval=element('div',undefined,'pack-approval'),approve=element('button','Approve whole pack'),count=element('p',undefined,'path');approve.id='pack-approve-all';approve.type='button';approve.onclick=()=>patch({review_label:'Approved'});count.id='pack-approval-count';count.setAttribute('role','status');approval.append(approve,count);toolbar.append(approval);
  const shortcuts=element('div',undefined,'pack-editor-shortcuts'),sections=element('div');
  const rename=disclosure('Rename pack','pack-rename',sections),tags=disclosure('Tags','pack-tags',sections),notes=disclosure('Pack notes','pack-notes',sections);
  shortcuts.append(rename.button,tags.button,notes.button);toolbar.append(shortcuts);
  const form=element('form',undefined,'rename-form'),nameLabel=element('label','Pack display name'),name=element('input');name.id='pack-display-name';name.maxLength=200;name.required=true;name.oninput=()=>{nameDirty=true;};nameLabel.append(name);
  const save=element('button','Save pack name');save.type='submit';const reset=element('button','Reset pack name');reset.type='button';
  form.onsubmit=event=>{event.preventDefault();const value=name.value.trim();if(value&&canEdit(entry())){const override=value===entry().title?'':value;patch({display_name:override});nameDirty=meta(entry()).display_name!==override;sync();}};
  reset.onclick=()=>{if(canEdit(entry())){nameDirty=false;patch({display_name:''});sync();}};
  const original=element('p',undefined,'path');original.id='pack-original-name';form.append(nameLabel,save,reset);rename.panel.append(form,original);
  const flags=element('fieldset',undefined,'pack-editor-flags');flags.append(element('legend','Attention tags'));
  const flagInputs=[];for(const flag of root.TrackerModel.attentions){const label=element('label',undefined,'checklabel'),input=element('input');input.type='checkbox';input.value=flag;
   input.onchange=()=>{const selected=new Set(meta(entry()).attention);input.checked?selected.add(flag):selected.delete(flag);patch({attention:[...selected]});};label.append(input,document.createTextNode(flag));flags.append(label);flagInputs.push(input);
  }
  tags.panel.append(flags);
  const notesLabel=element('label','Notes for the whole pack'),note=element('textarea');note.id='pack-entry-notes';note.rows=4;note.maxLength=10000;note.oninput=()=>patch({note:note.value});notesLabel.append(note);notes.panel.append(notesLabel);
  section.append(heading,explanation,toolbar,sections);host.replaceChildren(section);
  controls={review,approve,count,name,save,reset,original,flagInputs,note,tagsButton:tags.button,notesButton:notes.button};sync();
 }
 function sync(){
  const e=entry();if(!e||!controls)return;const m=meta(e),c=controls,editable=canEdit(e);
  c.review.value=m.review_label;c.review.dataset.state=m.review_label?m.review_label.toLowerCase():'unset';
  const members=e.members||[],approved=members.filter(id=>meta(get(id)).review_label==='Approved').length;
  c.count.textContent=`${approved}/${members.length} images approved`;c.approve.disabled=!editable||(m.review_label==='Approved'&&approved===members.length);
  if(!nameDirty)c.name.value=title(e);c.original.textContent='Catalog name: '+e.title;
  for(const input of c.flagInputs)input.checked=m.attention.includes(input.value);
  // Keep focused text and a pending explicit rename through saves and member edits.
  if(document.activeElement!==c.note)c.note.value=m.note;
  for(const control of [c.review,c.name,c.save,c.reset,c.note,...c.flagInputs])control.disabled=!editable;
  c.tagsButton.textContent=m.attention.length?'Tags ('+m.attention.length+')':'Tags';
  c.notesButton.textContent=m.note?'Pack notes · Added':'Pack notes';
 }
 function clear(){if(host)host.replaceChildren();entryId=null;host=null;controls=null;nameDirty=false;}
 return {open,sync,clear};
}
root.PackEditor={create};
})(window);
