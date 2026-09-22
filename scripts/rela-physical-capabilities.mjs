// Keep this parser tied to the physical compiler branches, not the
// differential evidence manifest. Unknown branches must be classified.
export function registeredDuckdbRelAOperations(
  {takeCompiler, nativeQuery, fixedQuery},
  fail,
) {
  const takeBodies = takeCompiler.split('match @lower.kernel_body(kernel) {')[1]
    ?.split('\n    stages.push(')[0] ?? '';
  const operations = new Set();
  const bodyOperations = new Map([
    ['Limit', 'take'], ['Select', 'select'], ['StableSort', 'sort'],
    ['DistinctRows', 'distinct'], ['DedupeRows', 'dedupe_rows'],
  ]);
  const copyOnlyBodies = new Set(['SnapshotMap', 'OrderedBindings', 'Field']);
  for (const match of takeBodies.matchAll(/@lower\.([A-Z][A-Za-z0-9_]*)/gu)) {
    const body = match[1];
    if (copyOnlyBodies.has(body)) continue;
    const operation = bodyOperations.get(body);
    if (!operation) fail(`unclassified DuckDB take compiler body: ${body}`);
    else operations.add(operation);
  }
  for (const [body, operation] of [['Filter', 'filter'], ['Select', 'select']]) {
    if (!nativeQuery.includes(`@lower.${body}(`)) {
      fail(`missing DuckDB fixed ${operation} compiler branch`);
    } else {
      operations.add(operation);
    }
  }
  const fixedVariants = fixedQuery.match(/pub enum FixedQuery \{([^}]+)\}/u)?.[1] ?? '';
  const fixedOperations = new Map([
    ['FilterSelect', null], ['CountGroup', 'group'],
    ['InnerJoin', 'join'],
  ]);
  for (const match of fixedVariants.matchAll(/^\s*([A-Z][A-Za-z0-9_]*)\(/gmu)) {
    if (!fixedOperations.has(match[1])) {
      fail(`unclassified DuckDB fixed query variant: ${match[1]}`);
    } else if (fixedOperations.get(match[1])) {
      operations.add(fixedOperations.get(match[1]));
    }
  }
  if (!fixedVariants.includes('CountGroup(') ||
    !fixedVariants.includes('InnerJoin(') || takeBodies.length === 0) {
    fail('DuckDB physical capability inventory could not be derived');
  }
  return operations;
}
