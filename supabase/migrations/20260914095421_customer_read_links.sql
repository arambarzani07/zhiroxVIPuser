create table if not exists public.customer_read_links (
 customer_id uuid primary key references public.profiles(id) on delete cascade,
 admin_id uuid not null references public.profiles(id) on delete cascade,
 token_hash text not null unique check(length(token_hash)=64),
 expires_at timestamptz not null,
 created_at timestamptz not null default now()
);
alter table public.customer_read_links enable row level security;
revoke all on public.customer_read_links from public,anon,authenticated;
grant all on public.customer_read_links to service_role;
create index if not exists customer_read_links_admin_idx on public.customer_read_links(admin_id);

create or replace function public.manage_customer_read_link(p_actor uuid,p_customer uuid,p_hash text default null)
returns boolean language plpgsql security invoker set search_path='' as $$
begin
 if not exists(select 1 from public.profiles a join public.profiles c on c.admin_id=a.id
 where a.id=p_actor and a.role='admin' and a.active and a.approved
 and (a.is_system_owner or a.subscription_end is null or a.subscription_end>=now())
 and c.id=p_customer and c.role='customer') then
 raise exception 'forbidden' using errcode='42501'; end if;
 if p_hash is null then
 delete from public.customer_read_links where customer_id=p_customer and admin_id=p_actor;
 else
 insert into public.customer_read_links(customer_id,admin_id,token_hash,expires_at)
 values(p_customer,p_actor,p_hash,now()+interval '90 days')
 on conflict(customer_id) do update set token_hash=excluded.token_hash,expires_at=excluded.expires_at,admin_id=excluded.admin_id,created_at=now();
 end if;
 return true;
end; $$;

create or replace function public.read_customer_link(p_hash text,p_offset integer default 0)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare c public.profiles%rowtype; market text; result jsonb; rows jsonb; n integer:=greatest(0,least(coalesce(p_offset,0),1000000));
begin
 select customer.* into c
 from public.customer_read_links l join public.profiles customer on customer.id=l.customer_id
 join public.profiles a on a.id=l.admin_id
 where l.token_hash=p_hash and l.expires_at>now() and customer.admin_id=l.admin_id
 and customer.role='customer' and customer.active and customer.approved
 and a.role='admin' and a.active and a.approved
 and (a.is_system_owner or a.subscription_end is null or a.subscription_end>=now());
 if c.id is null then raise exception 'link_unavailable' using errcode='42501'; end if;
 select a.market_name into market from public.profiles a where a.id=c.admin_id;
 select jsonb_build_object('name',c.name,'market',market,'debt_limit',c.debt_limit,
 'total_debt',coalesce(sum(d.amount),0),'remaining',coalesce(sum(d.remaining),0),
 'paid',coalesce(sum(d.amount-d.remaining),0),'as_of',now()) into result
 from public.debts d where d.customer_id=c.id and d.is_deleted=false;
 select coalesce(jsonb_agg(to_jsonb(t) order by t.date desc,t.kind,t.id),'[]'::jsonb) into rows from (
 select * from (
 select d.id,'debt'::text kind,d.amount,coalesce(d.custom_date,d.created_at) date,d.description note
 from public.debts d where d.customer_id=c.id and not d.is_deleted
 union all
 select p.id,'payment',p.amount,p.created_at,p.note from public.payments p
 join public.debts d on d.id=p.debt_id where d.customer_id=c.id and not d.is_deleted
 ) all_rows order by date desc,kind,id limit 51 offset n
 ) t;
 return result||jsonb_build_object('rows',rows,'offset',n);
end; $$;
revoke all on function public.manage_customer_read_link(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.read_customer_link(text,integer) from public,anon,authenticated;
grant execute on function public.manage_customer_read_link(uuid,uuid,text) to service_role;
grant execute on function public.read_customer_link(text,integer) to service_role;
