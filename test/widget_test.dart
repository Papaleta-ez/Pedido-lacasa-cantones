import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pedidos_casa_cantones/core/theme.dart';
import 'package:pedidos_casa_cantones/core/widgets.dart';
import 'package:pedidos_casa_cantones/core/models.dart';

void main() {
  test('receta limita disponibilidad por ingrediente más escaso', () {
    final p = Product('p', {
      'active': true,
      'priceCents': 1000,
      'recipe': [
        {'inventoryId': 'a', 'qty': .2},
        {'inventoryId': 'b', 'qty': .5},
      ],
    });
    expect(
      p.available({
        'a': {'stock': 1.0},
        'b': {'stock': 1.5},
      }),
      3,
    );
    expect(
      p.available({
        'a': {'stock': 1.0},
        'b': {'stock': 0},
      }),
      0,
    );
  });
  test('producto sin precio no puede venderse', () {
    expect(
      Product('p', {
        'active': true,
        'priceCents': 0,
        'inventoryId': 'p',
      }).available({
        'p': {'stock': 10},
      }),
      0,
    );
  });
  testWidgets('PIN requiere cuatro dígitos y admite cero inicial', (
    tester,
  ) async {
    int? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: posTheme,
        home: Builder(
          builder: (c) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await keypad(c, 'PIN', pin: true);
              },
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Aceptar'))
          .onPressed,
      isNull,
    );
    for (final key in ['0', '1', '2', '3']) {
      await tester.tap(find.widgetWithText(FilledButton, key));
      await tester.pump();
    }
    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();
    expect(result, 123);
  });
}
