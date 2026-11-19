-- PULSE database setup. Run the whole file in Supabase SQL Editor.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Пользователь',
  bio text not null default '',
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  content text not null default '',
  image_url text,
  created_at timestamptz not null default now(),
  constraint posts_content_or_image check (length(trim(content)) > 0 or image_url is not null)
);
create table if not exists public.likes (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(post_id,user_id)
);
create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  content text not null check(length(trim(content)) between 1 and 500),
  created_at timestamptz not null default now()
);
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles(id) on delete cascade,
  receiver_id uuid not null references public.profiles(id) on delete cascade,
  content text not null check(length(trim(content)) between 1 and 4000),
  created_at timestamptz not null default now(),
  constraint no_self_message check(sender_id <> receiver_id)
);
create index if not exists posts_created_at_idx on public.posts(created_at desc);
create index if not exists messages_pair_idx on public.messages(sender_id,receiver_id,created_at);

-- Create a profile automatically for every new account.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
  insert into public.profiles(id,display_name)
  values(new.id,coalesce(new.raw_user_meta_data->>'display_name',split_part(new.email,'@',1)));
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.posts enable row level security;
alter table public.likes enable row level security;
alter table public.comments enable row level security;
alter table public.messages enable row level security;

drop policy if exists "profiles readable by signed in" on public.profiles;
create policy "profiles readable by signed in" on public.profiles for select to authenticated using(true);
drop policy if exists "users update own profile" on public.profiles;
create policy "users update own profile" on public.profiles for update to authenticated using(auth.uid()=id) with check(auth.uid()=id);
drop policy if exists "users insert own profile" on public.profiles;
create policy "users insert own profile" on public.profiles for insert to authenticated with check(auth.uid()=id);

drop policy if exists "posts readable by signed in" on public.posts;
create policy "posts readable by signed in" on public.posts for select to authenticated using(true);
drop policy if exists "users create own posts" on public.posts;
create policy "users create own posts" on public.posts for insert to authenticated with check(auth.uid()=user_id);
drop policy if exists "users delete own posts" on public.posts;
create policy "users delete own posts" on public.posts for delete to authenticated using(auth.uid()=user_id);

drop policy if exists "likes readable by signed in" on public.likes;
create policy "likes readable by signed in" on public.likes for select to authenticated using(true);
drop policy if exists "users add own likes" on public.likes;
create policy "users add own likes" on public.likes for insert to authenticated with check(auth.uid()=user_id);
drop policy if exists "users remove own likes" on public.likes;
create policy "users remove own likes" on public.likes for delete to authenticated using(auth.uid()=user_id);

drop policy if exists "comments readable by signed in" on public.comments;
create policy "comments readable by signed in" on public.comments for select to authenticated using(true);
drop policy if exists "users create own comments" on public.comments;
create policy "users create own comments" on public.comments for insert to authenticated with check(auth.uid()=user_id);
drop policy if exists "users delete own comments" on public.comments;
create policy "users delete own comments" on public.comments for delete to authenticated using(auth.uid()=user_id);

drop policy if exists "messages visible to participants" on public.messages;
create policy "messages visible to participants" on public.messages for select to authenticated using(auth.uid()=sender_id or auth.uid()=receiver_id);
drop policy if exists "sender can send messages" on public.messages;
create policy "sender can send messages" on public.messages for insert to authenticated with check(auth.uid()=sender_id);

-- Storage bucket for post photos.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('post-images','post-images',true,8388608,array['image/jpeg','image/png','image/webp','image/gif'])
on conflict(id) do update set public=true,file_size_limit=8388608;
drop policy if exists "post images public read" on storage.objects;
create policy "post images public read" on storage.objects for select using(bucket_id='post-images');
drop policy if exists "users upload own post images" on storage.objects;
create policy "users upload own post images" on storage.objects for insert to authenticated with check(bucket_id='post-images' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "users delete own post images" on storage.objects;
create policy "users delete own post images" on storage.objects for delete to authenticated using(bucket_id='post-images' and (storage.foldername(name))[1]=auth.uid()::text);

-- Enable realtime for chat updates.
do $$ begin
  alter publication supabase_realtime add table public.messages;
exception when duplicate_object then null;
when others then null;
end $$;



-- Stories table (safe for projects where it was already created manually).
create table if not exists public.stories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  image_url text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '24 hours')
);
alter table public.stories enable row level security;
drop policy if exists "stories readable by signed in" on public.stories;
create policy "stories readable by signed in" on public.stories for select to authenticated using(true);
drop policy if exists "users create own stories" on public.stories;
create policy "users create own stories" on public.stories for insert to authenticated with check(auth.uid()=user_id);
drop policy if exists "users delete own stories" on public.stories;
create policy "users delete own stories" on public.stories for delete to authenticated using(auth.uid()=user_id);

-- PULSE November update: story reactions, message replies and voice messages.
create table if not exists public.story_likes (
  story_id uuid not null references public.stories(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(story_id,user_id)
);
alter table public.messages add column if not exists reply_to_message_id uuid references public.messages(id) on delete set null;
alter table public.messages add column if not exists audio_url text;
alter table public.messages alter column content drop not null;

alter table public.story_likes enable row level security;
drop policy if exists "story likes readable by signed in" on public.story_likes;
create policy "story likes readable by signed in" on public.story_likes for select to authenticated using(true);
drop policy if exists "users add own story likes" on public.story_likes;
create policy "users add own story likes" on public.story_likes for insert to authenticated with check(auth.uid()=user_id);
drop policy if exists "users remove own story likes" on public.story_likes;
create policy "users remove own story likes" on public.story_likes for delete to authenticated using(auth.uid()=user_id);

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('voice-messages','voice-messages',true,20971520,array['audio/webm','audio/ogg','audio/mp4','audio/mpeg'])
on conflict(id) do update set public=true,file_size_limit=20971520;
drop policy if exists "voice messages public read" on storage.objects;
create policy "voice messages public read" on storage.objects for select using(bucket_id='voice-messages');
drop policy if exists "users upload own voice messages" on storage.objects;
create policy "users upload own voice messages" on storage.objects for insert to authenticated with check(bucket_id='voice-messages' and (storage.foldername(name))[1]=auth.uid()::text);
