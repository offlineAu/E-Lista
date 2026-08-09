import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config/app_config.dart';
import 'product_catalog_service.dart';

/// [ProductCatalogService] backed by Open Food Facts.
///
/// Chosen because it needs no API key, has open licensing, and carries a usable share of
/// the barcodes on a Philippine sari-sari shelf — instant noodles, soft drinks, biscuits
/// and snacks are well covered. Household and personal-care items often are not, which is
/// why manual entry is a first-class path rather than a fallback.
///
/// Every request is bounded by [AppConfig.catalogTimeout]. An owner scanning a shelf must
/// not wait on a third party: eight seconds, then the manual form.
class OpenFoodFactsCatalogService implements ProductCatalogService {
  OpenFoodFactsCatalogService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? AppConfig.catalogBaseUrl;

  final http.Client _client;
  final String _baseUrl;

  /// Open Food Facts asks that clients identify themselves.
  static const Map<String, String> _headers = {
    'User-Agent': 'E-Lista/1.0 (Philippine sari-sari store app)',
    'Accept': 'application/json',
  };

  /// Only the fields the app actually uses. Requesting the full record would download
  /// several hundred nutrition fields per product over a mobile connection.
  static const String _fields =
      'code,product_name,brands,categories,generic_name,image_front_small_url,'
      'image_url,quantity';

  @override
  String get displayName => 'Open Food Facts';

  @override
  bool get isLive => true;

  @override
  Future<CatalogProduct?> lookupByBarcode(String barcode) async {
    final code = barcode.trim();
    if (code.isEmpty) return null;

    final uri = Uri.parse(
      '$_baseUrl/api/v2/product/$code.json',
    ).replace(queryParameters: {'fields': _fields});

    final json = await _getJson(uri);

    // `status: 0` is the documented "we do not have this barcode" answer. That is a
    // successful call with a negative result, not a failure.
    final status = json['status'];
    if (status == 0 || status == '0') return null;

    final product = json['product'];
    if (product is! Map<String, Object?>) return null;

    final normalised = _normalise(product, fallbackBarcode: code);
    return normalised != null && normalised.isUsable ? normalised : null;
  }

  @override
  Future<List<CatalogProduct>> search(String query, {int limit = 20}) async {
    final term = query.trim();
    if (term.length < 2) return const [];

    final uri = Uri.parse('$_baseUrl/cgi/search.pl').replace(
      queryParameters: {
        'search_terms': term,
        'search_simple': '1',
        'action': 'process',
        'json': '1',
        'page_size': '$limit',
        'fields': _fields,
      },
    );

    final json = await _getJson(uri);
    final products = json['products'];
    if (products is! List) return const [];

    return products
        .whereType<Map<String, Object?>>()
        .map(_normalise)
        .whereType<CatalogProduct>()
        .where((product) => product.isUsable)
        .take(limit)
        .toList();
  }

  Future<Map<String, Object?>> _getJson(Uri uri) async {
    try {
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(AppConfig.catalogTimeout);

      if (response.statusCode == 404) {
        // The v2 endpoint answers 404 for unknown barcodes. Present it as "not found"
        // rather than as an outage, so the UI offers manual entry instead of Retry.
        return const {'status': 0};
      }
      if (response.statusCode != 200) {
        throw CatalogUnavailable(
          cause: 'HTTP ${response.statusCode} from ${uri.host}',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, Object?>) {
        throw const CatalogUnavailable(
          message:
              'The product catalog returned something we could not read. '
              'You can add this product manually.',
        );
      }
      return decoded;
    } on CatalogUnavailable {
      rethrow;
    } on TimeoutException catch (error, stackTrace) {
      throw CatalogUnavailable(
        message:
            'The product catalog is not responding. '
            'You can add this product manually.',
        cause: error,
        stackTrace: stackTrace,
      );
    } catch (error, stackTrace) {
      throw CatalogUnavailable(cause: error, stackTrace: stackTrace);
    }
  }

  /// Turns one Open Food Facts record into a [CatalogProduct].
  ///
  /// Returns `null` for records with no name — the database has plenty of stub entries
  /// that are a barcode and nothing else, and offering one for import would waste the
  /// owner's time.
  CatalogProduct? _normalise(
    Map<String, Object?> raw, {
    String? fallbackBarcode,
  }) {
    final barcode = _string(raw['code']) ?? fallbackBarcode;
    if (barcode == null || barcode.isEmpty) return null;

    final name = _string(raw['product_name']);
    if (name == null) return null;

    return CatalogProduct(
      barcode: barcode,
      name: name,
      brand: _firstOf(_string(raw['brands'])),
      category: _firstOf(_string(raw['categories'])),
      description: _string(raw['generic_name']),
      imageUrl:
          _string(raw['image_front_small_url']) ?? _string(raw['image_url']),
      unit: _string(raw['quantity']),
      source: displayName,
    );
  }

  static String? _string(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Open Food Facts stores brands and categories as comma-separated lists. The first
  /// entry is the useful one; the rest are increasingly generic.
  static String? _firstOf(String? commaSeparated) {
    if (commaSeparated == null) return null;
    final first = commaSeparated.split(',').first.trim();
    return first.isEmpty ? null : first;
  }

  /// Releases the HTTP client. Called when the provider is disposed.
  void dispose() => _client.close();
}
