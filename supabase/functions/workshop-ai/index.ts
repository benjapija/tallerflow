import {createClient} from 'npm:@supabase/supabase-js@2.99.3';
import {assistantHandler,type AISettings} from './handler.ts';
const env=(key:string)=>Deno.env.get(key)??'';
const number=(key:string,fallback=0)=>env(key)===''?fallback:Number(env(key));
const settings:AISettings={enabled:env('TALLERFLOW_AI_ENABLED')==='true',freeCreditsConfirmed:env('TALLERFLOW_AI_FREE_CREDITS_CONFIRMED')==='true',model:env('TALLERFLOW_AI_MODEL'),dailyMicroUsd:number('TALLERFLOW_AI_DAILY_MICRO_USD'),requestLimit:number('TALLERFLOW_AI_REQUEST_LIMIT',10),maxOutputTokens:number('TALLERFLOW_AI_MAX_OUTPUT_TOKENS',1000),inputRateMicroPerMillion:number('TALLERFLOW_AI_INPUT_RATE'),outputRateMicroPerMillion:number('TALLERFLOW_AI_OUTPUT_RATE')};
// A server key is required only when the explicitly configured service is enabled.
const key=settings.enabled&&settings.freeCreditsConfirmed?env('OPENAI_API_KEY'):'';
settings.enabled=settings.enabled&&key.length>0;
const url=env('SUPABASE_URL'),anon=env('SUPABASE_ANON_KEY');
const user=(jwt:string)=>createClient(url,anon,{global:{headers:{Authorization:`Bearer ${jwt}`}},auth:{persistSession:false,autoRefreshToken:false}});
const rpc=async(c:ReturnType<typeof createClient>,name:string,p:Record<string,unknown>)=>{const {data,error}=await c.rpc(name,p);if(error)throw error;return data;};
const service=()=>createClient(url,env('SUPABASE_SERVICE_ROLE_KEY'),{auth:{persistSession:false,autoRefreshToken:false}});
Deno.serve(assistantHandler({settings,
 authenticate:async jwt=>{const {data,error}=await user(jwt).auth.getUser(jwt);return !error&&!!data.user;},
 context:(jwt,b)=>rpc(user(jwt),'ai_context',{workshop_id:b.workshopId,device_id:b.deviceId,order_id:b.orderId,mode:b.mode}),
 receipt:(jwt,b)=>rpc(user(jwt),'ai_receipt',{workshop_id:b.workshopId,device_id:b.deviceId,order_id:b.orderId,request_id:b.requestId}),
 reserve:(b,c,h,amount)=>rpc(service(),'ai_reserve',{workshop_id:b.workshopId,device_id:b.deviceId,user_id:c.userId,session_id:c.sessionId,request_id:b.requestId,order_id:b.orderId,revision:b.revision,mode:b.mode,request_hash:h,model:settings.model,reserve_micro:amount,limit_micro:settings.dailyMicroUsd,request_limit:settings.requestLimit}),
 finish:(b,h,r)=>rpc(service(),'ai_finish',{workshop_id:b.workshopId,request_id:b.requestId,request_hash:h,result:r}),
 generate:async request=>{const response=await fetch('https://api.openai.com/v1/responses',{method:'POST',headers:{'Content-Type':'application/json',Authorization:`Bearer ${key}`},body:JSON.stringify(request),signal:AbortSignal.timeout(45000)});if(!response.ok)throw new Error('Provider unavailable');return response.json();},
}));
