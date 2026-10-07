-- Sandbox drafts only. Ledger fingerprints are NOT AEAT fiscal fingerprints.
-- No invoice emission, official numbering, QR or transport is enabled here.
begin;
create table private.fiscal_draft_heads (
 workshop_id uuid not null references private.workshops(id), issuer_nif text not null,
 installation text not null, last_sequence bigint not null default 0 check(last_sequence>=0),
 last_hash text not null default '', restored boolean not null default false,
 primary key(workshop_id,issuer_nif,installation),
 check(issuer_nif ~ '^[A-Z0-9]{9}$'),check(length(installation) between 1 and 80),
 check((last_sequence=0 and last_hash='') or (last_sequence>0 and last_hash ~ '^[A-F0-9]{64}$'))
);
create table private.fiscal_draft_series (
 workshop_id uuid not null, issuer_nif text not null, installation text not null,
 prefix text not null check(prefix ~ '^ENSAYO-[A-Z0-9-]{1,16}$'),
 last_number bigint not null default 0 check(last_number between 0 and 999999999),
 primary key(workshop_id,issuer_nif,installation,prefix),
 foreign key(workshop_id,issuer_nif,installation) references private.fiscal_draft_heads
);
create table private.fiscal_draft_records (
 workshop_id uuid not null, id uuid not null, issuer_nif text not null, installation text not null,
 sequence bigint not null check(sequence>0), kind text not null check(kind in ('draft','withdrawal')),
 prefix text not null, number bigint not null check(number between 1 and 999999999),
 target_id uuid, actor_id uuid not null, device_id uuid not null,
 body jsonb not null, previous_hash text not null, ledger_hash text not null check(ledger_hash ~ '^[A-F0-9]{64}$'),
 primary key(workshop_id,id),unique(workshop_id,issuer_nif,installation,sequence),
 foreign key(workshop_id,issuer_nif,installation,prefix) references private.fiscal_draft_series,
 foreign key(workshop_id,target_id) references private.fiscal_draft_records(workshop_id,id),
 check((kind='draft' and target_id is null) or (kind='withdrawal' and target_id is not null)),
 check((sequence=1 and previous_hash='') or (sequence>1 and previous_hash ~ '^[A-F0-9]{64}$'))
);
create unique index fiscal_draft_number_once on private.fiscal_draft_records(workshop_id,issuer_nif,installation,prefix,number) where kind='draft';
create unique index fiscal_draft_withdraw_once on private.fiscal_draft_records(workshop_id,target_id) where kind='withdrawal';
alter table private.fiscal_draft_heads enable row level security;
alter table private.fiscal_draft_series enable row level security;
alter table private.fiscal_draft_records enable row level security;
revoke all on private.fiscal_draft_heads,private.fiscal_draft_series,private.fiscal_draft_records from public,anon,authenticated;
create trigger fiscal_drafts_immutable before update or delete on private.fiscal_draft_records for each row execute function private.immutable_document();

create function private.fiscal_draft_calculation(v jsonb) returns jsonb language plpgsql immutable set search_path='' as $$
declare l jsonb; price bigint;qty bigint;discount bigint;rate bigint;base bigint;tax bigint;
 base_sum bigint:=0;tax_sum bigint:=0;rows jsonb:='[]';descr text;
