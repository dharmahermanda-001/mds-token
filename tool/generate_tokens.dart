import 'dart:convert';
import 'dart:io';

void main() async {
  final inputPath = 'tokens/tokens.json';
  final tokenOutputPath = 'packages/fmi_core/lib/design_tokens/mds_tokens.dart';

  final inputFile = File(inputPath);
  if (!inputFile.existsSync()) {
    print('Token file not found at $inputPath');
    exit(1);
  }

  final jsonStr = await inputFile.readAsString();
  final Map<String, dynamic> tokens = jsonDecode(jsonStr);

  // --- STEP 1: collect categories & keys from tokens.json
  final newCategories = <String, Set<String>>{};
  tokens.forEach((category, values) {
    if (values is Map<String, dynamic> && values.isNotEmpty) {
      newCategories[category] = values.keys.toSet();
    }
  });

  // --- STEP 2: if old file exists, parse it
  final oldFile = File(tokenOutputPath);
  if (oldFile.existsSync()) {
    final oldContent = await oldFile.readAsString();

    final missing = <String, List<String>>{};

    // regex ambil class & getter
    final classRegex = RegExp(r'class _([A-Za-z0-9_]+) \{([\s\S]*?)\}');
    for (final match in classRegex.allMatches(oldContent)) {
      final category = match.group(1)?.toLowerCase();
      final body = match.group(2) ?? '';

      if (category != null) {
        final getters = RegExp(r'(\w+)\s+get\s+(\w+)')
            .allMatches(body)
            .map((m) => m.group(2)!)
            .toSet();

        final existing = newCategories[category] ?? <String>{};
        final diff = getters.difference(existing);

        if (diff.isNotEmpty) {
          missing[category] = diff.toList();
        }
      }
    }

    if (missing.isNotEmpty) {
      print(
          '❌ Validation failed: Some tokens disappeared compared to previous file.');
      missing.forEach((cat, props) {
        print(' - Category $cat: missing ${props.join(', ')}');
      });
      exit(1);
    }
  }

  // --- STEP 3: Generate tokens file ---
  final tokenBuffer = StringBuffer();
  tokenBuffer.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
  tokenBuffer.writeln('import \'package:flutter/material.dart\';\n');
  tokenBuffer.writeln('class MdsTokens {');

  tokens.forEach((category, values) {
    if (values is Map<String, dynamic> && values.isNotEmpty) {
      tokenBuffer.writeln('  static final $category = _${_capitalize(category)}();');
    }
  });
  tokenBuffer.writeln('}\n');

  tokens.forEach((category, values) {
    if (values is Map<String, dynamic> && values.isNotEmpty) {
      tokenBuffer.writeln('class _${_capitalize(category)} {');
      values.forEach((k, v) {
        if (v is Map<String, dynamic> && v.containsKey('value')) {
          final val = v['value'];
          final type = v['type'] ?? '';
          switch (type) {
            case 'color':
              final hex = val is String ? val.replaceAll('#', '') : '000000';
              tokenBuffer.writeln('  Color get $k => Color(0xFF$hex);');
              break;
            case 'dimension':
            case 'borderRadius':
              tokenBuffer.writeln('  double get $k => ${_parseDouble(val)};');
              break;
            default:
              tokenBuffer.writeln('  dynamic get $k => ${_encodeValue(val)};');
          }
        } else {
          tokenBuffer.writeln('  dynamic get $k => ${_encodeValue(v)};');
        }
      });
      tokenBuffer.writeln('}\n');
    }
  });

  final tokenFile = File(tokenOutputPath);
  tokenFile.parent.createSync(recursive: true);
  await tokenFile.writeAsString(tokenBuffer.toString());
  print('✅ Tokens generated to $tokenOutputPath');
}

String _capitalize(String s) => s[0].toUpperCase() + s.substring(1);

double _parseDouble(dynamic val) {
  if (val == null) return 0;
  if (val is num) return val.toDouble();
  if (val is String) {
    return double.tryParse(val.replaceAll('px', '').replaceAll('%', '')) ?? 0;
  }
  return 0;
}

String _encodeValue(dynamic val) {
  if (val is String) return "'$val'";
  if (val is num) return val.toString();
  if (val is bool) return val.toString();
  return jsonEncode(val);
}
