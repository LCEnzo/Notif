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
      body: const Column(children: [
        Center(
          child: Padding(
              padding: EdgeInsets.all(16.0), child: Logo(title: "Placeholder")),
        ),
        Center(child: NotificationsView())
      ]),
    );
  }
}

class NotificationsView extends StatefulWidget {
  const NotificationsView({super.key});

  @override
  NotificationViewState createState() => NotificationViewState();
}

class NotificationViewState extends State<NotificationsView> {
  @override
  Widget build(BuildContext context) {
    final userDataService =
        Provider.of<UserDataService>(context, listen: false);

    // TODO: implement build
    throw UnimplementedError();
  }
}