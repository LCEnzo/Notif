import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  Future<String> getAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.version;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
        centerTitle: true,
        backgroundColor: Theme.of(context).primaryColor,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Notif',
                style: TextStyle(fontSize: 24),
              ),
              const SizedBox(height: 16),
              FutureBuilder<String>(
                future: getAppVersion(),
                builder:
                    (BuildContext context, AsyncSnapshot<String> snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const CircularProgressIndicator();
                  } else {
                    return Text('Version: ${snapshot.data}');
                  }
                },
              ),
              const SizedBox(height: 16),
              const Text(
                'This app monitors the URLs you enter, and provides notifications when the sites '
                'at those URLs change. Notif is a personal project I made for my own needs, and to '
                'expand my knowledge and skills. As such, it\'s provided as is. '
                'No guarantees that it will work or whatever.',
                softWrap: true,
              ),
              const SizedBox(height: 16),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  const Text(
                      'The source code can be found on the following GitHub repository: '),
                  TextButton(
                    onPressed: () async {
                      const url = 'https://github.com/LCEnzo/Notif';
                      if (await canLaunchUrlString(url)) {
                        await launchUrlString(url);
                      } else {
                        throw 'Could not launch $url';
                      }
                    },
                    child: const Text(
                      'https://github.com/LCEnzo/Notif',
                      style: TextStyle(
                        color: Colors.blue,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  const Text(
                      'For any inquiries, you can contact me via github, or send me an email at: '),
                  TextButton(
                    onPressed: () async {
                      final Uri emailLaunchUri = Uri(
                        scheme: 'mailto',
                        path: 'lcenzo@protonmail.ch',
                      );
                      if (await canLaunchUrl(emailLaunchUri)) {
                        await launchUrl(emailLaunchUri);
                      } else {
                        throw 'Could not launch $emailLaunchUri.toString()';
                      }
                    },
                    child: const Text(
                      'lcenzo@protonmail.ch',
                      style: TextStyle(
                        color: Colors.blue,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
