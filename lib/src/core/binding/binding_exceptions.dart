/// Thrown when a binding source is unavailable.
class BindingSourceUnavailableException implements Exception {
  const BindingSourceUnavailableException(this.source);

  final String source;

  @override
  String toString() => 'BindingSourceUnavailableException: $source unavailable';
}

/// Thrown when a binding mapping fails.
class BindingMappingException implements Exception {
  const BindingMappingException(this.message);

  final String message;

  @override
  String toString() => 'BindingMappingException: $message';
}
