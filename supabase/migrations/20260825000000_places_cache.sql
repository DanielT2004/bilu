-- Cache tables backing supabase/functions/_shared/places.ts.
-- Reconstructed from the CacheRow interface — the original project's tables
-- predate this repo's migration tracking, so this recreates their shape.

create table if not exists places_cache (
  place_id     text primary key,
  photo_refs   text[] not null default '{}',
  rating       double precision,
  review_count integer,
  is_open      boolean,
  address      text,
  phone        text,
  website      text,
  reviews      jsonb,
  latitude     double precision,
  longitude    double precision,
  neighborhood text,
  cached_at    timestamptz not null default now()
);

create table if not exists place_name_cache (
  name_key   text primary key,
  place_id   text not null,
  cached_at  timestamptz not null default now()
);

-- Edge functions use the service role key, which bypasses RLS — but enabling
-- RLS with no policies still locks the tables down from the anon/public API key.
alter table places_cache enable row level security;
alter table place_name_cache enable row level security;
