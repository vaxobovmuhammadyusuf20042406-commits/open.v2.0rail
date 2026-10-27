# Open Rail: put your clothing swap online

Open Rail is a clothing swap that never closes. People sign up, hang up clothes they no longer wear (photo, size, condition, fabric), browse what others posted, ask for a swap, chat to agree a handover, and mark items as swapped.

It is three files plus a free Supabase project for accounts, data and photos:

| File | What it is |
|---|---|
| `index.html` | The whole website |
| `config.js` | Your settings. The only file you edit |
| `schema.sql` | The database setup you paste into Supabase once |

Open `index.html` before you set anything up and it runs in **demo mode** with sample data, so you can try every feature first.

Setup takes about 20 minutes. You don't need to write code.

---

## 1. Create a Supabase project (free)

1. Go to [supabase.com](https://supabase.com) and sign up.
2. Click **New project**. Pick any name (e.g. `open-rail`), set a database password (save it somewhere), and choose the region closest to your swappers.
3. Wait a minute or two while it starts.

## 2. Set up the database

1. In your project, open **SQL Editor** in the left sidebar, then **New query**.
2. Open `schema.sql`, copy everything, paste it in, and click **Run**.
3. You should see "Success. No rows returned."

This creates the tables, the photo storage, live updates, and the security rules:

- Anyone can browse items, even without an account.
- Only you can edit or delete your own items and photos.
- A swap request and its chat are visible only to the two people involved.
- Email addresses are never shown to other users.

## 3. Connect the website to your project

1. In Supabase, go to **Project Settings → API Keys**.
2. Copy the **Publishable key** (starts with `sb_publishable_`). If you only see the older keys, copy the **anon** key instead.
3. Copy your **Project URL** too. It's shown in **Project Settings → Data API**, or in the **Connect** dialog at the top of the dashboard. It looks like `https://abcdefgh.supabase.co`.
4. Open `config.js` in any text editor and fill in both values:

```js
window.OPEN_RAIL_CONFIG = {
  supabaseUrl: "https://abcdefgh.supabase.co",
  supabaseKey: "sb_publishable_xxxxxxxxxxxx",
  community: "Neukölln",   // optional, shown in the headline
};
```

The publishable key is designed to be public; the security rules from step 2 protect the data. **Never** put the *secret* or *service_role* key in this file.

## 4. Choose how sign-up emails work

Supabase's built-in email sender only allows **2 emails per hour** for the whole project. That covers testing, but not a launch.

**Option A: no confirmation emails (fastest)**
In Supabase go to **Authentication → Sign In / Providers → Email** and turn off **Confirm email**. People can sign up and start swapping immediately. Password-reset emails still use the 2-per-hour limit.

**Option B: your own email sender (recommended once real people use it)**
Create a free account with an email service such as Brevo or Resend. In Supabase, go to **Authentication → Emails → SMTP Settings**, enable custom SMTP, and enter the details they give you. Then you can leave **Confirm email** on.

## 5. Put it online (free)

The easiest route is **Netlify Drop**:

1. Go to [app.netlify.com/drop](https://app.netlify.com/drop) and create a free account.
2. Drag the folder containing `index.html`, `config.js` and `schema.sql` onto the page.
3. You get an address like `https://wonderful-name-123.netlify.app`. You can rename it under **Site configuration → Change site name**.

To update the site later, drag the folder onto the site's **Deploys** page.

Other free hosts work too, such as GitHub Pages, Cloudflare Pages and Vercel. Any host that serves static files is fine.

## 6. Tell Supabase your site's address

This makes password-reset and confirmation links return to your site.

1. In Supabase go to **Authentication → URL Configuration**.
2. Set **Site URL** to your site's address, e.g. `https://openrail-neukolln.netlify.app`.
3. Under **Redirect URLs**, add the same address followed by `/**`.

## 7. Test it

1. Open your site and click **Sign in → Create account**.
2. Hang up an item with a photo.
3. In a private browser window, create a second account and ask for that item.
4. Back in the first window, open **My rail**, accept the request, and send a message. It appears in the other window within a few seconds.

If that works, share the link.

---

## How a swap works

1. **Hang it up.** The item appears on the rail as *Available*.
2. **Someone asks.** They write a message and can offer one of their own items in return.
3. **The owner accepts.** The item becomes *Reserved* for that person, and the two of them chat to agree a time and place.
4. **Hand over and mark it swapped.** The item moves off the rail, and any other open requests for it are declined automatically.

Either side can step back. The asker can withdraw, and the owner can decline or undo a reservation to put the item back on the rail.

## Keeping it running

- **Free tier limits.** Supabase's free plan includes a 500 MB database, 1 GB of file storage and 50,000 monthly active users, which is plenty for a community swap. Photos are shrunk to 1200 px before upload to save space. Free projects are **paused after a week with no activity**; open the dashboard and click *Restore* if that happens, or upgrade if you want it always on.
- **Removing a problem post.** In Supabase, open **Table Editor → items**, find the row and delete it. Swap requests and messages for it are deleted with it.
- **Removing a user.** In **Authentication → Users**, delete the user. Their profile, items, requests and messages are deleted too.
- **Backups.** In **Table Editor**, you can export any table as CSV.

## Troubleshooting

| What you see | What to do |
|---|---|
| "Demo mode" banner on your live site | `config.js` is empty or wasn't uploaded. Check both values and re-deploy the whole folder. |
| "Can't reach the server" | Check the Project URL in `config.js` and that the project isn't paused. |
| Sign-up says to check email, but nothing arrives | You've hit the 2-emails-per-hour limit. See step 4. |
| Reset link opens the wrong site | Set the Site URL and Redirect URLs (step 6). |
| Photos don't upload | Re-run only section 5 of `schema.sql`, or check that a bucket called `photos` exists under **Storage**. |
| Messages only appear after a reload | Re-run only section 6 of `schema.sql`. The page also refreshes itself every minute as a fallback. |
