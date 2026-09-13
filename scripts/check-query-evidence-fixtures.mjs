import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

// Fixture copies carry full shared bodies into filesystem-free target tests.
// Pins and record expectations are independently fixed, never generated here.
for (const path of ['src/query_planning/evidence_bodies_wbtest.mbt', 'src/query_integration/query_evidence_bodies_wbtest.mbt']) {
  const text = readFileSync(path, 'utf8');
  for (const [index, name] of ['actql-query-acquisition', 'actql-query-process-evidence'].entries()) {
    const match = text.match(new RegExp(`let body${index} = @json\\.parse\\(\\s*("(?:[^"\\\\]|\\\\.)*")\\s*,?\\s*\\)`));
    assert.ok(match, `Missing body${index} fixture in ${path}`);
    const fixture = JSON.parse(JSON.parse(match[1]));
    const current = JSON.parse(readFileSync(`spec/contracts/${name}.json`, 'utf8'));
    assert.deepEqual(fixture, current, `${name} fixture in ${path} must match the complete shared body`);
  }
}
{
  const path = 'src/query_integration/query_two_receipt_body_wbtest.mbt';
  const text = readFileSync(path, 'utf8');
  const match = text.match(/@json\.parse\(\s*("(?:[^"\\]|\\.)*")\s*,?\s*\)/);
  assert.ok(match, `Missing two-receipt body fixture in ${path}`);
  assert.deepEqual(JSON.parse(JSON.parse(match[1])),
    JSON.parse(readFileSync('spec/contracts/actql-query-two-receipt.json', 'utf8')));
}
console.log('Query evidence fixture bodies match the shared contracts.');
