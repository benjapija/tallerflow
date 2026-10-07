import { PGlite } from '@electric-sql/pglite';
import { readFile, readdir } from 'node:fs/promises';
import assert from 'node:assert/strict';
const db = new PGlite();
let seq=1,passed=0;const id=()=>`00000000-0000-4000-8000-${String(seq++).padStart(12,'0')}`;
const w=id(),w2=id(),office=id(),tech=id(),foreign=id(),desk=id(),phone=id(),otherDesk=id(),order=id(),task=id(),newOwner=id();
await db.exec(`create role anon;create role authenticated;create role service_role;create schema auth;
create table auth.users(id uuid primary key);create table auth.sessions(id uuid primary key,user_id uuid not null);
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;`);
await db.exec(await readFile(new URL('./storage_fixture.sql',import.meta.url),'utf8'));
for(const f of (await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(f=>f.endsWith('.sql')).sort()) await db.exec(await readFile(new URL(`../supabase/migrations/${f}`,import.meta.url),'utf8'));
await db.query('insert into auth.users values($1),($2),($3)',[office,tech,foreign]);
await db.query("insert into private.workshops(id,name) values($1,'Synthetic'),($2,'Other workshop')",[w,w2]);
await db.query("insert into private.members values($1,$2,'Office','admin',true,true),($1,$3,'Tech','technician',false,true),($4,$5,'Foreign','admin',true,true)",[w,office,tech,w2,foreign]);
let who,dev;
async function login(user,device){who=user;dev=device;await db.exec('reset role');await db.query('insert into auth.sessions values($1,$2) on conflict do nothing',[device,user]);await db.query("select set_config('request.jwt.claim.sub',$1,false)",[user]);await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:user,session_id:device})]);await db.exec('set role authenticated');}
async function snap(ws=w){return (await db.query('select public.device_snapshot($1,$2) r',[ws,dev])).rows[0].r;}
async function receive(data,oid=id()) {const op={id:id(),orderId:oid,actorId:who,kind:'receive',at:new Date().toISOString(),baseRevision:0,payload:data};return (await db.query('select public.apply_operation($1,$2,$3) r',[w,dev,op])).rows[0].r;}
async function change(p,cid=id(),ws=w){return (await db.query("select public.vehicle_command($1,$2,$3,'vehicle_change',$4) r",[ws,dev,cid,p])).rows[0].r;}
async function test(name,fn){await fn();passed++;console.log(`PASS ${name}`);}
const data={plate:'12-34 ABC',country:'es',vin:'SYNTHETICVINONE',vehicle:'Fictional vehicle',engine:'Fictional engine',client:'Original fictitious recipient',phone:'600000001',km:100,symptom:'Original symptom',location:'Bay',keys:'Board',due:'Today',priority:'Normal',tasks:[{id:task,title:'Task',assignees:[tech],estimateMinutes:30}]};
try{
 await login(office,desk);await snap();assert.equal((await receive(data,order)).status,'accepted');
 let s=await snap(),v=s.vehicleProfiles[0],vid=v.id;const originalOwner=s.orders[0].ownerId;
 const doc={type:'work_note',clientSnapshot:data.client,plateSnapshot:'1234ABC',totalCents:1234};
 await db.exec('reset role');await db.query("insert into private.documents(workshop_id,id,order_id,type,version,recipient_id,snapshot) values($1,$2,$3,'work_note',1,$4,$5)",[w,id(),order,id(),doc]);await db.query("update private.orders set data=data||jsonb_build_object('document',$3::jsonb) where workshop_id=$1 and id=$2",[w,order,doc]);await login(office,desk);
 await test('Registration changes retain stable ID, original document and technical data',async()=>{
  const p={vehicleId:vid,revision:v.revision,change:'registration',plate:'98-76 xyz',country:'ES',vin:data.vin,reason:'Synthetic registration checked'},cid=id();
  assert.deepEqual(await change(p,cid),await change(p,cid));s=await snap();v=s.vehicleProfiles[0];assert.equal(v.id,vid);assert.equal(v.plate,'9876XYZ');assert.equal(v.engine,data.engine);assert.equal(v.identifiers.filter(i=>i.kind==='plate').length,2);
  assert.deepEqual(s.orders.find(o=>o.id===order).document,doc);assert.equal(s.orders.find(o=>o.id===order).plate,'1234ABC');
  await assert.rejects(()=>change({...p,reason:'Stale'}),/revision conflict/);
  await assert.rejects(()=>change({...p,reason:'Reused'},cid),/ID reused/);
 });
 await test('Previous registration finds the same car and recipient on a later visit',async()=>{
  assert.equal((await receive(data)).status,'accepted');s=await snap();assert.equal(s.orders.length,2);assert(s.orders.every(o=>o.vehicleId===vid&&o.ownerId===originalOwner));assert.equal(s.orders.find(o=>o.id!==order).plate,'9876XYZ');
 });
 await test('Owner transfer leaves every previous recipient and issued document unchanged',async()=>{
  v=(await snap()).vehicleProfiles[0];await change({vehicleId:vid,revision:v.revision,change:'owner',ownerId:newOwner,name:'New fictitious recipient',phone:'600000002',reason:'Synthetic ownership checked'});
  s=await snap();assert.equal(s.vehicleProfiles[0].ownerId,newOwner);assert(s.orders.every(o=>o.ownerId===originalOwner));assert.deepEqual(s.orders.find(o=>o.id===order).document,doc);
  await db.exec('reset role');const refs=(await db.query('select * from private.order_recipient_refs where workshop_id=$1',[w])).rows;assert(refs.every(r=>r.owner_id===originalOwner));await login(office,desk);
 });
 await test('New visits use the new recipient; stale offline owner data is retained as conflict',async()=>{
  assert.equal((await receive({...data,client:'New fictitious recipient',phone:'600000002'})).status,'accepted');
  const r=await receive(data);assert.equal(r.status,'conflict');assert.match(r.reason,/Confirm owner/);
  s=await snap();assert.equal(s.orders.length,3);const latest=s.orders.find(o=>o.ownerId===newOwner);assert(latest);assert.equal(latest.document,undefined);assert.equal(latest.vehicleId,vid);
 });
 await test('An earlier recipient ID cannot be renamed into a new owner',async()=>{
  v=(await snap()).vehicleProfiles[0];await assert.rejects(()=>change({vehicleId:vid,revision:v.revision,change:'owner',ownerId:originalOwner,name:'Impersonation',phone:'',reason:'Invalid'}),/New recipient/);
 });
 await login(tech,phone);await snap();
 await test('Technicians see technical history without recipient details or personal documents',async()=>{
  s=await snap();assert.equal(s.vehicleHistory.length,3);assert(s.vehicleHistory.every(h=>h.recipient===undefined&&h.document===undefined&&h.ownerId===undefined));assert.equal(s.vehicleProfiles[0].owner,null);assert.equal(s.vehicleHistory[0].symptom,data.symptom);assert.equal(s.vehicleHistory[0].tasks[0].authorization,undefined);
  await assert.rejects(()=>change({vehicleId:vid,revision:0,change:'owner'}),/Office/);
 });
 await test('Anonymous access and direct recipient mutation remain denied',async()=>{
  await assert.rejects(()=>db.exec("update private.order_recipient_refs set owner_id=gen_random_uuid()"),/permission denied/);
  await db.exec('reset role;set role anon');await assert.rejects(()=>snap(),/permission denied/);await login(office,desk);
  await db.exec('reset role');await assert.rejects(()=>db.query('update private.order_recipient_refs set owner_id=$2 where workshop_id=$1',[w,newOwner]),/immutable/);await login(office,desk);
 });
 await test('Workshop isolation and ambiguous registration/VIN prevent cross-linking',async()=>{
  const other={...data,plate:'OTHER CAR',vin:'SYNTHETICVINTWO',client:'Other client'};assert.equal((await receive(other)).status,'accepted');
  const r=await receive({...other,plate:'9876 XYZ'});assert.equal(r.status,'conflict');assert.match(r.reason,/different vehicles/);
  await login(foreign,otherDesk);await snap(w2);await assert.rejects(()=>change({vehicleId:vid,revision:0,change:'owner'}),/Membership/);await login(office,desk);
 });
 await test('Full export includes immutable recipients, aliases and changes without transferring document access',async()=>{
  const a=(await db.query('select public.export_workshop($1,$2) r',[w,dev])).rows[0].r;
  assert.equal(a.databaseVersion,13);assert.equal(a.tables.vehicle_changes.length,2);assert.equal(a.tables.order_recipient_refs.length,4);assert(a.tables.vehicle_identifiers.some(i=>i.value==='1234ABC'));assert.deepEqual(a.tables.documents[0].snapshot,doc);
 });
 console.log(`${passed} vehicle PostgreSQL integration tests passed (local PGlite, synthetic Auth)`);
}finally{await db.close();}
