import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
import {parse, type AnyNode, type Node, type Property} from 'acorn';
import {mkdtemp, writeFile, rm, readdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {createLocalReadAuthorizations, createLocalReadConnectionAuthorization} from './local-result-authorization.mjs';
import {canonicalJson, observeInstalledAccount, sourceReadAccountConfiguration} from './local-account-config.mjs';
import {loadExecutionAuthorizationRuntime} from './authorization.mjs';
import {installClientRunInspect} from './client-run-inspect.mjs';

type ConnectionAuthorization = Parameters<typeof createLocalReadConnectionAuthorization>[0];
type ReadOutcome = NonNullable<Parameters<typeof sourceReadAccountConfiguration>[0]['outcome']>;
type TestAccount = {entries: {entry_id: string; outcome: ReadOutcome; operation: {any_of: string[]}}[]};
type HeldOptions = {directory: string; document: string; requestId: string;
  runtimeRootUrl: URL; expressionContractUrl: URL; authorization: {accountConfiguration: string}};
const heldFixture = new URL('../../scripts/fixtures/synthetic-historical-held-values.mjs', import.meta.url);
const {heldValuesProgram, writeSyntheticHistoricalHeldValues}: {
  heldValuesProgram: object;
  writeSyntheticHistoricalHeldValues(options: HeldOptions): Promise<unknown>;
} = await import(heldFixture.href);

function* fixtureNodes(value: unknown): Generator<AnyNode> {
  if (value === null || typeof value !== 'object') return;
  if ('type' in value && typeof value.type === 'string') yield value as AnyNode;
  for (const child of Object.values(value)) yield* fixtureNodes(child);
}

function hasName(value: Node | null | undefined, name: string): boolean {
  return value?.type === 'Identifier' && 'name' in value && value.name === name;
}

function namedProperty(value: AnyNode, name: string): value is Property {
  return value.type === 'Property' && hasName(value.key, name);
}

test('packed Salesforce fixtures grant only the owner original Run and named Result reads', async () => {
  const text = readFileSync(new URL('../../scripts/test-packed-salesforce-source.mjs', import.meta.url), 'utf8');
  const accounts = new Map<string, unknown>();
  for (const node of fixtureNodes(parse(text, {ecmaVersion: 'latest', sourceType: 'module'}))) {
    if (node.type !== 'CallExpression' || !hasName(node.callee, 'canonicalJson')) continue;
    const value = node.arguments[0];
    if (value?.type !== 'ObjectExpression') continue;
    const identifier = value.properties.find((item): item is Property => namedProperty(item, 'account_id'))?.value;
    const id = identifier?.type === 'Literal' ? identifier.value : undefined;
    if (id !== 'packed-account' && id !== 'packed-effect-account') continue;
    accounts.set(id, new Function('orgId', 'composedModel', 'userInfo',
      `return (${text.slice(value.start, value.end)});`)('fixture-org', undefined, () => ({username: 'fixture-owner'})));
  }
  assert.equal(accounts.size, 2);
  const moon = await loadExecutionAuthorizationRuntime();
  for (const [id, account] of accounts) {
    const wire = canonicalJson(account);
    assert.equal(JSON.parse(moon.executionAuthorizationAccountJson(
      moon.executionAuthorizationAdmit(wire))).state, 'admitted');
    const scope = {namespaceId: 'fixture-namespace', authorityScopeCid: 'fixture-scope'};
    const authority = createLocalReadAuthorizations({moon,
      authorization: {accountConfiguration: wire}, principalId: 'fixture-owner', ...scope});
    const request = {principalId: 'fixture-owner', indexKey: scope};
    assert.equal(await authority.run(request), true, id);
    const names = id === 'packed-account' ? ['records'] : ['answer', 'classified', 'records', 'updates'];
    for (const resultName of names) assert.equal(await authority.result({...request, resultName}), true, resultName);
    assert.equal(await authority.result({...request, resultName: 'foreign'}), false);
    assert.equal(await authority.run({...request, principalId: 'foreign'}), false);
    assert.equal(await authority.run({...request, indexKey: {...scope, namespaceId: 'foreign'}}), false);
  }
});

function entrance(authorizeLocalRun: ConnectionAuthorization['authorizeLocalRun']) {
  return createLocalReadConnectionAuthorization({
    checkpointOperation: new Set(['checkpoints']),
    checkpointConnection: value => value.ref === undefined && value.principalId === 'reviewer',
    hostConnection: value => value.principalId === 'person' && value.connection.owner === 'local',
    authorizeLocalRun, namespaceId: 'local', authorityScopeCid: 'sha256:' + '1'.repeat(64),
  });
}
const facts = {principalId: 'person', connection: {mode: 'local', owner: 'local', consentRefs: [], runners: []},
  ref: {namespaceId: 'local', authorityScopeCid: 'sha256:' + '1'.repeat(64),
    runDefinitionCid: 'sha256:' + '2'.repeat(64)}} as const;

// Execute only this original fixture adapter with explicit issuer/Journal
// ports. This is not a real Common, durable Journal or ordinary Host test.
test('cancel fixture publishes its state through the same original Journal frame', () => {
  const text = readFileSync(new URL('./client-cancel-response-loss.fixture.mjs', import.meta.url), 'utf8');
  const properties = [...fixtureNodes(parse(text, {ecmaVersion: 'latest', sourceType: 'module'}))]
    .filter((node): node is Property => namedProperty(node, 'observeRun'));
  assert.equal(properties.length, 1);
  const fn = properties[0].value;
  const original = {runDefinition: {}, resultNames: ['answer'], revision: 12,
    dispatchReserved: true, preDispatchFailureConfirmed: false,
    cancellationRequested: false, physicalStartReserved: true, physicalCloseConfirmed: false};
  const moon = {}, control = {runDefinitionRunId(value: unknown) { assert.equal(value, original.runDefinition); return 'original'; }};
  const state = Object.freeze({run_id: 'original', status: 'running', result_availability: {}});
  const cancellation = Object.freeze({revision: 12, cancellation_requested: false, physical_stop: 'unknown'});
  const failure = new Error('Original Journal publication failure');
  let publishes = 0, reject = false;
  const journal = {
    lookupRunDefinition(ref: unknown, requestControl: unknown, publicationControl: unknown) {
      assert.equal(ref, facts.ref); assert.equal(requestControl, moon); assert.equal(publicationControl, control);
      return original;
    },
    publishRunState(frame: unknown, observed: typeof state, requestControl: unknown, publicationControl: unknown) {
      publishes++;
      assert.equal(frame, original); assert.equal(requestControl, moon); assert.equal(publicationControl, control);
      assert.equal(Object.hasOwn(observed, 'control'), false, 'The Journal owns the same original control projection');
      assert.equal(observed.result_availability, state.result_availability);
      assert.equal(Object.hasOwn(observed, 'revision'), false, 'The Journal alone issues the observation revision');
      if (reject) throw failure;
      return JSON.stringify({...observed, control: cancellation, revision: 19});
    },
  };
  const observe = new Function('assert', 'journal', 'moon', 'publicationControl',
    'issueInstalledUnpublishedRunState', 'issueInstalledRunControlObservation',
    'return function ' + text.slice(fn.start, fn.end))(assert, journal, moon, control, () => state,
    () => assert.fail('The fixture must not repeat the Journal control issuer'));
  const actual = observe({ref: facts.ref});
  assert.equal(publishes, 1); assert.equal(actual.revision, 19);
  assert.deepEqual(actual.control, cancellation); assert.equal(Object.isFrozen(actual), true);
  reject = true;
  assert.throws(() => observe({ref: facts.ref}), error => error === failure);
  assert.equal(publishes, 2);
});

test('historical fixture rejects missing duplicate or nondelegating run entries before state I/O', async () => {
  const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-held-delegate-',
    label: 'Historical write-delegate selection controls'});
  const read = {entry_id: 'read-original', outcome: 'allow'};
  const delegate = {entry_id: 'run-acceptance', outcome: 'delegate'};
  for (const entries of [[read], [read, delegate, delegate],
    [read, {...delegate, outcome: 'allow'}]]) {
    await assert.rejects(writeSyntheticHistoricalHeldValues({directory: join(scratch.path, 'unstarted-state'),
      document: JSON.stringify(heldValuesProgram), requestId: 'unaccepted-fixture-request',
      runtimeRootUrl: new URL('../../', import.meta.url),
      expressionContractUrl: pathToFileURL(join(scratch.path, 'unprovided-contract.json')),
      authorization: {accountConfiguration: JSON.stringify({account_id: 'authored-fixture', entries})}}),
    {code: 'ERR_ASSERTION'});
  }
  assert.deepEqual(await readdir(scratch.path), []);
  await scratch.passed();
});

