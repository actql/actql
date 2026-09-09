import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { walk, programs, validateCases, validateExamples } from './document-validation.mjs';
const read = path => JSON.parse(readFileSync(path, 'utf8'));
const discovered = new Map();
for (const path of ['README.md', ...walk('docs'), ...walk('spec/product-decisions')]) {
  if (!/\.(md|aql)$/.test(path)) continue;
  for (const program of programs(readFileSync(path, 'utf8'), path)) {
    const key = `${path}#${program.id}`;
    assert.ok(!discovered.has(key), `Duplicate example ${key}`);
    discovered.set(key, program);
  }
}
validateExamples(discovered, read('spec/actql-doc-examples.json').documents);
const count = validateCases(read('spec/product-decisions/acceptance-cases.json'), read('spec/product-decisions/traceability.json'));
console.log(JSON.stringify({ parsed_programs: discovered.size, acceptance_cases: count, semantic_check: 'not_run', runtime_conformance: false }));
