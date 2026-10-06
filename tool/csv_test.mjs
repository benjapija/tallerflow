import {PGlite} from '@electric-sql/pglite';
import {readFile,readdir} from 'node:fs/promises';
import assert from 'node:assert/strict';
let n=4000,passed=0;const id=()=>`00000000-0000-4000-8000-${String(n++).padStart(12,'0')}`;
const w=id(),admin=id(),office=id(),tech=id(),ad=id(),od=id(),td=id();
async function setup(bootstrap=false){const db=new PGlite();
await db.exec(`create role anon;create role authenticated;create role service_role;create schema auth;create table auth.users(id uuid primary key);create table auth.sessions(id uuid primary key,user_id uuid not null);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;`);
await db.exec(await readFile(new URL('./storage_fixture.sql',import.meta.url),'utf8'));
for(const f of (await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(f=>f.endsWith('.sql')).sort())await db.exec(await readFile(new URL(`../supabase/migrations/${f}`,import.meta.url),'utf8'));
await db.query('insert into auth.users values($1),($2),($3)',[admin,office,tech]);await db.query("insert into private.workshops(id,name) values($1,'Fictional CSV test')",[w]);await db.query("insert into private.members values($1,$2,'Admin','admin',true,true)",[w,admin]);if(!bootstrap)await db.query("insert into private.members values($1,$2,'Office','office',true,true),($1,$3,'Tech','technician',false,true)",[w,office,tech]);return db;}
const db=await setup();let exported;
async function login(u,d){await db.exec('reset role');await db.query('insert into auth.sessions values($1,$2) on conflict do nothing',[d,u]);await db.query("select set_config('request.jwt.claim.sub',$1,false)",[u]);await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:u,session_id:d})]);await db.exec('set role authenticated');await snap(d);}
async function snap(d){return(await db.query('select public.device_snapshot($1,$2) r',[w,d])).rows[0].r;}
const row=(data)=>({id:id(),line:2,data});
const client={code:'C1',name:'Fictional client',phone:'600000000',email:'fictional@example.invalid',taxId:'X0000000T',address:'Fictional street'};
const payload=(kind,rows)=>({kind,reason:'Fictional test import',rows});
async function command(d,c,p,preview=false){return(await db.query('select public.import_command($1,$2,$3,$4,$5) r',[w,d,c,preview?'import_preview':'import_commit',p])).rows[0].r;}
const test=async(name,f)=>{await f();passed++;console.log('PASS '+name);};
try{
 await login(office,od);const batch=id(),rows=[row(client),{...row({...client,name:'Duplicate'}),line:3},{...row({...client,code:'C2',email:'invalid'}),line:4}],p=payload('clients',rows);let result;
 await test('Preview distinguishes duplicate rows and validation errors without writing',async()=>{result=await command(od,batch,p,true);assert.deepEqual(result.rows.map(r=>r.status),['ready','duplicate','error']);assert.equal((await snap(od)).clients.length,0);});
 await test('Commit keeps per-row results and creates only valid unique rows with audit',async()=>{result=await command(od,batch,p);assert.deepEqual(result.rows.map(r=>r.status),['created','duplicate','error']);assert.equal(result.created,1);assert.equal((await snap(od)).clients.length,1);});
 await test('Lost reply retry creates no extra client or audit and changed payload is rejected',async()=>{assert.deepEqual(await command(od,batch,p),result);await assert.rejects(()=>command(od,batch,{...p,reason:'Changed'}),/Command ID reused/);await db.exec('reset role');assert.equal((await db.query("select count(*)::int n from private.audit where kind='csv_row_imported'")).rows[0].n,1);await login(office,od);});
 const car={plate:'1234 ABC',country:'ES',vin:'FICTIONAL-CAR',vehicle:'Fictional vehicle',engine:'2020',km:12345,clientCode:'C1'},carRow=row(car);
 await test('Vehicle import binds the stable customer and current identifiers without creating repair orders',async()=>{assert.equal((await command(od,id(),payload('vehicles',[carRow]))).created,1);const s=await snap(od);assert.equal(s.orders.length,0);assert.equal(s.vehicleProfiles[0].ownerId,rows[0].id);assert.equal(s.vehicleProfiles[0].plate,'1234ABC');assert.equal(s.vehicleProfiles[0].km,12345);});
 await test('Repeated VIN or registration preserves existing owner and history; missing client is a row error',async()=>{const res=await command(od,id(),payload('vehicles',[row({...car,plate:'9999XYZ'}),row({...car,plate:'5678ABC',vin:'OTHER',clientCode:'MISSING'})]));assert.deepEqual(res.rows.map(r=>r.status),['duplicate','error']);assert.equal((await snap(od)).vehicleProfiles[0].ownerId,rows[0].id);});
 const item={reference:'OIL-CSV',description:'Fictional oil',unit:'L',priceCents:1235,costCents:0,costKnown:false,taxBps:2100,stockMilli:1125,minMilli:500,supplier:'Fictional supplier'};
 await test('Office cannot import catalog and technician cannot preview clients or read private contacts',async()=>{await assert.rejects(()=>command(od,id(),payload('catalog',[row(item)])),/permiso/);await login(tech,td);assert.equal((await snap(td)).clients.length,0);await assert.rejects(()=>command(td,id(),p,true),/permiso/);await assert.rejects(()=>db.query('select * from private.clients'),/permission denied/);await login(admin,ad);});
 await test('Admin catalog import retains exact decimal quantities and unknown costs',async()=>{assert.equal((await command(ad,id(),payload('catalog',[row(item)]))).created,1);const s=await snap(ad);assert.equal(s.catalog[0].stockMilli,1125);assert.equal(s.catalog[0].priceCents,1235);assert.equal(s.catalog[0].costKnown,false);assert.equal(s.managementRevision,1);});
 await test('Catalog duplicate never overwrites price or stock and invalid quantities are row errors',async()=>{const res=await command(ad,id(),payload('catalog',[row({...item,priceCents:9999,stockMilli:999}),row({...item,reference:'BAD',stockMilli:1.5})]));assert.deepEqual(res.rows.map(r=>r.status),['duplicate','error']);assert.equal((await snap(ad)).catalog[0].priceCents,1235);assert.equal((await snap(ad)).catalog[0].stockMilli,1125);});
 await test('Unexpected fields, repeated row IDs and wrong workshop leave no imported data',async()=>{await assert.rejects(()=>command(ad,id(),{...p,extra:'forbidden'}),/inesperado/);await assert.rejects(()=>command(ad,id(),payload('clients',[rows[0],rows[0]])),/repetido/);const bad=payload('clients',[row({...client,code:'C3',taxId:'',workshopId:id()})]);assert.equal((await command(ad,id(),bad)).rows[0].status,'error');assert.equal((await snap(ad)).clients.length,1);await assert.rejects(()=>db.query('select public.import_command($1,$2,$3,$4,$5)',[id(),ad,id(),'import_commit',p]),/Membership/);});
 await test('Account revocation blocks import retries and exported customers are included in schema version 7',async()=>{const a=(await db.query('select public.export_workshop($1,$2) r',[w,ad])).rows[0].r;assert.equal(a.databaseVersion,7);assert.equal(a.tables.clients.length,1);exported=a;await db.exec('reset role');await db.query('delete from auth.sessions where id=$1',[ad]);await db.exec('set role authenticated');await assert.rejects(()=>command(ad,id(),p),/session/i);});
 for(const oldVersion of [false,true]){
  const target=await setup(true),device=id(),session=id();
  try{
   await target.query('insert into auth.sessions values($1,$2)',[session,admin]);await target.query("select set_config('request.jwt.claim.sub',$1,false)",[admin]);await target.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:admin,session_id:session})]);await target.exec('set role authenticated');await target.query('select public.device_snapshot($1,$2)',[w,device]);
   await test(oldVersion?'Version 6 recovery seeds historical owners without granting new document access':'Independent database recovers imported clients, vehicles, catalog and command originals',async()=>{
    const archive=structuredClone(exported);if(oldVersion){archive.databaseVersion=6;delete archive.tables.clients;}
    await target.query('select public.restore_workshop($1,$2,$3,$4)',[w,device,id(),archive]);const recovered=(await target.query('select public.device_snapshot($1,$2) r',[w,device])).rows[0].r;
    assert.equal(recovered.clients.length,1);assert.equal(recovered.clients[0].id,rows[0].id);assert.equal(recovered.vehicleProfiles[0].ownerId,rows[0].id);assert.equal(recovered.catalog[0].stockMilli,1125);
    if(!oldVersion)assert.equal(recovered.clients[0].taxId,client.taxId);else assert.equal(recovered.clients[0].code,null);
   });
  }finally{await target.close();}
 }
 console.log(`${passed} CSV checks passed in local PostgreSQL/PGlite. Hosted Auth, HTTP and native CSV file pickers remain separate validations.`);
}finally{await db.close();}