test('public Run observation entry requires its actual Account read exactly once', async () => {
  let calls = 0;
  const authorize = entrance(async value => {
    calls++;
    assert.equal(value.principalId, facts.principalId);
    assert.deepEqual(value.indexKey, facts.ref);
    return false;
  });
  for (const operation of ['status', 'wait', 'attach', 'run-plan',
    'owner-observations', 'lookup-request', 'lookup-submission'] as const) {
    const before = calls;
    assert.equal(await authorize({...facts, operation}), false);
    assert.equal(calls - before, 1);
  }
});

test('public Result, static checks, Inspect and Checkpoint keep their selected authorization entries', async () => {
  const authorize = entrance(() => assert.fail('a distinct permission owns this operation'));
  for (const operation of ['result-describe', 'read', 'delivery-attempt', 'check', 'plan', 'connect', 'inspect-run'] as const) {
    assert.equal(await authorize({...facts, operation}), true);
  }
  assert.equal(await authorize({...facts, operation: 'status', principalId: 'foreign'}), false);
  const reviewer = {...facts, ref: undefined, principalId: 'reviewer'};
  assert.equal(await authorize({...reviewer, operation: 'connect'}), true);
  assert.equal(await authorize({...reviewer, operation: 'checkpoints'}), true);
  assert.equal(await authorize({...reviewer, operation: 'lookup-submission'}), false);
});

