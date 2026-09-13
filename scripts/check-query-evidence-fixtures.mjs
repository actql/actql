import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

// Fixture copies carry full shared bodies into filesystem-free target tests.
// Pins and record expectations are independently fixed, never generated here.
const text = readFileSync('src/query_planning/evidence_bodies_wbtest.mbt', 'utf8');
for (const [index, name] of ['actql-query-acquisition', 'actql-query-process-evidence'].entries()) {
  const match = text.match(new RegExp(`let body${index} = @json\\.parse\\(\\s*("(?:[^"\\\\]|\\\\.)*")\\s*,?\\s*\\)`));
  assert.ok(match, `Missing body${index} fixture`);
  const fixture = JSON.parse(JSON.parse(match[1]));
  const current = JSON.parse(readFileSync(`spec/contracts/${name}.json`, 'utf8'));
  assert.deepEqual(fixture, current, `${name} fixture must match the complete shared body`);
}
console.log('Query evidence fixture bodies match the shared contracts.');
