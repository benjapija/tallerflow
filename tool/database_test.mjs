import { PGlite } from '@electric-sql/pglite';
import { readFile, readdir } from 'node:fs/promises';
import assert from 'node:assert/strict';
const db = new PGlite();
let passed = 0;
const tech='11111111-1111-4111-8111-111111111111';
const office='22222222-2222-4222-8222-222222222222';
const other='33333333-3333-4333-8333-333333333333';
const w='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const w2='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const order='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const task='dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const task2='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const part='ffffffff-ffff-4fff-8fff-ffffffffffff';
const device='00000000-0000-4000-8000-000000000001';
const techDevice='00000000-0000-4000-8000-000000000002';
let sequence=10;
const id=()=>`00000000-0000-4000-8000-${String(sequence++).padStart(12,'0')}`;
await db.exec(`create role anon; create role authenticated; create role service_role;
create schema auth; create table auth.users(id uuid primary key); create table auth.sessions(id uuid primary key,user_id uuid not null);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
grant usage on schema auth to authenticated; grant execute on function auth.uid() to authenticated;`);
for (const file of (await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(f=>f.endsWith('.sql')).sort()) await db.exec(await readFile(new URL(`../supabase/migrations/${file}`,import.meta.url),'utf8'));
let currentUser=office;
const currentDevice=()=>currentUser===tech?techDevice:currentUser===office?device:'00000000-0000-4000-8000-000000000003';
await db.query('insert into auth.users values($1),($2),($3)',[tech,office,other]);
await db.query('insert into private.workshops(id,name) values($1,$2),($3,$4)',[w,'Demo A',w2,'Demo B']);
await db.query("insert into private.members values($1,$2,'Tech A','technician',false,true),($1,$3,'Office A','office',true,true),($4,$5,'Office B','office',true,true)",[w,tech,office,w2,other]);
await db.query("insert into private.catalog(workshop_id,id,reference,description,unit,price_cents,cost_cents,stock_milli) values($1,$2,'OIL','Oil','L',1450,650,48000)",[w,part]);
const data={plate:'48-21 lkr',country:'ES',vin:'',vehicle:'Vehicle demo',engine:'2020',client:'Synthetic client',phone:'',km:100,symptom:'Original symptom',location:'Bay 1',keys:'Key board',due:'Today',priority:'Normal',tasks:[{id:task,title:'Diagnosis',authorized:true,done:false,assignees:[tech],estimateMinutes:30,billableMinutes:50,rateCents:999999,taxBps:0,approvedCents:999999},{id:task2,title:'Extension',assignees:[tech],estimateMinutes:30}]};
async function login(user) {currentUser=user;await db.exec('reset role');await db.query('insert into auth.sessions values($1,$2) on conflict do nothing',[currentDevice(),user]);await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:user,session_id:currentDevice()})]);await db.query("select set_config('request.jwt.claim.sub',$1,false)",[user]);await db.exec('set role authenticated');}
async function push(kind,payload,opts={}) {
 const op={id:opts.id??id(),orderId:opts.orderId??order,kind,actorId:opts.actor??office,baseRevision:opts.revision??0,at:opts.at??new Date().toISOString(),payload};
 await snapshot(opts.workshop??w);
 const r=await db.query('select public.apply_operation($1,$2,$3) result',[opts.workshop??w,opts.device??(op.actorId===tech?techDevice:device),op]);return {op,result:r.rows[0].result};
}
async function snapshot(workshop=w){return (await db.query('select public.device_snapshot($1,$2) result',[workshop,currentDevice()])).rows[0].result;}
async function test(name,fn){await fn();passed++;console.log(`PASS ${name}`);}
try {
 await login(office);
 const receive=await push('receive',data);
 await test('Reception canonicalizes plate and refuses injected approval/prices',async()=>{
  assert.equal(receive.result.status,'accepted');const o=(await snapshot()).orders[0];assert.equal(o.plate,'4821LKR');assert.equal(o.tasks[0].authorized,false);assert.equal(o.tasks[0].billableMinutes,0);assert.equal(o.tasks[0].rateCents,4800);
 });
 await test('Duplicate reception tasks are retained as a conflict without creating an order or another vehicle',async()=>{
  const r=await push('receive',{...data,plate:'FICT DUP',tasks:[data.tasks[0],data.tasks[0]]},{orderId:id()});
  assert.equal(r.result.status,'conflict');assert.match(r.result.reason,/Duplicate reception/);
  assert.equal((await snapshot()).orders.length,1);
 });
 await test('Direct table mutation is denied to authenticated clients',async()=>{await assert.rejects(()=>db.exec("update private.members set role='admin'"),/permission denied/);});
 await test('Workshop isolation and anonymous reads are enforced',async()=>{
  await assert.rejects(()=>snapshot(w2),/Membership required/);await db.exec('reset role;set role anon');await assert.rejects(()=>snapshot(),/permission denied/);await login(office);
 });
 const revision=async()=>(await snapshot()).orders[0].revision;
 await push('authorize',{taskId:task,approvedCents:50000,customer:'Synthetic client',version:1,evidence:'Telephone'}, {revision:await revision()});
 await login(tech);
 await test('Technician receives assigned data without money or prior documents',async()=>{
  const s=await snapshot();assert.equal(s.orders.length,1);assert.equal(JSON.stringify(s).includes('priceCents'),false);assert.equal(JSON.stringify(s).includes('rateCents'),false);assert.equal(JSON.stringify(s).includes('costCents'),false);
 });
 await test('Technician cannot authorize or forge a different actor',async()=>{
  await assert.rejects(()=>push('authorize',{taskId:task,approvedCents:90000},{actor:tech}),/Office permission required/);
  await assert.rejects(()=>push('note',{text:'Spoofed identity'},{actor:office}),/Actor mismatch/);
 });
 let timer;
 await test('Authorized timer starts; retry has exactly one effect',async()=>{
  timer=await push('start',{taskId:task},{actor:tech});assert.equal(timer.result.status,'accepted');
  await db.query('select public.apply_operation($1,$2,$3)',[w,techDevice,timer.op]);assert.equal((await snapshot()).orders[0].times.length,1);
 });
 await test('Concurrent same-user timer and unauthorized extension are retained as conflicts',async()=>{
  const t=await push('start',{taskId:task},{actor:tech});assert.equal(t.result.status,'conflict');
  const blocked=await push('start',{taskId:task2},{actor:tech});assert.equal(blocked.result.status,'conflict');assert.match(blocked.result.reason,/authorization/);
 });
 await test('Retry key with altered payload is rejected',async()=>{await assert.rejects(()=>db.query('select public.apply_operation($1,$2,$3)',[w,techDevice,{...timer.op,payload:{taskId:task2}}]),/Idempotency key reused/);});
 await test('Manual time overlapping an active session cannot be duplicated',async()=>{
  const now=new Date();const r=await push('manual_time',{taskId:task,start:timer.op.at,end:new Date(now.getTime()+1000).toISOString(),reason:'Forgot timer'},{actor:tech});assert.equal(r.result.status,'conflict');assert.match(r.result.reason,/overlaps/);
 });
 await push('stop',{sessionId:timer.op.id},{actor:tech,at:new Date(Date.now()+2000).toISOString()});
 let consume;
 await test('Server freezes catalog price and consumes decimal quantities once',async()=>{
  consume=await push('part',{taskId:task,itemId:part,kind:'consume',quantityMilli:4500,priceCents:1},{actor:tech});assert.equal(consume.result.status,'accepted');
  await db.query('select public.apply_operation($1,$2,$3)',[w,techDevice,consume.op]);await login(office);
  const p=(await snapshot()).orders[0].parts;assert.equal(p.length,1);assert.equal(p[0].priceCents,1450);assert.equal(p[0].quantityMilli,4500);await login(tech);
 });
 await test('Partial return succeeds; excess return is preserved as a conflict',async()=>{
  assert.equal((await push('return',{sourceId:consume.op.id,quantityMilli:500},{actor:tech})).result.status,'accepted');
  assert.equal((await push('return',{sourceId:consume.op.id,quantityMilli:4500},{actor:tech})).result.status,'conflict');
 });
 await login(office);
 await test('Stale office review cannot silently overwrite another change',async()=>{const r=await push('billable',{taskId:task,minutes:60,reason:'Reviewed'},{revision:0});assert.equal(r.result.status,'conflict');assert.match(r.result.reason,/Revision conflict/);});
 await test('Legacy issue cannot bypass all-device atomic closure',async()=>{await assert.rejects(()=>push('issue',{connected:true,pending:0}),/atomic closure|legacy issuing disabled/);});
 await test('Late records are retained without changing an emitted document',async()=>{
  await db.exec('reset role');const original={totalCents:12345,type:'Test note'};
  await db.query("update private.orders set data=jsonb_set(data,'{document}',$1::jsonb) where id=$2",[original,order]);await login(tech);
  const r=await push('note',{text:'Late measurement'},{actor:tech});assert.equal(r.result.status,'late');await login(office);assert.deepEqual((await snapshot()).orders[0].document,original);
 });
 await test('All private tables have RLS enabled',async()=>{
  await db.exec('reset role');const r=await db.query("select relname from pg_class join pg_namespace n on n.oid=relnamespace where n.nspname='private' and relkind='r' and not relrowsecurity");assert.equal(r.rows.length,0);
 });
 console.log(`${passed} database checks passed. PGlite executes PostgreSQL; hosted Supabase/Auth/Storage need separate integration tests.`);
} finally {await db.close();}
