import 'package:flutter/material.dart';
import 'package:notif/screens/shared.dart';
import 'package:notif/services/auth.dart';
import 'package:provider/provider.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => AuthService()),
      ],
      child: const App(),
    ),
  );
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notif',
      theme: ThemeData(
        // Define the default brightness and colors.
        brightness: Brightness.light,
        primaryColor: const Color.fromARGB(255, 69, 26, 172),
        primaryColorLight: const Color.fromARGB(255, 89, 53, 173),
        primaryColorDark: const Color.fromARGB(255, 76, 18, 211),
        // colorScheme: ColorScheme.fromSwatch(primarySwatch: Colors.deepPurple),

        // Define the default font family.
        fontFamily: 'Hack Regular',

        // Define the default `TextTheme`. Use this to specify the default
        // text styling for headlines, titles, bodies of text, and more.
        textTheme: const TextTheme(
          displayLarge: TextStyle(fontSize: 72),
          titleLarge: TextStyle(fontSize: 36),
          bodyMedium: TextStyle(fontSize: 14),
        ),
        // scaffoldBackgroundColor: const Color(0x1e1e1e), // default background color
        // backgroundColor: const Color(0x2e2e2e),
      ),
      home: const LogInPage(),
      routes: {
        '/Home': (context) => const HomePage(),
        '/LogIn': (context) => const LogInPage(),
        '/Register': (context) => const RegisterPage(),
        '/About': (context) => const AboutPage(),
      },
    );
  }
}
