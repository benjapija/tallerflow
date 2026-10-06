import {createClient} from 'npm:@supabase/supabase-js@2.99.3';
const runId="e2792469-2b98-48e1-b549-256d8c35ab7b";
const capabilityHash="49470989ab61b194ab4e19363eac7da251b752fb52a792e4bc13d2420d29c0c5";
const users={"admin":{"id":"9d57eda0-f968-499b-8674-ea1013caebee","email":"qa-9d57eda0-f968-499b-8674-ea1013caebee@example.invalid","device":"0ca8d285-e6dc-4acd-93a7-a5c88070e7fe"},"office":{"id":"9e5b5fc8-2440-4974-a0f2-5e3bf51014ca","email":"qa-9e5b5fc8-2440-4974-a0f2-5e3bf51014ca@example.invalid","device":"adeb3943-90fa-4c1b-8c20-b9778a69aa4f"},"tech1":{"id":"8bdf9936-4d34-4577-b624-c053777bdd1f","email":"qa-8bdf9936-4d34-4577-b624-c053777bdd1f@example.invalid","device":"c9687d4c-d734-46f8-b707-70112a9b155b"},"tech2":{"id":"85c7e759-f3d5-4e36-a31b-a57de630894b","email":"qa-85c7e759-f3d5-4e36-a31b-a57de630894b@example.invalid","device":"549b7020-33f7-40c1-8067-dd43330200a0"},"outsider":{"id":"f498df68-c545-4d49-a10e-f5883f5b2aab","email":"qa-f498df68-c545-4d49-a10e-f5883f5b2aab@example.invalid","device":"5291fbf8-8117-4627-9d22-b45d07784845"}};
const service=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
const hash=async(s:string)=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(s)))).map(b=>b.toString(16).padStart(2,'0')).join('');
Deno.serve(async req=>{
 const cap=req.headers.get('x-tallerflow-test')??'';
 if(req.method!=='POST'||cap.length!==64||await hash(cap)!==capabilityHash) return Response.json({error:'Denied'},{status:403});
 try {
  const text=await req.text();if(text.length>256)return Response.json({error:'Invalid request'},{status:400});
  const action=JSON.parse(text).action;if(!['create','retire'].includes(action))return Response.json({error:'Invalid action'},{status:400});
  let completed=0;
  for(const [role,u] of Object.entries(users)){
   const old=await service.auth.admin.getUserById(u.id);
   if(old.data.user && old.data.user.app_metadata.tallerflow_test_run!==runId)throw new Error('Identity conflict');
   if(action==='create'&&!old.data.user){
    const password='Qa!2026'+await hash(cap+u.id);
    const result=await service.auth.admin.createUser({id:u.id,email:u.email,password,email_confirm:true,app_metadata:{tallerflow_test_run:runId}});
    if(result.error||result.data.user?.id!==u.id)throw new Error('Create failed');
   }else if(action==='retire'&&old.data.user){
    const result=await service.auth.admin.updateUserById(u.id,{ban_duration:'87600h'});if(result.error)throw new Error('Retire failed');
   }
   completed++;
  }
  return Response.json({runId,action,completed,realUserCredentialsRead:false});
 }catch{return Response.json({error:'Fictional validation setup failed'},{status:500});}
});
