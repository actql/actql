import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';

const {cases} = JSON.parse(readFileSync(
  new URL('./fixtures/graph-argument-origin-literals.json', import.meta.url), 'utf8'));

for (const fixture of cases) {
  test(`Graph argument independent UTF-8 vector: ${fixture.id}`, () => {
    const bytes = Buffer.from(fixture.source, 'utf8');
    assert.equal(bytes.subarray(fixture.startByte, fixture.endByte).toString('utf8'),
      fixture.token);
    assert.equal(bytes.subarray(0, fixture.startByte).toString('utf8') + fixture.token +
      bytes.subarray(fixture.endByte).toString('utf8'), fixture.source);
    assert.ok(fixture.source.includes('WITH n AS ('));
    if (fixture.id.endsWith('emoji-crlf')) {
      assert.ok(fixture.source.startsWith('/*😀*/\r\n'));
    }
    if (fixture.id.endsWith('decomposed-crlf')) {
      assert.ok(fixture.source.startsWith('/*e\u0301*/\r\n'));
      assert.notEqual(fixture.source.normalize('NFC'), fixture.source);
    }
    // These validate fixture authorship only. Product acceptance must compare
    // the owned parser/lowerer origin to the fixed range; token slicing here
    // never supplies an origin to production diagnostics.
  });
}

const publicPrefix = 'WITH n AS (SELECT 1 AS node_key), g AS (GRAPH ' +
  '(NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) ';
for (const [suffix, start, end, token] of [
  ["components(kind: 'private-kind-value') |> SELECT component_size", 147, 167, "'private-kind-value'"],
  ["components(kind: 'weak', max_output_rows: 0) |> SELECT component_size", 172, 173, '0'],
  ["components(kind: 'weak', max_output_rows: 1.5) |> SELECT component_size", 172, 175, '1.5'],
  ['subgraph(nodes: [1]) |> node_rows() |> SELECT node_key', 146, 149, '[1]'],
  ['subgraph(nodes: {ids: []}) |> node_rows() |> SELECT node_key', 146, 155, '{ids: []}'],
  ['subgraph(nodes: {ids: [], unknown: true}) |> node_rows() |> SELECT node_key', 146, 170, '{ids: [], unknown: true}'],
]) {
  test(`Graph public fixture independent UTF-8 vector: ${suffix}`, () => {
    const source = '/*😀*/\r\n' + publicPrefix + 'FROM g |> ' + suffix;
    assert.equal(Buffer.from(source).subarray(start, end).toString('utf8'), token);
  });
}
