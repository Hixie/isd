import 'dart:io';

// TODO: upgrade flutter and re-enable cronet
// import 'package:cronet_http/cronet_http.dart';
import 'package:cupertino_http/cupertino_http.dart';
import 'package:http/http.dart';
import 'package:http/io_client.dart';

Client createClient({
  String? userAgent,
  int? cacheSize,
}) {
  // if (Platform.isAndroid) {
  //   final CronetEngine engine = CronetEngine.build(
  //     cacheMode: cacheSize == null ? CacheMode.disabled : CacheMode.memory,
  //     cacheMaxSize: cacheSize,
  //     userAgent: userAgent,
  //   );
  //   return CronetClient.fromCronetEngine(engine);
  // }
  if (Platform.isIOS || Platform.isMacOS) {
    final URLSessionConfiguration config = URLSessionConfiguration.defaultSessionConfiguration();
    if (cacheSize != null)
      config.cache = URLCache.withCapacity(memoryCapacity: cacheSize, diskCapacity: cacheSize);
    if (userAgent != null)
      config.httpAdditionalHeaders = <String, String>{'User-Agent': userAgent};
    return CupertinoClient.fromSessionConfiguration(config);
  }
  return IOClient(HttpClient()..userAgent = userAgent);
}
