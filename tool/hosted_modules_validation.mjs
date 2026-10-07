import {readFile,writeFile} from 'node:fs/promises';
import {createHash,randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
const cfg=JSON.parse(await readFile(process.env.TF_QA_CONFIG,'utf8'));
if(!cfg.approved||!Object.values(cfg.users).every(x=>x.email.endsWith('@example.invalid')))throw Error('Approved isolated fixture required');
cfg.moduleFixture??=Object.fromEntries(['oid','tid','clientId','vehicleId','itemId','qid','lid','caseid'].map(k=>[k,randomUUID()]));cfg.moduleChecks??=[];
const save=()=>writeFile(process.env.TF_QA_CONFIG,JSON.stringify(cfg));await save();
const sha=x=>createHash('sha256').update(x).digest('hex'), clients={},checks=[...cfg.moduleChecks];
const evidence=process.env.TF_QA_EVIDENCE;
const proof={date:new Date().toISOString(),runId:cfg.runId,workshop:cfg.workshop,environment:'Real hosted Auth and PostgREST HTTP; fictional accounts',nativeValidated:false,realAdminPasswordRead:false,checks,passed:false};
async function request(path,who,body,method='POST'){const headers={apikey:cfg.publishableKey,'Content-Type':'application/json'};if(who)headers.Authorization='Bearer '+clients[who];const r=await fetch(cfg.url+path,{method,headers,body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(45000)});let data={};try{data=await r.json()}catch{}return{ok:r.ok,status:r.status,data};}
async function rpc(who,name,body,deny=false){const r=await request('/rest/v1/rpc/'+name,who,body);if(deny){assert.equal(r.ok,false,'Expected denial '+name);return r;}assert.equal(r.ok,true,name+': '+(r.data.message??''));return r.data;}
const snap=who=>rpc(who,'device_snapshot',{workshop_id:cfg.workshop,device_id:cfg.users[who].device});
const cmd=(who,name,action,payload,id=randomUUID(),deny=false)=>rpc(who,name,{workshop_id:cfg.workshop,device_id:cfg.users[who].device,command_id:id,action,payload},deny);
async function op(who,oid,kind,payload,id=randomUUID(),conflict=false){const s=await snap(who),record={id,orderId:oid,actorId:cfg.users[who].id,kind,at:new Date().toISOString(),baseRevision:s.orders.find(x=>x.id===oid)?.revision??0,payload};const r=await rpc(who,'apply_operation',{workshop_id:cfg.workshop,device_id:cfg.users[who].device,operation:record});assert.equal(r.status,conflict?'conflict':'accepted',r.reason??kind);return{record,result:r};}
async function check(name,f){if(checks.includes(name)){console.log('RETAINED '+name);return;}await f();checks.push(name);cfg.moduleChecks=[...checks];await save();console.log('PASS '+name);await writeFile(evidence,JSON.stringify({...proof,totalChecks:checks.length},null,2));}
let {oid,tid,clientId,vehicleId,itemId,qid,lid,caseid}=cfg.moduleFixture;
try{
 for(const [who,u]of Object.entries(cfg.users)){const r=await request('/auth/v1/token?grant_type=password',null,{email:u.email,password:'Qa!2026'+sha(cfg.capability+u.id+cfg.url)});assert.ok(r.ok,'Login '+who);clients[who]=r.data.access_token;}
 for(const who of ['admin','office','tech1','tech2'])await snap(who);
 await check('CSV preview and commit preserve fictional clients, vehicles and catalog with role enforcement',async()=>{
  for(const [kind,who,data,id]of [['clients','office',{code:'HTTP-CURRENT',name:'Cliente ficticio CSV',phone:'',email:'csv@example.invalid',taxId:'',address:''},clientId],['vehicles','office',{plate:'9911FIC',country:'ES',vin:'CSV-CURRENT-'+cfg.runId,vehicle:'Vehículo ficticio CSV',engine:'Prueba',km:100,clientCode:'HTTP-CURRENT'},vehicleId],['catalog','admin',{reference:'HTTP-ITEM',description:'Recambio ficticio',unit:'unidad',priceCents:1000,costCents:600,costKnown:true,taxBps:2100,stockMilli:0,minMilli:0,supplier:'Proveedor ficticio'},itemId]]){
   const p={kind,reason:'Fictional CSV validation',rows:[{id,line:2,data}]};const preview=await cmd(who,'import_command','import_preview',p);assert.ok(['ready','duplicate'].includes(preview.rows[0].status));const key=randomUUID(),r=await cmd(who,'import_command','import_commit',p,key);assert.deepEqual(await cmd(who,'import_command','import_commit',p,key),r);assert.equal((await cmd(who,'import_command','import_preview',p)).rows[0].status,'duplicate');
  }
  await cmd('tech1','import_command','import_commit',{kind:'clients',reason:'Denied',rows:[]},randomUUID(),true);
 });
 const rates=await snap('admin');await cmd('admin','management_command','settings_save',{revision:rates.managementRevision,reason:'Fictional quote calculation fixture',settings:{hourlyRateCents:5000,taxBps:2100,internalHourlyCostCents:2500,internalCostKnown:true}});
 // Reception captures the current defaults; later setting edits never silently reprice it.
 if(!(await snap('office')).orders.some(o=>o.id===oid))await op('office',oid,'receive',{plate:'9911FIC',country:'ES',vin:'CSV-CURRENT-'+cfg.runId,vehicle:'Vehículo ficticio CSV',engine:'Prueba',client:'Cliente ficticio CSV',phone:'',km:100,symptom:'Prueba HTTP de módulos',tasks:[{id:tid,title:'Tarea ficticia',estimateMinutes:30,assignees:[cfg.users.tech1.id]}]});
 let quote1,approved;
 await check('Versioned quotes calculate 4661 cents, retry once and bind authorization to the reviewed version',async()=>{
  const p={id:qid,expectedVersion:0,title:'Presupuesto ficticio',reason:'Initial review',validUntil:new Date(Date.now()+86400000).toISOString(),lines:[{id:lid,taskId:tid,description:'Trabajo ficticio',laborMinutes:30,parts:[{reference:'OIL',description:'Aceite ficticio',unit:'litro',quantityMilli:1500,unitPriceCents:1001,taxBps:2100,discountBps:1000}]}]};
  const first=await op('office',oid,'quote_draft',p);assert.deepEqual(await rpc('office','apply_operation',{workshop_id:cfg.workshop,device_id:cfg.users.office.device,operation:first.record}),first.result);
  quote1=(await snap('office')).orders.find(x=>x.id===oid).quoteLedger.versions[0];assert.equal(quote1.totalCents,4661);
  const decision={quoteId:qid,version:1,customer:'Cliente ficticio CSV',channel:'telephone',evidence:'Fictional verified call',reason:'Decision recorded',decisions:[{lineId:lid,accepted:true}]};await op('office',oid,'quote_decision',decision);
  approved=(await snap('office')).orders.find(x=>x.id===oid).tasks[0];assert.equal(approved.approvedCents,4661);
  await op('office',oid,'quote_draft',{...p,expectedVersion:1,reason:'New review'});
  await op('office',oid,'quote_decision',decision,randomUUID(),true);
  await op('office',oid,'quote_decision',{...decision,version:2,decisions:[{lineId:lid,accepted:false}]});
  const o=(await snap('office')).orders.find(x=>x.id===oid);assert.deepEqual(o.quoteLedger.versions[0],quote1);assert.deepEqual(o.tasks[0],approved);assert.equal(o.parts.length,0);assert.equal((await snap('tech1')).orders.find(x=>x.id===oid).quoteLedger,undefined);
 });
 await check('Partial receipt, linked refund and settlement retain the exact issued document',async()=>{
  const original=(await snap('office')).orders.find(x=>x.id===cfg.orderId).document;assert.equal(original.totalCents,3300);
  const payment=await op('office',cfg.orderId,'payment_record',{amountCents:1500,method:'cash',paidAt:new Date().toISOString(),reference:'Recibo ficticio',reason:'Pago recibido ficticio'});
  assert.deepEqual(await rpc('office','apply_operation',{workshop_id:cfg.workshop,device_id:cfg.users.office.device,operation:payment.record}),payment.result);
  await op('office',cfg.orderId,'payment_reverse',{sourceId:payment.record.id,amountCents:500,paidAt:new Date().toISOString(),reference:'Devolución ficticia',reason:'Dinero devuelto ficticio'});
  await op('office',cfg.orderId,'payment_reverse',{sourceId:payment.record.id,amountCents:1001,paidAt:new Date().toISOString(),reference:'Denied',reason:'Excess'},randomUUID(),true);
  await op('office',cfg.orderId,'deliver',{reason:'Fictional office approves outstanding credit'});
  const credit=(await snap('office')).orders.find(x=>x.id===cfg.orderId).delivery;assert.equal(credit.outstandingCents,2300);
  await op('office',cfg.orderId,'payment_record',{amountCents:2300,method:'transfer',paidAt:new Date().toISOString(),reference:'Saldo ficticio',reason:'Settlement'});
  const o=(await snap('office')).orders.find(x=>x.id===cfg.orderId);assert.deepEqual(o.document,original);assert.deepEqual(o.delivery,credit);assert.equal((await snap('tech1')).orders.find(x=>x.id===cfg.orderId).payments,undefined);
 });
 await check('Administrator grants office cost management explicitly and the original denial stays enforced',async()=>{
  const s=await snap('admin');const member=s.members.find(x=>x.id===cfg.users.office.id);
  if(!member.seeCosts){assert.equal((await snap('office')).purchaseLedger,undefined);await cmd('office','inventory_command','purchase_create',{revision:0},randomUUID(),true);await cmd('admin','management_command','member_save',{revision:s.managementRevision,userId:cfg.users.office.id,name:'Fictional office',role:'office',seePrices:true,seeCosts:true,active:true,reason:'Explicit fictional cost-management permission'});}
  assert.ok((await snap('office')).purchaseLedger);assert.equal((await snap('tech1')).purchaseLedger,undefined);
 });
 await check('Purchase partial reception and supplier return preserve package quantities and original work',async()=>{
  const before=(await snap('office')).orders.find(x=>x.id===cfg.orderId),pid=randomUUID(),line=randomUUID();
  let s=await snap('office');const p={revision:s.purchaseLedger.revision,id:pid,supplier:'Proveedor ficticio',reference:'HTTP-PO',expectedAt:new Date(Date.now()+86400000).toISOString(),orderId:null,reason:'Fictional manual order',at:new Date().toISOString(),lines:[{id:line,itemId,packageSizeMilli:5000,packagesMilli:2000,unitCostCents:650}]};
  await cmd('office','inventory_command','purchase_create',p);s=await snap('office');await cmd('office','inventory_command','purchase_receive',{revision:s.purchaseLedger.revision,at:new Date().toISOString(),purchaseId:pid,lineId:line,packagesMilli:1000,reference:'Fictional receipt',reason:'Partial receipt'});s=await snap('office');
  await cmd('office','inventory_command','supplier_return',{revision:s.purchaseLedger.revision,at:new Date().toISOString(),purchaseId:pid,lineId:line,packagesMilli:500,reference:'Fictional supplier return',reason:'Returned half package'});s=await snap('office');assert.equal(s.catalog.find(x=>x.id===itemId).stockMilli,2500);assert.deepEqual(s.orders.find(x=>x.id===cfg.orderId),before);
  await cmd('tech1','inventory_command','purchase_create',p,randomUUID(),true);
 });
 await check('Warranty reception links the original repair without inheriting authorizations or changing its note',async()=>{
  const before=(await snap('office')).orders.find(x=>x.id===cfg.orderId),wid=randomUUID();await op('office',wid,'receive',{plate:cfg.plate??'9998FIC',country:'ES',vin:'HTTP-'+cfg.orderId,vehicle:'Vehículo ficticio',engine:'Prueba',client:'Cliente ficticio',phone:'',km:120,symptom:'Fictional warranty return',returnLink:{sourceOrderId:cfg.orderId,classification:'warranty',reason:'Fictional recurrence reviewed'},tasks:[{id:randomUUID(),title:'Nueva revisión',estimateMinutes:15,assignees:[cfg.users.tech1.id]}]});const s=await snap('office'),w=s.orders.find(x=>x.id===wid);assert.equal(w.returnHistory[0].sourceOrderId,cfg.orderId);assert.equal(w.tasks[0].authorized,false);assert.deepEqual(s.orders.find(x=>x.id===cfg.orderId),before);
 });
 let {conclusion,verification}=cfg.moduleFixture;
 await check('Diagnostic correction and withdrawal retain original human observations',async()=>{
  const first=await op('tech1',oid,'diagnosis_add',{stage:'result',text:'Resultado ficticio inicial',context:'Prueba',dtcs:'P0300',source:'Prueba manual',confirmed:false});
  const corrected=await op('tech1',oid,'diagnosis_add',{stage:'result',text:'Resultado ficticio corregido',replacesId:first.record.id,reason:'Repetición de medida',confirmed:true});
  await op('tech1',oid,'diagnosis_withdraw',{sourceId:corrected.record.id,reason:'Medición corregida retirada con evidencia'});
  conclusion=(await op('tech1',oid,'diagnosis_add',{stage:'conclusion',text:'Conclusión ficticia revisada',confirmed:true})).record.id;
  verification=(await op('tech1',oid,'diagnosis_add',{stage:'verification',text:'Verificación ficticia revisada',confirmed:true})).record.id;
  cfg.moduleFixture.conclusion=conclusion;cfg.moduleFixture.verification=verification;await save();
  const o=(await snap('tech1')).orders.find(x=>x.id===oid);assert.ok(o.diagnosisNotebook.some(x=>x.id===first.record.id&&x.text==='Resultado ficticio inicial'));assert.equal(o.parts.length,0);
 });
 await check('Case library requires technical/privacy review and hides drafts and source identities',async()=>{
  const content=Object.fromEntries(['title','vehicle','engine','symptom','dtcs','checks','result','conclusion','intervention','verification','sources'].map(k=>[k,'Fictional '+k]));const p={id:caseid,revision:0,sourceOrderId:oid,conclusionId:conclusion,verificationId:verification,content,reason:'Draft reviewed'};
  await cmd('tech1','case_command','case_draft',p);assert.equal((await snap('tech2')).caseLibrary.some(x=>x.id===caseid),false);
  await cmd('tech1','case_command','case_validate',{id:caseid,revision:1,version:1,technicalConfirmed:true,privacyConfirmed:false,reason:'Denied'},randomUUID(),true);
  await cmd('tech1','case_command','case_validate',{id:caseid,revision:1,version:1,technicalConfirmed:true,privacyConfirmed:true,reason:'Human reviewed'});
  const c=(await snap('tech2')).caseLibrary.find(x=>x.id===caseid);assert.ok(c);assert.equal(c.sourceOrderId,undefined);assert.equal(c.authorId,undefined);assert.equal(c.versions[0].conclusionId,undefined);
 });
 await check('Agenda enforces two operators, lift collisions, retries and private office evidence',async()=>{
  const lift=randomUUID(),bid=randomUUID();let s=await snap('admin');await cmd('admin','planning_command','schedule_resource',{id:lift,revision:s.planning.revision,name:'Elevador ficticio',active:true,reason:'Fictional resource'});
  s=await snap('office');const before=s.orders.find(x=>x.id===oid),p={id:bid,revision:s.planning.revision,title:'Cita ficticia',start:'2026-10-09T09:00:00Z',end:'2026-10-09T10:00:00Z',kind:'appointment',assignees:[cfg.users.tech1.id,cfg.users.tech2.id],liftId:lift,orderId:oid,reason:'Private office evidence'},id=randomUUID();const r=await cmd('office','planning_command','schedule_booking',p,id);assert.deepEqual(await cmd('office','planning_command','schedule_booking',p,id),r);
  s=await snap('office');await cmd('office','planning_command','schedule_booking',{...p,id:randomUUID(),revision:s.planning.revision},randomUUID(),true);assert.deepEqual(s.orders.find(x=>x.id===oid),before);const tech=(await snap('tech2')).planning;assert.equal(JSON.stringify(tech).includes('Private office evidence'),false);await cmd('tech1','planning_command','schedule_booking',p,randomUUID(),true);
 });
 await check('Maintenance records local calendar recurrence without mutating issued documents',async()=>{
  let s=await snap('office');const before=s.orders.find(x=>x.id===cfg.orderId),vid=s.orders.find(x=>x.id===oid).vehicleId,pid=randomUUID();await cmd('office','maintenance_command','care_plan',{id:pid,revision:s.maintenance.revision,vehicleId:vid,title:'Mantenimiento ficticio',source:'Criterio manual verificado',zone:'Europe/Madrid',dueDate:'2026-10-08',dueKm:130000,intervalMonths:12,intervalKm:15000,reason:'Fictional plan'});s=await snap('office');await cmd('office','maintenance_command','care_complete',{id:pid,revision:s.maintenance.revision,performedAt:'2026-09-30T22:30:00Z',km:129000,orderId:oid,evidence:'Fictional completed maintenance',reason:'Manual verified record'});s=await snap('office');const p=s.maintenance.plans.find(x=>x.id===pid);assert.equal(p.dueDate,'2027-10-01');assert.equal(p.dueKm,144000);assert.equal(p.completions[0].performedDate,'2026-10-01');assert.deepEqual(s.orders.find(x=>x.id===cfg.orderId),before);await cmd('tech1','maintenance_command','care_pause',{id:pid,revision:s.maintenance.revision,reason:'Denied'},randomUUID(),true);
 });
 await check('Fleet owner-bound memberships retain work and reject operator access',async()=>{
  let s=await snap('office');const o=s.orders.find(x=>x.id===oid),gid=randomUUID();await cmd('office','fleet_command','fleet_group',{id:gid,revision:s.fleets.revision,name:'Flota ficticia',organization:'Empresa ficticia',reason:'Manual reviewed group'});s=await snap('office');await cmd('office','fleet_command','fleet_attach',{id:gid,revision:s.fleets.revision,membershipId:randomUUID(),vehicleId:o.vehicleId,ownerId:o.ownerId,reference:'Unidad ficticia',evidence:'Fictional owner verified',reason:'Confirmed membership'});s=await snap('office');assert.deepEqual(s.orders.find(x=>x.id===oid),o);assert.equal((await snap('tech1')).fleets.groups.length,0);await cmd('tech1','fleet_command','fleet_group',{id:randomUUID(),revision:s.fleets.revision,name:'Denied',organization:'Denied',reason:'Denied'},randomUUID(),true);
 });
 await check('Format 14 export includes every new module and their command receipts',async()=>{
  const a=await rpc('admin','export_workshop',{workshop_id:cfg.workshop,device_id:cfg.users.admin.device});assert.equal(a.databaseVersion,14);for(const k of ['planning_state','maintenance_state','fleet_state','case_library','command_receipts'])assert.ok(a.tables[k].length>0,k);assert.ok(a.tables.orders.find(x=>x.id===cfg.orderId).data.payments.length===3);proof.operationCount=a.tables.operations.length;
 });
 proof.passed=true;
}catch(e){proof.error=e.message;console.error(e.message);process.exitCode=1;}
finally{for(const who of Object.keys(clients))await request('/auth/v1/logout?scope=local',who).catch(()=>{});await writeFile(evidence,JSON.stringify({...proof,totalChecks:checks.length},null,2));}
