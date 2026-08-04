class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.apiAccessToken,
  });

  factory AppConfig.fromEnvironment() {
    return const AppConfig(
      apiBaseUrl: String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'http://127.0.0.1:8000',
      ),
      apiAccessToken: String.fromEnvironment('API_ACCESS_TOKEN'),
    );
  }

  final String apiBaseUrl;
  final String apiAccessToken;
}
