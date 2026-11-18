import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fibpop_mobile/features/offline_play/card_catalog_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads the canonical shared card catalog as a bundled asset', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final catalog = await container.read(offlineCardCatalogProvider.future);

    expect(catalog.cards, hasLength(24));
    expect(
      catalog.cards.fold<int>(0, (total, card) => total + card.copies),
      72,
    );
  });
}
