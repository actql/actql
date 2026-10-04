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
import {userInfo} from 'node:os';
import {DatabaseSync} from 'node:sqlite';
import {join} from 'node:path';
import test, {after} from 'node:test';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {connect, getCheckInput, resolveCheckLocation, explainCheckReason} from '../../packages/sdk/index.mjs';
import {validCheckOutcome, checkReasonSchemaCid} from '../../packages/client-wire/index.mjs';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';
import {createNodeAuthorizationGate} from './authorization.mjs';
import {installNodeClientCheck} from './client-check.mjs';
import {connectEmbeddedLocal, openInstalledRemoteHttpHost} from
  './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';
import {sourceAliasPublication} from './source-alias-publication.mjs';

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
const contextRef = /^ctx:[0-9a-f]{64}$/u;
// Context references are keyed per Host installation: they are compared
// within one Host here, and across Hosts by the fixed-key tests below.
const withoutContext = (outcome, expectedAssertion) => {
  assert.equal(outcome.outcome, 'completed', expectedAssertion === undefined
    ? undefined : `[check-mutation:${expectedAssertion}]`);
  assert.match(outcome.report.context_ref, contextRef);
  assert.equal(outcome.reason_schema_cid, checkReasonSchemaCid);
  assert.equal(outcome.report.inputs[0].document_id, 'source');
  for (const input of outcome.report.inputs) assert.match(input.revision, /^rev:[0-9a-f]{64}$/u);
  // These original fixtures compare classification/coverage. Exact public
  // locations and retained inputs have their own independent vectors below.
  const {reason_schema_cid, ...envelope} = outcome;
  const {inputs, requirements, ...report} = outcome.report;
  return {...envelope, report: {...report, context_ref: '<ctx>',
    reasons: report.reasons.map(({location, facts, ...reason}) =>
      reason.code === 'supplied_value_type_mismatch' ? {code: 'supplied_value_invalid'} : reason)}};
};

const protectedSource = [{boundary: 'source_resolution',
  reason: 'unresolved_protected'}];

