import 'package:flutter/material.dart';
import 'package:notif/commons/login_register_fields.dart';
import 'package:notif/services/auth.dart';
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
        leading: BackButton(
          onPressed: () {
            authService.logout();
            Navigator.pushNamed(context, '/LogIn');
          },
        ),
      ),
      body: const SingleChildScrollView(
        child: Center(
          child: Padding(
              padding: EdgeInsets.all(16.0), child: Logo(title: "Placeholder")),
        ),
      ),
    );
  }
}
