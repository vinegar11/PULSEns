# PULSE

PULSE is a browser-based social network starter connected to your Supabase project.

## Included
- Email/password registration, login and logout
- User profiles (display name and bio)
- Post feed with text and photo uploads
- Likes and comments
- User directory and private one-to-one text messages
- Realtime incoming-message refresh
- Dark blue responsive interface

## One-time Supabase setup
1. Open your Supabase project: https://supabase.com/dashboard/project/dlgegrtgispausecewzs
2. Open **SQL Editor** → **New query**.
3. Open `supabase/schema.sql` from this project, copy its full contents into the query editor and press **Run**.
4. In **Authentication → URL Configuration**, set your local/dev URL while testing (for example `http://localhost:5500`) and add your eventual published site URL to Redirect URLs.
5. In **Authentication → Providers → Email**, choose whether email confirmation is required. If enabled, users must confirm their email before their first login.

## Run locally
Open the folder with a local static server (for example VS Code Live Server) and visit the shown localhost URL. Do not open `index.html` directly as a `file://` URL.

## Security
The browser uses only the Supabase publishable key. Never put a Supabase secret/service-role key in this project or share it. Row Level Security policies are included in `supabase/schema.sql`.

## Current scope
This version includes working foundations for auth, feed, profiles, likes, comments, photo storage and text DMs. It does not yet include voice/video calls, stories, push notifications, group chats or moderation tools. It requires the one-time SQL setup above and an internet connection.


## Stories
Stories are enabled through the Supabase `stories` table and public Storage bucket `story-images`. Uploads are limited to 10 MB per image and expire from the feed after 24 hours. Run the Stories SQL setup in Supabase before using this feature.
