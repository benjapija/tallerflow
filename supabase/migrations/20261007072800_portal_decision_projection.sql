begin;
-- The customer sees quotation lines; internal task identities remain in the
-- workshop ledger and immutable audit, including after a decision is saved.
alter function private.portal_access(uuid,text,text,text,uuid,jsonb)
 rename to portal_access_before_decision_projection;
create function private.portal_access(gid uuid,token text,code text,action text,cid uuid,p jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;decisions jsonb;
begin
 result:=private.portal_access_before_decision_projection(gid,token,code,action,cid,p);
 if action='read' and not result ? 'error' then
  select coalesce(jsonb_agg(jsonb_build_object('id',decision->'id','at',decision->'at','decisions',
   coalesce((select jsonb_agg(jsonb_build_object('lineId',line->'lineId','accepted',line->'accepted','approvedCents',line->'approvedCents'))
    from jsonb_array_elements(decision->'decisions') line),'[]'::jsonb))),'[]'::jsonb)
   into decisions from jsonb_array_elements(result->'decisions') decision;
  result:=jsonb_set(result,'{decisions}',decisions);
 end if;
 return result;
end $$;
create or replace function public.customer_portal(grant_id uuid,token_hash text,code_hash text,action text,command_id uuid,payload jsonb)
returns jsonb language sql security invoker set search_path='' as $$ select private.portal_access($1,$2,$3,$4,$5,$6) $$;
revoke all on function private.portal_access(uuid,text,text,text,uuid,jsonb) from public,anon,authenticated;
revoke all on function private.portal_access_before_decision_projection(uuid,text,text,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function private.portal_access(uuid,text,text,text,uuid,jsonb) to service_role;
commit;
