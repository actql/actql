import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';

const record = JSON.parse(readFileSync(new URL('./join-continuation-original-controls.json', import.meta.url)));
const hash = text => createHash('sha256').update(text).digest('hex');
const escape = text => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
function literalParts(source, name) {
  const start = source.indexOf(`fn ${name}(`);
  assert.ok(start >= 0, name);
  const end = source.indexOf('\n}\n', start);
  assert.ok(end > start, name);
  return source.slice(start, end).split('\n').map(line => line.trim())
    .filter(line => line.startsWith('#|')).map(line => line.slice(2));
}

// Transform only declared fixture binding coordinates, never expression/data
// strings or compiler results. Separate producer Stages remain separate even
// when their Values payloads happen to be identical.
function currentTopology(staged, profile) {
  const current = structuredClone(staged);
  const main = current.stages.at(-1);
  const sources = current.stages.slice(0, -1);
  const coordinates = new Map();
  const seeds = sources.map((source, index) => {
    assert.equal(source.steps.length, 1);
    assert.ok(source.steps[0].values);
    const name = `aql_script_seed_${2 + index}`;
    for (const [input, port] of Object.entries(main.inputs)) {
      if (port.result.stage === source.id) coordinates.set(input, name);
    }
    return {values: source.steps[0].values, as: name};
  });
  if (profile === 'specialized') {
    // Four range/seed slots precede this fixed role inventory. Unused roles
    // retain their slots; role selection is not an emitted-Step counter.
    const roles = ['prefiltered', 'output', 'raw', 'filtered', 'derived',
      'order_derived', 'unique', 'sorted', 'taken', 'visible', 'result', 'merged'];
    roles.forEach((role, index) => coordinates.set(`aql_join_${role}`, `aql_join_${role}_${4 + index}`));
  } else {
    coordinates.set('aql_chain_join_2', `aql_chain_join_${2 + seeds.length}`);
    coordinates.set('aql_chain_result_3', `aql_chain_result_${3 + seeds.length}`);
  }
  for (const step of main.steps) {
    for (const key of ['from', 'as']) {
      if (coordinates.has(step[key])) step[key] = coordinates.get(step[key]);
    }
    if (step.join) {
      assert.ok(coordinates.has(step.join.with));
      step.join.with = coordinates.get(step.join.with);
    }
  }
  for (const result of Object.values(main.results)) {
    result.from = coordinates.get(result.from) ?? result.from;
  }
  main.inputs = {};
  main.steps = [...seeds, ...main.steps];
  current.stages = [main];
  return current;
}

for (const control of record.controls) {
  test(`${control.file}: preserve the original complete JOIN continuation`, () => {
    const source = readFileSync(control.file, 'utf8');
    const tests = source.slice(source.indexOf('test "')).split('\n')
      .filter(line => !line.trim().startsWith('#|') && !line.trim().startsWith('//')).join('\n');
    const originalStrings = [...tests.matchAll(/"(?:\\.|[^"\\])*"/g)].map(match => match[0]);
    assert.equal(originalStrings.length, control.originalTestStringsCount);
    assert.equal(hash(originalStrings.join('\n')), control.originalTestStringsSha256);
    const old = literalParts(source, control.helper);
    const current = literalParts(source, control.currentHelper);
    if (old.length === 1) {
      assert.equal(hash(old[0]), control.originalLiteralSha256 ?? control.originalLiteralPartsSha256[0]);
      assert.equal(current.length, 1);
      assert.deepEqual(JSON.parse(current[0]), currentTopology(JSON.parse(old[0]), control.bindingProfile));
      return;
    }
    assert.equal(old.length, 3);
    assert.equal(current.length, 3);
    assert.deepEqual(old.map(hash), control.originalLiteralPartsSha256);
    // Both declarations consume precisely the unchanged original tail/fields
    // arguments. The MoonBit helper changes only from/as binding members.
    const quoted = '"(?:\\\\.|[^"\\\\])*"';
    const pattern = new RegExp(`\\b${escape(control.currentHelper)}\\(\\s*(${quoted})\\s*,\\s*(${quoted})`, 'g');
    const calls = [...source.matchAll(pattern)];
    assert.ok(calls.length > 0);
    for (const match of calls) {
      const tail = JSON.parse(match[1]);
      const fields = JSON.parse(match[2]);
      const remapped = control.bindingProfile === 'specialized'
        ? tail.replaceAll('"from":"aql_join_taken"', '"from":"aql_join_taken_12"')
          .replaceAll('"as":"aql_join_result"', '"as":"aql_join_result_14"')
        : tail.replaceAll('"from":"aql_chain_join_2"', '"from":"aql_chain_join_4"')
          .replaceAll('"as":"aql_chain_result_3"', '"as":"aql_chain_result_5"');
      const staged = JSON.parse(old[0] + tail + old[1] + fields + old[2]);
      const actualControl = JSON.parse(current[0] + remapped + current[1] + fields + current[2]);
      assert.deepEqual(actualControl, currentTopology(staged, control.bindingProfile));
    }
  });
}
