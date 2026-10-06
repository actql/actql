// Public check outcome and disclosure, through the public Local and HTTP
// entrances of installed Hosts with a real DuckDB source profile. The
// environment, aliases and account configurations are independent fixtures;
// nothing is read back from the implementation to build an expectation.
import './client-check-composition.test.mjs';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {createRequire} from 'node:module';
import {createHash, createHmac, generateKeyPairSync} from 'node:crypto';
import {userInfo} from 'node:os';
import {DatabaseSync} from 'node:sqlite';
import {join} from 'node:path';
import test, {after} from 'node:test';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {connect, getCheckInput, resolveCheckLocation, resolveCheckTextRange, explainCheckReason} from '../../packages/sdk/index.mjs';
import * as frontierSDK from '../../packages/sdk/index.mjs';

import * as sdk from '../../packages/sdk/index.mjs';
import {validCheckOutcome, checkReasonSchemaCid, checkOutcomeSchemaCid} from '../../packages/client-wire/index.mjs';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';
import {createNodeAuthorizationGate} from './authorization.mjs';
import {installNodeClientCheck} from './client-check.mjs';
import {connectEmbeddedLocal, openInstalledRemoteHttpHost} from
  './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';
import {sourceAliasPublication} from './source-alias-publication.mjs';
import {connectInProcess} from '../../packages/sdk/host-port.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {createClientHttpHandler} from './client-http.mjs';

const repository = fileURLToPath(new URL('../../', import.meta.url));
const scratch = join(repository, '_build', 'client-check');
await mkdir(scratch, {recursive: true});
const tlsRoot = await mkdtemp(join(scratch, 'tls-'));
execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
  '-keyout', 'remote.key', '-out', 'remote.crt', '-days', '1',
  '-subj', '/CN=localhost',
  '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'],
{cwd: tlsRoot, stdio: 'ignore'});
const tlsKey = await readFile(join(tlsRoot, 'remote.key'));
const tlsCertificate = await readFile(join(tlsRoot, 'remote.crt'));
setDefaultCACertificates([...getCACertificates('default'),
  tlsCertificate.toString('utf8')]);
after(() => rm(tlsRoot, {recursive: true, force: true}));
const owner = userInfo().username;
const {DuckDBInstance} = createRequire(join(repository,
  'adapters/connectors/duckdb/node/package.json'))('@duckdb/node-api');

const sourceEnvironment = JSON.parse(await readFile(join(repository,
  'adapters/host-node/fixtures/query-amount-environment.json'), 'utf8'));
const view = sourceEnvironment.source_views[0];
const sourceRef = 'connector://crm/main/r#v';
const alias = Object.freeze({name: 'records', sourceRef,
  sourceViewContractCid: view.contract_cid,
  schemaContractCid: view.output.schema.cid});
const account = outcome => canonicalJson({
  version: 'actql-execution-account-config/0.1', account_id: 'source-account',
  entries: [{entry_id: 'source-read', outcome, principal: {all: true},
    connection: {all: true}, resource: {all: true},
    operation: {any_of: ['read']}, exclusions: []}]});

// One check of a query over the `records` name with one declared parameter.
const query = 'SELECT id FROM records WHERE amount >= @minimum';
const declarations = Object.freeze({minimum: {type: 'number'}});
const expectedNumberAdmission = Object.freeze({kind: 'parameter_declaration',
  contract_schema_cid: 'sha256:02859499357530af0ae58e4f2958d1c8fa48f957b86b0a2976dad43bed99b551',
  contract: {nullable: false, type: 'number'},
  constraints: [{kind: 'numeric', path: [], integer: false}], supplier: 'caller'});
const requests = Object.freeze({
  // A real checker-detected violation of the caller's own input: the supplied
  // value does not satisfy its declared type.
  violation: {text: query, parameters: {minimum: 'twenty'}},
  satisfied: {text: query, parameters: {minimum: 20}},
  // No value for a declared parameter: a limit of this bound-input check.
  missing: {text: query, parameters: null},
});
const check = (client, name) => client.check(requests[name].text, {
  format: 'sql', parameterDeclarations: declarations,
  parameters: requests[name].parameters});

// Host configurations. `absent` publishes no query name; `denied` publishes
// it and its source's own account denies the read. Everything else is equal.
const configurations = Object.freeze({
  absent: {readOutcome: 'deny', aliases: []},
  denied: {readOutcome: 'deny', aliases: [alias]},
  allowed: {readOutcome: 'allow', aliases: [alias]},
  undecidable: {readOutcome: 'delegate', aliases: [alias]},
});

async function installedSource(root, {readOutcome, aliases,
  environment = sourceEnvironment}) {
  const database = join(root, 'records.duckdb');
  const instance = await DuckDBInstance.create(database);
  const connection = await instance.connect();
  try {
    await connection.run('CREATE TABLE records(id DOUBLE, amount DOUBLE)');
  } finally {
    connection.closeSync();
    instance.closeSync();
  }
  const path = join(root, 'source-profile.json');
  await writeFile(path, JSON.stringify({
    acquisitionPlanning: {policy: 'priority', priority: ['nativeQuery', 'broadQuery']},
    version: 'actql-installed-duckdb-source/0.1',
    database, schema: 'main', table: 'records',
    sourceRef: environment.schema_snapshots[0].source_ref,
    queryAliases: aliases,
    checkEnvironmentWire: canonicalText(environment),
    accountConfigurationWire: account(readOutcome),
  }));
  return path;
}

async function installedConfigurations(root, configuration) {
  if (!Array.isArray(configuration)) {
    return {sourceProfilePath: await installedSource(root, configuration)};
  }
  if (configuration.length === 0) return {};
  const paths = [];
  for (const [index, source] of configuration.entries()) {
    const directory = join(root, `source-${index}`);
    await mkdir(directory);
    paths.push(await installedSource(directory, source));
  }
  return paths.length === 1 ? {sourceProfilePath: paths[0]}
    : {sourceProfilePaths: paths};
}

// Guard only after fixture creation: checking may consult authorization but
// must never open an installed source, admit a Run, or reach dispatch.
function observeCheckOnly(t, root) {
  const original = DuckDBInstance.create;
  let sourceOpens = 0, dispatches = 0;
  t.mock.method(DuckDBInstance, 'create', async function(database, ...args) {
    if (typeof database === 'string' && database.startsWith(root) &&
        database.endsWith('records.duckdb')) sourceOpens++;
    return Reflect.apply(original, this, [database, ...args]);
  });
  return {
    beforeDispatch: () => { dispatches++; throw new Error('UnexpectedCheckDispatch'); },
    assertNoExecution: () => {
      assert.equal(sourceOpens, 0, 'check opens no source-row provider');
      assert.equal(dispatches, 0, 'check dispatches no Run');
      const journal = new DatabaseSync(join(root, 'state', 'requests',
        'client-requests.sqlite3'), {readOnly: true});
      try {
        assert.equal(journal.prepare('SELECT count(*) AS count FROM client_requests')
          .get().count, 0, 'check admits no Run');
      } finally { journal.close(); }
    },
  };
}

async function localClient(t, configuration) {
  const root = await mkdtemp(join(scratch, 'local-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const sourceInstallation = await installedConfigurations(root, configuration);
  const observation = observeCheckOnly(t, root);
  const client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
    installation: {directory: join(root, 'state'), ...sourceInstallation}});
  return {check: client.check, assertNoExecution: observation.assertNoExecution};
}

async function httpClient(t, configuration, mutateCheckReply) {
  const root = await mkdtemp(join(scratch, 'http-'));
  const sourceInstallation = await installedConfigurations(root, configuration);
  const observation = observeCheckOnly(t, root);
  const host = await openInstalledRemoteHttpHost({
    directory: join(root, 'state'), beforeDispatch: observation.beforeDispatch,
    authenticate: header => header === 'Bearer owner-token' ? owner
      : undefined,
    ...sourceInstallation,
  });
  const server = createServer({key: tlsKey, cert: tlsCertificate},
    (request, response) => {
      if (mutateCheckReply && request.url.endsWith('/check')) {
        const end = response.end.bind(response);
        response.end = body => end(JSON.stringify(
          mutateCheckReply(JSON.parse(body))));
      }
      return host.handler(request, response);
    });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(async () => {
    server.closeAllConnections?.();
    await new Promise(resolve => server.close(resolve));
    await host.close();
    await rm(root, {recursive: true, force: true});
  });
  const endpoint = `https://127.0.0.1:${server.address().port}/`;
  const client = await connect({mode: 'remote', endpoint,
    token: 'owner-token'});
  // The raw public route, for status and body shape.
  const post = body => fetch(new URL('actql/client/0.1/check', endpoint), {
    method: 'POST', headers: {authorization: 'Bearer owner-token',
      'content-type': 'application/json'},
    body: JSON.stringify({connection: {mode: 'remote', owner: 'remote',
      runners: [], consentRefs: []}, ...body})});
  return Object.freeze({check: client.check, post,
    assertNoExecution: observation.assertNoExecution});
}

const leftEnvironment = JSON.parse(await readFile(join(repository,
  'adapters/host-node/fixtures/two-source/left.environment.json'), 'utf8'));
const leftConfiguration = {...configurations.allowed, environment: leftEnvironment};
const rightEnvironment = JSON.parse(await readFile(join(repository,
  'adapters/host-node/fixtures/two-source/right.environment.json'), 'utf8'));
const rightView = rightEnvironment.source_views[0];
const rightAlias = Object.freeze({name: 'other_records',
  sourceRef: rightEnvironment.schema_snapshots[0].source_ref,
  sourceViewContractCid: rightView.contract_cid,
  schemaContractCid: rightView.output.schema.cid});
const rightConfiguration = name => ({...configurations[name],
  environment: rightEnvironment,
  aliases: name === 'absent' ? [] : [rightAlias]});

const entrances = Object.freeze({local: localClient, http: httpClient});

for (const [entrance, open] of Object.entries(entrances)) {
  test(`${entrance}: typed Requirement frontiers retain context and ignore presentation order`, async t => {
    let responses = 0;
    const reorder = outcome => {
      if (++responses === 2 && outcome.outcome === 'completed') {
        const requirements = outcome.report.requirements.reverse();
        outcome.report.requirements = [...requirements, requirements[0]];
        for (const reason of requirements) {
          reason.facts = {parameter: reason.facts.parameter, expected_type: reason.facts.expected_type,
            ...(reason.facts.admission === undefined ? {} : {admission: reason.facts.admission})};
          delete reason.location;
        }
      }
      return outcome;
    };
    const client = await open(t, configurations.denied, reorder);
    const text = 'SELECT @a AS first, @b AS second';
    const options = {format: 'sql', parameterDeclarations: {
      a: {type: 'number'}, b: {type: 'string'}}, parameters: {}};
    const first = await client.check(text, options);
    const second = await client.check(text, options);
    // Independent conditions come from the submitted declarations, not from
    // the SDK frontier normalizer or a replayed product expectation.
    for (const outcome of [first, second]) {
      assert.equal(outcome.outcome, 'completed');
      assert.equal(outcome.report.verdict, 'undetermined');
      assert.deepEqual([...new Set(outcome.report.requirements.map(reason =>
        reason.facts.parameter + ':' + reason.facts.expected_type))].sort(),
      ['a:number', 'b:string']);
      assert.deepEqual(outcome.report.coverage, {
        limits: [{code: 'bound_values_missing'}], unresolved: []});
    }
    assert.equal(first.report.context_ref, second.report.context_ref);
    assert.equal(typeof frontierSDK.getCheckRequirementFrontier, 'function', '[check-mutation:frontier-api]');
    const frontier = frontierSDK.getCheckRequirementFrontier(first);
    assert.deepEqual(frontier.scope, {kind: 'bound_input'});
    assert.equal(frontier.contextRef, first.report.context_ref);
    assert.equal(frontier.reasonSchemaCid, checkReasonSchemaCid);
    assert.equal(frontier.requirements.length, 2);
    assert.equal(Object.isFrozen(frontier.requirements), true);
    assert.equal(frontierSDK.equalCheckRequirementFrontiers(first, second), true, '[check-mutation:frontier-order]');
    const changed = await client.check(text, {...options, parameters: {a: 1}});
    assert.equal(changed.report.verdict, 'undetermined');
    assert.deepEqual(changed.report.requirements.map(reason => reason.facts),
      [{parameter: 'b', expected_type: 'string', admission: {
        kind: 'parameter_declaration', supplier: 'caller',
        contract: {type: 'string', nullable: false}, constraints: [],
        contract_schema_cid: 'sha256:02859499357530af0ae58e4f2958d1c8fa48f957b86b0a2976dad43bed99b551'}}]);
    assert.notEqual(changed.report.context_ref, first.report.context_ref);
    assert.equal(frontierSDK.equalCheckRequirementFrontiers(first, changed), false, '[check-mutation:frontier-context]');
    const anotherBinding = await client.check(text, {...options, parameters: {a: 2}});
    assert.notEqual(anotherBinding.report.context_ref, changed.report.context_ref);
    assert.equal(frontierSDK.equalCheckRequirementFrontiers(changed, anotherBinding), false, '[check-mutation:frontier-context]');
    assert.equal(frontierSDK.equalCheckRequirementFrontiers(first, structuredClone(first)), undefined,
      '[check-mutation:frontier-bound]');
    assert.equal(first.report.verdict, 'undetermined');
    client.assertNoExecution();
  });

  test(`${entrance}: supplementation checks stop unchanged frontiers and bound changing contexts`, async t => {
    const client = await open(t, configurations.denied);
    let calls = 0;
    const counted = {check: (...args) => { calls++; return client.check(...args); }};
    const text = 'SELECT @a AS first, @b AS second';
    const options = {format: 'sql', parameterDeclarations: {
      a: {type: 'number'}, b: {type: 'string'}}, parameters: {}};
    assert.equal(typeof frontierSDK.createCheckSupplementationSession, 'function', '[check-mutation:frontier-session-api]');
    const repeated = frontierSDK.createCheckSupplementationSession(counted, {maxAttempts: 5});
    const first = await repeated.check(text, options);
    assert.deepEqual(first.decision, {kind: 'more_checks'});
    const second = await repeated.check(text, options);
    assert.deepEqual(second.decision, {kind: 'stop', reason: 'unchanged_frontier'}, '[check-mutation:frontier-stalled]');
    await assert.rejects(repeated.check(text, {...options, parameters: {a: 1, b: 'bound'}}),
      {code: 'CheckSupplementationStopped'});
    assert.equal(calls, 2, '[check-mutation:frontier-no-repeat]');
    const changing = frontierSDK.createCheckSupplementationSession(counted, {maxAttempts: 3});
    for (const a of [1, 2, 3]) {
      const result = await changing.check(text, {...options, parameters: {a}});
      assert.equal(result.outcome.report.verdict, 'undetermined');
      assert.equal(result.attempts, a, '[check-mutation:frontier-budget-count]');
      assert.deepEqual(result.decision, a < 3 ? {kind: 'more_checks'}
        : {kind: 'stop', reason: 'attempt_budget'}, '[check-mutation:frontier-budget]');
    }
    await assert.rejects(changing.check(text, {...options, parameters: {a: 4}}),
      {code: 'CheckSupplementationStopped'});
    assert.equal(calls, 5, '[check-mutation:frontier-no-repeat]');
    const invalid = frontierSDK.createCheckSupplementationSession(counted, {maxAttempts: 3});
    const result = await invalid.check(text + ' FROM records', {...options, parameters: {a: 'wrong', b: 'bound'}});
    assert.equal(result.outcome.report.verdict, 'invalid');
    assert.deepEqual(result.outcome.report.reasons.map(({code, facts}) => ({code, facts})),
      [{code: 'supplied_value_type_mismatch',
        facts: {parameter: 'a', expected_type: 'number', actual_type: 'string'}}]);
    assert.deepEqual(result.outcome.report.requirements, []);
    assert.deepEqual(result.outcome.report.coverage, {limits: [],
      unresolved: [{boundary: 'source_resolution', reason: 'unresolved_protected'}]});
    assert.deepEqual(result.decision, {kind: 'stop', reason: 'no_known_supplement'});
    const complete = frontierSDK.createCheckSupplementationSession(counted, {maxAttempts: 3});
    const verified = await complete.check(text, {...options, parameters: {a: 1, b: 'bound'}});
    assert.equal(verified.outcome.report.verdict, 'verified');
    assert.deepEqual(verified.decision, {kind: 'stop', reason: 'no_known_supplement'});
    assert.equal(first.outcome.report.verdict, 'undetermined');
    client.assertNoExecution();
  });
}
for (const entrance of ['local', 'http']) {
  test(`${entrance}: incomparable Requirement reports stop read-only supplementation`, async t => {
    const options = {format: 'sql', parameterDeclarations: {a: {type: 'number'}}, parameters: {}};
    for (const mode of ['unknown', 'partial', 'malformed']) {
      let calls = 0;
      const client = await contextClient(t, entrance, absentEnvironment, {mutateCheckReply(outcome) {
        calls++;
        if (mode === 'unknown') outcome.report.requirements[0].code = 'future_requirement';
        else if (mode === 'partial') return {version: outcome.version,
          reason_schema_cid: outcome.reason_schema_cid, outcome_schema_cid: outcome.outcome_schema_cid, outcome: 'failed', correlation_ref: 'corr:fixture',
          problem: {code: 'check_internal'}, partial_report: outcome.report};
        else outcome.report.requirements[0].facts.expected_type = 42;
        return outcome;
      }});
      const session = frontierSDK.createCheckSupplementationSession(client, {maxAttempts: 3});
      if (mode !== 'partial') {
        // The existing closed Requirement schema refuses unknown codes and
        // malformed known facts before the Host publishes a check envelope.
        await assert.rejects(session.check('SELECT @a AS first', options),
          {code: entrance === 'local' ? 'InvalidClientHostCheckOutcome' : 'ClientHostFailure'});
      } else {
        const result = await session.check('SELECT @a AS first', options);
        assert.equal(result.outcome.outcome, 'failed');
        assert.equal((result.outcome.report ?? result.outcome.partial_report).verdict, 'undetermined');
        assert.equal(frontierSDK.getCheckRequirementFrontier(result.outcome), undefined,
          '[check-mutation:frontier-unavailable]');
        assert.deepEqual(result.decision, {kind: 'stop', reason: 'frontier_unavailable'});
        await assert.rejects(session.check('SELECT @a AS first', options),
          {code: 'CheckSupplementationStopped'});
      }
      assert.equal(calls, 1);
    }
  });
}

const contextRef = /^ctx:[0-9a-f]{64}$/u;
// Context references are keyed per Host installation: they are compared
// within one Host here, and across Hosts by the fixed-key tests below.
const withoutContext = (outcome, expectedAssertion) => {
  assert.equal(outcome.outcome, 'completed', expectedAssertion === undefined
    ? undefined : `[check-mutation:${expectedAssertion}]`);
  assert.match(outcome.report.context_ref, contextRef);
  assert.equal(outcome.reason_schema_cid, checkReasonSchemaCid);
  assert.equal(outcome.outcome_schema_cid, checkOutcomeSchemaCid);
  assert.equal(outcome.report.inputs[0].document_id, 'source');
  for (const input of outcome.report.inputs) assert.match(input.revision, /^rev:[0-9a-f]{64}$/u);
  // These original fixtures compare classification/coverage. Exact public
  // locations and retained inputs have their own independent vectors below.
  const {reason_schema_cid, outcome_schema_cid, ...envelope} = outcome;
  const {inputs, requirements, ...report} = outcome.report;
  return {...envelope, report: {...report, context_ref: '<ctx>',
    reasons: report.reasons.map(({location, facts, ...reason}) =>
      reason.code === 'supplied_value_type_mismatch' ? {code: 'supplied_value_invalid'} : reason)}};
};

const protectedSource = [{boundary: 'source_resolution',
  reason: 'unresolved_protected'}];

