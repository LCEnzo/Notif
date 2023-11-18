import 'package:Notif/services/auth.dart' show apiUrl;
import 'package:http/http.dart' as http;

List<String> startChoices = List<String>();

class Strategy {
  late String name;
  late String data;
}

class Link {
  late String name;
  late String url;
  late DateTime last_scraped;
  late String strat;
}

class LinkProvider {
  final String _baseUrl = apiUrl;

  Future<http.Response> createLink(Link link) {
    // Implement POST request to create a Link
  }

  Future<Link> getLink(int id) {
    // Implement GET request to retrieve a Link
  }

  Future<Link> getAllLinks() {
    // Implement GET request to retrieve a Link
  }

  Future<http.Response> updateLink(int id, Link link) {
    // Implement PUT request to update a Link
  }

  Future<http.Response> deleteLink(int id) {
    // Implement DELETE request to delete a Link
  }
}