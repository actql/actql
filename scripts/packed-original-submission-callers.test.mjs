// Source-extracted packed callers through the real SDK with explicit Host wire
// replies. These controls do not establish installed Run or resource acceptance.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';

const source = readFileSync(new URL('./test-node-client-package.mjs', import.meta.url), 'utf8');
const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
function actor(name) {
  const writer = tree.body.map(node => node.expression?.argument).find(node =>
    node?.callee?.name === 'writeFile' && node.arguments[0]?.arguments?.some(value => value.value === name));
  assert(writer, name);
  assert.equal(writer.arguments[1].expressions.length, 0);
  return writer.arguments[1].quasis[0].value.cooked;
}
function between(text, before, after) {
  const start = text.indexOf(before), end = text.indexOf(after, start);
  assert(start >= 0 && end > start, before);
  return text.slice(start + before.length, end);
}
function nodes(value, predicate, found = []) {
  if (!value || typeof value !== 'object') return found;
  if (predicate(value)) found.push(value);
  for (const member of Object.values(value)) {
    if (Array.isArray(member)) member.forEach(node => nodes(node, predicate, found));
    else if (member && typeof member === 'object') nodes(member, predicate, found);
  }
  return found;
}
const limits = {maxReadWireBytes: 4096, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
  maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 3, maxBatchRetainedValueBytes: 1024};

async function sdkOriginal(t, name, parameters) {
  const sdk = await import('../packages/sdk/index.mjs');
  const {submissionEpoch} = await import('../packages/sdk/submission-fixture.mjs');
  const calls = [], original = {epoch: submissionEpoch, nonce: 'original-' + name};
  const ref = {namespaceId: 'packed-original', authorityScopeCid: submissionEpoch.authorityScopeCid,
    runDefinitionCid: 'sha256:' + 'd'.repeat(64)};
  let intentCid, foreign = false;
  const client = await sdk.connectInProcess({mode: 'local', owner: 'local'}, {perform(operation, body) {
    if (operation === 'connect') return {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
      durability: 'durable', scopeRef: 'packed-original', capabilities: ['aql-document'], submissionEpoch, limits};
    if (operation === 'close') return;
    calls.push(operation);
    if (operation === 'lookup-request') return {kind: 'not_found'};
    if (operation === 'lookup-submission') {
      assert.deepEqual(body.submissionRef, original, 'lookup needs the original Owner outcome, not this replay candidate');
      return {kind: 'ready', submissionRef: foreign ? {...original, nonce: 'foreign'} : original,
        intentCid, admission: {ref, durability: 'durable', revision: 1}};
    }
    if (operation === 'submit-intent') {
      assert.deepEqual(body.submissionRef, original);
      assert.equal(body.intentCid, intentCid);
      return {kind: 'already_satisfied', attemptRef: body.attemptRef,
        outcome: {kind: 'ready', submissionRef: original, intentCid,
          admission: {ref, durability: 'durable', revision: 1}}};
    }
    assert.equal(operation, 'submit-named-intent');
    assert.equal(body.requestName, name);
    intentCid ??= body.intentCid;
    if (body.intentCid !== intentCid) return {kind: 'conflict', reason: 'intent',
      requestName: name, intentCid: body.intentCid, attemptRef: body.attemptRef};
    return {kind: 'observed', requestName: name, intentCid, attemptRef: body.attemptRef,
      outcome: {kind: 'ready', submissionRef: original, intentCid,
        admission: {ref, durability: 'durable', revision: 1}}};
  }});
  t.after(() => client.close());
  const document = JSON.stringify({stages: [{steps: [{values: {rows: [{id: 1}, {id: 2}]}}]}]});
  const execution = await client.startSource(document, {format: 'json', requestId: name,
    ...(parameters === undefined ? {} : {parameters})});
  assert.notDeepEqual(sdk.getSubmissionInput(execution).submissionRef, original);
  assert.deepEqual(sdk.getSubmissionOutcome(execution).submissionRef, original);
  return {sdk, client, execution, document, original, calls, makeForeign: () => {foreign = true;}};
}

