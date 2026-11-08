import assert from 'node:assert/strict';
import test from 'node:test';
import {writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {boundConstructionActualFixture} from './fixtures/bound-construction-actual.fixture.mjs';
import {installedSourceConfigurationReader} from './installed-host-services.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';

// Shared installation components only: no provider, public Run or budget
// replacement. The original Common Resource admits every actual reservation.
test('JSON configuration construction admits a large String on the unchanged original parent', async t => {
  const events = [], f = await boundConstructionActualFixture(t, {capacityEvents: events});
  const limits = f.moon.clientLocalPreparationResourceLimits(f.moon.clientLocalResourcePolicyOriginal());
  assert.equal(limits[4], 536870912n); assert.equal(limits[5], 536870912n);
  const payload = 'A'.repeat(482480), unicode = 'é😀';
  const wire = JSON.stringify({payload, unicode}), bytes = BigInt(Buffer.byteLength(wire));
  const old = checked(f.moon.clientProgramInstalledSourceConstructionCapacity(
    4n * bytes, 12n * bytes, 8n * bytes + 65536n, 0n, 0n, 0n));
  assert(runtimeField(f.moon.clientProgramSerializationCapacityBytes(old), 0) > limits[4],
    'the previous bytes-as-nodes request already exceeds retained capacity');
  const path = join(f.root, 'large-string.json'); await writeFile(path, wire);
  const parse = JSON.parse; let parses = 0, parsing;
  t.mock.method(JSON, 'parse', (input, ...args) => {
    if (input === wire) {parses++; parsing = events.at(-1);}
    return Reflect.apply(parse, JSON, [input, ...args]);
  });
  const reader = installedSourceConfigurationReader(f.services);
  const value = await reader.readJson(path, {maxBytes: Number(bytes)});
  assert(value.payload === payload); assert.equal(value.unicode, unicode);
  assert.equal(parses, 1); assert.equal(parsing.accepted, true);
  assert(parsing.peak < limits[5], 'the full parse is funded before construction');
  const completed = events.at(-1);
  assert.equal(completed.operation, 'clientProgramReconcileInstalledSourceConstruction');
  assert(completed.peak < parsing.peak, 'closed buffer workspace is removed on success');
  const next = join(f.root, 'next.json'); await writeFile(next, '{}');
  assert.deepEqual(await reader.readJson(next, {maxBytes: 2}), {});
  assert(events.at(-1).peak < parsing.peak, 'the next read does not retain the completed peak');
  assert.equal(f.secretReads(), 0);
  await f.close(); assert.equal(f.pending(), false); assert.equal(f.retire(), true);
});

test('JSON configuration construction still refuses genuinely excessive structure before native parse', async t => {
  const events = [], f = await boundConstructionActualFixture(t, {capacityEvents: events});
  const limits = f.moon.clientLocalPreparationResourceLimits(f.moon.clientLocalResourcePolicyOriginal());
  const wire = '[' + '0,'.repeat(599999) + '0]', path = join(f.root, 'many-values.json');
  await writeFile(path, wire);
  const parse = JSON.parse; let parses = 0;
  t.mock.method(JSON, 'parse', (input, ...args) => {
    if (input === wire) parses++;
    return Reflect.apply(parse, JSON, [input, ...args]);
  });
  await assert.rejects(installedSourceConfigurationReader(f.services).readJson(path,
    {maxBytes: Buffer.byteLength(wire)}), {code: 'MoonBitHostFailure'});
  assert.equal(parses, 0);
  const refused = events.at(-1);
  assert.equal(refused.operation, 'clientProgramReserveInstalledSourceConstruction');
  assert.equal(refused.accepted, false);
  assert(refused.retained > limits[4]);
  assert.equal(f.secretReads(), 0);
  await f.close(); assert.equal(f.pending(), false); assert.equal(f.retire(), true);
});
