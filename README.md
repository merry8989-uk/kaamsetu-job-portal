# KaamSetu — Job Vacancy Portal

A responsive job portal starter with Supabase Auth + Postgres, employer posting, admin moderation, and GitHub Pages hosting.

## Included
- Responsive Hindi/English job board, search by title/company/location, job-type filter.
- Email/password login and registration.
- Job-seeker and employer account requests.
- Employers submit jobs; new posts remain `pending` until admin approval.
- Admin can approve/reject/delete posts.
- Supabase Row Level Security policies enforce public approved-only listings, company/admin posting, and admin moderation.
- GitHub Pages deployment (static frontend).

## Architecture
- Frontend: plain HTML/CSS/JavaScript (`index.html`)
- Auth + database: Supabase
- Hosting: GitHub Pages
- No service-role key in browser. Only the Supabase anon/publishable key is used client-side.

## Step-by-step setup

### 1. Create the GitHub repository
1. Sign in to GitHub.
2. Open https://github.com/new
3. Repository name: `kaamsetu-job-portal`
4. Choose **Public** if you want free GitHub Pages on a standard public repository. Do not initialize with a README if you plan to upload these files directly.
5. Create repository, then upload `index.html`, `supabase-schema.sql`, and `README.md` using **Add file → Upload files** and commit.

### 2. Create the Supabase project
1. Open https://supabase.com/dashboard and create a project.
2. In **SQL Editor**, open a new query, paste all contents of `supabase-schema.sql`, and run it.
3. Open **Project Settings → API** (or Connect) and copy the Project URL and anon/publishable key.
4. In `index.html`, replace:
   - `YOUR_SUPABASE_PROJECT_URL`
   - `YOUR_SUPABASE_ANON_KEY`
   with your real values.
5. Commit the updated `index.html` to GitHub.
6. Never use the `service_role` / secret key in browser JavaScript.

### 3. Make your account admin
1. In Supabase Authentication → Users, register an account through the website first.
2. In SQL Editor, run the following, replacing the email:
   ```sql
   update public.profiles p set role = 'admin'
   from auth.users u where p.id = u.id and u.email = 'YOUR_EMAIL@example.com';
   ```
3. Log out and log back in. Your Dashboard should now show Admin moderation.

### 4. Approve employers
New registrations are always created as `job_seeker`, intentionally. Verify the employer first, then promote their account in SQL Editor:
```sql
update public.profiles p set role = 'company'
from auth.users u where p.id = u.id and u.email = 'EMPLOYER_EMAIL@example.com';
```
A company can submit a vacancy. It stays pending until admin approves it.

### 5. Enable GitHub Pages
1. Open repository **Settings → Pages**.
2. Under Build and deployment, choose **Deploy from a branch**.
3. Select branch `main` and folder `/ (root)`, then Save.
4. Wait for deployment. Your URL will look like `https://YOUR_GITHUB_USERNAME.github.io/kaamsetu-job-portal/`.

### 6. Test before launch
- Register a job seeker: they must not be able to post.
- Promote a test account to `company`; submit a job: it must be pending and not public.
- As admin, approve it: it should appear publicly.
- Test reject/delete and expired deadline display.
- Test on mobile and desktop.
- Verify application links and employer identity before approving posts.

## Separate pages: Jobs, Tenders, Schemes

`index.html` shows **jobs only**. Tenders and schemes live on their own sub-pages,
each with the same browse-by-state / browse-by-district controls and district links:

- `tenders.html` - `kind = 'tender'`
- `schemes.html` - `kind = 'scheme'`

GitHub Pages serves them at `/tenders.html` and `/schemes.html`. The nav on every
page links across.

## Important limitations / production hardening
- This is a functional starter, not a fully audited commercial hiring platform.
- Employer approval currently uses manual SQL. Build a dedicated admin user-management screen before handing it to a larger team.
- Public application links are used; this starter does not store candidate CVs or application records.
- Add CAPTCHA/rate limiting, audit logs, email verification, privacy policy, terms, report-abuse workflow, backups, and monitoring before public launch.
- Do not collect Aadhaar, bank details, passwords, or fees from applicants. Warn users against job scams.
- Supabase free-tier limits and GitHub Pages availability/terms may change.
