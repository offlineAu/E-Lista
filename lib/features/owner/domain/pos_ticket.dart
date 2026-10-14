import 'package:meta/meta.dart';

import '../../../core/money/money.dart';
import '../../../models/payment_method.dart';
import '../../../models/product.dart';

/// One product on an in-progress register sale, with the price/stock snapshot needed to
/// build the ticket without re-reading the catalog for every keystroke.
///
/// Deliberately not [Product]-backed and not the cart's `CartItem`: a walk-in sale has no
/// Firestore document until it is submitted, so this is pure in-memory scratch state.
@immutable
class PosTicketLine {
  const PosTicketLine({
    required this.productId,
    required this.productName,
    required this.unit,
    required this.cashPrice,
    required this.gcashPrice,
    required this.availableStock,
    required this.quantity,
    this.brand,
    this.imageUrl,
  });

  factory PosTicketLine.fromProduct(Product product, {int quantity = 1}) =>
      PosTicketLine(
        productId: product.id,
        productName: product.name,
        unit: product.unit,
        cashPrice: product.cashPrice,
        gcashPrice: product.gcashBasePrice,
        availableStock: product.stockQuantity,
        quantity: quantity,
        brand: product.brand,
        imageUrl: product.imageUrl,
      );

  final String productId;
  final String productName;
  final String? brand;
  final String unit;
  final String? imageUrl;
  final Money cashPrice;
  final Money gcashPrice;
  final int availableStock;
  final int quantity;

  Money unitPrice(PaymentMethod method) => switch (method) {
    PaymentMethod.cash => cashPrice,
    PaymentMethod.gcash => gcashPrice,
  };

  Money lineTotal(PaymentMethod method) => unitPrice(method) * quantity;

  bool get exceedsStock => quantity > availableStock;

  PosTicketLine copyWith({int? quantity}) => PosTicketLine(
    productId: productId,
    productName: productName,
    unit: unit,
    cashPrice: cashPrice,
    gcashPrice: gcashPrice,
    availableStock: availableStock,
    brand: brand,
    imageUrl: imageUrl,
    quantity: quantity ?? this.quantity,
  );
}

/// The sale a cashier is currently building at the register.
///
/// Held only in memory for the lifetime of the checkout screen — nothing here is written
/// to Firestore until `StoreFunctionsService.placeWalkInSale` submits it as a whole.
@immutable
class PosTicket {
  const PosTicket({this.lines = const []});

  final List<PosTicketLine> lines;

  bool get isEmpty => lines.isEmpty;

  int get itemCount =>
      lines.fold(0, (running, line) => running + line.quantity);

  bool get hasStockProblem => lines.any((line) => line.exceedsStock);

  Money subtotal(PaymentMethod method) =>
      Money.sum(lines.map((line) => line.lineTotal(method)));

  bool canCheckout(PaymentMethod method) => !isEmpty && !hasStockProblem;

  /// Adds one unit of [product], or bumps its quantity if it is already on the ticket.
  PosTicket addOrIncrement(Product product) {
    final index = lines.indexWhere((line) => line.productId == product.id);
    if (index == -1) {
      return PosTicket(lines: [...lines, PosTicketLine.fromProduct(product)]);
    }
    final updated = [...lines];
    updated[index] = updated[index].copyWith(
      quantity: updated[index].quantity + 1,
    );
    return PosTicket(lines: updated);
  }

  /// Sets a line's quantity directly, removing it when [quantity] is zero or less.
  PosTicket updateQuantity(String productId, int quantity) {
    if (quantity <= 0) return removeLine(productId);
    return PosTicket(
      lines: [
        for (final line in lines)
          if (line.productId == productId)
            line.copyWith(quantity: quantity)
          else
            line,
      ],
    );
  }

  PosTicket removeLine(String productId) => PosTicket(
    lines: lines.where((line) => line.productId != productId).toList(),
  );
}
