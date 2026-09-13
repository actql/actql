import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

// Fixture copies carry full shared bodies into filesystem-free target tests.
// Pins and record expectations are independently fixed, never generated here.
for (const path of ['src/query_planning/evidence_bodies_wbtest.mbt', 'src/execution_relation/query_evidence_bodies_wbtest.mbt']) {
  const text = readFileSync(path, 'utf8');
  for (const [index, name] of ['actql-query-acquisition', 'actql-query-process-evidence'].entries()) {
    const match = text.match(new RegExp(`let body${index} = @json\\.parse\\(\\s*("(?:[^"\\\\]|\\\\.)*")\\s*,?\\s*\\)`));
    assert.ok(match, `Missing body${index} fixture in ${path}`);
    const fixture = JSON.parse(JSON.parse(match[1]));
    const current = JSON.parse(readFileSync(`spec/contracts/${name}.json`, 'utf8'));
    assert.deepEqual(fixture, current, `${name} fixture in ${path} must match the complete shared body`);
  }
}
console.log('Query evidence fixture bodies match the shared contracts.');
