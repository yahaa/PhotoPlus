/// HTTP client for the NAS Go API. TODO: auth headers, upload, timeline.
class ApiClient {
  ApiClient({this.baseUrl = ''});
  final String baseUrl;
}
