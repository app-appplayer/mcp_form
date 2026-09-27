/// One problem found in a tool argument: where it is and what is wrong.
class ArgumentIssue {
  const ArgumentIssue(this.path, this.message);

  /// Dotted path from the arguments root, with list indexes in brackets —
  /// `template.defaultSections[0].blocks[2].content`.
  final String path;

  final String message;

  Map<String, String> toJson() => {'path': path, 'message': message};

  @override
  String toString() => '$path $message';
}

/// Checks a JSON value against the JSON Schema subset the `form.*` tool
/// definitions are written in, and reports every problem with its path.
///
/// Supported: `type` (`object`, `array`, `string`, `integer`, `number`,
/// `boolean`), `required`, `properties`, `items`, `enum`, `minimum`,
/// `maximum`, and `$ref` to `#/$defs/<name>` in the schema passed in.
/// Anything else in a schema is description and is not checked.
///
/// `integer` means a JSON integer: `1.0` is refused, because the form
/// models read these fields with an `int` cast.
///
/// `x-discriminator` picks the schema for a value from one of its
/// properties: `{property, mapping: {value: schema}, fallback}`. A value
/// whose property is missing from the mapping is checked against the
/// `fallback` entry, the way the form model reads an unknown block type as
/// a text block.
///
/// All problems are collected rather than stopping at the first, so one
/// answer tells the caller everything to fix.
List<ArgumentIssue> validateArgument(
  Object? value,
  Map<String, dynamic> schema, {
  String path = '',
}) {
  final issues = <ArgumentIssue>[];
  _check(value, schema, path, issues, schema);
  return issues;
}

void _check(
  Object? value,
  Map<String, dynamic> schema,
  String path,
  List<ArgumentIssue> issues,
  Map<String, dynamic> root,
) {
  final ref = schema[r'$ref'];
  if (ref is String) {
    final target = _resolve(ref, root);
    if (target != null) _check(value, target, path, issues, root);
    return;
  }

  final type = schema['type'];
  if (type is String && !_isType(value, type)) {
    issues.add(ArgumentIssue(
        _display(path), 'must be ${_article(type)}, got ${_typeOf(value)}'));
    return;
  }

  final allowed = schema['enum'];
  if (allowed is List && !allowed.contains(value)) {
    issues.add(ArgumentIssue(
        _display(path), 'must be one of ${allowed.join(', ')}, got $value'));
  }

  if (value is num) {
    final min = schema['minimum'];
    final max = schema['maximum'];
    if (min is num && value < min) {
      issues.add(ArgumentIssue(_display(path), 'must be at least $min'));
    }
    if (max is num && value > max) {
      issues.add(ArgumentIssue(_display(path), 'must be at most $max'));
    }
  }

  if (value is Map) {
    final discriminator = schema['x-discriminator'];
    if (discriminator is Map) {
      final branch = _branchFor(value, discriminator);
      if (branch != null) _check(value, branch, path, issues, root);
    }

    final required = schema['required'];
    if (required is List) {
      for (final key in required) {
        if (value[key] == null) {
          issues.add(ArgumentIssue(_join(path, '$key'), 'is required'));
        }
      }
    }

    final properties = schema['properties'];
    if (properties is Map) {
      for (final entry in properties.entries) {
        final child = value[entry.key];
        if (child == null || entry.value is! Map) continue;
        _check(child, (entry.value as Map).cast<String, dynamic>(),
            _join(path, '${entry.key}'), issues, root);
      }
    }
  }

  if (value is List) {
    final items = schema['items'];
    if (items is Map) {
      for (var i = 0; i < value.length; i++) {
        _check(
            value[i], items.cast<String, dynamic>(), '$path[$i]', issues, root);
      }
    }
  }
}

Map<String, dynamic>? _resolve(String ref, Map<String, dynamic> root) {
  const prefix = r'#/$defs/';
  if (!ref.startsWith(prefix)) return null;
  final defs = root[r'$defs'];
  final target = defs is Map ? defs[ref.substring(prefix.length)] : null;
  return target is Map ? target.cast<String, dynamic>() : null;
}

Map<String, dynamic>? _branchFor(
    Map<dynamic, dynamic> value, Map<dynamic, dynamic> discriminator) {
  final property = discriminator['property'];
  final mapping = discriminator['mapping'];
  if (property is! String || mapping is! Map) return null;
  final branch = mapping[value[property]] ?? mapping[discriminator['fallback']];
  return branch is Map ? branch.cast<String, dynamic>() : null;
}

bool _isType(Object? value, String type) => switch (type) {
      'object' => value is Map,
      'array' => value is List,
      'string' => value is String,
      'integer' => value is int,
      'number' => value is num,
      'boolean' => value is bool,
      _ => true,
    };

String _typeOf(Object? value) => switch (value) {
      null => 'null',
      Map() => 'an object',
      List() => 'an array',
      String() => 'a string',
      int() => 'an integer',
      num() => 'a number',
      bool() => 'a boolean',
      _ => value.runtimeType.toString(),
    };

String _article(String type) => switch (type) {
      'object' || 'array' || 'integer' => 'an $type',
      _ => 'a $type',
    };

String _join(String path, String key) => path.isEmpty ? key : '$path.$key';

String _display(String path) => path.isEmpty ? '(arguments)' : path;
