# Repo Recovery And Modernization Plan

This file tracks the current repository cleanup effort on the `master-integration` branch.

## Environment

- Active salvage worktree: `/tmp/notif-master-integration`
- Original workspace copy: `/mnt/c/Users/LCEnzo/Notif - Copy`
- User: `lcenzo`
- OS: Ubuntu 24.04.4 LTS on WSL2
- Kernel: `5.15.167.4-microsoft-standard-WSL2`
- Shell: `bash 5.2.21`
- Python: `3.12.3`
- `uv`: installed in user space as `~/.local/bin/uv`
- Backend verification environment: `/tmp/notif-master-integration/backend/.venv`
- Backend test runner: available inside that `.venv`
- `flutter`: installed separately but currently ignored during backend-focused salvage work

If you install tools for me, install them into this WSL environment so they are available from the Linux shell in `/tmp/notif-master-integration`.

## Current Known Facts

- `master` uses the personal email `lcenzo@protonmail.ch`. This is the desired base branch.
- `new-master` and several feature branches were created from a separate history rooted under the work email `luka.colic@qcerris.com`.
- `master` and `new-master` are not connected by normal ancestry. Their code is very similar, but Git sees them as unrelated histories.
- `origin/feat/site-crud-interface` is based on the `master` lineage and already includes a merge from `master`.
- The original checkout is noisy due to line-ending churn, so the active salvage work is happening in a clean worktree.

## Progress So Far

- [x] Create a clean worktree for salvage work
- [x] Create `master-integration` from `master`
- [x] Configure repo-local Git identity to use `Luka Colić <lcenzo@protonmail.ch>`
- [x] Add `.gitattributes` to reduce line-ending noise
- [x] Integrate the `new-master` baseline onto `master-integration`
- [x] Replace the deliberately failing placeholder in `backend/monitoring/tests.py`
- [x] Stabilize the frontend home screen enough to avoid the immediate `UnimplementedError`
- [x] Run `git diff --check`
- [x] Run `python3 -m compileall backend`
- [x] Create a local backend `.venv` with `uv`
- [x] Install backend dependencies needed for test execution
- [x] Run backend tests successfully

## Latest Checkpoint

- Branch: `master-integration`
- Commit: `9cf3ed7`
- Message: `Integrate new-master baseline into master-integration`

What that checkpoint includes:

- Backend-side `new-master` changes for permissions, test utilities, monitoring models/serializers/views/tests, strategy registration, and URL cleanup
- A non-crashing authenticated home screen path in Flutter
- `UserDataService` wired into the top-level provider tree
- `get_my_info` aligned with what the frontend expects
- Monitoring queryset fixes so the branch does not carry forward an obviously broken reverse relation

Working state beyond that checkpoint:

- `backend/manage.py test` now passes on `master-integration` in the local `.venv`
- A manual migration now renames `Strategy.function` to `Strategy.strat_cls`
- `origin/feat/site-crud-interface` has been reviewed and appears functionally absorbed by the current integration branch, with the remaining differences mostly being older tests, queryset bugs, and migration-shape choices

## Important Guardrails

- Do salvage work in this clean worktree, not in the original noisy checkout.
- Avoid merging unrelated histories just to preserve branch topology.
- Prefer selective integration, review, and stabilization over blind merges.
- Review migrations manually whenever branch code changes models.
- Keep risky branch work off `master` until a stable integration checkpoint exists.

## Branch Inventory

### `master`

- Personal-email lineage
- Intended final canonical branch

### `new-master`

- Work-email lineage
- First source branch integrated onto `master-integration`
- Baseline integration is complete

### `origin/feat/site-crud-interface`

- Based on the `master` lineage
- Review is now largely complete
- The useful behavior from this branch appears to already exist on `master-integration`
- Remaining differences are mostly migration layout and older implementations that should not be merged back blindly

### `origin/feat/frontend-register-screen`

- Frontend auth and registration work
- Still relevant after current integration

### `origin/feat/backend-dockerization`

- Docker-related work
- Lower priority than application correctness

### `origin/feat/jwt_auth`

- JWT/auth work
- Much of it may already be represented, but still needs verification before deletion

### `fix/strategy-testing`

- Strategy/testing branch
- Needs final verification before cleanup

## Known Functional Gaps

### Frontend

- The home screen no longer crashes immediately, but notifications are still placeholder-only.
- `frontend/lib/services/data.dart` is still stubbed.
- Auth persistence/storage is still unfinished.
- Flutter tooling is not installed here yet, so no real Flutter verification has been run.

### Backend

- Monitoring/scraping code still has TODO-heavy areas.
- Migrations still need branch-by-branch review.
- Backend tests currently pass in the local worktree environment.
- There is still no CI or modern test tooling setup yet.

### Repo Health

- The branch structure is still being converged.
- Only the `new-master` baseline integration is complete so far.

## Salvage TODO List

- [x] Create a clean worktree specifically for salvage work
- [x] Add `.gitattributes` to normalize line endings
- [x] Create `master-integration` from `master`
- [x] Compare `master-integration` against `new-master` and port the missing changes
- [x] Make the integrated `new-master` state stable enough to checkpoint
- [x] Review `origin/feat/site-crud-interface`
- [x] Reconcile the meaningful model and CRUD behavior differences from `origin/feat/site-crud-interface`
- [ ] Decide whether to keep the current migration chain or adopt a squashed variant before final merge
- [ ] Checkpoint the passing backend baseline after the site CRUD review
- [ ] Integrate `origin/feat/frontend-register-screen`
- [ ] Finish frontend auth flow so login, register, logout, and initial post-login navigation work
- [ ] Implement or remove stubbed frontend data-layer code
- [ ] Integrate `origin/feat/backend-dockerization`
- [ ] Verify whether `origin/feat/jwt_auth` contains anything still missing
- [ ] Verify whether `fix/strategy-testing` contains anything still missing
- [ ] Run backend tests
- [ ] Run frontend analysis/tests/build checks
- [ ] Manually test the login/register flow end to end
- [ ] Manually test link/strategy CRUD behavior end to end
- [ ] Merge `master-integration` into `master`
- [ ] Delete obsolete feature branches once their contents are confirmed present

## Modernization TODO List

- [ ] Create a new modernization branch from the cleaned-up `master`
- [ ] Move backend dependency management fully into `pyproject.toml`
- [ ] Adopt `uv` for environment and lockfile management
- [ ] Upgrade Django from the current 4.x-era setup to a current supported release
- [ ] Target Django 5.2 LTS first
- [ ] Pick a modern Python target version
- [ ] Update typing, linting, and test tooling accordingly
- [ ] Rework settings for cleaner local/dev/prod configuration
- [ ] Re-evaluate Docker setup after the app itself runs cleanly
- [ ] Decide whether SQLite remains the MVP database or whether PostgreSQL is now worth the extra setup

## Current Recommendation On Tech Choices

### Backend stack

- Django remains a valid choice for this project.
- Python remains the right language for the scraping side.
- There is no strong reason yet to split scraping into another language.

### Database

- SQLite is still reasonable for a one-user MVP.
- PostgreSQL becomes more attractive once concurrent writes, workers, or more production-like deployment matter.

### Frontend

- Mobile still matters because push notifications are an important goal.
- Flutter remains a viable direction for that goal.

## Next Step

- Checkpoint the current passing backend baseline on `master-integration`
- Move on to `origin/feat/frontend-register-screen`
- Finish the frontend auth path so login, registration, and post-login navigation are stable enough for real verification
