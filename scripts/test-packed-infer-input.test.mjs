import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {inferPackedFixture, inferPackedOptions} from './test-packed-infer-input.mjs';

const owner = 'a'.repeat(40);
test('packed INFER requires a real setup and full common owner SHA', () => {
  assert.throws(() => inferPackedOptions([]), /InferTestHostSetupRequired/u);
  for (const value of ['', 'abcd', 'HEAD', 'a'.repeat(39)]) {
    assert.throws(() => inferPackedOptions(['--host-setup', 'real-host.mjs',
      '--owner-sha', value]), /InferCommonOwnerFullShaRequired/u);
  }
  assert.throws(() => inferPackedOptions(['--host-setup', 'real-host.mjs',
    '--owner-sha', owner, '--skip-owner']), {code: 'ERR_PARSE_ARGS_UNKNOWN_OPTION'});
  const options = inferPackedOptions(['--host-setup', 'real-host.mjs',
    '--owner-sha', owner, '--keep-artifacts']);
  assert.equal(options.ownerSha, owner);
  assert.equal(options.keepArtifacts, true);
  assert.equal(options.firstRowOnly, false);
  assert.equal(inferPackedOptions(['--host-setup', 'real-host.mjs',
    '--owner-sha', owner, '--first-row-only']).firstRowOnly, true);
});

test('one-row profile selects independent expectations without changing the full matrix', async () => {
  const fixture = JSON.parse(await readFile(new URL(
    '../spec/frontend/fixtures/infer-keep/packed-acceptance.json',
    import.meta.url), 'utf8'));
  const original = structuredClone(fixture);
  const first = inferPackedFixture(fixture, true);
  assert.deepEqual(first.successes, [fixture.first_row_success]);
  assert.deepEqual(first.expected_rows['first-row'], [{assessment: {
    input_key: {id: 'a'}, outcome: 'ok',
    value: {risk: 'high', reason: null},
  }}]);
  assert.deepEqual(first.source_rows['first-row'], [
    {id: 'a', text: 'urgent', secret: 'private-a'},
  ]);
  assert.equal(first.successes[0].model_dispatches, 1);
  assert.equal(first.successes[0].captured_slots, 1);
  assert.equal(first.successes[0].columns, 'omitted');
  assert.deepEqual(first.preparation_refusals, []);
  assert.deepEqual(first.preflight_failures, []);
  assert.deepEqual(inferPackedFixture(fixture, false), original);
  assert.deepEqual(fixture, original);
  assert.throws(() => inferPackedFixture({}, true), /InferFirstRowFixtureRequired/u);
});

for (const [name, args, message] of [
  ['missing setup', [], /InferTestHostSetupRequired/u],
  ['missing owner', ['--host-setup', 'real-host.mjs'],
    /InferCommonOwnerFullShaRequired/u],
  ['nonexistent setup', ['--host-setup', 'missing-infer-host-setup.mjs',
    '--owner-sha', owner], /ENOENT/u],
]) {
  test(`packed prerequisites reject ${name} before invoking build tools`, () => {
    const result = spawnSync(process.execPath, [fileURLToPath(new URL(
      './test-packed-infer-input.mjs', import.meta.url)), ...args], {
      env: {...process.env, PATH: ''}, encoding: 'utf8', timeout: 5_000,
    });
    assert.equal(result.error, undefined);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, message);
    assert.doesNotMatch(result.stderr, /PackedQueryCommandFailed|spawnSync git/u);
  });
}
