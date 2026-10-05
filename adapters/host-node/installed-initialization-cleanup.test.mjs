import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

// Each subprocess installs module mocks before importing the real loaders.
// The public installation API gets no test-only dependency parameters.
const fixture = fileURLToPath(new URL(
  '../../scripts/fixtures/installed-initialization-cleanup.mjs', import.meta.url));
const repository = fileURLToPath(new URL('../../', import.meta.url));

function checkInitialization(scenario) {
  const result = spawnSync(process.execPath,
    ['--experimental-test-module-mocks', fixture, JSON.stringify(scenario)],
    {cwd: repository, encoding: 'utf8', timeout: 30_000});
  assert.equal(result.status, 0,
    `${result.error ?? ''}\n${result.stdout}\n${result.stderr}`);
  assert.match(result.stdout, /initialization custody checked/u);
}

for (const [kind, defects] of [
  ['source', ['registration', 'revision']],
  ['effect', ['registration', 'revision', 'prepareCaptured',
    'prepareRecovered', 'environmentWire']],
]) {
  for (const defect of defects) {
    for (const failClose of [false, true]) {
      test(`installed ${kind} ${defect} refusal ${failClose
        ? 'retains its adapter for close retry' : 'closes its returned adapter'}`,
      () => checkInitialization({mode: 'adapter', kind, defect, failClose}));
    }
  }
}

for (const kind of ['source', 'effect']) {
  for (const failClose of [false, true]) {
    test(`GitHub ${kind} async row factory failure ${failClose
      ? 'keeps its primary error and retryable Site' : 'closes its opened Site'}`,
    () => checkInitialization({mode: 'github', kind, failClose}));
  }
}

test('a second source initialization failure keeps both acquired owners reachable',
  () => checkInitialization({mode: 'multi-source'}));
