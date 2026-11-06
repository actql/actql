import assert from 'node:assert/strict';
import {readFile, writeFile} from 'node:fs/promises';
import test from 'node:test';
import {boundConstructionActualFixture} from './fixtures/bound-construction-actual.fixture.mjs';

// Actual Common parent, production generated loader, provider runtime and
// physical Site. Only the remote Describe service is an owned TLS fixture.
for (const role of ['source', 'effect']) {
  test(`Salesforce phased ${role} admits large ignored metadata under the original parent budget`, async t => {
    const f = await boundConstructionActualFixture(t);
    const selected = await f.salesforceProfile(role, {largeMetadata: true});
    const exchanges = selected.exchanges();
    const adapter = await f.load(selected);
    assert.equal(adapter.connectorBindings[0].connectorId, selected.value.connectorId);
    assert.equal(selected.exchanges(), exchanges, 'restoration issues no new metadata request');
    assert.equal(f.secretReads(), 0, 'restoration issues no credential grant');
    assert.equal(f.retire(), false, 'live original Site still prevents parent retirement');
    await f.close();
    assert.equal(f.pending(), false);
    assert.equal(f.retire(), true);
  });
}

test('Salesforce phased recovery refuses a changed original body and retains original cleanup', async t => {
  const f = await boundConstructionActualFixture(t);
  const selected = await f.salesforceProfile('source', {largeMetadata: true});
  const path = selected.value.publicationPath;
  const original = JSON.parse(await readFile(path, 'utf8'));
  const encoded = original.evidence.describeBodyBase64[0];
  original.evidence.describeBodyBase64[0] = encoded.slice(0, 4) +
    (encoded[4] === 'A' ? 'B' : 'A') + encoded.slice(5);
  await writeFile(path, JSON.stringify(original));
  const exchanges = selected.exchanges();
  await assert.rejects(f.load(selected), error => {
    const pending = [error], seen = new Set();
    while (pending.length) {
      const next = pending.shift();
      if (!next || typeof next !== 'object' || seen.has(next)) continue;
      seen.add(next);
      if (next.code === 'MoonBitHostFailure') return true;
      pending.push(next.cause, next.primaryFailure);
    }
    return false;
  });
  assert.equal(f.sources.length, 0, 'failed recovery never publishes an adapter');
  assert.equal(selected.exchanges(), exchanges);
  assert.equal(f.secretReads(), 0);
  await f.close();
  assert.equal(f.pending(), false);
  assert.equal(f.retire(), true);
});