for (const [entrance, open] of Object.entries(entrances)) {
  test(`${entrance}: complete Programs reject unused Parameter declarations`, async t => {
    const clients = [];
    for (const configuration of [configurations.absent, configurations.denied,
      configurations.allowed]) clients.push(await open(t, configuration));
    // Usage is the common Owner's complete Program decision. A literal default
    // supplies a value but does not make an otherwise unused declaration used.
    for (const format of ['sql', 'aql-text']) {
      for (const options of [
        {parameterDeclarations: {minimum: {type: 'number', default: 7}}},
        {parameterDeclarations: {minimum: {type: 'number'}}, parameters: {minimum: 7}},
      ]) {
        for (const client of clients) {
          const outcome = await client.check('SELECT 1 AS n', {format, ...options});
          assert.equal(outcome.outcome, 'completed');
          assert.equal(outcome.report.verdict, 'invalid', '[check-mutation:unused-verdict]');
          const declarationInput = getCheckInput(outcome, 'parameter_declarations');
          assert.deepEqual(outcome.report.reasons, [{code: 'parameter_unused',
            facts: {parameter: 'minimum'}, location: {kind: 'structured',
              document_id: 'parameter_declarations', revision: declarationInput.revision,
              pointer: '/minimum'}}],
            '[check-mutation:unused-reason]');
          assert.deepEqual(outcome.report.coverage, {limits: [], unresolved: []});
          assert.deepEqual(outcome.report.requirements, []);
          assert.equal(getCheckInput(outcome, 'source').text, 'SELECT 1 AS n');
          assert.equal(explainCheckReason(outcome.report.reasons[0]).kind, 'known');
          const location = outcome.report.reasons[0].location;
          assert.equal(resolveCheckLocation(outcome, location).input, declarationInput);
          assert.equal(resolveCheckLocation(outcome, {...location,
            revision: `rev:${'0'.repeat(64)}`}), undefined);
          assert.equal(resolveCheckLocation(structuredClone(outcome), location), undefined);
          assert.equal(getCheckInput(structuredClone(outcome), 'parameter_declarations'), undefined);
          const corrected = await client.check('SELECT @minimum AS n', {format, ...options});
          assert.equal(corrected.report.verdict, 'verified');
          assert.deepEqual(corrected.report.reasons, []);
        }
      }
    }
    for (const client of clients) client.assertNoExecution();
  });

  test(`${entrance}: unused Parameter explanations retain original custody without exposing values`, async t => {
    const client = await open(t, configurations.allowed);
    const text = "-- café cafe\u0301 😀\r\nSELECT 1 AS n";
    const parameterDeclarations = {unused: {type: 'string', default: 'private-default-cafe\u0301\r\n'}};
    const original = structuredClone(parameterDeclarations);
    const outcome = await client.check(text, {format: 'sql', parameterDeclarations});
    parameterDeclarations.unused.default = 'edited-after-check';
    const input = getCheckInput(outcome, 'parameter_declarations');
    assert.deepEqual(input.value, original);
    assert.equal(getCheckInput(outcome, 'source').text, text);
    assert.equal(outcome.report.verdict, 'invalid', '[check-mutation:unused-custody-verdict]');
    assert.deepEqual(outcome.report.reasons, [{code: 'parameter_unused', facts: {parameter: 'unused'},
      location: {kind: 'structured', document_id: 'parameter_declarations',
        revision: input.revision, pointer: '/unused'}}], '[check-mutation:unused-custody-reason]');
    assert.equal(JSON.stringify(outcome).includes('private-default'), false,
      '[check-mutation:unused-disclosure]');
    assert.deepEqual(explainCheckReason(outcome.report.reasons[0]), {kind: 'known',
      summary: 'A declared parameter is not used by the complete Program.',
      hint: 'Remove the unused declaration or reference the parameter in the Program, then check again.'});
    const oversizedName = 'x'.repeat(257);
    const bounded = await client.check('SELECT 1 AS n', {format: 'sql',
      parameterDeclarations: {[oversizedName]: {type: 'number', default: 7}}});
    assert.equal(bounded.report.verdict, 'invalid');
    assert.deepEqual(bounded.report.reasons, [{code: 'program_invalid'}]);
    const missing = await client.check('SELECT 1 AS n', {format: 'sql',
      parameterDeclarations: {unused: {type: 'number'}}});
    assert.equal(missing.report.verdict, 'undetermined');
    assert.deepEqual(missing.report.reasons, []);
    assert.deepEqual(missing.report.coverage.limits, [{code: 'bound_values_missing'}]);
    const protectedOutcomes = [];
    for (const configuration of [configurations.absent, configurations.denied]) {
      const protectedClient = await open(t, configuration);
      const protectedOutcome = await protectedClient.check('SELECT id FROM records', {format: 'sql',
        parameterDeclarations: {unused: {type: 'number', default: 7}}});
      assert.equal(protectedOutcome.report.verdict, 'undetermined');
      assert.deepEqual(protectedOutcome.report.reasons, []);
      assert.deepEqual(protectedOutcome.report.coverage, {limits: [], unresolved: protectedSource});
      protectedOutcomes.push(withoutContext(protectedOutcome));
      protectedClient.assertNoExecution();
    }
    assert.deepEqual(protectedOutcomes[0], protectedOutcomes[1]);
    client.assertNoExecution();
  });

  test(`${entrance}: non-Boolean predicates retain the common checker's requirement`, async t => {
    const client = await open(t, configurations.allowed);
    for (const text of ['SELECT id FROM records WHERE id', 'SELECT id FROM records WHERE 1']) {
      const result = await client.check(text, {format: 'sql'});
      assert.equal(result.outcome, 'completed');
      assert.equal(result.report.verdict, 'invalid', '[check-mutation:predicate-verdict]');
      assert.deepEqual(result.report.reasons, [{code: 'query_expression_invalid',
        facts: {issue: 'expected_boolean'}}], '[check-mutation:predicate-reason]');
      // The common issue retains a span without authored/generated provenance.
      // Do not invent an exact SQL location or expose a lowered Program path.
      assert.equal(result.report.reasons[0].location, undefined);
      assert.deepEqual(explainCheckReason(result.report.reasons[0]), {kind: 'known',
        summary: 'A predicate must have Boolean type.',
        hint: 'Use a Boolean condition, such as a comparison, in the predicate.'},
      '[check-mutation:predicate-explanation]');
      assert.deepEqual(result.report.coverage, {limits: [], unresolved: []});
      const document = result.report.inputs[0];
      assert.equal(getCheckInput(result, document.document_id, document.revision).text, text);
    }
    const corrected = await client.check('SELECT id FROM records WHERE id > 0', {format: 'sql'});
    assert.equal(corrected.report.verdict, 'verified');
    assert.deepEqual(corrected.report.reasons, []);
    const hidden = [];
    for (const configuration of [configurations.absent, configurations.denied]) {
      const protectedClient = await open(t, configuration);
      const result = await protectedClient.check('SELECT id FROM records WHERE id', {format: 'sql'});
      assert.deepEqual(result.report.reasons, [], '[check-mutation:predicate-disclosure]');
      hidden.push(withoutContext(result));
      protectedClient.assertNoExecution();
    }
    assert.deepEqual(hidden[0], hidden[1]);
    assert.equal(hidden[0].report.verdict, 'undetermined');
    assert.deepEqual(hidden[0].report.coverage, {limits: [], unresolved: protectedSource});
    client.assertNoExecution();
  });

  test(`${entrance}: invalid declarations retain only their owned submitted locations`, async t => {
    const client = await open(t, configurations.denied);
    for (const [declaration, pointer, typedDefault = false] of [
      [{options: {type: 'number', minimum: 1, default: 0}}, '/options/default'],
      [{options: {type: 'object', fields: {count: {type: 'number'}},
        default: {count: 'private-value'}}}, '/options/default/count', true],
      [{options: {type: 'number', future: 'private-value'}}, '/options/future'],
      [{options: {type: 'number', meta: {actql_private: 'private-value'}}},
        '/options/meta/actql_private'],
      [{options: {type: 'object', fields: {'/a~~//é': {type: 'number'}},
        default: {'/a~~//é': 'private-value'}}}, '/options/default/~1a~0~0~1~1é', true],
      [{'a~~//é': {type: 'number'}}, '/a~0~0~1~1é'],
      [{}, ''],
    ]) {
      const outcome = await client.check('SELECT 1 AS n', {format: 'sql',
        parameterDeclarations: declaration, parameters: {options: 3}});
      assert.equal(outcome.outcome, 'completed', '[check-mutation:declaration-outcome]');
      assert.equal(outcome.report.verdict, 'invalid');
      const input = getCheckInput(outcome, 'parameter_declarations');
      const location = {kind: 'structured', document_id: 'parameter_declarations',
        revision: input.revision, pointer};
      assert.deepEqual(outcome.report.reasons,
        [{...(typedDefault ? {code: 'parameter_default_type_mismatch',
          facts: {parameter: 'options', expected_type: 'number', actual_type: 'string'}}
          : {code: 'parameter_declarations_invalid'}), location}], '[check-mutation:declaration-location]');
      assert.equal(resolveCheckLocation(outcome, location).input, input);
      assert.equal(resolveCheckLocation(outcome, location,
        {...input, value: {options: {type: 'number'}}}), undefined);
      assert.equal(resolveCheckLocation(JSON.parse(JSON.stringify(outcome)), location), undefined);
      assert.equal(JSON.stringify(outcome).includes('private-value'), false);
      assert.deepEqual(outcome.report.coverage, {limits: [], unresolved: []});
    }
    // The reader's missing-member path does not name a submitted node.
    for (const [declaration, reason] of [
      [{options: {default: 0}}, {code: 'parameter_declarations_invalid'}],
      [{options: {type: 'object', fields: {count: {type: 'number'}}, default: {}}},
        {code: 'parameter_declarations_invalid'}],
      [{options: {type: 'object', fields: {['a'.repeat(4096)]: {type: 'number'}},
        default: {['a'.repeat(4096)]: 'private-value'}}},
      {code: 'parameter_default_type_mismatch', facts: {parameter: 'options',
        expected_type: 'number', actual_type: 'string'}}],
    ]) {
      const outcome = await client.check('SELECT 1 AS n', {format: 'sql',
        parameterDeclarations: declaration});
      assert.deepEqual(outcome.report.reasons, [reason]);
    }
    client.assertNoExecution();
  });

  test(`${entrance}: Graph components expose typed argument violations`, async t => {
    const client = await open(t, configurations.denied);
    const prefix = 'DATA n = SELECT 1 AS node_key; DATA g = PROPERTY GRAPH ' +
      '(NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES)); ';
    for (const format of ['aql-text']) {
      for (const kind of ['weak', 'strong']) {
        const outcome = await client.check(prefix +
          `FROM g |> components(kind: '${kind}') |> SELECT component_size`, {format});
        assert.equal(outcome.outcome, 'completed');
        assert.equal(outcome.report.verdict, 'verified', JSON.stringify(outcome.report));
        assert.deepEqual(outcome.report.reasons, []);
      }
      for (const [arguments_, issue, summary, hint] of [
        ["kind: 'private-kind-value'", 'invalid_kind',
          'The components kind is invalid.', 'Choose weak or strong for components kind.'],
        ["kind: 'weak', max_output_rows: 0", 'invalid_output_rows',
          'The components output row limit is invalid.',
          'Supply a positive safe integer for components max_output_rows.'],
        ["kind: 'weak', max_output_rows: 1.5", 'invalid_output_rows',
          'The components output row limit is invalid.',
          'Supply a positive safe integer for components max_output_rows.'],
      ]) {
        const text = '/*😀*/\r\n' + prefix +
          `FROM g |> components(${arguments_}) |> SELECT component_size`;
        const outcome = await client.check(text, {format});
        assert.equal(outcome.outcome, 'completed');
        assert.equal(outcome.report.verdict, 'invalid', '[check-mutation:graph-argument-verdict]');
        // Program paths and unproven argument precision are not input positions.
        assert.deepEqual(outcome.report.reasons, [{code: 'graph_operation_invalid',
          facts: {operation: 'components', issue}}], '[check-mutation:graph-argument-reason]');
        assert.deepEqual(outcome.report.coverage, {limits: [], unresolved: []});
        assert.deepEqual(outcome.report.requirements, []);
        assert.equal(getCheckInput(outcome, 'source').text, text);
        assert.deepEqual(explainCheckReason(outcome.report.reasons[0]),
          {kind: 'known', summary, hint});
        assert.equal(JSON.stringify(outcome).includes('private-kind-value'), false);
      }
    }
    const absent = await open(t, configurations.absent);
    const protectedText = prefix.replace('SELECT 1 AS node_key',
      'SELECT id AS node_key FROM records') +
      "FROM g |> components(kind: 'private-kind-value') |> SELECT component_size";
    for (const boundary of [client, absent]) {
      const outcome = await boundary.check(protectedText, {format: 'aql-text'});
      assert.equal(outcome.report.verdict, 'undetermined');
      assert.deepEqual(outcome.report.reasons, [], '[check-mutation:graph-protected]');
      assert.deepEqual(outcome.report.coverage, {limits: [], unresolved: protectedSource});
      boundary.assertNoExecution();
    }
    client.assertNoExecution();
  });

  test(`${entrance}: unresolved column expressions retain authored source positions`, async t => {
    const client = await open(t, configurations.denied);
    const visible = await open(t, configurations.allowed);
    for (const format of ['sql', 'aql-text']) {
      for (const [text, start, end, token] of [
        ['SELECT missing AS n', 7, 14, 'missing'],
        ['/*😀*/\r\nSELECT missing AS n', 17, 24, 'missing'],
        ['/* missing */ SELECT missing AS n', 21, 28, 'missing'],
        ['SELECT missing AS n, missing AS m', 7, 14, 'missing'],
        ['SELECT `é😀` AS n', 7, 15, '`é😀`'],
      ]) {
        const outcome = await client.check(text, {format});
        assert.equal(outcome.outcome, 'completed', '[check-mutation:column-outcome]');
        assert.equal(outcome.report.verdict, 'invalid', '[check-mutation:column-verdict]');
        const original = getCheckInput(outcome, 'source');
        assert.deepEqual(outcome.report.reasons, [{code: 'query_expression_invalid', facts: {issue: 'unknown_reference'},
          location: {document_id: 'source', revision: original.revision,
            kind: 'text', start_byte: start, end_byte: end, precision: 'exact'}}],
        '[check-mutation:column-location]');
        assert.deepEqual(outcome.report.coverage, {limits: [], unresolved: []});
        const location = outcome.report.reasons[0].location;
        assert.equal(resolveCheckLocation(outcome, location).text, token);
        assert.equal(resolveCheckLocation(outcome, location,
          {...original, text: 'SELECT id AS n'}), undefined);
        assert.equal(resolveCheckLocation(JSON.parse(JSON.stringify(outcome)), location), undefined);
        assert.equal(explainCheckReason(outcome.report.reasons[0]).kind, 'known');
      }
      // Double quotes are string literals; backticks quote identifiers.
      const literal = await client.check('SELECT "é😀" AS n', {format});
      assert.equal(literal.report.verdict, 'verified');
      assert.deepEqual(literal.report.reasons, []);
      const bare = await client.check('SELECT missing', {format});
      assert.deepEqual(bare.report.reasons, [{code: 'query_invalid'}]);
      const protectedInput = await client.check('SELECT missing AS n FROM records', {format});
      assert.equal(protectedInput.report.verdict, 'undetermined');
      assert.deepEqual(protectedInput.report.reasons, []);
      assert.deepEqual(protectedInput.report.coverage, {limits: [], unresolved: protectedSource});
      for (const [text, start, end, token] of [
        ['SELECT missing AS n FROM records', 7, 14, 'missing'],
        ['SELECT records.missing AS n FROM records', 7, 22, 'records.missing'],
      ]) {
        const outcome = await visible.check(text, {format});
        assert.equal(outcome.outcome, 'completed', '[check-mutation:column-outcome]');
        assert.equal(outcome.report.verdict, 'invalid', '[check-mutation:column-verdict]');
        const original = getCheckInput(outcome, 'source');
        assert.deepEqual(outcome.report.reasons, [{code: 'query_expression_invalid', facts: {issue: 'unknown_reference'},
          location: {document_id: 'source', revision: original.revision,
            kind: 'text', start_byte: start, end_byte: end, precision: 'exact'}}],
        '[check-mutation:column-location]');
        assert.equal(resolveCheckLocation(outcome, outcome.report.reasons[0].location).text, token);
      }
    }
    client.assertNoExecution();
    visible.assertNoExecution();
  });

  test(`${entrance}: nested supplied type facts follow the submitted contract and path`, async t => {
    const client = await open(t, configurations.denied);
    const cases = [
      [{type: 'object', fields: {'a//b': {type: 'number'}}},
        {'a//b': 'private-value'}, '/options/a~1~1b', 'number', 'string'],
      [{type: 'object', fields: {'/a~~//é': {type: 'array', items: {type: 'number'}}}},
        {'/a~~//é': [7, 'private-value']}, '/options/~1a~0~0~1~1é/1', 'number', 'string'],
      [{type: 'array', items: {type: 'object', fields: {enabled: {type: 'boolean'}}}},
        [{enabled: 2}], '/options/0/enabled', 'boolean', 'number'],
      [{type: 'object', fields: {count: {type: 'number'}}},
        {count: null}, '/options/count', 'number', 'null'],
    ];
    for (const [declaration, value, pointer, expected_type, actual_type] of cases) {
      const parameters = {options: value};
      const outcome = await client.check('SELECT id FROM records', {format: 'sql',
        parameterDeclarations: {options: declaration, missing: {type: 'string'}}, parameters});
      assert.equal(outcome.outcome, 'completed', '[check-mutation:nested-outcome]');
      assert.equal(outcome.report.verdict, 'invalid');
      const original = getCheckInput(outcome, 'parameters');
      assert.deepEqual(outcome.report.reasons, [{code: 'supplied_value_type_mismatch',
        facts: {parameter: 'options', expected_type, actual_type},
        location: {document_id: 'parameters', revision: original.revision,
          kind: 'structured', pointer}}], '[check-mutation:nested-type]');
      assert.deepEqual(outcome.report.coverage, {limits: [], unresolved: protectedSource});
      assert.deepEqual(original.value, parameters);
      const reason = outcome.report.reasons[0];
      assert.equal(resolveCheckLocation(outcome, reason.location).input, original);
      assert.equal(resolveCheckLocation(outcome, reason.location,
        {...original, value: {options: 'edited'}}), undefined);
      assert.equal(resolveCheckLocation(JSON.parse(JSON.stringify(outcome)), reason.location), undefined);
      assert.equal(JSON.stringify(outcome).includes('private-value'), false);
      assert.equal(explainCheckReason(reason).kind, 'known');
    }
    client.assertNoExecution();
  });

  test(`${entrance}: supplied constraint locations retain the binder path without private values`, async t => {
    const client = await open(t, configurations.denied);
    for (const [declaration, value, pointer, constraint] of [
      [{type: 'object', fields: {count: {type: 'number', integer: true}}},
        {count: 1.5}, '/options/count', 'numeric'],
      [{type: 'object', fields: {count: {type: 'number', minimum: 1}}},
        {count: 0}, '/options/count', 'numeric'],
      [{type: 'object', fields: {count: {type: 'number', maximum: 1}}},
        {count: 2}, '/options/count', 'numeric'],
      [{type: 'object', fields: {waits: {type: 'array', length: 2, items: {type: 'string'}}}},
        {waits: ['private-value']}, '/options/waits', 'array_length'],
      [{type: 'array', items: {type: 'string', format: 'duration'}},
        ['1s', 'private-value'], '/options/1', 'duration'],
      [{type: 'object', fields: {'/a~~//é': {type: 'array', max_items: 1, items: {type: 'string'}}}},
        {'/a~~//é': ['private-value', 'private-value']}, '/options/~1a~0~0~1~1é', 'array_size'],
    ]) {
      const outcome = await client.check('SELECT id FROM records', {format: 'sql',
        parameterDeclarations: {options: declaration}, parameters: {options: value}});
      assert.equal(outcome.outcome, 'completed', '[check-mutation:constraint-outcome]');
      const original = getCheckInput(outcome, 'parameters');
      assert.equal(outcome.report.verdict, 'invalid');
      assert.deepEqual(outcome.report.reasons, [{code: 'supplied_value_constraint_violation',
        facts: {parameter: 'options', constraint},
        location: {document_id: 'parameters', revision: original.revision,
          kind: 'structured', pointer}}], '[check-mutation:constraint-location]');
      assert.deepEqual(outcome.report.coverage, {limits: [], unresolved: protectedSource});
      assert.equal(resolveCheckLocation(outcome, outcome.report.reasons[0].location).input, original);
      assert.equal(JSON.stringify(outcome).includes('private-value'), false);
      assert.equal(explainCheckReason(outcome.report.reasons[0]).kind, 'known');
      assert.notEqual(explainCheckReason(outcome.report.reasons[0]).hint,
        explainCheckReason({code: 'supplied_value_invalid'}).hint);
    }
    // A valid pointer exceeding the public bound is omitted, not truncated.
    for (const longKey of ['a'.repeat(4096), '~'.repeat(2050)]) {
      const oversized = await client.check('SELECT 1 AS n', {format: 'sql',
        parameterDeclarations: {options: {type: 'object', fields: {[longKey]: {type: 'number'}}}},
        parameters: {options: {[longKey]: 'private-value'}}});
      assert.deepEqual(oversized.report.reasons, [{code: 'supplied_value_type_mismatch',
        facts: {parameter: 'options', expected_type: 'number', actual_type: 'string'}}]);
    }
    // Invalid defaults belong to declarations, never to the supplied document.
    const defaults = await client.check('SELECT 1 AS n', {format: 'sql',
      parameterDeclarations: {options: {type: 'number', minimum: 1, default: 0}},
      parameters: {options: 3}});
    assert.deepEqual(defaults.report.reasons, [{code: 'parameter_declarations_invalid',
      location: {kind: 'structured', document_id: 'parameter_declarations',
        revision: getCheckInput(defaults, 'parameter_declarations').revision,
        pointer: '/options/default'}}]);
    const longKey = 'a'.repeat(4096);
    const oversizedConstraint = await client.check('SELECT 1 AS n', {format: 'sql',
      parameterDeclarations: {options: {type: 'object', fields: {[longKey]: {type: 'number', minimum: 1}}}},
      parameters: {options: {[longKey]: 0}}});
    assert.deepEqual(oversizedConstraint.report.reasons, [{code: 'supplied_value_constraint_violation',
      facts: {parameter: 'options', constraint: 'numeric'}}]);
    const missingMember = await client.check('SELECT 1 AS n', {format: 'sql',
      parameterDeclarations: {options: {type: 'object', fields: {count: {type: 'number'}}}},
      parameters: {options: {}}});
    assert.deepEqual(missingMember.report.reasons, [{code: 'supplied_value_invalid'}]);
    client.assertNoExecution();
  });

  test(`${entrance}: undeclared references keep authored semantic locations`, async t => {
    const client = await open(t, configurations.denied);
    for (const [text, start, end] of [
      ['SELECT @missing AS n', 7, 15],
      ['/*😀*/\r\nSELECT @missing AS n', 17, 25],
    ]) {
      const outcome = await client.check(text, {format: 'sql'});
      assert.equal(outcome.report.verdict, 'invalid');
      assert.deepEqual(outcome.report.requirements, []);
      assert.deepEqual(outcome.report.coverage, {limits: [], unresolved: []});
      const revision = outcome.report.inputs[0].revision;
      assert.deepEqual(outcome.report.reasons, [{code: 'parameter_undeclared',
        facts: {parameter: 'missing'}, location: {document_id: 'source', revision,
          kind: 'text', start_byte: start, end_byte: end, precision: 'exact'}}]);
      assert.equal(resolveCheckLocation(outcome, outcome.report.reasons[0].location).text, '@missing');
    }
    client.assertNoExecution();
  });

  test(`${entrance}: supplied type violations and missing values expose different typed facts`, async t => {
    for (const hidden of ['absent', 'denied', 'allowed']) {
      const client = await open(t, configurations[hidden]);
      const violation = await check(client, 'violation');
      assert.equal(violation.report.verdict, 'invalid');
      const values = getCheckInput(violation, 'parameters');
      assert.deepEqual(values.value, {minimum: 'twenty'});
      assert.deepEqual(violation.report.reasons, [{code: 'supplied_value_type_mismatch',
        facts: {parameter: 'minimum', expected_type: 'number', actual_type: 'string'},
        location: {document_id: 'parameters', revision: values.revision,
          kind: 'structured', pointer: '/minimum'}}]);
      assert.deepEqual(violation.report.requirements, []);
      assert.deepEqual(violation.report.coverage, {limits: [],
        unresolved: hidden === 'allowed' ? [] : protectedSource});
      assert.equal(JSON.stringify(violation).includes('twenty'), false);
      assert.equal(resolveCheckLocation(violation, violation.report.reasons[0].location).input, values);
      const mixed = await client.check(query, {format: 'sql',
        parameterDeclarations: {...declarations, another: {type: 'number'}},
        parameters: {minimum: 'twenty'}});
      assert.equal(mixed.report.verdict, 'invalid');
      assert.deepEqual(mixed.report.reasons[0].facts,
        {parameter: 'minimum', expected_type: 'number', actual_type: 'string'});
      assert.deepEqual(mixed.report.coverage.unresolved,
        hidden === 'allowed' ? [] : protectedSource);
      const missing = await check(client, 'missing');
      const declared = getCheckInput(missing, 'parameter_declarations');
      assert.equal(missing.report.verdict, 'undetermined', '[check-mutation:missing-value]');
      assert.deepEqual(missing.report.reasons, []);
      assert.deepEqual(missing.report.requirements, [{code: 'parameter_value_required',
        facts: {parameter: 'minimum', expected_type: 'number', admission: expectedNumberAdmission},
        location: {document_id: 'parameter_declarations', revision: declared.revision,
          kind: 'structured', pointer: '/minimum'}}]);
      assert.equal(explainCheckReason(missing.report.requirements[0]).kind, 'known');
      assert.notEqual(missing.report.context_ref, violation.report.context_ref);
      assert.notEqual(declared.revision, values.revision);
      client.assertNoExecution();
    }
  });

  test(`${entrance}: authored syntax locations retain exact UTF-8 input revisions`, async t => {
    const client = await open(t, configurations.denied);
    // Fixed byte expectations, hand-counted independently of parser output.
    const cases = [
      ['SELECT', 6, 6, {line: 0, character: 6}],
      ["SELECT 'é😀e\u0301' AS x,", 24, 24, {line: 0, character: 20}],
      ['SELECT 1 AS n,\r\n', 16, 16, {line: 1, character: 0}],
      ["\ufeffSELECT 'é😀e\u0301' AS x,\r\n", 29, 29, {line: 1, character: 0}],
    ];
    const revisions = [];
    for (const [text, start, end, position] of cases) {
      const outcome = await client.check(text, {format: 'sql'});
      assert.equal(outcome.outcome, 'completed', '[check-mutation:syntax-outcome]');
      assert.equal(outcome.report.verdict, 'invalid');
      assert.deepEqual(outcome.report.coverage, {limits: [], unresolved: []});
      assert.deepEqual(outcome.report.requirements, []);
      assert.equal(outcome.report.reasons.length, 1);
      const reason = outcome.report.reasons[0];
      const input = getCheckInput(outcome, 'source');
      assert.deepEqual(input, {documentId: 'source', revision: outcome.report.inputs[0].revision,
        kind: 'text', text});
      assert.deepEqual(outcome.report.inputs, [{document_id: 'source', revision: input.revision,
        kind: 'text', byte_length: end}]);
      assert.deepEqual(reason, {code: 'query_syntax_invalid', location: {
        kind: 'text', document_id: 'source', revision: input.revision,
        start_byte: start, end_byte: end, precision: 'exact'}}, '[check-mutation:syntax-location]');
      const resolved = resolveCheckLocation(outcome, reason.location);
      assert.equal(resolved.text, '');
      assert.equal(resolved.input.text, text);
      const editor = resolveCheckTextRange(outcome, reason.location);
      assert.deepEqual(editor?.range, {start: position, end: position},
        '[check-mutation:editor-coordinates]');
      assert.equal(editor.input, input);
      assert.equal(editor.positionEncoding, 'utf-16');
      assert.equal(resolveCheckTextRange(outcome, reason.location,
        {...input, text: 'SELECT 1 AS n'}), undefined, '[check-mutation:editor-revision]');
      assert.equal(explainCheckReason(reason).kind, 'known');
      assert.equal(resolveCheckLocation(outcome, reason.location, {...input, text: 'SELECT 1 AS n'}), undefined);
      assert.equal(resolveCheckLocation(outcome, reason.location, {...input, revision: 'rev:' + '0'.repeat(64)}), undefined);
      assert.equal(resolveCheckLocation(JSON.parse(JSON.stringify(outcome)), reason.location), undefined);
      assert.equal(getCheckInput(outcome, 'source', 'rev:' + '0'.repeat(64)), undefined);
      revisions.push(input.revision);
    }
    assert.equal(new Set(revisions).size, cases.length);
    client.assertNoExecution();
  });

  test(`${entrance}: zero, one and two installed Sources preserve public checks`,
    async t => {
      for (const configuration of [[], [configurations.allowed],
        [leftConfiguration, rightConfiguration('denied')]]) {
        const client = await open(t, configuration);
        const expected = (verdict, reasons) => ({context_ref: '<ctx>',
          scope: {kind: 'bound_input'}, verdict, reasons,
          coverage: {limits: [], unresolved: []}});
        assert.deepEqual(withoutContext(await client.check('SELECT 1 AS n',
          {format: 'sql'})).report, expected('verified', []));
        assert.deepEqual(withoutContext(await client.check('SELECT FROM WHERE',
          {format: 'sql'})).report,
        expected('invalid', [{code: 'query_syntax_invalid'}]));
        client.assertNoExecution();
      }
    });

  test(`${entrance}: independent Source disclosure preserves visible checks in either order`,
    async t => {
      for (const hidden of ['absent', 'denied', 'undecidable']) {
        for (const reversed of [false, true]) {
          const configuration = [leftConfiguration, rightConfiguration(hidden)];
          if (reversed) configuration.reverse();
          const client = await open(t, configuration);
          assert.deepEqual(withoutContext(await check(client, 'satisfied')).report,
            {context_ref: '<ctx>', scope: {kind: 'bound_input'},
              verdict: 'verified', reasons: [],
              coverage: {limits: [], unresolved: []}});
          assert.deepEqual(withoutContext(await client.check(
            'SELECT id FROM other_records', {format: 'sql'})).report,
          {context_ref: '<ctx>', scope: {kind: 'bound_input'},
            verdict: 'undetermined', reasons: [],
            coverage: {limits: [], unresolved: protectedSource}});
          assert.deepEqual(withoutContext(await check(client, 'violation')).report,
            {context_ref: '<ctx>', scope: {kind: 'bound_input'},
              verdict: 'invalid', reasons: [{code: 'supplied_value_invalid'}],
              coverage: {limits: [], unresolved: []}});
          client.assertNoExecution();
        }
      }
    });

  test(`${entrance}: a disclosable violation is reported beside a ` +
    'protected source', async t => {
    for (const name of ['absent', 'denied']) {
      const client = await open(t, configurations[name]);
      const outcome = await check(client, 'violation');
      assert.equal(validCheckOutcome(outcome), true);
      assert.deepEqual(withoutContext(outcome), {
        outcome: 'completed', version: 'actql-check-outcome/0.1',
        report: {context_ref: '<ctx>', scope: {kind: 'bound_input'},
          verdict: 'invalid', reasons: [{code: 'supplied_value_invalid'}],
          coverage: {limits: [], unresolved: protectedSource}}}, '[check-mutation:public-violation]');
      // Without the violation the protected source leaves it undetermined,
      // never invalid and never verified.
      assert.deepEqual(withoutContext(await check(client, 'satisfied'), 'protected-outcome'), {
        outcome: 'completed', version: 'actql-check-outcome/0.1',
        report: {context_ref: '<ctx>', scope: {kind: 'bound_input'},
          verdict: 'undetermined', reasons: [],
          coverage: {limits: [], unresolved: protectedSource}}}, '[check-mutation:protected-unresolved]');
      // A missing value is a limit: undetermined, never invalid.
      assert.deepEqual(withoutContext(await check(client, 'missing')), {
        outcome: 'completed', version: 'actql-check-outcome/0.1',
        report: {context_ref: '<ctx>', scope: {kind: 'bound_input'},
          verdict: 'undetermined', reasons: [],
          coverage: {limits: [{code: 'bound_values_missing'}],
            unresolved: protectedSource}}}, name);
    }
  });

  test(`${entrance}: absent and denied sources give the same public outcome`,
    async t => {
      const seen = {};
      for (const name of ['absent', 'denied']) {
        const client = await open(t, configurations[name]);
        const first = await check(client, 'violation');
        // The same Host and disclosable context give the same reference;
        // other bindings give another one.
        assert.deepEqual(await check(client, 'violation'), first);
        assert.notEqual((await check(client, 'satisfied')).report.context_ref,
          first.report.context_ref);
        seen[name] = {violation: withoutContext(first),
          satisfied: withoutContext(await check(client, 'satisfied')),
          missing: withoutContext(await check(client, 'missing')),
          unknownName: withoutContext(await client.check(
            'SELECT id FROM accounts', {format: 'sql'}))};
        if (entrance === 'http') {
          const response = await client.post({input: {text: query,
            format: 'sql', parameterDeclarations: declarations},
          parameters: requests.violation.parameters});
          assert.equal(response.status, 200);
          seen[name].status = response.status;
          seen[name].body = withoutContext(await response.json());
        }
      }
      assert.deepEqual(seen.absent, seen.denied);
      // A name that was never installed anywhere is the same protected
      // boundary, not a disclosable unknown-name violation.
      assert.deepEqual(seen.absent.unknownName.report, {
        context_ref: '<ctx>', scope: {kind: 'bound_input'},
        verdict: 'undetermined', reasons: [],
        coverage: {limits: [], unresolved: protectedSource}});
    });

  test(`${entrance}: a visible source discharges the protected obligation`,
    async t => {
      const client = await open(t, configurations.allowed);
      assert.deepEqual(withoutContext(await check(client, 'violation')).report,
        {context_ref: '<ctx>', scope: {kind: 'bound_input'},
          verdict: 'invalid', reasons: [{code: 'supplied_value_invalid'}],
          coverage: {limits: [], unresolved: []}});
      assert.deepEqual(withoutContext(await check(client, 'satisfied')).report,
        {context_ref: '<ctx>', scope: {kind: 'bound_input'},
          verdict: 'verified', reasons: [],
          coverage: {limits: [], unresolved: []}});
    });

  test(`${entrance}: verified binds the supplied values it was checked with`,
    async t => {
      const client = await open(t, configurations.allowed);
      // Without the declared value the same source is never verified: there
      // is no template-scope verdict to reuse for a bound input.
      const unbound = await check(client, 'missing');
      assert.deepEqual(withoutContext(unbound).report, {context_ref: '<ctx>',
        scope: {kind: 'bound_input'}, verdict: 'undetermined', reasons: [],
        coverage: {limits: [{code: 'bound_values_missing'}],
          unresolved: []}});
      const bound = await check(client, 'satisfied');
      assert.equal(bound.report.verdict, 'verified');
      const rebound = await client.check(query, {format: 'sql',
        parameterDeclarations: declarations, parameters: {minimum: 30}});
      assert.equal(rebound.report.verdict, 'verified');
      // Each verdict names its own bindings; none stands for another.
      assert.equal(new Set([unbound, bound, rebound].map(outcome =>
        outcome.report.context_ref)).size, 3);
    });

  test(`${entrance}: an exhausted analysis budget is undetermined, ` +
    'not invalid or failed', async t => {
    const client = await open(t, configurations.allowed);
    const outcome = await client.check('SELECT id FROM records' +
      ' UNION ALL SELECT id FROM records'.repeat(50), {format: 'sql'});
    assert.deepEqual(withoutContext(outcome, 'construction-outcome').report, {context_ref: '<ctx>',
      scope: {kind: 'bound_input'}, verdict: 'undetermined', reasons: [],
      coverage: {limits: [{code: 'analysis_budget_exhausted'}],
        unresolved: []}}, '[check-mutation:construction-budget]');
  });

  test(`${entrance}: an undecided source is hidden exactly like an absent ` +
    'one and withholds nothing else', async t => {
    const seen = {};
    for (const name of ['absent', 'undecidable']) {
      const client = await open(t, configurations[name]);
      seen[name] = {
        // A violation that does not depend on the source at all.
        unrelated: withoutContext(await client.check('SELECT missing AS n',
          {format: 'sql'})),
        // The protected source referenced beside a definite violation.
        violation: withoutContext(await check(client, 'violation')),
        satisfied: withoutContext(await check(client, 'satisfied')),
      };
    }
    assert.deepEqual(seen.undecidable, seen.absent);
    assert.deepEqual(seen.undecidable.unrelated.report, {context_ref: '<ctx>',
      scope: {kind: 'bound_input'}, verdict: 'invalid',
      reasons: [{code: 'query_expression_invalid'}],
      coverage: {limits: [], unresolved: []}});
    assert.deepEqual(seen.undecidable.violation.report, {context_ref: '<ctx>',
      scope: {kind: 'bound_input'}, verdict: 'invalid',
      reasons: [{code: 'supplied_value_invalid'}],
      coverage: {limits: [], unresolved: protectedSource}});
  });

  test(`${entrance}: a verdict is bound to the exact source it checked`,
    async t => {
      const client = await open(t, configurations.allowed);
      const ref = async (text, format = 'sql') =>
        (await client.check(text, {format})).report.context_ref;
      const first = await client.check('SELECT 1 AS n', {format: 'sql'});
      assert.equal(first.report.verdict, 'verified');
      // The same source again is the same context.
      assert.deepEqual(await client.check('SELECT 1 AS n', {format: 'sql'}),
        first);
      // Another source, or the same text in another format or with other
      // line endings, is another context.
      const other = await client.check('SELECT missing AS n', {format: 'sql'});
      assert.equal(other.report.verdict, 'invalid');
      const refs = [first.report.context_ref, other.report.context_ref,
        await ref('SELECT 1 AS n', 'aql-text'), await ref('SELECT 1 AS n\n'),
        await ref('SELECT 1 AS n\r\n')];
      assert.equal(new Set(refs).size, refs.length);
    });

  test(`${entrance}: Unicode source spelling survives ordinary and fallback binding`,
    async t => {
      const client = await open(t, configurations.allowed);
      const texts = ["SELECT 'caf\u00e9' AS label", "SELECT 'cafe\u0301' AS label"];
      // Canonically colliding declaration names force the received-input
      // fallback. They are invalid declarations, not a second valid Program.
      for (const parameterDeclarations of [undefined,
        {'\u00e9': {type: 'string'}, 'e\u0301': {type: 'string'}}]) {
        const run = text => client.check(text, {format: 'sql', parameterDeclarations});
        const outcomes = await Promise.all(texts.map(run));
        const invalid = parameterDeclarations !== undefined;
        for (let index = 0; index < texts.length; index++) {
          assert.deepEqual(withoutContext(outcomes[index]).report, {
            context_ref: '<ctx>', scope: {kind: 'bound_input'},
            verdict: invalid ? 'invalid' : 'verified',
            reasons: invalid ? [{code: 'binding_json_invalid'}] : [],
            coverage: {limits: [], unresolved: []}});
          if (invalid) assert.deepEqual(outcomes[index].report.reasons, [{code: 'binding_json_invalid',
            facts: {document: 'parameter_declarations', issue: 'duplicate_key'}}],
          '[check-mutation:json-parser-fallback-facts]');
          assert.deepEqual(await run(texts[index]), outcomes[index]);
        }
        assert.notEqual(outcomes[0].report.context_ref, outcomes[1].report.context_ref);
      }
      client.assertNoExecution();
    });

  test(`${entrance}: distinct supplied values give distinct contexts`,
    async t => {
      const client = await open(t, configurations.allowed);
      const valueRef = async (parameters, declared = {x: {type: 'string'}}) => {
        const outcome = await client.check('SELECT @x AS value', {
          format: 'sql', parameterDeclarations: declared, parameters});
        assert.equal(outcome.report.verdict, 'verified');
        return outcome.report.context_ref;
      };
      // String values stay exact: composed and decomposed, CR, LF and CRLF
      // are different values.
      const refs = [await valueRef({x: '\u00e9'}), await valueRef({x: 'e\u0301'}),
        await valueRef({x: '\r'}), await valueRef({x: '\n'}),
        await valueRef({x: '\r\n'}),
        // So are declared defaults.
        await valueRef({}, {x: {type: 'string', default: '\u00e9'}}),
        await valueRef({}, {x: {type: 'string', default: 'e\u0301'}})];
      assert.equal(new Set(refs).size, refs.length);
      // Member order is not part of a value.
      const pair = {x: {type: 'string'}, y: {type: 'string'}};
      const ordered = async (declared, parameters) =>
        (await client.check('SELECT @x AS a, @y AS b', {format: 'sql',
          parameterDeclarations: declared, parameters})).report.context_ref;
      assert.equal(await ordered(pair, {x: 'a', y: 'b'}),
        await ordered({y: pair.y, x: pair.x}, {y: 'b', x: 'a'}));
    });

  for (const format of ['sql', 'aql-text']) {
    test(`${entrance}: declaration exhaustion still permits bounded syntax checking (${format})`,
      async t => {
        const client = await open(t, configurations.absent);
        const parameterDeclarations = Object.fromEntries(Array.from(
          {length: 1100}, (_, index) => [`p${index}`, {type: 'number'}]));
        const expected = (verdict, reasons) => ({
          context_ref: '<ctx>', scope: {kind: 'bound_input'}, verdict, reasons,
          coverage: {limits: [{code: 'analysis_budget_exhausted'}], unresolved: []}});
        const run = async text => withoutContext(await client.check(text, {
          format, parameterDeclarations, parameters: null})).report;
        // Syntax success cannot discharge the unadmitted declarations or
        // turn their parameters/columns into semantic violations.
        for (const text of ['SELECT 1 AS n', 'SELECT @p0 AS n',
          'SELECT missing AS n', 'SELECT id FROM records']) {
          assert.deepEqual(await run(text), expected('undetermined', []));
        }
        assert.deepEqual(await run('SELECT FROM WHERE'),
          expected('invalid', [{code: 'query_syntax_invalid'}]));
        // A separate parser token budget is finite too: never blame input
        // merely because both admission and syntax checking exhaust budgets.
        assert.deepEqual(await run('SELECT ' + Array(4200).fill('1').join(',')),
          expected('undetermined', []));
      });
  }

  test(`${entrance}: parameter budgets are limits, never violations`,
    async t => {
      const client = await open(t, configurations.absent);
      const numbers = {xs: {type: 'array', items: {type: 'number'}}};
      const nested = depth => depth === 0 ? 1 : [nested(depth - 1)];
      const run = (text, parameterDeclarations, parameters) =>
        client.check(text, {format: 'sql', parameterDeclarations, parameters})
          .then(outcome => withoutContext(outcome).report);
      const budget = [{code: 'analysis_budget_exhausted'}];
      const expected = (verdict, reasons, limits, unresolved) => ({
        context_ref: '<ctx>', scope: {kind: 'bound_input'}, verdict, reasons,
        coverage: {limits, unresolved}});
      const read = 'SELECT id FROM records';
      assert.deepEqual(await run(read, numbers, {xs: Array(10).fill(1)}),
        expected('undetermined', [], [], protectedSource));
      // Node budget of a valid value (about 18 KB of JSON).
      assert.deepEqual(await run(read, numbers, {xs: Array(9000).fill(1)}),
        expected('undetermined', [], budget, protectedSource));
      // Depth budget.
      assert.deepEqual(await run(read,
        {xs: {type: 'array', items: {type: 'array', items: {type: 'number'}}}},
        {xs: nested(70)}), expected('undetermined', [], budget,
        protectedSource));
      // A definite violation elsewhere is kept, and so is the budget.
      assert.deepEqual(await run('SELECT FROM WHERE', numbers,
        {xs: Array(9000).fill(1)}),
      expected('invalid', [{code: 'query_syntax_invalid'}], budget, []));
      // Declaration budget: more parameters than this check admits.
      assert.deepEqual(await run('SELECT 1 AS n', Object.fromEntries(
        Array.from({length: 1100}, (_, index) => [`p${index}`,
          {type: 'number'}])), null), expected('undetermined', [], budget, []));
      // Text budget: one string value longer than this check admits. HTTP
      // refuses such a body before checking.
      if (entrance === 'local') {
        assert.deepEqual(await run('SELECT @s AS v', {s: {type: 'string'}},
          {s: 'a'.repeat(70000)}), expected('undetermined', [], budget, []));
        // The submitted byte measurement can exceed admission's budget;
        // publishing that measurement must not turn a limit into failure.
        assert.deepEqual(await run('SELECT @s AS v', {s: {type: 'string'}},
          {s: 'a'.repeat(1048577)}), expected('undetermined', [], budget, []));
        // Binding budget: a declared default and a supplied value that are
        // each admissible, but not together.
        const pair = {a: {type: 'string', default: 'a'.repeat(40000)},
          b: {type: 'string'}};
        assert.deepEqual(await run('SELECT @a AS a, @b AS b', pair,
          {b: 'b'.repeat(40000)}), expected('undetermined', [], budget, []),
        '[check-mutation:binding-budget]');
        assert.deepEqual(await run('SELECT @a AS a, @b AS b', pair,
          {b: 'b'.repeat(20000)}), expected('verified', [], [], []));
      }
    });
}

