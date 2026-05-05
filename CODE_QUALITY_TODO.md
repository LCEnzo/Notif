# Code Quality TODO

Local working list for `codex/code-quality-audit`.

## Backend Hardening

- [x] Make password reset codes non-plaintext at rest.
- [x] Put an explicit failed-attempt cap on password reset confirmation.
- [x] Return explicit validation errors instead of silently dropping password updates.
- [x] Make scrape comparison-state JSON failures non-crashing and diagnosable.
- [x] Replace production scrape `assert` checks with explicit request failures.
- [x] Re-run `ruff`, `mypy`, and backend tests after each backend batch.

## Frontend Refactor

- [ ] Keep the existing token/theme/text system as the design-system source of truth.
- [x] Split `frontend/lib/commons/components/primitives.dart` into smaller primitive files behind one barrel export.
- [ ] Add missing reusable primitives before migrating more screens: radio, switch, dialog actions, app shell, list rows.
- [x] Add reusable field/input primitive and migrate the obvious ad-hoc field decorations.
- [ ] Break `frontend/lib/screens/homescreen.dart` into route shells, source widgets, notification widgets, dialogs, and painters.
- [ ] Move API DTOs and services out of the single `frontend/lib/services/data.dart` file.
- [ ] Replace raw `TextButton`, `OutlineInputBorder`, and ad-hoc control styling with primitives.
- [ ] Re-run `flutter analyze` and `flutter test` after each frontend batch.
