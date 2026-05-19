import 'package:flutter_test/flutter_test.dart';
import 'package:tropia/features/cart/models/cart_item_model.dart';

// ── Helper ────────────────────────────────────────────────────────────────────

CartItemModel _makeItem({
  int unitPrice = 80000,
  int originalPrice = 100000,
  int quantity = 2,
  List<CartAttribute> attributes = const [],
  bool isSelected = true,
}) =>
    CartItemModel(
      id: 'item-1',
      variantId: 'var-1',
      productId: 'prod-1',
      productName: 'Gạo ST25',
      shopId: 'shop-1',
      shopName: 'Lạc Yên Foods',
      unitPrice: unitPrice,
      originalPrice: originalPrice,
      quantity: quantity,
      attributes: attributes,
      isSelected: isSelected,
    );

void main() {
  // ── CartAttribute ─────────────────────────────────────────────────────────

  group('CartAttribute', () {
    test('stores typeName and value', () {
      const attr = CartAttribute(typeName: 'Size', value: 'L');
      expect(attr.typeName, 'Size');
      expect(attr.value, 'L');
      expect(attr.colorHex, isNull);
    });

    test('stores optional colorHex', () {
      const attr = CartAttribute(typeName: 'Màu', value: 'Đỏ', colorHex: '#FF0000');
      expect(attr.colorHex, '#FF0000');
    });

    group('fromJson', () {
      test('parses camelCase keys', () {
        final attr = CartAttribute.fromJson({'typeName': 'Khối lượng', 'value': '1kg'});
        expect(attr.typeName, 'Khối lượng');
        expect(attr.value, '1kg');
      });

      test('parses snake_case keys', () {
        final attr = CartAttribute.fromJson({'type_name': 'Size', 'value': 'M'});
        expect(attr.typeName, 'Size');
      });

      test('parses colorHex from camelCase', () {
        final attr = CartAttribute.fromJson(
            {'typeName': 'Màu', 'value': 'Xanh', 'colorHex': '#0000FF'});
        expect(attr.colorHex, '#0000FF');
      });

      test('parses colorHex from snake_case', () {
        final attr = CartAttribute.fromJson(
            {'type_name': 'Màu', 'value': 'Xanh', 'color_hex': '#00FF00'});
        expect(attr.colorHex, '#00FF00');
      });

      test('defaults typeName and value to empty string when absent', () {
        final attr = CartAttribute.fromJson({});
        expect(attr.typeName, '');
        expect(attr.value, '');
      });
    });
  });

  // ── CartItemModel computed properties ─────────────────────────────────────

  group('CartItemModel.subtotal', () {
    test('equals unitPrice * quantity', () {
      expect(_makeItem(unitPrice: 85000, quantity: 3).subtotal, 255000);
    });

    test('is zero when quantity is 0', () {
      expect(_makeItem(unitPrice: 85000, quantity: 0).subtotal, 0);
    });
  });

  group('CartItemModel.saving', () {
    test('equals (originalPrice - unitPrice) * quantity', () {
      final item = _makeItem(unitPrice: 80000, originalPrice: 100000, quantity: 2);
      expect(item.saving, 40000);
    });

    test('is zero when prices are equal', () {
      expect(_makeItem(unitPrice: 50000, originalPrice: 50000, quantity: 3).saving, 0);
    });
  });

  group('CartItemModel.hasDiscount', () {
    test('true when unitPrice < originalPrice', () {
      expect(_makeItem(unitPrice: 80000, originalPrice: 100000).hasDiscount, isTrue);
    });

    test('false when prices are equal', () {
      expect(_makeItem(unitPrice: 50000, originalPrice: 50000).hasDiscount, isFalse);
    });
  });

  group('CartItemModel.discountPercent', () {
    test('calculates integer percentage correctly', () {
      // (100000 - 80000) * 100 ~/ 100000 = 20
      expect(_makeItem(unitPrice: 80000, originalPrice: 100000).discountPercent, 20);
    });

    test('returns 0 when originalPrice is 0', () {
      expect(_makeItem(unitPrice: 0, originalPrice: 0).discountPercent, 0);
    });

    test('returns 0 when no discount', () {
      expect(_makeItem(unitPrice: 50000, originalPrice: 50000).discountPercent, 0);
    });
  });

  group('CartItemModel.attributeLabel', () {
    test('joins values with " · "', () {
      final item = _makeItem(attributes: [
        const CartAttribute(typeName: 'Màu', value: 'Đỏ'),
        const CartAttribute(typeName: 'Size', value: 'L'),
        const CartAttribute(typeName: 'Khối lượng', value: '1kg'),
      ]);
      expect(item.attributeLabel, 'Đỏ · L · 1kg');
    });

    test('is empty string when no attributes', () {
      expect(_makeItem(attributes: []).attributeLabel, '');
    });

    test('single attribute has no separator', () {
      final item = _makeItem(
          attributes: [const CartAttribute(typeName: 'Size', value: 'M')]);
      expect(item.attributeLabel, 'M');
    });
  });

  // ── CartItemModel.fromJson ────────────────────────────────────────────────

  group('CartItemModel.fromJson', () {
    final baseJson = {
      'id': 'ci-json',
      'variant_id': 'var-json',
      'product_id': 'prod-json',
      'product_name': 'Trứng gà ta',
      'shop_id': 'shop-json',
      'shop_name': 'Tropia Market',
      'unit_price': 38000,
      'original_price': 45000,
      'quantity': 2,
      'attributes': [
        {'typeName': 'Loại', 'value': 'Ta'}
      ],
    };

    test('parses all fields correctly', () {
      final item = CartItemModel.fromJson(baseJson);
      expect(item.id, 'ci-json');
      expect(item.variantId, 'var-json');
      expect(item.productName, 'Trứng gà ta');
      expect(item.unitPrice, 38000);
      expect(item.originalPrice, 45000);
      expect(item.quantity, 2);
      expect(item.attributes.length, 1);
    });

    test('isSelected defaults to true when absent', () {
      expect(CartItemModel.fromJson(baseJson).isSelected, isTrue);
    });

    test('parses isSelected = false from json', () {
      final item = CartItemModel.fromJson({...baseJson, 'is_selected': false});
      expect(item.isSelected, isFalse);
    });

    test('handles null attributes gracefully', () {
      final item = CartItemModel.fromJson({...baseJson, 'attributes': null});
      expect(item.attributes, isEmpty);
    });

    test('accepts numeric prices as doubles', () {
      final item = CartItemModel.fromJson(
          {...baseJson, 'unit_price': 38000.0, 'original_price': 45000.0});
      expect(item.unitPrice, 38000);
      expect(item.originalPrice, 45000);
    });

    test('imageUrl is null when absent', () {
      expect(CartItemModel.fromJson(baseJson).imageUrl, isNull);
    });

    test('parses imageUrl when present', () {
      final item = CartItemModel.fromJson(
          {...baseJson, 'image_url': 'https://cdn.tropia.vn/egg.jpg'});
      expect(item.imageUrl, 'https://cdn.tropia.vn/egg.jpg');
    });
  });

  // ── CartSummary ───────────────────────────────────────────────────────────

  group('CartSummary', () {
    test('stores all fields', () {
      const s = CartSummary(totalItems: 3, totalPrice: 150000, totalSaving: 20000);
      expect(s.totalItems, 3);
      expect(s.totalPrice, 150000);
      expect(s.totalSaving, 20000);
    });

    group('fromJson', () {
      test('parses all fields', () {
        final s = CartSummary.fromJson(
            {'totalItems': 5, 'totalPrice': 300000, 'totalSaving': 50000});
        expect(s.totalItems, 5);
        expect(s.totalPrice, 300000);
        expect(s.totalSaving, 50000);
      });

      test('handles double values', () {
        final s = CartSummary.fromJson(
            {'totalItems': 2.0, 'totalPrice': 100000.0, 'totalSaving': 0.0});
        expect(s.totalItems, 2);
        expect(s.totalPrice, 100000);
      });
    });
  });
}