for (const [entrance, open] of Object.entries(entrances)) {
  test(`${entrance}: unresolved column expressions retain authored source positions`, async t => {
    const client = await open(t, configurations.denied);
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
        assert.deepEqual(outcome.report.reasons, [{code: 'query_invalid',
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
    }
    client.assertNoExecution();
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
    for (const [declaration, value, pointer] of [
      [{type: 'object', fields: {count: {type: 'number', integer: true}}},
        {count: 1.5}, '/options/count'],
      [{type: 'object', fields: {count: {type: 'number', minimum: 1}}},
        {count: 0}, '/options/count'],
      [{type: 'object', fields: {waits: {type: 'array', length: 2, items: {type: 'string'}}}},
        {waits: ['private-value']}, '/options/waits'],
      [{type: 'array', items: {type: 'string', format: 'duration'}},
        ['1s', 'private-value'], '/options/1'],
    ]) {
      const outcome = await client.check('SELECT id FROM records', {format: 'sql',
        parameterDeclarations: {options: declaration}, parameters: {options: value}});
      assert.equal(outcome.outcome, 'completed', '[check-mutation:constraint-outcome]');
      const original = getCheckInput(outcome, 'parameters');
      assert.equal(outcome.report.verdict, 'invalid');
      assert.deepEqual(outcome.report.reasons, [{code: 'supplied_value_invalid',
        location: {document_id: 'parameters', revision: original.revision,
          kind: 'structured', pointer}}], '[check-mutation:constraint-location]');
      assert.deepEqual(outcome.report.coverage, {limits: [], unresolved: protectedSource});
      assert.equal(resolveCheckLocation(outcome, outcome.report.reasons[0].location).input, original);
      assert.equal(JSON.stringify(outcome).includes('private-value'), false);
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
    assert.deepEqual(defaults.report.reasons, [{code: 'parameter_declarations_invalid'}]);
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
        facts: {parameter: 'minimum', expected_type: 'number'},
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
      ['SELECT', 6, 6],
      ['SELECT 1 AS n,\r\n', 16, 16],
      ["\ufeffSELECT 'é😀e\u0301' AS x,\r\n", 29, 29],
    ];
    const revisions = [];
    for (const [text, start, end] of cases) {
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
      reasons: [{code: 'query_invalid'}],
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
            reasons: invalid ? [{code: 'parameter_declarations_invalid'}] : [],
            coverage: {limits: [], unresolved: []}});
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
    undecidable: await installation(install, configurations.undecidable)};
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
  // When the decision owner itself cannot be consulted, the absent and the
  // denied installation are both unavailable, with nothing else to compare.
  const unavailable = [];
  for (const configuration of [configurations.absent, configurations.denied]) {
    const check = await installation(install, configuration, {closed: true});
    const outcome = await check(ownerRequest('violation'));
    assert.deepEqual(Object.keys(outcome).sort(),
      ['correlation_ref', 'outcome', 'problem', 'reason_schema_cid', 'version']);
    unavailable.push({...outcome, correlation_ref: '<corr>'});
  }
  assert.deepEqual(unavailable[0], unavailable[1]);
  assert.equal(unavailable[0].outcome, 'unavailable');
}

test('fixed-key owners give byte-equal outcomes for absent, denied and ' +
  'undecided sources',
  () => acceptDisclosure(installNodeClientCheck));

test('an unsupported format is a failure without a verdict', async () => {
  const check = await installation(installNodeClientCheck,
    configurations.denied);
  assert.deepEqual(await check({principalId: owner,
    input: {text: 'SELECT id FROM records', format: 'json'},
    parameters: null}), {outcome: 'failed',
    problem: {code: 'check_format_unsupported'}, reason_schema_cid: checkReasonSchemaCid,
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
  assert.equal(validCheckOutcome({outcome: 'completed', report, version, reason_schema_cid}),
    true);
  for (const key of ['context_ref', 'scope']) {
    const {[key]: _removed, ...unbound} = report;
    assert.equal(validCheckOutcome({outcome: 'completed', report: unbound,
      version, reason_schema_cid}), false, key);
  }
  assert.equal(validCheckOutcome({outcome: 'failed',
    partial_report: {...report, verdict: 'invalid',
      reasons: [{code: 'supplied_value_invalid'}]},
    problem: {code: 'check_internal'}, version, reason_schema_cid}), true);
  assert.equal(validCheckOutcome({outcome: 'failed',
    partial_report: {...report, verdict: 'verified',
      coverage: {limits: [], unresolved: []}},
    problem: {code: 'check_internal'}, version, reason_schema_cid}), false);
  assert.equal(validCheckOutcome({outcome: 'unavailable',
    correlation_ref: 'corr:a', problem: {code: 'check_unavailable'},
    report, version, reason_schema_cid}), false);
});

// Each mutation is one plausible change to the Host owner. Its module is
// written beside the scratch Host roots with absolute imports.
const ownerSource = await readFile(new URL('./client-check.mjs',
  import.meta.url), 'utf8');
const mutations = Object.freeze({
  // A denied name becomes unavailable while an absent one completes.
  'denied changes the outcome kind': [
    "if (decision?.action !== 'dispatch') return [];",
    "if (decision?.action === 'deny') return undefined;\n" +
    "    if (decision?.action !== 'dispatch') return [];"],
  // An undecided source withholds the whole check, unrelated violations
  // included.
  'an undecided source withholds the check': [
    "if (decision?.action !== 'dispatch') return [];",
    "if (!['dispatch', 'deny'].includes(decision?.action)) return undefined;\n" +
    "    if (decision?.action !== 'dispatch') return [];"],
  // Whether the decision owner is consulted depends on the published names.
  'unavailability depends on the published names': [
    'if (!readTuple) return null;',
    'if (!readTuple || aliases.length === 0) return null;'],
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
    for (const coverage of [
      {limits: [{code: 'analysis_budget_exhausted'}], unresolved: []},
      {limits: [], unresolved: [{boundary: 'source_resolution',
        reason: 'unresolved_protected'}]},
    ]) {
      mutation = value => ({...value, report: {...value.report, coverage}});
      await assert.rejects(check(), {code: 'InvalidHostCheckOutcome'});
    }
    mutation = value => ({version: value.version, outcome: 'failed',
      problem: {code: 'check_internal'}, partial_report: value.report});
    await assert.rejects(check(), {code: 'InvalidHostCheckOutcome'});
  });
