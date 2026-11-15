import assert from 'node:assert/strict';
import test from 'node:test';
import {writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {boundConstructionActualFixture} from './fixtures/bound-construction-actual.fixture.mjs';
import {installedSourceConfigurationReader} from './installed-host-services.mjs';

// Real shared initialization and original Account runtime, with no budget
// replacement or copied namespace used to inspect private reserve calls.
test('JSON configuration construction admits a large String on the unchanged original parent', async t => {
  const f = await boundConstructionActualFixture(t);
  const limits = f.moon.clientLocalPreparationResourceLimits(f.moon.clientLocalResourcePolicyOriginal());
  assert.equal(limits[4], 536870912n); assert.equal(limits[5], 536870912n);
  const payload = 'A'.repeat(482480), unicode = 'é😀';
  const wire = JSON.stringify({payload, unicode}), path = join(f.root, 'large-string.json');
  await writeFile(path, wire);
  const parse = JSON.parse; let parses = 0;
  t.mock.method(JSON, 'parse', (input, ...args) => {
    if (input === wire) parses++;
    return Reflect.apply(parse, JSON, [input, ...args]);
  });
  const reader = installedSourceConfigurationReader(f.services);
  const value = await reader.readJson(path, {maxBytes: Buffer.byteLength(wire)});
  assert.equal(value.payload, payload); assert.equal(value.unicode, unicode);
  assert.equal(parses, 1);
  const next = join(f.root, 'next.json'); await writeFile(next, '{}');
  assert.deepEqual(await reader.readJson(next, {maxBytes: 2}), {});
  assert.equal(value.payload, payload, 'the retained result survives the next original read');
  assert.equal(f.secretReads(), 0);
  await f.close(); assert.equal(f.pending(), false); assert.equal(f.retire(), true);
});

test('JSON configuration construction still refuses genuinely excessive structure before native parse', async t => {
  const f = await boundConstructionActualFixture(t);
  const wire = '[' + '0,'.repeat(599999) + '0]', path = join(f.root, 'many-values.json');
  await writeFile(path, wire);
  const parse = JSON.parse; let parses = 0;
  t.mock.method(JSON, 'parse', (input, ...args) => {
    if (input === wire) parses++;
    return Reflect.apply(parse, JSON, [input, ...args]);
  });
  await assert.rejects(installedSourceConfigurationReader(f.services).readJson(path,
    {maxBytes: Buffer.byteLength(wire)}), error => error.code === 'MoonBitHostFailure' && error.cause !== undefined);
  assert.equal(parses, 0);
  assert.equal(f.secretReads(), 0);
  await f.close(); assert.equal(f.pending(), false); assert.equal(f.retire(), true);
});

test('completed JSON current failure denies the next constructor on the same parent', async t => {
  const f = await boundConstructionActualFixture(t);
  const reader = installedSourceConfigurationReader(f.services);
  const wire = JSON.stringify({payload: 'A'.repeat(482480)}), path = join(f.root, 'current-json.json');
  await writeFile(path, wire);
  let fault; const parse = JSON.parse;
  t.mock.method(JSON, 'parse', (input, ...args) => {
    const value = Reflect.apply(parse, JSON, [input, ...args]);
    if (input === wire) fault = f.failCurrentBeforeNextConstruction();
    return value;
  });
  await assert.rejects(reader.readJson(path, {maxBytes: Buffer.byteLength(wire)}), error =>
    error.code === 'MoonBitHostFailure' && error.cause !== undefined && fault.calls === 1);
  assert.equal(fault.calls, 1);
  const next = join(f.root, 'next-current.txt'); await writeFile(next, 'x');
  await assert.rejects(reader.readText(next, {maxBytes: 1}), error =>
    error.code === 'MoonBitHostFailure' && error.cause !== undefined);
  assert.equal(f.secretReads(), 0);
  await f.close(); assert.equal(f.pending(), false); assert.equal(f.retire(), true);
});
