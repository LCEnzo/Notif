import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:notif/commons/auth_chrome.dart';
import 'package:notif/commons/auth_palette.dart';
import 'package:notif/commons/login_register_fields.dart';
import 'package:notif/commons/notif_text_theme.dart';
import 'package:notif/commons/notif_tokens.dart';
import 'package:notif/services/app_settings.dart';
import 'package:notif/services/auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LogInPage extends StatelessWidget {
  const LogInPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AuthScaffold(child: _FormContent());
  }
}

class _FormContent extends StatefulWidget {
  const _FormContent();

  @override
  _FormContentState createState() => _FormContentState();
}

class _FormContentState extends State<_FormContent> {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  bool rememberMe = false;

  @override
  void initState() {
    super.initState();

    _loadUsername();
    _loadRememberMe();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      final AuthService authService;
      authService = Provider.of<AuthService>(context, listen: false);
      if (authService.jwt != null) {
        Navigator.pushReplacementNamed(context, '/Home');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final appSettings = context.watch<AppSettingsController?>();
    final isFramed = appSettings?.authCardStyle == AuthCardStyle.framed;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: isFramed ? 420 : 330),
      child: AuthPanel(
        child: Form(
          key: formKey,
          child: isFramed
              ? _buildFramedForm(context, authService)
              : _buildGlassForm(context, authService),
        ),
      ),
    );
  }

  Widget _buildFramedForm(BuildContext context, AuthService authService) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AuthPanelHeader(
          eyebrow: '01 / auth',
          title: 'Welcome back',
          description: 'Use your handle and passphrase.',
        ),
        const SizedBox(height: 24),
        AuthField(
          label: 'Handle',
          meta: 'required',
          child: UsernameTextField(
            key: const Key('usernameField'),
            labelText: 'Username',
            hintText: 'Enter your username',
            textController: usernameController,
          ),
        ),
        const SizedBox(height: 20),
        AuthField(
          label: 'Passphrase',
          meta: 'required',
          child: PasswordTextField(
            key: const Key('passwordField'),
            labelText: 'Password',
            hintText: 'Enter your password',
            textController: passwordController,
            validator: noValidate,
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 360;

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _RememberDeviceRow(
                    value: rememberMe,
                    onChanged: _setRememberMe,
                  ),
                  const SizedBox(height: 8),
                  AuthInlineAction(
                    label: 'Forgot password?',
                    onPressed: () {
                      Navigator.pushNamed(context, '/ForgotPassword');
                    },
                  ),
                ],
              );
            }

            return Row(
              children: [
                Expanded(
                  child: _RememberDeviceRow(
                    value: rememberMe,
                    onChanged: _setRememberMe,
                  ),
                ),
                const SizedBox(width: 12),
                AuthInlineAction(
                  label: 'Forgot password?',
                  onPressed: () {
                    Navigator.pushNamed(context, '/ForgotPassword');
                  },
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        CustomButton(
          buttonText: 'Log in',
          trailingIcon: const Icon(Icons.arrow_forward_rounded, size: 16),
          onPressed: () async {
            if (rememberMe) {
              _saveUsername();
            }

            final loggedIn = await loginClick(authService, context);
            if (loggedIn && context.mounted) {
              Navigator.pushReplacementNamed(context, '/Home');
            }
          },
        ),
        const SizedBox(height: 12),
        const AuthRuleDivider(),
        const SizedBox(height: 12),
        CustomButton(
          buttonText: 'Create account',
          buttonColor: AuthPalette.secondaryButtonBase,
          onPressed: () {
            Navigator.pushReplacementNamed(context, '/Register');
          },
        ),
      ],
    );
  }

  Widget _buildGlassForm(BuildContext context, AuthService authService) {
    final rememberMeStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
      color: Colors.white70,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        UsernameTextField(
          key: const Key('usernameField'),
          labelText: 'Username',
          hintText: 'Enter your username',
          textController: usernameController,
        ),
        const SizedBox(height: 16),
        PasswordTextField(
          key: const Key('passwordField'),
          labelText: 'Password',
          hintText: 'Enter your password',
          textController: passwordController,
          validator: noValidate,
        ),
        const SizedBox(height: 16),
        CheckboxListTile(
          value: rememberMe,
          onChanged: (value) {
            if (value == null) return;
            _setRememberMe(value);
          },
          title: Text('Remember me', style: rememberMeStyle),
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          contentPadding: const EdgeInsets.all(0),
        ),
        const SizedBox(height: 16),
        CustomButton(
          buttonText: 'Log in',
          onPressed: () async {
            if (rememberMe) {
              _saveUsername();
            }

            final loggedIn = await loginClick(authService, context);
            if (loggedIn && context.mounted) {
              Navigator.pushReplacementNamed(context, '/Home');
            }
          },
        ),
        const SizedBox(height: 16),
        CustomButton(
          buttonText: 'Register',
          buttonColor: AuthPalette.secondaryButtonBase,
          onPressed: () {
            Navigator.pushReplacementNamed(context, '/Register');
          },
        ),
      ],
    );
  }

  Future<bool> loginClick(AuthService authService, BuildContext context) async {
    if (formKey.currentState?.validate() ?? false) {
      if (kDebugMode) {
        final pw = passwordController.text;
        final masked = pw.length >= 2
            ? '${pw[0]}***${pw[pw.length - 1]}'
            : pw.isNotEmpty ? '***' : '(empty)';
        debugPrint("Validated data:\n\tusername: ${usernameController.text}, password: $masked");
      }
      try {
        await authService.login(
          usernameController.text,
          passwordController.text,
        );
        return true;
      } catch (e) {
        if (context.mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            showDialog<dynamic>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Login Failed'),
                content: Text('$e'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          });
        }
      }
    }

    return false;
  }

  Future<void> _loadRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    bool? rememberMe = prefs.getBool('rememberMe');

    if (rememberMe != null && mounted) {
      setState(() {
        this.rememberMe = rememberMe;
      });
    }
  }

  Future<void> _saveRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('rememberMe', rememberMe);
  }

  Future<void> _loadUsername() async {
    final prefs = await SharedPreferences.getInstance();
    String? username = prefs.getString('username');

    if (username != null && mounted) {
      setState(() {
        usernameController.text = username;
      });
    }
  }

  Future<void> _saveUsername() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('username', usernameController.text);
  }

  void _setRememberMe(bool value) {
    setState(() {
      rememberMe = value;
    });
    _saveRememberMe();
  }

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  String? noValidate(String? password) {
    if (password == null || password.isEmpty) {
      return "Password cannot be empty";
    }

    return null;
  }
}

class _RememberDeviceRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _RememberDeviceRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final tokens = NotifTokens.of(context);
    final text$ = NotifTextTheme.of(context);

    return InkWell(
      onTap: () => onChanged(!value),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Checkbox(
            value: value,
            side: BorderSide(color: tokens.ruleStrong),
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            fillColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return tokens.btnBg;
              }
              return Colors.transparent;
            }),
            checkColor: tokens.btnInk,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            onChanged: (next) {
              if (next == null) return;
              onChanged(next);
            },
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Remember this device',
              style: text$.body.copyWith(color: tokens.inkDim),
            ),
          ),
        ],
      ),
    );
  }
}
