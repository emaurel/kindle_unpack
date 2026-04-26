/// Thrown when record 0's headers (PalmDOC / MOBI) cannot be parsed.
class HeaderException implements Exception {
  HeaderException(this.message);

  final String message;

  @override
  String toString() => 'HeaderException: $message';
}