test('packed named callers look up original outcomes and keep replay and intent conflict distinct', async t => {
  const smoke = actor('smoke.mjs');
  const acquired = between(smoke, 'async function runAcquiredApplication(options, requestId) {',
    '// Focused review acceptance');
  const checks = [
    ['packed-standard-values', between(smoke, "  .deliveryAttempt(reader.attemptId)).kind, 'found');",
      'assert.deepEqual((await installedLocal.attach(execution.ref)).ref,')],
    ['packed-remote-values', between(smoke, 'assert.deepEqual((await installedRemote.attach(remoteExecution.ref)).ref,\n  remoteExecution.ref);',
      "await assert.rejects(remoteExecution.result('answer').all({maxRows: 1}),")],
    ['packed-acquired-local', between(acquired, "    'found');", '  return {client, execution, b, c'), {minimum: 1}],
    ['packed-standard-values', between(smoke, "await checkSegmentedResults(installedLocal, 'local');",
      'installedLocal.close();')],
  ];
  for (const [name, fragment, parameters] of checks) {
    const f = await sdkOriginal(t, name, parameters);
    const check = new Function('assert', 'installedLocal', 'installedRemote', 'client', 'execution', 'remoteExecution',
      'requestId', 'document', 'acquiredDocument', 'getSubmissionOutcome', 'getSubmissionAttempt', 'valuesSubmission',
      'return (async () => {' + fragment + '})();');
    const invoke = () => check(assert, f.client, f.client, f.client, f.execution, f.execution,
      name, f.document, f.document, f.sdk.getSubmissionOutcome, f.sdk.getSubmissionAttempt,
      f.sdk.getSubmissionOutcome(f.execution));
    const before = f.calls.length;
    await invoke();
    const calls = f.calls.slice(before);
    assert.equal(calls.filter(value => value === 'lookup-request').length, 0);
    const replayed = fragment.includes('startSource');
    assert.equal(calls.filter(value => value === 'submit-named-intent').length, replayed ? 2 : 0);
    if (calls.includes('lookup-submission')) {
      f.makeForeign();
      await assert.rejects(invoke(), {code: 'InvalidHostSubmissionLookup'});
      assert.equal(f.calls.slice(before).filter(value => value === 'submit-named-intent').length, replayed ? 2 : 0);
    }
  }
});

test('packed lost-reply callers keep the sent SDK candidate and only look it up', async t => {
  const sdk = await import('../packages/sdk/index.mjs');
  const {submissionEpoch} = await import('../packages/sdk/submission-fixture.mjs');
  const originalGlobalFetch = globalThis.fetch, packets = [], outcomes = new Map();
  t.after(() => {globalThis.fetch = originalGlobalFetch;});
  const originalFetch = async (url, options) => {
    const operation = new URL(url).pathname.split('/').at(-1), body = JSON.parse(options.body);
    if (operation === 'connect') return Response.json({version: 'actql-client-host/0.1', mode: 'remote', owner: 'remote',
      durability: 'durable', scopeRef: 'packed-loss', capabilities: ['aql-document'], submissionEpoch, limits});
    packets.push({operation, body});
    if (operation === 'lookup-submission') {
      const outcome = outcomes.get(body.submissionRef.nonce); assert(outcome);
      assert.deepEqual(body.submissionRef, outcome.submissionRef);
      return Response.json(outcome);
    }
    if (operation === 'attach') return Response.json({ref: body.ref, durability: 'durable', revision: 1});
    assert.equal(operation, 'submit-named-intent');
    const outcome = {kind: 'ready', submissionRef: body.submissionRef, intentCid: body.intentCid,
      admission: {ref: {namespaceId: 'packed-loss', authorityScopeCid: submissionEpoch.authorityScopeCid,
        runDefinitionCid: 'sha256:' + 'e'.repeat(64)}, durability: 'durable', revision: 1}};
    outcomes.set(body.submissionRef.nonce, outcome);
    return Response.json({kind: 'observed', requestName: body.requestName, intentCid: body.intentCid,
      attemptRef: body.attemptRef, outcome});
  };
  globalThis.fetch = originalFetch;
  const client = await sdk.connect({mode: 'remote', endpoint: 'https://packed.example/', token: 'fixture-token', durability: 'durable'});
  t.after(() => client.close());
  const smoke = actor('smoke.mjs');
  const fragments = [
    'let remoteReplyLost = false;' + between(smoke, 'let remoteReplyLost = false;', "assert.equal((await resumedRemote.wait()).status, 'succeeded');"),
    'let acquiredReplyLost = false;' + between(smoke, 'let acquiredReplyLost = false;', "assert.equal((await recoveredAcquired.wait()).status, 'succeeded');"),
  ];
  for (const fragment of fragments) {
    const before = packets.length;
    await new Function('assert', 'installedRemote', 'document', 'acquiredDocument', 'originalFetch', 'getSubmissionInput',
      'return (async () => {' + fragment + '})();')(assert, client, '{}', '{}', originalFetch, sdk.getSubmissionInput);
    assert.deepEqual(packets.slice(before).map(value => value.operation), ['submit-named-intent', 'lookup-submission', 'attach']);
    assert.deepEqual(packets[before + 1].body.submissionRef, packets[before].body.submissionRef);
    assert.deepEqual(packets[before + 2].body.ref, outcomes.get(packets[before].body.submissionRef.nonce).admission.ref);
  }
});

