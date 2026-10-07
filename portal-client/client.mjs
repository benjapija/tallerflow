export function parseAccess(fragment){
 const value=new URLSearchParams(fragment.replace(/^#/,'' )).get('access')??'';
 const match=/^([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})\.([a-f0-9]{64})$/i.exec(value);
 if(!match)throw new Error('Este enlace no está completo. Pide otro enlace al taller.');
 return {grantId:match[1].toLowerCase(),token:match[2].toLowerCase()};
}
export function normalizeCode(value){const v=value.replace(/[\s-]/g,'').toLowerCase();if(!/^[a-f0-9]{32}$/.test(v))throw new Error('Revisa el código recibido por separado.');return v;}
export function decisionPayload(values){const decisions=values.filter(v=>v.choice==='yes'||v.choice==='no').map(v=>({lineId:v.id,accepted:v.choice==='yes'}));if(!decisions.length)throw new Error('Selecciona las partidas que quieres aceptar o rechazar.');return {decisions};}
export function portalClient(endpoint,credentials,transport=fetch){
 let pending=null;
 async function request(action,payload={},commandId){
  const response=await transport(endpoint,{method:'POST',headers:{'Content-Type':'application/json'},cache:'no-store',credentials:'omit',referrerPolicy:'no-referrer',body:JSON.stringify({...credentials,action,payload,...(commandId?{commandId}:{})})});
  if(!response.ok){let message='No se pudo confirmar. Revisa el acceso o contacta con el taller.';try{message=(await response.json()).error??message;}catch{}throw new Error(message);}
  return action==='photo'?response.blob():response.json();
 }
 return {read:()=>request('read'),photo:id=>request('photo',{photoId:id}),pending:()=>pending,
  async decide(payload){pending??={id:crypto.randomUUID(),payload:structuredClone(payload)};const r=await request('decide',pending.payload,pending.id);pending=null;return r;},
  reconcile(snapshot){if(pending&&(snapshot.decisions??[]).some(d=>d.id===pending.id))pending=null;},
 };
}
