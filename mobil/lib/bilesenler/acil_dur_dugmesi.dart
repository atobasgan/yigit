import 'package:flutter/material.dart';

/// Her zaman görünen ACİL DUR. Tek dokunuş, onay sormaz.
class AcilDurDugmesi extends StatelessWidget {
  const AcilDurDugmesi({super.key, required this.onBasildi, this.etkin = true});

  final VoidCallback onBasildi;
  final bool etkin;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: etkin ? onBasildi : null,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFD50000),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1),
      ),
      icon: const Icon(Icons.pan_tool),
      label: const Text('ACİL DUR'),
    );
  }
}
