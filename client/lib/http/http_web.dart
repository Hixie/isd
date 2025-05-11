import 'package:fetch_client/fetch_client.dart';
import 'package:http/http.dart';

Client createClient({
  String? userAgent,
  int? cacheSize,
}) {
  return FetchClient(mode: RequestMode.sameOrigin);
}