test('actual Account keeps Run-read and named-Result-read distinct and current', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-run-account-'));
  t.after(() => rm(directory, {recursive: true}));
  const accountConfig = join(directory, 'account.json');
  const configuration = (run: ReadOutcome, result: ReadOutcome) => {
    const value: TestAccount = JSON.parse(sourceReadAccountConfiguration({connection: 'local-mock',
      resource: 'run', entryId: 'run-read', outcome: run}));
    value.entries.push(JSON.parse(sourceReadAccountConfiguration({connection: 'local-mock',
      resource: 'result/main', entryId: 'result-read', outcome: result})).entries[0]);
    value.entries.sort((left, right) => left.entry_id < right.entry_id ? -1
      : left.entry_id > right.entry_id ? 1 : 0);
    return JSON.stringify(value);
  };
  await writeFile(accountConfig, configuration('allow', 'deny'), {mode: 0o600});
  const runtime = await loadExecutionAuthorizationRuntime();
  const initial = JSON.parse(runtime.executionAuthorizationAccountJson(
    runtime.executionAuthorizationAdmit(configuration('allow', 'deny'))));
  assert.equal(initial.state, 'admitted', JSON.stringify(initial));
  let evaluations = 0;
  const moon = {...runtime, executionAuthorizationEvaluate(...args: Parameters<typeof runtime.executionAuthorizationEvaluate>) {
    evaluations++;
    return runtime.executionAuthorizationEvaluate(...args);
  }};
  const authority = createLocalReadAuthorizations({moon,
    authorization: {accountConfig, siteKey: 'local-mock'}, principalId: 'person',
    namespaceId: facts.ref.namespaceId, authorityScopeCid: facts.ref.authorityScopeCid});
  const request = {principalId: facts.principalId, indexKey: facts.ref, purpose: 'inspect'};
  assert.equal(await authority.run(request), true);
  assert.equal(evaluations, 1);
  assert.equal(await authority.result({...request, resultName: 'main'}), false);
  assert.equal(evaluations, 2);
  await writeFile(accountConfig, configuration('deny', 'allow'));
  assert.equal(await authority.run(request), false);
  const resultRequest = Object.freeze({...request, resultName: 'main'});
  assert.equal(await authority.result(resultRequest, resultRequest), true);
  let inspectAdmissions = 0;
  const noRead = () => assert.fail('Denied Inspect reached an original read or the sink');
  const inspect = installClientRunInspect({
    authorize(selected, operation) {
      inspectAdmissions++;
      assert.equal(operation.purpose, 'inspect');
      assert.equal(operation.indexKey, selected.ref);
      assert.deepEqual(selected.ref, facts.ref);
      return authority.run(operation, operation);
    },
    authorizeCurrent: (_selected, operation) => authority.runCurrent(operation, operation),
    observeOwners: noRead,
    lookupOriginal: noRead,
    control: {admitRunEvidence: noRead, readCurrentClientRunView: noRead},
  });
  await assert.rejects(inspect({...facts, maxWireBytes: 65536, maxNodes: 10000, maxDepth: 64}, noRead),
    {code: 'RunObservationAccessDenied'});
  assert.equal(inspectAdmissions, 1);
  const before = evaluations;
  await authority.result(resultRequest, resultRequest);
  assert.equal(evaluations, before, 'unchanged internal consumption evaluates nothing again');
  await writeFile(accountConfig, configuration('deny', 'deny'));
  assert.equal(await authority.run(request), false);
  assert.equal(await authority.result(resultRequest, resultRequest), false,
    'the same Account owner already observed this policy change');
  assert.equal(await authority.run({...request, principalId: 'foreign'}), false);
  assert.equal(await authority.run({...request, indexKey: {...facts.ref, namespaceId: 'foreign'}}), false);
  await writeFile(accountConfig, configuration('allow', 'allow'));
  assert.equal(authority.sampleCaptureImmediate(request), false);
  const sample: TestAccount = JSON.parse(configuration('allow', 'allow'));
  const sampleConfiguration: TestAccount = JSON.parse(sourceReadAccountConfiguration({connection: 'local-mock',
    resource: 'sample', entryId: 'sample-access'}));
  const [sampleRead] = sampleConfiguration.entries;
  sample.entries.push(sampleRead);
  await writeFile(accountConfig, canonicalJson(sample));
  assert.equal(authority.sampleCaptureImmediate(request), false, 'Sample read never grants capture');
  sampleRead.operation.any_of = ['capture'];
  await writeFile(accountConfig, canonicalJson(sample));
  assert.equal(authority.sampleCaptureImmediate(request), true);
  sampleRead.outcome = 'deny';
  await writeFile(accountConfig, canonicalJson(sample));
  assert.equal(authority.sampleCaptureImmediate(request), false);

  const controls: TestAccount = JSON.parse(configuration('allow', 'allow'));
  const debug: TestAccount = JSON.parse(sourceReadAccountConfiguration({connection: 'local-mock',
    resource: 'run', entryId: 'debug'}));
  const [debugEntry] = debug.entries;
  debugEntry.operation.any_of = ['resume'];
  controls.entries.unshift(debugEntry);
  await writeFile(accountConfig, canonicalJson(controls));
  assert.equal(authority.resumeImmediate(request), true);
  assert.equal(authority.debugEntryImmediate(request), false, 'Resume and Run read cannot authorize a new Pause');
  debugEntry.operation.any_of = ['pause'];
  await writeFile(accountConfig, canonicalJson(controls));
  assert.equal(authority.debugEntryImmediate(request), true);
  assert.equal(authority.debugEntryImmediate({principalId: 'foreign'}), false);
  debugEntry.outcome = 'deny';
  await writeFile(accountConfig, canonicalJson(controls));
  assert.equal(authority.debugEntryImmediate(request), false, 'new entry rechecks the current Account');
});