test('http: a malformed check request is refused before checking',
  async t => {
    const client = await httpClient(t, configurations.denied);
    await assert.rejects(client.check(query, {format: 'json'}),
      {code: 'InvalidCheckRequest'});
    const response = await client.post({input: {text: query, format: 'json'},
      parameters: null});
    assert.equal(response.status, 400);
    assert.deepEqual(await response.json(), {code: 'InvalidClientRequest'});
  });

// The Host check owner with a fixed context key, so that whole outcomes,
// context references included, are compared across installations. The same
// acceptance runs against mutated owners below; each mutation must fail it.
const moon = await import(pathToFileURL(join(repository,
  '_build/js/release/build/connectors_builtin_node/' +
  'connectors_builtin_node.js')).href);
const environment = moon.clientProgramCheckEnvironment(
  canonicalText(sourceEnvironment), sourceEnvironment.evidence_bundle_cid,
  false, false, true, true, false, false, false);
const contextKey = new Uint8Array(32).fill(7);

// Actual public ingress with the real admitted checker and read-decision owner.
// A fixed test-only key makes complete envelopes comparable across physically
// different private inventories. No provider or Run handler is installed.
async function contextClient(t, entrance, wire, {aliases = [], readOutcome,
  closed = false, connectionAllowed = true, observations,
  sdkConnect = connect,
  sdkConnectInProcess = connectInProcess,
  localAuthenticate = () => owner,
  maxRequestBytes = 65536,
  reportContextOverflow = false,
  mutateCheckReply,
  mutateCheckTransportReply, mutateUnavailable,
  profiles = [false, false, true, true, false, false, false]} = {}) {
  const admitted = moon.clientProgramCheckEnvironment(canonicalText(wire),
    wire.evidence_bundle_cid, ...profiles);
  assert.notEqual(admitted, undefined, 'context fixture must be admitted');
  const authorization = readOutcome === undefined ? undefined
    : await createNodeAuthorizationGate({configuration: account(readOutcome),
      context: {principal: owner, contextCid: `sha256:${'3'.repeat(64)}`}});
  if (authorization) t.after(() => authorization.close());
  if (closed) authorization.close();
  const observedMoon = observations || reportContextOverflow ? {...moon,
    clientProgramCheckSource: (...args) => {
      if (observations) observations.analysis++;
      // A reporting-capacity fault at the existing producer: even its minimal
      // original binding cannot fit the reserved envelope. No second checker.
      if (reportContextOverflow) args[6] = 'ctx:' + 'x'.repeat(65536);
      return moon.clientProgramCheckSource(...args);
    },
    clientProgramCheckUnavailable: (...args) => {
      if (observations) observations.unavailable++; return moon.clientProgramCheckUnavailable(...args);
    },
  } : moon;
  const check = installNodeClientCheck({moon: observedMoon, environment: admitted, contextKey,
    publication: sourceAliasPublication(moon, admitted, aliases),
    sourceAccesses: authorization === undefined ? [] : [{authorization: observations ? {
      authorize: (...args) => { observations.sourceDecisions++; return authorization.authorize(...args); },
    } : authorization,
      connection: 'local-database', resource: '/records.duckdb',
      sourceRef: aliases[0].sourceRef}]});
  const mode = entrance === 'local' ? 'local' : 'remote';
  const profile = {version: 'actql-client-host/0.1', mode, owner: mode,
    durability: 'volatile', scopeRef: 'check-fixture', capabilities: [],
    limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
      maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
      maxRows: 10, maxBatchRows: 10, maxBatchRetainedValueBytes: 2048}};
  const configuration = {authenticate: localAuthenticate,
    authorizeConnection: value => {
      if (value.operation === 'connect') return true;
      if (observations) observations.authorization++;
      return typeof connectionAllowed === 'function' ? connectionAllowed(value) : connectionAllowed;
    },
    negotiate: () => profile,
    check: mutateCheckReply || mutateUnavailable ? Object.assign(async request => {
      const outcome = await check(request);
      return mutateCheckReply ? mutateCheckReply(outcome) : outcome;
    }, {unavailable: () => mutateUnavailable ? mutateUnavailable(check.unavailable()) : check.unavailable()}) : check,
    maxRowBytes: 1024, maxRequestBytes};
  if (entrance === 'local') {
    const port = createNodeInProcessClientHost(configuration);
    const client = await sdkConnectInProcess({mode, owner: mode},
      mutateCheckTransportReply || observations ? {async perform(operation, body, signal) {
        const value = await port.perform(operation, body, signal);
        if (operation === 'check' && observations) observations.wireOutcomes.push(structuredClone(value));
        return operation === 'check' && mutateCheckTransportReply ? mutateCheckTransportReply(value) : value;
      }} : port);
    t.after(() => client.close());
    return client;
  }
  const handler = createClientHttpHandler({...configuration,
    authenticate: header => header === 'Bearer owner-token' ? owner : undefined});
  const server = createServer({key: tlsKey, cert: tlsCertificate}, (request, response) => {
    if (observations && request.url.endsWith('/check')) {
      response.on('finish', () => observations.statuses.push(response.statusCode));
      const end = response.end.bind(response);
      response.end = (body, ...args) => {
        observations.wireOutcomes.push(JSON.parse(body));
        return end(body, ...args);
      };
    }
    if (mutateCheckTransportReply && request.url.endsWith('/check')) {
      const end = response.end.bind(response);
      response.end = body => end(JSON.stringify(mutateCheckTransportReply(JSON.parse(body))));
    }
    return handler(request, response);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(async () => {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  });
  const client = await sdkConnect({mode,
    endpoint: `https://127.0.0.1:${server.address().port}/`, token: 'owner-token'});
  t.after(() => client.close());
  return client;
}

for (const entrance of ['local', 'http']) {
  test(`${entrance}: check explains owned invalid frame bounds`, async t => {
    const client = await contextClient(t, entrance, sourceEnvironment,
      {aliases: [alias], readOutcome: 'allow'});
    const declarations = {before: {type: 'number', nullable: false},
      after: {type: 'number', nullable: false}};
    for (const [direction, parameters] of [
      ['PRECEDING', {before: 1, after: 2}],
      ['FOLLOWING', {before: 2, after: 1}],
    ]) {
      const text = 'SELECT FIRST_VALUE(amount) OVER '
        + `(ORDER BY id ROWS BETWEEN @before ${direction} AND @after ${direction}) AS first FROM records`;
      const outcome = await client.check(text, {format: 'sql',
        parameterDeclarations: declarations, parameters});
      assert.equal(outcome.outcome, 'completed');
      assert.equal(outcome.report.verdict, 'invalid', JSON.stringify(outcome));
      assert.deepEqual(outcome.report.reasons, [{code: 'query_frame_invalid',
        facts: {issue: 'invalid_bounds'}}], 'check-frame-reason');
      assert.deepEqual(outcome.report.coverage, {limits: [], unresolved: []});
      assert.deepEqual(outcome.report.requirements, []);
      assert.equal(Object.hasOwn(outcome.report.reasons[0], 'location'), false);
      assert.deepEqual(explainCheckReason(outcome.report.reasons[0]), {kind: 'known',
        summary: 'The analytic ROWS frame boundaries do not form a valid interval.',
        hint: 'For two PRECEDING boundaries, the start distance must be at least the end distance; for two FOLLOWING boundaries, it must be at most the end distance.'},
        '[check-mutation:check-frame-explanation]');
      assert.deepEqual(explainCheckReason(outcome.report.reasons[0], {locale: 'ja'}), {kind: 'known',
        summary: 'analytic ROWS frameの境界が有効な区間になっていません。',
        hint: '両境界がPRECEDINGなら開始距離を終了距離以上に、両境界がFOLLOWINGなら開始距離を終了距離以下にしてください。'});
    }
  });
}

for (const entrance of ['local', 'http']) {
  test(`${entrance}: SDK rejects malformed frame facts from an actual check reply`, async t => {
    let mutation = value => value;
    const client = await contextClient(t, entrance, sourceEnvironment,
      {aliases: [alias], readOutcome: 'allow',
        mutateCheckTransportReply: value => mutation(value)});
    const check = () => client.check('SELECT FIRST_VALUE(amount) OVER '
      + '(ORDER BY id ROWS BETWEEN @before PRECEDING AND @after PRECEDING) AS first FROM records',
      {format: 'sql', parameterDeclarations: {before: {type: 'number', nullable: false},
        after: {type: 'number', nullable: false}}, parameters: {before: 1, after: 2}});
    assert.deepEqual((await check()).report.reasons[0].facts, {issue: 'invalid_bounds'});
    for (const facts of [undefined, {}, {issue: 'reversed_preceding'},
      {issue: 'invalid_bounds', requirement_index: 0}, {issue: 'expected_boolean'}]) {
      mutation = value => ({...value, report: {...value.report,
        reasons: [{...value.report.reasons[0], facts}]}});
      await assert.rejects(check(), {code: 'InvalidHostCheckOutcome'});
    }
  });

  test(`${entrance}: protected frames retain safe independent violations`, async t => {
    const clients = [
      await contextClient(t, entrance, sourceEnvironment, {aliases: []}),
      await contextClient(t, entrance, sourceEnvironment, {aliases: [alias], readOutcome: 'deny'}),
      await contextClient(t, entrance, sourceEnvironment, {aliases: [alias], readOutcome: 'allow', closed: true}),
    ];
    const text = 'SELECT FIRST_VALUE(amount) OVER '
      + '(ORDER BY id ROWS BETWEEN @before PRECEDING AND @after PRECEDING) AS first FROM records';
    const declarations = {before: {type: 'number', nullable: false},
      after: {type: 'number', nullable: false}};
    for (const parameters of [{before: 1, after: 2}, {before: 'private-frame-value', after: 2}]) {
      const outcomes = await Promise.all(clients.map(client => client.check(text,
        {format: 'sql', parameterDeclarations: declarations, parameters})));
      assert.deepEqual(outcomes[0], outcomes[1], 'check-frame-disclosure');
      assert.deepEqual(outcomes[0], outcomes[2], 'check-frame-disclosure');
      const invalid = typeof parameters.before === 'string';
      const report = outcomes[0].report;
      assert.equal(report.verdict, invalid ? 'invalid' : 'undetermined');
      assert.deepEqual(report.coverage, {limits: [],
        unresolved: [{boundary: 'source_resolution', reason: 'unresolved_protected'}]});
      assert.deepEqual(report.reasons.map(({code, facts}) => ({code, ...(facts ? {facts} : {})})),
        invalid ? [{code: 'supplied_value_type_mismatch',
          facts: {parameter: 'before', expected_type: 'number', actual_type: 'string'}}] : []);
      assert.equal(JSON.stringify(outcomes).includes('private-frame-value'), false);
      assert.equal(report.reasons.some(reason => reason.code === 'query_frame_invalid'), false);
      if (invalid) assert.equal(resolveCheckLocation(outcomes[0], report.reasons[0].location).pointer, '/before');
    }
  });
}

const withPolicy = (wire, host_policy_profile) => {
  const {evidence_bundle_cid, ...body} = structuredClone(wire);
  body.host_policy_profile = structuredClone(host_policy_profile);
  return {...body, evidence_bundle_cid: `sha256:${createHash('sha256')
    .update(canonicalText(body)).digest('hex')}`};
};
const emptyEnvironment = JSON.parse(await readFile(join(repository,
  'spec/local-check-environment.json'), 'utf8'));
const absentEnvironment = withPolicy(emptyEnvironment, sourceEnvironment.host_policy_profile);

for (const entrance of ['local', 'http']) {
  test(`${entrance}: check accepts ordered and equal frame boundaries`, async t => {
    const wire = withPolicy(sourceEnvironment, {capacity: {
      ...sourceEnvironment.host_policy_profile.capacity,
      max_analytic_input_wire_bytes: 10000, max_analytic_output_wire_bytes: 10000,
      max_analytic_partition_wire_bytes: 10000, max_analytic_frame_memberships: 10000,
    }});
    const client = await contextClient(t, entrance, wire, {aliases: [alias], readOutcome: 'allow'});
    for (const [direction, parameters] of [
      ['PRECEDING', {before: 2, after: 1}], ['FOLLOWING', {before: 1, after: 2}],
      ['PRECEDING', {before: 1, after: 1}], ['FOLLOWING', {before: 1, after: 1}],
    ]) {
      const text = 'SELECT FIRST_VALUE(amount) OVER '
        + `(ORDER BY id ROWS BETWEEN @before ${direction} AND @after ${direction}) AS first FROM records`;
      const outcome = await client.check(text, {format: 'sql',
        parameterDeclarations: {before: {type: 'number', nullable: false},
          after: {type: 'number', nullable: false}}, parameters});
      assert.equal(outcome.outcome, 'completed');
      assert.equal(outcome.report.verdict, 'verified', JSON.stringify(outcome));
      assert.deepEqual(outcome.report.reasons, []);
      assert.deepEqual(outcome.report.requirements, []);
      assert.deepEqual(outcome.report.coverage, {limits: [], unresolved: []});
    }
  });
}

for (const entrance of ['local', 'http']) {
  test(`${entrance}: check locales retain protected equivalence and frontier`, async t => {
    const clients = [
      await contextClient(t, entrance, absentEnvironment),
      await contextClient(t, entrance, sourceEnvironment, {aliases: [alias], readOutcome: 'deny'}),
      await contextClient(t, entrance, sourceEnvironment, {aliases: [alias], readOutcome: 'allow', closed: true}),
    ];
    const outcomes = [];
    for (const client of clients) {
      const outcome = await client.check('SELECT id FROM records WHERE amount >= @p', {
        format: 'sql', parameterDeclarations: {p: {type: 'number'}},
        parameters: {p: 'secret-locale-value'},
      });
      assert.equal(outcome.outcome, 'completed');
      assert.equal(outcome.report.verdict, 'invalid');
      assert.equal(outcome.report.reasons[0].code, 'supplied_value_type_mismatch');
      assert.deepEqual(outcome.report.coverage.unresolved, protectedSource);
      for (const locale of ['en', 'ja', 'fr']) {
        const explanation = sdk.explainCheckOutcome(outcome, {locale});
        const reason = sdk.explainCheckReason(outcome.report.reasons[0], {locale});
        assert.equal(explanation.report.verdict, 'invalid');
        assert.equal(reason.kind, 'known');
        assert.equal(JSON.stringify([explanation, reason]).includes('secret-locale-value'), false);
      }
      assert.deepEqual(sdk.explainCheckReason({code: 'unresolved_protected'}, {locale: 'ja'}),
        {kind: 'known', summary: '開示された文脈ではSource解決を確定できません。',
          hint: 'Sourceまたは検査文脈の管理者に公開文脈の確認を依頼してください。'});
      outcomes.push(outcome);
    }
    for (const outcome of outcomes.slice(1)) {
      assert.deepEqual(outcome, outcomes[0], '[check-mutation:check-locale-disclosure]');
      for (const locale of ['en', 'ja', 'fr']) {
        assert.deepEqual(sdk.explainCheckOutcome(outcome, {locale}),
          sdk.explainCheckOutcome(outcomes[0], {locale}));
      }
    }
    const missing = await clients[0].check('SELECT @p AS n', {format: 'sql',
      parameterDeclarations: {p: {type: 'number'}}, parameters: {}});
    const frontier = sdk.getCheckRequirementFrontier(missing);
    for (const locale of ['en', 'ja', 'fr']) {
      sdk.explainCheckOutcome(missing, {locale});
      sdk.explainCheckReason(missing.report.requirements[0], {locale});
      assert.deepEqual(sdk.getCheckRequirementFrontier(missing), frontier);
    }
  });

  test(`${entrance}: check locales preserve observations and safe fallback`, async t => {
    let requests = 0;
    const client = await contextClient(t, entrance, absentEnvironment, {
      mutateCheckTransportReply(outcome) { requests++; return outcome; },
    });
    const words = ({summary, hint}) => ({summary, ...(hint === undefined ? {} : {hint})});
    const control = ({summary, hint, ...rest}) => rest;
    const cases = [
      ['/*😀*/\r\nSELECT', {}, 'invalid', 'query_syntax_invalid',
        '検査範囲内の入力違反が確認されました。',
        {kind: 'known', summary: 'クエリの構文が不正です。',
          hint: '位置が示されている場合は、その位置のクエリ構文を修正してください。'}],
      ['SELECT @p AS n', {}, 'invalid', 'parameter_undeclared',
        '検査範囲内の入力違反が確認されました。',
        {kind: 'known', summary: 'クエリが未宣言のパラメータを参照しています。',
          hint: 'パラメータを宣言するか参照を修正してください。値を渡すだけでは宣言になりません。'}],
      ['SELECT @p AS n', {parameterDeclarations: {p: {type: 'number'}},
        parameters: {p: 'secret-locale-value'}}, 'invalid', 'supplied_value_type_mismatch',
        '検査範囲内の入力違反が確認されました。',
        {kind: 'known', summary: '渡された値の型が宣言と一致しません。',
          hint: '宣言された型の値を渡してください。'}],
      ['SELECT @p AS n', {parameterDeclarations: {p: {type: 'number'}}, parameters: {}},
        'undetermined', 'parameter_value_required',
        '検査範囲内では、検証成功も確定した入力違反も判断できません。',
        {kind: 'known', summary: '宣言されたパラメータの値が不足しています。',
          hint: '宣言された値を補い、束縛された入力全体を再検査してください。'}],
      ['SELECT 1 AS n', {}, 'verified', undefined,
        'この報告が検証するのは、束縛された検査範囲と文脈だけです。'],
    ];
    for (const [text, options, verdict, code, summary, reasonExplanation] of cases) {
      const outcome = await client.check(text, {format: 'sql', ...options});
      const count = requests;
      const original = JSON.stringify(outcome);
      assert.equal(outcome.report.verdict, verdict);
      const english = sdk.explainCheckOutcome(outcome);
      const japanese = sdk.explainCheckOutcome(outcome, {locale: 'ja'});
      assert.deepEqual(control(japanese), control(english), '[check-mutation:check-locale-control]');
      if (code === 'query_syntax_invalid') {
        const expected = {summary: 'The report establishes an input violation in its checking scope.',
          hint: 'Review the disclosed reasons and correct the submitted revision where indicated.'};
        const brokenLocale = {get locale() { throw new Error('private locale failure'); }};
        for (const locale of [{locale: 'fr'}, {locale: 'ja-unknown'}, brokenLocale]) {
          assert.deepEqual(words(sdk.explainCheckOutcome(outcome, locale)), expected,
            '[check-mutation:check-locale-fallback]');
        }
        assert.equal(outcome.report.reasons[0].location.start_byte, 16);
        assert.equal(outcome.report.reasons[0].location.end_byte, 16);
      }
      assert.equal(japanese.summary, summary, '[check-mutation:check-locale-presentation]');
      assert.deepEqual(sdk.explainCheckOutcome(outcome, {locale: 'ja-JP'}), japanese);
      const reason = [...outcome.report.reasons, ...outcome.report.requirements]
        .find(value => value.code === code);
      if (reason) {
        const originalLocation = reason.location && resolveCheckLocation(outcome, reason.location);
        const localized = sdk.explainCheckReason(reason, {locale: 'ja'});
        assert.deepEqual(localized, reasonExplanation, '[check-mutation:check-locale-reason]');
        assert.deepEqual(control(localized), control(sdk.explainCheckReason(reason)));
        assert.equal(Object.hasOwn(localized, 'next'), false);
        if (reason.location) assert.deepEqual(resolveCheckLocation(outcome, reason.location), originalLocation);
      }
      assert.equal(Object.hasOwn(japanese, 'next'), false);
      assert.equal(JSON.stringify(japanese).includes('secret-locale-value'), false);
      assert.equal(JSON.stringify(outcome), original);
      assert.equal(requests, count, 'Presentation performs no additional check or execution I/O');
      assert.deepEqual(sdk.getCheckPresentationInfo({locale: 'ja'}),
        {locale: 'ja', translationRevision: '2026-10-07.ja.7'});
    }
    const declarations = Object.fromEntries(Array.from({length: 512}, (_, i) =>
      [`p${String(i).padStart(3, '0')}`, {type: 'number'}]));
    const reportingFailure = await contextClient(t, entrance, absentEnvironment, {reportContextOverflow: true});
    const failed = await reportingFailure.check('SELECT 1 AS n', {format: 'sql',
      parameterDeclarations: declarations, parameters: {}});
    assert.equal(failed.outcome, 'failed');
    const explanation = sdk.explainCheckOutcome(failed, {locale: 'ja'});
    assert.equal(explanation.summary, '報告用の予算内では、束縛された検査報告全体を作成できませんでした。');
    assert.deepEqual(control(explanation), control(sdk.explainCheckOutcome(failed)));
    assert.equal(explanation.correlationRef, failed.correlation_ref);
    assert.equal(Object.hasOwn(explanation, 'report'), false);
    assert.equal(Object.hasOwn(explanation, 'next'), false);
    assert.equal(getCheckInput(structuredClone(failed), 'source'), undefined);
  });

  test(`${entrance}: default type violations retain declaration input and the owned leaf type`, async t => {
    const client = await contextClient(t, entrance, absentEnvironment);
    const cases = [
      [{minimum: {type: 'number', default: 'private-default'}}, 'minimum',
        '/minimum/default', 'number', 'string'],
      [{payload: {type: 'object', fields: {rows: {type: 'array', items: {type: 'number'}}},
        default: {rows: ['private-default']}}}, 'payload', '/payload/default/rows/0', 'number', 'string'],
      [{payload: {type: 'object', fields: {'x/~': {type: 'number'}},
        default: {'x/~': 'private-default'}}}, 'payload', '/payload/default/x~1~0', 'number', 'string'],
      [{payload: {type: 'object', fields: {'e\u0301/~😀': {type: 'number'}},
        default: {'e\u0301/~😀': 'private-default'}}}, 'payload',
      '/payload/default/e\u0301~1~0😀', 'number', 'string'],
      [{minimum: {type: 'number', nullable: false, default: null}}, 'minimum',
        '/minimum/default', 'number', 'null'],
    ];
    for (const [parameterDeclarations, parameter, pointer, expected_type, actual_type] of cases) {
      const original = structuredClone(parameterDeclarations);
      const outcome = await client.check('SELECT 1 AS n', {format: 'sql', parameterDeclarations});
      assert.equal(outcome.outcome, 'completed');
      assert.equal(outcome.report.verdict, 'invalid', '[check-mutation:default-verdict]');
      const input = getCheckInput(outcome, 'parameter_declarations');
      assert.deepEqual(input.value, original);
      assert.deepEqual(outcome.report.reasons, [{code: 'parameter_default_type_mismatch',
        facts: {parameter, expected_type, actual_type}, location: {
          document_id: 'parameter_declarations', revision: input.revision,
          kind: 'structured', pointer}}], '[check-mutation:default-reason]');
      assert.deepEqual(outcome.report.requirements, []);
      assert.deepEqual(outcome.report.coverage, {limits: [], unresolved: []});
      assert.equal(resolveCheckLocation(outcome, outcome.report.reasons[0].location).input, input);
      assert.equal(JSON.stringify(outcome).includes('private-default'), false);
      assert.deepEqual(explainCheckReason(outcome.report.reasons[0]), {kind: 'known',
        summary: 'A parameter default does not match its declared type.',
        hint: 'Correct the default to match the declared type, then check again.'});
    }
    const valid = await client.check('SELECT @minimum AS n', {format: 'sql',
      parameterDeclarations: {minimum: {type: 'number', default: 7}}});
    assert.equal(valid.report.verdict, 'verified', JSON.stringify(valid.report));
    assert.deepEqual(valid.report.reasons, []);
    assert.deepEqual(valid.report.requirements, []);
  });

  test(`${entrance}: Subgraph selector violations preserve the common Owner reason`, async t => {
    const client = await contextClient(t, entrance, absentEnvironment);
    const prefix = 'DATA n = SELECT 1 AS node_key; DATA g = PROPERTY GRAPH ' +
      '(NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES)); ';
    for (const selector of ['[1]', '{ids: []}', '{ids: [], unknown: true}']) {
      const text = prefix + `FROM g |> subgraph(nodes: ${selector}) |> node_rows() |> SELECT node_key`;
      const outcome = await client.check(text, {format: 'aql-text'});
      assert.equal(outcome.outcome, 'completed');
      assert.equal(outcome.report.verdict, 'invalid', '[check-mutation:subgraph-verdict]');
      assert.deepEqual(outcome.report.reasons, [{code: 'graph_operation_invalid',
        facts: {operation: 'subgraph', issue: 'invalid_node_selector'}}],
      '[check-mutation:subgraph-reason]');
      assert.deepEqual(outcome.report.coverage, {limits: [], unresolved: []});
      assert.deepEqual(explainCheckReason(outcome.report.reasons[0]), {kind: 'known',
        summary: 'The Subgraph node selector is invalid.',
        hint: 'Provide one selector: nonempty ids, a named Relation with an id field, or a node where predicate.'});
      assert.equal(getCheckInput(outcome, 'source').text, text);
    }
    const unsupported = await client.check(prefix +
      'FROM g |> subgraph(nodes: {where: "true"}) |> node_rows() |> SELECT node_key',
    {format: 'aql-text'});
    assert.equal(unsupported.outcome, 'completed');
    assert.equal(unsupported.report.verdict, 'undetermined', '[check-mutation:subgraph-limit-verdict]');
    assert.deepEqual(unsupported.report.reasons, []);
    assert.deepEqual(unsupported.report.coverage.limits, [{code: 'implementation_limit'}],
      '[check-mutation:subgraph-limit]');
    const denied = await contextClient(t, entrance, sourceEnvironment,
      {aliases: [alias], readOutcome: 'deny'});
    const protectedText = prefix.replace('SELECT 1 AS node_key',
      'SELECT id AS node_key FROM records') +
      'FROM g |> subgraph(nodes: [1]) |> node_rows() |> SELECT node_key';
    for (const wrongType of [false, true]) {
      const outcomes = [];
      for (const boundary of [client, denied]) {
        const outcome = await boundary.check(protectedText, {format: 'aql-text',
          parameterDeclarations: declarations,
          parameters: {minimum: wrongType ? 'private-value' : 1}});
        assert.equal(outcome.outcome, 'completed');
        assert.deepEqual({verdict: outcome.report.verdict,
          reasons: outcome.report.reasons.map(({location, ...reason}) => reason),
          coverage: outcome.report.coverage}, {
          verdict: wrongType ? 'invalid' : 'undetermined',
          reasons: wrongType ? [{code: 'supplied_value_type_mismatch', facts: {
            parameter: 'minimum', expected_type: 'number', actual_type: 'string'}}] : [],
          coverage: {limits: [], unresolved: protectedSource},
        }, '[check-mutation:subgraph-protected]');
        outcomes.push(outcome);
      }
      assert.deepEqual(outcomes[0], outcomes[1],
        'Absent and denied dependencies have equivalent complete public envelopes');
    }
  });

  test(`${entrance}: check Problems retain opaque attempt correlation`, async t => {
    const client = await contextClient(t, entrance, absentEnvironment, {reportContextOverflow: true});
    const parameterDeclarations = Object.fromEntries(Array.from({length: 512}, (_, i) =>
      [`p${String(i).padStart(3, '0')}`, {type: 'number'}]));
    const options = {format: 'sql', parameterDeclarations, parameters: {}};
    const first = await client.check('SELECT 1 AS n', options);
    assert.equal(first.outcome, 'failed');
    assert.equal(first.problem.code, 'check_report_unbounded');
    assert.equal(typeof first.correlation_ref, 'string', '[check-mutation:check-problem-correlation]');
    assert.match(first.correlation_ref, /^corr:[0-9a-f]{32}$/u);
    const second = await client.check('SELECT 1 AS n', options);
    assert.notEqual(second.correlation_ref, first.correlation_ref,
      '[check-mutation:check-problem-attempt]');
    assert.equal(sdk.explainCheckOutcome(first).correlationRef, first.correlation_ref,
      '[check-mutation:check-problem-explanation]');
    assert.equal(sdk.explainCheckOutcome(structuredClone(first)).correlationRef, first.correlation_ref);
    for (const outcome of [first, second]) {
      assert.equal(Object.hasOwn(outcome, 'report'), false);
      assert.equal(Object.hasOwn(outcome, 'partial_report'), false);
      assert.equal(Object.hasOwn(outcome, 'context_ref'), false);
      assert.equal(getCheckInput(outcome, 'source'), undefined);
      assert.equal(Object.hasOwn(sdk.explainCheckOutcome(outcome), 'next'), false);
    }
  });

  test(`${entrance}: check outcome pins refuse mismatches with unchanged reason identity`, async t => {
    const declarations = Object.fromEntries(Array.from({length: 512}, (_, i) =>
      [`p${String(i).padStart(3, '0')}`, {type: 'number'}]));
    for (const failed of [false, true]) {
      for (const mutation of ['missing', 'different']) {
        const client = await contextClient(t, entrance, absentEnvironment, {
          reportContextOverflow: failed,
          mutateCheckTransportReply(outcome) {
            assert.equal(outcome.outcome, failed ? 'failed' : 'completed');
            assert.equal(outcome.reason_schema_cid, checkReasonSchemaCid);
            if (mutation === 'missing') delete outcome.outcome_schema_cid;
            else outcome.outcome_schema_cid = 'sha256:' + '0'.repeat(64);
            return outcome;
          },
        });
        let refused = false;
        try {
          await client.check('SELECT 1 AS n', {format: 'sql',
            ...(failed ? {parameterDeclarations: declarations, parameters: {}} : {})});
        } catch (cause) {
          if (cause?.code !== 'InvalidHostCheckOutcome') throw cause;
          refused = true;
        }
        assert.equal(refused, true, '[check-mutation:check-outcome-pin]');
      }
    }
  });

  test(`${entrance}: check outcome explanations preserve reporting boundaries`, async t => {
    const client = await contextClient(t, entrance, absentEnvironment,
      {maxRequestBytes: 262144, reportContextOverflow: true});
    // The separately reserved minimal envelope is deliberately unavailable.
    // Analysis still runs once through the existing checker.
    const declarations = Object.fromEntries(Array.from({length: 512}, (_, i) =>
      [`p${String(i).padStart(3, '0')}`, {type: 'number'}]));
    const unbounded = await client.check('SELECT 1 AS n', {format: 'sql',
      parameterDeclarations: declarations, parameters: {}});
    assert.match(unbounded.correlation_ref, /^corr:[0-9a-f]{32}$/u);
    assert.deepEqual(unbounded, {version: 'actql-check-outcome/0.1',
      reason_schema_cid: checkReasonSchemaCid, outcome_schema_cid: checkOutcomeSchemaCid,
      outcome: 'failed', correlation_ref: unbounded.correlation_ref,
      problem: {code: 'check_report_unbounded'}});
    assert.equal(typeof sdk.explainCheckOutcome, 'function',
      '[check-mutation:check-outcome-explanation]');
    assert.deepEqual(sdk.explainCheckOutcome(unbounded), {outcome: 'failed', correlationRef: unbounded.correlation_ref,
      problem: {kind: 'known', code: 'check_report_unbounded'},
      summary: 'The reporting budget could not produce a complete bound check report.',
      hint: 'Ask the checking-context owner to review reporting capacity for the original checking scope.'},
    '[check-mutation:check-outcome-explanation]');

    const ordinaryCases = await contextClient(t, entrance, absentEnvironment);
    for (const [text, options, verdict, summary, hint] of [
      ['SELECT 1 AS n', {}, 'verified',
        'The report verifies only its bound checking scope and context.',
        'Use the execution, cancellation and release owners for their respective results.'],
      ['SELECT', {}, 'invalid',
        'The report establishes an input violation in its checking scope.',
        'Review the disclosed reasons and correct the submitted revision where indicated.'],
      ['SELECT @x AS n', {parameterDeclarations: {x: {type: 'number'}}, parameters: {}},
        'undetermined',
        'The report cannot establish verification or a proven input violation in its checking scope.',
        'Review missing inputs and disclosed checking limits; an outstanding obligation is not an input error.'],
    ]) {
      const outcome = await ordinaryCases.check(text, {format: 'sql', ...options});
      assert.equal(outcome.outcome, 'completed');
      assert.equal(outcome.report.verdict, verdict);
      const expected = {outcome: 'completed', summary, hint,
        report: {completeness: 'complete', verdict, scope: {kind: 'bound_input'},
          contextRef: outcome.report.context_ref}};
      const explanation = sdk.explainCheckOutcome(outcome);
      assert.deepEqual(explanation, expected, '[check-mutation:check-outcome-explanation]');
      assert.equal(Object.isFrozen(explanation.report.scope), true);
      // Safe text survives transport copies; original-input custody does not.
      const copy = structuredClone(outcome);
      assert.deepEqual(sdk.explainCheckOutcome(copy), expected);
      assert.equal(getCheckInput(copy, 'source'), undefined);
    }
    const overBudget = `/*${'é'.repeat(32758)}*/SELECT 1 AS n`;
    assert.equal(Buffer.byteLength(overBudget), 65533);
    const ordinary = await contextClient(t, entrance, absentEnvironment, {maxRequestBytes: 262144});
    const analysis = await ordinary.check(overBudget + '    ', {format: 'sql'});
    assert.equal(analysis.outcome, 'completed');
    assert.equal(analysis.report.verdict, 'undetermined');
    assert.deepEqual(analysis.report.coverage.limits, [{code: 'analysis_budget_exhausted'}]);
    assert.equal(sdk.explainCheckOutcome(analysis).report.verdict, 'undetermined',
      '[check-mutation:check-outcome-explanation]');
    assert.equal(sdk.explainCheckOutcome(analysis).report.completeness, 'complete');
  });

  test(`${entrance}: check outcome explanations preserve partial and unavailable boundaries`, async t => {
    let branch = 'partial';
    const client = await contextClient(t, entrance, absentEnvironment, {
      // Fault injection into the real Host boundary. These two shapes are
      // schema acceptance evidence, not claims of a natural Owner failure.
      mutateCheckReply: outcome => branch === 'partial' ? {
        version: outcome.version, reason_schema_cid: outcome.reason_schema_cid, outcome_schema_cid: outcome.outcome_schema_cid,
        outcome: 'failed', correlation_ref: 'corr:fixture', problem: {code: 'check_internal'}, partial_report: outcome.report,
      } : {version: outcome.version, reason_schema_cid: outcome.reason_schema_cid, outcome_schema_cid: outcome.outcome_schema_cid,
        outcome: 'unavailable', correlation_ref: 'corr:check-fixture',
        problem: {code: 'check_unavailable'}},
    });
    const partial = await client.check('SELECT', {format: 'sql'});
    const explanation = sdk.explainCheckOutcome(partial);
    assert.deepEqual(explanation, {outcome: 'failed', correlationRef: 'corr:fixture',
      problem: {kind: 'known', code: 'check_internal'},
      summary: 'An internal checking failure prevented a complete bound check report.',
      hint: 'Ask the checking-context owner to investigate the reporting failure.',
      report: {completeness: 'partial', verdict: 'invalid', scope: {kind: 'bound_input'},
        contextRef: partial.partial_report.context_ref}},
    '[check-mutation:check-outcome-partial]');
    assert.equal(resolveCheckLocation(partial, partial.partial_report.reasons[0].location).text, '');
    branch = 'unavailable';
    const unavailable = await client.check('SELECT 1 AS n', {format: 'sql'});
    assert.deepEqual(sdk.explainCheckOutcome(unavailable), {outcome: 'unavailable',
      problem: {kind: 'known', code: 'check_unavailable'}, correlationRef: 'corr:check-fixture',
      summary: 'The scope and checking context needed for a safe public report are unavailable.',
      hint: 'Ask the checking-context owner to review the published context; this response does not establish an input error.'},
    '[check-mutation:check-outcome-unavailable]');
    assert.equal(getCheckInput(unavailable, 'source'), undefined);
    assert.deepEqual(sdk.explainCheckOutcome(partial), explanation);
    const copied = structuredClone(partial);
    copied.partial_report.verdict = 'verified';
    copied.partial_report.reasons = [];
    assert.equal(sdk.explainCheckOutcome(copied), undefined,
      '[check-mutation:check-outcome-invalid]');
  });
}
const numericContract = JSON.parse(await readFile(join(repository,
  'spec/contracts/actql-numeric-reduction.json'), 'utf8'));
const graphLaw = JSON.parse(await readFile(join(repository,
  'spec/dependencies/actql-graph-laws.json'), 'utf8'));
const fixtureCid = value => `sha256:${createHash('sha256')
  .update(canonicalText(value)).digest('hex')}`;

for (const entrance of ['local', 'http']) {
  test(`${entrance}: reused check replies retain independent Requirement frontiers`, async t => {
    const cache = {};
    const client = await contextClient(t, entrance, absentEnvironment, {mutateCheckReply(outcome) {
      for (const key of Object.keys(cache)) delete cache[key];
      return Object.assign(cache, outcome);
    }});
    const options = {format: 'sql', parameterDeclarations: {x: {type: 'number'}}};
    const missing = await client.check('SELECT @x AS n', options);
    const frontier = frontierSDK.getCheckRequirementFrontier(missing);
    assert.deepEqual(frontier.requirements, [{code: 'parameter_value_required',
      facts: {parameter: 'x', expected_type: 'number', admission: expectedNumberAdmission}}], '[check-mutation:frontier-custody]');
    assert.equal(frontierSDK.getCheckRequirementFrontier(cache), undefined);
    const supplied = await client.check('SELECT @x AS n', {...options, parameters: {x: 1}});
    assert.equal(supplied.report.verdict, 'verified');
    assert.equal(frontierSDK.getCheckRequirementFrontier(missing), frontier,
      '[check-mutation:frontier-custody]');
    assert.equal(frontierSDK.equalCheckRequirementFrontiers(missing, supplied), false,
      '[check-mutation:frontier-custody]');
    assert.equal(frontierSDK.getCheckRequirementFrontier(cache), undefined);
    assert.equal(sdk.explainCheckOutcome(missing).report.verdict, 'undetermined');
    assert.equal(sdk.explainCheckOutcome(supplied).report.verdict, 'verified');
  });

  test(`${entrance}: reused check replies preserve original syntax inputs and positions`, async t => {
    const cache = {};
    const client = await contextClient(t, entrance, absentEnvironment, {mutateCheckReply(outcome) {
      for (const key of Object.keys(cache)) delete cache[key];
      return Object.assign(cache, outcome);
    }});
    const first = await client.check('SELECT', {format: 'sql'});
    assert.equal(first.outcome, 'completed');
    assert.equal(first.report.verdict, 'invalid');
    const original = getCheckInput(first, 'source');
    const location = first.report.reasons[0].location;
    assert.deepEqual(location, {kind: 'text', document_id: 'source', revision: original.revision,
      start_byte: 6, end_byte: 6, precision: 'exact'});
    assert.equal(original.text, 'SELECT');
    assert.equal(Object.isFrozen(first), true);
    assert.equal(Object.isFrozen(cache), false, '[check-mutation:check-response-custody]');
    assert.equal(Object.isFrozen(cache.report), false, '[check-mutation:check-response-custody]');
    const text = "\ufeffSELECT 'é😀e\u0301' AS x,\r\n";
    const second = await client.check(text, {format: 'sql'});
    const next = getCheckInput(second, 'source');
    assert.equal(second.report.verdict, 'invalid');
    assert.notEqual(first, second);
    assert.notEqual(first.report.context_ref, second.report.context_ref);
    assert.notEqual(original.revision, next.revision);
    assert.equal(next.text, text);
    assert.deepEqual(second.report.reasons[0].location, {kind: 'text', document_id: 'source',
      revision: next.revision, start_byte: 29, end_byte: 29, precision: 'exact'});
    assert.deepEqual(resolveCheckTextRange(second, second.report.reasons[0].location).range,
      {start: {line: 1, character: 0}, end: {line: 1, character: 0}});
    const verified = await client.check('SELECT 1 AS n', {format: 'sql'});
    assert.equal(verified.report.verdict, 'verified');
    assert.equal(first.report.verdict, 'invalid');
    assert.equal(getCheckInput(first, 'source'), original);
    assert.equal(resolveCheckLocation(first, location).input, original);
    assert.deepEqual(resolveCheckTextRange(first, location).range,
      {start: {line: 0, character: 6}, end: {line: 0, character: 6}});
    assert.equal(resolveCheckLocation(first, location, next), undefined);
    assert.equal(resolveCheckTextRange(first, location, next), undefined);
    assert.equal(resolveCheckLocation(structuredClone(first), location), undefined);
    assert.equal(Object.isFrozen(cache), false, '[check-mutation:check-response-custody]');
  });

  test(`${entrance}: reused check replies retain structured and partial input custody`, async t => {
    const cache = {};
    let reporting = 'completed';
    const client = await contextClient(t, entrance, absentEnvironment, {mutateCheckReply(outcome) {
      // Reporting-failure injection carries the exact real checker report.
      const received = reporting === 'partial' ? {version: outcome.version,
        reason_schema_cid: outcome.reason_schema_cid, outcome_schema_cid: outcome.outcome_schema_cid, outcome: 'failed', correlation_ref: 'corr:fixture',
        problem: {code: 'check_internal'}, partial_report: outcome.report}
        : reporting === 'unavailable' ? {version: outcome.version,
          reason_schema_cid: outcome.reason_schema_cid, outcome_schema_cid: outcome.outcome_schema_cid, outcome: 'unavailable',
          problem: {code: 'check_unavailable'}, correlation_ref: 'fixture-unavailable'} : outcome;
      for (const key of Object.keys(cache)) delete cache[key];
      return Object.assign(cache, received);
    }});
    const parameters = {x: 'original-secret'};
    const options = {format: 'sql', parameterDeclarations: {x: {type: 'number'}}, parameters};
    const first = await client.check('SELECT @x AS n', options);
    assert.equal(first.report.verdict, 'invalid');
    assert.deepEqual(first.report.reasons[0].facts,
      {parameter: 'x', expected_type: 'number', actual_type: 'string'});
    const original = getCheckInput(first, 'parameters');
    const location = first.report.reasons[0].location;
    assert.deepEqual(location, {kind: 'structured', document_id: 'parameters',
      revision: original.revision, pointer: '/x'});
    assert.equal(JSON.stringify(first).includes('original-secret'), false);
    assert.equal(Object.isFrozen(cache), false, '[check-mutation:check-response-custody]');
    parameters.x = 1;
    const second = await client.check('SELECT @x AS n', options);
    assert.equal(second.report.verdict, 'verified');
    const next = getCheckInput(second, 'parameters');
    assert.deepEqual(next.value, {x: 1});
    assert.notEqual(next.revision, original.revision);
    assert.notEqual(first.report.context_ref, second.report.context_ref);
    assert.deepEqual(getCheckInput(first, 'parameters').value, {x: 'original-secret'});
    assert.equal(resolveCheckLocation(first, location, next), undefined);
    reporting = 'partial';
    const partial = await client.check('SELECT @x AS n', {...options, parameters: {x: 'original-secret'}});
    assert.equal(partial.outcome, 'failed');
    assert.equal(partial.partial_report.verdict, 'invalid');
    const partialInput = getCheckInput(partial, 'parameters');
    const partialLocation = partial.partial_report.reasons[0].location;
    assert.deepEqual(resolveCheckLocation(partial, partialLocation).input.value, {x: 'original-secret'});
    reporting = 'unavailable';
    const unavailable = await client.check('SELECT @x AS n', options);
    assert.equal(unavailable.outcome, 'unavailable');
    assert.equal(getCheckInput(unavailable, 'source'), undefined);
    assert.equal(unavailable.report, undefined);
    assert.equal(unavailable.partial_report, undefined);
    assert.equal(getCheckInput(partial, 'parameters'), partialInput);
    assert.equal(partial.outcome, 'failed');
    assert.equal(resolveCheckLocation(partial, partialLocation).input, partialInput);
    assert.equal(first.outcome, 'completed');
    assert.equal(first.report.verdict, 'invalid');
    assert.equal(getCheckInput(first, 'parameters'), original);
    assert.deepEqual(resolveCheckLocation(first, location).input.value, {x: 'original-secret'});
    assert.equal(resolveCheckLocation(structuredClone(partial), partialLocation), undefined);
  });
}

test('local: check reply custody refuses uncloneable values and copied shape loss', async t => {
  for (const kind of ['proxy', 'date']) {
    const client = await contextClient(t, 'local', absentEnvironment, {mutateCheckReply(outcome) {
      // Both values satisfy the incoming shape; copying must preserve a valid
      // plain public envelope before the SDK associates any original input.
      const received = kind === 'proxy' ? new Proxy(outcome, {}) : Object.assign(new Date(0), outcome);
      assert.equal(validCheckOutcome(received), true);
      return received;
    }});
    let refused = false;
    try { await client.check('SELECT', {format: 'sql'}); }
    catch (cause) {
      if (cause?.code !== 'InvalidHostCheckOutcome') throw cause;
      refused = true;
    }
    assert.equal(refused, true, '[check-mutation:check-copied-shape]');
  }
});

test('the admitted checker exposes exact selections without private Source inventories', () => {
  const flags = ['text_time', 'veca', 'rela', 'sga', 'tea', 'calendar', 'text_rank'];
  for (const enabled of [undefined, ...flags]) {
    const choices = flags.map(flag => flag === enabled);
    const admitted = moon.clientProgramCheckEnvironment(canonicalText(absentEnvironment),
      absentEnvironment.evidence_bundle_cid, ...choices);
    assert.notEqual(admitted, undefined);
    const expected = {host_policy_profile: sourceEnvironment.host_policy_profile,
      model_task_contract_cids: [], profiles: {
        ...Object.fromEntries(flags.map(flag => [flag, flag === enabled])),
        graph: false, graph_law_cid: null, model_tasks: true,
        numeric_profile_cid: null, calendar_profile_cid: null, text_rank_profile_cid: null}};
    assert.deepEqual(JSON.parse(moon.clientProgramCheckContextIdentity(admitted)), expected);
  }
  const numericCid = fixtureCid(numericContract);
  const propertyCid = fixtureCid(graphLaw);
  const numeric = moon.clientProgramCheckEnvironmentWithNumericProfile(
    canonicalText(absentEnvironment), absentEnvironment.evidence_bundle_cid,
    false, false, true, true, false, false, false, numericCid);
  assert.notEqual(numeric, undefined);
  assert.equal(JSON.parse(moon.clientProgramCheckContextIdentity(numeric))
    .profiles.numeric_profile_cid, numericCid);
  const graph = moon.clientProgramCheckEnvironmentWithGraphProfile(
    canonicalText(absentEnvironment), absentEnvironment.evidence_bundle_cid,
    false, false, true, true, false, false, false, numericCid, propertyCid);
  assert.notEqual(graph, undefined);
  assert.deepEqual(JSON.parse(moon.clientProgramCheckContextIdentity(graph)).profiles,
    {text_time: false, veca: false, rela: true, sga: true, tea: false,
      calendar: false, text_rank: false, graph: true,
      graph_law_cid: propertyCid, model_tasks: true,
      numeric_profile_cid: numericCid, calendar_profile_cid: null, text_rank_profile_cid: null});
  const paddedPolicy = {capacity: sourceEnvironment.host_policy_profile.capacity,
    padding: ''};
  const initialWire = withPolicy(emptyEnvironment, paddedPolicy);
  paddedPolicy.padding = 'x'.repeat(65536 - Buffer.byteLength(canonicalText(initialWire)));
  const paddedWire = withPolicy(emptyEnvironment, paddedPolicy);
  assert.equal(Buffer.byteLength(canonicalText(paddedWire)), 65536);
  const padded = moon.clientProgramCheckEnvironment(canonicalText(paddedWire),
    paddedWire.evidence_bundle_cid, false, false, true, true, false, false, false);
  assert.notEqual(padded, undefined, 'maximum-size wire fixture must be admitted');
  assert.deepEqual(JSON.parse(moon.clientProgramCheckContextIdentity(padded))
    .host_policy_profile, paddedPolicy, 'projection reserves its own metadata overhead');
});

for (const entrance of ['local', 'http']) {
  test(`${entrance}: typed expression explanations retain original source ranges`, async t => {
    const clients = [
      await contextClient(t, entrance, absentEnvironment),
      await contextClient(t, entrance, sourceEnvironment, {aliases: [alias], readOutcome: 'deny'}),
      await contextClient(t, entrance, sourceEnvironment, {aliases: [alias], readOutcome: 'allow', closed: true}),
      await contextClient(t, entrance, withPolicy(rightEnvironment, sourceEnvironment.host_policy_profile),
        {aliases: [rightAlias], readOutcome: 'delegate'}),
    ];
    // Literal expectations describe the authored UTF-8 bytes, not a lowered path.
    const cases = [
      ['/*😀*/\r\nSELECT missing AS n', 'unknown_reference', 17, 24, 'missing',
        'Use a declared reference from the disclosed query context.'],
      ['/*😀*/\r\nSELECT CONCAT() AS n', 'invalid_arguments', 17, 25, 'CONCAT()',
        'Correct the argument count or form required by the selected operation.'],
      ['/*😀*/\r\nSELECT SQRT(1, 2) AS n', 'invalid_arguments', 17, 27, 'SQRT(1, 2)',
        'Correct the argument count or form required by the selected operation.'],
      ['/*😀*/\r\nSELECT 9007199254740992 AS n', 'invalid_number', 17, 33, '9007199254740992',
        'Use a finite number in the admitted precision and signed-zero domain.'],
      ['/*😀*/\r\nSELECT 1e999 AS n', 'invalid_number', 17, 22, '1e999',
        'Use a finite number in the admitted precision and signed-zero domain.'],
      ['/*😀*/\r\nSELECT -0 AS n', 'invalid_number', 17, 19, '-0',
        'Use a finite number in the admitted precision and signed-zero domain.'],
    ];
    for (const format of ['sql', 'aql-text']) for (const [text, issue, start, end, token, hint] of cases) {
      let originalOutcome;
      for (const client of clients) {
        const pending = client.check(text, {format});
        const edited = 'SELECT 1 AS n';
        const outcome = await pending;
        assert.equal(outcome.outcome, 'completed', '[check-mutation:expression-outcome]');
        assert.equal(outcome.report.verdict, 'invalid', '[check-mutation:expression-verdict]');
        assert.deepEqual(outcome.report.coverage, {limits: [], unresolved: []});
        assert.deepEqual(outcome.report.requirements, []);
        const input = getCheckInput(outcome, 'source');
        assert.equal(input.text, text);
        assert.deepEqual(outcome.report.reasons, [{code: 'query_expression_invalid', facts: {issue},
          location: {document_id: 'source', revision: input.revision, kind: 'text',
            start_byte: start, end_byte: end, precision: 'exact'}}], '[check-mutation:expression-reason]');
        const reason = outcome.report.reasons[0];
        const range = resolveCheckTextRange(outcome, reason.location);
        assert.equal(range.text, token);
        assert.deepEqual(range.range, {start: {line: 1, character: 7}, end: {line: 1, character: 7 + token.length}});
        assert.equal(resolveCheckTextRange(outcome, reason.location, {...input, text: edited}), undefined);
        assert.equal(resolveCheckTextRange(outcome, {...reason.location, revision: 'rev:' + '0'.repeat(64)}), undefined);
        assert.equal(resolveCheckTextRange(JSON.parse(JSON.stringify(outcome)), reason.location), undefined);
        assert.equal(explainCheckReason(reason).hint, hint);
        if (originalOutcome) assert.deepEqual(outcome, originalOutcome, '[check-mutation:expression-disclosure]');
        else originalOutcome = outcome;
      }
    }
    for (const text of ["SELECT CONCAT('x') AS n", 'SELECT SQRT(1) AS n',
      'SELECT 9007199254740991 AS n', 'SELECT 1e308 AS n']) {
      const outcome = await clients[0].check(text, {format: 'sql'});
      assert.equal(outcome.report.verdict, 'verified');
      assert.deepEqual(outcome.report.reasons, []);
      assert.deepEqual(outcome.report.coverage, {limits: [], unresolved: []});
    }
    // A protected relation prevents this expression's resolution. Never infer
    // that protected failure's issue, span, name or count from its private owner.
    let mixedOutcome;
    for (const client of clients) {
      const outcome = await client.check('SELECT CONCAT() AS n FROM records', {format: 'sql',
        parameterDeclarations: {minimum: {type: 'number'}}, parameters: {minimum: 'private-value'}});
      assert.equal(outcome.report.verdict, 'invalid');
      assert.deepEqual(outcome.report.reasons.map(reason => reason.code), ['supplied_value_type_mismatch'],
        '[check-mutation:expression-protected]');
      assert.deepEqual(outcome.report.coverage, {limits: [], unresolved: protectedSource});
      assert.equal(JSON.stringify(outcome).includes('private-value'), false);
      if (mixedOutcome) assert.deepEqual(outcome, mixedOutcome, '[check-mutation:expression-disclosure]');
      else mixedOutcome = outcome;
    }
  });

  test(`${entrance}: known check locations reject another submitted document`, async t => {
    // The destination nodes really exist in the same call. Revision, kind,
    // size and pointer checks alone cannot establish the reason's input domain.
    const cases = [
      ['supplied_value_type_mismatch', 'SELECT @minimum AS n',
        {minimum: {type: 'number'}}, {minimum: 'wrong'}, 'parameter_declarations'],
      ['supplied_value_constraint_violation', 'SELECT @minimum AS n',
        {minimum: {type: 'number', minimum: 1}}, {minimum: 0}, 'parameter_declarations'],
      ['supplied_value_invalid', 'SELECT @minimum AS n',
        {minimum: {type: 'number'}}, {minimum: 7, extra: 0}, 'parameter_declarations'],
      ['query_syntax_invalid', 'SELECT',
        {minimum: {type: 'number'}}, {minimum: 7}, 'parameter_declarations'],
      ['parameter_undeclared', 'SELECT @missing AS n',
        {minimum: {type: 'number'}}, {minimum: 7}, 'parameter_declarations'],
      ['parameter_declarations_invalid', 'SELECT @minimum AS n',
        {minimum: {type: 'number', minimum: 1, default: 0}}, {minimum: 7}, 'parameters'],
      ['parameter_value_required', 'SELECT @minimum AS n',
        {minimum: {type: 'number'}}, {}, 'parameters'],
    ];
    const refusals = [];
    for (const partial of [false, true]) {
      for (const [code, text, parameterDeclarations, parameters, documentId] of cases) {
        const client = await contextClient(t, entrance, absentEnvironment, {
          mutateCheckTransportReply(outcome) {
            const report = structuredClone(outcome.report);
            const findings = code === 'parameter_value_required' ? report.requirements : report.reasons;
            assert.equal(findings[0].code, code);
            const document = report.inputs.find(input => input.document_id === documentId);
            assert.notEqual(document, undefined);
            findings[0].location = {kind: 'structured', document_id: documentId,
              revision: document.revision, pointer: ''};
            return partial ? {version: outcome.version, reason_schema_cid: outcome.reason_schema_cid, outcome_schema_cid: outcome.outcome_schema_cid,
              outcome: 'failed', correlation_ref: 'corr:fixture', problem: {code: 'check_internal'}, partial_report: report}
              : {...outcome, report};
          },
        });
        let refused = false;
        try { await client.check(text, {format: 'sql', parameterDeclarations, parameters}); }
        catch (cause) {
          if (cause?.code !== 'InvalidHostCheckOutcome') throw cause;
          refused = true;
        }
        refusals.push({code, partial, refused});
      }
    }
    assert.deepEqual(refusals, [false, true].flatMap(partial =>
      cases.map(([code]) => ({code, partial, refused: true}))),
    '[check-mutation:known-location-domain]');
  });

  test(`${entrance}: structured check locations name only submitted JSON nodes`, async t => {
    const client = await contextClient(t, entrance, absentEnvironment);
    const refusedLocation = async operation => {
      let refused = false;
      try { await operation; }
      catch (cause) {
        if (cause?.code !== 'InvalidHostCheckOutcome') throw cause;
        refused = true;
      }
      assert.equal(refused, true, '[check-mutation:structured-refusal]');
    };
    const cases = [
      [{type: 'array', items: {type: 'number'}}, [1, 'private-value'], '/options/1'],
      [{type: 'object', fields: {'': {type: 'number'}}}, {'': 'private-value'},
        '/options/fields/', 'parameter_declarations'],
      [{type: 'object', fields: {'a/b~c': {type: 'number'}}},
        {'a/b~c': 'private-value'}, '/options/a~1b~0c'],
      [{type: 'object', fields: {'~1': {type: 'number'}}},
        {'~1': 'private-value'}, '/options/~01'],
      [{type: 'object', fields: {'é😀': {type: 'number'}}},
        {'é😀': 'private-value'}, '/options/é😀'],
      [{type: 'object', fields: JSON.parse('{"__proto__":{"type":"number"}}')},
        JSON.parse('{"__proto__":"private-value"}'), '/options/__proto__'],
      [{type: 'object', fields: {constructor: {type: 'number'}}},
        {constructor: 'private-value'}, '/options/constructor'],
    ];
    for (const [declaration, value, pointer, documentId = 'parameters'] of cases) {
      let outcome;
      try {
        outcome = await client.check('SELECT 1 AS n', {format: 'sql',
          parameterDeclarations: {options: declaration}, parameters: {options: value}});
      } catch (cause) {
        if (cause?.code !== 'InvalidHostCheckOutcome') throw cause;
      }
      assert.notEqual(outcome, undefined, '[check-mutation:structured-valid]');
      assert.equal(outcome.report.verdict, 'invalid');
      const location = outcome.report.reasons[0].location;
      assert.equal(location.pointer, pointer);
      assert.equal(resolveCheckLocation(outcome, location)?.input,
        getCheckInput(outcome, documentId), '[check-mutation:structured-resolved]');
      assert.equal(resolveCheckLocation(outcome, {...location, pointer: ''})?.input,
        getCheckInput(outcome, documentId));
      assert.equal(resolveCheckLocation(outcome, location,
        {...getCheckInput(outcome, documentId), value: {options: 'edited'}}), undefined);
      assert.equal(resolveCheckLocation(JSON.parse(JSON.stringify(outcome)), location), undefined);
      assert.ok(!JSON.stringify(outcome).includes('private-value'));
    }
    for (const partial of [false, true]) {
      const mutate = edit => outcome => {
        const report = structuredClone(outcome.report);
        edit(report);
        return partial ? {version: outcome.version, reason_schema_cid: outcome.reason_schema_cid, outcome_schema_cid: outcome.outcome_schema_cid,
          outcome: 'failed', correlation_ref: 'corr:fixture', problem: {code: 'check_internal'}, partial_report: report}
          : {...outcome, report};
      };
      const arrayOptions = {format: 'sql',
        parameterDeclarations: {options: {type: 'array', items: {type: 'number'}}},
        parameters: {options: ['private-value']}};
      for (const pointer of ['/options/1', '/options/00', '/options/-',
        '/options/length', '/options/map', '/options/constructor',
        '/options/__proto__', '/options/0/x', '/options/9007199254740993']) {
        const malformed = await contextClient(t, entrance, absentEnvironment,
          {mutateCheckReply: mutate(report => { report.reasons[0].location.pointer = pointer; })});
        await refusedLocation(malformed.check('SELECT 1 AS n', arrayOptions));
      }
      const objectOptions = {format: 'sql',
        parameterDeclarations: {options: {type: 'object', fields: {count: {type: 'number'}}}},
        parameters: {options: {count: 'private-value'}}};
      for (const pointer of ['/options/missing', '/options/toString',
        '/options/__proto__', '/options/constructor', '/options/count/length']) {
        const malformed = await contextClient(t, entrance, absentEnvironment,
          {mutateCheckReply: mutate(report => { report.reasons[0].location.pointer = pointer; })});
        await refusedLocation(malformed.check('SELECT 1 AS n', objectOptions));
      }
      const missing = await contextClient(t, entrance, absentEnvironment,
        {mutateCheckReply: mutate(report => {
          report.requirements[0].location.pointer = '/undeclared';
        })});
      await refusedLocation(missing.check('SELECT 1 AS n', {format: 'sql',
        parameterDeclarations: {options: {type: 'number'}}}));
    }
  });

  test(`${entrance}: source byte exhaustion is a limit of the original bound check`, async t => {
    // Use the existing configurable HTTP ingress budget to reach the parser's
    // smaller source budget. Default HTTP ingress still refuses oversized wire.
    const ingress = {maxRequestBytes: 262144};
    const clients = [
      await contextClient(t, entrance, absentEnvironment, ingress),
      await contextClient(t, entrance, sourceEnvironment,
        {...ingress, aliases: [alias], readOutcome: 'deny'}),
      await contextClient(t, entrance, sourceEnvironment,
        {...ingress, aliases: [alias], readOutcome: 'allow', closed: true}),
    ];
    // The parser admits 65,536 UTF-8 bytes; the public ingress admits up to
    // 65,536 UTF-16 code units. These are independent literal boundary cases.
    const atLimit = `SELECT 1 AS n /*${'é'.repeat(32759)}*/`;
    const overLimit = [
      `${atLimit.slice(0, -2)} */`,
      `SELECT 1 AS n /*${'界'.repeat(21839)}  */`,
      `SELECT 1 AS n /*${'😀'.repeat(16379)}   */`,
    ];
    assert.equal(Buffer.byteLength(atLimit), 65536);
    for (const text of overLimit) {
      assert.equal(Buffer.byteLength(text), 65537);
      assert.ok(text.length <= 65536, 'fixture must pass public ingress');
    }
    if (entrance === 'http') {
      const defaultIngress = await contextClient(t, entrance, absentEnvironment);
      await assert.rejects(defaultIngress.check(overLimit[0], {format: 'sql'}),
        {code: 'ClientRequestTooLarge'});
    }
    const budget = [{code: 'analysis_budget_exhausted'}];
    const parameterDeclarations = Object.fromEntries(Array.from(
      {length: 1100}, (_, index) => [`p${index}`, {type: 'number'}]));
    for (const format of ['sql', 'aql-text']) {
      const atBoundary = await clients[0].check(atLimit, {format});
      assert.equal(atBoundary.report.verdict, 'verified');
      assert.deepEqual(atBoundary.report.coverage, {limits: [], unresolved: []});
      for (const text of overLimit) {
        for (const options of [{}, {parameterDeclarations, parameters: null}]) {
          let first;
          for (const client of clients) {
            const outcome = await client.check(text, {format, ...options});
            assert.equal(outcome.outcome, 'completed', '[check-mutation:source-byte-outcome]');
            assert.equal(outcome.report.verdict, 'undetermined', '[check-mutation:source-byte-verdict]');
            assert.deepEqual(outcome.report.scope, {kind: 'bound_input'});
            assert.deepEqual(outcome.report.reasons, [], '[check-mutation:source-byte-reasons]');
            assert.deepEqual(outcome.report.requirements, []);
            assert.deepEqual(outcome.report.coverage, {limits: budget, unresolved: []},
              '[check-mutation:source-byte-coverage]');
            const input = getCheckInput(outcome, 'source');
            assert.equal(input.text, text);
            assert.equal(outcome.report.inputs[0].byte_length, 65537);
            assert.deepEqual(outcome, first ?? outcome, '[check-mutation:source-byte-disclosure]');
            first ??= outcome;
            assert.equal(explainCheckReason(budget[0]).hint,
              'Ask the checking-context owner to review the analysis budget.');
          }
        }
      }
      const text = overLimit[0];
      let firstInvalid, firstMissing;
      for (const client of clients) {
        // Parameter admission is independent: an exhausted source budget
        // must retain a proven supplied violation and a known missing value.
        const invalid = await client.check(text, {format,
          parameterDeclarations: {minimum: {type: 'number'}},
          parameters: {minimum: 'private-value'}});
        assert.equal(invalid.report.verdict, 'invalid');
        const values = getCheckInput(invalid, 'parameters');
        assert.deepEqual(invalid.report.reasons, [{code: 'supplied_value_type_mismatch',
          facts: {parameter: 'minimum', expected_type: 'number', actual_type: 'string'},
          location: {document_id: 'parameters', revision: values.revision,
            kind: 'structured', pointer: '/minimum'}}]);
        assert.deepEqual(invalid.report.coverage, {limits: budget, unresolved: []});
        assert.ok(!JSON.stringify(invalid).includes('private-value'));
        assert.deepEqual(invalid, firstInvalid ?? invalid,
          '[check-mutation:source-byte-disclosure]');
        firstInvalid ??= invalid;
        const missing = await client.check(text, {format,
          parameterDeclarations: {minimum: {type: 'number'}}});
        assert.equal(missing.report.verdict, 'undetermined');
        assert.deepEqual(missing.report.reasons, []);
        assert.equal(missing.report.requirements[0].code, 'parameter_value_required');
        assert.deepEqual(missing.report.requirements[0].facts,
          {parameter: 'minimum', expected_type: 'number', admission: expectedNumberAdmission});
        assert.deepEqual(missing.report.coverage, {limits: [
          {code: 'bound_values_missing'}, ...budget], unresolved: []});
        assert.deepEqual(missing, firstMissing ?? missing,
          '[check-mutation:source-byte-disclosure]');
        firstMissing ??= missing;
      }
    }
  });

  test(`${entrance}: typed lexical explanations retain the submitted token position`, async t => {
    const clients = [
      await contextClient(t, entrance, absentEnvironment),
      await contextClient(t, entrance, sourceEnvironment,
        {aliases: [alias], readOutcome: 'deny'}),
      await contextClient(t, entrance, sourceEnvironment,
        {aliases: [alias], readOutcome: 'allow', closed: true}),
    ];
    // Original byte offsets and lexical families are literal expectations,
    // independently counted from each submitted spelling and parser contract.
    const cases = [
      ["SELECT 'x", 'unexpected_end', 9, {line: 0, character: 9}],
      ['SELECT !', 'unexpected_token', 7, {line: 0, character: 7}],
      ["SELECT '\\q' AS x", 'invalid_escape', 9, {line: 0, character: 9}],
      ["SELECT '\\uD800' AS x", 'invalid_scalar', 10, {line: 0, character: 10}],
      ['SELECT `` AS x', 'empty_identifier', 7, {line: 0, character: 7}],
      ['SELECT 1 /* comment', 'unterminated_comment', 9, {line: 0, character: 9}, 19],
      ['SELECT 1e+', 'invalid_number', 7, {line: 0, character: 7}],
      ['SELECT @', 'invalid_parameter', 7, {line: 0, character: 7}],
      ["/*😀é*/\r\nSELECT '\\q' AS x", 'invalid_escape', 21, {line: 1, character: 9}],
      ["SELECT 'é😀e\u0301\\q' AS x", 'invalid_escape', 18, {line: 0, character: 14}],
      ["\ufeffSELECT '\\q' AS x", 'invalid_escape', 12, {line: 0, character: 10}],
    ];
    for (const format of ['sql', 'aql-text']) {
      for (const [text, issue, byte, position, fixAt] of cases) {
        let originalOutcome;
        for (const client of clients) {
          const outcome = await client.check(text, {format});
          assert.equal(outcome.outcome, 'completed', '[check-mutation:lexical-outcome]');
          assert.equal(outcome.report.verdict, 'invalid', '[check-mutation:lexical-verdict]');
          assert.deepEqual(outcome.report.coverage, {limits: [], unresolved: []});
          assert.deepEqual(outcome.report.requirements, []);
          const input = getCheckInput(outcome, 'source');
          assert.equal(input.text, text);
          assert.deepEqual(outcome.report.reasons, [{code: 'query_lexical_invalid',
            facts: {issue}, location: {document_id: 'source', revision: input.revision,
              kind: 'text', start_byte: byte, end_byte: byte, precision: 'exact'},
            ...(fixAt === undefined ? {} : {fixes: [{code: 'close_block_comment',
              applicability: 'requires_review', risk: 'syntax_structure',
              target: {document_id: 'source', revision: input.revision},
              edits: [{start_byte: fixAt, end_byte: fixAt, replacement: '*/'}]}]})}],
          '[check-mutation:lexical-reason]');
          const reason = outcome.report.reasons[0];
          const range = resolveCheckTextRange(outcome, reason.location);
          assert.deepEqual(range?.range, {start: position, end: position});
          assert.equal(range.input, input);
          assert.equal(resolveCheckTextRange(outcome, reason.location,
            {...input, text: 'SELECT 1 AS n'}), undefined);
          assert.equal(resolveCheckTextRange(JSON.parse(JSON.stringify(outcome)), reason.location), undefined);
          assert.equal(explainCheckReason(reason).kind, 'known');
          assert.ok(explainCheckReason(reason).hint);
          if (issue === 'unterminated_comment') assert.equal(explainCheckReason(reason).hint,
            'Add the closing block-comment delimiter.');
          if (issue === 'invalid_parameter') assert.equal(explainCheckReason(reason).hint,
            'Provide a valid parameter name after @.');
          if (issue === 'invalid_escape') assert.equal(explainCheckReason(reason).hint,
            'Use an escape allowed by the selected string or identifier syntax.');
          if (originalOutcome) assert.deepEqual(outcome, originalOutcome,
            '[check-mutation:lexical-disclosure]');
          else originalOutcome = outcome;
        }
      }
    }
  });

  test(`${entrance}: failed Source read owners preserve the bound public check`, async t => {
    const absent = await contextClient(t, entrance, absentEnvironment);
    const hidden = [
      await contextClient(t, entrance, sourceEnvironment,
        {aliases: [alias], readOutcome: 'deny'}),
      await contextClient(t, entrance, sourceEnvironment,
        {aliases: [alias], readOutcome: 'allow', closed: true}),
      await contextClient(t, entrance,
        withPolicy(rightEnvironment, sourceEnvironment.host_policy_profile),
        {aliases: [rightAlias], readOutcome: 'allow', closed: true}),
    ];
    for (const [text, options, verdict, codes, limits] of [
      ['SELECT 1 AS n', {format: 'sql'}, 'verified', [], []],
      ['SELECT id FROM records', {format: 'sql'}, 'undetermined', [], []],
      ['/*😀*/\r\nSELECT missing AS n', {format: 'sql'}, 'invalid', ['query_expression_invalid'], []],
      [query, {format: 'sql', parameterDeclarations: declarations,
        parameters: {minimum: 'twenty'}}, 'invalid', ['supplied_value_type_mismatch'], []],
      [query, {format: 'sql', parameterDeclarations: declarations},
        'undetermined', [], [{code: 'bound_values_missing'}]],
      [query, {format: 'sql', parameterDeclarations: {...declarations, another: {type: 'number'}},
        parameters: {minimum: 'twenty'}}, 'invalid', ['supplied_value_type_mismatch'], []],
    ]) {
      const expected = await absent.check(text, options);
      assert.equal(expected.outcome, 'completed');
      assert.equal(expected.report.verdict, verdict);
      assert.deepEqual(expected.report.scope, {kind: 'bound_input'});
      assert.deepEqual(expected.report.coverage, {limits,
        unresolved: text.includes('FROM records') ? protectedSource : []});
      assert.deepEqual(expected.report.reasons.map(reason => reason.code), codes);
      for (const client of hidden) {
        const outcome = await client.check(text, options);
        assert.deepEqual(outcome, expected, '[check-mutation:source-owner]');
        assert.equal(getCheckInput(outcome, 'source').text, text);
        if (codes[0] === 'query_expression_invalid') {
          const original = getCheckInput(outcome, 'source');
          assert.deepEqual(outcome.report.reasons[0].location,
            {document_id: 'source', revision: original.revision,
              kind: 'text', start_byte: 17, end_byte: 24, precision: 'exact'});
          assert.equal(resolveCheckLocation(outcome, outcome.report.reasons[0].location).text, 'missing');
        }
        if (codes[0] === 'supplied_value_type_mismatch') {
          const original = getCheckInput(outcome, 'parameters');
          assert.deepEqual(outcome.report.reasons[0], {code: codes[0],
            facts: {parameter: 'minimum', expected_type: 'number', actual_type: 'string'},
            location: {document_id: 'parameters', revision: original.revision,
              kind: 'structured', pointer: '/minimum'}});
          assert.equal(resolveCheckLocation(outcome, outcome.report.reasons[0].location).input, original);
        }
        if (limits.length) {
          const declared = getCheckInput(outcome, 'parameter_declarations');
          assert.deepEqual(outcome.report.requirements, [{code: 'parameter_value_required',
            facts: {parameter: 'minimum', expected_type: 'number', admission: expectedNumberAdmission},
            location: {document_id: 'parameter_declarations', revision: declared.revision,
              kind: 'structured', pointer: '/minimum'}}]);
        }
      }
    }
  });

  test(`${entrance}: Source failure cannot bypass connection authorization`, async t => {
    const client = await contextClient(t, entrance, sourceEnvironment,
      {aliases: [alias], readOutcome: 'allow', closed: true, connectionAllowed: false});
    const outcome = await client.check('SELECT 1 AS n', {format: 'sql'});
    assert.equal(outcome.outcome, 'unavailable');
    assert.equal(outcome.report, undefined);
    assert.equal(outcome.partial_report, undefined);
    assert.equal(getCheckInput(outcome, 'source'), undefined);
  });

  test(`${entrance}: unsupported function lowering remains an implementation limit`, async t => {
    const clients = [
      await contextClient(t, entrance, absentEnvironment),
      await contextClient(t, entrance, sourceEnvironment, {aliases: [alias], readOutcome: 'deny'}),
      await contextClient(t, entrance, sourceEnvironment, {aliases: [alias], readOutcome: 'delegate'}),
      await contextClient(t, entrance, sourceEnvironment, {aliases: [alias], readOutcome: 'allow', closed: true}),
      await contextClient(t, entrance, withPolicy(rightEnvironment, sourceEnvironment.host_policy_profile),
        {aliases: [rightAlias], readOutcome: 'deny'}),
    ];
    // The existing lowerer returns one typed issue for these distinct forms.
    // It cannot establish which one is a proven unknown name or a support gap.
    const cases = ['/*😀*/\r\nSELECT UNKNOWN_FUNCTION(1) AS n',
      '/*😀*/\r\nSELECT `SQRT`(1) AS n', '/*😀*/\r\nSELECT ACTQL.OTHER(1) AS n'];
    for (const format of ['sql', 'aql-text']) for (const text of cases) {
      let expected;
      for (const client of clients) {
        const outcome = await client.check(text, {format});
        assert.equal(outcome.outcome, 'completed', '[check-mutation:function-limit-outcome]');
        assert.equal(outcome.report.verdict, 'undetermined', '[check-mutation:function-limit-verdict]');
        assert.deepEqual(outcome.report.scope, {kind: 'bound_input'});
        assert.deepEqual(outcome.report.reasons, []);
        assert.deepEqual(outcome.report.requirements, []);
        assert.deepEqual(outcome.report.coverage,
          {limits: [{code: 'implementation_limit'}], unresolved: []},
          '[check-mutation:function-limit-coverage]');
        assert.equal(getCheckInput(outcome, 'source').text, text);
        assert.equal(explainCheckReason(outcome.report.coverage.limits[0]).hint,
          'Ask the checking-context owner to review support for the submitted construct.');
        if (expected) assert.deepEqual(outcome, expected, '[check-mutation:function-limit-disclosure]');
        else expected = outcome;
      }
    }
    const parameterDeclarations = {minimum: {type: 'number'}};
    const text = cases[0];
    for (const format of ['sql', 'aql-text']) {
      let mixedExpected, missingExpected;
      for (const client of clients) {
        const mixed = await client.check(text, {format, parameterDeclarations,
          parameters: {minimum: 'private-wrong-type'}});
        assert.equal(mixed.report.verdict, 'invalid', '[check-mutation:function-limit-mixed]');
        const supplied = getCheckInput(mixed, 'parameters');
        assert.deepEqual(mixed.report.reasons, [{code: 'supplied_value_type_mismatch',
          facts: {parameter: 'minimum', expected_type: 'number', actual_type: 'string'},
          location: {document_id: 'parameters', revision: supplied.revision,
            kind: 'structured', pointer: '/minimum'}}]);
        assert.deepEqual(mixed.report.coverage, {limits: [{code: 'implementation_limit'}], unresolved: []});
        assert.equal(JSON.stringify(mixed).includes('private-wrong-type'), false);
        if (mixedExpected) assert.deepEqual(mixed, mixedExpected);
        else mixedExpected = mixed;

        const missing = await client.check(text, {format, parameterDeclarations});
        assert.equal(missing.report.verdict, 'undetermined');
        assert.deepEqual(missing.report.reasons, []);
        assert.deepEqual(missing.report.coverage, {limits: [
          {code: 'bound_values_missing'}, {code: 'implementation_limit'}], unresolved: []});
        const declaration = getCheckInput(missing, 'parameter_declarations');
        assert.deepEqual(missing.report.requirements, [{code: 'parameter_value_required',
          facts: {parameter: 'minimum', expected_type: 'number', admission: expectedNumberAdmission},
          location: {document_id: 'parameter_declarations', revision: declaration.revision,
            kind: 'structured', pointer: '/minimum'}}]);
        if (missingExpected) assert.deepEqual(missing, missingExpected);
        else missingExpected = missing;
      }
    }
    let protectedExpected;
    for (const client of clients) {
      const outcome = await client.check('SELECT UNKNOWN_FUNCTION(1) AS n FROM records',
        {format: 'sql', parameterDeclarations, parameters: {minimum: 'private-wrong-type'}});
      assert.equal(outcome.report.verdict, 'invalid');
      assert.deepEqual(outcome.report.reasons.map(reason => reason.code), ['supplied_value_type_mismatch']);
      // The protected relation blocks lowering before a function issue exists.
      assert.deepEqual(outcome.report.coverage, {limits: [], unresolved: protectedSource},
        '[check-mutation:function-limit-protected]');
      if (protectedExpected) assert.deepEqual(outcome, protectedExpected);
      else protectedExpected = outcome;
    }
    const valid = await clients[0].check('SELECT SQRT(1) AS n', {format: 'sql'});
    assert.equal(valid.report.verdict, 'verified');
    assert.deepEqual(valid.report.coverage, {limits: [], unresolved: []});
    const invalid = await clients[0].check('SELECT SQRT(1, 2) AS n', {format: 'sql'});
    assert.equal(invalid.report.verdict, 'invalid');
    assert.deepEqual(invalid.report.reasons.map(reason => reason.code), ['query_expression_invalid']);
    assert.deepEqual(invalid.report.reasons[0].facts, {issue: 'invalid_arguments'});
    assert.deepEqual(invalid.report.coverage, {limits: [], unresolved: []});
  });

  test(`${entrance}: expression construction limits remain undetermined`, async t => {
    const absent = await contextClient(t, entrance, absentEnvironment);
    const hidden = [
      await contextClient(t, entrance, sourceEnvironment, {aliases: [alias], readOutcome: 'deny'}),
      await contextClient(t, entrance, sourceEnvironment, {aliases: [alias], readOutcome: 'delegate'}),
      await contextClient(t, entrance,
        withPolicy(rightEnvironment, sourceEnvironment.host_policy_profile),
        {aliases: [rightAlias], readOutcome: 'deny'}),
    ];
    // Forty valid calls fit the existing syntax limits. Their structured
    // expansion exhausts the lowerer's admitted construction depth instead.
    const text = '/*😀*/\r\nSELECT ' + 'COALESCE('.repeat(40) + '1' + ', 1)'.repeat(40) + ' AS n';
    for (const format of ['sql', 'aql-text']) {
      const outcome = await absent.check(text, {format});
      assert.equal(outcome.outcome, 'completed', '[check-mutation:expression-budget-outcome]');
      assert.equal(outcome.report.verdict, 'undetermined', '[check-mutation:expression-budget-verdict]');
      assert.deepEqual(outcome.report.reasons, []);
      assert.deepEqual(outcome.report.requirements, []);
      assert.deepEqual(outcome.report.scope, {kind: 'bound_input'});
      assert.deepEqual(outcome.report.coverage,
        {limits: [{code: 'analysis_budget_exhausted'}], unresolved: []},
        '[check-mutation:expression-budget-limit]');
      assert.equal(getCheckInput(outcome, 'source').text, text);
      for (const client of hidden) assert.deepEqual(await client.check(text, {format}), outcome);

      const mixed = await absent.check(text, {format,
        parameterDeclarations: {minimum: {type: 'number'}}, parameters: {minimum: 'private-wrong-type'}});
      assert.equal(mixed.report.verdict, 'invalid', '[check-mutation:expression-budget-mixed]');
      const original = getCheckInput(mixed, 'parameters');
      assert.deepEqual(mixed.report.reasons, [{code: 'supplied_value_type_mismatch',
        facts: {parameter: 'minimum', expected_type: 'number', actual_type: 'string'},
        location: {document_id: 'parameters', revision: original.revision,
          kind: 'structured', pointer: '/minimum'}}]);
      assert.deepEqual(mixed.report.coverage, outcome.report.coverage);
      assert.equal(JSON.stringify(mixed).includes('private-wrong-type'), false);
      for (const client of hidden) assert.deepEqual(await client.check(text, {format,
        parameterDeclarations: {minimum: {type: 'number'}}, parameters: {minimum: 'private-wrong-type'}}), mixed);
    }
  });

  test(`${entrance}: private Source inventories cannot change public context references`, async t => {
    const absent = await contextClient(t, entrance, absentEnvironment);
    const hidden = [
      await contextClient(t, entrance, sourceEnvironment, {aliases: [alias], readOutcome: 'deny'}),
      await contextClient(t, entrance, sourceEnvironment, {aliases: [alias], readOutcome: 'delegate'}),
      await contextClient(t, entrance,
        withPolicy(rightEnvironment, sourceEnvironment.host_policy_profile),
        {aliases: [rightAlias], readOutcome: 'deny'}),
    ];
    for (const [text, options, verdict] of [
      ['SELECT 1 AS n', {format: 'sql'}, 'verified'],
      ['SELECT id FROM records', {format: 'sql'}, 'undetermined'],
      ['SELECT missing AS n', {format: 'sql'}, 'invalid'],
      [query, {format: 'sql', parameterDeclarations: declarations,
        parameters: {minimum: 'twenty'}}, 'invalid'],
    ]) {
      const expected = await absent.check(text, options);
      assert.equal(expected.outcome, 'completed');
      assert.equal(expected.report.verdict, verdict);
      assert.deepEqual(expected.report.coverage.unresolved,
        text.includes('FROM records') ? protectedSource : []);
      assert.deepEqual(expected.report.reasons.map(reason => reason.code),
        text === 'SELECT missing AS n' ? ['query_expression_invalid']
          : options.parameters ? ['supplied_value_type_mismatch'] : []);
      for (const client of hidden) {
        const outcome = await client.check(text, options);
        assert.deepEqual(outcome, expected, '[check-mutation:private-context]');
        assert.equal(getCheckInput(outcome, 'source').text, text);
      }
    }
  });

  test(`${entrance}: absent declarations still bind independently supplied input`, async t => {
    const absent = await contextClient(t, entrance, absentEnvironment);
    const hidden = [
      await contextClient(t, entrance, sourceEnvironment, {aliases: [alias], readOutcome: 'deny'}),
      await contextClient(t, entrance, sourceEnvironment, {aliases: [alias], readOutcome: 'delegate'}),
      await contextClient(t, entrance,
        withPolicy(rightEnvironment, sourceEnvironment.host_policy_profile),
        {aliases: [rightAlias], readOutcome: 'deny'}),
    ];
    for (const format of ['sql', 'aql-text']) {
      for (const text of ['SELECT id FROM records', 'SELECT 1 AS n']) {
        const unresolved = text === 'SELECT id FROM records' ? protectedSource : [];
        for (const [parameters, pointer] of [
          [{'a/~e\u0301😀': 'private-undeclared-value'}, '/a~1~0e\u0301😀'],
          [{unexpected: 'private-undeclared-value'}, '/unexpected'],
          [{'line\r\n~/': 'private-undeclared-value'}, '/line\r\n~0~1'],
        ]) {
          const outcome = await absent.check(text, {format, parameters});
          assert.equal(outcome.outcome, 'completed');
          assert.equal(outcome.report.verdict, 'invalid', '[check-mutation:absent-binding-verdict]');
          const original = getCheckInput(outcome, 'parameters');
          assert.deepEqual(outcome.report.reasons, [{code: 'supplied_value_invalid',
            location: {document_id: 'parameters', revision: original.revision,
              kind: 'structured', pointer}}], '[check-mutation:absent-binding-location]');
          assert.deepEqual(outcome.report.coverage, {limits: [], unresolved});
          assert.deepEqual(outcome.report.requirements, []);
          assert.deepEqual(outcome.report.scope, {kind: 'bound_input'});
          assert.deepEqual(original.value, parameters);
          assert.equal(getCheckInput(outcome, 'parameter_declarations'), undefined);
          assert.equal(resolveCheckLocation(outcome, outcome.report.reasons[0].location).input, original);
          assert.equal(resolveCheckLocation(outcome, outcome.report.reasons[0].location,
            {...original, revision: 'rev:' + 'f'.repeat(64)}), undefined);
          assert.equal(resolveCheckLocation(JSON.parse(JSON.stringify(outcome)),
            outcome.report.reasons[0].location), undefined);
          assert.equal(explainCheckReason(outcome.report.reasons[0]).kind, 'known');
          assert.equal(JSON.stringify(outcome).includes('private-undeclared-value'), false);
          for (const client of hidden) {
            assert.deepEqual(await client.check(text, {format, parameters}), outcome,
              '[check-mutation:absent-binding-disclosure]');
          }
        }
        const oversizedKey = await absent.check(text, {format,
          parameters: {['x'.repeat(4096)]: 'private-undeclared-value'}});
        assert.equal(oversizedKey.report.verdict, 'invalid');
        assert.deepEqual(oversizedKey.report.reasons, [{code: 'supplied_value_invalid'}]);
        assert.deepEqual(oversizedKey.report.coverage, {limits: [], unresolved});
        // Omission and an empty supplied map bind the empty declaration set;
        // an authored empty declaration document is a different invalid input.
        for (const parameters of [undefined, {}]) {
          const options = {format, ...(parameters === undefined ? {} : {parameters})};
          const outcome = await absent.check(text, options);
          assert.equal(outcome.report.verdict, unresolved.length ? 'undetermined' : 'verified');
          assert.deepEqual(outcome.report.reasons, []);
          assert.deepEqual(outcome.report.requirements, []);
          assert.deepEqual(outcome.report.coverage, {limits: [], unresolved});
          for (const client of hidden) assert.deepEqual(await client.check(text, options), outcome);
        }
        const empty = await absent.check(text, {format, parameterDeclarations: {}});
        assert.equal(empty.report.verdict, 'invalid');
        const original = getCheckInput(empty, 'parameter_declarations');
        assert.deepEqual(empty.report.reasons, [{code: 'parameter_declarations_invalid',
          location: {document_id: 'parameter_declarations', revision: original.revision,
            kind: 'structured', pointer: ''}}]);
        for (const client of hidden) {
          assert.deepEqual(await client.check(text, {format, parameterDeclarations: {}}), empty);
        }
      }
    }
  });

  test(`${entrance}: structured locations keep original key spellings after admission`, async t => {
    const client = await contextClient(t, entrance, absentEnvironment);
    for (const [name, pointer] of [
      ['a/~e\u0301😀', '/options/a~1~0e\u0301😀'],
      ['line\r\n~/', '/options/line\r\n~0~1'],
      ['quote"\\', '/options/quote"\\'],
    ]) {
      const parameters = {options: {[name]: 'private-original-value'}};
      const outcome = await client.check('SELECT id FROM records', {format: 'sql',
        parameterDeclarations: {options: {type: 'object', fields: {[name]: {type: 'number'}}}},
        parameters});
      const original = getCheckInput(outcome, 'parameters');
      assert.equal(outcome.report.verdict, 'invalid');
      assert.deepEqual(outcome.report.reasons, [{code: 'supplied_value_type_mismatch',
        facts: {parameter: 'options', expected_type: 'number', actual_type: 'string'},
        location: {document_id: 'parameters', revision: original.revision,
          kind: 'structured', pointer}}], '[check-mutation:original-key-location]');
      assert.deepEqual(original.value, parameters);
      assert.equal(resolveCheckLocation(outcome, outcome.report.reasons[0].location).input, original);
    }
    const declaration = await client.check('SELECT id FROM records', {format: 'sql',
      parameterDeclarations: {'e\u0301': {type: 'number'}}});
    const original = getCheckInput(declaration, 'parameter_declarations');
    assert.deepEqual(declaration.report.reasons, [{code: 'parameter_declarations_invalid',
      location: {document_id: 'parameter_declarations', revision: original.revision,
        kind: 'structured', pointer: '/e\u0301'}}]);
  });

  test(`${entrance}: public context references retain policy profiles and visible contracts`, async t => {
    const original = await contextClient(t, entrance, absentEnvironment);
    const changedPolicy = await contextClient(t, entrance, emptyEnvironment);
    const changedProfiles = await contextClient(t, entrance, absentEnvironment,
      {profiles: [true, false, true, true, false, false, false]});
    const visible = await contextClient(t, entrance, sourceEnvironment,
      {aliases: [alias], readOutcome: 'allow'});
    const reference = (await original.check('SELECT 1 AS n', {format: 'sql'})).report.context_ref;
    for (const client of [changedPolicy, changedProfiles, visible]) {
      const outcome = await client.check('SELECT 1 AS n', {format: 'sql'});
      assert.equal(outcome.report.verdict, 'verified');
      assert.notEqual(outcome.report.context_ref, reference,
        '[check-mutation:public-context]');
    }
  });
}

async function installation(install, {readOutcome, aliases},
  {closed = false} = {}) {
  const authorization = await createNodeAuthorizationGate({
    configuration: account(readOutcome),
    context: {principal: owner, contextCid: `sha256:${'3'.repeat(64)}`}});
  // A closed decision owner cannot be consulted for any name.
  if (closed) authorization.close();
  return install({moon, environment, contextKey,
    publication: sourceAliasPublication(moon, environment, aliases),
    sourceAccesses: [{authorization, connection: 'local-database',
      resource: '/records.duckdb', sourceRef}]});
}

const ownerRequest = (name, principalId = owner) => ({principalId,
  input: {text: requests[name].text, format: 'sql',
    parameterDeclarations: declarations},
  parameters: requests[name].parameters});
const sourceRequest = (text, parameters = null, parameterDeclarations) => ({
  principalId: owner, input: {text, format: 'sql',
    ...(parameterDeclarations === undefined ? {} : {parameterDeclarations})},
  parameters});

async function acceptDisclosure(install) {
  const absent = await installation(install, configurations.absent);
  const hidden = {denied: await installation(install, configurations.denied),
    undecidable: await installation(install, configurations.undecidable),
    failedOwner: await installation(install, configurations.allowed, {closed: true})};
  for (const [variant, check] of Object.entries(hidden)) {
    for (const name of ['violation', 'satisfied']) {
      const left = await absent(ownerRequest(name));
      const right = await check(ownerRequest(name));
      assert.equal(canonicalJson(left), canonicalJson(right),
        `${variant} ${name}`);
      assert.equal(left.outcome, 'completed', name);
      assert.deepEqual(left.report.coverage.unresolved, protectedSource, name);
      assert.equal(left.report.verdict,
        name === 'violation' ? 'invalid' : 'undetermined', name);
      assert.deepEqual(withoutContext(left).report.reasons, name === 'violation'
        ? [{code: 'supplied_value_invalid'}] : [], name);
    }
    // A violation that does not depend on any source is reported as is.
    const unrelated = await check(sourceRequest('SELECT missing AS n'));
    assert.equal(canonicalJson(unrelated),
      canonicalJson(await absent(sourceRequest('SELECT missing AS n'))));
    assert.equal(unrelated.report?.verdict, 'invalid', variant);
    const nestedRequest = sourceRequest('SELECT id FROM records',
      {options: {'/a~~//é': [7, 'private-value']}},
      {options: {type: 'object', fields: {'/a~~//é': {type: 'array', items: {type: 'number'}}}}});
    const nested = await check(nestedRequest);
    assert.equal(nested.outcome, 'completed');
    assert.equal(canonicalJson(nested), canonicalJson(await absent(nestedRequest)),
      '[check-mutation:nested-disclosure]');
    assert.equal(nested.report.verdict, 'invalid');
    assert.deepEqual(nested.report.coverage.unresolved, protectedSource);
    assert.deepEqual(nested.report.reasons[0].facts,
      {parameter: 'options', expected_type: 'number', actual_type: 'string'});
    assert.equal(nested.report.reasons[0].location.pointer, '/options/~1a~0~0~1~1é/1');
    const invalidDeclaration = sourceRequest('SELECT id FROM records', {options: 3},
      {options: {type: 'number', minimum: 1, default: 0}});
    const declaration = await check(invalidDeclaration);
    assert.equal(canonicalJson(declaration), canonicalJson(await absent(invalidDeclaration)),
      '[check-mutation:declaration-disclosure]');
    assert.equal(declaration.report.verdict, 'invalid');
    assert.equal(declaration.report.reasons[0].code, 'parameter_declarations_invalid');
    assert.equal(declaration.report.reasons[0].location.document_id, 'parameter_declarations');
    assert.equal(declaration.report.reasons[0].location.pointer, '/options/default');
    const constraintRequest = sourceRequest('SELECT id FROM records',
      {options: {count: 0}},
      {options: {type: 'object', fields: {count: {type: 'number', minimum: 1}}}});
    const constraint = await check(constraintRequest);
    assert.equal(canonicalJson(constraint), canonicalJson(await absent(constraintRequest)),
      '[check-mutation:constraint-disclosure]');
    assert.equal(constraint.report.verdict, 'invalid');
    assert.deepEqual(constraint.report.coverage.unresolved, protectedSource);
    assert.deepEqual(constraint.report.reasons[0].facts,
      {parameter: 'options', constraint: 'numeric'});
    assert.equal(constraint.report.reasons[0].location.pointer, '/options/count');
  }
  // A reference is never reused for another audience, another source or
  // another exact value.
  const denied = hidden.denied;
  const refOf = async request => (await denied(request)).report.context_ref;
  assert.notEqual(await refOf(ownerRequest('violation', 'other')),
    await refOf(ownerRequest('violation')));
  assert.notEqual(await refOf(sourceRequest('SELECT 1 AS n')),
    await refOf(sourceRequest('SELECT 2 AS n')));
  const text = {x: {type: 'string'}};
  assert.notEqual(
    await refOf(sourceRequest('SELECT @x AS v', {x: '\u00e9'}, text)),
    await refOf(sourceRequest('SELECT @x AS v', {x: 'e\u0301'}, text)));
}

test('fixed-key owners give byte-equal outcomes for absent, denied and ' +
  'undecided sources',
  () => acceptDisclosure(installNodeClientCheck));

test('an unsupported format is a failure without a verdict', async () => {
  const check = await installation(installNodeClientCheck,
    configurations.denied);
  const outcome = await check({principalId: owner,
    input: {text: 'SELECT id FROM records', format: 'json'},
    parameters: null});
  assert.match(outcome.correlation_ref, /^corr:[0-9a-f]{32}$/u);
  assert.deepEqual(outcome, {outcome: 'failed', correlation_ref: outcome.correlation_ref,
    problem: {code: 'check_format_unsupported'}, reason_schema_cid: checkReasonSchemaCid, outcome_schema_cid: checkOutcomeSchemaCid,
    version: 'actql-check-outcome/0.1'});
});

test('the public outcome contract keeps verdicts bound and partial ' +
  'reports unverified', () => {
  const report = {context_ref: 'ctx:a', requirements: [], inputs: [{document_id: 'source', revision: 'rev:' + '1'.repeat(64), kind: 'text', byte_length: 1}], scope: {kind: 'bound_input'},
    verdict: 'undetermined', reasons: [],
    coverage: {limits: [{code: 'analysis_budget_exhausted'}],
      unresolved: []}};
  const version = 'actql-check-outcome/0.1';
  const reason_schema_cid = checkReasonSchemaCid;
  const outcome_schema_cid = checkOutcomeSchemaCid;
  assert.equal(validCheckOutcome({outcome: 'completed', report, version, reason_schema_cid, outcome_schema_cid}),
    true);
  for (const key of ['context_ref', 'scope']) {
    const {[key]: _removed, ...unbound} = report;
    assert.equal(validCheckOutcome({outcome: 'completed', report: unbound,
      version, reason_schema_cid, outcome_schema_cid}), false, key);
  }
  assert.equal(validCheckOutcome({outcome: 'failed', correlation_ref: 'corr:fixture',
    partial_report: {...report, verdict: 'invalid',
      reasons: [{code: 'supplied_value_invalid'}]},
    problem: {code: 'check_internal'}, version, reason_schema_cid, outcome_schema_cid}), true);
  assert.equal(validCheckOutcome({outcome: 'failed', correlation_ref: 'corr:fixture',
    partial_report: {...report, verdict: 'verified',
      coverage: {limits: [], unresolved: []}},
    problem: {code: 'check_internal'}, version, reason_schema_cid, outcome_schema_cid}), false);
  assert.equal(validCheckOutcome({outcome: 'unavailable',
    correlation_ref: 'corr:a', problem: {code: 'check_unavailable'},
    report, version, reason_schema_cid, outcome_schema_cid}), false);
});

// Each mutation is one plausible change to the Host owner. Its module is
// written beside the scratch Host roots with absolute imports.
const ownerSource = await readFile(new URL('./client-check.mjs',
  import.meta.url), 'utf8');
const mutations = Object.freeze({
  // A hidden published name changes the whole outcome instead of coverage.
  'hidden publication changes the outcome kind': [
    'const visible = await visibleAliases(signal);',
    "const visible = await visibleAliases(signal);\n" +
    "    if (aliases.length > 0 && visible.length === 0) return JSON.parse(moon.clientProgramCheckUnavailable('corr:mutant'));"],
  // Empty visibility withholds independently disclosable input violations.
  'empty visibility withholds the check': [
    'const visible = await visibleAliases(signal);',
    "const visible = await visibleAliases(signal);\n" +
    "    if (visible.length === 0) return JSON.parse(moon.clientProgramCheckUnavailable('corr:mutant'));"],
  // An unusable read owner reveals the installed publication.
  'failed read owner reveals names': [
    'if (signal?.aborted) throw cause;\n      return undefined;',
    'if (signal?.aborted) throw cause;\n      return aliases;'],
  // A hidden name is checked as if it were visible.
  'hidden source is checked as visible': [
    'JSON.stringify({environmentCid, aliases: visible})',
    'JSON.stringify({environmentCid, aliases})'],
  // The context reference names the private source set.
  'context binds the private source set': [
    'visible_aliases: visible};', 'visible_aliases: aliases};'],
  // A reference is reused across audiences.
  'context omits the audience': [
    'version: contextVersion, audience: principalId,',
    'version: contextVersion,'],
  // A reference is reused across sources.
  'context omits the source': [
    'source: {format: input.format, text: input.text},', ''],
  // A reference normalizes distinct String values together.
  'context normalizes String values': [
    "from '../../packages/sdk/host-port.mjs';",
    "from './local-account-config.mjs';"],
});

for (const [name, [from, to]] of Object.entries(mutations)) {
  test(`mutation is rejected: ${name}`, async t => {
    assert.equal(ownerSource.split(from).length, 2, 'mutation anchor');
    const directory = await mkdtemp(join(scratch, 'mutant-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const path = join(directory, 'client-check.mjs');
    await writeFile(path, ownerSource.replace(from, to)
      .replaceAll("from '../../", `from '${pathToFileURL(repository).href}`)
      .replaceAll("from './", `from '${new URL('./', import.meta.url).href}`));
    const mutant = await import(pathToFileURL(path).href);
    await assert.rejects(acceptDisclosure(mutant.installNodeClientCheck),
      assert.AssertionError);
  });
}


for (const entrance of ['local', 'http']) {
  test(`${entrance}: the pinned pre-extension SDK refuses the current Host contract`, async t => {
    // Load immutable historical consumers for this negative acceptance only.
    // No historical implementation or compatibility adapter ships in the product.
    for (const [revision, expectedCid] of [
      ['ea67efe6c4adbb17353eea61f06a3fdfc52dd91b', 'sha256:1565f0b7e8e32f70d97905797ccc37a872b08116c0ef3d9599e4e4509b568621'],
      ['c4bdfd21416f02aa13a2ac1d7614ef398dec7b31', 'sha256:16c81ff351a5c3d1fa56757c3c9936a68fd7014c81137e8efa1c54988a61c961'],
      ['5d52b3a970984f3cdad554b9030a0c25fa8ac887', 'sha256:ac08ebfd20b15d7ee4898039c94f3d089baaaeb693b319d241b3e0fe6adec4a6'],
      ['7f4a8167a0e6492b61478c805a77f3f583b0cd2f', 'sha256:9fec13a58413e7a0267442d380986e6e8567a0711cd3f486885b7de6b9ef297d'],
      ['39939e32f8b81812204f4b62affb318b4dcd1077', 'sha256:3204b8f2edb377120d3139f380fc3c49541ff34b7117430de4ed52e0f826025f'],
      ['b40f973ca636895d7dccac79c4c678371d912887', 'sha256:15d4d9b93f6e22c50256271ba09d09ba5da6a2a7105e118af2ad224a0591feac'],
      ['47fd48576a1c4f48ebd0ce949e821e302a420cba', 'sha256:9fec13a58413e7a0267442d380986e6e8567a0711cd3f486885b7de6b9ef297d'],
      ['11f43a5ff151dfe6c0a5f243298dbec50eeefefe', 'sha256:ae227713f6c587924092d7bfe5624ebaf5aa2969453ca48611272ff4bece9ace'],
    ]) {
      const historical = path => execFileSync('git', ['show', `${revision}:${path}`],
        {cwd: repository, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024});
      const moduleUrl = source => `data:text/javascript;base64,${Buffer.from(source).toString('base64')}`;
      const hostWire = moduleUrl(historical('packages/client-wire/client-host.generated.js'));
      const publicationWire = moduleUrl(historical('packages/client-wire/publication.generated.js'));
      const wire = moduleUrl(historical('packages/client-wire/index.mjs')
        .replaceAll("'./client-host.generated.js'", JSON.stringify(hostWire))
        .replaceAll("'./publication.generated.js'", JSON.stringify(publicationWire)));
      const checkpoints = moduleUrl(historical('packages/sdk/checkpoints.mjs')
        .replace("'@actql/client-wire'", JSON.stringify(wire)));
      let previousSource = historical('packages/sdk/index.mjs');
      if (previousSource.includes("'./check-presentation.mjs'")) {
        previousSource = previousSource.replaceAll("'./check-presentation.mjs'",
          JSON.stringify(moduleUrl(historical('packages/sdk/check-presentation.mjs'))));
      }
      if (previousSource.includes("'./json-value-wire.generated.mjs'")) {
        previousSource = previousSource.replaceAll("'./json-value-wire.generated.mjs'",
          JSON.stringify(moduleUrl(historical('packages/sdk/json-value-wire.generated.mjs'))));
      }
      const previous = await import(moduleUrl(previousSource
        .replace("'@actql/client-wire'", JSON.stringify(wire))
        .replace("'./checkpoints.mjs'", JSON.stringify(checkpoints))));
      const oldWire = await import(wire);
      assert.equal(oldWire.checkReasonSchemaCid, expectedCid);
      const client = await contextClient(t, entrance, absentEnvironment,
        {sdkConnect: previous.connect, sdkConnectInProcess: previous.connectInProcess});
      for (const text of ['SELECT 1 AS n', "SELECT '\\q' AS x", 'SELECT CONCAT() AS n']) {
        await assert.rejects(client.check(text, {format: 'sql'}), {code: 'InvalidHostCheckOutcome'});
      }
    }
  });
}

test('http: SDK rejects malformed expression facts from an actual check reply', async t => {
  let mutation = value => value;
  const client = await httpClient(t, configurations.denied, value => mutation(value));
  const check = () => client.check('SELECT CONCAT() AS n', {format: 'sql'});
  assert.deepEqual((await check()).report.reasons[0].facts, {issue: 'invalid_arguments'});
  for (const facts of [undefined, {}, {issue: 'future_issue'}, {issue: 'invalid_escape'},
    {issue: 'invalid_arguments', name: 'private_name'}, {parameter: 'minimum'}]) {
    mutation = value => ({...value, report: {...value.report,
      reasons: [{...value.report.reasons[0], facts}]}});
    await assert.rejects(check(), {code: 'InvalidHostCheckOutcome'});
  }
});

test('http: SDK rejects malformed lexical facts from an actual check reply', async t => {
  let mutation = value => value;
  const client = await httpClient(t, configurations.denied, value => mutation(value));
  const check = () => client.check("SELECT '\\q' AS x", {format: 'sql'});
  const baseline = await check();
  assert.deepEqual(baseline.report.reasons[0].facts, {issue: 'invalid_escape'});
  for (const facts of [undefined, {}, {issue: 'future_issue'},
    {issue: 'invalid_escape', token: 'private text'},
    {parameter: 'minimum', expected_type: 'number', actual_type: 'string'}]) {
    mutation = value => ({...value, report: {...value.report,
      reasons: [{...value.report.reasons[0], facts}]}});
    await assert.rejects(check(), {code: 'InvalidHostCheckOutcome'});
  }
});

test('http: SDK rejects contradictory evidence injected into a real verified reply',
  async t => {
    let mutation = value => value;
    const client = await httpClient(t, configurations.allowed, value => {
      assert.equal(value.report.verdict, 'verified');
      return mutation(value);
    });
    const check = () => client.check('SELECT 1 AS n', {format: 'sql'});
    assert.equal((await check()).report.verdict, 'verified');
    // A mismatched contract is refused even when there are no reasons.
    mutation = value => {
      const mismatched = structuredClone(value);
      delete mismatched.reason_schema_cid;
      delete mismatched.report.inputs;
      delete mismatched.report.requirements;
      return mismatched;
    };
    await assert.rejects(check(), {code: 'InvalidHostCheckOutcome'});
    mutation = value => ({...value, reason_schema_cid: 'sha256:' + '0'.repeat(64)});
    await assert.rejects(check(), {code: 'InvalidHostCheckOutcome'});
    mutation = value => ({...value,
      reason_schema_cid: 'sha256:9fec13a58413e7a0267442d380986e6e8567a0711cd3f486885b7de6b9ef297d',
      outcome_schema_cid: 'sha256:a5dd8a6e4a3c5411d97b4d4a5f333992c655c038534352e701257a4c28baea4d'});
    await assert.rejects(check(), {code: 'InvalidHostCheckOutcome'});
    mutation = value => ({...value,
      reason_schema_cid: 'sha256:1565f0b7e8e32f70d97905797ccc37a872b08116c0ef3d9599e4e4509b568621'});
    await assert.rejects(check(), {code: 'InvalidHostCheckOutcome'});
    mutation = value => ({...value,
      reason_schema_cid: 'sha256:6ef2aefaf03e046fcfa830ce1b0648c6b04701162755ba869a9996cd69ade8ef'});
    await assert.rejects(check(), {code: 'InvalidHostCheckOutcome'});
    mutation = value => ({...value,
      reason_schema_cid: 'sha256:ce47f3f27b2f37b0aa48cab9b32fc60c93d5c92ac8196a0a8f80a09df4ae34fa'});
    await assert.rejects(check(), {code: 'InvalidHostCheckOutcome'});
    for (const coverage of [
      {limits: [{code: 'analysis_budget_exhausted'}], unresolved: []},
      {limits: [], unresolved: [{boundary: 'source_resolution',
        reason: 'unresolved_protected'}]},
    ]) {
      mutation = value => ({...value, report: {...value.report, coverage}});
      await assert.rejects(check(), {code: 'InvalidHostCheckOutcome'});
    }
    mutation = value => ({version: value.version, outcome: 'failed', correlation_ref: 'corr:fixture',
      problem: {code: 'check_internal'}, partial_report: value.report});
    await assert.rejects(check(), {code: 'InvalidHostCheckOutcome'});
  });

for (const entrance of ['local', 'http']) {
  test(`${entrance}: operation parameter violations explain owned domains and input origins`, async t => {
    const client = await contextClient(t, entrance, sourceEnvironment,
      {aliases: [alias], readOutcome: 'allow'});
    for (const direction of ['PRECEDING', 'FOLLOWING']) {
      const text = 'SELECT FIRST_VALUE(amount) OVER '
        + `(ORDER BY id ROWS BETWEEN @before ${direction} AND @after ${direction}) AS first FROM records`;
      for (const before of [0, -1, 1.5, 9007199254740992]) {
        const outcome = await client.check(text, {format: 'sql',
          parameterDeclarations: {before: {type: 'number', nullable: false},
            after: {type: 'number', nullable: false}}, parameters: {before, after: 2}});
        assert.equal(outcome.outcome, 'completed');
        assert.equal(outcome.report.verdict, 'invalid');
        const [reason] = outcome.report.reasons;
        assert.deepEqual({code: reason.code, facts: reason.facts},
          {code: 'operation_parameter_invalid', facts: {parameter: 'before', domain: 'positive_safe_integer'}},
          '[check-mutation:operation-parameter-facts]');
        assert.deepEqual(reason.location, {kind: 'structured', document_id: 'parameters',
          revision: outcome.report.inputs.find(input => input.document_id === 'parameters').revision, pointer: '/before'},
          '[check-mutation:operation-parameter-location]');
        const resolved = resolveCheckLocation(outcome, reason.location);
        assert.equal(resolved.input.value.before, before);
        assert.equal(resolved.pointer, '/before');
        assert.deepEqual(explainCheckReason(reason), {kind: 'known',
          summary: 'An operation parameter must be a positive safe integer.',
          hint: 'Supply an integer from 1 through 9007199254740991.'}, '[check-mutation:operation-parameter-explanation]');
        assert.deepEqual(explainCheckReason(reason, {locale: 'ja'}), {kind: 'known',
          summary: '演算パラメータには正のsafe integerが必要です。', hint: '1以上9007199254740991以下の整数を渡してください。'});
        assert.equal(resolveCheckLocation(structuredClone(outcome), reason.location), undefined);
        assert.equal(resolveCheckLocation(outcome, reason.location, {...resolved.input, revision: `rev:${'0'.repeat(64)}`}), undefined);
        assert.deepEqual(outcome.report.coverage, {limits: [], unresolved: []});
        assert.deepEqual(outcome.report.requirements, []);
      }
    }
  });
}

for (const entrance of ['local', 'http']) {
  test(`${entrance}: operation parameter defaults and missing values keep distinct origins`, async t => {
    const client = await contextClient(t, entrance, sourceEnvironment,
      {aliases: [alias], readOutcome: 'allow'});
    const text = 'SELECT FIRST_VALUE(amount) OVER '
      + '(ORDER BY id ROWS BETWEEN @before PRECEDING AND @after PRECEDING) AS first FROM records';
    const declarations = {before: {type: 'number', nullable: false, default: 0},
      after: {type: 'number', nullable: false}};
    const pending = client.check(text, {format: 'sql', parameterDeclarations: declarations,
      parameters: {after: 2}});
    declarations.before.default = 2;
    const outcome = await pending;
    assert.equal(outcome.report.verdict, 'invalid');
    const [reason] = outcome.report.reasons;
    assert.deepEqual({code: reason.code, facts: reason.facts}, {code: 'operation_parameter_invalid',
      facts: {parameter: 'before', domain: 'positive_safe_integer'}});
    assert.deepEqual(reason.location, {kind: 'structured', document_id: 'parameter_declarations',
      revision: outcome.report.inputs.find(input => input.document_id === 'parameter_declarations').revision,
      pointer: '/before/default'}, '[check-mutation:operation-default-location]');
    const resolved = resolveCheckLocation(outcome, reason.location);
    assert.equal(resolved.input.value.before.default, 0);
    assert.equal(resolved.pointer, '/before/default');
    assert.equal(resolveCheckLocation(outcome, reason.location, {...resolved.input, value: declarations}), undefined);
    assert.equal(getCheckInput(outcome, 'parameters').value.before, undefined);
    const overridden = await client.check(text, {format: 'sql',
      parameterDeclarations: {...declarations, before: {...declarations.before, default: 0}},
      parameters: {before: 1.5, after: 2}});
    assert.equal(overridden.report.reasons[0].location.document_id, 'parameters');
    assert.equal(overridden.report.reasons[0].location.pointer, '/before');
    const missing = await client.check(text, {format: 'sql', parameterDeclarations: {
      before: {type: 'number', nullable: false}, after: {type: 'number', nullable: false}}, parameters: {after: 2}});
    assert.equal(missing.report.verdict, 'undetermined');
    assert.deepEqual(missing.report.reasons, []);
    assert.deepEqual(missing.report.requirements.map(({code, facts}) => ({code, facts})),
      [{code: 'parameter_value_required', facts: {parameter: 'before', expected_type: 'number', admission: expectedNumberAdmission}}]);
  });

  test(`${entrance}: operation offset violations retain the nonnegative domain`, async t => {
    const wire = withPolicy(sourceEnvironment, {capacity: {...sourceEnvironment.host_policy_profile.capacity,
      max_analytic_input_wire_bytes: 10000, max_analytic_output_wire_bytes: 10000,
      max_analytic_partition_wire_bytes: 10000, max_analytic_frame_memberships: 10000}});
    const client = await contextClient(t, entrance, wire,
      {aliases: [alias], readOutcome: 'allow'});
    for (const offset of [-1, 1.5, 9007199254740992]) {
      const outcome = await client.check('SELECT LAG(amount, @offset) OVER (ORDER BY id) AS previous FROM records', {format: 'sql',
        parameterDeclarations: {offset: {type: 'number', nullable: false}}, parameters: {offset}});
      assert.equal(outcome.report.verdict, 'invalid', JSON.stringify(outcome));
      assert.deepEqual(outcome.report.reasons[0].facts, {parameter: 'offset', domain: 'nonnegative_safe_integer'});
      assert.equal(outcome.report.reasons[0].location.pointer, '/offset');
      assert.deepEqual(explainCheckReason(outcome.report.reasons[0]), {kind: 'known',
        summary: 'An operation parameter must be a nonnegative safe integer.',
        hint: 'Supply an integer from 0 through 9007199254740991; negative zero is not admitted.'});
    }
    const verified = await client.check('SELECT LAG(amount, @offset) OVER (ORDER BY id) AS previous FROM records', {format: 'sql',
      parameterDeclarations: {offset: {type: 'number', nullable: false}}, parameters: {offset: 0}});
    assert.equal(verified.report.verdict, 'verified', JSON.stringify(verified));
  });
}

for (const entrance of ['local', 'http']) {
  test(`${entrance}: malformed LIMIT operand does not invent scalar domain facts`, async t => {
    const client = await contextClient(t, entrance, sourceEnvironment,
      {aliases: [alias], readOutcome: 'allow'});
    const outcome = await client.check('SELECT id FROM records LIMIT 2 OFFSET (', {format: 'sql'});
    assert.equal(outcome.report.verdict, 'invalid');
    assert.deepEqual(outcome.report.reasons.map(({code, facts}) => ({code, ...(facts ? {facts} : {})})),
      [{code: 'query_syntax_invalid'}]);
    assert.equal(outcome.report.reasons[0].location.document_id, 'source');
    assert.deepEqual({...outcome.report.reasons[0].location, revision: 'submitted'},
      {kind: 'text', document_id: 'source', revision: 'submitted', start_byte: 38, end_byte: 38, precision: 'exact'});
    assert.equal(resolveCheckLocation(outcome, outcome.report.reasons[0].location).text, '');
  });

  test(`${entrance}: admitted LIMIT parameters retain the owned offset domain`, async t => {
    const client = await contextClient(t, entrance, sourceEnvironment,
      {aliases: [alias], readOutcome: 'allow'});
    const text = 'SELECT id FROM records LIMIT 2 OFFSET @offset';
    const options = {format: 'sql', parameterDeclarations: {
      offset: {type: 'number', nullable: false}}, parameters: {offset: -1}};
    const outcome = await client.check(text, options);
    assert.equal(outcome.report.verdict, 'invalid');
    assert.deepEqual(outcome.report.reasons.map(({code, facts}) => ({code, ...(facts ? {facts} : {})})),
      [{code: 'operation_parameter_invalid',
        facts: {parameter: 'offset', domain: 'nonnegative_safe_integer'}}]);
    const input = getCheckInput(outcome, 'parameters');
    assert.deepEqual(outcome.report.reasons[0].location,
      {kind: 'structured', document_id: 'parameters', revision: input.revision, pointer: '/offset'});
    assert.equal(resolveCheckLocation(outcome, outcome.report.reasons[0].location).input, input);
    assert.equal(outcome.report.reasons[0].location.kind === 'text', false);
    for (const offset of [0, 2]) {
      const valid = await client.check(text, {...options, parameters: {offset}});
      assert.equal(valid.report.verdict, 'verified');
      assert.deepEqual(valid.report.reasons, []);
      assert.deepEqual(valid.report.coverage, {limits: [], unresolved: []});
    }
  });

  test(`${entrance}: admitted LIMIT parameters retain scalar facts and input location`, async t => {
    const client = await contextClient(t, entrance, sourceEnvironment,
      {aliases: [alias], readOutcome: 'allow'});
    const source = 'SELECT id FROM records ORDER BY id LIMIT 2 OFFSET @offset';
    const options = {format: 'sql',
      parameterDeclarations: {offset: {type: 'number', nullable: false}}};
    const invalid = await client.check(source, {...options, parameters: {offset: -1}});
    assert.equal(invalid.report.verdict, 'invalid');
    assert.deepEqual(invalid.report.reasons.map(({code, facts}) => ({code, facts})),
      [{code: 'operation_parameter_invalid',
        facts: {parameter: 'offset', domain: 'nonnegative_safe_integer'}}]);
    assert.deepEqual({...invalid.report.reasons[0].location, revision: 'submitted'},
      {kind: 'structured', document_id: 'parameters', revision: 'submitted', pointer: '/offset'});
    const valid = await client.check(source, {...options, parameters: {offset: 0}});
    assert.equal(valid.report.verdict, 'verified', JSON.stringify(valid));
  });

  test(`${entrance}: protected scalar demands retain only independent public violations`, async t => {
    const clients = [
      await contextClient(t, entrance, sourceEnvironment),
      await contextClient(t, entrance, sourceEnvironment, {aliases: [alias], readOutcome: 'deny'}),
      await contextClient(t, entrance, sourceEnvironment, {aliases: [alias], readOutcome: 'allow', closed: true}),
    ];
    for (const before of [0, 'private-operation-value']) {
      const results = await Promise.all(clients.map(client => client.check('SELECT FIRST_VALUE(amount) OVER '
        + '(ORDER BY id ROWS BETWEEN @before PRECEDING AND @after PRECEDING) AS first FROM records',
      {format: 'sql', parameterDeclarations: {before: {type: 'number'}, after: {type: 'number'}},
        parameters: {before, after: 2}})));
      assert.deepEqual(results[0], results[1], '[check-mutation:operation-parameter-protected]');
      assert.deepEqual(results[0], results[2], '[check-mutation:operation-parameter-protected]');
      const {report} = results[0];
      assert.equal(report.verdict, typeof before === 'number' ? 'undetermined' : 'invalid');
      assert.deepEqual(report.reasons.map(({code, facts}) => ({code, ...(facts ? {facts} : {})})),
        typeof before === 'number' ? [] : [{code: 'supplied_value_type_mismatch',
          facts: {parameter: 'before', expected_type: 'number', actual_type: 'string'}}]);
      assert.deepEqual(report.coverage, {limits: [],
        unresolved: [{boundary: 'source_resolution', reason: 'unresolved_protected'}]});
      assert.equal(JSON.stringify(results).includes('private-operation-value'), false);
    }
  });
}

for (const entrance of ['local', 'http']) {
  test(`${entrance}: SDK rejects malformed operation facts from an actual check reply`, async t => {
    let mutation = value => value;
    const client = await contextClient(t, entrance, sourceEnvironment,
      {aliases: [alias], readOutcome: 'allow', mutateCheckTransportReply: value => mutation(value)});
    const check = () => client.check('SELECT FIRST_VALUE(amount) OVER '
      + '(ORDER BY id ROWS BETWEEN @before PRECEDING AND @after PRECEDING) AS first FROM records',
    {format: 'sql', parameterDeclarations: {before: {type: 'number'}, after: {type: 'number'}},
      parameters: {before: 0, after: 2}});
    assert.deepEqual((await check()).report.reasons[0].facts,
      {parameter: 'before', domain: 'positive_safe_integer'});
    for (const facts of [undefined, {}, {parameter: 'before', domain: 'private_domain'},
      {parameter: 'before', domain: 'positive_safe_integer', requirement_index: 0},
      {parameter: 'before', domain: 'positive_safe_integer', value: 'private-value'}]) {
      mutation = value => ({...value, report: {...value.report,
        reasons: [{...value.report.reasons[0], facts}]}});
      await assert.rejects(check(), {code: 'InvalidHostCheckOutcome'});
    }
  });
}

for (const entrance of ['local', 'http']) {
  test(`${entrance}: expression type rejections explain only owned expected domains`, async t => {
    const client = await contextClient(t, entrance, absentEnvironment);
    const cases = [
      ["SELECT SQRT('private-expression-text') AS n", 'number'],
      ['SELECT SQRT(TRUE) AS n', 'number'],
      ['SELECT LOWER(1) AS n', 'string'],
      ['SELECT NOT 1 AS n', 'boolean'],
      ['SELECT IF(1, 2, 3) AS n', 'boolean'],
    ];
    for (const format of ['sql', 'aql-text']) for (const [text, expected] of cases) {
      const result = await client.check(text, {format});
      assert.equal(result.outcome, 'completed');
      assert.equal(result.report.verdict, 'invalid', JSON.stringify({text, result}));
      assert.deepEqual(result.report.reasons, [{code: 'expression_type_mismatch',
        facts: {expected_type: expected}}], '[check-mutation:expression-type-reason]');
      assert.equal(result.report.reasons[0].location, undefined);
      assert.deepEqual(result.report.coverage, {limits: [], unresolved: []});
      assert.deepEqual(result.report.requirements, []);
      assert.equal(getCheckInput(result, 'source').text, text);
      assert.equal(JSON.stringify(result).includes('private-expression-text'), false);
      assert.deepEqual(explainCheckReason(result.report.reasons[0]), {kind: 'known',
        summary: `An expression argument must have ${expected} type.`,
        hint: `Use an expression with ${expected} type for the rejected argument.`},
      '[check-mutation:expression-type-explanation]');
    }
    for (const text of ['SELECT SQRT(1) AS n', "SELECT LOWER('X') AS n",
      'SELECT NOT FALSE AS n', 'SELECT IF(TRUE, 2, 3) AS n']) {
      const result = await client.check(text, {format: 'sql'});
      assert.equal(result.report.verdict, 'verified');
      assert.deepEqual(result.report.reasons, []);
    }
  });
}

for (const entrance of ['local', 'http']) {
  test(`${entrance}: unsupported expression functions remain limits beside type diagnostics`, async t => {
    const client = await contextClient(t, entrance, absentEnvironment);
    for (const text of ['SELECT ABS(TRUE) AS n', 'SELECT ABS(1) AS n']) {
      const result = await client.check(text, {format: 'sql'});
      assert.equal(result.report.verdict, 'undetermined');
      assert.deepEqual(result.report.reasons, []);
      assert.deepEqual(result.report.coverage, {limits: [{code: 'implementation_limit'}], unresolved: []});
    }
  });
}

for (const entrance of ['local', 'http']) {
  test(`${entrance}: expression type facts retain protected-source equivalence`, async t => {
    const clients = [
      await contextClient(t, entrance, sourceEnvironment),
      await contextClient(t, entrance, sourceEnvironment, {aliases: [alias], readOutcome: 'deny'}),
      await contextClient(t, entrance, sourceEnvironment, {aliases: [alias], readOutcome: 'allow', closed: true}),
    ];
    for (const text of ["SELECT SQRT('private-expression-text') AS n",
      "SELECT SQRT('private-expression-text') AS n FROM records"]) {
      const results = await Promise.all(clients.map(client => client.check(text, {format: 'sql'})));
      assert.deepEqual(results[0], results[1], '[check-mutation:expression-type-disclosure]');
      assert.deepEqual(results[0], results[2], '[check-mutation:expression-type-disclosure]');
      const report = results[0].report;
      assert.equal(report.verdict, text.endsWith('records') ? 'undetermined' : 'invalid');
      assert.deepEqual(report.reasons, text.endsWith('records') ? [] :
        [{code: 'expression_type_mismatch', facts: {expected_type: 'number'}}]);
      assert.deepEqual(report.coverage, {limits: [], unresolved: text.endsWith('records')
        ? [{boundary: 'source_resolution', reason: 'unresolved_protected'}] : []});
      assert.equal(JSON.stringify(results).includes('private-expression-text'), false);
    }
    for (const client of clients) {
      const result = await client.check("SELECT SQRT('private-expression-text') AS n FROM records", {format: 'sql',
        parameterDeclarations: {minimum: {type: 'number'}}, parameters: {minimum: 'private-parameter-value'}});
      assert.equal(result.report.verdict, 'invalid');
      assert.deepEqual(result.report.reasons.map(({code, facts}) => ({code, facts})),
        [{code: 'supplied_value_type_mismatch', facts: {parameter: 'minimum', expected_type: 'number', actual_type: 'string'}}]);
      assert.equal(result.report.reasons[0].location.pointer, '/minimum');
      assert.deepEqual(result.report.coverage.unresolved,
        [{boundary: 'source_resolution', reason: 'unresolved_protected'}]);
    }
  });

  test(`${entrance}: SDK rejects malformed expression type facts from an actual check reply`, async t => {
    let mutation = value => value;
    const client = await contextClient(t, entrance, absentEnvironment,
      {mutateCheckTransportReply: value => mutation(value)});
    const check = () => client.check("SELECT SQRT('private-expression-text') AS n", {format: 'sql'});
    assert.deepEqual((await check()).report.reasons, [{code: 'expression_type_mismatch', facts: {expected_type: 'number'}}]);
    for (const facts of [undefined, {}, {expected_type: 'private-field'},
      {expected_type: 'number', actual_value: 'secret'}, {expected_type: 'number', parameter: 'private'}]) {
      mutation = value => ({...value, report: {...value.report,
        reasons: [{code: 'expression_type_mismatch', facts}]}});
      await assert.rejects(check(), {code: 'InvalidHostCheckOutcome'});
    }
  });
}

for (const entrance of ['local', 'http']) {
  test(`${entrance}: check rejects invalid owned frame scalar values`, async t => {
    const client = await contextClient(t, entrance, sourceEnvironment,
      {aliases: [alias], readOutcome: 'allow'});
    for (const direction of ['PRECEDING', 'FOLLOWING']) {
      const text = 'SELECT FIRST_VALUE(amount) OVER '
        + `(ORDER BY id ROWS BETWEEN @before ${direction} AND @after ${direction}) AS first FROM records`;
      for (const before of [0, -1, 1.5, 9007199254740992]) {
        const outcome = await client.check(text, {format: 'sql',
          parameterDeclarations: {before: {type: 'number', nullable: false},
            after: {type: 'number', nullable: false}}, parameters: {before, after: 2}});
        assert.equal(outcome.outcome, 'completed', '[check-mutation:frame-scalar-outcome]');
        assert.equal(outcome.report.verdict, 'invalid', '[check-mutation:frame-scalar-verdict]');
        assert.deepEqual(outcome.report.reasons.map(({code, facts}) => ({code, facts})),
          [{code: 'operation_parameter_invalid', facts: {parameter: 'before', domain: 'positive_safe_integer'}}]);
        assert.deepEqual(outcome.report.coverage, {limits: [], unresolved: []});
        assert.deepEqual(outcome.report.requirements, []);
      }
    }
  });
}

for (const entrance of ['local', 'http']) {
  test(`${entrance}: frame scalar admission retains equal bounds and protected obligations`, async t => {
    const text = direction => 'SELECT FIRST_VALUE(amount) OVER '
      + `(ORDER BY id ROWS BETWEEN @before ${direction} AND @after ${direction}) AS first FROM records`;
    const declarations = {before: {type: 'number', nullable: false},
      after: {type: 'number', nullable: false}};
    const wire = withPolicy(sourceEnvironment, {capacity: {
      ...sourceEnvironment.host_policy_profile.capacity,
      max_analytic_input_wire_bytes: 10000, max_analytic_output_wire_bytes: 10000,
      max_analytic_partition_wire_bytes: 10000, max_analytic_frame_memberships: 10000,
    }});
    const visible = await contextClient(t, entrance, wire, {aliases: [alias], readOutcome: 'allow'});
    for (const direction of ['PRECEDING', 'FOLLOWING']) {
      const valid = await visible.check(text(direction), {format: 'sql',
        parameterDeclarations: declarations, parameters: {before: 2, after: 2}});
      assert.equal(valid.outcome, 'completed');
      assert.equal(valid.report.verdict, 'verified');
      assert.deepEqual(valid.report.reasons, []);
      assert.deepEqual(valid.report.coverage, {limits: [], unresolved: []});
      assert.deepEqual(valid.report.requirements, []);
    }
    const clients = [
      await contextClient(t, entrance, sourceEnvironment),
      await contextClient(t, entrance, sourceEnvironment, {aliases: [alias], readOutcome: 'deny'}),
      await contextClient(t, entrance, sourceEnvironment, {aliases: [alias], readOutcome: 'allow', closed: true}),
    ];
    for (const parameters of [{before: 0, after: 2}, {before: 'private-distance', after: 2}]) {
      const outcomes = await Promise.all(clients.map(client => client.check(text('PRECEDING'),
        {format: 'sql', parameterDeclarations: declarations, parameters})));
      assert.deepEqual(outcomes[0], outcomes[1], '[check-mutation:frame-scalar-disclosure]');
      assert.deepEqual(outcomes[0], outcomes[2], '[check-mutation:frame-scalar-disclosure]');
      const wrongType = typeof parameters.before === 'string';
      const {report} = outcomes[0];
      assert.equal(report.verdict, wrongType ? 'invalid' : 'undetermined');
      assert.deepEqual(report.coverage, {limits: [],
        unresolved: [{boundary: 'source_resolution', reason: 'unresolved_protected'}]});
      assert.deepEqual(report.reasons.map(({code, facts}) => ({code, ...(facts ? {facts} : {})})),
        wrongType ? [{code: 'supplied_value_type_mismatch',
          facts: {parameter: 'before', expected_type: 'number', actual_type: 'string'}}] : []);
      assert.equal(JSON.stringify(outcomes).includes('private-distance'), false);
      if (wrongType) assert.equal(resolveCheckLocation(outcomes[0], report.reasons[0].location).pointer, '/before');
    }
  });
}

// Parser failures carry original structural paths even when no decoded cursor
// can be admitted. These are caller input paths, never serialized SQL spans.
const invalidParsedBindings = [
  {document: 'parameters', code: 'binding_json_invalid',
    options: key => ({parameterDeclarations: {payload: {type: 'number'}},
      parameters: {payload: {[key]: ['safe', '\ud800']}}}),
    prefix: '/payload/'},
  {document: 'parameter_declarations', code: 'binding_json_invalid',
    options: key => ({parameterDeclarations: {payload: {type: 'number',
      default: {[key]: ['safe', '\udfff']}}}}),
    prefix: '/payload/default/'},
];

for (const entrance of ['local', 'http']) {
  test(`${entrance}: session formats use negotiated coordinates and omit stale positions`, async t => {
    const client = await contextClient(t, entrance, sourceEnvironment);
    for (const [encoding, character] of [['utf-8', 19], ['utf-16', 15], ['utf-32', 14]]) {
      const session = sdk.createCheckDocumentSession(client,
        {text: '\ufeff/*😀*/SELECT (', version: 1, positionEncoding: encoding});
      const observation = await session.check({format: 'sql'});
      const shown = JSON.parse(session.format(observation, {format: 'json'}));
      assert.deepEqual(shown.entries[0].location,
        {kind: 'text', documentId: 'source', revision: observation.outcome.report.inputs[0].revision,
          startByte: 19, endByte: 19, precision: 'exact', positionEncoding: encoding,
          range: {start: {line: 0, character}, end: {line: 0, character}}},
        '[check-mutation:session-format-public-encoding]');
      for (const format of ['text', 'html']) {
        const output = session.format(observation, {format});
        assert.ok(output.includes(encoding));
        assert.equal(format === 'html' ? output.includes('&quot;character&quot;:' + character)
          : output.includes('"character":' + character), true);
      }
      const copied = JSON.parse(session.format({...observation}, {format: 'json'}));
      assert.equal(Object.hasOwn(copied.entries[0], 'location'), false,
        '[check-mutation:session-format-public-copy]');
      const stale = JSON.parse(session.format(observation, {format: 'json', get locale() {
        session.update('\ufeff/*😀*/SELECT (', 2); return 'en';
      }}));
      assert.equal(Object.hasOwn(stale.entries[0], 'location'), false,
        '[check-mutation:session-format-public-current]');
      assert.deepEqual(stale.observation, shown.observation);
      const current = await session.check({format: 'sql'});
      const input = getCheckInput(current.outcome, 'source');
      let edited = false;
      const changing = {...input, get text() {
        if (!edited) { edited = true; session.update('edited', 3); }
        return input.text;
      }};
      const changed = JSON.parse(session.format(current, {format: 'json', currentInputs: [changing]}));
      assert.equal(Object.hasOwn(changed.entries[0], 'location'), false,
        '[check-mutation:session-format-public-recheck]');
      assert.deepEqual(changed.observation, shown.observation);
      session.close();
    }
  });

  test(`${entrance}: session formats retain binding JSON facts and protected equivalence`, async t => {
    const clients = [
      await contextClient(t, entrance, sourceEnvironment),
      await contextClient(t, entrance, sourceEnvironment, {aliases: [alias], readOutcome: 'deny'}),
      await contextClient(t, entrance, sourceEnvironment, {aliases: [alias], readOutcome: 'allow', closed: true}),
    ];
    for (const fixture of invalidParsedBindings) {
      const displays = [];
      for (const client of clients) {
        const session = sdk.createCheckDocumentSession(client,
          {text: 'SELECT @payload AS n FROM records', version: 1, positionEncoding: 'utf-8'});
        const observation = await session.check({format: 'sql', ...fixture.options('a/~e\u0301😀')});
        const display = JSON.parse(session.format(observation, {format: 'json'}));
        const reason = observation.outcome.report.reasons[0];
        assert.deepEqual(display.entries[0].facts,
          {document: fixture.document, issue: 'invalid_unicode'},
          '[check-mutation:session-format-public-facts]');
        assert.deepEqual(display.entries[0].location,
          {kind: 'structured', documentId: fixture.document, revision: reason.location.revision,
            pointer: fixture.prefix + 'a~1~0e\u0301😀/1'},
          '[check-mutation:session-format-public-pointer]');
        const formats = ['text', 'html', 'json'].map(format => session.format(observation, {format}));
        for (const formatted of formats) assert.doesNotMatch(formatted,
          /\\ud800|\\udfff|records\.duckdb/u, '[check-mutation:session-format-public-private-value]');
        displays.push(formats);
        session.close();
        const closed = JSON.parse(session.format(observation, {format: 'json'}));
        assert.equal(Object.hasOwn(closed.entries[0], 'location'), false,
          '[check-mutation:session-format-public-close]');
        assert.deepEqual(closed.entries[0].facts, display.entries[0].facts);
      }
      assert.deepEqual(displays[0], displays[1], '[check-mutation:session-format-public-disclosure]');
      assert.deepEqual(displays[0], displays[2], '[check-mutation:session-format-public-disclosure]');
    }
  });
}

for (const entrance of ['local', 'http']) {
  for (const fixture of invalidParsedBindings) {
    test(`${entrance}: JSON parser location survives ${fixture.document} failure`, async t => {
      const client = await contextClient(t, entrance, sourceEnvironment);
      for (const [key, token] of [['a/~é😀', 'a~1~0é😀'], ['a/~e\u0301😀', 'a~1~0e\u0301😀']]) {
        const result = await client.check('SELECT @payload AS n',
          {format: 'sql', ...fixture.options(key)}).catch(error => ({protocolFailure: error.code}));
        assert.equal(result.outcome, 'completed', '[check-mutation:json-parser-outcome]');
        assert.equal(result.report.verdict, 'invalid', '[check-mutation:json-parser-verdict]');
        const input = getCheckInput(result, fixture.document);
        assert.ok(input);
        const location = {kind: 'structured', document_id: fixture.document,
          revision: input.revision, pointer: fixture.prefix + token + '/1'};
        assert.deepEqual(result.report.reasons, [{code: fixture.code, facts: {document: fixture.document, issue: 'invalid_unicode'}, location}],
          '[check-mutation:json-parser-location]');
        assert.deepEqual(explainCheckReason(result.report.reasons[0]), {kind: 'known',
          summary: 'The binding JSON contains invalid Unicode text.',
          hint: 'Use valid Unicode scalar values in member names and string values.'},
        '[check-mutation:json-parser-explanation]');
        assert.equal(resolveCheckLocation(result, location).input, input);
        assert.equal(resolveCheckTextRange(result, location), undefined);
        assert.equal(resolveCheckLocation(result, location, {...input, revision: 'rev:' + '0'.repeat(64)}), undefined);
        assert.equal(JSON.stringify(result).includes('safe'), false);
      }

      // A preserving read may reach a later Unicode error after a normalized
      // duplicate key. It cannot replace the authoritative failure's location.
      const collision = fixture.document === 'parameters'
        ? {parameterDeclarations: {payload: {type: 'number'}},
          parameters: {payload: {'é': 'safe', 'e\u0301': '\ud800'}}}
        : {parameterDeclarations: {'é': {type: 'number'}, 'e\u0301': {type: 'string', default: '\ud800'}}};
      const duplicate = await client.check('SELECT @payload AS n', {format: 'sql', ...collision});
      assert.deepEqual(duplicate.report.reasons, [{code: fixture.code, facts: {document: fixture.document, issue: 'duplicate_key'}}]);
      // A malformed member name has the parser's known enclosing root path,
      // not a fabricated location at a member that could not be decoded.
      const options = fixture.document === 'parameters'
        ? {parameterDeclarations: {payload: {type: 'number'}}, parameters: {'\ud800': 'safe'}}
        : {parameterDeclarations: {'\ud800': {type: 'number'}}};
      const root = await client.check('SELECT @payload AS n', {format: 'sql', ...options});
      const input = getCheckInput(root, fixture.document);
      assert.deepEqual(root.report.reasons, [{code: fixture.code, facts: {document: fixture.document, issue: 'invalid_unicode'},
        location: {kind: 'structured', document_id: fixture.document,
          revision: input.revision, pointer: ''}}]);
    });
  }

  test(`${entrance}: JSON parser failures retain protected-source equivalence`, async t => {
    const clients = [
      await contextClient(t, entrance, sourceEnvironment),
      await contextClient(t, entrance, sourceEnvironment, {aliases: [alias], readOutcome: 'deny'}),
      await contextClient(t, entrance, sourceEnvironment, {aliases: [alias], readOutcome: 'allow', closed: true}),
    ];
    for (const fixture of invalidParsedBindings) {
      const results = await Promise.all(clients.map(client => client.check('SELECT id FROM records',
        {format: 'sql', ...fixture.options('a/~é😀')})));
      assert.deepEqual(results[0], results[1], '[check-mutation:json-parser-disclosure]');
      assert.deepEqual(results[0], results[2], '[check-mutation:json-parser-disclosure]');
      assert.equal(results[0].report.verdict, 'invalid');
      assert.equal(results[0].report.reasons[0].code, fixture.code);
      if (fixture.document === 'parameters') {
        assert.deepEqual(results[0].report.coverage.unresolved,
          [{boundary: 'source_resolution', reason: 'unresolved_protected'}]);
      }
    }
  });

  test(`${entrance}: JSON parser budgets stay unlocated checking limits`, async t => {
    const client = await contextClient(t, entrance, sourceEnvironment);
    const nested = depth => {
      let value = 'leaf';
      for (let i = 0; i < depth; i++) value = [value];
      return value;
    };
    for (const options of [
      {parameterDeclarations: {payload: {type: 'number'}}, parameters: {payload: nested(70)}},
      {parameterDeclarations: {payload: {type: 'number', default: nested(40)}}},
    ]) {
      const result = await client.check('SELECT @payload AS n', {format: 'sql', ...options});
      assert.equal(result.outcome, 'completed');
      assert.equal(result.report.verdict, 'undetermined', '[check-mutation:json-parser-budget]');
      assert.deepEqual(result.report.reasons, []);
      assert.deepEqual(result.report.coverage.limits, [{code: 'analysis_budget_exhausted'}]);
    }
  });
}

for (const entrance of ['local', 'http']) {
  test(`${entrance}: unavailable checking contexts hide every protected Source variant`, async t => {
    const clients = [];
    for (const [wire, options] of [
      [absentEnvironment, {}],
      [sourceEnvironment, {aliases: [alias], readOutcome: 'deny'}],
      [sourceEnvironment, {aliases: [alias], readOutcome: 'allow', closed: true}],
    ]) {
      const observations = {analysis: 0, unavailable: 0, sourceDecisions: 0, authorization: 0, statuses: [], wireOutcomes: []};
      const client = await contextClient(t, entrance, wire,
        {...options, connectionAllowed: false, observations});
      clients.push({client, observations});
    }
    const correlations = new Set();
    for (const [text, options] of [
      ['SELECT 1 AS n', {format: 'sql'}],
      ['SELECT (', {format: 'sql'}],
      [query, {format: 'sql', parameterDeclarations: declarations,
        parameters: {minimum: 'private-input-secret'}}],
      [query, {format: 'sql', parameterDeclarations: declarations}],
    ]) {
      for (const {client, observations} of clients) {
        const received = await client.check(text, options).then(outcome => ({outcome}), error => {
          if (!(error instanceof sdk.ClientError)) throw error;
          return {clientError: error.code};
        });
        assert.equal(received.outcome?.outcome, 'unavailable', `[check-mutation:check-context-outcome] ${received.clientError ?? 'public outcome'}`);
        const outcome = received.outcome;
        assert.deepEqual(observations.wireOutcomes.at(-1), outcome, '[check-mutation:check-context-envelope]');
        assert.match(outcome.correlation_ref, /^corr:[a-f0-9]{32}$/u);
        assert.equal(correlations.has(outcome.correlation_ref), false);
        correlations.add(outcome.correlation_ref);
        assert.deepEqual({...outcome, correlation_ref: 'opaque-attempt'}, {
          version: 'actql-check-outcome/0.1', reason_schema_cid: checkReasonSchemaCid,
          outcome_schema_cid: checkOutcomeSchemaCid, outcome: 'unavailable',
          correlation_ref: 'opaque-attempt', problem: {code: 'check_unavailable'},
        }, '[check-mutation:check-context-envelope]');
        assert.equal(getCheckInput(outcome, 'source'), undefined);
        assert.equal(sdk.getCheckRequirementFrontier(outcome), undefined);
        assert.deepEqual(sdk.explainCheckOutcome(outcome), {
          outcome: 'unavailable', problem: {kind: 'known', code: 'check_unavailable'},
          correlationRef: outcome.correlation_ref,
          summary: 'The scope and checking context needed for a safe public report are unavailable.',
          hint: 'Ask the checking-context owner to review the published context; this response does not establish an input error.',
        });
        assert.equal(observations.analysis, 0, '[check-mutation:check-context-analysis]');
        assert.equal(observations.sourceDecisions, 0, '[check-mutation:check-context-analysis]');
      }
    }
    for (const {observations} of clients) {
      assert.equal(observations.authorization, 4);
      assert.equal(observations.unavailable, 4);
      assert.deepEqual(observations.statuses, entrance === 'http' ? [200, 200, 200, 200] : []);
    }
  });

  test(`${entrance}: connection authorization loss preserves earlier reports`, async t => {
    let allowed = true;
    const observations = {analysis: 0, unavailable: 0, sourceDecisions: 0, authorization: 0, statuses: [], wireOutcomes: []};
    const client = await contextClient(t, entrance, sourceEnvironment,
      {aliases: [alias], readOutcome: 'allow', observations,
        connectionAllowed: () => allowed});
    const earlier = await client.check('SELECT 1 AS n', {format: 'sql'});
    const retained = structuredClone(earlier);
    assert.equal(earlier.report.verdict, 'verified');
    assert.equal(observations.analysis, 1);
    assert.equal(observations.sourceDecisions, 1);
    allowed = false;
    const received = await client.check('SELECT (', {format: 'sql'}).then(outcome => ({outcome}), error => {
      if (!(error instanceof sdk.ClientError)) throw error;
      return {clientError: error.code};
    });
    assert.equal(received.outcome?.outcome, 'unavailable', `[check-mutation:check-context-outcome] ${received.clientError ?? 'public outcome'}`);
    assert.deepEqual(earlier, retained);
    assert.equal(getCheckInput(earlier, 'source').text, 'SELECT 1 AS n');
    assert.equal(getCheckInput(received.outcome, 'source'), undefined);
    assert.equal(observations.analysis, 1, '[check-mutation:check-context-analysis]');
    assert.equal(observations.sourceDecisions, 1, '[check-mutation:check-context-analysis]');
    allowed = true;
    const current = await client.check('SELECT @x AS n', {format: 'sql',
      parameterDeclarations: {x: {type: 'number'}}, parameters: {}});
    assert.equal(current.report.verdict, 'undetermined');
    assert.notEqual(current.report.context_ref, earlier.report.context_ref);
    assert.deepEqual(current.report.requirements.map(reason => reason.facts),
      [{parameter: 'x', expected_type: 'number', admission: expectedNumberAdmission}]);
    assert.equal(observations.analysis, 2);
    assert.equal(observations.sourceDecisions, 2);
  });
}


for (const entrance of ['local', 'http']) {
  test(`${entrance}: unavailable producer failures never disclose a report`, async t => {
    let replacement;
    let rejectProjection = false;
    let authorization = true;
    const observations = {analysis: 0, unavailable: 0, sourceDecisions: 0, authorization: 0, statuses: [], wireOutcomes: []};
    const client = await contextClient(t, entrance, sourceEnvironment,
      {aliases: [alias], readOutcome: 'allow', observations,
        connectionAllowed: () => {
          if (authorization === 'throw') throw new Error('private-context-authorization');
          return authorization;
        },
        mutateUnavailable: value => {
          if (rejectProjection) throw new Error('private-context-producer');
          return replacement ?? value;
        }});
    const earlier = await client.check('SELECT 1 AS n', {format: 'sql'});
    authorization = false;
    for (const invalid of [earlier,
      {version: 'actql-check-outcome/0.1', reason_schema_cid: checkReasonSchemaCid,
        outcome_schema_cid: checkOutcomeSchemaCid, outcome: 'unavailable', correlation_ref: 'corr:bad',
        problem: {code: 'check_unavailable'}, context_ref: 'private-context-binding'},
      {version: 'actql-check-outcome/0.1', reason_schema_cid: checkReasonSchemaCid,
        outcome_schema_cid: checkOutcomeSchemaCid, outcome: 'unavailable', correlation_ref: 'corr:bad',
        problem: {code: 'check_unavailable', secret: 'private-context-fact'}},
    ]) {
      replacement = invalid;
      await assert.rejects(client.check('SELECT 1 AS n', {format: 'sql'}), error =>
        error instanceof sdk.ClientError && error.code === 'ClientHostFailure' &&
        !JSON.stringify(error).includes('private-context'));
      assert.equal(observations.analysis, 1);
      assert.equal(observations.sourceDecisions, 1);
    }
    replacement = undefined;
    rejectProjection = true;
    await assert.rejects(client.check('SELECT 1 AS n', {format: 'sql'}), error =>
      error instanceof sdk.ClientError && error.code === 'ClientHostFailure' &&
        !JSON.stringify(error).includes('private-context'));
    rejectProjection = false;
    for (const unknown of ['throw', undefined, {allow: true}]) {
      authorization = unknown;
      const outcome = await client.check('SELECT 1 AS n', {format: 'sql'});
      assert.equal(outcome.outcome, 'unavailable');
      assert.equal(outcome.report, undefined);
      assert.equal(outcome.partial_report, undefined);
      assert.equal(observations.analysis, 1);
      assert.equal(observations.sourceDecisions, 1);
    }
    assert.deepEqual(observations.statuses, entrance === 'http'
      ? [200, 500, 500, 500, 500, 200, 200, 200] : []);
    for (const value of observations.wireOutcomes.slice(1)) {
      assert.equal(value.report, undefined);
      assert.equal(value.context_ref, undefined);
      assert.equal(JSON.stringify(value).includes('private-context'), false);
    }
  });
}

test('installed HTTPS: checkpoint readers receive context-unavailable without execution', async t => {
  const hostKeys = generateKeyPairSync('ed25519');
  const reviewerKeys = generateKeyPairSync('ed25519');
  const authorization = {
    reviewers: [{keyId: 'reviewer-key', reviewerId: 'reviewer', principalId: 'reviewer-principal',
      publicKey: reviewerKeys.publicKey.export({format: 'pem', type: 'spki'})}],
    reviewReaders: ['reader-principal'],
    hostKey: {keyId: 'host-key', privateKey: hostKeys.privateKey.export({format: 'pem', type: 'pkcs8'})},
  };
  const outcomes = [];
  for (const configuration of [configurations.absent, configurations.denied]) {
    const root = await mkdtemp(join(scratch, 'context-reader-'));
    const sourceInstallation = await installedConfigurations(root, configuration);
    const observation = observeCheckOnly(t, root);
    const host = await openInstalledRemoteHttpHost({directory: join(root, 'state'),
      authenticate: header => header === 'Bearer reader-token' ? 'reader-principal' : undefined,
      authorization, beforeDispatch: observation.beforeDispatch, ...sourceInstallation});
    const statuses = [];
    const server = createServer({key: tlsKey, cert: tlsCertificate}, (request, response) => {
      if (request.url.endsWith('/check')) response.on('finish', () => statuses.push(response.statusCode));
      return host.handler(request, response);
    });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    t.after(async () => {
      server.closeAllConnections();
      await new Promise(resolve => server.close(resolve));
      await host.close();
      await rm(root, {recursive: true, force: true});
    });
    const client = await connect({mode: 'remote', endpoint: `https://127.0.0.1:${server.address().port}/`,
      token: 'reader-token'});
    t.after(() => client.close());
    // The existing installed Checkpoint owner admits this principal's connection,
    // while the Host connection owner denies its access to the checking context.
    assert.deepEqual((await client.checkpoints()).items, []);
    const received = await client.check(query, {format: 'sql', parameterDeclarations: declarations,
      parameters: {minimum: 'private-input-secret'}}).then(outcome => ({outcome}), error => {
      if (!(error instanceof sdk.ClientError)) throw error;
      return {clientError: error.code};
    });
    assert.equal(received.outcome?.outcome, 'unavailable',
      `[check-mutation:installed-check-context] ${received.clientError ?? 'public outcome'}`);
    outcomes.push({...received.outcome, correlation_ref: 'opaque-attempt'});
    assert.equal(getCheckInput(received.outcome, 'source'), undefined);
    assert.deepEqual(statuses, [200]);
    observation.assertNoExecution();
  }
  assert.deepEqual(outcomes[0], outcomes[1], '[check-mutation:installed-check-context-envelope]');
  assert.deepEqual(outcomes[0], {version: 'actql-check-outcome/0.1',
    reason_schema_cid: checkReasonSchemaCid, outcome_schema_cid: checkOutcomeSchemaCid,
    outcome: 'unavailable', correlation_ref: 'opaque-attempt', problem: {code: 'check_unavailable'}});
});

for (const entrance of ['local', 'http']) {
  test(`${entrance}: check refuses source numbers that JSON would replace`, async t => {
    const client = await contextClient(t, entrance, sourceEnvironment);
    for (const value of [NaN, Infinity, -Infinity, -0]) {
      for (const options of [
        {parameterDeclarations: {x: {type: 'number', nullable: true}}, parameters: {x: value}},
        {parameterDeclarations: {x: {type: 'json'}}, parameters: {x: {nested: [value]}}},
        {parameterDeclarations: {x: {type: 'number', default: value}}},
        {parameterDeclarations: {x: {type: 'json', default: {nested: [value]}}}},
      ]) {
        const result = await client.check('SELECT @x AS n', {format: 'sql', ...options})
          .then(() => ({}), error => ({code: error.code}));
        assert.equal(result.code, 'InvalidCheckRequest', '[check-mutation:numeric-source-refusal]');
        assert.deepEqual(result, {code: 'InvalidCheckRequest'});
      }
    }
    for (const value of [null, 0, 1.25, -2, Number.MAX_VALUE, Number.MIN_VALUE]) {
      const result = await client.check('SELECT @x AS n', {format: 'sql',
        parameterDeclarations: {x: {type: 'number', nullable: true}}, parameters: {x: value}});
      assert.equal(result.report.verdict, 'verified');
      assert.deepEqual(getCheckInput(result, 'parameters').value, {x: value});
    }
  });
}


for (const [entrance, open] of Object.entries(entrances)) {
  test(`${entrance}: check formats retain submitted coordinates and protected equivalence`, async t => {
    const client = await open(t, configurations.denied);
    const outcome = await client.check('\ufeff/*😀*/\r\nSELECT (', {format: 'sql'});
    const json = JSON.parse(sdk.formatCheckOutcome(outcome, {format: 'json'}));
    assert.equal(json.observation.report.verdict, 'invalid', '[check-mutation:format-verdict]');
    assert.deepEqual(json.entries[0].location, {kind: 'text', documentId: 'source',
      revision: outcome.report.inputs[0].revision, startByte: 21, endByte: 21, precision: 'exact',
      positionEncoding: 'utf-16', range: {start: {line: 1, character: 8}, end: {line: 1, character: 8}}},
    '[check-mutation:format-location]');
    const copied = JSON.parse(sdk.formatCheckOutcome(JSON.parse(JSON.stringify(outcome)), {format: 'json'}));
    assert.equal(Object.hasOwn(copied.entries[0], 'location'), false, '[check-mutation:format-stale]');
    const input = getCheckInput(outcome, 'source');
    for (const currentInputs of [[], [{...input, text: 'SELECT 1 AS n'}],
      [{...input, revision: 'rev:' + '0'.repeat(64)}]]) {
      const stale = JSON.parse(sdk.formatCheckOutcome(outcome, {format: 'json', currentInputs}));
      assert.equal(Object.hasOwn(stale.entries[0], 'location'), false, '[check-mutation:format-stale]');
      assert.equal(stale.observation.report.verdict, 'invalid');
    }
    assert.deepEqual(JSON.parse(sdk.formatCheckOutcome(outcome, {format: 'json', currentInputs: [input]})), json);
    let reads = 0;
    const changing = {...input, get text() { return ++reads <= 2 ? input.text : ' '.repeat(21); }};
    const owned = JSON.parse(sdk.formatCheckOutcome(outcome, {format: 'json', currentInputs: [changing]}));
    assert.deepEqual(owned.entries[0].location.range,
      {start: {line: 1, character: 8}, end: {line: 1, character: 8}}, '[check-mutation:format-owned-input]');

    for (const format of ['text', 'html', 'json']) {
      const views = [];
      for (const configuration of [configurations.absent, configurations.denied]) {
        const selected = await contextClient(t, entrance, sourceEnvironment, {
          aliases: configuration.aliases,
          ...(configuration.aliases.length ? {readOutcome: configuration.readOutcome} : {})});
        const check = await selected.check('SELECT @x AS n FROM records', {format: 'sql',
          parameterDeclarations: {x: {type: 'number'}}, parameters: {x: 'private-supplied-value'}});
        const rendered = sdk.formatCheckOutcome(check, {format});
        assert.doesNotMatch(rendered, /private-supplied-value|records\.duckdb/u, '[check-mutation:format-input]');
        views.push(rendered);
      }
      assert.equal(views[0], views[1], '[check-mutation:format-disclosure]');
      if (format === 'json') {
        const model = JSON.parse(views[0]);
        assert.equal(model.observation.report.verdict, 'invalid');
        assert.deepEqual(model.entries.map(x => x.kind), ['violation', 'unresolved']);
      }
    }
    client.assertNoExecution();
  });
}

for (const entrance of ['local', 'http']) {
  test(`${entrance}: raw check ingress refuses lossy source numbers`, async t => {
    let post, checked = 0;
    const body = options => ({connection: {mode: entrance === 'local' ? 'local' : 'remote',
      owner: entrance === 'local' ? 'local' : 'remote', consentRefs: [], runners: []},
    input: {text: 'SELECT @x AS n', format: 'sql',
      parameterDeclarations: options.parameterDeclarations}, parameters: options.parameters ?? null});
    await contextClient(t, entrance, sourceEnvironment, {
      mutateCheckReply: outcome => {checked++; return outcome;},
      sdkConnectInProcess: async (options, port) => {
        post = async (options) => port.perform('check', body(options))
          .then(value => ({value}), error => ({value: {code: error.code}}));
        return connectInProcess(options, port);
      },
      sdkConnect: async options => {
        post = async (bindings, token) => {
          const wire = JSON.stringify(body(bindings)).replace('"numeric-token"', token ?? 'null');
          const response = await fetch(new URL('actql/client/0.1/check', options.endpoint), {
            method: 'POST', headers: {'content-type': 'application/json',
              authorization: 'Bearer owner-token'}, body: wire,
            signal: AbortSignal.timeout(5000)});
          return {status: response.status, value: await response.json()};
        };
        return connect(options);
      },
    });
    const fixtures = value => [
      {parameterDeclarations: {x: {type: 'number', nullable: true}}, parameters: {x: value}},
      {parameterDeclarations: {x: {type: 'object', fields: {nested: {type: 'array', items: {type: 'number'}}}}},
        parameters: {x: {nested: [value]}}},
      {parameterDeclarations: {x: {type: 'number', default: value}}},
      {parameterDeclarations: {x: {type: 'object', fields: {nested: {type: 'array', items: {type: 'number'}}},
        default: {nested: [value]}}}},
    ];
    const invalid = entrance === 'local'
      ? [NaN, Infinity, -Infinity, -0, new Number(NaN), new Number(-0),
        {toJSON: () => Infinity}, {toJSON: () => -0},
        Object.assign(new Number(1), {valueOf: () => NaN}),
        Object.assign(new Number(1), {[Symbol.toPrimitive]: () => -0})]
      : ['-0', '1e309', '-1e309'];
    for (const value of invalid) {
      for (const fixture of fixtures(entrance === 'local' ? value : 'numeric-token')) {
        const response = await post(fixture, value);
        assert.equal(response.value.code, 'InvalidClientRequest', '[check-mutation:host-numeric-refusal]');
        assert.deepEqual(response.value, {code: 'InvalidClientRequest'});
        if (entrance === 'http') assert.equal(response.status, 400);
        assert.equal(checked, 0);
      }
    }
    for (const value of [null, 0, 1.25, -2, Number.MAX_VALUE, Number.MIN_VALUE]) {
      const response = await post({parameterDeclarations: {x: {type: 'number', nullable: true}},
        parameters: {x: entrance === 'local' ? value : 'numeric-token'}}, JSON.stringify(value));
      assert.equal(response.value.report?.verdict, 'verified');
      if (entrance === 'http') assert.equal(response.status, 200);
    }
    // Detachment does not turn the checker's depth budget into request refusal.
    let nested = 'leaf';
    for (let i = 0; i < 70; i++) nested = [nested];
    const limited = await post({parameterDeclarations: {x: {type: 'number'}}, parameters: {x: nested}});
    assert.equal(limited.value.outcome, 'completed');
    assert.equal(limited.value.report.verdict, 'undetermined');
    assert.deepEqual(limited.value.report.reasons, []);
    assert.deepEqual(limited.value.report.coverage.limits, [{code: 'analysis_budget_exhausted'}]);
  });
}

test('local: raw check input custody precedes asynchronous authentication', async t => {
  let raw, waiting = false, release;
  const pendingAuthentication = new Promise(resolve => {release = resolve;});
  await contextClient(t, 'local', sourceEnvironment, {
    localAuthenticate: async () => {if (waiting) await pendingAuthentication; return owner;},
    sdkConnectInProcess: async (options, port) => {
      raw = body => port.perform('check', body);
      return connectInProcess(options, port);
    },
  });
  waiting = true;
  const body = {connection: {mode: 'local', owner: 'local', consentRefs: [], runners: []},
    input: {text: 'SELECT @x AS n', format: 'sql', parameterDeclarations: {x: {type: 'number'}}},
    parameters: {x: 7}};
  const pending = raw(body);
  body.input.text = 'SELECT (';
  body.input.parameterDeclarations.x.type = 'string';
  body.parameters.x = 'changed-after-admission';
  release();
  const result = await pending;
  assert.equal(result.report.verdict, 'verified', '[check-mutation:host-check-input-custody]');
  assert.deepEqual(result.report.inputs.map(({document_id, byte_length}) => ({document_id, byte_length})),
    [{document_id: 'source', byte_length: 14}, {document_id: 'parameter_declarations', byte_length: 23},
      {document_id: 'parameters', byte_length: 7}]);
});

test('local: check snapshots cannot erase or introduce unexpected request fields', async t => {
  let raw, checked = 0;
  await contextClient(t, 'local', sourceEnvironment, {
    mutateCheckReply: outcome => {checked++; return outcome;},
    sdkConnectInProcess: async (options, port) => {
      raw = body => port.perform('check', body).then(value => value,
        error => ({code: error.code}));
      return connectInProcess(options, port);
    },
  });
  const request = () => ({connection: {mode: 'local', owner: 'local', consentRefs: [], runners: []},
    input: {text: 'SELECT 1 AS n', format: 'sql'}, parameters: null});
  for (const value of [undefined, () => null, Symbol('unknown')]) {
    for (const domain of ['request', 'input']) {
      const body = request();
      (domain === 'request' ? body : body.input).extra = value;
      const result = await raw(body);
      assert.equal(result.code, 'InvalidClientRequest', '[check-mutation:host-check-request-shape]');
      assert.deepEqual(result, {code: 'InvalidClientRequest'});
      assert.equal(checked, 0);
    }
  }
  const body = request();
  Object.defineProperty(body, 'toJSON', {value: () => ({...body, extra: true})});
  const result = await raw(body);
  assert.equal(result.code, 'InvalidClientRequest', '[check-mutation:host-check-request-shape]');
  assert.deepEqual(result, {code: 'InvalidClientRequest'});
  assert.equal(checked, 0);
});

for (const entrance of ['local', 'http']) {
  test(`${entrance}: unsaved document sessions bind current revisions and reply order`, async t => {
    let hold = false;
    const waiting = [];
    let arrived;
    const client = await contextClient(t, entrance, absentEnvironment, {
      mutateCheckReply: outcome => hold ? new Promise(resolve => {
        waiting.push(() => resolve(outcome));
        arrived?.();
      }) : outcome,
    });
    const waitFor = count => waiting.length >= count ? Promise.resolve() :
      new Promise(resolve => {arrived = () => {if (waiting.length >= count) resolve();};});
    // Independent source bytes include BOM, a non-BMP scalar and unchanged CRLF.
    for (const [encoding, eof] of [['utf-8', 19], ['utf-16', 15], ['utf-32', 14]]) {
      const session = sdk.createCheckDocumentSession(client,
        {text: '\ufeff/*😀*/SELECT (', version: 1, positionEncoding: encoding});
      const observation = await session.check({format: 'sql'});
      const location = observation.outcome.report.reasons[0].location;
      assert.equal(location.start_byte, 19);
      assert.deepEqual(session.resolveTextRange(observation, location)?.range,
        {start: {line: 0, character: eof}, end: {line: 0, character: eof}},
        '[check-mutation:document-public-encoding]');
      assert.equal(getCheckInput(observation.outcome, 'source').text, '\ufeff/*😀*/SELECT (');
      session.close();
    }
    const session = sdk.createCheckDocumentSession(client,
      {text: '\ufeff/*😀*/\r\nSELECT (', version: 1});
    hold = true;
    const first = session.check({format: 'sql'});
    const second = session.check({format: 'sql', parameters: {x: 'private-second-binding'}});
    await waitFor(2);
    waiting[1](); const newer = await second;
    waiting[0](); const older = await first;
    const location = newer.outcome.report.reasons[0].location;
    assert.equal(newer.outcome.report.verdict, 'invalid');
    assert.deepEqual(session.resolveTextRange(newer, location)?.range,
      {start: {line: 1, character: 8}, end: {line: 1, character: 8}});
    assert.equal(session.resolveTextRange(older, older.outcome.report.reasons[0].location), undefined,
      '[check-mutation:document-public-order]');
    assert.equal(session.resolveTextRange({...newer}, location), undefined,
      '[check-mutation:document-public-copy]');
    session.update('SELECT 1 AS n', 2);
    assert.equal(session.resolveTextRange(newer, location), undefined,
      '[check-mutation:document-public-current]');
    const closing = session.check({format: 'sql'});
    await waitFor(3); session.close(); waiting[2](); const closed = await closing;
    assert.equal(closed.outcome.report.verdict, 'verified');
    assert.equal(session.resolveTextRange(newer, location), undefined,
      '[check-mutation:document-public-close]');
    hold = false;
    const reopened = sdk.createCheckDocumentSession(client,
      {text: '\ufeff/*😀*/\r\nSELECT (', version: 1});
    assert.equal(reopened.resolveTextRange(newer, location), undefined,
      '[check-mutation:document-public-session]');
    const current = await reopened.check({format: 'sql'});
    assert.ok(reopened.resolveTextRange(current, current.outcome.report.reasons[0].location));
    assert.equal(getCheckInput(current.outcome, 'source').text, '\ufeff/*😀*/\r\nSELECT (');
    assert.doesNotMatch(JSON.stringify(newer), /private-second-binding/);
    reopened.close();
  });
}

for (const entrance of ['local', 'http']) {
  test(`${entrance}: check protocol failures retain original input without verdict or retry authority`, async t => {
    let alter = value => value;
    const observations = {authorization: 0, analysis: 0, unavailable: 0,
      sourceDecisions: 0, wireOutcomes: [], statuses: []};
    const client = await contextClient(t, entrance, absentEnvironment,
      {observations, mutateCheckTransportReply: value => alter(value)});
    const text = '/*e\u0301😀*/\r\nSELECT \'\\q\' AS label';
    const parameterDeclarations = {x: {type: 'string'}};
    const parameters = {x: 'private-submitted-protocol-value'};
    for (const [mutation, kind, problem] of [
      [value => ({...value, outcome: 'private-future-outcome'}), 'uninterpretable', 'unknown_outcome'],
      [value => ({...value, report: {...value.report,
        reasons: [{code: 'query_lexical_invalid', facts: {issue: 42}}]}}),
      'protocol_failure', 'malformed_response'],
      [value => ({...value, outcome_schema_cid: `sha256:${'0'.repeat(64)}`}),
        'protocol_failure', 'contract_mismatch'],
      [value => ({...value, reason_schema_cid: undefined}), 'protocol_failure', 'malformed_response'],
      [value => ({...value, report: {...value.report, inputs: value.report.inputs.map(input =>
        input.document_id === 'source' ? {...input, byte_length: input.byte_length + 1} : input)}}),
      'protocol_failure', 'malformed_response'],
    ]) {
      alter = mutation;
      const before = observations.analysis;
      let failure;
      try { await client.check(text, {format: 'sql', parameterDeclarations, parameters}); }
      catch (error) { failure = error; }
      assert.equal(failure?.code, 'InvalidHostCheckOutcome', '[check-mutation:protocol-failure-public-rejection]');
      const view = sdk.explainCheckFailure(failure);
      assert.deepEqual(view && {kind: view.kind, problem: view.problem}, {kind, problem},
        '[check-mutation:protocol-failure-public]');
      assert.deepEqual(sdk.getCheckFailureInput(failure), {text, format: 'sql', parameterDeclarations, parameters},
        '[check-mutation:protocol-failure-public-input]');
      assert.equal(observations.analysis, before + 1);
      for (const field of ['verdict', 'report', 'scope', 'contextRef', 'correlationRef', 'next', 'ref']) {
        assert.equal(Object.hasOwn(view, field), false);
      }
      assert.equal(getCheckInput(failure, 'source'), undefined);
      assert.equal(resolveCheckLocation(failure, observations.wireOutcomes.at(-1).report.reasons[0].location), undefined);
      assert.equal(sdk.getCheckFailureInput(structuredClone(failure)), undefined);
      assert.equal(sdk.explainCheckFailure(new Error('InvalidHostCheckOutcome')), undefined);
      assert.equal(JSON.stringify({failure, view}).includes('private-future-outcome'), false);
      assert.equal(JSON.stringify({failure, view}).includes('private-submitted-protocol-value'), false);
      assert.equal(sdk.explainCheckFailure(failure, {locale: 'ja'}).kind, kind);
    }
    // A valid unknown reason remains a rejected-source observation with a safe
    // unknown explanation, distinct from malformed known reason facts.
    alter = value => ({...value, report: {...value.report, reasons: [{code: 'future_reason'}]}});
    const outcome = await client.check(text, {format: 'sql', parameterDeclarations, parameters});
    assert.equal(outcome.report.verdict, 'invalid');
    assert.equal(explainCheckReason(outcome.report.reasons[0]).kind, 'unknown');
    assert.equal(sdk.explainCheckFailure(outcome), undefined);
    assert.equal(observations.analysis, 6);
  });
}


for (const [entrance, open] of Object.entries(entrances)) {
  test(`${entrance}: lexical fixes retain original EOF edits and require review`, async t => {
    const client = await open(t, configurations.absent);
    // Original byte intervals and edited texts are independently authored.
    for (const [text, at, comment, changed] of [
      ['SELECT 1 AS n /*', 16, 14, 'SELECT 1 AS n /**/'],
      ['/*😀*/\r\nSELECT 1 AS n /*', 26, 24, '/*😀*/\r\nSELECT 1 AS n /**/'],
      ['\ufeffSELECT 1 AS n /*', 19, 17, '\ufeffSELECT 1 AS n /**/'],
      ['SELECT 1 AS n /* e\u0301😀\r\n', 26, 14, 'SELECT 1 AS n /* e\u0301😀\r\n*/'],
    ]) {
      const session = sdk.createCheckDocumentSession(client, {text, version: 1});
      const observation = await session.check({format: 'sql'});
      const outcome = observation.outcome;
      assert.equal(outcome.outcome, 'completed');
      assert.equal(outcome.report.verdict, 'invalid');
      const input = sdk.getCheckInput(outcome, 'source');
      assert.equal(input.text, text);
      const reason = outcome.report.reasons[0];
      assert.deepEqual(reason, {code: 'query_lexical_invalid',
        facts: {issue: 'unterminated_comment'},
        location: {kind: 'text', document_id: 'source', revision: input.revision,
          start_byte: comment, end_byte: comment, precision: 'exact'},
        fixes: [{code: 'close_block_comment', applicability: 'requires_review',
          risk: 'syntax_structure', target: {document_id: 'source', revision: input.revision},
          edits: [{start_byte: at, end_byte: at, replacement: '*/'}]}]},
      '[check-mutation:lexical-fix-original]');
      assert.equal(new TextEncoder().encode(text).length, at);
      assert.equal(sdk.getCheckFixes(structuredClone(outcome)), undefined,
        '[check-mutation:fix-copy]');
      let refusal;
      try { await session.applyFixes(observation, sdk.getCheckFixes(outcome),
        {version: 2, reviewed: false}); } catch (error) { refusal = error.code; }
      assert.equal(refusal, 'CheckFixReviewRequired', '[check-mutation:fix-review]');
      const applied = await session.applyFixes(observation, sdk.getCheckFixes(outcome),
        {version: 2, reviewed: true});
      const corrected = applied.outcome;
      assert.equal(sdk.getCheckInput(corrected, 'source').text, changed,
        '[check-mutation:fix-atomic-text]');
      assert.equal(sdk.getCheckInput(outcome, 'source').text, text);
      assert.equal(session.resolveTextRange(observation, reason.location), undefined);
      assert.equal(corrected.outcome, 'completed');
      assert.equal(corrected.report.verdict, 'verified');
      assert.deepEqual(corrected.report.reasons, []);
      session.close();
    }
    client.assertNoExecution();
  });
}

for (const entrance of ['local', 'http']) {
  for (const lostAt of ['before', 'after_candidate']) {
    test(`${entrance}: lexical fixes reject connection permission loss ${lostAt}`, async t => {
      let allowed = true, checks = 0;
      const client = await contextClient(t, entrance, absentEnvironment, {
        connectionAllowed: () => allowed,
        mutateCheckReply: outcome => {
          if (++checks === 3 && lostAt === 'after_candidate') allowed = false;
          return outcome;
        },
      });
      const session = sdk.createCheckDocumentSession(client, {text: 'SELECT 1 AS n /*', version: 1});
      const observation = await session.check({format: 'sql'});
      if (lostAt === 'before') allowed = false;
      let refusal;
      try {await session.applyFixes(observation, sdk.getCheckFixes(observation.outcome),
        {version: 2, reviewed: true});} catch (error) {refusal = error.code;}
      assert.equal(refusal, 'CheckFixContextChanged', '[check-mutation:fix-public-permission]');
      assert.ok(session.resolveTextRange(observation, observation.outcome.report.reasons[0].location));
      allowed = true;
      const unchanged = await session.check({format: 'sql'});
      assert.equal(sdk.getCheckInput(unchanged.outcome, 'source').text, 'SELECT 1 AS n /*');
      assert.equal(unchanged.version, 1);
      session.close();
    });
  }
}

for (const entrance of ['local', 'http']) {
  test(`${entrance}: lexical fix replies reject preceding pins and malformed proposals`, async t => {
    for (const mutate of [
      outcome => {
        outcome.reason_schema_cid = 'sha256:6b6f4811a1d2fd685c309769b30a796273d47a45182aff58b7398358c6770fb6';
        outcome.outcome_schema_cid = 'sha256:0f7a006d18e01848f95b7d6b7204f82c1913136d148d26ebffec26bb1b587ef2';
      },
      outcome => {outcome.report.reasons[0].fixes[0].edits[0].start_byte = 15;},
      outcome => {outcome.report.reasons[0].fixes[0].target.revision = 'rev:' + '0'.repeat(64);},
      outcome => {outcome.report.reasons[0].location.precision = 'approximate';},
    ]) {
      const client = await contextClient(t, entrance, absentEnvironment, {
        mutateCheckTransportReply: outcome => {mutate(outcome); return outcome;},
      });
      let refusal;
      try {await client.check('SELECT 1 AS n /*', {format: 'sql'});} catch (error) {refusal = error.code;}
      assert.equal(refusal, 'InvalidHostCheckOutcome', '[check-mutation:fix-reply-validation]');
    }
  });
}

for (const entrance of ['local', 'http']) {
  for (const [property, transition] of [
    ['document_id', 'close'], ['kind', 'edit'], ['start_byte', 'edit'],
    ['end_byte', 'edit'], ['document_id', 'newer-check'],
  ]) {
    test(`${entrance}: session range rejects ${transition} from a ${property} accessor`, async t => {
      const client = await contextClient(t, entrance, absentEnvironment);
      const text = '\ufeff/*😀*/SELECT (';
      const session = sdk.createCheckDocumentSession(client, {text, version: 1});
      t.after(() => session.close());
      const observation = await session.check({format: 'sql'});
      const location = observation.outcome.report.reasons[0].location;
      assert.equal(location.start_byte, 19);
      assert.deepEqual(session.resolveTextRange(observation, location)?.range,
        {start: {line: 0, character: 15}, end: {line: 0, character: 15}});
      let changed = false, newer;
      const changingLocation = {...location};
      Object.defineProperty(changingLocation, property, {enumerable: true, get() {
        if (!changed) {
          changed = true;
          if (transition === 'edit') session.update('SELECT 1 AS n', 2);
          else if (transition === 'close') session.close();
          else newer = session.check({format: 'sql'});
        }
        return location[property];
      }});
      const resolved = session.resolveTextRange(observation, changingLocation);
      if (newer) await newer;
      assert.equal(changed, true);
      assert.equal(session.resolveTextRange(observation, location), undefined);
      assert.equal(getCheckInput(observation.outcome, 'source').text, text);
      assert.equal(observation.outcome.report.verdict, 'invalid');
      assert.equal(resolved, undefined, '[check-mutation:document-public-range-callback]');
    });
  }
}

// Independent context oracle: literal public fixture selections and registered
// manifests, with an ordinary sorted JSON encoder. No product canonicalizer,
// compiler accessor or returned reference constructs the expected preimage.
const contextGrammar = JSON.parse(await readFile(join(repository,
  'spec/manifests/actql-grammar-0.1.json'), 'utf8'));
const contextBarriers = JSON.parse(await readFile(join(repository,
  'spec/manifests/actql-barrier-contracts-0.1.json'), 'utf8'));
const contextProtocols = JSON.parse(await readFile(join(repository,
  'spec/contracts/actql-protocol-schemas.json'), 'utf8'));
const contextJSON = value => {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return '[' + value.map(contextJSON).join(',') + ']';
  return '{' + Object.keys(value).sort().map(key =>
    JSON.stringify(key) + ':' + contextJSON(value[key])).join(',') + '}';
};

for (const entrance of ['local', 'http']) {
  test(`${entrance}: context references bind both schemas through ordinary and fallback input`, async t => {
    const clients = [
      await contextClient(t, entrance, absentEnvironment),
      await contextClient(t, entrance, sourceEnvironment, {aliases: [alias], readOutcome: 'deny'}),
      await contextClient(t, entrance, sourceEnvironment, {aliases: [alias], readOutcome: 'allow', closed: true}),
    ];
    const base = {version: 'actql-check-context/0.1', audience: owner,
      disclosure_policy: 'actql-check-disclosure/0.1', projection: 'actql-check-outcome/0.1',
      scope: 'bound_input', compiler: {compiler_version: 'actql-moonbit-0.0.1',
        grammar_manifest_cid: contextGrammar.grammar_manifest_cid,
        barrier_contract_manifest_cid: contextBarriers.barrier_contract_manifest_cid},
      reason_schema_cid: contextProtocols.artifact_schema_cids.check_reason,
      outcome_schema_cid: contextProtocols.artifact_schema_cids.check_outcome,
      checking_context: {host_policy_profile: sourceEnvironment.host_policy_profile,
        model_task_contract_cids: [], profiles: {text_time: false, veca: false,
          rela: true, sga: true, tea: false, calendar: false, text_rank: false,
          graph: false, graph_law_cid: null, model_tasks: true,
          numeric_profile_cid: null, calendar_profile_cid: null, text_rank_profile_cid: null}},
      visible_aliases: []};
    const hash = value => 'ctx:' + createHmac('sha256', new Uint8Array(32).fill(7))
      .update(contextJSON(value)).digest('hex');
    for (const parameterDeclarations of [undefined,
      {'é': {type: 'string'}, 'e\u0301': {type: 'string'}}]) {
      const references = [];
      for (const text of ["SELECT 'café' AS label", "SELECT 'cafe\u0301' AS label"]) {
        const input = {text, format: 'sql',
          ...(parameterDeclarations === undefined ? {} : {parameterDeclarations})};
        const preimage = {...base, ...(parameterDeclarations === undefined
          ? {source: {format: 'sql', text}, parameter_declarations: null, parameters: null}
          : {received: JSON.stringify({input, parameters: null})})};
        const {outcome_schema_cid, ...precedingProjection} = preimage;
        assert.notEqual(hash(preimage), hash(precedingProjection));
        const outcomes = [];
        for (const client of clients) {
          const outcome = await client.check(text, {format: 'sql', parameterDeclarations});
          assert.equal(outcome.outcome, 'completed');
          assert.equal(outcome.report.context_ref, hash(preimage),
            '[check-mutation:context-schema-public]');
          assert.equal(getCheckInput(outcome, 'source').text, text);
          assert.deepEqual(await client.check(text, {format: 'sql', parameterDeclarations}), outcome);
          outcomes.push(outcome);
        }
        assert.deepEqual(outcomes[0], outcomes[1]);
        assert.deepEqual(outcomes[0], outcomes[2]);
        references.push(outcomes[0].report.context_ref);
      }
      assert.notEqual(references[0], references[1]);
    }
  });
}


for (const entrance of ['local', 'http']) {
  test(`${entrance}: bounded Requirement enumeration preserves verdict, scope and protected coverage`, async t => {
    const observations = {authorization: 0, analysis: 0, unavailable: 0, sourceDecisions: 0, wireOutcomes: [], statuses: []};
    const client = await contextClient(t, entrance, absentEnvironment, {observations});
    const parameterDeclarations = Object.fromEntries(Array.from({length: 512}, (_, i) =>
      [`p${String(i).padStart(3, '0')}`, {type: 'number'}]));
    const expected = Array.from({length: 64}, (_, i) => ({code: 'parameter_value_required',
      facts: {parameter: `p${String(i).padStart(3, '0')}`, expected_type: 'number', admission: expectedNumberAdmission}}));
    const options = {format: 'sql', parameterDeclarations, parameters: {}};
    for (const [text, verdict, reasons] of [
      ['SELECT 1 AS n', 'undetermined', []],
      ['SELECT (', 'invalid', [{code: 'query_syntax_invalid'}]],
    ]) {
      const before = observations.analysis;
      const outcome = await client.check(text, options);
      assert.equal(outcome.outcome, 'completed', '[check-mutation:omissions-public-outcome]');
      assert.equal(outcome.report.verdict, verdict, '[check-mutation:omissions-public-verdict]');
      assert.deepEqual(outcome.report.scope, {kind: 'bound_input'});
      assert.deepEqual(outcome.report.omissions, {requirements: true}, '[check-mutation:omissions-public-summary]');
      assert.deepEqual(outcome.report.reasons.map(({location, ...reason}) => reason), reasons);
      assert.deepEqual(outcome.report.requirements.map(({location, ...reason}) => reason), expected,
        '[check-mutation:omissions-public-prefix]');
      assert.deepEqual(outcome.report.coverage, {limits: [{code: 'bound_values_missing'}], unresolved: []});
      assert.equal(observations.analysis, before + 1, '[check-mutation:omissions-public-once]');
      assert.ok(Buffer.byteLength(JSON.stringify(outcome)) <= 65536);
      assert.equal(getCheckInput(outcome, 'source').text, text);
      const view = sdk.explainCheckOutcome(outcome);
      assert.deepEqual(view.report.omissions, {requirements: true});
      assert.equal(view.report.completeness, 'complete');
      assert.equal(sdk.getCheckRequirementFrontier(outcome), undefined, '[check-mutation:omissions-public-frontier]');
      assert.equal(sdk.equalCheckRequirementFrontiers(outcome, outcome), undefined);
      for (const locale of ['en', 'ja']) {
        const json = JSON.parse(sdk.formatCheckOutcome(outcome, {format: 'json', locale, maxBytes: 1024}));
        assert.equal(json.observation.report.verdict, verdict);
        assert.deepEqual(json.observation.report.omissions, {requirements: true});
        const textView = sdk.formatCheckOutcome(outcome, {locale, maxBytes: 1024});
        assert.match(textView, locale === 'ja' ? /省略しました/ : /Host omitted/);
      }
      if (verdict === 'invalid') {
        const location = outcome.report.reasons[0].location;
        const resolved = resolveCheckLocation(outcome, location);
        assert.deepEqual({kind: resolved.kind, startByte: resolved.start_byte,
          endByte: resolved.end_byte, originalText: resolved.input.text, span: resolved.text},
          {kind: 'text', startByte: 8, endByte: 8, originalText: text, span: ''});
      }
    }
    const absent = await contextClient(t, entrance, sourceEnvironment);
    const denied = await contextClient(t, entrance, sourceEnvironment, {aliases: [alias], readOutcome: 'deny'});
    const protectedText = 'SELECT id FROM records';
    const protectedOutcomes = [];
    for (const boundary of [absent, denied]) {
      const outcome = await boundary.check(protectedText, options);
      assert.equal(outcome.outcome, 'completed');
      assert.equal(outcome.report.verdict, 'undetermined');
      assert.deepEqual(outcome.report.omissions, {requirements: true});
      assert.deepEqual(outcome.report.coverage, {limits: [{code: 'bound_values_missing'}], unresolved: [{boundary: 'source_resolution', reason: 'unresolved_protected'}]});
      protectedOutcomes.push(outcome);
    }
    assert.deepEqual(protectedOutcomes[0], protectedOutcomes[1], '[check-mutation:omissions-public-disclosure]');
    const session = sdk.createCheckSupplementationSession(client, {maxAttempts: 3});
    const result = await session.check('SELECT 1 AS n', options);
    assert.deepEqual(result.decision, {kind: 'stop', reason: 'frontier_unavailable'});
    const after = observations.analysis;
    await assert.rejects(session.check('SELECT 1 AS n', options), {code: 'CheckSupplementationStopped'});
    assert.equal(observations.analysis, after);
  });

  test(`${entrance}: Requirement byte pressure reduces only enumeration within a reserved budget`, async t => {
    const observations = {authorization: 0, analysis: 0, unavailable: 0, sourceDecisions: 0, wireOutcomes: [], statuses: []};
    const client = await contextClient(t, entrance, absentEnvironment, {observations});
    const names = Array.from({length: 128}, (_, i) => `p${String(i).padStart(3, '0')}_${'x'.repeat(235)}`);
    const parameterDeclarations = Object.fromEntries(names.map(name => [name, {type: 'number'}]));
    const outcome = await client.check('SELECT 1 AS n', {format: 'sql', parameterDeclarations, parameters: {}});
    assert.equal(outcome.outcome, 'completed');
    assert.equal(outcome.report.verdict, 'undetermined');
    assert.deepEqual(outcome.report.omissions, {requirements: true});
    assert.deepEqual(outcome.report.requirements.map(reason => reason.facts.parameter), names.slice(0, 64),
      '[check-mutation:omissions-public-byte-prefix]');
    assert.ok(Buffer.byteLength(JSON.stringify(outcome)) <= 65536);
    assert.equal(observations.analysis, 1);
    assert.deepEqual(outcome.report.coverage, {limits: [{code: 'bound_values_missing'}], unresolved: []});
  });
}

for (const entrance of ['local', 'http']) {
  test(`${entrance}: missing parameter Requirements expose admitted recursive declaration conditions`, async t => {
    const client = await contextClient(t, entrance, absentEnvironment);
    const contractSchemaCid = 'sha256:02859499357530af0ae58e4f2958d1c8fa48f957b86b0a2976dad43bed99b551';
    const cases = [
      [{type: 'number', nullable: true, integer: true, minimum: -2.5, maximum: 4.5,
        meta: {note: 'private-admission-note', instruction: 'private-admission-instruction'}},
      {nullable: true, type: 'number'}, [{kind: 'numeric', path: [], integer: true, minimum: -2.5, maximum: 4.5}], 3],
      [{type: 'string', format: 'duration'}, {nullable: false, type: 'string'},
        [{kind: 'duration', path: []}], '2s'],
      [{type: 'boolean'}, {nullable: false, type: 'boolean'}, [], true],
      [{type: 'decimal', precision: 4, scale: 2}, {nullable: false, type: 'decimal', precision: 4, scale: 2}, [],
        {__cid: {decimal: '1.25', precision: 4, scale: 2}}],
      [{type: 'object', fields: {rows: {type: 'array', length: 2, max_items: 3,
        items: {type: 'number', integer: true, minimum: -1.5}}}},
      {nullable: false, type: 'object', additional_properties: false, fields: {rows: {
        nullable: false, type: 'array', max_items: 3, items: {nullable: false, type: 'number'}}}},
      [{kind: 'array_length', path: [{kind: 'field', name: 'rows'}], length: 2},
        {kind: 'numeric', path: [{kind: 'field', name: 'rows'}, {kind: 'items'}], integer: true, minimum: -1.5}],
      {rows: [0, 1]}],
    ];
    for (const [declaration, contract, constraints, supplied] of cases) {
      const parameterDeclarations = {x: declaration};
      const outcome = await client.check('SELECT @x AS n', {format: 'sql', parameterDeclarations, parameters: {}});
      assert.equal(outcome.outcome, 'completed');
      assert.equal(outcome.report.verdict, 'undetermined');
      assert.deepEqual(outcome.report.scope, {kind: 'bound_input'}, '[check-mutation:admission-public-scope]');
      const expected = {kind: 'parameter_declaration', contract_schema_cid: contractSchemaCid,
        contract, constraints, supplier: 'caller'};
      const requirement = outcome.report.requirements[0];
      assert.doesNotMatch(JSON.stringify(outcome), /private-admission-note|private-admission-instruction|"meta"|"default"/,
        '[check-mutation:admission-public-disclosure]');
      assert.deepEqual(requirement.facts.admission, expected, '[check-mutation:admission-public-facts]');
      assert.deepEqual(sdk.getCheckParameterAdmission(outcome, 'x'), expected);
      const frontier = sdk.getCheckRequirementFrontier(outcome);
      assert.deepEqual(frontier.requirements[0].facts.admission, expected,
        '[check-mutation:frontier-admission-facts]');
      assert.ok(Object.isFrozen(frontier.requirements[0].facts.admission));
      assert.equal(frontier.contextRef, outcome.report.context_ref);
      assert.ok(Object.isFrozen(sdk.getCheckParameterAdmission(outcome, 'x')));
      assert.equal(sdk.getCheckParameterAdmission(outcome, 'unknown'), undefined);
      assert.equal(sdk.getCheckParameterAdmission(structuredClone(outcome), 'x'), undefined,
        '[check-mutation:admission-public-custody]');
      assert.deepEqual(resolveCheckLocation(outcome, requirement.location).input.value.x, declaration);

      const view = JSON.parse(sdk.formatCheckOutcome(outcome, {format: 'json', maxBytes: 65536}));
      assert.deepEqual(view.entries.find(entry => entry.kind === 'requirement').facts.admission, expected);
      // The existing binder and complete Program checker decide the new value.
      // Conditions in a Requirement are not an admitted value or Run permission.
      if (contract.type !== 'decimal') {
        const bound = await client.check('SELECT @x AS n', {format: 'sql', parameterDeclarations, parameters: {x: supplied}});
        assert.equal(bound.report.verdict, 'verified');
        assert.notEqual(bound.report.context_ref, outcome.report.context_ref, '[check-mutation:admission-public-recheck]');
        assert.equal(outcome.report.verdict, 'undetermined');
        assert.equal(sdk.getCheckParameterAdmission(bound, 'x'), undefined);
      }
    }
    const invalid = await client.check('SELECT @x AS n', {format: 'sql',
      parameterDeclarations: {x: {type: 'number', integer: true, minimum: -2.5, maximum: 4.5}}, parameters: {x: 2.25}});
    assert.equal(invalid.report.verdict, 'invalid');
    assert.deepEqual(invalid.report.reasons[0].facts,
      {parameter: 'x', constraint: 'numeric'});
    assert.equal(sdk.getCheckParameterAdmission(invalid, 'x'), undefined);
  });

  test(`${entrance}: an unbound checking frontier does not certify unused template declarations`, async t => {
    const client = await contextClient(t, entrance, absentEnvironment);
    const text = 'SELECT 1 AS n';
    const parameterDeclarations = {x: {type: 'number'}};
    const missing = await client.check(text, {format: 'sql', parameterDeclarations, parameters: {}});
    assert.equal(missing.report.verdict, 'undetermined', '[check-mutation:template-frontier-not-proof]');
    assert.deepEqual(missing.report.scope, {kind: 'bound_input'});
    assert.deepEqual(missing.report.coverage.limits, [{code: 'bound_values_missing'}]);
    assert.equal(missing.report.requirements.length, 1);
    const supplied = await client.check(text, {format: 'sql', parameterDeclarations, parameters: {x: 1}});
    assert.equal(supplied.report.verdict, 'invalid');
    assert.deepEqual(supplied.report.reasons[0].facts, {parameter: 'x'});
    assert.equal(supplied.report.reasons[0].code, 'parameter_unused');
    assert.notEqual(supplied.report.context_ref, missing.report.context_ref);
    assert.equal(getCheckInput(supplied, 'source').revision, getCheckInput(missing, 'source').revision);
  });
}

for (const entrance of ['local', 'http']) {
  test(`${entrance}: Requirement rule ordering cannot create supplementation progress`, async t => {
    let reverse = false;
    const client = await contextClient(t, entrance, absentEnvironment, {mutateCheckTransportReply(outcome) {
      if (reverse) outcome.report.requirements[0].facts.admission.constraints.reverse();
      return outcome;
    }});
    const options = {format: 'sql', parameterDeclarations: {x: {type: 'array', length: 2,
      items: {type: 'number', integer: true, minimum: -1.5}}}, parameters: {}};
    const session = sdk.createCheckSupplementationSession(client, {maxAttempts: 3});
    const first = await session.check('SELECT @x AS n', options);
    assert.deepEqual(first.decision, {kind: 'more_checks'});
    reverse = true;
    const second = await session.check('SELECT @x AS n', options);
    assert.deepEqual(second.decision, {kind: 'stop', reason: 'unchanged_frontier'},
      '[check-mutation:admission-public-frontier]');
    assert.equal(sdk.equalCheckRequirementFrontiers(first.outcome, second.outcome), true);
    assert.equal(first.outcome.report.context_ref, second.outcome.report.context_ref);
    assert.notDeepEqual(first.outcome.report.requirements[0].facts.admission.constraints,
      second.outcome.report.requirements[0].facts.admission.constraints);
  });
}
