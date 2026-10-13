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