begin
 if jsonb_typeof(v) is distinct from 'array' or jsonb_array_length(v) not between 1 and 1000 then raise exception 'Draft lines required';end if;
 if (select count(*) from jsonb_array_elements(v))<>(select count(distinct x->>'id') from jsonb_array_elements(v) x) then raise exception 'Duplicate draft line';end if;
 for l in select value from jsonb_array_elements(v) loop
  if jsonb_typeof(l) is distinct from 'object' or exists(select 1 from jsonb_object_keys(l) k where k not in ('id','description','unitCents','quantityMilli','discountBps','taxBps','tax','treatment','reason')) then raise exception 'Invalid draft line';end if;
  if (l->>'id')::uuid is null then raise exception 'Draft line identity required';end if;
  if jsonb_typeof(l->'description') is distinct from 'string' or (l ? 'reason' and jsonb_typeof(l->'reason') is distinct from 'string') then raise exception 'Draft description and reason must be text';end if;
  descr:=private.require_text(l->>'description','Draft description',500);
  price:=private.require_int(l->'unitCents',0,1000000000000,'Draft price');
  qty:=private.require_int(l->'quantityMilli',1,1000000000,'Draft quantity');
  discount:=private.require_int(l->'discountBps',0,10000,'Draft discount');
  rate:=private.require_int(l->'taxBps',0,10000,'Draft rate');
  if coalesce(l->>'tax','') not in ('iva','igic','ipsi','other') or coalesce(l->>'treatment','') not in ('taxable','exempt','reverse_charge','outside_scope') then raise exception 'Draft tax and treatment required';end if;
  if l->>'treatment'<>'taxable' then perform private.require_text(l->>'reason','Draft treatment reason');if rate<>0 then raise exception 'Special treatment requires zero rate';end if;end if;
  base:=round(price::numeric*qty::numeric*(10000-discount)::numeric/10000000)::bigint;
  if base>1000000000000 then raise exception 'Draft base out of range';end if;
  tax:=case when l->>'treatment'='taxable' then round(base::numeric*rate/10000)::bigint else 0 end;
  base_sum:=base_sum+base;tax_sum:=tax_sum+tax;
  if base_sum+tax_sum>1000000000000 then raise exception 'Draft total out of range';end if;
  rows:=rows||jsonb_build_array(l||jsonb_build_object('description',descr,'baseCents',base,'taxCents',tax,'totalCents',base+tax));
 end loop;
 return jsonb_build_object('lines',rows,'baseCents',base_sum,'taxCents',tax_sum,'totalCents',base_sum+tax_sum);
end $$;
create function private.fiscal_draft_fingerprint(b jsonb,p text) returns text language sql immutable set search_path='' as $$
 select upper(encode(sha256(convert_to('TALLERFLOW-DRAFT-1|'||p||'|'||b::text,'UTF8')),'hex'))
$$;

