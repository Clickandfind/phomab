# PHOMAB fresh app — setup and test guide

This guide applies only to `fresh-app/`. The original PHOMAB website and deployment remain untouched.

## Included in this build

- Rental, job and service browsing, publishing and owner-only post management.
- Rental photo upload (image files up to 20 MB).
- Consent-controlled phone visibility and WhatsApp contact.
- Voice search where supported by the browser.
- ASK requests in English, Shona or Ndebele.
- Basic keyword, location and budget ranking for rental, job and service matches, with save-match actions.
- Passenger ride requests, a driver board, driver fare offers and passenger accept/decline.
- Service offers, AGREE offer review and private messages.
- Accepted service and ride offers attempt to create a conversation.

Matching is rule-based, not AI semantic matching. Selecting a language saves the request language; it does not translate the whole interface.

## 1. Database setup (required)

Open the Supabase SQL Editor for the project configured in `index.html`.

1. Run all of `supabase/schema.sql`.
2. Confirm it completes without errors.
3. Run all of `supabase/feature-pack.sql` in a second query.
4. Confirm it completes without errors.

The scripts are committed to GitHub but have not been executed against your Supabase project from this session. Do not assume the database is ready until both scripts succeed.

## 2. Authentication

In Supabase, open Authentication → URL Configuration. Add the exact deployed fresh-app URL to Site URL and Redirect URLs. Keep email confirmation enabled for real users. Never place a service-role key in browser code; the app uses the publishable key.

## 3. Driver access

Ride offers require a profile with `account_type='driver'`. Do not assign driver access without checking applicable local licensing, insurance and vehicle requirements. The app does not yet provide a complete trusted driver-verification/admin workflow; a driver label is not proof of registration.

## 4. Separate deployment

Deploy only the contents of `fresh-app/` as a separate static site. Do not replace the repository-root `index.html`, change the original PHOMAB website, alter Cloudflare/Firebase settings, or deploy over the old site. Entry point: `index.html`.

## 5. Required tests

Use at least two separate test accounts:

- Register, confirm email if enabled, sign in and sign out.
- Publish a rental, job and service profile; verify each appears in its browse category.
- Test photo upload, including a file near 20 MB.
- Confirm phone numbers stay hidden without publisher consent and WhatsApp appears only when enabled.
- Confirm users cannot edit or delete another user's posts.
- Submit rental, job and service Asks; run Find my matches and Save match.
- Submit a ride request; verify an approved driver account sees it and can offer a fare.
- Verify the passenger can review, accept or decline the offer.
- Submit a service offer; verify the service owner can review and decide it.
- Accept an offer and test the generated conversation and messages from both accounts.
- Repeat on Android Chrome and desktop.

Do not invite real users until these tests pass.

## 6. Remaining work before production

- Video calling: WebRTC media, TURN service, realtime signalling, permissions and call lifecycle UI. The call-session table alone does not provide video calls.
- Live maps, route display, driver location sharing and trip tracking.
- Full Shona/Ndebele interface translation and speech recognition testing.
- Trusted driver verification/admin review, moderation, reporting, blocking and support.
- Push/email notifications and realtime message/offer updates.
- AI matching connected to live listing data; current ranking is keyword-based.
- Security, privacy, abuse/rate-limit, backup and load testing.

Do not describe this as a production-ready marketplace or ride service until these items are completed and the end-to-end tests pass.
