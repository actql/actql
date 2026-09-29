import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {mkdir, writeFile} from 'node:fs/promises';
import {isAbsolute, join} from 'node:path';
import {querySuccesses, queryRefusals} from './public-query-input.mjs';

// The caller installs the real native binary, configures its mTLS connection,
// and provisions records through the ordinary Host profile. No source is
// lowered here. observe() reports real Host admission/acquisition counters.
// This application is pending until the public Host routing is connected.
export async function exerciseNativeQueryInput({executable, root, commonArgs,
  requestPrefix, observe}) {
  assert.ok(isAbsolute(executable) && isAbsolute(root));
  assert.match(requestPrefix, /^[a-zA-Z0-9_-]+$/);
  assert.equal(typeof observe, 'function');
  const emptyPath = join(root, 'empty-path');
  await mkdir(emptyPath, {recursive: true});
  const run = (...args) => new Promise((resolve, reject) => {
    execFile(executable, [...commonArgs, ...args], {cwd: root,
      env: {...process.env, PATH: emptyPath}, encoding: 'utf8',
      timeout: 60_000, maxBuffer: 2 * 1024 * 1024},
    (error, stdout, stderr) => {
      if (error && (typeof error.code !== 'number' || error.signal)) {
        reject(error);
      } else {
        resolve({code: error?.code ?? 0, stdout, stderr});
      }
    });
  });
  const json = async (...args) => {
    const result = await run(...args);
    assert.equal(result.code, 0, result.stderr);
    return JSON.parse(result.stdout);
  };
  const counters = async () => {
    const {acceptedRuns, sourceIo} = await observe();
    assert.ok(Number.isSafeInteger(acceptedRuns) && acceptedRuns >= 0);
    assert.ok(Number.isSafeInteger(sourceIo) && sourceIo >= 0);
    return {acceptedRuns, sourceIo};
  };
  const submitArgs = async item => {
    const stem = requestPrefix + '-' + item.name;
    await writeFile(join(root, stem + '.source'), item.text, {mode: 0o600});
    const args = ['aql', '--program-file', stem + '.source', '--format',
      item.format, '--request-id', stem];
    for (const [field, option] of [
      ['parameterDeclarations', '--parameter-declarations-file'],
      ['parameters', '--parameters-file'],
    ]) {
      if (item[field] !== undefined) {
        const file = stem + '.' + field + '.json';
        await writeFile(join(root, file), JSON.stringify(item[field]),
          {mode: 0o600});
        args.push(option, file);
      }
    }
    return args;
  };
  await json('connect');
  for (const item of querySuccesses) {
    const args = await submitArgs(item);
    const accepted = await json(...args);
    assert.ok(accepted.ref, 'expected Run acceptance, not a held request');
    const refFile = requestPrefix + '-' + item.name + '.ref.json';
    await writeFile(join(root, refFile), JSON.stringify(accepted.ref));
    const state = await json('wait', '--ref-file', refFile);
    assert.equal(state.status, 'succeeded', JSON.stringify(state));
    const before = await counters();
    for (let attempt = 0; attempt < 2; attempt++) {
      const read = await run('read', '--ref-file', refFile, '--result-name',
        'answer', '--attempt-id', requestPrefix + '-' + item.name + '-' + attempt);
      assert.equal(read.code, 0, read.stderr);
      const rows = read.stdout === '' ? []
        : read.stdout.trimEnd().split('\n').map(line => JSON.parse(line));
      assert.deepEqual(rows, item.expected);
      assert.deepEqual((await json('attach', '--ref-file', refFile)).ref,
        accepted.ref);
    }
    assert.deepEqual((await json(...args)).ref, accepted.ref);
    assert.deepEqual((await json('lookup-request', '--request-id',
      requestPrefix + '-' + item.name)).ref, accepted.ref);
    assert.deepEqual(await counters(), before,
      'read, attach and resend must not admit or acquire again');
  }
  for (const item of queryRefusals) {
    const before = await counters();
    const rejected = await run(...await submitArgs(item));
    assert.notEqual(rejected.code, 0);
    assert.match(rejected.stderr,
      /Client(?:Program(?:InvalidInput|Unsupported|NeedsInputs|Rejected)|Parameters(?:Invalid|TooLarge))/);
    assert.doesNotMatch(rejected.stderr, /SubmissionUnknown|secret-value/);
    assert.deepEqual(await counters(), before,
      'rejected source must not admit a Run or perform source I/O');
    assert.deepEqual(await json('lookup-request', '--request-id',
      requestPrefix + '-' + item.name), {kind: 'not_found'});
  }
}