test('packed restart actors retain complete original submission refs beside their Run refs', async t => {
  const ordinary = await sdkOriginal(t, 'saved-values'), acquired = await sdkOriginal(t, 'saved-acquired', {minimum: 1});
  const saved = new Map();
  for (const [name, paths] of [
    ['smoke.mjs', ['run-submission-ref.json', 'acquired-local-submission-ref.json']],
    ['reserve-remote.mjs', ['restart-remote-submission-ref.json', 'restart-acquired-submission-ref.json']],
  ]) {
    const text = actor(name), parsed = parse(text, {ecmaVersion: 'latest', sourceType: 'module'});
    for (const [index, path] of paths.entries()) {
      const calls = nodes(parsed, node => node.type === 'CallExpression' && node.callee.name === 'writeFileSync' &&
        node.arguments[0]?.value === path);
      assert.equal(calls.length, 1, path);
      const write = (file, bytes, options) => {
        assert.equal(file, path); assert.equal(options.mode, 0o600);
        const expected = index === 0 ? ordinary.original : acquired.original;
        assert.deepEqual(JSON.parse(bytes), expected); saved.set(path, bytes);
      };
      new Function('writeFileSync', 'getSubmissionOutcome', 'execution', 'acquiredLocal', 'acquired',
        text.slice(calls[0].start, calls[0].end))(write, ordinary.sdk.getSubmissionOutcome,
        ordinary.execution, {execution: acquired.execution}, acquired.execution);
    }
  }
  for (const [name, paths] of [
    ['restart.mjs', ['run-submission-ref.json', 'acquired-local-submission-ref.json']],
    ['resume-remote.mjs', ['restart-remote-submission-ref.json', 'restart-acquired-submission-ref.json']],
  ]) {
    const text = actor(name), parsed = parse(text, {ecmaVersion: 'latest', sourceType: 'module'});
    assert.equal(nodes(parsed, node => node.type === 'CallExpression' && node.callee.property?.name === 'lookupRequest').length, 0);
    for (const path of paths) {
      const reads = nodes(parsed, node => node.type === 'CallExpression' && node.callee.name === 'readFileSync' && node.arguments[0]?.value === path);
      assert.equal(reads.length, 1, path);
      const declaration = nodes(parsed, node => node.type === 'VariableDeclarator' &&
        node.init && node.start < reads[0].start && node.end >= reads[0].end);
      assert.equal(declaration.length, 1);
      const restored = new Function('readFileSync', 'return (' + text.slice(declaration[0].init.start, declaration[0].init.end) + ');')(
        (file, encoding) => {assert.equal(encoding, 'utf8'); return saved.get(file);});
      assert.deepEqual(restored, JSON.parse(saved.get(path)));
    }
  }
});

test('packed restart explicitly continues the original submission instead of only observing its name', async t => {
  const text = actor('resume-remote.mjs');
  const parsed = parse(text, {ecmaVersion: 'latest', sourceType: 'module'});
  for (const [name, requestName, parameters] of [
    ['execution', 'packed-restart-before-physical-start', undefined],
    ['acquiredResumed', 'packed-acquired-restart-before-start', {minimum: 1}],
  ]) {
    const f = await sdkOriginal(t, requestName, parameters);
    const declaration = nodes(parsed, node => node.type === 'VariableDeclaration' &&
      node.declarations.some(value => value.id.name === name));
    assert.equal(declaration.length, 1);
    const invoke = new Function('client', 'document', 'acquiredDocument', 'submissionRef', 'acquiredSubmissionRef',
      'return (async () => {' + text.slice(declaration[0].start, declaration[0].end) +
      '\nreturn ' + name + ';})();');
    const before = f.calls.length;
    const replayed = await invoke(f.client, f.document, f.document, f.original, f.original);
    assert.deepEqual(f.calls.slice(before), ['submit-intent']);
    assert.deepEqual(replayed.ref, f.execution.ref);
    assert.deepEqual(f.sdk.getSubmissionOutcome(replayed).submissionRef, f.original);
  }
});

