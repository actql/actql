import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {inferPackedOptions} from './test-packed-infer-input.mjs';

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
