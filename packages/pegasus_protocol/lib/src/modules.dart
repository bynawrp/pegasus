/// Module de permission associé à une opération (spec §7).
///
/// Retourne `null` pour les opérations toujours autorisées
/// (`session.*`, `pair.*`, `agent.*`).
String? moduleForOp(String op) {
  final prefix = op.split('.').first;
  return switch (prefix) {
    'input' => 'input',
    'media' || 'audio' => 'media',
    'power' => 'power',
    'apps' || 'url' => 'apps',
    'session' || 'pair' || 'agent' => null,
    _ => prefix,
  };
}
