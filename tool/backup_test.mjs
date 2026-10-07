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
const source=await setup();const target=await setup();let archive;
const closeOrder=id(),closeRequest=id(),accountRequest=id();
try{
 await source.query("insert into private.members values($1,$2,'Tech','technician',false,true)",[w,tech]);
 await source.query("insert into private.catalog(workshop_id,id,reference,description,unit,price_cents,cost_cents,stock_milli) values($1,$2,'OIL','Oil','L',1200,500,2000)",[w,item]);
 await login(source,admin,sourceDev);await snap(source,sourceDev);
 const data={plate:'1234ABC',country:'ES',vin:'VIN-TEST',vehicle:'Synthetic',engine:'2020',client:'Synthetic owner',phone:'',km:120,symptom:'Original symptom',tasks:[{id:task,title:'Test',assignees:[tech],estimateMinutes:30}]};
 let op={id:id(),orderId:order,actorId:admin,kind:'receive',baseRevision:0,at:new Date().toISOString(),payload:data};
 assert.equal((await source.query('select public.apply_operation($1,$2,$3) r',[w,sourceDev,op])).rows[0].r.status,'accepted');
 await source.exec('reset role');
 const document={issuedAt:'2026-10-06T00:00:00Z',revision:0,totalCents:12345,clientSnapshot:'Synthetic owner',lines:[],type:'Original immutable note'};
 await source.query("update private.orders set data=jsonb_set(data,'{document}',$1) where id=$2",[document,order]);
 await source.query("insert into private.documents(workshop_id,order_id,type,version,recipient_id,snapshot) values($1,$2,'work_note',1,$3,$4)",[w,order,admin,document]);
 await login(source,admin,sourceDev);
 const payment={id:id(),orderId:order,actorId:admin,kind:'payment_record',baseRevision:(await snap(source,sourceDev)).orders[0].revision,at:new Date().toISOString(),payload:{amountCents:2345,method:'cash',paidAt:new Date().toISOString(),reference:'Fictional receipt for recovery',reason:'Already received'}};
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
 let result;
 await test('Independent database restores original documents, records and audit',async()=>{
  result=(await target.query('select public.restore_workshop($1,$2,$3,$4) r',[w,targetDev,rid,archive])).rows[0].r;
  assert.equal(result.restored,true);const s=await snap(target,targetDev);
  assert.deepEqual(s.orders.find(o=>o.id===order).document,document);assert.equal(s.orders.find(o=>o.id===order).payments[0].id,payment.id);assert.equal(s.orders.find(o=>o.id===order).payments[0].amountCents,2345);assert.deepEqual(s.incidents.find(x=>x.operation.id===op.id).operation,op);
  await target.exec('reset role');assert.equal((await target.query('select count(*)::int n from private.audit where source_id is not null')).rows[0].n,archive.tables.audit.length);
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
 console.log(`${passed} backup checks passed in two independent PostgreSQL/PGlite databases. Hosted Auth and native files remain separate validations.`);
}finally{await source.close();await target.close();}
