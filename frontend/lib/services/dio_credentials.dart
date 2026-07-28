import 'package:dio/dio.dart';
import 'package:notif/services/dio_credentials_stub.dart'
    if (dart.library.js_interop) 'package:notif/services/dio_credentials_web.dart';

void configureDioCredentials(Dio dio) {
  configureDioCredentialsImpl(dio);
}