test('packed acquisition inspection consumes the original SDK outcome and existing typed identity projection', async t => {
  const f = await sdkOriginal(t, 'packed-acquired-remote', {minimum: 1});
  const smoke = actor('smoke.mjs'), parsed = parse(smoke, {ecmaVersion: 'latest', sourceType: 'module'});
  const writers = nodes(parsed, node => node.type === 'CallExpression' && node.callee.name === 'writeFileSync' &&
    node.arguments[0]?.value === 'acquired-remote-original.json');
  assert.equal(writers.length, 1, 'The child must retain its actual original outcome beside the original Run ref');
  let saved;
  new Function('writeFileSync', 'acquiredRemote', 'getSubmissionOutcome',
    smoke.slice(writers[0].start, writers[0].end))((file, wire, options) => {
    assert.equal(file, 'acquired-remote-original.json'); assert.equal(options.mode, 0o600); saved = wire;
  }, {execution: f.execution}, f.sdk.getSubmissionOutcome);
  const original = JSON.parse(saved);
  assert.deepEqual(original.submissionRef, f.original);
  assert.deepEqual(original.ref, f.execution.ref);
  assert.notDeepEqual(original.submissionRef, f.sdk.getSubmissionInput(f.execution).submissionRef);
  const imports = nodes(tree, node => node.type === 'VariableDeclarator' && node.id.name === 'installedControl');
  assert.equal(imports.length, 1);
  const installedUrl = imports[0].init.argument.source;
  assert.equal(installedUrl.callee.name, 'pathToFileURL');
  const installedPath = installedUrl.arguments[0];
  assert.equal(installedPath.callee.name, 'join');
  assert.equal(installedPath.arguments[0].name, 'root');
  assert.deepEqual(installedPath.arguments.slice(1).map(node => node.value),
    ['node_modules', '@actql', 'local-node', '_build', 'js', 'release', 'build',
      'connectors_builtin_node', 'connectors_builtin_node.js']);
  const start = source.indexOf('const acquiredOriginal =');
  const end = source.indexOf('await remoteHost.close();', start);
  assert.ok(start >= 0 && end > start);
  const epoch = Object.freeze({fixture: 'typed-original-epoch'}), calls = [];
  const control = {
    clientSubmissionEpoch(...args) {
      calls.push('epoch');
      assert.deepEqual(args, [f.original.epoch.authorityScopeCid, f.original.epoch.epochNonce,
        f.original.epoch.notBefore, f.original.epoch.expiresAt]);
      return epoch;
    },
    clientSubmissionRequestId(value, nonce) {
      calls.push('identity'); assert.equal(value, epoch); assert.equal(nonce, f.original.nonce);
      return 'original-internal-request';
    },
  };
  let inspections = 0;
  const host = {async inspectAcquisition(value) {
    inspections++;
    if (value.principalId !== 'fixture-owner') throw new Error('AcquisitionInspectionDenied');
    assert.deepEqual(value.connection, {mode: 'remote', owner: 'remote'});
    if (value.requestId === 'never-submitted') return {state: 'not_started'};
    assert.equal(value.requestId, 'original-internal-request');
    return {state: 'completed_retained', ref: f.execution.ref};
  }};
  await new Function('assert', 'readFile', 'join', 'root', 'installedControl', 'userInfo', 'remoteHost',
    'return (async () => {' + source.slice(start, end) + '})();')(
    assert, async (path, encoding) => {assert.equal(path, 'fixture-root/acquired-remote-original.json');
      assert.equal(encoding, 'utf8'); return saved;}, (...parts) => parts.join('/'), 'fixture-root',
    control, () => ({username: 'fixture-owner'}), host);
  assert.deepEqual(calls, ['epoch', 'identity']); assert.equal(inspections, 3);
});

