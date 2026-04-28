/// Validates that a version string follows semantic versioning (semver) format.
///
/// Returns true for valid formats like "1.0.0", "2.1.3", "0.0.0".
/// Returns false for invalid formats like "1.0", "v1.0.0", "abc", "".
bool isValidVersion(String version) {
  final semverPattern = RegExp(r'^\d+\.\d+\.\d+$');
  return semverPattern.hasMatch(version);
}
