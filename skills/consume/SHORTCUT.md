# The "Consume" Apple Shortcut

A share-sheet button that sends whatever you're looking at (a tweet, an
article, a repo) into your Consume inbox with one tap. Build it once on your
iPhone; it syncs to your Mac through iCloud and shows up in the share menu
there too.

## Before you start

Run `setup/setup.sh` first. It prints the two values you need:

- **URL:** `https://<your-project-ref>.supabase.co/functions/v1/consume-capture`
- **Token:** the `CONSUME_CAPTURE_TOKEN` line in `~/.env.consume`

Get the token onto your phone without pasting it anywhere public: AirDrop a
note to yourself, or build the Shortcut on your Mac (step list is the same)
and let iCloud sync it.

## Build it (about three minutes)

1. Open **Shortcuts**, tap **+** to make a new shortcut.
2. Tap the name at the top, choose **Rename**, call it `Consume`.
3. Tap the **(i)** button, turn on **Show in Share Sheet**. Under share sheet
   types, keep **URLs** (you can turn the rest off).
4. If it asks what to do when there is no input, choose **Continue**.
5. Tap **Add Action**, search for **Get Contents of URL**, add it.
6. Set it up:
   - **URL:** your capture URL from above.
   - Tap **Show More**.
   - **Method:** `POST`.
   - **Headers:** add two:
     - `Authorization` with the value `Bearer YOUR_TOKEN` (the word Bearer, a
       space, then the token)
     - `Content-Type` with the value `application/json`
   - **Request Body:** `JSON`. Add one field: type **Text**, key `url`, and
     for the value pick the **Shortcut Input** variable.
7. Optional: add a **Show Notification** action after it saying `Saved to
   Consume`, so you know the tap landed.
8. Tap **Done**.

## Test it

Open any page in Safari, tap **Share**, then **Consume**. No error means it
saved. Run `/consume` in Claude Code and the link will be in the list.

From a terminal, the same request looks like this:

```bash
set -a; . ~/.env.consume; set +a
curl -sS -X POST "$CONSUME_CAPTURE_URL" \
  -H "Authorization: Bearer $CONSUME_CAPTURE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"url":"https://example.com"}'
# {"success":true,"id":"..."}
```

## On the Mac

The Shortcut arrives through iCloud. Use **Share, Consume** from Safari, Arc,
Chrome or anywhere with a share menu. If it's missing, open Shortcuts on the
Mac, find Consume and turn on **Show in Share Sheet** there too.

## If saving stops working

- **401 Unauthorized:** the token in the Shortcut doesn't match the function
  secret, or the function was deployed without `--no-verify-jwt`. Re-run
  `setup/setup.sh` (it keeps your existing token) and check the header value.
- **400:** the share didn't pass a URL. Make sure the request body uses
  **Shortcut Input** and the share sheet type includes URLs.