test('Sheets public fixture admits only owner Run and answer reads while keeping business denial', async () => {
  const fixture = new URL('../connectors/sheets/test/sheets-public-acceptance.fixture.mts', import.meta.url);
  const source = stripTypeScriptTypes(readFileSync(fixture, 'utf8'));
  const declarations = new Map<string, string>();
  for (const node of fixtureNodes(parse(source, {ecmaVersion: 'latest', sourceType: 'module'}))) {
    if (node.type !== 'VariableDeclarator' || node.id.type !== 'Identifier' || !node.init ||
        !['entry', 'configuration'].includes(node.id.name)) continue;
    assert.equal(declarations.has(node.id.name), false);
    declarations.set(node.id.name, source.slice(node.init.start, node.init.end));
  }
  assert.equal(declarations.size, 2);
  const configuration = new Function('canonicalJson', 'owner',
    `const entry=(${declarations.get('entry')}); return (${declarations.get('configuration')});`)(canonicalJson, 'fixture-owner');
  const moon = await loadExecutionAuthorizationRuntime();
  const scope = {namespaceId: 'fixture-namespace', authorityScopeCid: 'fixture-scope'};
  for (const commit of ['delegate', 'deny']) {
    const wire = configuration('sheets:fixture/book', commit, true);
    assert.equal(JSON.parse(moon.executionAuthorizationAccountJson(
      moon.executionAuthorizationAdmit(wire))).state, 'admitted');
    const body: TestAccount = JSON.parse(wire);
    assert.equal(body.entries.find(entry => entry.entry_id === 'range-effect')?.outcome, commit);
    for (const principalId of ['fixture-owner', 'foreign-reader']) {
      const authority = createLocalReadAuthorizations({moon, authorization: {accountConfiguration: wire}, principalId, ...scope});
      const facts = {principalId, indexKey: scope};
      assert.equal(await authority.run(facts), principalId === 'fixture-owner');
      assert.equal(await authority.result({...facts, resultName: 'answer'}), principalId === 'fixture-owner');
      assert.equal(await authority.result({...facts, resultName: 'unrelated'}), false);
    }
  }
});

