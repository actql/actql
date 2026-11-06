import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {compileFunction} from 'node:vm';
import test from 'node:test';
import {parse} from 'acorn';

test('both packed Remote Hosts install only the authored request and observation tuples', () => {
  const source = readFileSync(new URL('./test-node-client-package.mjs', import.meta.url), 'utf8');
  const parseSource = text => parse(text, {ecmaVersion: 'latest', sourceType: 'module'});
  const nodes = ast => {
    const found = [];
    (function visit(node) {
      if (!node || typeof node !== 'object') return;
      if (typeof node.type === 'string') found.push(node);
      for (const value of Object.values(node)) {
        if (Array.isArray(value)) value.forEach(visit);
        else if (value && typeof value === 'object') visit(value);
      }
    })(ast);
    return found;
  };
  const ast = nodes(parseSource(source));
  const policy = ast.filter(node => node.type === 'VariableDeclarator' && node.id.name === 'remoteAuthorization');
  assert.equal(policy.length, 1, 'The operator must explicitly install the Remote Account');
  const principal = 'packed-operator';
  const authorization = compileFunction('return ' + source.slice(policy[0].init.start, policy[0].init.end),
    ['userInfo'])(() => ({username: principal}));
  const account = JSON.parse(authorization.accountConfiguration);
  assert.equal(account.version, 'actql-execution-account-config/0.1');
  assert.equal(account.account_id, 'packed-remote-account');
  const rowSource = readFileSync(new URL('../adapters/host-node/installed-duckdb-source.mjs', import.meta.url), 'utf8');
  assert.match(rowSource, /realizationKey: 'duckdb-acquired'/u);
  const tuples = [];
  for (const entry of account.entries) {
    assert.equal(entry.outcome, 'allow');
    assert.deepEqual(entry.principal, {any_of: [principal]});
    assert.deepEqual(entry.connection, {any_of: ['actql-remote-host']});
    assert.deepEqual(entry.exclusions, []);
    assert.deepEqual(Object.keys(entry.resource), ['any_of']);
    assert.deepEqual(Object.keys(entry.operation), ['any_of']);
    assert.deepEqual(entry.resource.any_of, [...entry.resource.any_of].sort());
    assert.deepEqual(entry.operation.any_of, [...entry.operation.any_of].sort());
    for (const resource of entry.resource.any_of) for (const operation of entry.operation.any_of) {
      tuples.push(resource + ':' + operation);
    }
  }
  assert.deepEqual(tuples.sort(), ['result/answer:read', 'result/b:read', 'result/c:read',
    'result/last:read', 'run:read', 'duckdb-acquired:write', 'source-free-values:write'].sort());
  const primary = ast.filter(node => node.type === 'VariableDeclarator' && node.id.name === 'remoteHost');
  assert.equal(primary.length, 1);
  const first = primary[0].init.argument.arguments[0];
  const firstOptions = compileFunction('return ' + source.slice(first.start, first.end),
    ['join', 'root', 'sourceProfilePath', 'hostCapacityPolicy', 'userInfo', 'heldDispatch', 'remoteAuthorization'])(
    (...parts) => parts.join('/'), 'root', 'source-profile', {}, () => ({username: principal}), undefined, authorization);
  assert.equal(firstOptions.authorization, authorization);
  assert.equal(firstOptions.authenticate('Bearer packed-test-token'), principal);
  assert.equal(firstOptions.authenticate('Bearer foreign'), undefined);
  const writes = ast.filter(node => node.type === 'CallExpression' && node.callee.name === 'writeFile');
  const sidecar = writes.filter(node => node.arguments[0]?.arguments?.[1]?.value === 'remote-authorization.json');
  assert.equal(sidecar.length, 1);
  assert.equal(source.slice(sidecar[0].arguments[1].start, sidecar[0].arguments[1].end),
    'JSON.stringify(remoteAuthorization)');
  const restart = writes.filter(node => node.arguments[0]?.arguments?.[1]?.value === 'restart-remote-host.mjs');
  assert.equal(restart.length, 1);
  const template = restart[0].arguments[1];
  assert.equal(template.expressions.length, 0);
  const child = template.quasis[0].value.cooked;
  const host = nodes(parseSource(child)).find(node => node.type === 'VariableDeclarator' && node.id.name === 'host');
  const options = host.init.argument.arguments[0];
  const restored = compileFunction('return ' + child.slice(options.start, options.end),
    ['join', 'process', 'hostCapacityPolicy', 'readFileSync', 'userInfo'])(
    (...parts) => parts.join('/'), {cwd: () => 'fresh-restart', env: {}}, {},
    (path, encoding) => {assert.equal(path, 'remote-authorization.json'); assert.equal(encoding, 'utf8');
      return JSON.stringify(authorization);}, () => ({username: principal}));
  assert.deepEqual(restored.authorization, authorization);
  assert.equal(restored.authenticate('Bearer packed-test-token'), principal);
  assert.equal(restored.authenticate('Bearer foreign'), undefined);
});

test('the repeated-cancel caller distinguishes the attempt from its original Run cancellation', async () => {
  const source = readFileSync(new URL('./test-node-client-package.mjs', import.meta.url), 'utf8');
  const start = source.indexOf('const repeatedCancellation = await cancelledRun.cancel();');
  assert.ok(start >= 0);
  const end = source.indexOf("assert.equal((await cancelledRun.wait()).status, 'cancelled');", start);
  assert.ok(end > start);
  const original = Object.freeze({fixture: 'same-cancelled-run'});
  const consume = compileFunction('return (async () => {' + source.slice(start, end) + '})();',
    ['assert', 'cancelledRun']);
  let calls = 0;
  const response = {kind: 'already_satisfied', cancellation: {kind: 'already_requested', ref: original}};
  await consume(assert, {ref: original, async cancel() {calls++; return response;}});
  assert.equal(calls, 1);
  for (const changed of [{...response, kind: 'accepted'},
    {...response, cancellation: {...response.cancellation, kind: 'already_terminal'}},
    {...response, cancellation: {...response.cancellation, ref: {fixture: 'foreign'}}}]) {
    await assert.rejects(consume(assert, {ref: original, cancel: async () => changed}),
      {code: 'ERR_ASSERTION'});
  }
});
