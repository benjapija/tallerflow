import {parseAccess,normalizeCode,decisionPayload,portalClient} from './client.mjs';
const endpoint='https://gpseuqmzbazifmkhjyby.supabase.co/functions/v1/workshop-portal';
const access=document.querySelector('#access'),repair=document.querySelector('#repair'),message=document.querySelector('#message');
let identity,client,snapshot;const photoUrls=[];
try{identity=parseAccess(location.hash);}catch(e){message.textContent=e.message;document.querySelector('#login button').disabled=true;}
// Credentials stay in memory and are removed from the address bar. Never put
// the link or code in cookies, local storage, analytics or query strings.
history.replaceState(null,'',location.pathname);
const money=n=>new Intl.NumberFormat('es-ES',{style:'currency',currency:'EUR'}).format(n/100);
const date=v=>new Date(v).toLocaleString('es-ES');
const node=(tag,text,className)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=text;if(className)n.className=className;return n;};
function button(text,action,secondary=false){const b=node('button',text,secondary?'secondary':'');b.type='button';b.onclick=async()=>{b.disabled=true;message.textContent='';try{await action();}catch(e){message.textContent=e.message;}finally{b.disabled=false;}};return b;}
async function refresh(){const s=await client.read();client.reconcile(s);snapshot=s;render();}
document.querySelector('#login').onsubmit=async e=>{e.preventDefault();const b=e.target.querySelector('button');b.disabled=true;message.textContent='';try{client=portalClient(endpoint,{...identity,code:normalizeCode(document.querySelector('#code').value)});await refresh();document.querySelector('#code').value='';access.hidden=true;repair.hidden=false;}catch(e){message.textContent=e.message;}finally{b.disabled=false;}};
function render(){
 for(const url of photoUrls)URL.revokeObjectURL(url);photoUrls.length=0;repair.replaceChildren();
 const s=snapshot;const head=node('section',undefined,'card');head.append(node('p',s.workshop,'eyebrow'),node('h1',s.orderNumber??'Tu reparación'));
 const states={pending:'En recepción',diagnosis:'En diagnóstico',repair:'En reparación',authorization:'Esperando autorización',parts:'Esperando piezas',blocked:'Pendiente de una comprobación',finished:'Trabajo realizado',verified:'Comprobación final realizada',delivered:'Entregado'};
 head.append(node('p',states[s.status]??'En seguimiento por el taller'),node('p',`Acceso válido hasta ${date(s.expiresAt)}`,'muted'));
 head.append(button('Actualizar',refresh,true),button('Cerrar acceso',()=>{client=null;snapshot=null;repair.hidden=true;repair.replaceChildren();access.hidden=false;for(const url of photoUrls)URL.revokeObjectURL(url);photoUrls.length=0;message.textContent='Acceso cerrado. Vuelve a abrir tu enlace para entrar.';document.querySelector('#login button').disabled=true;},true));repair.append(head);
 const quote=node('section',undefined,'card');quote.append(node('h2',`${s.quote.title} · versión ${s.quote.version}`),node('p',`Destinatario: ${s.quote.customer}`),node('p',`Válido hasta ${date(s.quote.validUntil)}`,'muted'));
 if(!s.canDecide)quote.append(node('p','Esta versión se conserva para consulta. Contacta con el taller para autorizar una versión vigente.','warning'));
 const decided=new Map((s.decisions??[]).flatMap(d=>d.decisions).map(d=>[d.lineId,d.accepted]));const selectors=[];
 for(const line of s.quote.lines){const block=node('div',undefined,'line');block.append(node('h3',line.description));
  for(const c of line.components){block.append(node('p',`${c.description} · ${money(c.netCents)} + ${money(c.taxCents)} de impuestos`,'muted'));}
  block.append(node('p',`Total de la partida: ${money(line.totalCents)}`));
  if(decided.has(line.id)){block.append(node('p',decided.get(line.id)?'Partida aceptada':'Partida rechazada','success'));}
  else if(s.canDecide){const label=node('label',`Decisión para ${line.description}`);const select=node('select');select.id=`line-${line.id}`;label.htmlFor=select.id;for(const [v,t]of[['','Selecciona una decisión'],['yes','Aceptar esta partida'],['no','Rechazar esta partida']]){const o=node('option',t);o.value=v;select.append(o);}select.disabled=!!client.pending();const chosen=client.pending()?.payload.decisions.find(d=>d.lineId===line.id);if(chosen)select.value=chosen.accepted?'yes':'no';selectors.push({id:line.id,select});block.append(label,select);}
  quote.append(block);
 }
 quote.append(node('p',`Total del presupuesto: ${money(s.quote.totalCents)}`,'amount'));
 if(s.canDecide){quote.append(node('p','Al confirmar se registran las partidas elegidas sobre esta versión. Las decisiones anteriores se conservan; los cambios requieren otro presupuesto.','muted'));
  quote.append(button(client.pending()?'Reintentar la misma decisión':'Confirmar partidas elegidas',async()=>{
   const payload=client.pending()?.payload??decisionPayload(selectors.map(x=>({id:x.id,choice:x.select.value})));
   selectors.forEach(x=>x.select.disabled=true);try{await client.decide(payload);await refresh();message.textContent='Decisión registrada sobre esta versión.';}catch(e){render();throw e;}
  }));
 }
 repair.append(quote);
 if(s.photos.length){const section=node('section',undefined,'card');section.append(node('h2','Evidencias compartidas'));
  for(const p of s.photos){const block=node('div',undefined,'line');block.append(node('p',p.caption||'Fotografía de la reparación'));block.append(button('Ver fotografía',async()=>{const blob=await client.photo(p.id);const url=URL.createObjectURL(blob);photoUrls.push(url);const img=node('img',undefined,'photo');img.src=url;img.alt=p.caption||'Evidencia compartida por el taller';block.append(img);},true));section.append(block);}repair.append(section);
 }
 for(const d of s.documents){const section=node('section',undefined,'card');section.append(node('h2',`${d.type==='work_note'?'Nota de trabajo':'Presupuesto'} · versión ${d.version}`),node('p',`Emitido el ${date(d.issuedAt)}`,'muted'));const snap=d.snapshot;
  section.append(node('p',`Destinatario: ${typeof snap.clientSnapshot==='string'?snap.clientSnapshot:s.quote.customer}`));
  const table=node('table');const tr=node('tr');tr.append(node('th','Concepto'),node('th','Base'),node('th','Impuestos'),node('th','Total'));table.append(tr);
  for(const l of snap.lines??[]){const r=node('tr');r.append(node('td',l.description??''),node('td',money(l.netCents??0)),node('td',money(l.taxCents??0)),node('td',money(l.totalCents??(l.netCents??0)+(l.taxCents??0))));table.append(r);}section.append(table,node('p',`Total: ${money(snap.totalCents??0)}`,'amount'));repair.append(section);
 }
 repair.append(button('Guardar o imprimir esta consulta',()=>window.print(),true));
}
