import {PGlite} from '@electric-sql/pglite';
import {readFile,readdir} from 'node:fs/promises';
import assert from 'node:assert/strict';
let passed=0,seq=100;
const id=()=>`00000000-0000-4000-8000-${String(seq++).padStart(12,'0')}`;
const w=id(),admin=id(),tech=id(),sourceDev=id(),targetDev=id(),foreign=id(),order=id(),task=id(),item=id();
const migrations=(await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(f=>f.endsWith('.sql')).sort();
async function setup(){
 const db=new PGlite();
 await db.exec(`create role anon; create role authenticated; create role service_role; create schema auth; create table auth.users(id uuid primary key); create table auth.sessions(id uuid primary key,user_id uuid not null);
 create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
 grant usage on schema auth to authenticated; grant execute on function auth.uid() to authenticated;`);
await db.exec(await readFile(new URL('./storage_fixture.sql',import.meta.url),'utf8'));
 for(const f of migrations) await db.exec(await readFile(new URL(`../supabase/migrations/${f}`,import.meta.url),'utf8'));
 await db.query('insert into auth.users values($1),($2),($3)',[admin,tech,foreign]);
 await db.query("insert into private.workshops(id,name) values($1,'Recovery test')",[w]);
 await db.query("insert into private.members values($1,$2,'Admin','admin',true,true)",[w,admin]);
 return db;
}
async function login(db,user,dev){
 await db.exec('reset role');await db.query('insert into auth.sessions values($1,$2) on conflict do nothing',[dev,user]);
 await db.query("select set_config('request.jwt.claim.sub',$1,false)",[user]);
 await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:user,session_id:dev})]);await db.exec('set role authenticated');
}
async function snap(db,dev){return(await db.query('select public.device_snapshot($1,$2) r',[w,dev])).rows[0].r;}
async function test(name,fn){await fn();passed++;console.log('PASS '+name);}
const source=await setup();const target=await setup();const legacyTarget=await setup();let archive;
const closeOrder=id(),closeRequest=id(),accountRequest=id(),caseid=id(),portalOrder=id(),portalTask=id(),portalQuote=id(),portalLine=id(),grant=id(),customerDecision=id();
try{
 await source.query("insert into private.members values($1,$2,'Tech','technician',false,true)",[w,tech]);
 await source.query("insert into private.catalog(workshop_id,id,reference,description,unit,price_cents,cost_cents,stock_milli) values($1,$2,'OIL','Oil','L',1200,500,2000)",[w,item]);
 await login(source,admin,sourceDev);await snap(source,sourceDev);
 await source.query('select public.apply_operation($1,$2,$3)',[w,sourceDev,{id:id(),orderId:portalOrder,actorId:admin,kind:'receive',baseRevision:0,at:new Date().toISOString(),payload:{plate:'9999FIC',country:'ES',vin:'FICTIONAL-RECOVERY-PORTAL',vehicle:'Fictional',engine:'2020',client:'Fictional recipient',phone:'',km:100,symptom:'Fictional',tasks:[{id:portalTask,title:'Scope',assignees:[tech],estimateMinutes:30}]}}]);
 await source.query('select public.apply_operation($1,$2,$3)',[w,sourceDev,{id:id(),orderId:portalOrder,actorId:admin,kind:'quote_draft',baseRevision:1,at:new Date().toISOString(),payload:{id:portalQuote,expectedVersion:0,title:'Fictional quote',reason:'Recovery test',validUntil:new Date(Date.now()+86400000).toISOString(),lines:[{id:portalLine,taskId:portalTask,description:'Scope',laborMinutes:30,parts:[]}]}}]);
 const portalRevision=(await snap(source,sourceDev)).orders.find(o=>o.id===portalOrder).revision;
 await source.query('select public.portal_command($1,$2,$3,$4,$5)',[w,sourceDev,id(),'portal_create',{id:grant,orderId:portalOrder,revision:portalRevision,quoteId:portalQuote,quoteVersion:1,tokenHash:'a'.repeat(64),codeHash:'b'.repeat(64),expiresAt:new Date(Date.now()+3600000).toISOString(),recipientConfirmed:true,verificationEvidence:'Fictional recipient verified',photoIds:[],documentIds:[],reason:'Recovery access'}]);
 await source.exec('reset role;set role service_role');
 assert.equal((await source.query('select public.customer_portal($1,$2,$3,$4,$5,$6) r',[grant,'a'.repeat(64),'b'.repeat(64),'decide',customerDecision,{decisions:[{lineId:portalLine,accepted:true}]}])).rows[0].r.accepted,true);
 await login(source,admin,sourceDev);
 const data={plate:'1234ABC',country:'ES',vin:'VIN-TEST',vehicle:'Synthetic',engine:'2020',client:'Synthetic owner',phone:'',km:120,symptom:'Original symptom',tasks:[{id:task,title:'Test',assignees:[tech],estimateMinutes:30}]};
 let op={id:id(),orderId:order,actorId:admin,kind:'receive',baseRevision:0,at:new Date().toISOString(),payload:data};
 assert.equal((await source.query('select public.apply_operation($1,$2,$3) r',[w,sourceDev,op])).rows[0].r.status,'accepted');
 await source.exec('reset role');
 const document={issuedAt:'2026-10-06T00:00:00Z',revision:0,totalCents:12345,clientSnapshot:'Synthetic owner',lines:[],type:'Original immutable note'};
 await source.query("update private.orders set data=jsonb_set(data,'{document}',$1) where id=$2",[document,order]);
 await source.query("insert into private.documents(workshop_id,order_id,type,version,recipient_id,snapshot) values($1,$2,'work_note',1,$3,$4)",[w,order,admin,document]);
 await login(source,admin,sourceDev);
 const purchase=id(),purchaseLine=id();
 await source.query('select public.inventory_command($1,$2,$3,$4,$5)',[w,sourceDev,id(),'purchase_create',{revision:0,at:new Date().toISOString(),id:purchase,supplier:'Fictional recovery supplier',reference:'Recovery request',expectedAt:'2026-10-08T00:00:00Z',orderId:order,reason:'Fictional recovery purchase',lines:[{id:purchaseLine,itemId:item,packageSizeMilli:1000,packagesMilli:1000,unitCostCents:500}]}]);
 await source.query('select public.inventory_command($1,$2,$3,$4,$5)',[w,sourceDev,id(),'purchase_receive',{revision:1,at:new Date().toISOString(),purchaseId:purchase,lineId:purchaseLine,packagesMilli:1000,reference:'Fictional recovery delivery',reason:'Fictional material physically received'}]);
 const payment={id:id(),orderId:order,actorId:admin,kind:'payment_record',baseRevision:(await snap(source,sourceDev)).orders.find(o=>o.id===order).revision,at:new Date().toISOString(),payload:{amountCents:2345,method:'cash',paidAt:new Date().toISOString(),reference:'Fictional receipt for recovery',reason:'Already received'}};
 assert.equal((await source.query('select public.apply_operation($1,$2,$3) r',[w,sourceDev,payment])).rows[0].r.status,'accepted');
 op={id:id(),orderId:order,actorId:admin,kind:'note',baseRevision:0,at:new Date().toISOString(),payload:{text:'Original late evidence'}};
 assert.equal((await source.query('select public.apply_operation($1,$2,$3) r',[w,sourceDev,op])).rows[0].r.status,'late');
 await source.exec('reset role');
 await source.query('insert into private.orders(workshop_id,id,vehicle_id,data,revision) select workshop_id,$1,vehicle_id,$2,7 from private.orders where id=$3',[closeOrder,{...data,id:closeOrder,vehicleId:'historical',tasks:[],number:'Fictional closure'},order]);
 await source.query("insert into private.close_requests(workshop_id,id,order_id,revision,status,requested_by) values($1,$2,$3,7,'active',$4)",[w,closeRequest,closeOrder,admin]);
 await source.query('insert into private.order_devices(workshop_id,order_id,device_id) values($1,$2,$3)',[w,closeOrder,sourceDev]);
 await source.query('insert into private.close_acknowledgements(workshop_id,request_id,device_id,revision,confirmed_by) values($1,$2,$3,7,$4)',[w,closeRequest,sourceDev,admin]);
 await source.query('insert into private.account_requests(workshop_id,id,actor_id,device_id,session_id,payload) values($1,$2,$3,$4,$4,$5)',[w,accountRequest,admin,sourceDev,{name:'Fictional',email:'pending@example.invalid',role:'technician',seePrices:false,seeCosts:false,reason:'Training'}]);
 await login(source,admin,sourceDev);
 const conclusion=id(),verification=id();
 for(const [eid,stage] of [[conclusion,'conclusion'],[verification,'verification']]){
  const entry={id:eid,orderId:order,actorId:admin,kind:'diagnosis_add',baseRevision:0,at:new Date().toISOString(),payload:{stage,text:'Fictional '+stage,confirmed:true}};
  assert.equal((await source.query('select public.apply_operation($1,$2,$3) r',[w,sourceDev,entry])).rows[0].r.status,'accepted');
 }
 const content=Object.fromEntries(['title','vehicle','engine','symptom','dtcs','checks','result','conclusion','intervention','verification','sources'].map(k=>[k,'Fictional '+k]));
 await source.query('select public.case_command($1,$2,$3,$4,$5)',[w,sourceDev,id(),'case_draft',{id:caseid,revision:0,sourceOrderId:order,conclusionId:conclusion,verificationId:verification,content,reason:'Recovery draft'}]);
 await source.query('select public.case_command($1,$2,$3,$4,$5)',[w,sourceDev,id(),'case_validate',{id:caseid,revision:1,version:1,technicalConfirmed:true,privacyConfirmed:true,reason:'Human review'}]);
 const planningLift=id(),planningBooking=id();
 await source.query('select public.planning_command($1,$2,$3,$4,$5)',[w,sourceDev,id(),'schedule_resource',{id:planningLift,revision:0,name:'Recovery lift',active:true,reason:'Fictional configuration'}]);
 await source.query('select public.planning_command($1,$2,$3,$4,$5)',[w,sourceDev,id(),'schedule_booking',{id:planningBooking,revision:1,title:'Fictional recovery appointment',start:'2026-10-08T09:00:00Z',end:'2026-10-08T10:00:00Z',kind:'appointment',assignees:[tech],liftId:planningLift,orderId:order,reason:'Fictional recovered slot'}]);
 const careid=id();
 const vid=(await snap(source,sourceDev)).orders.find(o=>o.id===order).vehicleId;
 await source.query('select public.maintenance_command($1,$2,$3,$4,$5)',[w,sourceDev,id(),'care_plan',{id:careid,revision:0,vehicleId:vid,title:'Fictional oil',source:'Manual criterion',zone:'Europe/Madrid',dueDate:'2026-10-08',dueKm:130000,intervalMonths:12,intervalKm:15000,reason:'Recovery evidence'}]);
 await source.query('select public.maintenance_command($1,$2,$3,$4,$5)',[w,sourceDev,id(),'care_complete',{id:careid,revision:1,performedAt:'2026-10-06T12:00:00Z',km:129000,orderId:order,evidence:'Fictional completion',reason:'Recovery evidence'}]);
 const fleetid=id(),membershipid=id();
 const owner=(await snap(source,sourceDev)).orders.find(o=>o.id===order).ownerId;
 await source.query('select public.fleet_command($1,$2,$3,$4,$5)',[w,sourceDev,id(),'fleet_group',{id:fleetid,revision:0,name:'Fictional recovered fleet',organization:'Confirmed fictional manager',reason:'Recovery evidence'}]);
 await source.query('select public.fleet_command($1,$2,$3,$4,$5)',[w,sourceDev,id(),'fleet_attach',{id:fleetid,revision:1,membershipId:membershipid,vehicleId:vid,ownerId:owner,reference:'Fictional unit',evidence:'Original membership checked',reason:'Recovery evidence'}]);
 archive=(await source.query('select public.export_workshop($1,$2) r',[w,sourceDev])).rows[0].r;
 await test('Export contains documents, late originals, audit and all protocol tables, without Auth secrets',async()=>{
  assert.equal(archive.tables.documents[0].snapshot.totalCents,12345);
  assert.deepEqual(archive.tables.operations.find(x=>x.id===op.id).operation,op);
  assert.ok(archive.tables.audit.length);assert.ok(archive.tables.device_sessions.length);
  assert.equal(archive.authExcluded,true);assert.ok(!archive.tables.auth);assert.ok(!JSON.stringify(archive).includes('refresh_token'));
 });
 const techDevice=id();await login(source,tech,techDevice);await snap(source,techDevice);
 await test('Technician and anonymous cannot export private workshop data',async()=>{
  const dev=techDevice;
  await assert.rejects(()=>source.query('select public.export_workshop($1,$2)',[w,dev]),/Administrator/);
  await source.exec('reset role; set role anon');await assert.rejects(()=>source.query('select public.export_workshop($1,$2)',[w,sourceDev]),/permission denied/);
 });
 await login(target,admin,targetDev);await snap(target,targetDev);
 const rid=id();
 await test('Malformed cross-workshop archive is rejected atomically',async()=>{
  const bad=structuredClone(archive);bad.tables.catalog[0].workshop_id=id();
  await assert.rejects(()=>target.query('select public.restore_workshop($1,$2,$3,$4)',[w,targetDev,rid,bad]),/Cross-workshop/);
  assert.equal((await snap(target,targetDev)).orders.length,0);
 });
 await test('Missing Auth identity blocks restore without changing existing data',async()=>{
  const bad=structuredClone(archive);bad.tables.members[1].user_id=id();
  await assert.rejects(()=>target.query('select public.restore_workshop($1,$2,$3,$4)',[w,targetDev,rid,bad]),/Auth identities/);
  assert.equal((await snap(target,targetDev)).catalog.length,0);
 });
 await test('Malformed inventory ledger blocks restoration atomically',async()=>{
  const bad=structuredClone(archive);bad.tables.inventory_state[0].data={revision:2,orders:[]};
  await assert.rejects(()=>target.query('select public.restore_workshop($1,$2,$3,$4)',[w,targetDev,rid,bad]));
  assert.equal((await snap(target,targetDev)).catalog.length,0);
 });
 await test('Malformed or cross-workshop planning blocks restoration atomically',async()=>{
  for(const field of ['assignees','start','versions']) {
   const bad=structuredClone(archive),b=bad.tables.planning_state[0].data.bookings[0];
   b[field]=field==='assignees'?[id()]:field==='start'?'2026-02-30T09:00:00Z':[];
   await assert.rejects(()=>target.query('select public.restore_workshop($1,$2,$3,$4)',[w,targetDev,rid,bad]));
   assert.equal((await snap(target,targetDev)).orders.length,0);
  }
 });
 await test('Invalid maintenance archive rejects foreign vehicles, dates, versions and chronology atomically',async()=>{
  for(const field of ['vehicleId','dueDate','versions','completions']) {
   const bad=structuredClone(archive),p=bad.tables.maintenance_state[0].data.plans[0];
   p[field]=field==='vehicleId'?id():field==='dueDate'?'2026-02-30':field==='versions'?[]:[...p.completions,...p.completions];
   await assert.rejects(()=>target.query('select public.restore_workshop($1,$2,$3,$4)',[w,targetDev,rid,bad]));
   assert.equal((await snap(target,targetDev)).orders.length,0);
  }
 });
 await test('Malformed fleet recovery rejects foreign vehicles, actors, duplicate links and missing evidence atomically',async()=>{
  for(const field of ['vehicleId','addedBy','evidence','duplicate']) {
   const bad=structuredClone(archive),g=bad.tables.fleet_state[0].data.groups[0],m=g.memberships[0];
   if(field==='duplicate')g.memberships.push(structuredClone(m));else m[field]=field==='evidence'?'':id();
   await assert.rejects(()=>target.query('select public.restore_workshop($1,$2,$3,$4)',[w,targetDev,rid,bad]));
   assert.equal((await snap(target,targetDev)).orders.length,0);
  }
 });
 await test('Malformed case library blocks restoration atomically',async()=>{
  const bad=structuredClone(archive);bad.tables.case_library[0].data={revision:2,versions:[]};
  await assert.rejects(()=>target.query('select public.restore_workshop($1,$2,$3,$4)',[w,targetDev,rid,bad]));
  assert.equal((await snap(target,targetDev)).catalog.length,0);
 });
 let result;
 await test('Independent database restores original documents, records and audit',async()=>{
  result=(await target.query('select public.restore_workshop($1,$2,$3,$4) r',[w,targetDev,rid,archive])).rows[0].r;
  assert.equal(result.restored,true);const s=await snap(target,targetDev);
  assert.deepEqual(s.orders.find(o=>o.id===order).document,document);assert.equal(s.orders.find(o=>o.id===order).payments[0].id,payment.id);assert.equal(s.orders.find(o=>o.id===order).payments[0].amountCents,2345);assert.deepEqual(s.incidents.find(x=>x.operation.id===op.id).operation,op);
  assert.deepEqual(s.planning,archive.tables.planning_state[0].data);
  assert.deepEqual(s.fleets,archive.tables.fleet_state[0].data);
  assert.deepEqual(s.maintenance,archive.tables.maintenance_state[0].data);
  assert.deepEqual(s.caseLibrary[0].versions,archive.tables.case_library[0].data.versions);assert.equal(s.caseLibrary[0].activeVersion,1);assert.equal(s.caseLibrary[0].needsReview,false);
  assert.deepEqual(s.purchaseLedger,archive.tables.inventory_state[0].data);assert.equal(s.catalog.find(x=>x.id===item).stockMilli,3000);
  await target.exec('reset role');assert.equal((await target.query('select count(*)::int n from private.audit where source_id is not null')).rows[0].n,archive.tables.audit.length);
  await login(target,admin,targetDev);
 });
 await test('Restored portal links are disabled while original customer decisions and receipts survive',async()=>{
  const s=await snap(target,targetDev);assert.equal(s.portalGrants[0].restored,true);
  assert.equal(s.orders.find(o=>o.id===portalOrder).quoteLedger.decisions[0].id,customerDecision);
  await target.exec('reset role;set role service_role');
  assert.deepEqual((await target.query('select public.customer_portal($1,$2,$3,$4,$5,$6) r',[grant,'a'.repeat(64),'b'.repeat(64),'read',null,{}])).rows[0].r,{error:'access'});
  await target.exec('reset role');assert.equal((await target.query('select id from private.portal_receipts')).rows[0].id,customerDecision);
  await login(target,admin,targetDev);
 });
 await test('Restored acknowledgements remain historical, active closure is invalidated and account request cannot gain authority',async()=>{
  await target.exec('reset role');
  assert.equal((await target.query('select status from private.close_requests where id=$1',[closeRequest])).rows[0].status,'invalidated');
  assert.equal((await target.query('select revision from private.close_acknowledgements where request_id=$1',[closeRequest])).rows[0].revision,7);
  assert.equal((await target.query('select device_id from private.account_requests where id=$1',[accountRequest])).rows[0].device_id,sourceDev);
  await target.exec('set role service_role');await assert.rejects(()=>target.query('select public.account_provision_state($1,$2)',[w,accountRequest]),/no longer authorized/);
  await login(target,admin,targetDev);
 });
 await test('Lost restoration reply can be retried without duplicate documents or original operations',async()=>{
  assert.deepEqual((await target.query('select public.restore_workshop($1,$2,$3,$4) r',[w,targetDev,rid,archive])).rows[0].r,result);
  await target.exec('reset role');assert.equal((await target.query('select count(*)::int n from private.documents')).rows[0].n,1);await login(target,admin,targetDev);
 });
 await test('Same restore ID with changed content and restore over populated workshop are rejected',async()=>{
  const bad=structuredClone(archive);bad.workshop.name='Changed';
  await assert.rejects(()=>target.query('select public.restore_workshop($1,$2,$3,$4)',[w,targetDev,rid,bad]),/Restore ID reused/);
  await assert.rejects(()=>target.query('select public.restore_workshop($1,$2,$3,$4)',[w,targetDev,id(),archive]),/empty isolated/);
 });
 await test('Historical device sessions stay retired and cannot mint another editing identity',async()=>{
  await login(target,admin,sourceDev);
  await assert.rejects(()=>snap(target,sourceDev),/retired/);
  await assert.rejects(()=>snap(target,id()),/retired/);
  await login(target,admin,targetDev);
 });
 await test('Restored issued document remains immutable and further records remain late',async()=>{
  await target.exec('reset role');await assert.rejects(()=>target.query("update private.documents set snapshot='{}' where workshop_id=$1",[w]),/immutable/);
  await login(target,admin,targetDev);const late={...op,id:id(),payload:{text:'After restoration'}};
  assert.equal((await target.query('select public.apply_operation($1,$2,$3) r',[w,targetDev,late])).rows[0].r.status,'late');
  assert.deepEqual((await snap(target,targetDev)).orders.find(o=>o.id===order).document,document);
 });
 await test('Version seven archives remain recoverable without a purchase table',async()=>{
  const legacy=structuredClone(archive);legacy.databaseVersion=7;delete legacy.tables.fleet_state;delete legacy.tables.maintenance_state;delete legacy.tables.inventory_state;delete legacy.tables.case_library;
  const dev=id();await login(legacyTarget,admin,dev);await snap(legacyTarget,dev);
  await legacyTarget.query('select public.restore_workshop($1,$2,$3,$4)',[w,dev,id(),legacy]);
  assert.equal((await snap(legacyTarget,dev)).purchaseLedger.revision,0);
 });
 await test('Version eight archive restores with an empty case library',async()=>{
  const old=await setup();try{const oldDev=id();await login(old,admin,oldDev);await snap(old,oldDev);
   const legacy=structuredClone(archive);legacy.databaseVersion=8;delete legacy.tables.fleet_state;delete legacy.tables.maintenance_state;delete legacy.tables.case_library;
   await old.query('select public.restore_workshop($1,$2,$3,$4)',[w,oldDev,id(),legacy]);
   assert.deepEqual((await snap(old,oldDev)).caseLibrary,[]);assert.deepEqual((await snap(old,oldDev)).purchaseLedger,archive.tables.inventory_state[0].data);
  }finally{await old.close();}
 });
 await test('Version nine archive restores without reactivating any customer link',async()=>{
  const old=await setup();try{const oldDev=id();await login(old,admin,oldDev);await snap(old,oldDev);
   const legacy=structuredClone(archive);legacy.databaseVersion=9;delete legacy.tables.fleet_state;delete legacy.tables.maintenance_state;delete legacy.tables.portal_grants;delete legacy.tables.portal_receipts;
   await old.query('select public.restore_workshop($1,$2,$3,$4)',[w,oldDev,id(),legacy]);
   assert.deepEqual((await snap(old,oldDev)).portalGrants,[]);assert.equal((await snap(old,oldDev)).caseLibrary.length,1);
  }finally{await old.close();}
 });
 await test('Version ten restores without an agenda and preserves portal revocation',async()=>{
  const old=await setup();try{const oldDev=id();await login(old,admin,oldDev);await snap(old,oldDev);
   const legacy=structuredClone(archive);legacy.databaseVersion=10;delete legacy.tables.fleet_state;delete legacy.tables.maintenance_state;delete legacy.tables.planning_state;
   await old.query('select public.restore_workshop($1,$2,$3,$4)',[w,oldDev,id(),legacy]);
   assert.equal((await snap(old,oldDev)).planning.revision,0);assert.equal((await snap(old,oldDev)).portalGrants[0].restored,true);
  }finally{await old.close();}
 });
 await test('Version eleven restores agenda and starts empty maintenance while retaining original evidence',async()=>{
  const old=await setup();try{const oldDev=id();await login(old,admin,oldDev);await snap(old,oldDev);
   const legacy=structuredClone(archive);legacy.databaseVersion=11;delete legacy.tables.fleet_state;delete legacy.tables.maintenance_state;
   await old.query('select public.restore_workshop($1,$2,$3,$4)',[w,oldDev,id(),legacy]);
   assert.equal((await snap(old,oldDev)).maintenance.revision,0);assert.deepEqual((await snap(old,oldDev)).planning,archive.tables.planning_state[0].data);
  }finally{await old.close();}
 });
 await test('Version twelve restores original maintenance with fleets initially empty',async()=>{
  const old=await setup();try{const oldDev=id();await login(old,admin,oldDev);await snap(old,oldDev);
   const legacy=structuredClone(archive);legacy.databaseVersion=12;delete legacy.tables.fleet_state;
   await old.query('select public.restore_workshop($1,$2,$3,$4)',[w,oldDev,id(),legacy]);
   assert.deepEqual((await snap(old,oldDev)).fleets,{revision:0,groups:[]});assert.deepEqual((await snap(old,oldDev)).maintenance,archive.tables.maintenance_state[0].data);
  }finally{await old.close();}
 });
 console.log(`${passed} backup checks passed in two independent PostgreSQL/PGlite databases. Hosted Auth and native files remain separate validations.`);
}finally{await source.close();await target.close();await legacyTarget.close();}