const checkpointWrapper = readFileSync(new URL('../../scripts/test-packed-client-checkpoint.mjs', import.meta.url), 'utf8');
const checkpointWrapperAst = parse(checkpointWrapper, {ecmaVersion: 'latest', sourceType: 'module'});
function checkpointActor(name: 'client.mjs' | 'remote-host.mjs'): string {
  const recipes = [...fixtureNodes(checkpointWrapperAst)].flatMap(node => {
    if (node.type !== 'AwaitExpression' || node.argument.type !== 'CallExpression' ||
        !hasName(node.argument.callee, 'writeFile')) return [];
    const [destination, template] = node.argument.arguments;
    return destination?.type === 'CallExpression' &&
      destination.arguments.some(arg => arg.type === 'Literal' && arg.value === name) &&
      template?.type === 'TemplateLiteral' ? [template] : [];
  });
  assert.equal(recipes.length, 1, 'Select the actual installed Host actor');
  const [template] = recipes;
  const head = template.quasis[0].value.cooked;
  assert(typeof head === 'string');
  if (template.expressions.length === 0) return head;
  assert.equal(name, 'remote-host.mjs');
  assert.equal(template.expressions.length, 1);
  const expression = template.expressions[0];
  assert.equal(expression.type, 'CallExpression');
  assert.equal(expression.optional, false);
  assert.equal(expression.callee.type, 'MemberExpression');
  assert.equal(expression.callee.computed, false);
  assert(hasName(expression.callee.object, 'JSON'));
  assert(hasName(expression.callee.property, 'stringify'));
  assert.equal(expression.arguments.length, 1);
  assert.equal(expression.arguments[0].type, 'Identifier');
  assert.equal(expression.arguments[0].name, 'hostCapacityPolicy');
  const policy = JSON.parse(readFileSync(new URL('../../spec/local-check-environment.json',
    import.meta.url), 'utf8')).host_policy_profile.capacity;
  const tail = template.quasis[1].value.cooked;
  assert(typeof tail === 'string');
  return head + JSON.stringify(policy) + tail;
}

