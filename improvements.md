# FellScout improvements

Prioritised list generated 2026-06-18. Focus: simplification and maintainability.
Computing resources are plentiful; internet access at the event is poor.

---

## Priority 1 — Actual bugs

- [x] **1. Vendor CDN assets** (`views/layouts/main.tt:7-25`)
  Bootstrap, jQuery, FancyTable, and Leaflet are all loaded from external CDNs — the UI
  will be broken or slow at the event. Download them into `public/`.
  Also: jQuery is loaded *twice* (lines 7 and 10, different versions).
  **Reconsidered, not done.** Devices only get one guaranteed connection (at
  start/finish) and poor-to-none thereafter (checkpoints), so what actually matters is
  whether the *first* load gets cached hard enough to survive that. Checked directly:
  jsdelivr/unpkg/code.jquery.com already send `Cache-Control: public, max-age=31536000`
  (or `immutable`) on these exact versioned URLs, so they're already cached maximally
  after that first load — vendoring wouldn't improve on that, and trades a one-line
  URL bump for manually re-fetching/verifying/committing binary blobs on every future
  library update. Did the part that *was* missing instead: FellScout's own static
  assets (`public/css/style.css` etc.) had no `Cache-Control` at all (confirmed - just
  `Last-Modified`), so added one via a small Plack middleware in `bin/app.psgi`
  (`public, max-age=604800`; Dancer2's own hooks don't fire for static files - they're
  served by an internal `Plack::App::File` ahead of the hook chain). Also found and
  deleted three dead files while in there: `public/javascripts/jquery.js` and
  `moment.min.js` (vendored once, never referenced by any template) and `teams.js`
  (references a nonexistent `api/teams/table` endpoint and the DataTables API, not
  FancyTable - clearly an abandoned prototype). New coverage in `t/003_app_psgi.t`,
  the first test to exercise `bin/app.psgi` itself rather than `FellScout->to_app`
  directly.

  **Double jQuery load: done separately.** Checked what the app actually needs
  (grepped every `.tt`/`.js` file for jQuery usage) before picking which copy to
  keep: only plain `$(document).ready(...)` and `$(".table").fancyTable(...)` -
  nothing needs the `ajax`/`effects` modules the *slim* build drops. Kept the slim
  3.3.1 build (it already had a proper `https://` URL, SRI `integrity` hash, and
  `crossorigin` - the full 3.4.1 build had none of those, was protocol-relative
  `//...`, and was loading *first*, so slim already silently won every load since it
  overwrote `window.jQuery` second - removing the redundant copy is a zero
  runtime-behaviour change). Regression test in `t/030_routes.t` asserts the layout
  includes jQuery core exactly once.

- [x] **2. Scratch team deletion only processes the first entrant** (was `FellScout.pm:613`)
  ```perl
  foreach (my $row = $sth->fetchrow_hashref()){  # should be `while`
  ```
  `foreach` evaluates the expression once and loops over that single value, so only the
  first entrant in the team gets their team reset when deleting a scratch team.
  **Fixed**: now `FellScout::Data::delete_scratch_team`, uses `while`. Regression test
  in `t/034_scratch_teams.t`.

- [x] **3. `get_percentile()` pushes the same element N times** (was `FellScout.pm:1327-1330`)
  ```perl
  for(0 .. $index){
      push(@numbers, $in[$index]);  # should be $in[$_]
  }
  ```
  Builds `@numbers` as N copies of one element rather than a slice of the array.
  Arrival-time predictions are wrong whenever `percentile_sample_size` is in effect.
  **Fixed**: now `FellScout::Sync::get_percentile`, uses `$in[$_]`. Regression test in
  `t/010_data_munging.t`.

- [x] **4. Leg-matching pattern is too broad** (was `FellScout.pm:539`)
  ```perl
  $sth->execute($route, $route, "%-$checkpoint");
  ```
  `leg_name LIKE '%-5'` also matches `15-5`, `25-5`, etc. Replace the `LIKE` on
  `leg_name` with a direct `leg_to = ?` join condition.
  **Fixed, but the actual root cause was narrower than described above**: for this
  app's single-dash `"$from-$to"` leg-naming scheme, `LIKE '%-N'` turns out to already
  be equivalent to `leg_to = N` in every normal case. The one real failure mode is a
  route that revisits a checkpoint (an out-and-back section) — then `leg_to` for that
  checkpoint is genuinely ambiguous (two legs share it), and the query's scalar
  subquery died with "Subquery returns more than 1 row" regardless of LIKE vs `=`.
  Now `FellScout::Data::get_checkpoint_arrivals` uses `leg_to = ? order by index desc
  limit 1` — picks the *last* occurrence of a revisited checkpoint (arbitrary but safe
  choice; revisit if a real out-and-back route ever gets used for an event). Regression
  test in `t/031_api_content.t`.

- [x] **5. `to_hhmm` reads `$_` for no reason** (was `FellScout.pm:1302-1303`)
  ```perl
  $separator = $_ if $_;  # $_ is whatever Perl's implicit variable happens to be
  ```
  The separator is never passed as an argument and the function doesn't use a custom
  separator anywhere. Delete the line.
  **Resolved differently**: turned out `to_hhmm` (not `to_hh_mm`, its near-twin) had
  zero call sites anywhere in the app. Deleted the whole function rather than the one
  line.

---

## Priority 2 — Structural simplifications

- [x] **6. Magic number `99` for "finish checkpoint" is used ~25 times**
  (`FellScout.pm` and `progress-to-db`, throughout)
  Define it once at the top of each file:
  ```perl
  use constant FINISH_CP => 99;
  ```
  **Declined.** With ~20 checkpoints per real event there's no realistic collision
  risk, and most usages are embedded in raw SQL string literals anyway (`and
  checkpoint = 99`), which can't cleanly share a Perl constant without string
  interpolation — a partial fix would leave `FINISH_CP` and literal `99` both
  referring to the same thing in the same file, arguably less clear than now.

