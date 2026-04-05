import 'package:flutter/material.dart';
import 'package:Notif/commons/login_register_fields.dart';
import 'package:Notif/services/auth.dart';
import 'package:provider/provider.dart';

class HomePage extends StatelessWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: true);

    if (authService.jwt == null) {
      Future.delayed(Duration.zero, () {
        Navigator.pushNamed(context, '/LogIn');
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notif'),
        centerTitle: true,
        backgroundColor: Theme.of(context).primaryColor,
        leading: IconButton(
          icon: const Icon(Icons.logout),
          onPressed: () {
            authService.logout();
            Navigator.pushNamed(context, '/LogIn');
          },
        ),
      ),
      body: const Column(
        children: [
          Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Logo(title: "Placeholder"),
            ),
          ),
          Expanded(
            child: Center(
              child: NotificationsView(),
            ),
          ),
        ],
      ),
    );
  }
}

class NotificationsView extends StatelessWidget {
  const NotificationsView({super.key});

  @override
  Widget build(BuildContext context) {
    final userDataService = Provider.of<UserDataService>(context, listen: true);
    final userData = userDataService.userData;

    if (userData == null) {
      return const Padding(
        padding: EdgeInsets.all(24.0),
        child: Text(
          'Your notifications feed will appear here. User info is still loading.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Signed in as ${userData.username}',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Notifications are not wired up yet, but the authenticated home view is now in place for ${userData.name}.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
