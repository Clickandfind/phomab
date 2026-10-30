# PHOMAB fresh app — setup guide

This guide applies only to `fresh-app/`. It does not change the original PHOMAB website.

## 1. Create the database

1. Open the Supabase project used by the fresh app.
2. Open **SQL Editor** and create a new query.
3. Open [supabase/schema.sql](./supabase/schema.sql), copy the entire file, paste it into the SQL Editor and run it.
4. Confirm the query completes without errors. The script creates the rentals, jobs and service-provider tables, safe public views, and the rental photo bucket/policies.

If Supabase reports a permission error involving the `storage` schema or `storage.buckets`, stop and check that you are running the script as the project owner in the Supabase SQL Editor.

## 2. Configure sign-in

In Supabase, open **Authentication → URL Configuration** and add the eventual deployed app URL to the allowed Site URL / Redirect URLs. For local preview, use the local preview URL shown by your preview host. Keep email confirmation enabled for real users.

## 3. Deploy the fresh app

Deploy the contents of this folder as a separate static site. Do not change the root `index.html`, root README, Cloudflare project, Firebase setup, or the original `Clickandfind/clickandfind.github.io` repository.

The entry page is `index.html`. It uses the Supabase browser client and the publishable key already configured in that file. Never put a Supabase service-role key in browser code.

## 4. Test before inviting users

Use a test account and check each flow:

- Create an account, confirm the email if required, then sign in.
- Publish a rental with a photo and test the listing appears in rental search.
- Publish a job and a service-provider profile and test both search categories.
- Test contact visibility with phone-sharing unchecked and checked.
- Test WhatsApp only when the owner explicitly enables it.
- Test that one account cannot edit or delete another account's posts.
- Test on Android Chrome and a desktop browser.

## Current implementation boundaries

- This is the fresh PHOMAB build, isolated in this folder.
- The app currently supports browsing, account registration/sign-in, and publishing rental, job and service posts.
- Rental photo upload is limited to image files up to 20 MB.
- Do not call the app production-ready until the SQL setup has run and the tests above pass.
- Moderation, reporting, richer profiles, and the complete Ask / Match / Agree interaction flow still need implementation and testing.
