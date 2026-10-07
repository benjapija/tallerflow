// Run only with the explicitly approved, isolated fixture configuration.
// This client has publishable/anon keys and fictional account credentials only.
// Administrative setup is separate; no secret or service-role key is accepted.
import {readFile,writeFile} from 'node:fs/promises';
import {createHash,randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
const configPath=process.env.TF_QA_CONFIG;
if(!configPath)throw new Error('An approved fictional fixture configuration is required');
const cfg=JSON.parse(await readFile(configPath,'utf8'));
if(!cfg.badVinReceptionId){cfg.badVinReceptionId=randomUUID();cfg.badVinOrderId=randomUUID();await writeFile(configPath,JSON.stringify(cfg));}
if(cfg.approved!==true||!Object.values(cfg.users).every(u=>u.email.endsWith('@example.invalid')))throw new Error('Fictional fixture approval required');
const sha=b=>createHash('sha256').update(b).digest('hex');
const clients={},checks=[];
const evidencePath=process.env.TF_QA_EVIDENCE??'outputs/TallerFlow/evidence/hosted-http-validation.json';
const resumed=process.env.TF_QA_RESUME==='after-timers'?JSON.parse(await readFile(evidencePath,'utf8')):null;
if(resumed && (resumed.runId!==cfg.runId || resumed.workshop!==cfg.workshop || ![11,12].includes(resumed.totalChecks)))throw new Error('Unexpected fixture checkpoint');
async function request(path,{who,body,method='POST',bytes}={}){
 const headers={apikey:cfg.publishableKey};
 if(who)headers.Authorization='Bearer '+clients[who].jwt;
 if(bytes){headers['Content-Type']='image/jpeg';headers['cache-control']='max-age=0';}else headers['Content-Type']='application/json';
 const response=await fetch(cfg.url+path,{method,headers,body:bytes??(body===undefined?undefined:JSON.stringify(body)),signal:AbortSignal.timeout(45000)});
 const text=await response.text();let data;try{data=JSON.parse(text);}catch{data={};}
 return {ok:response.ok,status:response.status,data};
}
async function rpc(who,name,body,{deny=false}={}){
 const result=await request('/rest/v1/rpc/'+name,{who,body});
 if(deny){assert.equal(result.ok,false,'Expected RPC denial: '+name);return result;}
 if(!result.ok)throw new Error('RPC '+name+' failed ('+result.status+'): '+String(result.data.message??result.data.error??''));
 return result.data;
}
const snap=(who,workshop=cfg.workshop)=>rpc(who,'device_snapshot',{workshop_id:workshop,device_id:cfg.users[who].device});
const command=(who,action,payload,id=randomUUID())=>rpc(who,'reliability_command',{workshop_id:cfg.workshop,device_id:cfg.users[who].device,command_id:id,action,payload});
async function check(name,action){await action();checks.push(name);console.log('PASS '+name);}
async function operation(who,kind,payload,{id=randomUUID(),revision,at,orderId=cfg.orderId}={}){
 const current=revision??(await snap(who)).orders.find(o=>o.id===orderId)?.revision??0;
 const op={id,orderId,actorId:cfg.users[who].id,kind,at:at??new Date().toISOString(),baseRevision:current,payload};
 return {op,result:await rpc(who,'apply_operation',{workshop_id:cfg.workshop,device_id:cfg.users[who].device,operation:op})};
}
async function photoRead(who,id){
 const response=await fetch(cfg.url+'/functions/v1/workshop-photos',{method:'POST',headers:{apikey:cfg.publishableKey,Authorization:'Bearer '+clients[who].jwt,'Content-Type':'application/json'},body:JSON.stringify({action:'read',workshopId:cfg.workshop,deviceId:cfg.users[who].device,photoId:id}),signal:AbortSignal.timeout(45000)});
 return {ok:response.ok,status:response.status,bytes:Buffer.from(await response.arrayBuffer()),cacheControl:response.headers.get('cache-control')};
}
const photoBytes=await readFile(process.env.TF_QA_JPEG??'work/qa-fictional.jpg');
const proof={date:new Date().toISOString(),runId:cfg.runId,workshop:cfg.workshop,applicationCheckpoint:process.env.TF_SOURCE_COMMIT??null,validationScriptPublished:false,environment:'hosted Auth, PostgREST, Edge Functions and Storage HTTP',fictionalAccounts:true,nativeDeviceValidated:false,realAdminPasswordRead:false,checks,passed:false};
try{
 await check('Five fictional accounts sign in through GoTrue and user IDs remain original',async()=>{
  for(const [role,u]of Object.entries(cfg.users)){
   const password='Qa!2026'+sha(cfg.capability+u.id+cfg.url);
   const r=await request('/auth/v1/token?grant_type=password',{body:{email:u.email,password}});
   assert.equal(r.ok,true,'Fictional login '+role+' failed');assert.equal(r.data.user.id,u.id);
   clients[role]={jwt:r.data.access_token,refresh:r.data.refresh_token};
  }
 });
 await check('Real JWT snapshots bind admin, office and both operators to individual devices',async()=>{
  for(const role of ['admin','office','tech1','tech2']){const s=await snap(role);assert.equal(s.actor.id,cfg.users[role].id);assert.equal(s.actor.role,role.startsWith('tech')?'technician':role);}
  await snap('outsider',cfg.otherWorkshop);
 });
 await check('Anonymous and another workshop cannot read the fixture',async()=>{
  const anon=await request('/rest/v1/rpc/device_snapshot',{body:{workshop_id:cfg.workshop,device_id:randomUUID()}});assert.equal(anon.ok,false);
  await rpc('outsider','device_snapshot',{workshop_id:cfg.workshop,device_id:cfg.users.outsider.device},{deny:true});
 });
 await check('Admin rates are audited and operator administration is denied over HTTP',async()=>{
  const s=await snap('admin');
  const p={revision:s.managementRevision,reason:'Fictional hosted HTTP validation',settings:{hourlyRateCents:6000,taxBps:1000,internalHourlyCostCents:2500,internalCostKnown:true}};
  await rpc('admin','management_command',{workshop_id:cfg.workshop,device_id:cfg.users.admin.device,command_id:randomUUID(),action:'settings_save',payload:p});
  await rpc('tech1','management_command',{workshop_id:cfg.workshop,device_id:cfg.users.tech1.device,command_id:randomUUID(),action:'settings_save',payload:p},{deny:true});
 });
 await check('Office receives a fictional vehicle with two assigned operators and authorizes its task',async()=>{
  const existing=(await snap('office')).orders.find(o=>o.id===cfg.orderId);
  if(existing){assert.equal(existing.plate,cfg.plate??'9998FIC');assert.ok(existing.tasks.find(t=>t.id===cfg.taskId)?.assignees.includes(cfg.users.tech2.id));return;}
  const {result}=await operation('office','receive',{plate:cfg.plate??'9998 FIC',country:'ES',vin:'HTTP-'+cfg.orderId,vehicle:'Vehículo ficticio',engine:'Prueba',client:'Cliente ficticio',phone:'',km:10,symptom:'Validación ficticia',due:'Prueba',priority:'Normal',location:'Prueba',keys:'Prueba',tasks:[{id:cfg.taskId,title:'Comprobación ficticia',estimateMinutes:30,assignees:[cfg.users.tech1.id,cfg.users.tech2.id]}]},{revision:0});
  assert.equal(result.status,'accepted','Reception rejected: '+String(result.reason??''));
  assert.equal((await operation('office','authorize',{taskId:cfg.taskId,approvedCents:50000,version:1,customer:'Ficticio',evidence:'Autorización ficticia'})).result.status,'accepted');
 });
 await check('Operators see technical work but tariff and internal cost remain hidden',async()=>{
  for(const who of ['tech1','tech2']){const s=await snap(who);assert.ok(s.orders.find(o=>o.id===cfg.orderId));assert.equal(s.settings.hourlyRateCents,undefined);assert.equal(s.settings.internalHourlyCostCents,undefined);}
 });
  let info;
  await check('An authenticated operator prepares a private photo and stable retry preserves its identity',async()=>{
  const existing=(await snap('tech1')).photoManifest.find(p=>p.id===cfg.photoId);
  const payload={id:cfg.photoId,orderId:cfg.orderId,originalDeviceId:cfg.users.tech1.device,sha256:sha(photoBytes),size:photoBytes.length,mime:'image/jpeg',caption:'Imagen ficticia para validar Storage',capturedAt:existing?new Date(existing.capturedAt).toISOString():new Date().toISOString()};
  const body={action:'prepare',workshopId:cfg.workshop,deviceId:cfg.users.tech1.device,commandId:cfg.photoPrepareId,payload};
  const first=await request('/functions/v1/workshop-photos',{who:'tech1',body});
  if(!first.ok)throw new Error('Photo prepare failed: '+first.status+' '+String(first.data.error??first.data.message??''));
  info=first.data;assert.equal(info.id,cfg.photoId);assert.equal(info.sha256,sha(photoBytes));
  const repeated=await request('/functions/v1/workshop-photos',{who:'tech1',body});assert.equal(repeated.ok,true);assert.equal(repeated.data.path,info.path);
 });
 await check('Storage upload uses the reserved immutable path and verification retries once',async()=>{
  const uploaded=await request('/storage/v1/object/tallerflow-photos/'+info.path,{who:'tech1',bytes:photoBytes});
  if(!uploaded.ok){const r=await photoRead('tech1',cfg.photoId);assert.equal(r.ok,true,'Failed upload is not a successful retry without an authorized read');assert.equal(sha(r.bytes),info.sha256);}
  const body={action:'verify',workshopId:cfg.workshop,deviceId:cfg.users.tech1.device,photoId:cfg.photoId};
  const verified=await request('/functions/v1/workshop-photos',{who:'tech1',body});assert.equal(verified.ok,true,'Photo verification failed: '+verified.status);assert.equal(verified.data.status,'attached');
  const repeated=await request('/functions/v1/workshop-photos',{who:'tech1',body});assert.equal(repeated.ok,true);
  const s=await snap('tech1');assert.equal(s.photoManifest.filter(p=>p.id===cfg.photoId).length,1);
 });
 await check('Office and the assigned second operator download the exact private bytes',async()=>{
  for(const who of ['office','tech2']){
   const r=await photoRead(who,cfg.photoId);
   assert.equal(r.ok,true,'Private read '+who+' failed');assert.equal(sha(r.bytes),info.sha256);assert.ok(r.cacheControl.includes('no-store'));
  }
 });
 await check('Another workshop, anonymous read, signed URLs, replacement and deletion are denied',async()=>{
  assert.equal((await request('/storage/v1/object/authenticated/tallerflow-photos/'+info.path,{who:'outsider',method:'GET'})).ok,false);
  assert.equal((await request('/storage/v1/object/public/tallerflow-photos/'+info.path,{method:'GET'})).ok,false);
  assert.equal((await request('/storage/v1/object/sign/tallerflow-photos/'+info.path,{who:'office',body:{expiresIn:60}})).ok,false);
  assert.equal((await request('/storage/v1/object/tallerflow-photos/'+info.path,{who:'tech1',method:'PUT',bytes:photoBytes})).ok,false);
  const deleted=await request('/storage/v1/object/tallerflow-photos',{who:'office',method:'DELETE',body:{prefixes:[info.path]}});
  if(deleted.ok)assert.deepEqual(deleted.data,[],'A forbidden deletion removed an object');
  const retained=await photoRead('office',cfg.photoId);assert.equal(retained.ok,true);assert.equal(sha(retained.bytes),info.sha256);assert.equal((await request('/storage/v1/object/authenticated/tallerflow-photos/'+info.path,{who:'office',method:'GET'})).ok,false,'Direct object GET must remain disabled');
 });
 await check('Concurrent operators and a lost operation response preserve one original timer each',async()=>{
  if(resumed){
   const order=(await snap('office')).orders.find(o=>o.id===cfg.orderId);
   assert.equal(order.times.length,2);assert.ok(order.times.every(t=>t.end));assert.equal(order.tasks.find(t=>t.id===cfg.taskId).done,true);
   assert.ok(resumed.checks.includes('Concurrent operators and a lost operation response preserve one original timer each'));
   proof.concurrencyCheckedAt=resumed.date;return;
  }
  const s=await snap('tech1'),revision=s.orders.find(o=>o.id===cfg.orderId).revision,start=new Date(Date.now()-60000).toISOString();
  const results=await Promise.all(['tech1','tech2'].map(who=>operation(who,'start',{taskId:cfg.taskId},{revision,at:start})));
  for(const {op,result}of results)assert.equal(result.status,'accepted');
  const repeated=await rpc('tech1','apply_operation',{workshop_id:cfg.workshop,device_id:cfg.users.tech1.device,operation:results[0].op});assert.deepEqual(repeated,results[0].result);
  for(const [i,who]of ['tech1','tech2'].entries())assert.equal((await operation(who,'stop',{sessionId:results[i].op.id})).result.status,'accepted');
  assert.equal((await snap('office')).orders.find(o=>o.id===cfg.orderId).times.length,2);
  assert.equal((await operation('tech1','finish_task',{taskId:cfg.taskId})).result.status,'accepted');
 });
 await check('Office archives the rejected fictional VIN with a reason before coordinated closure',async()=>{
  const existingAttempt=(await snap('office')).incidents?.find(r=>r.operation?.id===cfg.badVinReceptionId);
  const rejectedAttempt=existingAttempt?{result:{status:'conflict',reason:existingAttempt.reason}}:await operation('office','receive',{plate:cfg.plate??'9998FIC',country:'ES',vin:'X'.repeat(80)},{id:cfg.badVinReceptionId,orderId:cfg.badVinOrderId});
  assert.equal(rejectedAttempt.result.status,'conflict');assert.match(rejectedAttempt.result.reason,/VIN/i);
  const s=await snap('office');
  const rejected=s.incidents?.find(r=>r.operation?.id===cfg.badVinReceptionId);
  assert.ok(rejected,'Expected recorded fictional reception conflict');
  for(const incident of s.incidents.filter(i=>[cfg.badVinReceptionId,cfg.badReceptionId].includes(i.operation?.id))){
   if(incident.resolution){assert.equal(incident.resolution.outcome,'archive');continue;}
   const currentRevision=s.orders.find(o=>o.id===incident.operation.orderId)?.revision??null;
   const resolution=await command('office','resolve',{operationId:incident.operation.id,revision:currentRevision,outcome:'archive',reason:'Rejected fictional reception retained with its original validation reason'});
   assert.equal(resolution.resolved,true);
  }
 });
 await check('Office quality and billable review calculate an immutable document after every device acknowledges',async()=>{
  assert.equal((await operation('office','billable',{taskId:cfg.taskId,minutes:30,reason:'Revisión ficticia'})).result.status,'accepted');
  assert.equal((await operation('office','quality',{result:'Comprobación ficticia',pendingSymptoms:''})).result.status,'accepted');
  await snap('admin');
  const revision=(await snap('office')).orders.find(o=>o.id===cfg.orderId).revision;
  const close=await command('office','request_close',{orderId:cfg.orderId,revision});
  const ack={orderId:cfg.orderId,revision,requestId:close.requestId,locallyFrozen:true};
  await command('office','ack_close',ack);
  await rpc('office','reliability_command',{workshop_id:cfg.workshop,device_id:cfg.users.office.device,command_id:randomUUID(),action:'issue',payload:{orderId:cfg.orderId,requestId:close.requestId}},{deny:true});
  for(const who of ['admin','tech1','tech2'])await command(who,'ack_close',ack);
  const id=randomUUID(),payload={orderId:cfg.orderId,requestId:close.requestId};
  const issued=await command('office','issue',payload,id);assert.equal(issued.document.totalCents,3300);
  assert.deepEqual(await command('office','issue',payload,id),issued);
  proof.closureRequestId=issued.document.closureRequestId;proof.photoHash=info.sha256;proof.photoPath=info.path;
 });
 await check('Complete HTTP export preserves photos, audit and document while excluding Auth secrets',async()=>{
  const backup=await rpc('admin','export_workshop',{workshop_id:cfg.workshop,device_id:cfg.users.admin.device});
  assert.equal(backup.authExcluded,true);assert.equal(backup.databaseVersion,13);assert.ok(backup.tables.documents.find(d=>d.order_id===cfg.orderId));assert.ok(backup.photoFiles.find(p=>p.id===cfg.photoId&&p.filePresent===true));
  assert.equal(JSON.stringify(backup).includes(clients.admin.jwt),false);
 });
 await check('Sign-out invalidates real session access even when the old JWT has not expired',async()=>{
  const jwt=clients.tech2.jwt;
  assert.equal((await request('/auth/v1/logout?scope=local',{who:'tech2'})).ok,true);
  clients.tech2.jwt=jwt;
  await rpc('tech2','device_snapshot',{workshop_id:cfg.workshop,device_id:cfg.users.tech2.device},{deny:true});
  assert.equal((await photoRead('tech2',cfg.photoId)).ok,false,'Revoked private POST download must be denied');
  assert.equal((await request('/storage/v1/object/authenticated/tallerflow-photos/'+info.path,{who:'tech2',method:'GET'})).ok,false,'Direct object download stays disabled');
 });
 proof.passed=true;
}catch(error){proof.error=String(error.message??'Validation failed');process.exitCode=1;console.error(proof.error);}
finally{
 for(const who of Object.keys(clients))await request('/auth/v1/logout?scope=local',{who}).catch(()=>{});
 await writeFile(evidencePath,JSON.stringify({...proof,totalChecks:checks.length},null,2)+'\n');
 console.log(JSON.stringify({passed:proof.passed,totalChecks:checks.length,environment:proof.environment}));
}
