import assert from 'node:assert/strict';
import test from 'node:test';
import childProcess from 'node:child_process';
import {readFileSync} from 'node:fs';
import {dirname, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {inUnnestLiteralArraySuccesses as successes, inUnnestLiteralArrayRefusals as combinedRefusals}
  from './fixtures/in-unnest-literal-array-source-input.mjs';
import {selectReleaseSourcefreeQueryCases, releaseSourcefreeSuccessNames, releaseSourcefreeRefusalNames,
  selectInstalledSourcefreeQuerySuite, releaseSourcefreeFixturePaths, sourcefreeSuiteRequiresReread}
  from './release-sourcefree-query-cases.mjs';
import {sequenceSourceSuccesses, sequenceSourceRefusals} from './fixtures/sequence-source-input.mjs';
import {guardReleaseSourcefreeIo} from './fixtures/release-sourcefree-io.mjs';
import {sourcefreeFixtureAuthorization} from './fixtures/release-sourcefree-authorization.mjs';

const refusals = combinedRefusals.filter(value =>
  value.name.startsWith('in-unnest-literal-array-'));

test('closed installed suites retain the old default and the complete original Sequence cohort', () => {
  assert.deepEqual(selectInstalledSourcefreeQuerySuite(), selectReleaseSourcefreeQueryCases());
  assert.deepEqual(selectInstalledSourcefreeQuerySuite('sequence'), {
    successes: sequenceSourceSuccesses, refusals: sequenceSourceRefusals});
  for (const suite of ['unknown', '--sequence-only', '']) {
    assert.throws(() => selectInstalledSourcefreeQuerySuite(suite), TypeError);
  }
});

test('custody and both process entries share the closed reread selection', () => {
  assert.equal(sourcefreeSuiteRequiresReread(), false);
  assert.equal(sourcefreeSuiteRequiresReread('in-unnest'), false);
  for (const suite of ['sequence', 'time-series', 'temporal-join', 'calendar']) {
    assert.equal(sourcefreeSuiteRequiresReread(suite), true);
  }
  for (const suite of ['unknown', '--sequence-only', '']) {
    assert.throws(() => sourcefreeSuiteRequiresReread(suite), TypeError);
  }
  const root = fileURLToPath(new URL('../', import.meta.url));
  for (const path of ['scripts/fixtures/release-sourcefree-authorization.mjs',
    'scripts/fixtures/release-time-series-reread.mjs', 'scripts/test-package-release-sourcefree-query.mjs']) {
    assert.match(readFileSync(resolve(root, path), 'utf8'), /sourcefreeSuiteRequiresReread\(suite\)/u);
  }
});

test('normal source-free delivery contains its full relative import closure', () => {
  const root = fileURLToPath(new URL('../', import.meta.url));
  const closure = paths => {
    const delivered = new Set(paths.map(path => resolve(root, path)));
    const pending = [resolve(root, 'scripts/fixtures/release-sourcefree-query.mjs'),
      resolve(root, 'scripts/fixtures/release-time-series-reread.mjs')];
    const seen = new Set(), missing = [];
    while (pending.length) {
      const path = pending.pop();
      if (seen.has(path)) continue;
      seen.add(path);
      if (!delivered.has(path)) { missing.push(path); continue; }
      for (const match of readFileSync(path, 'utf8').matchAll(
        /(?:from\s*|import\s*\()(['"])(\.[^'"\n]+\.mjs)\1/gu)) {
        pending.push(resolve(dirname(path), match[2]));
      }
    }
    return {seen, missing};
  };
  const complete = closure(releaseSourcefreeFixturePaths);
  assert.deepEqual(complete.missing, []);
  assert.equal(complete.seen.size, 17);
  assert.deepEqual(closure(releaseSourcefreeFixturePaths.filter(path =>
    !path.endsWith('/in-unnest-source-input.mjs'))).missing,
  [resolve(root, 'scripts/fixtures/in-unnest-source-input.mjs')]);
  assert.deepEqual(closure(releaseSourcefreeFixturePaths.filter(path =>
    !path.endsWith("/release-public-aql-format-cases.mjs"))).missing,
  [resolve(root, "scripts/release-public-aql-format-cases.mjs")]);
  assert.deepEqual(closure(releaseSourcefreeFixturePaths.filter(path =>
    !path.endsWith('/calendar-source-input.mjs'))).missing,
  [resolve(root, 'scripts/fixtures/calendar-source-input.mjs')]);
  const omitted = resolve(root, 'scripts/fixtures/sequence-source-input.mjs');
  assert.deepEqual(closure(releaseSourcefreeFixturePaths.filter(path =>
    !path.endsWith('/sequence-source-input.mjs'))).missing, [omitted]);
  assert.deepEqual(closure(releaseSourcefreeFixturePaths.filter(path =>
    !path.endsWith('/temporal-join-source-input.mjs'))).missing,
  [resolve(root, 'scripts/fixtures/temporal-join-source-input.mjs')]);
});

test('installed source-free worker and consumer parse without starting a product', () => {
  const root = fileURLToPath(new URL('../', import.meta.url));
  for (const path of ['scripts/fixtures/release-sourcefree-query.mjs',
    'scripts/test-package-release-sourcefree-query.mjs']) {
    childProcess.execFileSync(process.execPath, ['--check', resolve(root, path)], {timeout: 10000});
  }
});

test('release selection preserves four independent inputs and all six refusals', () => {
  const before = JSON.stringify({successes, refusals});
  const selected = selectReleaseSourcefreeQueryCases();
  assert.deepEqual(selected.successes.map(value => value.name), [
    'in-unnest-literal-array-general-element', 'in-unnest-literal-array-array-field',
    'in-unnest-literal-array-conditional-array', 'in-unnest-literal-array-lazy-array-branch']);
  assert.equal(selected.refusals.length, 6);
  for (const value of selected.refusals) {
    assert.equal(value, combinedRefusals.find(item => item.name === value.name));
  }
  assert.equal(combinedRefusals.length, 13, 'the packed corpus keeps whole-ARRAY refusals');
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
  for (const changed of [combinedRefusals, refusals.slice(1), [...refusals, refusals[0]], [...refusals].reverse(),
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


test('membership fixture separately grants only its actual Run and main Result reads', async () => {
  const selected = selectReleaseSourcefreeQueryCases();
  assert.deepEqual([...new Set(selected.successes.flatMap(value => Object.keys(value.results)))], ['main']);
  for (const mode of ['local', 'https']) {
    const authorization = await sourcefreeFixtureAuthorization(mode, 'in-unnest');
    const account = JSON.parse(authorization.accountConfiguration);
    const entries = account.entries.filter(value => value.operation.any_of.includes('read'));
    assert.deepEqual(entries, [
      {entry_id: 'run-read', outcome: 'allow', principal: {all: true},
        connection: {any_of: ['actql-remote-host']}, resource: {any_of: ['run']},
        operation: {any_of: ['read']}, exclusions: []},
      {entry_id: 'result-main-read', outcome: 'allow', principal: {all: true},
        connection: {any_of: ['actql-remote-host']}, resource: {any_of: ['result/main']},
        operation: {any_of: ['read']}, exclusions: []},
    ]);
    assert.deepEqual(account.entries[0], {entry_id: 'write', outcome: 'allow',
      principal: {all: true}, connection: {all: true}, resource: {all: true},
      operation: {any_of: ['write']}, exclusions: []});
    const unchanged = JSON.parse((await sourcefreeFixtureAuthorization(mode, 'aql-format')).accountConfiguration);
    assert.deepEqual(unchanged.entries, [account.entries[0]], 'other suites receive no new grants');
  }
});
