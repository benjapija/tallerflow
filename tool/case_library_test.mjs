import {PGlite} from '@electric-sql/pglite';
import {readFile,readdir} from 'node:fs/promises';import assert from 'node:assert/strict';
let seq=14000,passed=0;const id=()=>`00000000-0000-4000-8000-${String(seq++).padStart(12,'0')}`;
const w=id(),w2=id(),admin=id(),tech=id(),other=id(),ad=id(),td=id(),od=id(),source=id(),caseid=id();
const db=new PGlite();
await db.exec("create role anon;create role authenticated;create role service_role;create schema auth;create table auth.users(id uuid primary key);create table auth.sessions(id uuid primary key,user_id uuid not null);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;");
await db.exec(await readFile(new URL('./storage_fixture.sql',import.meta.url),'utf8'));
for(const f of (await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(f=>f.endsWith('.sql')).sort())await db.exec(await readFile(new URL(`../supabase/migrations/${f}`,import.meta.url),'utf8'));
await db.query('insert into auth.users values($1),($2),($3)',[admin,tech,other]);await db.query("insert into private.workshops(id,name) values($1,'Fictional case validation'),($2,'Other isolated workshop')",[w,w2]);await db.query("insert into private.members values($1,$2,'Fictional admin','admin',true,true),($1,$3,'Fictional author','technician',false,true),($1,$4,'Other technician','technician',false,true),($5,$4,'Other technician','technician',false,true)",[w,admin,tech,other,w2]);
let actor=admin,dev=ad;
const snap=async(ws=w)=>(await db.query('select public.device_snapshot($1,$2) r',[ws,dev])).rows[0].r;
async function login(user,device){await db.exec('reset role');await db.query('insert into auth.sessions values($1,$2) on conflict do nothing',[device,user]);await db.query("select set_config('request.jwt.claim.sub',$1,false)",[user]);await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:user,session_id:device})]);await db.exec('set role authenticated');actor=user;dev=device;await snap();}
async function op(kind,p,rev){const record={id:id(),orderId:source,actorId:actor,kind,baseRevision:rev??(await snap()).orders.find(o=>o.id===source)?.revision??0,at:new Date().toISOString(),payload:p};const r=(await db.query('select public.apply_operation($1,$2,$3) r',[w,dev,record])).rows[0].r;assert.equal(r.status,'accepted');return record.id;}
const command=async(action,p,cid=id(),ws=w)=>(await db.query('select public.case_command($1,$2,$3,$4,$5) r',[ws,dev,cid,action,p])).rows[0].r;
const content=Object.fromEntries(['title','vehicle','engine','symptom','dtcs','checks','result','conclusion','intervention','verification','sources'].map(k=>[k,'Fictional '+k]));
let conclusion,verification;const draft=(revision=0)=>({id:caseid,revision,sourceOrderId:source,conclusionId:conclusion,verificationId:verification,content,reason:'Fictional draft'});
const validate=(revision=1,version=1)=>({id:caseid,revision,version,technicalConfirmed:true,privacyConfirmed:true,reason:'Fictional human review'});
const test=async(name,fn)=>{await fn();passed++;console.log('PASS '+name);};
try{
 await login(admin,ad);await op('receive',{plate:'4010FIC',country:'ES',vin:'FICTIONAL-CASE',vehicle:'Fictional model',engine:'2020',client:'Private owner',phone:'Private phone',km:100,symptom:'Original symptom',tasks:[{id:id(),title:'Diagnosis',estimateMinutes:30,assignees:[tech]}]});
 await login(tech,td);conclusion=await op('diagnosis_add',{stage:'conclusion',text:'Fictional conclusion',confirmed:true});verification=await op('diagnosis_add',{stage:'verification',text:'Fictional verification',confirmed:true});
 let cid=id(),p=draft();
 await test('Draft requires active source evidence, technical-only fields and proper assignment',async()=>{
  await assert.rejects(()=>command('case_draft',{...p,verificationId:id()}),/confirmed conclusion/);
  await assert.rejects(()=>command('case_draft',{...p,content:{...content,phone:'Private'}}),/technical content/i);
  await login(other,od);await assert.rejects(()=>command('case_draft',p),/Assigned source/);await login(tech,td);
  assert.equal((await command('case_draft',p,cid)).revision,1);
 });
 await test('Lost draft reply is retried once and altered command identity is refused',async()=>{
  assert.equal((await command('case_draft',p,cid)).revision,1);await assert.rejects(()=>command('case_draft',{...p,reason:'Changed'},cid),/ID reused/);
  assert.equal((await snap()).caseLibrary[0].versions.length,1);
 });
 await test('Explicit technical and privacy checks are both necessary before publishing',async()=>{
  for(const key of ['technicalConfirmed','privacyConfirmed'])for(const value of [false,'true'])await assert.rejects(()=>command('case_validate',{...validate(),[key]:value}),/review required/);
  await login(other,od);assert.deepEqual((await snap()).caseLibrary,[]);await login(tech,td);await command('case_validate',validate());
 });
 await test('Published technical view excludes private source identities, authors, reasons and drafts',async()=>{
  await command('case_draft',{...draft(2),content:{...content,title:'Private draft title'}});
  await login(other,od);const s=await snap(),c=s.caseLibrary[0];assert.equal(c.versions.length,1);assert.equal(c.versions[0].content.title,content.title);
  assert.equal(c.sourceOrderId,undefined);assert.equal(c.authorId,undefined);assert.equal(c.versions[0].conclusionId,undefined);assert.deepEqual(c.events,[]);
  assert.equal(JSON.stringify(c).includes('Private'),false);assert.equal(s.orders.length,0);
 });
 await test('Another author, stale reviewer and direct private access cannot change cases',async()=>{
  await assert.rejects(()=>command('case_validate',validate(3,2)),/Author or office/);
  await assert.rejects(()=>db.query('select * from private.case_library'),/permission denied/);
  await assert.rejects(()=>db.query("select private.case_evidence('{}','{}')"),/permission denied/);
  await login(tech,td);await assert.rejects(()=>command('case_validate',validate(2,2)),/revision conflict/);
  await assert.rejects(()=>command('case_validate',validate(3,1)),/latest draft/);await command('case_validate',validate(3,2));
 });
 await test('Workshop isolation and anonymous access are enforced on reads and writes',async()=>{
  await login(other,od);assert.deepEqual((await snap(w2)).caseLibrary,[]);
  await assert.rejects(()=>command('case_withdraw',{id:caseid,revision:0,reason:'Foreign'},id(),w2),/Assigned source/);
  await db.exec('reset role;set role anon');await assert.rejects(()=>command('case_draft',draft()),/permission denied/);await login(tech,td);
 });
 await test('Source evidence withdrawal flags case and blocks revalidation',async()=>{
  await op('diagnosis_withdraw',{sourceId:conclusion,reason:'Fictional fault returned'});
  await login(other,od);assert.equal((await snap()).caseLibrary[0].needsReview,true);await login(tech,td);
  await assert.rejects(()=>command('case_validate',validate(4,2)),/needs review/);
 });
 await test('Office withdrawal retains all versions and audits without altering the repair document',async()=>{
  await db.exec('reset role');await db.query('update private.orders set data=data||$1 where workshop_id=$2 and id=$3',[{document:{totalCents:12345,clientSnapshot:'Original private owner'}},w,source]);await login(admin,ad);
  await command('case_withdraw',{id:caseid,revision:4,reason:'Fictional recurrence'});const c=(await snap()).caseLibrary[0];assert.equal(c.versions.length,2);assert.equal(c.withdrawn,true);assert.equal((await snap()).orders[0].document.totalCents,12345);
  await login(other,od);assert.deepEqual((await snap()).caseLibrary,[]);await login(admin,ad);
 });
 await test('Fresh evidence allows a new reviewed version while old versions remain original',async()=>{
  conclusion=await op('diagnosis_add',{stage:'conclusion',text:'Revised fictional cause',confirmed:true});
  await command('case_draft',draft(5));await command('case_validate',validate(6,3));
  const c=(await snap()).caseLibrary[0];assert.equal(c.versions.length,3);assert.equal(c.activeVersion,3);assert.equal(c.withdrawn,false);assert.equal(c.needsReview,false);
 });
 await test('Backup version nine includes versions, receipts, audit and source evidence',async()=>{
  const a=(await db.query('select public.export_workshop($1,$2) r',[w,dev])).rows[0].r;assert.equal(a.databaseVersion,10);assert.equal(a.tables.case_library[0].data.versions.length,3);assert.ok(a.tables.command_receipts.find(x=>x.id===cid));assert.equal(a.tables.audit.filter(x=>x.kind==='case_withdraw').length,1);
 });
 await test('Retiring a device blocks retries even when command was already committed',async()=>{
  await db.exec('reset role');await db.query('update private.devices set retired_at=now() where workshop_id=$1 and id=$2',[w,td]);await login(admin,ad);await db.query("select set_config('request.jwt.claim.sub',$1,false)",[tech]);await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:tech,session_id:td})]);dev=td;await assert.rejects(()=>command('case_draft',p,cid),/retired|Active authenticated device/i);
 });
 console.log(`${passed} case-library checks passed in PostgreSQL/PGlite with synthetic Auth.`);
}finally{await db.close();}