- [x] **7. `get_summary()` fires 12+ queries in two near-identical blocks** (was `FellScout.pm:58-175`)
  Global stats and then the same 6 queries repeated per route. The earliest/latest finish
  queries are identical except `ASC`/`DESC` — one query, take first/last row. Any SQL change
  currently needs to be made in 3+ places.
  **Done**: factored into `_route_summary($dbh, $route)` (undef route = all teams) and
  `_finish_extremes($dbh, $where, @params)`, called once for general stats and once per
  route. Found and fixed two bugs uncovered while consolidating the earliest/latest-finish
  queries: (1) the old `ASC`/`DESC` pair had earliest_finish and latest_finish's *results*
  swapped, which `views/summary.tt` happened to swap back again when displaying them — two
  bugs cancelling out, so the page looked right but the underlying data (and `/api/summary`)
  was backwards; now both are correctly named and the template no longer needs to
  compensate. (2) the template also referenced a nonexistent `finish_expected_time` field
  (real field: `finish_expected_in`) — the "finish expected in Xh Ym" line has always
  rendered blank; fixed. Regression tests in `t/031_api_content.t`.

- [ ] **8. `get_checkpoints()` calls `get_checkpoint_details()` N times inside a loop** (`FellScout.pm:388-391`)
  Each call fires 5+ more queries. Logic is split across two functions each with their own
  inner loops, making it hard to follow what data ends up where.

- [x] **9. `run_cronjobs()` builds a shell command with string interpolation** (now
  `FellScout::Sync::run_cronjobs`, `lib/FellScout/Sync.pm`)
  ```perl
  my $cmd = join(" ", cwd()."/bin/get-data", $config{felltrack_owner}, ...);
  ```
  Credentials containing spaces or shell metacharacters will silently break this.
  Use list-form `open` instead:
  ```perl
  open(my $fh, '-|', cwd()."/bin/get-data", $owner, $user, $pass)
  ```
  **Done** — both the `get-data` and `progress-to-db` invocations use list-form
  `open('-|', @args)` now; with more than one list element Perl guarantees no shell
  is involved, so credentials reach the script as literal arguments regardless of
  their content. `t/032_cron.t` already exercises the full pipeline through this
  code path end-to-end.

- [x] **10. `FellScout.pm` is ~1350 lines of routes + logic + data-access all mixed together**
  Split data-access functions (`get_summary`, `get_teams`, `get_legs`, etc.) into a
  separate `FellScout::Data` module. Makes both files much easier to scan after a year away.
  **Done**: split into `FellScout::Data` (queries + scratch-team mutations, `$dbh`
  passed explicitly) and `FellScout::Sync` (the FellTrack sync pipeline). `FellScout.pm`
  is routes only now.

---

## Priority 3 — Dead code (remove to reduce confusion)

- [x] **11. Unused `%teams` hash in `get_legs()`** (was `FellScout.pm:265-270`)
  Built using `$row->{number}` (which doesn't exist — should be `{team_number}`) and then
  never referenced. Delete the whole block.
  **Fixed** — deleted.

- [x] **12. Unused `%legs_seconds` hash in `get_team()`** (was `FellScout.pm:946-952`)
  Built from a routes+legs JOIN, never used. Delete it.
  **Fixed** — deleted.

- [x] **13. `routes_checkpoints` table is never populated or read** (was `build/sql/all.sql:163-171`)
  Nothing in the codebase touches this table. Drop it from the schema.
  **Done** — dropped from `all.sql`; also removed from `FellScout::Data::clear_cache`'s
  truncate list (it referenced the table by name, which would have started failing
  once the table no longer existed). Verified by restarting `db-test` (tmpfs, so a
  restart re-runs the init scripts from scratch) and confirming a clean import.

- [x] **14. Duplicate `config` table definition in `all.sql`** (was `build/sql/all.sql:257-269`)
  The SQL file was assembled from two separate dumps; `config` CREATE TABLE appears twice.
  Remove the second copy (keep the one followed by the INSERT data).
  **Done** — removed the first (data-less) `CREATE TABLE config`, kept the second
  (immediately followed by the `INSERT INTO config VALUES (...)` seed data). Same
  verification as #13 — one clean `config` table, all 18 seed rows present.

---

## Priority 4 — Operational / deployment

- [x] **15. `mariadb:latest` in `compose.yaml:25`**
  Pin to a specific version (e.g. `mariadb:11.8`) so the DB doesn't silently change
  between events a year apart.
  **Done** — `db` now pins `mariadb:11.8`, matching `db-test` (which was already
  pinned when it was added for testing).

- [x] **16. DB credentials hardcoded in `compose.yaml`**
  `MARIADB_ROOT_PASSWORD: supersecret` is in the repo. Move to a `.env` file that is
  gitignored. Docker Compose supports this natively.
  **Done** — `web`/`db`/`cron` all reference `${DB_ROOT_PASSWORD}` now, read from a
  gitignored `.env` (`.env.example` committed as the template). The `.env` created
  here keeps the *same* password value that was previously hardcoded — changing it
  wouldn't actually rotate the password on the existing `fellscout_db` volume
  (MariaDB only applies `MARIADB_ROOT_PASSWORD` on first init of a fresh data
  directory), it would just break connectivity until the volume is recreated or the
  password is changed manually inside the running DB. `db-test`'s password stays
  hardcoded (`test`) — it's a disposable local test credential, not a secret, and
  also has to match the literal value in `t/lib/TestDB.pm`.
