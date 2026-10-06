import {createClient} from 'npm:@supabase/supabase-js@2.99.3';
import {photoHandler} from './handler.ts';
const url=Deno.env.get('SUPABASE_URL')!;
const anon=Deno.env.get('SUPABASE_ANON_KEY')!;
const service=createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
const user=(jwt:string)=>createClient(url,anon,{global:{headers:{Authorization:`Bearer ${jwt}`}},auth:{persistSession:false,autoRefreshToken:false}});
async function rpc(c:ReturnType<typeof createClient>,name:string,params:Record<string,unknown>){const {data,error}=await c.rpc(name,params);if(error)throw error;return data;}
Deno.serve(photoHandler({
 async authenticate(jwt){const {data,error}=await user(jwt).auth.getUser(jwt);return !error&&!!data.user;},
 async prepare(jwt,w,d,id,p){return rpc(user(jwt),'photo_command',{workshop_id:w,device_id:d,command_id:id,action:'photo_prepare',payload:p});},
 async info(jwt,w,d,id){return rpc(user(jwt),'photo_upload_info',{workshop_id:w,device_id:d,photo_id:id});},
 async readInfo(jwt,w,d,id){return rpc(user(jwt),'photo_download_info',{workshop_id:w,device_id:d,photo_id:id});},
 async bucket(){
  const {data,error}=await service.storage.getBucket('tallerflow-photos');
  if(data){if(data.public)throw new Error('Photo bucket must remain private');return;}
  if(error && !['404','400'].includes(error.statusCode??''))throw error;
  const created=await service.storage.createBucket('tallerflow-photos',{public:false,fileSizeLimit:4194304,allowedMimeTypes:['image/jpeg']});
  if(created.error && !created.error.message.toLowerCase().includes('already exists'))throw created.error;
  const checked=await service.storage.getBucket('tallerflow-photos');if(checked.error||checked.data?.public!==false)throw new Error('Private Storage unavailable');
 },
 async download(path){const {data,error}=await service.storage.from('tallerflow-photos').download(path);if(error||!data)throw error??new Error('Missing file');return new Uint8Array(await data.arrayBuffer());},
 async finish(w,d,id,info,hash,size){return rpc(service,'photo_finalize',{workshop_id:w,device_id:d,photo_id:id,user_id:info.userId,session_id:info.sessionId,sha256:hash,byte_size:size});}
}));
