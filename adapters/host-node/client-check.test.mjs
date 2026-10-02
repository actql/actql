// Public check outcome and disclosure, through the public Local and HTTP
// entrances of installed Hosts with a real DuckDB source profile. The
// environment, aliases and account configurations are independent fixtures;
// nothing is read back from the implementation to build an expectation.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {createRequire} from 'node:module';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import test, {after} from 'node:test';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {connect} from '../../packages/sdk/index.mjs';
import {validCheckOutcome} from '../../packages/client-wire/index.mjs';
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

async function installedSource(root, {readOutcome, aliases}) {
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
    version: 'actql-installed-duckdb-source/0.1',
    database, schema: 'main', table: 'records', sourceRef,
    queryAliases: aliases,
    checkEnvironmentWire: canonicalText(sourceEnvironment),
    accountConfigurationWire: account(readOutcome),
  }));
  return path;
}

async function localClient(t, configuration) {
  const root = await mkdtemp(join(scratch, 'local-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const sourceProfilePath = await installedSource(root, configuration);
  return connectEmbeddedLocal({mode: 'local', owner: 'local',
    installation: {directory: join(root, 'state'), sourceProfilePath}});
}

async function httpClient(t, configuration) {
  const root = await mkdtemp(join(scratch, 'http-'));
  const sourceProfilePath = await installedSource(root, configuration);
  const host = await openInstalledRemoteHttpHost({
    directory: join(root, 'state'),
    authenticate: header => header === 'Bearer owner-token' ? owner
      : undefined,
    sourceProfilePath,
  });
  const server = createServer({key: tlsKey, cert: tlsCertificate},
    host.handler);
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
  return Object.freeze({check: client.check, post});
}

const entrances = Object.freeze({local: localClient, http: httpClient});
const contextRef = /^ctx:[0-9a-f]{64}$/u;
// Context references are keyed per Host installation: they are compared
// within one Host here, and across Hosts by the fixed-key tests below.
const withoutContext = outcome => {
  assert.equal(outcome.outcome, 'completed');
  assert.match(outcome.report.context_ref, contextRef);
  return {...outcome, report: {...outcome.report, context_ref: '<ctx>'}};
};

const protectedSource = [{boundary: 'source_resolution',
  reason: 'unresolved_protected'}];

for (const [entrance, open] of Object.entries(entrances)) {
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
          coverage: {limits: [], unresolved: protectedSource}}}, name);
      // Without the violation the protected source leaves it undetermined,
      // never invalid and never verified.
      assert.deepEqual(withoutContext(await check(client, 'satisfied')), {
        outcome: 'completed', version: 'actql-check-outcome/0.1',
        report: {context_ref: '<ctx>', scope: {kind: 'bound_input'},
          verdict: 'undetermined', reasons: [],
          coverage: {limits: [], unresolved: protectedSource}}}, name);
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
    assert.deepEqual(withoutContext(outcome).report, {context_ref: '<ctx>',
      scope: {kind: 'bound_input'}, verdict: 'undetermined', reasons: [],
      coverage: {limits: [{code: 'analysis_budget_exhausted'}],
        unresolved: []}});
  });

  test(`${entrance}: undecidable visibility is unavailable without a report`,
    async t => {
      const client = await open(t, configurations.undecidable);
      const outcomes = [await check(client, 'violation'),
        await check(client, 'satisfied'),
        await client.check('SELECT id FROM accounts', {format: 'sql'})];
      for (const outcome of outcomes) {
        assert.equal(validCheckOutcome(outcome), true);
        assert.deepEqual(Object.keys(outcome).sort(),
          ['correlation_ref', 'outcome', 'problem', 'version']);
        assert.equal(outcome.outcome, 'unavailable');
        assert.deepEqual(outcome.problem, {code: 'check_unavailable'});
      }
      // A correlation reference identifies one answer, not the request.
      assert.equal(new Set(outcomes.map(item => item.correlation_ref)).size,
        outcomes.length);
      if (entrance === 'http') {
        const response = await client.post({input: {text: query,
          format: 'sql'}, parameters: null});
        assert.equal(response.status, 200);
        assert.equal((await response.json()).outcome, 'unavailable');
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

async function installation(install, {readOutcome, aliases}) {
  const authorization = await createNodeAuthorizationGate({
    configuration: account(readOutcome),
    context: {principal: owner, contextCid: `sha256:${'3'.repeat(64)}`}});
  return install({moon, environment, contextKey,
    publication: sourceAliasPublication(moon, environment, aliases),
    sourceAccess: {authorization, connection: 'local-database',
      resource: '/records.duckdb', sourceRef}});
}

const ownerRequest = (name, principalId = owner) => ({principalId,
  input: {text: requests[name].text, format: 'sql',
    parameterDeclarations: declarations},
  parameters: requests[name].parameters});

async function acceptDisclosure(install) {
  const absent = await installation(install, configurations.absent);
  const denied = await installation(install, configurations.denied);
  for (const name of ['violation', 'satisfied']) {
    const left = await absent(ownerRequest(name));
    const right = await denied(ownerRequest(name));
    assert.equal(canonicalJson(left), canonicalJson(right), name);
    assert.equal(left.outcome, 'completed', name);
    assert.deepEqual(left.report.coverage.unresolved, protectedSource, name);
    assert.equal(left.report.verdict,
      name === 'violation' ? 'invalid' : 'undetermined', name);
    assert.deepEqual(left.report.reasons, name === 'violation'
      ? [{code: 'supplied_value_invalid'}] : [], name);
  }
  // A reference is never reused for another audience.
  assert.notEqual((await denied(ownerRequest('violation', 'other')))
    .report.context_ref, (await denied(ownerRequest('violation')))
    .report.context_ref);
}

test('fixed-key owners give byte-equal outcomes for absent and denied',
  () => acceptDisclosure(installNodeClientCheck));

test('an unsupported format is a failure without a verdict', async () => {
  const check = await installation(installNodeClientCheck,
    configurations.denied);
  assert.deepEqual(await check({principalId: owner,
    input: {text: 'SELECT id FROM records', format: 'json'},
    parameters: null}), {outcome: 'failed',
    problem: {code: 'check_format_unsupported'},
    version: 'actql-check-outcome/0.1'});
});

test('the public outcome contract keeps verdicts bound and partial ' +
  'reports unverified', () => {
  const report = {context_ref: 'ctx:a', scope: {kind: 'bound_input'},
    verdict: 'undetermined', reasons: [],
    coverage: {limits: [], unresolved: []}};
  const version = 'actql-check-outcome/0.1';
  assert.equal(validCheckOutcome({outcome: 'completed', report, version}),
    true);
  for (const key of ['context_ref', 'scope']) {
    const {[key]: _removed, ...unbound} = report;
    assert.equal(validCheckOutcome({outcome: 'completed', report: unbound,
      version}), false, key);
  }
  assert.equal(validCheckOutcome({outcome: 'failed',
    partial_report: {...report, verdict: 'invalid'},
    problem: {code: 'check_internal'}, version}), true);
  assert.equal(validCheckOutcome({outcome: 'failed',
    partial_report: {...report, verdict: 'verified'},
    problem: {code: 'check_internal'}, version}), false);
  assert.equal(validCheckOutcome({outcome: 'unavailable',
    correlation_ref: 'corr:a', problem: {code: 'check_unavailable'},
    report, version}), false);
});

// Each mutation is one plausible change to the Host owner. Its module is
// written beside the scratch Host roots with absolute imports.
const ownerSource = await readFile(new URL('./client-check.mjs',
  import.meta.url), 'utf8');
const mutations = Object.freeze({
  // A denied name becomes unavailable while an absent one completes.
  'denied changes the outcome kind': [
    "else if (decision.action !== 'deny') return undefined;",
    'else return undefined;'],
  // A denied name is checked as if it were visible.
  'denied source is checked as visible': [
    'JSON.stringify({environmentCid, aliases: visible})',
    'JSON.stringify({environmentCid, aliases})'],
  // The context reference names the private source set.
  'context binds the private source set': [
    'visible_aliases: visible,', 'visible_aliases: aliases,'],
  // A reference is reused across audiences.
  'context omits the audience': [
    'version: contextVersion, audience: principalId,',
    'version: contextVersion,'],
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
