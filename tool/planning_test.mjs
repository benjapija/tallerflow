import {PGlite} from '@electric-sql/pglite';import {readFile,readdir} from 'node:fs/promises';import assert from 'node:assert/strict';
let seq=19000,passed=0;const id=()=>`00000000-0000-4000-8000-${String(seq++).padStart(12,'0')}`;
const w=id(),other=id(),admin=id(),office=id(),a=id(),b=id(),ad=id(),od=id(),td=id(),order=id(),lift=id(),booking=id(),task=id();const db=new PGlite();
await db.exec("create role anon;create role authenticated;create role service_role;create schema auth;create table auth.users(id uuid primary key);create table auth.sessions(id uuid primary key,user_id uuid not null);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;");await db.exec(await readFile(new URL('./storage_fixture.sql',import.meta.url),'utf8'));
for(const f of (await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(x=>x.endsWith('.sql')).sort())await db.exec(await readFile(new URL(`../supabase/migrations/${f}`,import.meta.url),'utf8'));
await db.query('insert into auth.users values($1),($2),($3),($4)',[admin,office,a,b]);await db.query("insert into private.workshops(id,name) values($1,'Fictional agenda'),($2,'Isolated workshop')",[w,other]);
await db.query("insert into private.members values($1,$2,'Admin','admin',true,true),($1,$3,'Office','office',true,true),($1,$4,'Tech A','technician',false,true),($1,$5,'Tech B','technician',false,true),($6,$2,'Admin','admin',true,true)",[w,admin,office,a,b,other]);
let dev=ad;async function login(user,device){await db.exec('reset role');await db.query('insert into auth.sessions values($1,$2) on conflict do nothing',[device,user]);await db.query("select set_config('request.jwt.claim.sub',$1,false)",[user]);await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:user,session_id:device})]);await db.exec('set role authenticated');dev=device;await snap();}
const snap=async()=>(await db.query('select public.device_snapshot($1,$2) r',[w,dev])).rows[0].r;
const command=async(action,p,cid=id())=>(await db.query('select public.planning_command($1,$2,$3,$4,$5) r',[w,dev,cid,action,p])).rows[0].r;
const reserve=async(overrides={})=>({id:booking,revision:(await snap()).planning.revision,title:'Fictional private reception',start:'2026-10-08T09:00:00+02:00',end:'2026-10-08T10:00:00+02:00',kind:'appointment',assignees:[a,b],liftId:lift,orderId:order,reason:'Private office evidence',...overrides});
const test=async(name,fn)=>{await fn();passed++;console.log('PASS '+name);};
try{
 await login(admin,ad);await db.query('select public.apply_operation($1,$2,$3)',[w,dev,{id:id(),orderId:order,actorId:admin,kind:'receive',baseRevision:0,at:new Date().toISOString(),payload:{plate:'9301FIC',country:'ES',vin:'FICTIONAL-AGENDA',vehicle:'Fictional',engine:'2020',client:'Fictional',phone:'',km:100,symptom:'Fictional',tasks:[{id:task,title:'Diagnosis',estimateMinutes:30,assignees:[a]}]}}]);
 await test('Admin configures lifts; office and technicians cannot change resources',async()=>{
  await command('schedule_resource',{id:lift,revision:0,name:'Lift 1',active:true,reason:'Fictional configuration'});
  await login(office,od);await assert.rejects(()=>command('schedule_resource',{id:id(),revision:1,name:'Lift 2',active:true,reason:'Attempt'}),/Administrator/);await login(a,td);await assert.rejects(()=>command('schedule_booking',{}),/Office/);await login(office,od);
 });
 let p,cid=id();
 await test('Office reserves several technicians and lift without billing or changing repair',async()=>{
  const before=(await snap()).orders[0];p=await reserve();await command('schedule_booking',p,cid);const s=await snap();assert.deepEqual(s.orders[0],before);assert.equal(Date.parse(s.planning.bookings[0].start),Date.parse('2026-10-08T07:00:00Z'));assert.equal(s.planning.bookings[0].assignees.length,2);
 });
 await test('Lost response retries once; different payload with same ID is rejected',async()=>{
  assert.equal((await command('schedule_booking',p,cid)).saved,true);assert.equal((await snap()).planning.bookings.length,1);await assert.rejects(()=>command('schedule_booking',{...p,title:'Changed'},cid),/ID reused/);
 });
 await test('Stale simultaneous reservation cannot replace newer agenda',async()=>{
  await assert.rejects(()=>command('schedule_booking',{...p,id:id()}),/revision conflict/);assert.equal((await snap()).planning.revision,2);
 });
 await test('Any shared technician or lift blocks an overlapping appointment',async()=>{
  for(const overrides of [{id:id(),assignees:[]},{id:id(),liftId:null,assignees:[b]},{id:id(),liftId:null,assignees:[a]}])await assert.rejects(async()=>command('schedule_booking',await reserve(overrides)),/Overlapping/);
 });
 await test('Foreign order, duplicate members and missing or invalid timezone are rejected atomically',async()=>{
  for(const overrides of [{orderId:id()},{assignees:[a,a]},{assignees:[office]},{assignees:[id()]},{liftId:id()},{start:'2026-10-08T09:00'},{start:'2026-02-30T09:00:00Z'},{end:'2026-10-08T08:00:00+02:00'},{end:'2026-10-16T09:00:00Z'},{assignees:[],liftId:null}])await assert.rejects(async()=>command('schedule_booking',await reserve({...overrides,id:id()})));
  assert.equal((await snap()).planning.bookings.length,1);
 });
 await test('Technician sees own slots without office history or unassigned repair identifiers',async()=>{
  const hidden=id();await command('schedule_booking',await reserve({id:hidden,start:'2026-10-08T10:00:00+02:00',end:'2026-10-08T11:00:00+02:00',assignees:[a],title:'Private other appointment'}));
  await login(b,id());const s=await snap();assert.equal(s.planning.bookings.length,1);assert.equal(s.planning.bookings[0].orderId,null);assert.deepEqual(s.planning.bookings[0].events,[]);assert.equal(s.planning.resources[0].events,undefined);assert.equal(JSON.stringify(s.planning).includes('Private office evidence'),false);await login(office,od);
 });
 await test('Reprogramming preserves original slot, finishing and cancelling never erase versions',async()=>{
  await command('schedule_booking',await reserve({start:'2026-10-08T12:00:00+02:00',end:'2026-10-08T13:00:00+02:00'}));
  let s=await snap(),row=s.planning.bookings.find(x=>x.id===booking);assert.equal(row.versions.length,2);assert.equal(Date.parse(row.versions[0].start),Date.parse('2026-10-08T07:00:00Z'));
  await command('schedule_status',{id:booking,revision:s.planning.revision,status:'cancelled',reason:'Fictional cancellation'});await assert.rejects(async()=>command('schedule_booking',await reserve()),/finished/);
  s=await snap();assert.equal(s.planning.bookings.find(x=>x.id===booking).events.length,3);
 });
 await test('Indisponibility blocks slots, adjacent windows work, future reservations prevent lift retirement',async()=>{
  await command('schedule_booking',await reserve({id:id(),kind:'unavailable',orderId:null}));await assert.rejects(async()=>command('schedule_booking',await reserve({id:id()})),/Overlapping/);
  await login(admin,ad);await assert.rejects(async()=>command('schedule_resource',{id:lift,revision:(await snap()).planning.revision,name:'Lift 1',active:false,reason:'Retire'}),/Reassign/);
 });
 await test('Another workshop cannot see agenda; anonymous cannot call RPC or tables',async()=>{
  const s=(await db.query('select public.workshop_snapshot($1) r',[other])).rows[0].r;assert.equal(s.planning.bookings.length,0);await assert.rejects(()=>db.query('select * from private.planning_state'),/permission denied/);
  await db.exec('reset role;set role anon');await assert.rejects(()=>db.query('select public.planning_command($1,$2,$3,$4,$5)',[w,ad,id(),'schedule_status',{}]),/permission denied/);await login(admin,ad);
 });
 await test('Complete archive includes versioned agenda and command evidence',async()=>{
  const archive=(await db.query('select public.export_workshop($1,$2) r',[w,ad])).rows[0].r;assert.equal(archive.databaseVersion,12);assert.deepEqual(archive.tables.planning_state[0].data,(await snap()).planning);assert.ok(archive.tables.command_receipts.find(r=>r.id===cid));assert.equal(archive.tables.audit.filter(r=>r.kind==='schedule_booking').length,4);
 });
 await test('Revoked session stops queued reservations and replay',async()=>{
  await db.exec('reset role');await db.query('delete from auth.sessions where id=$1',[ad]);await db.exec('set role authenticated');await assert.rejects(()=>command('schedule_booking',p,cid),/session/);
 });
 console.log(`${passed} planning checks passed in PostgreSQL/PGlite with synthetic Auth.`);
}finally{await db.close();}
