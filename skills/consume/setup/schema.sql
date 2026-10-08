-- Consume: one inbox for links saved from your phone or Mac (the "Consume"
-- Apple Shortcut posts them to the consume-capture Edge Function) and triaged
-- weekly with the /consume skill.
--
-- Safe to re-run: every statement is idempotent. setup.sh applies it with
-- `supabase db query --project-ref <ref> -f schema.sql`; you can also paste it
-- into the Supabase SQL editor.

create table if not exists public.consume_items (
  id uuid primary key default gen_random_uuid(),
  url text not null,
  source text not null default 'shortcut',          -- shortcut | manual
  status text not null default 'pending'
    check (status in ('pending', 'triaged', 'archived')),
  action_taken text,                                 -- what triage did: read, notes, shared, reviewed, done, or your own
  title text,                                        -- cached at review time
  notes text,                                        -- verdict or what was done
  created_at timestamptz not null default now(),
  triaged_at timestamptz
);

create index if not exists idx_consume_items_status
  on public.consume_items (status, created_at);

-- RLS on with no policies: only the service_role key can read or write. The
-- capture function and the /consume skill both use it; the public anon key
-- sees nothing.
alter table public.consume_items enable row level security;
