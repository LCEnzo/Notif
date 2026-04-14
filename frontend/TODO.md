# Frontend Bugs

## auth.dart: No HTTP request timeouts

All `http.post` / `http.get` calls in `AuthService` and `UserDataService` have no timeout.
A hanging server will freeze the UI indefinitely with no feedback to the user.

Fix: Add `.timeout(Duration(seconds: N))` to each request future, and handle
`TimeoutException` with a user-facing error.

## pubspec.yaml: Hardcoded font family not declared

`main.dart` references `fontFamily: 'Hack Regular'` but no font assets are declared in
`pubspec.yaml` under the `fonts:` section. The font silently falls back to the system
default, meaning the `fontFamily` line is dead code that misleads anyone reading the theme.

Fix: Either add the Hack font files to the project and declare them in pubspec.yaml, or
remove the `fontFamily` line.

## about.dart: Broken string interpolation in mailto error

The mailto error handler has:
```dart
throw 'Could not launch $emailLaunchUri.toString()';
```
This interpolates `emailLaunchUri` (calling its own `.toString()` implicitly) and then
appends the literal string `.toString()`. Should be `$emailLaunchUri` or
`${emailLaunchUri.toString()}`.
