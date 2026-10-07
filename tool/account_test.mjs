import {PGlite} from '@electric-sql/pglite';
import {readFile,readdir} from 'node:fs/promises';
import assert from 'node:assert/strict';
const db=new PGlite();let n=100,passed=0;
const id=()=>`01000000-0000-4000-8000-${String(n++).padStart(12,'0')}`;
const w=id(),admin=id(),tech=id(),device=id(),session=id(),request=id(),created=id();
await db.exec(`create role anon;create role authenticated;create role service_role;create schema auth;
 create table auth.users(id uuid primary key,email text,raw_app_meta_data jsonb default '{}');create table auth.sessions(id uuid primary key,user_id uuid not null);
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;`);
await db.exec(await readFile(new URL('./storage_fixture.sql',import.meta.url),'utf8'));
for(const f of (await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(f=>f.endsWith('.sql')).sort())await db.exec(await readFile(new URL(`../supabase/migrations/${f}`,import.meta.url),'utf8'));
await db.query("insert into auth.users(id,email) values($1,'admin@example.invalid'),($2,'tech@example.invalid')",[admin,tech]);
await db.query("insert into private.workshops(id,name) values($1,'Fictional account tests')",[w]);
await db.query("insert into private.members values($1,$2,'Admin','admin',true,true),($1,$3,'Tech','technician',false,true)",[w,admin,tech]);
await db.query('insert into auth.sessions values($1,$2)',[session,admin]);
await db.query("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:admin,session_id:session})]);
await db.exec('set role authenticated');await db.query('select public.device_snapshot($1,$2)',[w,device]);
const p={name:'Fictional mechanic',email:'MECHANIC@example.invalid',role:'technician',seePrices:false,seeCosts:false,reason:'Fictional training',password:'Must never enter SQL'};
const prepare=(rid=request,preferences=p)=>db.query('select public.prepare_account($1,$2,$3,$4) r',[w,device,rid,preferences]);
const elevate=async()=>{await db.exec('reset role;set role service_role');};
const state=()=>db.query('select public.account_provision_state($1,$2) r',[w,request]);
const finish=(uid=created)=>db.query('select public.finish_account_provision($1,$2,$3) r',[w,request,uid]);
async function test(name,fn){await fn();passed++;console.log(`PASS ${name}`);}
try{
 await test('Admin prepares a stable request and excludes credential fields',async()=>{
  const a=await prepare(),b=await prepare();assert.deepEqual(a.rows,b.rows);
  await db.exec('reset role');const stored=(await db.query('select payload from private.account_requests')).rows[0].payload;
  assert.equal(stored.email,'mechanic@example.invalid');assert.equal(stored.password,undefined);
  await db.exec('set role authenticated');await assert.rejects(()=>prepare(request,{...p,name:'Changed'}),/ID reused/);
 });
 await test('Clients cannot read requests or invoke elevated finalization',async()=>{
  await assert.rejects(()=>db.query('select * from private.account_requests'),/permission denied/);
  await assert.rejects(state,/permission denied/);await assert.rejects(()=>finish(),/permission denied/);
 });
 await test('Foreign existing identities are never adopted or given membership',async()=>{
  await assert.rejects(()=>prepare(id(),{...p,email:'tech@example.invalid'}),/already uses/);
  await elevate();await assert.rejects(()=>finish(tech),/does not match/);
  await db.exec('reset role');assert.equal((await db.query('select count(*) n from private.members')).rows[0].n,2);
 });
 await test('Only the matching server marker can finalize; retries have one membership and audit effect',async()=>{
  await db.query('insert into auth.users(id,email,raw_app_meta_data) values($1,$2,$3)',[created,'mechanic@example.invalid',{tallerflow_request:request,tallerflow_workshop:w}]);
  await elevate();assert.equal((await state()).rows[0].r.userId,created);
  assert.deepEqual((await finish()).rows,(await finish()).rows);
  await db.exec('reset role');assert.equal((await db.query("select count(*) n from private.audit where kind='account_created'")).rows[0].n,1);
  assert.equal((await db.query('select revision from private.management_state')).rows[0].revision,1);
 });
 await test('Retired or reassigned device and inactive admin revoke provisioning authority',async()=>{
  await db.query('update private.devices set retired_at=now() where id=$1',[device]);await elevate();await assert.rejects(state,/no longer authorized/);
  await db.exec('reset role');await db.query('update private.devices set retired_at=null,user_id=$1 where id=$2',[tech,device]);await elevate();await assert.rejects(state,/no longer authorized/);
  await db.exec('reset role');await db.query('update private.devices set user_id=$1 where id=$2',[admin,device]);await db.query('update private.members set active=false where user_id=$1',[admin]);await elevate();await assert.rejects(()=>finish(),/no longer authorized/);
  await db.exec('reset role');await db.query('update private.members set active=true where user_id=$1',[admin]);
 });
 await test('Non-admin cannot prepare accounts and permissions are validated before any request',async()=>{
  await db.exec('set role authenticated');await assert.rejects(()=>prepare(id(),{...p,seeCosts:true}),/requires price/);
  const techSession=id();await db.exec('reset role');await db.query('insert into auth.sessions values($1,$2)',[techSession,tech]);await db.exec('set role authenticated');
  await db.query("select set_config('request.jwt.claim.sub',$1,false)",[tech]);await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:tech,session_id:techSession})]);await assert.rejects(()=>prepare(id()),/Administrator/);
  await db.query("select set_config('request.jwt.claim.sub',$1,false)",[admin]);await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:admin,session_id:session})]);
 });
 await test('Workshop archive includes account recovery records without passwords',async()=>{
  const a=(await db.query('select public.export_workshop($1,$2) r',[w,device])).rows[0].r;
  assert.equal(a.databaseVersion,11);assert.equal(a.tables.account_requests.length,1);assert(!JSON.stringify(a).includes(p.password));
  assert(a.tables.devices.length>0);
 });
 console.log(`${passed} account provisioning checks passed. Auth API and native operation require separate validation.`);
}finally{await db.close();}
