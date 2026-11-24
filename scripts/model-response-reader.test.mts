import test from 'node:test';
import assert from 'node:assert/strict';
import {copyFileSync, mkdirSync, readFileSync, symlinkSync, writeFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createOwnedScratch} from './owned-scratch.mjs';
import {setImmediate as turn} from 'node:timers/promises';
import {readBoundedInferResponse as common} from '../adapters/host-common/model-response-reader.mjs';
import {readBoundedInferResponse as ai} from '../packages/provider-ai-sdk/_internal/bounded-response.mjs';
import {readBoundedInferResponse as http} from '../packages/provider-http/_internal/bounded-response.mjs';

const source = new URL('../adapters/host-common/model-response-reader.mjs', import.meta.url);
test('independent physical reader copies remain byte-identical to their single source', () => {
  const original = readFileSync(source);
  for (const path of ['../packages/provider-ai-sdk/_internal/bounded-response.mjs',
    '../packages/provider-http/_internal/bounded-response.mjs']) {
    assert.deepEqual(readFileSync(new URL(path, import.meta.url)), original);
  }
});

// Direct physical reader conformance, not SDK/Core/Store/public admission.
// Every fixture settles its original operations in teardown, never pretending
// that a permanently unresponsive implementation has physically retired.
for (const [name, read] of [['Common', common], ['AI SDK copy', ai], ['independent HTTP copy', http]] as const) {
  test(`${name} abort exposes exact prefix but cancel alone cannot retire pending read`, async () => {
    const controller = new AbortController();
    let finishRead: ((value: {done: boolean; value?: Uint8Array}) => void) | undefined;
    let finishCancel: (() => void) | undefined;
    let releases = 0;
    let reads = 0;
    let cancellations = 0;
    const response = {status: 200, headers: new Headers(), body: {getReader() {
      return {
        read() {
          reads++;
          if (reads === 1) return Promise.resolve({done: false, value: new Uint8Array([65])});
          return new Promise<{done: boolean; value?: Uint8Array}>(resolve => { finishRead = resolve; });
        },
        cancel() { cancellations++; return new Promise<void>(resolve => { finishCancel = resolve; }); },
        releaseLock() { releases++; },
      };
    }}};
    let observed: Awaited<ReturnType<typeof common>> | undefined;
    const operation = read(response, {maxBytes: 8, maxChunkBytes: 4, maxChunks: 2,
      maxHeaderBytes: 16}, controller.signal).then(value => { observed = value; return value; });
    try {
      for (let i = 0; i < 8 && finishRead === undefined; i++) await turn();
      assert.equal(reads, 2);
      controller.abort();
      for (let i = 0; i < 8 && observed === undefined; i++) await turn();
      assert.notEqual(observed, undefined);
      assert.deepEqual(observed!.body, new Uint8Array([65]));
      assert.equal(observed!.transportComplete, false);
      assert.equal(observed!.issue, 'InferResponseReadCancelled');
      finishCancel!();
      for (let i = 0; i < 4; i++) await turn();
      assert.equal(releases, 0);
      assert.equal(cancellations, 1);
      finishRead!({done: false, value: new Uint8Array([66])});
      assert.equal(await observed!.readerRetirement, true);
      assert.equal(releases, 1);
      assert.equal(reads, 2);
      assert.deepEqual(observed!.body, new Uint8Array([65]));
      assert.equal(observed!.observedBytes, 1);
      assert.equal(observed!.transportComplete, false);
    } finally {
      finishRead?.({done: true});
      const original = await operation;
      finishCancel?.();
      await original.readerRetirement;
    }
  });
}


test('physical reader generator checks authored Source and both output kinds without partial publication', async () => {
  const originalRoot = fileURLToPath(new URL('../', import.meta.url));
  const scratch = await createOwnedScratch({parent: join(originalRoot, '_build'),
    prefix: 'model-reader-generation-', label: 'model reader generation Source control'});
  const directory = scratch.path;
  const inputs = ['tsconfig.base.json', 'scripts/generate-model-response-reader.mjs',
    'scripts/typescript-interface-emit.mjs', 'adapters/host-common/model-response-reader.mts'];
  const outputs = ['provider-ai-sdk', 'provider-http'].flatMap(name =>
    ['mjs', 'd.mts'].map(extension => `packages/${name}/_internal/bounded-response.${extension}`));
  for (const path of [...inputs, ...outputs]) {
    mkdirSync(dirname(join(directory, path)), {recursive: true});
    copyFileSync(join(originalRoot, path), join(directory, path));
  }
  symlinkSync(join(originalRoot, 'node_modules'), join(directory, 'node_modules'), 'dir');
  // Stale ignored emit is deliberately unusable; only authored Source compiles.
  writeFileSync(join(directory, 'adapters/host-common/model-response-reader.mjs'),
    'throw new Error("ignored emit is not a generation input");');
  const run = (mode: '--check' | '--write') => spawnSync(process.execPath,
    ['scripts/generate-model-response-reader.mjs', mode], {cwd: directory,
      encoding: 'utf8', timeout: 30000, maxBuffer: 1024 * 1024});
  const clean = run('--check');
  assert.equal(clean.error, undefined); assert.equal(clean.signal, null);
  assert.equal(clean.status, 0, clean.stderr);
  const originals = new Map(outputs.map(path => [path, readFileSync(join(directory, path))]));
  for (const path of [outputs[0]!, outputs[3]!]) {
    writeFileSync(join(directory, path), Buffer.concat([originals.get(path)!, Buffer.from('\n// stale fixture output\n')]));
    const changed = readFileSync(join(directory, path));
    const stale = run('--check');
    assert.equal(stale.error, undefined); assert.equal(stale.signal, null);
    assert.notEqual(stale.status, 0);
    assert.match(stale.stderr, /Model response reader drift/u);
    for (const other of outputs) assert.deepEqual(readFileSync(join(directory, other)),
      other === path ? changed : originals.get(other), 'read-only refusal must not rewrite either package');
    writeFileSync(join(directory, path), originals.get(path)!);
  }
  const authored = join(directory, 'adapters/host-common/model-response-reader.mts');
  writeFileSync(authored, readFileSync(authored, 'utf8') + '\nconst invalidSource: number = "not a number";\n');
  const refused = run('--write');
  assert.equal(refused.error, undefined); assert.equal(refused.signal, null);
  assert.notEqual(refused.status, 0);
  assert.match(refused.stderr, /TS2322/u);
  for (const path of outputs) assert.deepEqual(readFileSync(join(directory, path)), originals.get(path),
    'failed strict compile cannot publish partial runtime or declarations');
  scratch.passed(); scratch.close();
});
