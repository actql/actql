import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
import test from 'node:test';
import {parse} from 'acorn';

const source = readFileSync(new URL('./test-native-remote-runtime.mjs', import.meta.url), 'utf8');
const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
function fixture({reportFailure} = {}) {
  const names = ['timedRemotePhase', 'timedRemoteAsyncPhase'];
  const functions = names.map(name => ast.body.find(node =>
    node.type === 'FunctionDeclaration' && node.id.name === name));
  assert(functions.every(Boolean), 'Both original sync/async timing boundaries required');
  const records = [], clock = {now: 0};
  const context = {performance: {now: () => clock.now}, console: {error(line) {
    if (reportFailure) throw reportFailure;
    assert(line.startsWith('ACTQL_NATIVE_CI_PHASE '));
    records.push(JSON.parse(line.slice('ACTQL_NATIVE_CI_PHASE '.length)));
  }}};
  const helpers = runInNewContext(functions.map(node => source.slice(node.start, node.end)).join('\n') +
    '\n({timedRemotePhase,timedRemoteAsyncPhase})', context);
  return {...helpers, records, clock};
}

test('remote phase timing preserves synchronous results and primary errors even if reporting fails', () => {
  const f = fixture(), original = {}, failure = new Error('original'), reporting = new Error('reporting');
  let calls = 0;
  assert.equal(f.timedRemotePhase('executor', () => {calls++; f.clock.now = 17.4; return original;}), original);
  assert.equal(calls, 1);
  assert.deepEqual(f.records, [{scope: 'remote-runtime', phase: 'executor', milliseconds: 17, succeeded: true}]);
  assert.throws(() => f.timedRemotePhase('runtime', () => {throw failure;}), error => error === failure);
  assert.equal(f.records.at(-1).succeeded, false);
  const broken = fixture({reportFailure: reporting});
  assert.equal(broken.timedRemotePhase('executor', () => original), original);
  assert.throws(() => broken.timedRemotePhase('runtime', () => {throw failure;}), error => error === failure);
});

test('remote async phase reports only after the original pending operation settles', async () => {
  const f = fixture(), original = {}; let resolveOriginal, calls = 0;
  const pending = new Promise(resolve => {resolveOriginal = resolve;});
  const result = f.timedRemoteAsyncPhase('query', () => {calls++; return pending;});
  f.clock.now = 23.6;
  await Promise.resolve();
  assert.equal(calls, 1); assert.deepEqual(f.records, []);
  resolveOriginal(original);
  assert.equal(await result, original);
  assert.deepEqual(f.records, [{scope: 'remote-runtime', phase: 'query', milliseconds: 24, succeeded: true}]);
});

test('remote async timing preserves original rejection and synchronous throws through reporting failure', async () => {
  const failure = new Error('original');
  for (const reportFailure of [undefined, new Error('reporting')]) {
    const f = fixture({reportFailure});
    await assert.rejects(f.timedRemoteAsyncPhase('values-exchange', () => Promise.reject(failure)), error => error === failure);
    await assert.rejects(f.timedRemoteAsyncPhase('values-exchange', () => {throw failure;}), error => error === failure);
    if (!reportFailure) assert(f.records.every(record => !record.succeeded));
  }
});

test('remote timing selects only the existing preparation and Native command boundaries', () => {
  const calls = [];
  function visit(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'CallExpression' && ['timedRemotePhase', 'timedRemoteAsyncPhase'].includes(node.callee?.name)) calls.push(node);
    for (const child of Object.values(node)) {
      if (Array.isArray(child)) child.forEach(visit); else if (child && typeof child === 'object') visit(child);
    }
  }
  visit(ast);
  assert.deepEqual(calls.map(call => [call.callee.name, call.arguments[0].value]).sort(), [
    ['timedRemotePhase', 'compiler-copy'], ['timedRemotePhase', 'portable-core'],
    ['timedRemotePhase', 'executor'], ['timedRemotePhase', 'runtime'],
    ['timedRemoteAsyncPhase', 'query'], ['timedRemotePhase', 'values-build'],
    ['timedRemoteAsyncPhase', 'values-exchange'], ['timedRemotePhase', 'agent'],
  ].sort());
  for (const call of calls) {
    assert.equal(call.arguments.length, 2);
    assert.equal(call.arguments[1].type, 'ArrowFunctionExpression');
    assert.equal(call.arguments[1].params.length, 0);
    assert.equal(call.arguments[1].body.type, 'CallExpression');
  }
});
