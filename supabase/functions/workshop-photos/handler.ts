type Info=Record<string,any>;
export type PhotoDependencies={
 authenticate(jwt:string):Promise<boolean>;
 prepare(jwt:string,w:string,d:string,id:string,p:Info):Promise<Info>;
 info(jwt:string,w:string,d:string,id:string):Promise<Info>;
 readInfo(jwt:string,w:string,d:string,id:string):Promise<Info>;
 bucket():Promise<void>;
 download(path:string):Promise<Uint8Array>;
 finish(w:string,d:string,id:string,info:Info,hash:string,size:number):Promise<Info>;
};
const uuid=(v:unknown):v is string=>typeof v==='string'&&/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(v);
const response=(status:number,data:Info)=>new Response(JSON.stringify(data),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
export function photoHandler(dep:PhotoDependencies){return async(req:Request):Promise<Response>=>{
 if(req.method!=='POST')return response(405,{error:'POST required'});
 const match=/^Bearer ([^\s]+)$/.exec(req.headers.get('Authorization')??'');
 if(!match)return response(401,{error:'Authentication required'});
 try{
  if(!await dep.authenticate(match[1]))return response(401,{error:'Authentication required'});
  const body=await req.text();if(body.length>16000)return response(413,{error:'Metadata too large'});
  const b=JSON.parse(body);if(!uuid(b.workshopId)||!uuid(b.deviceId))return response(400,{error:'Invalid workshop or device'});
  let id=b.photoId;
  if(b.action==='prepare'){
   if(!uuid(b.commandId)||!uuid(b.payload?.id))return response(400,{error:'Invalid photo identity'});
   await dep.prepare(match[1],b.workshopId,b.deviceId,b.commandId,b.payload);id=b.payload.id;
  }else if(!['verify','restore','read'].includes(b.action)||!uuid(id))return response(400,{error:'Invalid photo action'});
  const info=b.action==='read'?await dep.readInfo(match[1],b.workshopId,b.deviceId,id):await dep.info(match[1],b.workshopId,b.deviceId,id);
  // All privileged Storage work follows the user-scoped SQL authorization.
  await dep.bucket();
  if(!['verify','read'].includes(b.action))return response(200,info);
  const bytes=await dep.download(info.path);
  if(bytes.length<4||bytes.length>4194304||bytes[0]!==255||bytes[1]!==216||bytes[2]!==255||bytes[bytes.length-2]!==255||bytes[bytes.length-1]!==217)throw new Error('JPEG required');
  const hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))).map(n=>n.toString(16).padStart(2,'0')).join('');
  if(hash!==info.sha256||bytes.length!==info.size)throw new Error('Photo integrity mismatch');
  if(b.action==='read'){
   const current=await dep.readInfo(match[1],b.workshopId,b.deviceId,id);
   if(current.path!==info.path||current.sha256!==hash||current.size!==bytes.length||current.userId!==info.userId||current.sessionId!==info.sessionId)throw {code:'42501'};
   return new Response(bytes,{status:200,headers:{'Content-Type':'application/octet-stream','Cache-Control':'private, no-store, max-age=0','Pragma':'no-cache','X-Content-Type-Options':'nosniff'}});
  }
  // SQL checks current Auth session and assignment again after reading bytes.
  return response(200,await dep.finish(b.workshopId,b.deviceId,id,info,hash,bytes.length));
 }catch(error){
  const code=(error as {code?:string})?.code;
  return response(code==='42501'?403:409,{error:code==='42501'?'Access revoked or not permitted':'Photo not confirmed; preserve the local file and retry'});
 }
};}
