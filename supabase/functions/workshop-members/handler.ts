// The dependency boundary permits deterministic tests without live credentials.
export interface Provisioning {
 authenticate(jwt:string):Promise<boolean>;
 prepare(jwt:string,w:string,d:string,id:string,p:Record<string,unknown>):Promise<void>;
 state(w:string,id:string):Promise<{payload:Record<string,unknown>;userId?:string|null;completed:boolean}>;
 create(w:string,id:string,p:Record<string,unknown>,password:string):Promise<string>;
 finish(w:string,id:string,user:string):Promise<unknown>;
}
export function handler(api:Provisioning) {
 return async(req:Request):Promise<Response>=>{
  const headers={'Content-Type':'application/json','Cache-Control':'no-store','Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info'};
  const response=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers});
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
  if(req.method!=='POST')return response({error:'Método no permitido'},405);
  const bearer=req.headers.get('Authorization')??'';
  if(!bearer.startsWith('Bearer '))return response({error:'Inicia sesión con una cuenta autorizada'},401);
  try { if(!(await api.authenticate(bearer.slice(7))))return response({error:'Inicia sesión con una cuenta autorizada'},401); }
  catch { return response({error:'No se pudo comprobar la sesión. Reintenta cuando recuperes la conexión.'},503); }
  try{
   const raw=await req.text();if(raw.length>12000)return response({error:'Solicitud demasiado extensa'},413);
   const b=JSON.parse(raw),uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
   if(![b.workshopId,b.deviceId,b.requestId].every(x=>typeof x==='string'&&uuid.test(x)))return response({error:'Solicitud inválida'},400);
   if(typeof b.password!=='string'||b.password.length<12||b.password.length>1024)return response({error:'La contraseña debe tener entre 12 y 1024 caracteres'},400);
   const p=b.payload??{},safe={name:p.name,email:p.email,role:p.role,seePrices:p.seePrices,seeCosts:p.seeCosts,reason:p.reason};
   await api.prepare(bearer.slice(7),b.workshopId,b.deviceId,b.requestId,safe);
   const state=await api.state(b.workshopId,b.requestId);
   let user=state.userId;
   // A retry finds the original Auth identity through server-only app metadata.
   if(!user)user=await api.create(b.workshopId,b.requestId,state.payload,b.password);
   return response(await api.finish(b.workshopId,b.requestId,user));
  }catch{return response({error:'No se ha podido completar la cuenta. Conserva la solicitud y revisa el acceso o un correo ya utilizado.'},409);}
 };
}
