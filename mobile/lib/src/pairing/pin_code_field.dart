import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pegasus_ui/pegasus_ui.dart';

/// Saisie d'un code à 6 chiffres en cases (`xxx-xxx`), comme les apps de
/// vérification. Un champ invisible reçoit la saisie (clavier, collage,
/// remplissage automatique) ; les cases ne font que l'afficher.
class PinCodeField extends StatefulWidget {
  const PinCodeField({
    super.key,
    required this.controller,
    this.focusNode,
    this.onCompleted,
    this.enabled = true,
    this.length = 6,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onCompleted;
  final bool enabled;
  final int length;

  @override
  State<PinCodeField> createState() => _PinCodeFieldState();
}

class _PinCodeFieldState extends State<PinCodeField> {
  late final FocusNode _focus = widget.focusNode ?? FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _focus.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.removeListener(_changed);
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pegasus;
    final code = widget.controller.text;
    final half = widget.length ~/ 2;
    return LayoutBuilder(builder: (context, box) {
      const gap = 6.0;
      const dash = 18.0;
      final size = ((box.maxWidth - dash - gap * (widget.length - 2)) / widget.length).clamp(28.0, 52.0);
      Widget cell(int i) {
        final active = _focus.hasFocus && (i == code.length || (i == widget.length - 1 && code.length == widget.length));
        final filled = i < code.length;
        return Container(
          key: ValueKey('pin-cell-$i'),
          width: size,
          height: size * 1.15,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.surfaceHigh,
            borderRadius: BorderRadius.circular(PegasusRadii.control),
            border: Border.all(color: active ? c.accent2 : (filled ? c.accent : c.line), width: active ? 2 : 1),
            boxShadow: active ? PegasusEffects.neonGlow(c.accent2, Theme.of(context).brightness) : null,
          ),
          child: FittedBox(
            child: Text(
              filled ? code[i] : '',
              style: TextStyle(
                fontFamily: PegasusFonts.mono,
                package: PegasusFonts.package,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: c.text,
              ),
            ),
          ),
        );
      }

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? _focus.requestFocus : null,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Champ réel, invisible : garde le clavier, le collage et l'autofill.
            Positioned.fill(
              child: Opacity(
                opacity: 0,
                child: TextField(
                  key: const ValueKey('code'),
                  controller: widget.controller,
                  focusNode: _focus,
                  enabled: widget.enabled,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  showCursor: false,
                  enableInteractiveSelection: false,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(widget.length),
                  ],
                  onChanged: (v) {
                    if (v.length == widget.length) widget.onCompleted?.call(v);
                  },
                ),
              ),
            ),
            IgnorePointer(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < widget.length; i++) ...[
                    if (i == half)
                      SizedBox(
                        width: dash,
                        child: Center(child: Container(width: 10, height: 2, color: c.textMuted)),
                      )
                    else if (i > 0)
                      const SizedBox(width: gap),
                    cell(i),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}