test('packed Checkpoint fixture separates owner observation from business authorization', async () => {
  const hostSource = checkpointActor('remote-host.mjs');
  const hostAst = parse(hostSource, {ecmaVersion: 'latest', sourceType: 'module'});
  const declaration = hostAst.body.flatMap(node => node.type === 'VariableDeclaration'
    ? node.declarations : []).find(node => hasName(node.id, 'configuration'));
  assert.ok(declaration?.init);
  const configuration = new Function('outcome', 'canonical', 'userInfo',
    `return (${hostSource.slice(declaration.init.start, declaration.init.end)});`);
  const moon = await loadExecutionAuthorizationRuntime();
  const scope = {namespaceId: 'fixture-namespace', authorityScopeCid: 'fixture-scope'};
  for (const outcome of ['allow', 'deny', 'delegate', 'missing']) {
    const wire = configuration(outcome, canonicalJson, () => ({username: 'fixture-owner'}));
    const authorization = wire === undefined ? {} : {accountConfiguration: wire};
    const account = observeInstalledAccount(moon, authorization);
    if (wire !== undefined) {
      assert.equal(JSON.parse(moon.executionAuthorizationAccountJson(account)).state, 'admitted');
    }
    const authority = createLocalReadAuthorizations({moon, principalId: 'fixture-owner', ...scope,
      authorization});
    const facts = {principalId: 'fixture-owner', indexKey: scope};
    assert.equal(await authority.run(facts), outcome !== 'missing', outcome);
    assert.equal(await authority.result({...facts, resultName: 'answer'}), outcome !== 'missing', outcome);
    assert.equal(await authority.result({...facts, resultName: 'unrelated'}), false);
    assert.equal(await authority.run({...facts, principalId: 'reviewer-principal'}), false);
    if (wire !== undefined) {
      for (const resource of ['duckdb-acquired', 'source-free-values']) {
        const decision = moon.executionAuthorizationEvaluate(account, 'fixture-owner',
          'actql-remote-host', resource, 'write');
        assert.equal(JSON.parse(moon.executionAuthorizationEvaluationJson(decision)).outcome, outcome);
      }
    }
  }
});

