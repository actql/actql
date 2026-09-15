import {readFileSync, readdirSync} from 'node:fs';
import {join} from 'node:path';

// Supplement typed ownership tests with an alias-aware dependency regression
// gate. This is not a parser or a sandbox against malicious plugin code.
const forbiddenReaders = new Map([
  ['pipeline_typing', new Set(['step_at', 'step_count', 'input_count', 'schema_at', 'input_at', 'input_occurrence_at', 'input_occurrence_count'])],
  ['lowering_relation', new Set(['pipeline', 'payload', 'kernel_checked', 'inner_join_checked', 'count_group_checked'])],
  ['sourceview_resolution', new Set(['query_acquisition_pipeline'])],
]);

export function semanticBoundaryViolations(source, aliases) {
  const code = source.replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*|"(?:\\.|[^"\\])*"/g, ' ');
  return [...code.matchAll(/@([A-Za-z_][\w]*)\.([A-Za-z_][\w]*)\s*\(/g)]
    .filter(([, alias, reader]) => forbiddenReaders.get(aliases.get(alias))?.has(reader))
    .map(([, alias, reader]) => `${alias}.${reader}`);
}

export function checkBackendSemanticBoundary(root = '.') {
  const checked = [];
  function walk(directory) {
    const entries = readdirSync(directory, {withFileTypes: true});
    if (entries.some(entry => entry.name === 'moon.pkg')) {
      const manifest = readFileSync(join(directory, 'moon.pkg'), 'utf8');
      const aliases = new Map([...manifest.matchAll(/"actql\/actql\/([^"\n]+)"(?:\s+@([\w]+))?/g)]
        .map(([, path, alias]) => [alias ?? path.split('/').at(-1), path]));
      for (const entry of entries) {
        if (!entry.name.endsWith('.mbt') || entry.name.endsWith('test.mbt')) continue;
        const file = join(directory, entry.name);
        const failures = semanticBoundaryViolations(readFileSync(file, 'utf8'), aliases);
        if (failures.length) throw new Error(`${file}: frontend semantic traversal: ${failures.join(', ')}`);
        checked.push(file);
      }
    }
    for (const entry of entries) if (entry.isDirectory()) walk(join(directory, entry.name));
  }
  walk(join(root, 'src/connectors'));
  for (const packageName of ['physical_host', 'connector_sdk', 'connectors/duckdb/compute', 'connectors/duckdb/driver', 'connectors/reference_compute', 'connectors/reference_compute/driver']) {
    const api = readFileSync(join(root, 'src', packageName, 'pkg.generated.mbti'), 'utf8');
    if (/\bGeneratedSequence\b/.test(api)) throw new Error(`${packageName}: Local preparation in common or non-Local API`);
  }
  return checked.length;
}
