import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Mapping from v4 short keys to canonical long keys.
const _v4Decode = {
  'v': 'version',
  'n': 'name',
  'u': 'url',
  'lu': 'library_uuid',
  'ek': 'ed25519_public_key',
  'xk': 'x25519_public_key',
  'ru': 'relay_url',
  'mi': 'mailbox_id',
  'wt': 'relay_write_token',
};

/// Builds the invite payload Map using v4 short keys.
///
/// The returned Map uses compact key names and `"v": 4`.
Map<String, dynamic> buildInvitePayload({
  required String name,
  required String url,
  String? libraryUuid,
  String? ed25519PublicKey,
  String? x25519PublicKey,
  String? relayUrl,
  String? mailboxId,
  String? relayWriteToken,
}) {
  return {
    'v': 4,
    'n': name,
    'u': url,
    if (libraryUuid != null) 'lu': libraryUuid,
    if (ed25519PublicKey != null) 'ek': ed25519PublicKey,
    if (x25519PublicKey != null) 'xk': x25519PublicKey,
    if (relayUrl != null) 'ru': relayUrl,
    if (mailboxId != null) 'mi': mailboxId,
    if (relayWriteToken != null) 'wt': relayWriteToken,
  };
}

/// Encodes an invite payload Map into a full invite URL (long format).
///
/// Uses the payload's relay_url as the hub base, falling back to
/// [hubBaseUrl]. The payload is passed as `?d=` query parameter.
///
/// This is the synchronous fallback when the hub is unreachable.
String encodeInviteLink(Map<String, dynamic> payload, {required String hubBaseUrl}) {
  // Read relay_url: short key "ru" (v4) or long key "relay_url" (v3)
  final hubBase = (payload['ru'] ?? payload['relay_url'] ?? hubBaseUrl) as String;
  final json = jsonEncode(payload);
  // Strip '=' padding: it confuses URL detection in messaging apps
  // (= is the key/value separator in query strings).
  // The decoder uses base64Url.normalize() which restores padding.
  final encoded = base64Url.encode(utf8.encode(json)).replaceAll('=', '');
  return '$hubBase/invite?d=$encoded';
}

/// Creates a short invite link by posting the payload to the hub.
///
/// POSTs to `$hubBaseUrl/api/invite` and returns the short URL (~50 chars).
/// Falls back to the long base64 format if the hub is unreachable.
Future<String> createInviteLink(
  Map<String, dynamic> payload, {
  required String hubBaseUrl,
}) async {
  final hubBase = (payload['ru'] ?? payload['relay_url'] ?? hubBaseUrl) as String;
  final jsonPayload = jsonEncode(payload);

  try {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ));
    final response = await dio.post(
      '$hubBase/api/invite',
      data: {'payload': jsonPayload},
      options: Options(contentType: Headers.jsonContentType),
    );

    if (response.statusCode == 201 && response.data is Map) {
      final url = response.data['url'] as String?;
      if (url != null && url.isNotEmpty) {
        return url;
      }
    }
  } catch (e) {
    debugPrint('createInviteLink: hub unreachable, using long format: $e');
  }

  // Fallback: return long base64 link
  return encodeInviteLink(payload, hubBaseUrl: hubBaseUrl);
}

/// Normalizes an invite payload to canonical (long) keys.
///
/// Accepts both v3 (long keys) and v4 (short keys).
/// Returns a Map with the canonical long key names so callers
/// don't need to know which version they received.
Map<String, dynamic> normalizeInvitePayload(Map<String, dynamic> raw) {
  // Detect version: v4 uses short key "v", v3 uses "version"
  final version = raw['v'] ?? raw['version'];

  if (version == 4) {
    // Expand short keys to canonical long keys
    final result = <String, dynamic>{};
    for (final entry in raw.entries) {
      final longKey = _v4Decode[entry.key];
      if (longKey != null) {
        result[longKey] = entry.value;
      } else {
        // Pass through unknown keys as-is (future-proof)
        result[entry.key] = entry.value;
      }
    }
    return result;
  }

  // v3 or older: already using long keys
  return raw;
}
