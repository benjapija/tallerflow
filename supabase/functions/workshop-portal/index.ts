import {createClient} from 'npm:@supabase/supabase-js@2.99.3';
import {portalHandler} from './handler.ts';
const service=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
Deno.serve(portalHandler({
 async access(id,tokenHash,codeHash,action,cid,payload){const {data,error}=await service.rpc('customer_portal',{grant_id:id,token_hash:tokenHash,code_hash:codeHash,action,command_id:cid,payload});if(error)throw error;return data;},
 async download(path){const {data,error}=await service.storage.from('tallerflow-photos').download(path);if(error||!data)throw error??new Error('Private original unavailable');return new Uint8Array(await data.arrayBuffer());}
}));
