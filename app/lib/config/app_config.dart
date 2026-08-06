class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
  });

  factory AppConfig.fromEnvironment() {
    return const AppConfig(
      apiBaseUrl: String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'http://127.0.0.1:8000',
      ),
    );
  }

  final String apiBaseUrl;
}