for (const hasOriginal of [false, true]) {
  test(`packed restart acquisition inspection ${hasOriginal ? 'uses the saved original' : 'does not inspect before any original exists'}`, async t => {
    const f = await sdkOriginal(t, 'packed-acquired-restart-before-start', {minimum: 1});
    const text = actor('restart-remote-host.mjs');
    const prefix = text.slice(0, text.indexOf('const server ='));
    const parsed = parse(prefix, {ecmaVersion: 'latest', sourceType: 'module'});
    let body = prefix;
    // Evaluate the actual caller with explicit Core/Host/file ports only.
    // This is not a compiled image, original epoch or Host initialization.
    const replacements = nodes(parsed, node => node.type === 'ImportExpression').map(node => {
      const path = node.source.arguments[0];
      assert.equal(node.source.callee.name, 'pathToFileURL'); assert.equal(path.callee.name, 'join');
      assert.deepEqual(path.arguments.slice(1).map(value => value.value),
        ['node_modules', '@actql', 'local-node', '_build', 'js', 'release', 'build',
          'connectors_builtin_node', 'connectors_builtin_node.js']);
      return {start: node.start, end: node.end, replacement: 'control'};
    });
    replacements.push(...parsed.body.filter(node => node.type === 'ImportDeclaration')
      .map(node => ({start: node.start, end: node.end, replacement: ''})));
    for (const node of replacements.sort((a, b) => b.start - a.start)) {
      body = body.slice(0, node.start) + node.replacement + body.slice(node.end);
    }
    const reads = [], projections = [], logs = [], epoch = {}, originalRef = f.execution.ref;
    const control = {
      clientSubmissionEpoch(...args) {
        projections.push('epoch');
        assert.deepEqual(args, [f.original.epoch.authorityScopeCid, f.original.epoch.epochNonce,
          f.original.epoch.notBefore, f.original.epoch.expiresAt]); return epoch;
      },
      clientSubmissionRequestId(value, nonce) {
        projections.push('identity'); assert.equal(value, epoch); assert.equal(nonce, f.original.nonce);
        return 'same-original-private-id';
      },
    };
    let selected, inspections = 0;
    const host = {async inspectAcquisition(value) {
      inspections++; assert.equal(hasOriginal, true, 'No inspection may invent an original at first startup');
      assert.deepEqual(value, {requestId: 'same-original-private-id', principalId: 'fixture-owner',
        connection: {mode: 'remote', owner: 'remote'}});
      return {state: 'completed_retained', ref: originalRef};
    }};
    await new Function('assert', 'readFileSync', 'existsSync', 'join', 'process', 'userInfo',
      'openInstalledRemoteHttpHost', 'control', 'console', 'return (async () => {' + body + '})();')(
      assert, (path, encoding) => {
        reads.push(path); assert.equal(encoding, 'utf8');
        if (path === 'source-profile.json') return JSON.stringify({checkEnvironmentWire:
          JSON.stringify({host_policy_profile: {capacity: {fixture: 'same-host-capacity'}}})});
        if (path === 'remote-authorization.json') return '{}';
        assert.equal(hasOriginal, true);
        if (path === 'restart-acquired-submission-ref.json') return JSON.stringify(f.original);
        assert.equal(path, 'restart-acquired-ref.json'); return JSON.stringify(originalRef);
      }, path => {assert.equal(path, 'restart-acquired-submission-ref.json'); return hasOriginal;},
      (...parts) => parts.join('/'), {cwd: () => 'fixture-root', env: {}}, () => ({username: 'fixture-owner'}),
      async options => {selected = options; return host;}, control, {log: value => logs.push(value)});
    assert.equal(selected.sourceProfilePath, 'fixture-root/source-profile.json');
    assert.deepEqual(selected.hostCapacityPolicy, {fixture: 'same-host-capacity'});
    assert.deepEqual(logs, ['RECOVERY:' + (hasOriginal ? 'completed_retained' : 'not_observed')]);
    assert.equal(inspections, hasOriginal ? 1 : 0);
    assert.deepEqual(projections, hasOriginal ? ['epoch', 'identity'] : []);
    assert.equal(reads.includes('restart-acquired-submission-ref.json'), hasOriginal);
  });
}
