import assert from 'node:assert/strict';
import test from 'node:test';
import childProcess from 'node:child_process';
import {inUnnestLiteralArraySuccesses as successes, inUnnestLiteralArrayRefusals as refusals}
  from './fixtures/in-unnest-literal-array-source-input.mjs';
import {selectReleaseSourcefreeQueryCases, releaseSourcefreeSuccessNames, releaseSourcefreeRefusalNames}
  from './release-sourcefree-query-cases.mjs';
import {guardReleaseSourcefreeIo} from './fixtures/release-sourcefree-io.mjs';

test('release selection preserves four independent inputs and all six refusals', () => {
  const before = JSON.stringify({successes, refusals});
  const selected = selectReleaseSourcefreeQueryCases();
  assert.deepEqual(selected.successes.map(value => value.name), [
    'in-unnest-literal-array-general-element', 'in-unnest-literal-array-array-field',
    'in-unnest-literal-array-conditional-array', 'in-unnest-literal-array-lazy-array-branch']);
  assert.equal(selected.refusals.length, 6);
  for (const value of selected.successes) {
    assert.equal(value, successes.find(item => item.name === value.name));
    assert.deepEqual(value.expected, value.name.endsWith('general-element') ? [{found: true}] : [{included: true}]);
    assert.deepEqual(value.columns, [{name: value.name.endsWith('general-element') ? 'found' : 'included',
      contract: {type: 'boolean', nullable: false}}]);
  }
  assert.ok(!selected.successes.some(value => value.name.endsWith('where-source-once')));
  assert.equal(successes.find(value => value.name.endsWith('where-source-once')).sourceReadCount, 1);
  assert.equal(JSON.stringify({successes, refusals}), before);
});
for (const name of releaseSourcefreeSuccessNames) test(`missing case refuses: ${name}`, () => {
  assert.throws(() => selectReleaseSourcefreeQueryCases({successes: successes.filter(value => value.name !== name)}));
});
test('duplicate and Source-bearing selected cases refuse', () => {
  const item = successes[0];
  assert.throws(() => selectReleaseSourcefreeQueryCases({successes: [...successes, item]}));
  for (const property of ['sourceReadCount', 'sourceReadSessionCount']) {
    assert.throws(() => selectReleaseSourcefreeQueryCases({successes: successes.map(value =>
      value === item ? {...value, [property]: 1} : value)}));
  }
});
test('missing, duplicate, reordered and extra refusal inventory refuse', () => {
  for (const changed of [refusals.slice(1), [...refusals, refusals[0]], [...refusals].reverse(),
    [...refusals, {name: 'unreviewed-refusal'}]]) {
    assert.throws(() => selectReleaseSourcefreeQueryCases({refusals: changed}));
  }
  assert.deepEqual(selectReleaseSourcefreeQueryCases().refusals.map(value => value.name), releaseSourcefreeRefusalNames);
});
test('provider guard refuses observable process/fetch/secret attempts and restores hooks', async () => {
  const before = childProcess.spawn, beforeFetch = globalThis.fetch;
  const io = guardReleaseSourcefreeIo();
  try {
    assert.throws(() => childProcess.spawn('must-not-start'), /UnexpectedSourcefreeProviderProcess/u);
    assert.throws(() => globalThis.fetch('https://provider.invalid/'), /UnexpectedSourcefreeProviderFetch/u);
    assert.throws(() => io.resolveSourceSecret(), /UnexpectedSourcefreeSecretResolution/u);
    assert.deepEqual(io.snapshot(), {forbiddenProcesses: 1, forbiddenFetches: 1, sourceSecrets: 1});
    assert.throws(() => io.assertQuiet());
  } finally {io.close();}
  assert.equal(childProcess.spawn, before);
  assert.equal(globalThis.fetch, beforeFetch);
});
test('provider guard permits only one exact fixture HTTPS origin', () => {
  const io = guardReleaseSourcefreeIo();
  try {
    assert.throws(() => io.allowTransportOrigin('https://provider.invalid'));
    io.allowTransportOrigin('https://127.0.0.1:9443');
    assert.throws(() => io.allowTransportOrigin('https://127.0.0.1:444'));
    assert.throws(() => globalThis.fetch('https://127.0.0.1:444/'));
  } finally {io.close();}
});