// Execute the authored packed refusal actor and its actual scenario wiring.
// These explicit ports test fixture expectations, not a packed Host/runtime.
test('packed Checkpoint refusal actor preserves missing-Account lookup denial only', async () => {
  type RefusalEnv = {CODE: string; LOOKUP?: 'allowed' | 'denied'};
  type Submission = {nonce: string};
  type Refusal = {kind: string; submissionRef: Submission; problem: {code: string}};
  type ActorClient = {
    newSubmission(): Submission;
    startSource(): Promise<never>;
    lookupSubmission(ref: Submission): Promise<Refusal>;
    checkpoints(): Promise<{items: unknown[]}>;
  };
  type Actor = (assertions: typeof assert, as: (token: string) => Promise<ActorClient>, requestId: string,
    text: string, outcome: (error: {refusal: Refusal}) => Refusal, process: {env: RefusalEnv}) => () => Promise<void>;
  type Matrix = (
    withHost: (outcome: string, env: {OUTCOME: string}, action: (token: string) => unknown) => Promise<void>,
    client: (outcome: string, step: string, args: string[], env: RefusalEnv) => Promise<void>,
    assertions: typeof assert, counts: () => Promise<unknown[]>, none: unknown[]) => Promise<void>;
  const clientSource = checkpointActor('client.mjs');
  const clientAst = parse(clientSource, {ecmaVersion: 'latest', sourceType: 'module'});
  const steps = clientAst.body.flatMap(node => node.type === 'VariableDeclaration'
    ? node.declarations : []).find(node => hasName(node.id, 'steps'));
  assert(steps?.init?.type === 'ObjectExpression');
  const refused = steps.init.properties.find((node): node is Property => namedProperty(node, 'refused'))?.value;
  assert(refused);
  const actor = new Function('assert', 'as', 'requestId', 'text', 'getSubmissionOutcome', 'process',
    'return async function ' + clientSource.slice(refused.start, refused.end)) as Actor;
  const scenarios = [...fixtureNodes(checkpointWrapperAst)].filter(node => {
    if (node.type !== 'ForOfStatement' || node.left.type !== 'VariableDeclaration') return false;
    const id = node.left.declarations[0]?.id;
    return id?.type === 'ArrayPattern' &&
      id.elements.map(item => item?.type === 'Identifier' ? item.name : undefined).join(',') === 'outcome,code,lookup';
  });
  assert.equal(scenarios.length, 1);
  const calls: {outcome: string; env: RefusalEnv}[] = [];
  const run = async (outcome: string, env: RefusalEnv, lookupFailure?: string) => {
    const submissionRef = {nonce: outcome + '-a'};
    const refusal = {kind: 'preparation_failed', submissionRef, problem: {code: env.CODE}};
    const visited: string[] = [];
    const client: ActorClient = {
      newSubmission: () => submissionRef,
      async startSource() { throw {code: 'SubmissionPreparationFailed', refusal}; },
      async lookupSubmission(ref) {
        assert.equal(ref, submissionRef); visited.push('lookup');
        // Independent fixture contract: missing Account never supplies Run-read.
        const code = lookupFailure ?? (outcome === 'missing' ? 'ClientConnectionDenied' : undefined);
        if (code) throw Object.assign(new Error(code), {code});
        return refusal;
      },
      async checkpoints() {visited.push('checkpoints'); return {items: []};},
    };
    await actor(assert, async token => {
      assert.equal(token, 'owner-token'); return client;
    }, submissionRef.nonce, 'original source', error => error.refusal, {env})();
    assert.deepEqual(visited, ['lookup', 'checkpoints']);
    calls.push({outcome, env});
  };
  const matrix = new Function('withHost', 'client', 'assert', 'counts', 'none',
    'return (async () => {' + checkpointWrapper.slice(scenarios[0].start, scenarios[0].end) + '})();') as Matrix;
  await matrix(async (outcome, hostEnv, action) => {
    assert.equal(hostEnv.OUTCOME, outcome); await action(outcome);
  }, async (outcome, step, args, env) => {
    assert.equal(step, 'refused'); assert.deepEqual(args, [outcome + '-a']);
    await run(outcome, env);
  }, assert, async () => [], []);
  assert.deepEqual(calls, [
    {outcome: 'deny', env: {CODE: 'ACTQL_E_ACCOUNT_DENIED', LOOKUP: 'allowed'}},
    {outcome: 'missing', env: {CODE: 'ACTQL_E_ACCOUNT_CONFIG_INVALID', LOOKUP: 'denied'}},
  ]);
  for (const CODE of ['ACTQL_E_DELEGATION_REJECTED', 'ACTQL_E_DELEGATION_UNAVAILABLE']) {
    await run('delegate', {CODE});
  }
  await assert.rejects(run('missing', calls[1].env, 'ClientHostFailure'),
    {code: 'ERR_ASSERTION'}, 'A different Host failure is not the expected permission refusal');
  await assert.rejects(run('deny', calls[0].env, 'ClientConnectionDenied'),
    {code: 'ClientConnectionDenied'}, 'Authorized refusal recovery must still succeed');
});
