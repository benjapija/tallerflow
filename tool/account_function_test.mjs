import assert from 'node:assert/strict';
import {handler} from '../supabase/functions/workshop-members/handler.ts';
let passed=0,creates=0,finishes=0,prepared=[],identity=null,loseFinish=true;
const uuid='01000000-0000-4000-8000-000000000001';
const api={
 authenticate:async jwt=>jwt==='valid',
 prepare:async(jwt,w,d,id,p)=>{prepared.push(p);},
 state:async()=>({payload:prepared.at(-1),userId:identity,completed:finishes>0}),
 create:async(w,id,p,password)=>{creates++;assert.equal(password,'fictional-test-password');identity=uuid;return identity;},
 finish:async()=>{if(loseFinish){loseFinish=false;throw new Error('Fictional interrupted finalization');}finishes++;return {created:true,userId:identity};},
};
const payload={name:'Fictional',email:'user@example.invalid',role:'technician',seePrices:false,seeCosts:false,reason:'Training',password:'forbidden-field'};
const body={workshopId:uuid,deviceId:uuid,requestId:uuid,payload,password:'fictional-test-password'};
const request=(b=body,jwt='valid')=>new Request('https://example.invalid',{method:'POST',headers:{Authorization:`Bearer ${jwt}`},body:JSON.stringify(b)});
async function test(name,fn){await fn();passed++;console.log(`PASS ${name}`);}
await test('Unauthorized requests have no provisioning effects',async()=>{assert.equal((await handler(api)(request(body,'invalid'))).status,401);assert.equal(creates,0);assert.equal(prepared.length,0);});
await test('Credential-like payload fields are removed before prepare and an uncertain finish is recoverable',async()=>{assert.equal((await handler(api)(request())).status,409);assert.equal(prepared[0].password,undefined);assert.equal(creates,1);});
await test('Retry reuses the existing Auth identity after interrupted finalization',async()=>{const r=await handler(api)(request());assert.equal(r.status,200);assert.equal((await r.json()).userId,uuid);assert.equal(creates,1);assert.equal(finishes,1);});
await test('Revocation checked during prepare prevents new identities',async()=>{const fail={...api,prepare:async()=>{throw new Error('Revoked');}};assert.equal((await handler(fail)(request())).status,409);assert.equal(creates,1);});
await test('Invalid passwords and identifiers fail before storage',async()=>{const count=prepared.length;assert.equal((await handler(api)(request({...body,password:'short'}))).status,400);assert.equal((await handler(api)(request({...body,deviceId:'other'}))).status,400);assert.equal(prepared.length,count);});
await test('Authentication outages return a controlled response without provisioning',async()=>{const fail={...api,authenticate:async()=>{throw new Error('Network');}};assert.equal((await handler(fail)(request())).status,503);assert.equal(creates,1);});
console.log(`${passed} account function checks passed with simulated Auth API.`);
