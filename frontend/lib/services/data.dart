import 'package:http/http.dart' as http;
import 'package:notif/services/api_client.dart';
import 'package:notif/services/app_settings.dart';

final List<String> startChoices = <String>[];

class Strategy {
  Strategy({required this.name, required this.data});

  final String name;
  final String data;
}

class Link {
  Link({
    required this.name,
    required this.url,
    this.lastScraped,
    required this.strategy,
  });

  final String name;
  final String url;
  final DateTime? lastScraped;
  final String strategy;
}

class LinkProvider {
  AppSettingsController? _settings;

  void updateSettings(AppSettingsController? settings) {
    _settings = settings;
  }

  Future<http.Response> createLink(Link link) {
    throw UnimplementedError(
      'LinkProvider.createLink is not wired up for ${resolveUrls('', _settings).first} yet.',
    );
  }

  Future<Link> getLink(int id) {
    throw UnimplementedError(
      'LinkProvider.getLink is not wired up for ${resolveUrls('', _settings).first} yet.',
    );
  }

  Future<List<Link>> getAllLinks() {
    throw UnimplementedError(
      'LinkProvider.getAllLinks is not wired up for ${resolveUrls('', _settings).first} yet.',
    );
  }

  Future<http.Response> updateLink(int id, Link link) {
    throw UnimplementedError(
      'LinkProvider.updateLink is not wired up for ${resolveUrls('', _settings).first} yet.',
    );
  }

  Future<http.Response> deleteLink(int id) {
    throw UnimplementedError(
      'LinkProvider.deleteLink is not wired up for ${resolveUrls('', _settings).first} yet.',
    );
  }
}
