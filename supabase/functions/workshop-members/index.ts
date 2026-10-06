import {createClient} from 'npm:@supabase/supabase-js@2.99.3';
import {handler} from './handler.ts';
const url=Deno.env.get('SUPABASE_URL')!;
const anon=Deno.env.get('SUPABASE_ANON_KEY')!;
const service=createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
const client=(jwt:string)=>createClient(url,anon,{global:{headers:{Authorization:`Bearer ${jwt}`}},auth:{persistSession:false,autoRefreshToken:false}});
async function rpc(c:ReturnType<typeof createClient>,name:string,params:Record<string,unknown>){const {data,error}=await c.rpc(name,params);if(error)throw error;return data;}
Deno.serve(handler({
 async authenticate(jwt){const {data,error}=await client(jwt).auth.getUser(jwt);return !error&&!!data.user;},
 async prepare(jwt,w,d,id,p){await rpc(client(jwt),'prepare_account',{workshop_id:w,device_id:d,request_id:id,payload:p});},
 async state(w,id){return await rpc(service,'account_provision_state',{workshop_id:w,request_id:id});},
 async create(w,id,p,password){const {data,error}=await service.auth.admin.createUser({email:p.email as string,password,email_confirm:true,
  user_metadata:{display_name:p.name},app_metadata:{tallerflow_workshop:w,tallerflow_request:id}});if(error||!data.user)throw error??new Error('Auth creation failed');return data.user.id;},
 async finish(w,id,user){return await rpc(service,'finish_account_provision',{workshop_id:w,request_id:id,user_id:user});}
}));
