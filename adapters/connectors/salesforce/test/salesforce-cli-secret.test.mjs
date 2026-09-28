import assert from 'node:assert/strict';
import test from 'node:test';
import {createSalesforceCliSecretResolver,
  inspectSalesforceCliConnection} from '../site/salesforce-cli-secret.mjs';

const binding = Object.freeze({alias: 'actql-test', orgId: '00D-ONE',
  username: 'user@example.test', instanceOrigin: 'https://sf.example.test'});
const scope = Object.freeze({principal: 'principal-a', namespaceId: 'namespace-a',
  environment: 'local', siteKey: 'site-a', siteGeneration: 3,
  connectorRegistration: 'salesforce',
  resourceOrigin: binding.instanceOrigin, operation: 'salesforce:query:read'});
const serialized = (result = {}, status = 0) => JSON.stringify({status,
  result: {alias: binding.alias, id: binding.orgId,
    username: binding.username, instanceUrl: binding.instanceOrigin,
    accessToken: '(redacted)', ...result}});
const tokenJson = accessToken => JSON.stringify({status: 0,
  result: {accessToken}});
const settings = invoke => ({invoke, executable: 'sf',
  maxOutputBytes: 8192, timeoutMs: 1000});
const resolver = (invoke, overrides = {}) =>
  createSalesforceCliSecretResolver({connection: binding,
    principal: scope.principal, namespaceId: scope.namespaceId,
    environment: scope.environment, siteKey: scope.siteKey,
    siteGeneration: scope.siteGeneration, ...settings(invoke), ...overrides});

test('CLI connection inspection exposes no secret and uses public arguments',
  async () => {
    const calls = [];
    const connection = await inspectSalesforceCliConnection(binding.alias, {
      ...settings(async (...args) => {
        calls.push(args);
        return {stdout: serialized()};
      }),
    });
    assert.deepEqual(connection, binding);
    assert.doesNotMatch(JSON.stringify(connection), /sensitive-access-token/u);
    assert.deepEqual(calls[0][1], ['org', 'display', '--target-org',
      binding.alias, '--json']);
    assert.equal(calls[0][2].maxBuffer, 8192);
    assert.equal(calls[0][2].timeout, 1000);
  });

test('Site session reuses its exact binding and refreshes after expiry',
  async () => {
  let tokenCalls = 0;
  let displays = 0;
  let currentTime = 0;
  const resolveSecret = resolver(async (_executable, args) => ({
    stdout: args[1] === 'auth'
      ? tokenJson(`token-${++tokenCalls}`)
      : (displays++, serialized()),
  }), {tokenReuseMs: 100, monotonicNow: () => currentTime});
  assert.equal(await resolveSecret(scope), 'token-1');
  assert.equal(await resolveSecret(scope), 'token-1');
  assert.equal(tokenCalls, 1);
  assert.equal(displays, 2);
  currentTime = 100;
  assert.equal(await resolveSecret(scope), 'token-2');
  assert.equal(tokenCalls, 2);
  assert.equal(displays, 4);
  const changed = resolver(async () => ({stdout: serialized({
    id: '00D-OTHER',
  })}));
  await assert.rejects(changed(scope), {
    code: 'SalesforceCliConnectionMismatch',
  });
});

test('concurrent uses share refresh and cancellation cannot cancel peers',
  async () => {
    let release;
    const pending = new Promise(resolve => { release = resolve; });
    let entered;
    const started = new Promise(resolve => { entered = resolve; });
    let tokenCalls = 0;
    const resolveSecret = resolver(async (_executable, args) => {
      if (args[1] === 'auth') {
        tokenCalls++;
        entered();
        await pending;
        return {stdout: tokenJson('session-token')};
      }
      return {stdout: serialized()};
    });
    const cancellation = new AbortController();
    const cancelled = resolveSecret(scope, cancellation.signal);
    const active = resolveSecret(scope);
    await started;
    cancellation.abort();
    await assert.rejects(cancelled, {code: 'SalesforceCliCancelled'});
    release();
    assert.equal(await active, 'session-token');
    assert.equal(tokenCalls, 1);
    assert.equal(await resolveSecret(scope), 'session-token');
    assert.equal(tokenCalls, 1);
  });

test('credential invalidation is token-specific and refreshes on next use',
  async () => {
    let tokenCalls = 0;
    const resolveSecret = resolver(async (_executable, args) => ({
      stdout: args[1] === 'auth'
        ? tokenJson(`token-${++tokenCalls}`) : serialized(),
    }));
    assert.equal(await resolveSecret(scope), 'token-1');
    assert.equal(resolveSecret.invalidate('different-token'), false);
    assert.equal(await resolveSecret(scope), 'token-1');
    assert.equal(resolveSecret.invalidate('token-1'), true);
    assert.equal(await resolveSecret(scope), 'token-2');
    assert.equal(tokenCalls, 2);
  });

