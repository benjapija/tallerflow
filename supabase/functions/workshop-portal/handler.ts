type Info=Record<string,any>;
export interface PortalDependencies {
 access(id:string,tokenHash:string,codeHash:string,action:string,cid:string|null,payload:Info):Promise<Info>;
 download(path:string):Promise<Uint8Array>;
}
const uuid=(v:unknown):v is string=>typeof v==='string'&&/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(v);
export async function secretHash(value:string):Promise<string>{return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value)))).map(x=>x.toString(16).padStart(2,'0')).join('');}
// This public boundary authenticates the random link plus the separately
// delivered verification code. SQL rechecks expiry, revocation and recipient.
export function portalHandler(dep:PortalDependencies){return async(req:Request):Promise<Response>=>{
 const headers={'Content-Type':'application/json','Cache-Control':'private, no-store, max-age=0','Pragma':'no-cache','X-Content-Type-Options':'nosniff','Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Referrer-Policy':'no-referrer'};
 const response=(status:number,data:Info)=>new Response(JSON.stringify(data),{status,headers});
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST')return response(405,{error:'Método no permitido'});
 try{
  if(Number(req.headers.get('Content-Length')??0)>16000)return response(413,{error:'Solicitud demasiado extensa'});
  const raw=await req.text();if(raw.length>16000)return response(413,{error:'Solicitud demasiado extensa'});
  const b=JSON.parse(raw);
  if(!uuid(b.grantId)||typeof b.token!=='string'||!/^[a-f0-9]{64}$/.test(b.token)||typeof b.code!=='string'||!/^[a-f0-9]{32}$/.test(b.code))return response(403,{error:'Acceso no disponible. Revisa el código o contacta con el taller.'});
  if(!['read','photo','decide'].includes(b.action)||Object.keys(b).some(k=>!['grantId','token','code','action','commandId','payload'].includes(k)))return response(400,{error:'Solicitud inválida'});
  if(b.action==='decide'&&!uuid(b.commandId))return response(400,{error:'Identificador de decisión requerido'});
  if(b.payload!==undefined&&(b.payload===null||typeof b.payload!=='object'||Array.isArray(b.payload)))return response(400,{error:'Datos inválidos'});
  const th=await secretHash(b.token),ch=await secretHash(b.code),p=b.payload??{};
  const info=await dep.access(b.grantId,th,ch,b.action,b.commandId??null,p);
  if(info.error)return response(403,{error:'Acceso no disponible. Revisa el código o contacta con el taller.'});
  if(b.action!=='photo')return response(200,info);
  const bytes=await dep.download(info.path);
  if(bytes.length!==info.size||bytes.length<4||bytes.length>4194304||bytes[0]!==255||bytes[1]!==216||bytes[2]!==255||bytes[bytes.length-2]!==255||bytes[bytes.length-1]!==217||await secretHashBytes(bytes)!==info.sha256)throw new Error('Photo integrity');
  const current=await dep.access(b.grantId,th,ch,'photo',null,p);
  if(current.error||current.path!==info.path||current.sha256!==info.sha256||current.size!==info.size)return response(403,{error:'Acceso no disponible. Contacta con el taller.'});
  return new Response(bytes,{status:200,headers:{...headers,'Content-Type':'image/jpeg'}});
 }catch{return response(409,{error:'No se pudo completar. Conserva la selección y actualiza el presupuesto antes de reintentar.'});}
};}
async function secretHashBytes(bytes:Uint8Array):Promise<string>{return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))).map(x=>x.toString(16).padStart(2,'0')).join('');}
