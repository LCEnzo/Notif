import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:notif/commons/components/primitives.dart';
import 'package:notif/commons/dither_overlay.dart';
import 'package:notif/commons/notif_text_theme.dart';
import 'package:notif/commons/notif_tokens.dart';
import 'package:notif/services/api_client.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/auth.dart';
import 'package:notif/services/device_sessions.dart';
import 'package:provider/provider.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _profileLoading = false;
  bool _passwordLoading = false;
  bool _deleteLoading = false;
  String? _profileError;
  String? _passwordError;
  bool _profileSaved = false;
  bool _passwordSaved = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUserData();
      unawaited(context.read<DeviceSessionService>().fetch());
    });
  }

  void _loadUserData() {
    final userData = context.read<UserDataService>().userData;
    if (userData != null) {
      _usernameController.text = userData.username;
      _emailController.text = userData.email;
      _nameController.text = userData.name;
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _nameController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  /// The api_client attaches the credential; this only names the payload
  /// shape. Kept as a helper so the call sites read the same as before.
  Map<String, String> _authHeaders(AuthService auth) => const {
    'Content-Type': 'application/json',
  };

  Future<void> _saveProfile() async {
    final auth = context.read<AuthService>();
    final settings = context.read<AppSettingsController?>();
    final userId = auth.currentUserId;
    if (userId == null) return;

    setState(() {
      _profileLoading = true;
      _profileError = null;
      _profileSaved = false;
    });

    try {
      final response = await apiPatch(
        '/accounts/users/$userId/',
        settings: settings,
        headers: _authHeaders(auth),
        body: {
          'username': _usernameController.text.trim(),
          'email': _emailController.text.trim(),
          'name': _nameController.text.trim(),
        },
      );
      expectSuccessStatus(
        response,
        'Update profile',
        successCodes: const {200},
      );

      // Refresh cached user data so the top bar shows updated info.
      if (mounted) {
        await context.read<UserDataService>().getUserInfo();
      }
      if (!mounted) {
        return;
      }

      setState(() {
        _profileSaved = true;
      });
    } on Exception catch (error) {
      setState(() {
        _profileError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _profileLoading = false;
        });
      }
    }
  }

  Future<void> _changePassword() async {
    final auth = context.read<AuthService>();
    final settings = context.read<AppSettingsController?>();

    final current = _currentPasswordController.text;
    final newPw = _newPasswordController.text;
    final confirm = _confirmPasswordController.text;

    if (newPw != confirm) {
      setState(() {
        _passwordError = 'New passwords do not match.';
      });
      return;
    }

    setState(() {
      _passwordLoading = true;
      _passwordError = null;
      _passwordSaved = false;
    });

    try {
      final response = await apiPost(
        '/accounts/users/change_password/',
        settings: settings,
        headers: _authHeaders(auth),
        body: {'current_password': current, 'new_password': newPw},
      );
      expectSuccessStatus(
        response,
        'Change password',
        successCodes: const {200},
      );
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      setState(() {
        _passwordSaved = true;
      });
    } on Exception catch (error) {
      setState(() {
        _passwordError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _passwordLoading = false;
        });
      }
    }
  }

  Future<void> _deleteAccount() async {
    final auth = context.read<AuthService>();
    final settings = context.read<AppSettingsController?>();
    final userId = auth.currentUserId;
    if (userId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final tokens = NotifTokens.of(ctx);
        final text$ = NotifTextTheme.of(ctx);
        return AlertDialog(
          backgroundColor: tokens.bg1,
          title: Text(
            'Delete account?',
            style: text$.heading.copyWith(color: tokens.ink),
          ),
          content: Text(
            'This will soft-delete your account — your username, links, and notifications '
            'will be deactivated but not permanently removed. You cannot undo this from the app.',
            style: text$.body.copyWith(color: tokens.inkDim),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                'Cancel',
                style: text$.body.copyWith(color: tokens.inkMute),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text(
                'Delete',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() {
      _deleteLoading = true;
    });

    try {
      final response = await apiDelete(
        '/accounts/users/$userId/',
        settings: settings,
        headers: _authHeaders(auth),
      );
      expectSuccessStatus(response, 'Delete account');
      // Deleting the account revokes every session server-side, so this only
      // has to clear the local credential and let the router take over.
      await auth.logout();
      if (mounted) {
        context.go('/login');
      }
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _deleteLoading = false;
        });
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('Delete failed: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);
    final appSettings = context.watch<AppSettingsController?>();

    return Scaffold(
      backgroundColor: tokens.bg1,
      appBar: AppBar(
        backgroundColor: tokens.bg1,
        foregroundColor: tokens.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 24,
        title: Row(
          children: [
            Text(
              'Notif',
              style: text$.heading.copyWith(
                color: tokens.ink,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '/ account',
              style: text$.micro.copyWith(color: tokens.inkMute),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: tokens.rule),
        ),
      ),
      body: Stack(
        children: [
          if (appSettings?.designDitheringEnabled ?? true)
            const DitherOverlay(),
          SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const IndexRule(index: 1, title: 'Profile'),
                    const SizedBox(height: 8),
                    Text(
                      'Edit your public profile. Leaving a field empty reverts to the default.',
                      style: text$.body.copyWith(color: tokens.inkDim),
                    ),
                    const SizedBox(height: 16),
                    NotifCard(
                      bordered: true,
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _FieldLabel(
                            text$: text$,
                            tokens: tokens,
                            label: 'Username',
                          ),
                          const SizedBox(height: 6),
                          _AccountTextField(
                            controller: _usernameController,
                            hint: 'your-username',
                          ),
                          const SizedBox(height: 16),
                          _FieldLabel(
                            text$: text$,
                            tokens: tokens,
                            label: 'Email',
                          ),
                          const SizedBox(height: 6),
                          _AccountTextField(
                            controller: _emailController,
                            hint: 'you@example.com',
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 16),
                          _FieldLabel(
                            text$: text$,
                            tokens: tokens,
                            label: 'Display name',
                          ),
                          const SizedBox(height: 6),
                          _AccountTextField(
                            controller: _nameController,
                            hint: 'Your Name',
                          ),
                          if (_profileError != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _profileError!,
                              style: text$.micro.copyWith(
                                color: NotifFeedback.error,
                              ),
                            ),
                          ],
                          if (_profileSaved) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Profile saved.',
                              style: text$.micro.copyWith(
                                color: NotifFeedback.success,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          NotifButton(
                            label: _profileLoading ? 'Saving…' : 'Save profile',
                            onPressed: _profileLoading ? null : _saveProfile,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                    const IndexRule(index: 2, title: 'Password'),
                    const SizedBox(height: 8),
                    Text(
                      'Change your password. You will stay logged in after changing it.',
                      style: text$.body.copyWith(color: tokens.inkDim),
                    ),
                    const SizedBox(height: 16),
                    NotifCard(
                      bordered: true,
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _FieldLabel(
                            text$: text$,
                            tokens: tokens,
                            label: 'Current password',
                          ),
                          const SizedBox(height: 6),
                          _AccountTextField(
                            controller: _currentPasswordController,
                            hint: 'Enter current password',
                            obscure: true,
                          ),
                          const SizedBox(height: 16),
                          _FieldLabel(
                            text$: text$,
                            tokens: tokens,
                            label: 'New password',
                          ),
                          const SizedBox(height: 6),
                          _AccountTextField(
                            controller: _newPasswordController,
                            hint: 'Enter new password',
                            obscure: true,
                          ),
                          const SizedBox(height: 16),
                          _FieldLabel(
                            text$: text$,
                            tokens: tokens,
                            label: 'Confirm new password',
                          ),
                          const SizedBox(height: 6),
                          _AccountTextField(
                            controller: _confirmPasswordController,
                            hint: 'Confirm new password',
                            obscure: true,
                          ),
                          if (_passwordError != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _passwordError!,
                              style: text$.micro.copyWith(
                                color: NotifFeedback.error,
                              ),
                            ),
                          ],
                          if (_passwordSaved) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Password changed.',
                              style: text$.micro.copyWith(
                                color: NotifFeedback.success,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          NotifButton(
                            label: _passwordLoading
                                ? 'Changing…'
                                : 'Change password',
                            onPressed: _passwordLoading
                                ? null
                                : _changePassword,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                    const IndexRule(index: 3, title: 'Devices'),
                    const SizedBox(height: 8),
                    Text(
                      'Every device currently signed in as you. Revoking one '
                      'signs it out on its next request — this is how you undo '
                      'a sign-in you did not intend.',
                      style: text$.body.copyWith(color: tokens.inkDim),
                    ),
                    const SizedBox(height: 16),
                    const _DeviceSessionsSection(),
                    const SizedBox(height: 40),
                    const IndexRule(index: 4, title: 'Danger'),
                    const SizedBox(height: 8),
                    Text(
                      'Soft-delete your account. All your data is preserved but deactivated.',
                      style: text$.body.copyWith(color: tokens.inkDim),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: tokens.bg2,
                        border: Border.all(
                          color: Colors.redAccent.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Once deleted, you will be logged out and cannot log back in. '
                            'Contact the server admin to restore the account.',
                            style: text$.body.copyWith(color: tokens.inkDim),
                          ),
                          const SizedBox(height: 16),
                          NotifButton(
                            label: _deleteLoading
                                ? 'Deleting…'
                                : 'Delete account',
                            onPressed: _deleteLoading ? null : _deleteAccount,
                            variant: NotifButtonVariant.primary,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({
    required this.text$,
    required this.tokens,
    required this.label,
  });
  final NotifTextTheme text$;
  final NotifTokens tokens;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: text$.micro.copyWith(color: tokens.inkMute, letterSpacing: 1.2),
    );
  }
}

class _AccountTextField extends StatelessWidget {
  const _AccountTextField({
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.keyboardType,
  });
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return NotifTextField(
      controller: controller,
      hint: hint,
      obscureText: obscure,
      keyboardType: keyboardType,
    );
  }
}

class _DeviceSessionsSection extends StatelessWidget {
  const _DeviceSessionsSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NotifTokens>()!;
    final text$ = theme.extension<NotifTextTheme>()!;
    final service = context.watch<DeviceSessionService>();
    final sessions = service.sessions;
    final others = sessions.where((session) => !session.isCurrent).length;

    return NotifCard(
      bordered: true,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (service.error != null) ...[
            Text(
              service.error!,
              style: text$.body.copyWith(color: Colors.redAccent),
            ),
            const SizedBox(height: 12),
          ],
          if (service.loading && sessions.isEmpty)
            Text(
              'Loading devices…',
              style: text$.body.copyWith(color: tokens.inkDim),
            )
          else if (sessions.isEmpty)
            Text(
              'No devices to show.',
              style: text$.body.copyWith(color: tokens.inkDim),
            )
          else
            for (final session in sessions) ...[
              _DeviceSessionRow(session: session, service: service),
              if (session != sessions.last) const SizedBox(height: 16),
            ],
          if (others > 0) ...[
            const SizedBox(height: 20),
            NotifButton(
              label: service.loading
                  ? 'Working…'
                  : 'Sign out other devices ($others)',
              onPressed: service.loading
                  ? null
                  : () => unawaited(service.revokeAllOthers()),
            ),
          ],
        ],
      ),
    );
  }
}

class _DeviceSessionRow extends StatelessWidget {
  const _DeviceSessionRow({required this.session, required this.service});

  final DeviceSession session;
  final DeviceSessionService service;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NotifTokens>()!;
    final text$ = theme.extension<NotifTextTheme>()!;
    final lastUsed = session.lastUsedAt;
    final revoking = service.isRevoking(session.publicId);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                session.isCurrent
                    ? '${session.displayName} — this device'
                    : session.displayName,
                style: text$.body.copyWith(color: tokens.ink),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  session.transport,
                  if (session.ip.isNotEmpty) session.ip,
                  if (lastUsed != null)
                    'last used ${lastUsed.toIso8601String().substring(0, 16)}',
                ].join(' · '),
                style: text$.micro.copyWith(color: tokens.inkMute),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        NotifButton(
          label: revoking ? 'Revoking…' : 'Revoke',
          onPressed: revoking
              ? null
              : () => unawaited(service.revoke(session.publicId)),
        ),
      ],
    );
  }
}
