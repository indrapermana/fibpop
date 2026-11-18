import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/card_catalog.dart';

final offlineCardCatalogProvider = FutureProvider<CardCatalog>((ref) async {
  final json = await rootBundle.loadString('../../shared/card_catalog_v1.json');
  final decoded = jsonDecode(json);
  if (decoded is! Map) {
    throw const FormatException('Card catalog must be an object');
  }
  return CardCatalog.fromJson(decoded.cast<String, Object?>());
});
