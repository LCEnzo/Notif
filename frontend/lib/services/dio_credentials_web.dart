import 'package:dio/browser.dart';
import 'package:dio/dio.dart';

void configureDioCredentialsImpl(Dio dio) {
  dio.httpClientAdapter = BrowserHttpClientAdapter()..withCredentials = true;
}