test('alias retarget affects refresh, not the active pinned session',
  async () => {
    let orgId = binding.orgId;
    let currentTime = 0;
    const resolveSecret = resolver(async (_executable, args) => ({
      stdout: args[1] === 'auth' ? tokenJson('session-token')
        : serialized({id: orgId}),
    }), {tokenReuseMs: 100, monotonicNow: () => currentTime});
    assert.equal(await resolveSecret(scope), 'session-token');
    orgId = '00D-OTHER';
    assert.equal(await resolveSecret(scope), 'session-token');
    currentTime = 100;
    await assert.rejects(resolveSecret(scope), {
      code: 'SalesforceCliConnectionMismatch',
    });
  });

test('scope mismatch fails before invoking the CLI', async () => {
  let calls = 0;
  const resolveSecret = resolver(async () => {
    calls++;
    return {stdout: serialized()};
  });
  for (const difference of [
    {principal: 'other'}, {namespaceId: 'other'}, {environment: 'cloud'},
    {siteGeneration: 4}, {siteKey: 'site-b'},
    {connectorRegistration: 'other'},
    {resourceOrigin: 'https://other.example.test'},
  ]) {
    await assert.rejects(resolveSecret({...scope, ...difference}), {
      code: 'SalesforceCliConnectionMismatch',
    });
  }
  assert.equal(calls, 0);
});

test('alias change after token resolution still denies credential use',
  async () => {
    let displays = 0;
    const resolveSecret = resolver(async (_executable, args) => ({
      stdout: args[1] === 'auth' ? tokenJson('sensitive-access-token')
        : serialized({id: ++displays === 1 ? binding.orgId : '00D-OTHER'}),
    }));
    await assert.rejects(resolveSecret(scope), {
      code: 'SalesforceCliConnectionMismatch',
    });
    assert.equal(displays, 2);
  });

test('CLI failures are bounded, typed, and redact token-bearing output',
  async () => {
    const cases = [
      [async () => { throw Object.assign(new Error('secret'),
        {code: 'ENOENT'}); }, 'SalesforceCliUnavailable'],
      [async () => { throw Object.assign(new Error('secret'),
        {killed: true}); }, 'SalesforceCliTimeout'],
      [async () => { throw Object.assign(new Error('secret'),
        {code: 'ERR_CHILD_PROCESS_STDIO_MAXBUFFER'}); },
      'SalesforceCliOutputLimit'],
      [async () => { throw new Error('sensitive-access-token'); },
        'SalesforceCliAuthenticationFailed'],
      [async () => ({stdout: '{sensitive-access-token'}),
        'SalesforceCliMalformedOutput'],
      [async () => ({stdout: ''}), 'SalesforceCliMalformedOutput'],
      [async () => ({stdout: serialized({}, 1)}),
        'SalesforceCliAuthenticationFailed'],
      [async () => ({stdout: serialized({connectedStatus: 'Expired'})}),
        'SalesforceCliAuthenticationFailed'],
      [async () => ({stdout: 'x'.repeat(8193)}),
        'SalesforceCliOutputLimit'],
    ];
    for (const [invoke, code] of cases) {
      const resolveSecret = resolver(invoke);
      await assert.rejects(resolveSecret(scope), error => {
        assert.equal(error.code, code);
        assert.doesNotMatch(String(error), /sensitive-access-token/u);
        assert.equal(error.cause, undefined);
        return true;
      });
    }
  });

test('production subprocess path rejects absent CLI without a fallback',
  async () => {
    const resolveSecret = createSalesforceCliSecretResolver({
      connection: binding, principal: scope.principal, namespaceId: scope.namespaceId,
      environment: scope.environment, siteKey: scope.siteKey,
      siteGeneration: scope.siteGeneration,
      executable: 'actql-nonexistent-salesforce-cli-executable',
    });
    await assert.rejects(resolveSecret(scope), {
      code: 'SalesforceCliUnavailable',
    });
  });

test('CLI process limits cannot be configured to unbounded values', () => {
  assert.throws(() => resolver(async () => ({stdout: serialized()}), {
    maxOutputBytes: 1_048_577,
  }), {code: 'SalesforceCliInvalidConfiguration'});
  assert.throws(() => resolver(async () => ({stdout: serialized()}), {
    timeoutMs: 60_001,
  }), {code: 'SalesforceCliInvalidConfiguration'});
  assert.throws(() => resolver(async () => ({stdout: serialized()}), {
    tokenReuseMs: 300_001,
  }), {code: 'SalesforceCliInvalidConnection'});
});