create function private.fiscal_draft_command(w uuid,dev uuid,cid uuid,action text,p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare prior private.command_receipts%rowtype; head private.fiscal_draft_heads%rowtype;
 original private.fiscal_draft_records%rowtype; nif text;inst text;pref text;num bigint;
 reason text;expected bigint;profile jsonb;b jsonb;calculation jsonb;result jsonb;target uuid;record_kind text;
begin
 perform private.backup_admin(w,dev);
 -- Same lock order as export/restore. No external work occurs while locked.
 perform 1 from private.workshops where id=w for update;
 if cid is null or jsonb_typeof(p) is distinct from 'object' then raise exception 'Draft command identity required';end if;
 select * into prior from private.command_receipts where workshop_id=w and id=cid;
 if found then
  if prior.actor_id is distinct from auth.uid() or prior.device_id is distinct from dev or prior.action is distinct from action or prior.payload is distinct from p then raise exception 'Command ID reused';end if;
  return prior.result;
 end if;
 if coalesce(action,'') not in ('fiscal_draft_append','fiscal_draft_withdraw') then raise exception 'Unknown draft action';end if;
 if exists(select 1 from jsonb_object_keys(p) k where k not in ('issuerNif','installation','prefix','expectedSequence','expectedHash','reason','lines','issueDate','recipient','targetId')) then raise exception 'Unknown draft field or attempted emission';end if;
 if jsonb_typeof(p->'issuerNif') is distinct from 'string' or jsonb_typeof(p->'installation') is distinct from 'string' or jsonb_typeof(p->'reason') is distinct from 'string' then raise exception 'Draft identity and reason must be text';end if;
 reason:=private.require_text(p->>'reason','Draft reason');nif:=private.require_text(p->>'issuerNif','Draft issuer',9);inst:=private.require_text(p->>'installation','Draft installation',80);
 if nif !~ '^[A-Z0-9]{9}$' or inst ~ '[[:cntrl:]]' then raise exception 'Invalid draft identity';end if;
 select settings->'fiscalProfile' into profile from private.workshops where id=w;
 profile:=private.normalize_fiscal_profile(profile);
 if profile->>'sii'<>'no' or profile->>'territory' not in ('common','canary','ceuta','melilla') then raise exception 'Draft circuit does not cover SII, unknown or foral territory';end if;
 expected:=private.require_int(p->'expectedSequence',0,999999999,'Draft sequence');
 if jsonb_typeof(p->'expectedHash') is distinct from 'string' then raise exception 'Draft expected hash required';end if;
 insert into private.fiscal_draft_heads(workshop_id,issuer_nif,installation) values(w,nif,inst) on conflict do nothing;
 select * into head from private.fiscal_draft_heads where workshop_id=w and issuer_nif=nif and installation=inst for update;
 if head.restored then raise exception 'Restored draft installation is frozen; use a new sandbox installation';end if;
 if head.last_sequence<>expected or head.last_hash<>p->>'expectedHash' then raise exception 'Draft chain conflict; refresh and review';end if;
 if action='fiscal_draft_append' then
  if p ? 'targetId' then raise exception 'A new draft cannot select a withdrawal target';end if;
  pref:=private.require_text(p->>'prefix','Sandbox series',23);
  if pref !~ '^ENSAYO-[A-Z0-9-]{1,16}$' then raise exception 'Only ENSAYO sandbox series are allowed';end if;
  if jsonb_typeof(p->'issueDate') is distinct from 'string' or p->>'issueDate' !~ '^\d{4}-\d{2}-\d{2}$' or to_char((p->>'issueDate')::date,'YYYY-MM-DD')<>p->>'issueDate' then raise exception 'Invalid draft date';end if;
  if jsonb_typeof(p->'recipient') is distinct from 'object' or exists(select 1 from jsonb_object_keys(p->'recipient') k where k not in ('name','nif')) then raise exception 'Draft recipient required';end if;
  if jsonb_typeof(p->'recipient'->'name') is distinct from 'string' or jsonb_typeof(p->'recipient'->'nif') is distinct from 'string' then raise exception 'Draft recipient must contain text';end if;
  perform private.require_text(p->'recipient'->>'name','Draft recipient name',120);
  if coalesce(p->'recipient'->>'nif','') !~ '^[A-Z0-9]{9}$' then raise exception 'Draft recipient NIF structure';end if;
  calculation:=private.fiscal_draft_calculation(p->'lines');
  insert into private.fiscal_draft_series(workshop_id,issuer_nif,installation,prefix) values(w,nif,inst,pref) on conflict do nothing;
  update private.fiscal_draft_series set last_number=last_number+1 where workshop_id=w and issuer_nif=nif and installation=inst and prefix=pref returning last_number into num;
  record_kind:='draft';
  b:=jsonb_build_object('calculation',calculation,'issueDate',p->'issueDate','recipient',p->'recipient');
 else
  if p ?| array['lines','issueDate','recipient','prefix'] then raise exception 'Withdrawal cannot replace draft contents';end if;
  target:=(p->>'targetId')::uuid;
  select * into original from private.fiscal_draft_records where workshop_id=w and id=target and issuer_nif=nif and installation=inst and kind='draft';
  if not found then raise exception 'Draft withdrawal target not found';end if;
  if exists(select 1 from private.fiscal_draft_records where workshop_id=w and target_id=target) then raise exception 'Draft already withdrawn';end if;
  record_kind:='withdrawal';pref:=original.prefix;num:=original.number;
  b:=jsonb_build_object('targetId',target,'originalLedgerHash',original.ledger_hash);
 end if;
 b:=b||jsonb_build_object('draftFormat',1,'emissionEnabled',false,'transmissionEnabled',false,'scope','sandbox',
  'id',cid,'issuerNif',nif,'installation',inst,'sequence',expected+1,'kind',record_kind,'prefix',pref,'number',num,
  'reason',reason,'actorId',auth.uid(),'deviceId',dev,'createdAt',clock_timestamp());
 result:=jsonb_build_object('saved',true,'id',cid,'sequence',expected+1,'prefix',pref,'number',num,
  'ledgerHash',private.fiscal_draft_fingerprint(b,head.last_hash),'emissionEnabled',false,'transmissionEnabled',false);
 insert into private.fiscal_draft_records values(w,cid,nif,inst,expected+1,record_kind,pref,num,target,auth.uid(),dev,b,head.last_hash,result->>'ledgerHash');
 update private.fiscal_draft_heads set last_sequence=expected+1,last_hash=result->>'ledgerHash' where workshop_id=w and issuer_nif=nif and installation=inst;
 insert into private.command_receipts values(w,cid,auth.uid(),dev,action,p,result);
 insert into private.audit(workshop_id,actor_id,operation_id,kind,after_data) values(w,auth.uid(),cid,action,jsonb_build_object('recordId',cid,'ledgerHash',result->>'ledgerHash','reason',reason,'sandbox',true));
 return result;
end $$;
create function public.fiscal_draft_command(workshop_id uuid,device_id uuid,command_id uuid,action text,payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.fiscal_draft_command($1,$2,$3,$4,$5)$$;
create function private.fiscal_drafts(w uuid,dev uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform private.backup_admin(w,dev);
 return jsonb_build_object('scope','sandbox','emissionEnabled',false,'transmissionEnabled',false,
  'heads',coalesce((select jsonb_agg(to_jsonb(h) order by h.issuer_nif,h.installation) from private.fiscal_draft_heads h where workshop_id=w),'[]'),
  'series',coalesce((select jsonb_agg(to_jsonb(s) order by s.issuer_nif,s.installation,s.prefix) from private.fiscal_draft_series s where workshop_id=w),'[]'),
  'records',coalesce((select jsonb_agg(to_jsonb(r) order by r.issuer_nif,r.installation,r.sequence) from private.fiscal_draft_records r where workshop_id=w),'[]'));
end $$;
create function public.fiscal_drafts(workshop_id uuid,device_id uuid) returns jsonb language sql security invoker set search_path='' as $$select private.fiscal_drafts($1,$2)$$;

alter function private.backup_tables() rename to backup_tables_before_fiscal_drafts;
create function private.backup_tables() returns text[] language sql immutable set search_path='' as $$select private.backup_tables_before_fiscal_drafts()||array['fiscal_draft_heads','fiscal_draft_series','fiscal_draft_records']::text[]$$;
alter function private.export_workshop(uuid,uuid) rename to export_workshop_before_fiscal_drafts;
create function private.export_workshop(w uuid,dev uuid) returns jsonb language sql security definer set search_path='' as $$select private.export_workshop_before_fiscal_drafts(w,dev)||jsonb_build_object('databaseVersion',14)$$;

create function private.validate_fiscal_drafts(w uuid) returns void language plpgsql security definer set search_path='' as $$
declare h private.fiscal_draft_heads%rowtype;r private.fiscal_draft_records%rowtype;s private.fiscal_draft_series%rowtype;
 seq bigint;ph text;num bigint;o private.fiscal_draft_records%rowtype;calc jsonb;
begin
 for h in select * from private.fiscal_draft_heads where workshop_id=w loop
  seq:=0;ph:='';
  for r in select * from private.fiscal_draft_records where workshop_id=w and issuer_nif=h.issuer_nif and installation=h.installation order by sequence loop
   seq:=seq+1;
   if r.sequence<>seq or r.previous_hash<>ph or r.ledger_hash<>private.fiscal_draft_fingerprint(r.body,ph) then raise exception 'Invalid draft ledger chain';end if;
   if r.body->'draftFormat' is distinct from '1'::jsonb or r.body->>'scope' is distinct from 'sandbox' or r.body->'emissionEnabled' is distinct from 'false'::jsonb or r.body->'transmissionEnabled' is distinct from 'false'::jsonb
    or r.body->>'id' is distinct from r.id::text or r.body->>'issuerNif' is distinct from r.issuer_nif or r.body->>'installation' is distinct from r.installation or r.body->>'sequence' is distinct from r.sequence::text
    or r.body->>'kind' is distinct from r.kind or r.body->>'prefix' is distinct from r.prefix or r.body->>'number' is distinct from r.number::text
    or r.body->>'actorId' is distinct from r.actor_id::text or r.body->>'deviceId' is distinct from r.device_id::text then raise exception 'Malformed draft body';end if;
   perform private.require_text(r.body->>'reason','Restored draft reason');
   if r.body->>'createdAt' is null or (r.body->>'createdAt')::timestamptz is null then raise exception 'Draft creation timestamp required';end if;
   if not exists(select 1 from private.command_receipts c where c.workshop_id=w and c.id=r.id and c.actor_id=r.actor_id and c.device_id=r.device_id
    and c.action=case when r.kind='draft' then 'fiscal_draft_append' else 'fiscal_draft_withdraw' end
    and c.result->>'ledgerHash'=r.ledger_hash and c.result->>'id'=r.id::text and c.result->>'sequence'=r.sequence::text
    and c.result->'emissionEnabled'='false'::jsonb and c.result->'transmissionEnabled'='false'::jsonb)
    or not exists(select 1 from private.audit a where a.workshop_id=w and a.operation_id=r.id and a.actor_id=r.actor_id
     and a.kind=case when r.kind='draft' then 'fiscal_draft_append' else 'fiscal_draft_withdraw' end
     and a.after_data->>'ledgerHash'=r.ledger_hash and a.after_data->>'reason'=r.body->>'reason') then raise exception 'Draft receipt or audit missing';end if;
   if not exists(select 1 from private.members where workshop_id=w and user_id=r.actor_id) or not exists(select 1 from private.devices where workshop_id=w and id=r.device_id and user_id=r.actor_id) then raise exception 'Invalid draft original author/device';end if;
   if r.kind='draft' then
    select jsonb_agg(x-array['baseCents','taxCents','totalCents']) into calc from jsonb_array_elements(r.body->'calculation'->'lines') x;
    if private.fiscal_draft_calculation(calc) is distinct from r.body->'calculation' then raise exception 'Invalid restored draft calculation';end if;
   else
    select * into o from private.fiscal_draft_records where workshop_id=w and id=r.target_id and kind='draft' and issuer_nif=r.issuer_nif and installation=r.installation and sequence<r.sequence;
    if not found or r.prefix<>o.prefix or r.number<>o.number or r.body->>'targetId' is distinct from o.id::text or r.body->>'originalLedgerHash' is distinct from o.ledger_hash then raise exception 'Invalid draft withdrawal';end if;
   end if;
   ph:=r.ledger_hash;
  end loop;
  if h.last_sequence<>seq or h.last_hash<>ph then raise exception 'Invalid draft head';end if;
 end loop;
 for s in select * from private.fiscal_draft_series where workshop_id=w loop
  select coalesce(max(number),0) into num from private.fiscal_draft_records where workshop_id=w and issuer_nif=s.issuer_nif and installation=s.installation and prefix=s.prefix and kind='draft';
  if s.last_number<>num or num<>(select count(*) from private.fiscal_draft_records where workshop_id=w and issuer_nif=s.issuer_nif and installation=s.installation and prefix=s.prefix and kind='draft') then raise exception 'Invalid draft series or number gap';end if;
 end loop;
end $$;
alter function private.restore_workshop(uuid,uuid,uuid,jsonb) rename to restore_workshop_before_fiscal_drafts;
create function private.restore_workshop(w uuid,dev uuid,rid uuid,a jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare n jsonb:=a;t text;r jsonb;already boolean;
begin
 perform private.backup_admin(w,dev);perform 1 from private.workshops where id=w for update;
 already:=exists(select 1 from private.restores where workshop_id=w and id=rid);
 if exists(select 1 from private.fiscal_draft_heads where workshop_id=w) and not already then raise exception 'Restore requires empty isolated fiscal draft state';end if;
 if a->>'databaseVersion'='14' then
  foreach t in array array['fiscal_draft_heads','fiscal_draft_series','fiscal_draft_records'] loop if jsonb_typeof(a->'tables'->t) is distinct from 'array' then raise exception 'Fiscal draft backup table missing';end if;end loop;
  n:=a||jsonb_build_object('databaseVersion',13);
 elsif a->>'databaseVersion' in ('2','3','4','5','6','7','8','9','10','11','12','13') then
  if exists(select 1 from jsonb_array_elements(a->'tables'->'command_receipts') x where x->>'action' like 'fiscal_draft_%') then raise exception 'Old archive cannot carry unversioned fiscal drafts';end if;
  foreach t in array array['fiscal_draft_heads','fiscal_draft_series','fiscal_draft_records'] loop
   if a->'tables' ? t and a->'tables'->t is distinct from '[]'::jsonb then raise exception 'Old archive cannot carry unversioned fiscal drafts';end if;
   n:=jsonb_set(n,array['tables',t],'[]');
  end loop;
 end if;
 r:=private.restore_workshop_before_fiscal_drafts(w,dev,rid,n);
 if already then return r;end if;
 perform private.validate_fiscal_drafts(w);
 -- Recovery preserves records/series but never resumes an old installation.
 update private.fiscal_draft_heads set restored=true where workshop_id=w;
 return r;
end $$;
revoke all on function private.fiscal_draft_calculation(jsonb),private.fiscal_draft_fingerprint(jsonb,text),private.validate_fiscal_drafts(uuid),private.backup_tables_before_fiscal_drafts(),private.backup_tables(),private.export_workshop_before_fiscal_drafts(uuid,uuid),private.restore_workshop_before_fiscal_drafts(uuid,uuid,uuid,jsonb) from public,anon,authenticated;
revoke all on function private.fiscal_draft_command(uuid,uuid,uuid,text,jsonb),public.fiscal_draft_command(uuid,uuid,uuid,text,jsonb),private.fiscal_drafts(uuid,uuid),public.fiscal_drafts(uuid,uuid),private.export_workshop(uuid,uuid),private.restore_workshop(uuid,uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function private.fiscal_draft_command(uuid,uuid,uuid,text,jsonb),public.fiscal_draft_command(uuid,uuid,uuid,text,jsonb),private.fiscal_drafts(uuid,uuid),public.fiscal_drafts(uuid,uuid),private.export_workshop(uuid,uuid),private.restore_workshop(uuid,uuid,uuid,jsonb) to authenticated;
commit;
