import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {compileFunction} from 'node:vm';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {parse} from 'acorn';
import {buildSync} from 'esbuild';

test('packed browser closure matches the actual authored SDK entry and preserves foreign-input refusal', () => {
  const repository = fileURLToPath(new URL('../', import.meta.url));
  const source = readFileSync(new URL('./test-node-client-package.mjs', import.meta.url), 'utf8');
  const syntax = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
  const selected = syntax.body.filter(node => node.type === 'ExpressionStatement' &&
    source.slice(node.start, node.end).startsWith('assert.deepEqual(Object.keys(metadata.inputs).sort(), ['));
  assert.equal(selected.length, 1);
  const graph = buildSync({absWorkingDir: repository, entryPoints: ['packages/sdk/index.mjs'],
    bundle: true, platform: 'browser', format: 'esm', target: 'es2022', metafile: true,
    write: false, logLevel: 'silent'});
  const inputs = Object.fromEntries(Object.keys(graph.metafile.inputs).map(path => {
    assert.match(path, /^packages\/(?:sdk|client-wire)\//u,
      'Browser entry may not acquire Local/Node/Core or an unrelated package');
    return [path.replace(/^packages\/sdk\//u, 'node_modules/@actql/sdk/')
      .replace(/^packages\/client-wire\//u, 'node_modules/@actql/client-wire/'), {}];
  }));
  assert(Object.values(graph.metafile.outputs).every(output => output.imports.length === 0));
  assert.equal(Object.keys(inputs).some(path => path.endsWith('/loopback-http.mjs')), false,
    'The browser condition must keep the unavailable loopback transport');
  const consume = compileFunction(source.slice(selected[0].start, selected[0].end), ['assert', 'metadata']);
  consume(assert, {inputs});
  for (const extra of ['node_modules/@actql/local-node/index.mjs',
    'node_modules/@actql/sdk/unreviewed.mjs', 'node_modules/foreign/index.mjs']) {
    assert.throws(() => consume(assert, {inputs: {...inputs, [extra]: {}}}), {code: 'ERR_ASSERTION'});
  }
  const absent = {...inputs}; delete absent['node_modules/@actql/sdk/internal/client.mjs'];
  assert.throws(() => consume(assert, {inputs: absent}), {code: 'ERR_ASSERTION'});
});
