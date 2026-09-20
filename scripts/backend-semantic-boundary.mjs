import {readFileSync, readdirSync} from 'node:fs';
import {join} from 'node:path';

// Supplement typed ownership tests with an alias-aware dependency regression
// gate. This is not a parser or a sandbox against malicious plugin code.
const forbiddenReaders = new Map([
  ['pipeline_typing', new Set(['step_at', 'step_count', 'input_count', 'schema_at', 'input_at', 'input_occurrence_at', 'input_occurrence_count', 'input_producer', 'producer_pipeline', 'producer_target', 'producer_projection', 'candidate_keys'])],
  ['lowering_relation', new Set(['pipeline', 'payload', 'kernel_checked', 'inner_join_checked', 'count_group_checked', 'prepare_projection'])],
  ['sourceview_resolution', new Set(['query_acquisition_pipeline'])],
]);

export function semanticBoundaryViolations(source, aliases, ownedProducerBinding = false) {
  let code = source.replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*|"(?:\\.|[^"\\])*"/g, ' ');
  if (ownedProducerBinding) {
    // The sole frontend escape retained in the engine checks exact producer or
    // checked Result-port ownership. Do not exempt this file's operation/schema
    // exploration.
    for (const call of [
      '@lower.pipeline(@lower.bound_preparation(receiver))',
      '@lower.pipeline(@lower.bound_preparation(expected_producer))',
      '@pipeline.input_producer(pipeline, input_index)',
      '@pipeline.producer_pipeline(producer)',
      '@pipeline.producer_target(producer)',
      '@pipeline.producer_pipeline(@results.port_input(port))',
      '@lower.pipeline(@lower.bound_preparation(owner))',
    ]) code = code.replace(call, 'opaque_owner');
  }
  return [...code.matchAll(/@([A-Za-z_][\w]*)\.([A-Za-z_][\w]*)\s*\(/g)]
    .filter(([, alias, reader]) => forbiddenReaders.get(aliases.get(alias))?.has(reader) ||
      (['relation_typing', 'relation_join_shape', 'relation_values'].includes(aliases.get(alias)) && /^[a-z]/.test(reader)))
    .map(([, alias, reader]) => `${alias}.${reader}`);
}

export function checkBackendSemanticBoundary(root = '.') {
  const checked = [];
  function walk(directory, localEngine = false) {
    if (directory === join(
      root, 'src/connectors/duckdb/conformance',
    )) return;
    const entries = readdirSync(directory, {withFileTypes: true});
    if (entries.some(entry => entry.name === 'moon.pkg')) {
      const manifest = readFileSync(join(directory, 'moon.pkg'), 'utf8');
      const aliases = new Map([...manifest.matchAll(/"actql\/actql\/([^"\n]+)"(?:\s+@([\w]+))?/g)]
        .map(([, path, alias]) => [alias ?? path.split('/').at(-1), path]));
      for (const entry of entries) {
        if (!entry.name.endsWith('.mbt') || entry.name.endsWith('test.mbt')) continue;
        const file = join(directory, entry.name);
        const failures = semanticBoundaryViolations(readFileSync(file, 'utf8'), aliases,
          localEngine && entry.name === 'producer_binding.mbt');
        if (failures.length) throw new Error(`${file}: frontend semantic traversal: ${failures.join(', ')}`);
        checked.push(file);
      }
    }
    for (const entry of entries) if (entry.isDirectory()) walk(join(directory, entry.name));
  }
  walk(join(root, 'src/connectors'));
  // Local evaluation and preparation are implementation code even though they
  // share a package with the common completion/ownership facade.
  walk(join(root, 'src/execution_relation'), true);
  for (const packageName of ['physical_host', 'connector_sdk', 'connectors/duckdb/compute', 'connectors/duckdb/driver', 'connectors/reference_compute', 'connectors/reference_compute/driver']) {
    const api = readFileSync(join(root, 'src', packageName, 'pkg.generated.mbti'), 'utf8');
    if (/\bGeneratedSequence\b/.test(api)) throw new Error(`${packageName}: Local preparation in common or non-Local API`);
  }
  return checked.length;
}
