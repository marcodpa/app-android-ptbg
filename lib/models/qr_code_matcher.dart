import 'dart:convert';

import 'models.dart';

const List<String> _qrFieldNames = <String>[
  'CODE_QR',
  'QR_CONTENT',
  'QR_CODE',
  'CD_QR',
  'code_qr',
  'qr_content',
  'qr_code',
  'cd_qr',
  'code',
  'qr',
  'tag',
  'tg',
  'id',
  'equipo',
  'lc',
  'localizacion',
  'localization',
];

String extractQrText(String? raw) {
  var value = (raw ?? '').trim();
  if (value.isEmpty) return '';

  try {
    final decoded = jsonDecode(value);
    if (decoded is Map) {
      for (final key in _qrFieldNames) {
        final v = decoded[key];
        if (v != null && v.toString().trim().isNotEmpty) {
          value = v.toString().trim();
          break;
        }
      }
    }
  } catch (_) {}

  try {
    final uri = Uri.tryParse(value);
    if (uri != null) {
      var matchedQuery = false;
      for (final key in _qrFieldNames) {
        final v = uri.queryParameters[key];
        if (v != null && v.trim().isNotEmpty) {
          value = v.trim();
          matchedQuery = true;
          break;
        }
      }
      if (uri.hasScheme && uri.pathSegments.isNotEmpty) {
        final last = uri.pathSegments.last.trim();
        if (last.isNotEmpty && !matchedQuery) value = last;
      }
    }
  } catch (_) {}

  final lower = value.toLowerCase();
  for (final key in _qrFieldNames) {
    final token = '${key.toLowerCase()}=';
    final idx = lower.lastIndexOf(token);
    if (idx >= 0) {
      value = value.substring(idx + token.length);
      value = value
          .split('&')
          .first
          .split(';')
          .first
          .split(',')
          .first
          .split('\n')
          .first;
      break;
    }
  }

  return value.trim().toUpperCase();
}

Set<String> qrKeys(String? raw) {
  final base = extractQrText(raw);
  final out = <String>{};

  void add(String? v) {
    final s = (v ?? '').trim().toUpperCase();
    if (s.isNotEmpty) out.add(s);
  }

  add(base);
  add(base.replaceAll(' ', ''));
  add(base.replaceAll('-', ''));
  add(base.replaceAll('_', ''));

  final alnum = base.replaceAll(RegExp(r'[^A-Z0-9]'), '');
  add(alnum);

  final digits = base.replaceAll(RegExp(r'[^0-9]'), '');
  if (_canUseNumericFallback(base, digits)) {
    add(digits);
    final n = int.tryParse(digits);
    if (n != null) {
      add('$n');
      add('PTBG-${n.toString().padLeft(3, '0')}');
      add('PTBG${n.toString().padLeft(3, '0')}');
    }
    add('MOT-$digits');
    add('MOT$digits');
  }

  if (base.startsWith('PTBG-')) add(base.replaceFirst('PTBG-', ''));
  if (base.startsWith('PTBG')) add(base.replaceFirst('PTBG', ''));
  if (base.startsWith('MOT-')) {
    final rest = base.replaceFirst('MOT-', '');
    add(rest);
    add('MOT$rest');
  }
  if (base.startsWith('MOT')) {
    final rest =
        base.replaceFirst('MOT', '').replaceFirst(RegExp(r'^[-_]+'), '');
    add(rest);
    if (rest.isNotEmpty) add('MOT-$rest');
  }

  return out;
}

bool _canUseNumericFallback(String base, String digits) {
  if (digits.isEmpty) return false;
  if (RegExp(r'^\d+$').hasMatch(base)) return true;
  return RegExp(r'^(PTBG|LOC)[-_ ]*\d+$').hasMatch(base);
}

List<String> remoteLookupCandidates(String raw) {
  final original = raw.trim().toUpperCase();
  final keys = qrKeys(raw);

  final numeric = keys.where((v) => RegExp(r'^\d+$').hasMatch(v)).toList()
    ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));

  final preferred = <String>[];
  final digits = original.replaceAll(RegExp(r'[^0-9]'), '');
  if (_canUseNumericFallback(original, digits)) {
    final n = int.tryParse(digits);
    if (n != null) preferred.add(n.toString());
  }

  final result = <String>[];
  void add(String v) {
    final clean = v.trim().toUpperCase();
    if (clean.isNotEmpty && !result.contains(clean)) result.add(clean);
  }

  for (final v in preferred) {
    add(v);
  }
  for (final v in numeric) {
    add(v);
  }
  add(original);
  for (final v in keys) {
    add(v);
  }
  return result;
}

bool fieldMatchesQr(Set<String> inputKeys, String? value) {
  if (value == null || value.trim().isEmpty) return false;
  final keys = qrKeys(value);
  return keys.any(inputKeys.contains);
}

bool equipoMatchesQr(Equipo e, Set<String> inputKeys) {
  return fieldMatchesQr(inputKeys, e.qrCode) ||
      fieldMatchesQr(inputKeys, e.qrDisplay) ||
      fieldMatchesQr(inputKeys, e.scada) ||
      fieldMatchesQr(inputKeys, e.localizacion.toString()) ||
      fieldMatchesQr(inputKeys, e.id.toString()) ||
      fieldMatchesQr(inputKeys, e.equipo);
}
