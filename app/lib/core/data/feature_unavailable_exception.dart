class FeatureUnavailableException implements Exception {
  const FeatureUnavailableException(this.feature);

  final String feature;

  @override
  String toString() => 'FeatureUnavailableException: $feature';
}
