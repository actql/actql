import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';

export function renderVocabulary(manifest) {
  const names = manifest.operations;
  if (!Array.isArray(names) || names.length === 0 ||
      names.some(name => typeof name !== 'string' || !/^[a-z][a-z0-9_]*$/u.test(name)) ||
      new Set(names).size !== names.length) {
    throw new Error('Expected a closed, unique operation inventory');
  }
  return `// Generated from spec/manifests/actql-grammar-0.1.json.\n` +
    `// Run node scripts/generate-aql-text-vocabulary.mjs to regenerate.\n\n` +
    `///|\nfn native_operation(name : String) -> Bool {\n  match name {\n` +
    [...names].sort().map((name, i) => `    ${i ? '| ' : ''}${JSON.stringify(name)}`).join('\n') +
    ` => true\n    _ => false\n  }\n}\n`;
}

export function checkVocabulary() {
  const manifest = JSON.parse(readFileSync(new URL('../spec/manifests/actql-grammar-0.1.json', import.meta.url)));
  const path = new URL('../src/aql_text/vocabulary.generated.mbt', import.meta.url);
  if (readFileSync(path, 'utf8') !== renderVocabulary(manifest)) {
    throw new Error('Structural AQL operation vocabulary is stale');
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (process.argv.includes('--check')) {
    checkVocabulary();
  } else {
    const manifest = JSON.parse(readFileSync(new URL('../spec/manifests/actql-grammar-0.1.json', import.meta.url)));
    writeFileSync(new URL('../src/aql_text/vocabulary.generated.mbt', import.meta.url), renderVocabulary(manifest));
  }
}
