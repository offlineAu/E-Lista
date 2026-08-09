import 'dart:convert';

import 'package:e_lista/services/mock_product_catalog_service.dart';
import 'package:e_lista/services/open_food_facts_catalog_service.dart';
import 'package:e_lista/services/product_catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Builds a service whose HTTP layer answers with [handler], so the tests exercise the
/// real parsing and error mapping without touching the network.
OpenFoodFactsCatalogService serviceReturning(
  Future<http.Response> Function(http.Request request) handler,
) {
  return OpenFoodFactsCatalogService(
    client: MockClient(handler),
    baseUrl: 'https://example.test',
  );
}

http.Response jsonResponse(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  group('Open Food Facts — barcode lookup', () {
    test('normalises a record into the app’s own shape', () async {
      final service = serviceReturning(
        (request) async => jsonResponse({
          'status': 1,
          'product': {
            'code': '4800016641107',
            'product_name': 'Piattos Cheese',
            'brands': 'Jack n Jill, Universal Robina',
            'categories': 'Snacks, Crisps, Potato crisps',
            'generic_name': 'Potato crisps',
            'image_front_small_url': 'https://images.test/piattos.jpg',
            'quantity': '40 g',
          },
        }),
      );

      final product = await service.lookupByBarcode('4800016641107');

      expect(product, isNotNull);
      expect(product!.name, 'Piattos Cheese');
      // Only the first entry of the comma-separated list is useful; the rest get vaguer.
      expect(product.brand, 'Jack n Jill');
      expect(product.category, 'Snacks');
      expect(product.imageUrl, 'https://images.test/piattos.jpg');
      expect(product.unit, '40 g');
      expect(product.source, 'Open Food Facts');
    });

    test('carries no price — the owner enters the receipt cost', () {
      // A compile-time guarantee rather than a runtime one: if a price field were ever
      // added to CatalogProduct, this test would stop compiling and force the discussion.
      const product = CatalogProduct(barcode: '1', name: 'x');
      expect(product.toString(), isNot(contains('price')));
    });

    test('an unknown barcode is null, not a failure', () async {
      final service = serviceReturning(
        (request) async => jsonResponse({'status': 0}),
      );
      expect(await service.lookupByBarcode('0000000000000'), isNull);
    });

    test(
      'a 404 is treated as “not in the catalog”, not as an outage',
      () async {
        final service = serviceReturning(
          (request) async => http.Response('not found', 404),
        );
        expect(await service.lookupByBarcode('0000000000000'), isNull);
      },
    );

    test(
      'a record with no name is skipped rather than offered for import',
      () async {
        final service = serviceReturning(
          (request) async => jsonResponse({
            'status': 1,
            'product': {'code': '4800016641107'},
          }),
        );
        expect(await service.lookupByBarcode('4800016641107'), isNull);
      },
    );

    test('a server error surfaces as CatalogUnavailable', () async {
      final service = serviceReturning(
        (request) async => http.Response('boom', 500),
      );
      await expectLater(
        service.lookupByBarcode('4800016641107'),
        throwsA(isA<CatalogUnavailable>()),
      );
    });

    test('unreadable JSON surfaces as CatalogUnavailable', () async {
      final service = serviceReturning(
        (request) async => http.Response('<html>nope</html>', 200),
      );
      await expectLater(
        service.lookupByBarcode('4800016641107'),
        throwsA(isA<CatalogUnavailable>()),
      );
    });

    test(
      'the failure tells the owner they can still add the product by hand',
      () async {
        final service = serviceReturning(
          (request) async => http.Response('boom', 503),
        );
        try {
          await service.lookupByBarcode('4800016641107');
          fail('expected CatalogUnavailable');
        } on CatalogUnavailable catch (failure) {
          expect(failure.message, contains('manually'));
          expect(failure.isRetryable, isTrue);
        }
      },
    );

    test('an empty barcode does not reach the network', () async {
      var called = false;
      final service = serviceReturning((request) async {
        called = true;
        return jsonResponse({'status': 0});
      });

      expect(await service.lookupByBarcode('   '), isNull);
      expect(called, isFalse);
    });

    test('requests only the fields the app uses', () async {
      Uri? requested;
      final service = serviceReturning((request) async {
        requested = request.url;
        return jsonResponse({'status': 0});
      });

      await service.lookupByBarcode('4800016641107');

      expect(requested!.queryParameters['fields'], contains('product_name'));
      expect(
        requested!.queryParameters['fields'],
        isNot(contains('nutriments')),
        reason: 'downloading the full record would be wasteful on mobile data',
      );
    });
  });

  group('Open Food Facts — search', () {
    test('maps a result list', () async {
      final service = serviceReturning(
        (request) async => jsonResponse({
          'products': [
            {'code': '1', 'product_name': 'Coke Sakto', 'brands': 'Coca-Cola'},
            {'code': '2', 'product_name': 'Coke Zero', 'brands': 'Coca-Cola'},
            {'code': '3'}, // No name — dropped.
          ],
        }),
      );

      final results = await service.search('coke');

      expect(results, hasLength(2));
      expect(results.first.name, 'Coke Sakto');
    });

    test('a one-letter query does not reach the network', () async {
      var called = false;
      final service = serviceReturning((request) async {
        called = true;
        return jsonResponse({'products': <Object>[]});
      });

      expect(await service.search('c'), isEmpty);
      expect(called, isFalse);
    });

    test('a missing products array is an empty result, not a crash', () async {
      final service = serviceReturning((request) async => jsonResponse({}));
      expect(await service.search('coke'), isEmpty);
    });
  });

  group('mock catalog', () {
    const service = MockProductCatalogService(latency: Duration.zero);

    test('declares itself as not live so the UI can say so', () {
      expect(service.isLive, isFalse);
    });

    test('finds a sample product by barcode', () async {
      final product = await service.lookupByBarcode('4800016641107');
      expect(product?.name, 'Piattos Cheese');
    });

    test('returns null for a barcode it does not have', () async {
      expect(await service.lookupByBarcode('9999999999999'), isNull);
    });

    test('searches name, brand and category', () async {
      expect(await service.search('lucky'), isNotEmpty);
      expect(await service.search('coca-cola'), isNotEmpty);
      expect(await service.search('canned'), isNotEmpty);
      expect(await service.search('nothing like this'), isEmpty);
    });

    test('every sample row is importable', () {
      for (final product in MockProductCatalogService.sampleProducts) {
        expect(product.isUsable, isTrue, reason: product.barcode);
      }
    });
  });
}
