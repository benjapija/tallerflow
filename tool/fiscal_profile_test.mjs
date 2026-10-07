import {PGlite} from '@electric-sql/pglite';
import {readFile,readdir} from 'node:fs/promises';
import assert from 'node:assert/strict';
const db=new PGlite();let sequence=35000,passed=0;
const id=()=>`00000000-0000-4000-8000-${String(sequence++).padStart(12,'0')}`;
const w=id(),other=id(),admin=id(),office=id(),technician=id(),foreign=id(),dev=id(),od=id(),td=id(),fd=id(),order=id(),vehicle=id(),document=id();
await db.exec("create role anon;create role authenticated;create role service_role;create schema auth;create table auth.users(id uuid primary key);create table auth.sessions(id uuid primary key,user_id uuid not null);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;");
await db.exec(await readFile(new URL('./storage_fixture.sql',import.meta.url),'utf8'));
for(const f of (await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(f=>f.endsWith('.sql')).sort())await db.exec(await readFile(new URL(`../supabase/migrations/${f}`,import.meta.url),'utf8'));
await db.query('insert into auth.users values($1),($2),($3),($4)',[admin,office,technician,foreign]);
await db.query("insert into private.workshops(id,name) values($1,'Fictional fiscal workshop'),($2,'Other fiscal workshop')",[w,other]);
await db.query("insert into private.members values($1,$2,'Admin','admin',true,true),($1,$3,'Office','office',true,true),($1,$4,'Tech','technician',false,true),($5,$6,'Other','admin',true,true)",[w,admin,office,technician,other,foreign]);
const original={id:order,plate:'1234ABC',vehicle:'Fictional',client:'Fictional',vin:'',phone:'',km:0,engine:'',symptom:'',status:'issued',tasks:[],times:[],parts:[],notes:[],quotes:[],payments:[],diagnosisNotebook:[],document:{totalCents:3300,recipient:{name:'Fictional original'}}};
await db.query("insert into private.vehicles(workshop_id,id,plate,country) values($1,$2,'1234ABC','ES')",[w,vehicle]);
await db.query('insert into private.orders(workshop_id,id,vehicle_id,data,revision) values($1,$2,$3,$4,7)',[w,order,vehicle,original]);
await db.query("insert into private.documents(workshop_id,id,order_id,type,version,recipient_id,snapshot) values($1,$2,$3,'work_note',1,$4,$5)",[w,document,order,admin,original.document]);
let device=dev;
async function login(user,d){device=d;await db.exec('reset role');await db.query('insert into auth.sessions values($1,$2) on conflict do nothing',[d,user]);await db.query("select set_config('request.jwt.claim.sub',$1,false)",[user]);await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:user,session_id:d})]);await db.exec('set role authenticated');await snap(user===foreign?other:w);}
async function snap(ws=w){return (await db.query('select public.device_snapshot($1,$2) r',[ws,device])).rows[0].r;}
const profile={country:'ES',legalForm:'company',territory:'common',sii:'no',clients:'mixed',turnover:'under_8m',taxSystem:'iva'};
async function save(p,cid=id(),ws=w){return (await db.query("select public.management_command($1,$2,$3,'fiscal_profile_save',$4) r",[ws,device,cid,p])).rows[0].r;}
const payload=(revision,changes={})=>({revision,reason:'Fictional preparation',profile:{...profile,...changes}});
async function test(name,fn){await fn();passed++;console.log('PASS '+name);}
try{
 await login(admin,dev);
 const first=id(),p=payload(0);
 await test('Admin stores preparation independently for the workshop',async()=>{assert.deepEqual(await save(p,first),{saved:true,revision:1});const s=await snap();assert.deepEqual(s.settings.fiscalProfile,{...profile,profileVersion:1,emissionEnabled:false});});
 await test('Lost reply retries the original command without new revision',async()=>{assert.deepEqual(await save(p,first),{saved:true,revision:1});assert.equal((await snap()).managementRevision,1);});
 await test('Reusing identity with changed profile or reason is rejected',async()=>{await assert.rejects(()=>save({...p,reason:'Changed'},first),/reused/);await assert.rejects(()=>save(payload(0,{sii:'yes'}),first),/reused/);});
 await test('Stale preparation conflicts instead of overwriting',async()=>{await assert.rejects(()=>save(payload(0,{territory:'canary'})),/revision conflict/);});
 await test('Server refuses activation, secrets, unknown or incomplete options',async()=>{for(const changes of [{emissionEnabled:true},{emissionEnabled:'false'},{profileVersion:2},{apiKey:'fictional'},{territory:'invented'},{country:'FR'},{sii:null}])await assert.rejects(()=>save(payload(1,changes)));const missing=payload(1);delete missing.profile.clients;await assert.rejects(()=>save(missing));assert.equal((await snap()).managementRevision,1);});
 await test('Options stay preparatory for each Spanish territory and legal form',async()=>{let revision=1;for(const territory of ['common','canary','ceuta','melilla','navarra','alava','bizkaia','gipuzkoa','unknown']){await save(payload(revision++,{territory}));assert.equal((await snap()).settings.fiscalProfile.emissionEnabled,false);}for(const legalForm of ['sole_trader','company','attribution','other','unknown'])await save(payload(revision++,{legalForm}));});
 await test('Tariff changes keep preparation and existing document unchanged',async()=>{const before=await snap();await db.query("select public.management_command($1,$2,$3,'settings_save',$4)",[w,dev,id(),{revision:before.managementRevision,reason:'Fictional tariff change',settings:{hourlyRateCents:6000,taxBps:2100,internalHourlyCostCents:2500,internalCostKnown:true}}]);const after=await snap();assert.deepEqual(after.settings.fiscalProfile,before.settings.fiscalProfile);assert.deepEqual(after.orders[0].document,original.document);assert.equal(after.orders[0].revision,7);});
 await test('Backup retains profile, immutable document and reasoned audit',async()=>{const a=(await db.query('select public.export_workshop($1,$2) r',[w,dev])).rows[0].r;assert.equal(a.databaseVersion,13);assert.equal(a.workshop.settings.fiscalProfile.emissionEnabled,false);assert.equal(a.tables.orders[0].revision,7);assert.equal(a.tables.audit.filter(x=>x.kind==='fiscal_profile_save').length,15);assert.ok(a.tables.audit.filter(x=>x.kind==='fiscal_profile_save').every(x=>x.after_data.reason==='Fictional preparation'));});
 await test('Office and technician cannot update preparation',async()=>{for(const [user,d] of [[office,od],[technician,td]]){await login(user,d);await assert.rejects(()=>save(payload(0)),/Administrator/);}await login(admin,dev);});
 await test('Foreign workshop remains unchanged and inaccessible',async()=>{await login(foreign,fd);assert.equal((await snap(other)).settings.fiscalProfile,undefined);await assert.rejects(()=>save(payload(0),id(),w),/Membership/);await login(admin,dev);});
 await test('Session revocation blocks configuration',async()=>{await db.exec('reset role');await db.query('delete from auth.sessions where id=$1',[dev]);await db.exec('set role authenticated');await assert.rejects(()=>save(payload(0)),/session/);});
 await test('Anonymous and direct access cannot bypass the public command',async()=>{await db.exec('reset role;set role anon');await assert.rejects(()=>save(payload(0)),/permission denied/);await db.exec('reset role;set role authenticated');await assert.rejects(()=>db.query('select private.normalize_fiscal_profile($1)',[profile]),/permission denied/);await assert.rejects(()=>db.query('select private.management_command_before_fiscal($1,$2,$3,$4,$5)',[w,dev,id(),'settings_save',{}]),/permission denied/);});
 console.log(`${passed} fiscal preparation checks passed in PostgreSQL/PGlite; emission remains disabled.`);
}finally{await db.close();}
