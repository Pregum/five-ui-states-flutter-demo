import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

/// このアプリが AI に使わせる部品の一覧（GenUI のカタログ）。
///
/// 基本の部品（Text・Column・Button など）に、旅の相談用の 2 つを足す。
const travelCatalogId = 'https://pregum.dev/five-state-demo/travel';

Catalog buildTravelCatalog() => BasicCatalogItems.asCatalog().copyWith(
  newItems: [planDay, hotelCard],
  catalogId: travelCatalogId,
  systemPromptFragments: [
    '旅のプランは日ごとに PlanDay を 1 つずつ使い、Column に並べてください。',
    '宿の提案には HotelCard を使ってください。料金は円、評価は 5 点満点です。',
  ],
);

Map<String, Object?> _map(CatalogItemContext c) =>
    (c.data as Map).cast<String, Object?>();

/// 1 日分の旅程。
final planDay = CatalogItem(
  name: 'PlanDay',
  dataSchema: S.object(
    description: '旅程の 1 日分。何日目か、その日のテーマ、予定の箇条書き。',
    properties: {
      'day': S.integer(description: '何日目か（1 始まり）'),
      'title': S.string(description: 'その日のテーマ'),
      'items': S.list(description: 'その日の予定。1 項目 1 文', items: S.string()),
    },
    required: ['day', 'title', 'items'],
  ),
  widgetBuilder: (c) {
    final d = _map(c);
    final items = (d['items'] as List?)?.cast<Object?>() ?? const [];
    final scheme = Theme.of(c.buildContext).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${d['day']} 日目　${d['title'] ?? ''}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 6),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('・$item'),
              ),
          ],
        ),
      ),
    );
  },
);

/// 宿の候補。
final hotelCard = CatalogItem(
  name: 'HotelCard',
  dataSchema: S.object(
    description: '宿の候補 1 件。',
    properties: {
      'name': S.string(description: '宿の名前'),
      'price': S.integer(description: '1 泊の料金（円）'),
      'rating': S.number(description: '評価（5 点満点）'),
      'note': S.string(description: 'おすすめの理由を 1 文で'),
    },
    required: ['name', 'price', 'rating'],
  ),
  widgetBuilder: (c) {
    final d = _map(c);
    final scheme = Theme.of(c.buildContext).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(Icons.hotel_outlined, color: scheme.primary),
        title: Text('${d['name']}'),
        subtitle: Text(
          ['★ ${d['rating']}', if (d['note'] != null) '${d['note']}'].join('　'),
        ),
        trailing: Text(
          '¥${d['price']}〜',
          style: TextStyle(color: scheme.tertiary, fontWeight: FontWeight.bold),
        ),
      ),
    );
  },
);
