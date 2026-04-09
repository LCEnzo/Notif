import 'package:flutter/material.dart';
import 'package:notif/screens/shared.dart';
import 'package:notif/services/auth.dart';
import 'package:provider/provider.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => AuthService()),
        ChangeNotifierProvider(
          create: (context) => UserDataService(context.read<AuthService>()),
        ),
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
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 69, 26, 172),
          brightness: Brightness.light,
          primaryContainer: const Color.fromARGB(255, 89, 53, 173),
          primary: const Color.fromARGB(255, 69, 26, 172),
          tertiary: const Color.fromARGB(255, 76, 18, 211),
        ),
        fontFamily: 'Hack Regular',
        textTheme: const TextTheme(
          displayLarge: TextStyle(fontSize: 72),
          titleLarge: TextStyle(fontSize: 36),
          bodyMedium: TextStyle(fontSize: 14),
        ),
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
