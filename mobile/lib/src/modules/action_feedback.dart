import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pegasus_link/pegasus_link.dart';

/// Envoie une requête et affiche le résultat (« retour d'état ») en bas d'écran.
Future<bool> runAction(BuildContext context, Future<Object?> Function() action, {String? success}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  HapticFeedback.selectionClick();
  try {
    await action();
    if (success != null) _show(messenger, success);
    return true;
  } catch (e) {
    _show(messenger, describeActionError(e), error: true);
    return false;
  }
}

String describeActionError(Object e) => switch (e) {
      RequestFailedException(:final error) when error.message.isNotEmpty => error.message,
      RequestFailedException() => 'Action refusée par le PC',
      ConnectionClosedException() => 'PC non connecté',
      _ => 'Le PC ne répond pas',
    };

void _show(ScaffoldMessengerState? messenger, String text, {bool error = false}) {
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
      duration: Duration(seconds: error ? 4 : 2),
    ));
}
