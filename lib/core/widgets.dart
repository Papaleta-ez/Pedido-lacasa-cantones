import 'package:flutter/material.dart';

import 'models.dart';
import 'theme.dart';

class LiveList extends StatelessWidget {
  final Stream<List<Json>> stream;
  final Widget Function(List<Json>) builder;
  const LiveList({super.key, required this.stream, required this.builder});
  @override
  Widget build(BuildContext context) => StreamBuilder<List<Json>>(
    stream: stream,
    builder: (c, s) {
      if (s.hasError) {
        return Center(child: SelectableText('No se pudo leer: ${s.error}'));
      }
      if (!s.hasData) return const Center(child: CircularProgressIndicator());
      return builder(s.data!);
    },
  );
}

Future<String?> askText(
  BuildContext context,
  String title, {
  String initial = '',
  bool secret = false,
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        obscureText: secret,
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, controller.text.trim()),
          child: const Text('Aceptar'),
        ),
      ],
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 250));
  controller.dispose();
  return result;
}

Future<int?> keypad(
  BuildContext context,
  String title, {
  bool pin = false,
  bool monetary = true,
  int initial = 0,
}) => showDialog<int>(
  context: context,
  builder: (c) =>
      NumberPad(title: title, pin: pin, monetary: monetary, initial: initial),
);

class NumberPad extends StatefulWidget {
  final String title;
  final bool pin;
  final bool monetary;
  final int initial;
  const NumberPad({
    super.key,
    required this.title,
    this.pin = false,
    this.monetary = true,
    this.initial = 0,
  });
  @override
  State<NumberPad> createState() => _NumberPadState();
}

class _NumberPadState extends State<NumberPad> {
  late String value = widget.initial == 0 ? '' : widget.initial.toString();
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              widget.pin
                  ? '●' * value.length
                  : widget.monetary
                  ? money(int.tryParse(value) ?? 0)
                  : value.isEmpty
                  ? '0'
                  : value,
              style: const TextStyle(fontSize: 32),
            ),
          ),
          for (final row in ['123', '456', '789', 'C0⌫'])
            Row(
              children: row
                  .split('')
                  .map(
                    (key) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: FilledButton(
                          onPressed: () => setState(() {
                            if (key == 'C') {
                              value = '';
                            } else if (key == '⌫') {
                              if (value.isNotEmpty) {
                                value = value.substring(0, value.length - 1);
                              }
                            } else if (value.length < (widget.pin ? 4 : 9)) {
                              value += key;
                            }
                          }),
                          child: Text(
                            key,
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: widget.pin && value.length != 4
            ? null
            : () => Navigator.pop(context, int.tryParse(value) ?? 0),
        child: const Text('Aceptar'),
      ),
    ],
  );
}

Future<String?> askPin(BuildContext context) async {
  final v = await keypad(context, 'PIN del dueño', pin: true);
  return v?.toString().padLeft(4, '0');
}
