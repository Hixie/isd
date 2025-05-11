export 'package:http/http.dart';
export 'http_stub.dart'
    if (dart.library.io) 'http_io.dart'
    if (dart.library.js_interop) 'http_web.dart';
