import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { legacySchedule, peakRssBytes, checkedSample } from './layout-measurement-support.mjs';
const manifest = JSON.parse(readFileSync(new URL('../benchmarks/local-relation/columnar-experiment.json', import.meta.url)));

test('fixed legacy schedule pairs seven fresh samples and alternates candidate order', () => {
  for (const target of ['native', 'js', 'wasm']) {
    const schedule = legacySchedule(manifest, target, false);
    assert.equal(schedule.length, (target === 'native' ? 12 : 4) * 7 * 3);
    const cases = [...new Set(schedule.map(s => s.case_index))];
    assert.deepEqual(cases, target === 'native' ? [...Array(12).keys()] : [1, 3, 9, 11]);
    for (const index of cases) {
      for (let repeat = 0; repeat < 7; repeat++) {
        const paired = schedule.filter(s => s.case_index === index && s.repeat === repeat);
        assert.deepEqual(paired.map(s => s.candidate), repeat % 2 ? ['C', 'B', 'A'] : ['A', 'B', 'C']);
        assert.equal(new Set(paired.map(s => `${s.rows}/${s.columns}/${s.same_keys}`)).size, 1);
      }
    }
    assert.deepEqual(legacySchedule(manifest, target, true).map(s => [s.case_index, s.repeat, s.candidate]),
      [[0, 0, 'A'], [0, 0, 'B'], [0, 0, 'C']]);
  }
  const invalid = structuredClone(manifest);
  invalid.sampling.measured_repetitions = 6;
  assert.throws(() => legacySchedule(invalid, 'native', false));
});

test('RSS keeps platform units separate and refuses missing ambiguous or invalid records', () => {
  assert.equal(peakRssBytes('  4096  maximum resident set size\n', 'darwin'), 4096);
  assert.equal(peakRssBytes('\tMaximum resident set size (kbytes): 4096\n', 'linux'), 4194304);
  for (const text of ['', '0 maximum resident set size', '9 maximum resident set size\n8 maximum resident set size',
    '9999999999999999999999999 maximum resident set size']) assert.throws(() => peakRssBytes(text, 'darwin'));
  assert.throws(() => peakRssBytes('', 'win32'));
});

test('sample requires exact case candidate and successful independent assertions', () => {
  const expected = { candidate: 'C', rows: 10000, columns: 64, same_keys: false };
  const sample = { kind: 'layout-sample', ...expected, phases_us: [1, 2, 3, 4, 5], end_to_end_us: 16 };
  const success = { type: 'result', file: 'sequence_profile_wbtest.mbt', index: 0, message: '' };
  const output = (...events) => events.map(e => JSON.stringify(e)).join('\n');
  assert.deepEqual(checkedSample(output(sample, success), expected), sample);
  for (const changed of [{ candidate: 'A' }, { rows: 100 }, { same_keys: true }, { phases_us: [] },
    { phases_us: [1, 2, 3, 4, -1] }, { end_to_end_us: 1 }]) {
    assert.throws(() => checkedSample(output({ ...sample, ...changed }, success), expected));
  }
  assert.throws(() => checkedSample(output(sample), expected));
  assert.throws(() => checkedSample(output(sample, success, success), expected));
  assert.throws(() => checkedSample(output(sample, { ...success, message: 'assertion failed' }), expected));
});
