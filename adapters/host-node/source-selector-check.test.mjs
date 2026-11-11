// Independent authored cases through installed Local and trusted HTTPS Hosts.
// The common row Source supplies metadata; checking never calls its page driver.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {generateKeyPairSync} from 'node:crypto';
import {mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import test, {after} from 'node:test';
import * as sdk from '../../packages/sdk/index.mjs';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {validCheckOutcome} from '../../packages/client-wire/index.mjs';
import {createInstalledConnectorTable} from './installed-connectors.mjs';
import {canonicalJson, contentCid, createLocalAuthorizationGate} from './local-account-config.mjs';
import {connectEmbeddedLocal, openInstalledRemoteHttpHost} from './embedded-local.mjs';

const scratch = new URL('../../_build/source-selector-check/', import.meta.url);
await mkdir(scratch, {recursive: true});
const tls = await mkdtemp(new URL('tls-', scratch).pathname);
execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
  '-keyout', 'key.pem', '-out', 'cert.pem', '-days', '1', '-subj', '/CN=localhost',
  '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd: tls, stdio: 'ignore'});
const key = await readFile(join(tls, 'key.pem')), cert = await readFile(join(tls, 'cert.pem'));
const certificates = getCACertificates('default');
setDefaultCACertificates([...certificates, cert.toString()]);
after(async () => {setDefaultCACertificates(certificates); await rm(tls, {recursive: true, force: true});});
const principal = userInfo().username;
const baseWire = (await readFile(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8')).trimEnd();
const keys = generateKeyPairSync('ed25519');
const account = (outcome = 'allow', namespace = 'registrations', submissionRead = false) => canonicalJson({
  version: 'actql-execution-account-config/0.1', account_id: 'selector-disclosure',
  entries: [...(submissionRead ? [{entry_id: 'read-original-submission', outcome: 'allow',
    principal: {any_of: [principal]}, connection: {any_of: ['actql-remote-host']},
    resource: {any_of: ['run']}, operation: {any_of: ['read']}, exclusions: []}] : []),
    {entry_id: 'selector-absence', outcome, principal: {any_of: [principal]},
    connection: {any_of: ['actql-source-namespace']}, resource: {any_of: [namespace]},
    operation: {any_of: ['inspect_absence']}, exclusions: []}]});
const protectedSource = [{boundary: 'source_resolution', reason: 'unresolved_protected'}];
const program = (selector = {connector: 'missing', resource: 'r', view: 'records'}, inputName = 'rows') => ({
  version: 'actql/0.1', id: 'selector.input',
  stages: [{id: 'main', inputs: {[inputName]: selector},
    steps: [{from: inputName, select: ['id'], as: 'selected'}],
    results: {out: {from: 'selected', fields: ['id']}}}],
  results: {out: {from: {stage: 'main', result: 'out'}}}});
const options = {kind: 'program', scope: 'bound_input'};
const absentReason = (result, selector, pointer = '/stages/0/inputs/rows/view', namespace = 'registrations') => ({
  code: 'source_selector_unregistered', facts: {namespace, ...selector},
  location: {kind: 'structured', document_id: 'program',
    revision: sdk.getCheckInput(result, 'program').revision, pointer}});

async function fixture(t, entrance, {registered = false, namespace = 'registrations',
  grant = 'allow', grantNamespace = namespace, unstable = false, accountFile, omitNamespace = false,
  submissionRead = false} = {}) {
  const root = await mkdtemp(new URL(`${entrance}-`, scratch).pathname);
  const counts = {sourcePages: 0, physicalTarget: 0, credentials: 0, model: 0, effect: 0, resume: 0, dispatch: 0};
  let sourceProfilePath, connectorTable, client, host, server;
  t.after(async () => {
    await client?.close();
    if (server !== undefined) {server.closeAllConnections(); await new Promise(resolve => server.close(resolve));}
    await host?.close();
    await rm(root, {recursive: true, force: true});
  });
  if (registered) {
    sourceProfilePath = join(root, 'source.json');
    const profile = {version: 'actql-installed-selector-test-source/0.1', generation: 1};
    await writeFile(sourceProfilePath, JSON.stringify(profile));
    connectorTable = createInstalledConnectorTable([{name: 'selector_fixture', registration: 'selector_fixture',
      revision: 'selector_fixture/0.1', source: {profileVersion: profile.version, load: async () => ({
        check: value => Object.freeze({...value, connectorId: 'fixture'}),
        identityParts: value => [value],
        async load(value, {principalId, construction}) {
          construction.prepareAuthoredDeclaration(JSON.stringify({views: [
            {resource: 'r', resource_kind: 'row', fields: [{name: 'id', type: 'number', nullable: false}]},
          ]}));
          await construction.openSpecializedSite({
            authorizationConstructor: () => createLocalAuthorizationGate({principal: principalId,
              accountConfiguration: canonicalJson({version: 'actql-execution-account-config/0.1',
                account_id: 'private-source', entries: []})}),
            siteConstructor: (_profile, {authorization}) => Object.freeze({
              connection: 'selector-fixture', close: () => authorization.close()}),
          });
          if (unstable) await writeFile(sourceProfilePath, JSON.stringify({version: value.version, generation: 2}));
          return construction.createRowSource({connection: 'selector-fixture',
            bindingCid: contentCid({site: 'selector-fixture'}), readOperation: 'read',
            physicalTarget() {counts.physicalTarget++; assert.fail('Check must not select a physical target');},
            readPages() {counts.sourcePages++; assert.fail('Check must not read Source pages');},
            limits: {maxPages: 1, maxPageBytes: 1024, maxPageRows: 10, maxCaptureRows: 10}});
        },
      })}}]);
  }
  const installation = {directory: join(root, 'state'), sourceProfilePath, connectorTable,
    ...(omitNamespace ? {} : {sourceSelectorNamespace: namespace}),
    resolveSourceSecret() {counts.credentials++; assert.fail('Check must not resolve credentials');},
    registerModelProviders: () => [{providerId: 'selector-test-model', validatePrompt: () => false,
      invoke() {counts.model++; assert.fail('Check must not invoke Model');}}],
    effectInstallation: {environmentWire: baseWire,
      execute() {counts.effect++; assert.fail('Check must not execute Effect');},
      resume() {counts.resume++; assert.fail('Check must not resume Effect');}},
    authorization: {...(accountFile ? {accountConfig: accountFile} : {accountConfiguration: account(grant, grantNamespace, submissionRead)}),
      hostKey: {keyId: 'selector-host', privateKey: keys.privateKey.export({format: 'pem', type: 'pkcs8'})},
      reviewers: [{keyId: 'selector-reviewer', reviewerId: 'selector-reviewer', principalId: principal,
        publicKey: keys.publicKey.export({format: 'pem', type: 'spki'})}]},
  };
  if (entrance === 'local') {
    client = await connectEmbeddedLocal({mode: 'local', owner: 'local', installation});
  }
  else {
    host = await openInstalledRemoteHttpHost({...installation,
      authenticate: header => header === 'Bearer selector-token' ? principal : undefined,
      beforeDispatch() {counts.dispatch++; assert.fail('Check must not dispatch');}});
    server = createServer({key, cert}, (request, response) => host.handler(request, response));
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    client = await sdk.connect({mode: 'remote', endpoint: `https://127.0.0.1:${server.address().port}/`, token: 'selector-token'});
  }
  const assertCheckOnly = (submitted = 0) => {
    const db = new DatabaseSync(join(root, 'state/requests/client-requests.sqlite3'), {readOnly: true});
    try {
      assert.deepEqual({...db.prepare(`SELECT COUNT(*) AS runs, COALESCE(SUM(dispatch_reserved),0) AS dispatch,
        COALESCE(SUM(physical_start_reserved),0) AS physical FROM client_requests`).get(),
        submissions: db.prepare('SELECT COUNT(*) AS n FROM client_submitted_intents').get().n,
        issued: db.prepare('SELECT issued_count AS n FROM client_submitted_intent_custody').get().n},
      {runs: 0, dispatch: 0, physical: 0, submissions: submitted, issued: submitted});
    } finally {db.close();}
    assert.deepEqual(counts, {sourcePages: 0, physicalTarget: 0, credentials: 0, model: 0, effect: 0, resume: 0, dispatch: 0},
      '[check-mutation:selector-public-no-execution]');
  };
  return {client, assertCheckOnly, root};
}

for (const entrance of ['local', 'https']) {
  test(`${entrance}: original Program refusal exposes passive selector diagnostics without Run admission`, async t => {
    // Same-intent lookup needs its own Host read permission; this grants no
    // Source read, Model call, physical start or Run acceptance.
    const f = await fixture(t, entrance, {submissionRead: true}), input = program();
    let rejection;
    try {await f.client.start(input);} catch (error) {rejection = error;}
    assert.equal(rejection?.code, 'SubmissionNotAccepted');
    const outcome = sdk.getSubmissionOutcome(rejection);
    assert.equal(outcome.kind, 'not_accepted');
    const checked = sdk.getSubmissionCheckObservation(rejection);
    assert.equal(checked.report.verdict, 'invalid');
    const {location: _authoredOnly, ...reason} = absentReason(checked, input.stages[0].inputs.rows);
    // This projects the SAME captured native Program refusal. Its detached
    // keys have no original authored coordinates; explicit check keeps them.
    assert.deepEqual(checked.report.reasons, [reason]);
    assert.equal(Object.hasOwn(checked.report.reasons[0], 'location'), false);
    const original = sdk.getCheckInput(checked, 'program');
    assert.deepEqual(original.value, input);
    assert.equal(sdk.resolveCheckLocation(checked, checked.report.reasons[0].location), undefined);
    sdk.explainCheckReason(checked.report.reasons[0]);
    assert.deepEqual(sdk.getCheckFixes(checked), []);
    assert.equal(sdk.getSubmissionCheckObservation({...rejection}), undefined);
    assert.equal(sdk.getCheckInput(structuredClone(checked), 'program'), undefined);
    f.assertCheckOnly(1);
    const retained = await f.client.lookupSubmission(outcome.submissionRef);
    assert.deepEqual(retained, outcome);
    assert.equal(Object.hasOwn(retained, 'checkObservation'), false);
    assert.equal(sdk.getSubmissionCheckObservation(retained), undefined);
    assert.deepEqual(sdk.getSubmissionOutcome(rejection), outcome);
    f.assertCheckOnly(1);
  });

  test(`${entrance}: complete registration namespace discloses only the original unregistered selector`, {timeout: 20000}, async t => {
    const f = await fixture(t, entrance);
    const input = program(), result = await f.client.check(input, options);
    assert.equal(result.outcome, 'completed');
    assert.equal(result.report.verdict, 'invalid', '[check-mutation:selector-public-verdict]');
    assert.equal(validCheckOutcome(result), true);
    assert.deepEqual(result.report.reasons, [absentReason(result, input.stages[0].inputs.rows)],
      '[check-mutation:selector-public-reason]');
    assert.deepEqual(result.report.coverage, {limits: [], unresolved: []});
    const reason = result.report.reasons[0], original = sdk.getCheckInput(result, 'program');
    assert.deepEqual(original.value, input);
    const location = sdk.resolveCheckLocation(result, reason.location);
    assert.equal(location.input, original);
    assert.equal(location.pointer, '/stages/0/inputs/rows/view');
    assert.equal(sdk.explainCheckReason(reason).summary,
      'The submitted Source selector has no matching installed registration in the inspected namespace.');
    assert.match(sdk.explainCheckReason(reason).hint, /does not prove that a Provider Resource is absent or authorize execution/u);
    assert.deepEqual(sdk.getCheckFixes(result), []);
    assert.equal(sdk.getCheckInput(structuredClone(result), 'program'), undefined);
    assert.equal(sdk.resolveCheckLocation(structuredClone(result), reason.location), undefined);
    input.stages[0].inputs.rows.connector = 'changed';
    assert.equal(original.value.stages[0].inputs.rows.connector, 'missing');
    const corrected = await f.client.check({version: 'actql/0.1', id: 'corrected', stages: [{id: 'main', inputs: {},
      steps: [{values: {schema: {n: {type: 'number', nullable: false}}, rows: [{n: 1}]}, as: 'rows'}], results: {out: {from: 'rows', fields: ['n']}}}],
      results: {out: {from: {stage: 'main', result: 'out'}}}}, options);
    assert.equal(corrected.report.verdict, 'verified');
    assert.notEqual(corrected.report.context_ref, result.report.context_ref);
    assert.equal(sdk.resolveCheckLocation(corrected, reason.location), undefined);
    f.assertCheckOnly();
  });

  test(`${entrance}: hidden registered selector remains protected beside independently absent registration`, async t => {
    const f = await fixture(t, entrance, {registered: true});
    const present = await f.client.check(program({connector: 'fixture', resource: 'r', view: 'records'}), options);
    assert.equal(present.report.verdict, 'undetermined');
    assert.deepEqual(present.report.reasons, [], '[check-mutation:selector-hidden-registration]');
    assert.deepEqual(present.report.coverage, {limits: [], unresolved: protectedSource});
    const input = program(); input.stages[0].inputs.private = {connector: 'fixture', resource: 'r', view: 'records'};
    const result = await f.client.check(input, options);
    assert.equal(result.report.verdict, 'invalid');
    assert.deepEqual(result.report.reasons, [absentReason(result, input.stages[0].inputs.rows)]);
    assert.deepEqual(result.report.coverage, {limits: [], unresolved: protectedSource});
    assert.equal(JSON.stringify(result).includes('fixture'), false);
    f.assertCheckOnly();
  });

  test(`${entrance}: original Unicode pointer omission and NULL keep their distinct meanings`, async t => {
    const f = await fixture(t, entrance), key = 'e\u0301/~🧭';
    const absent = {connector: 'missing', resource: 'r'};
    const result = await f.client.check(program(absent, key), options);
    assert.deepEqual(result.report.reasons, [absentReason(result, absent, '/stages/0/inputs/e\u0301~1~0🧭')],
      '[check-mutation:selector-public-pointer]');
    const nullInput = program({...absent, view: null}, key);
    const invalid = await f.client.check(nullInput, options);
    assert.equal(invalid.report.verdict, 'invalid', '[check-mutation:selector-null-owner-classification]');
    assert.equal(invalid.report.reasons.some(reason => reason.code === 'source_selector_unregistered'), false);
    assert.deepEqual(invalid.report.reasons, [{code: 'program_structure_invalid', facts: {issue: 'wrong_type'},
      location: {kind: 'structured', document_id: 'program', revision: sdk.getCheckInput(invalid, 'program').revision,
        pointer: '/stages/0/inputs/e\u0301~1~0🧭/view'}}]);
    assert.deepEqual(sdk.getCheckInput(invalid, 'program').value, nullInput);
    f.assertCheckOnly();
  });

  test(`${entrance}: missing values and wrong values survive safe registration absence`, async t => {
    const f = await fixture(t, entrance), input = program();
    input.params = {early: {type: 'number'}, wrong: {type: 'number'}};
    const result = await f.client.check(input, {...options, parameters: {wrong: 'private-value'}});
    assert.equal(result.report.verdict, 'invalid');
    assert.deepEqual(result.report.reasons.map(reason => reason.code),
      ['source_selector_unregistered', 'supplied_value_type_mismatch']);
    assert.deepEqual(result.report.requirements.map(reason => reason.facts.parameter), ['early']);
    assert.equal(JSON.stringify(result).includes('private-value'), false);
    assert.deepEqual(result.report.coverage, {limits: [{code: 'bound_values_missing'}], unresolved: []});
    for (const reason of [...result.report.reasons, ...result.report.requirements]) {
      assert.ok(sdk.resolveCheckLocation(result, reason.location));
    }
    f.assertCheckOnly();
  });

  test(`${entrance}: incomplete or undisclosed registration cannot become absence`, async t => {
    for (const configuration of [{grant: 'deny'}, {grantNamespace: 'other'}, {omitNamespace: true},
      {registered: true, unstable: true}]) {
      const f = await fixture(t, entrance, configuration), input = program();
      const result = await f.client.check(input, options);
      assert.equal(result.report.verdict, 'undetermined');
      assert.deepEqual(result.report.reasons, [], '[check-mutation:selector-public-disclosure]');
      assert.deepEqual(result.report.coverage, {limits: [], unresolved: protectedSource});
      f.assertCheckOnly();
    }
  });

  test(`${entrance}: selector resolution budget cannot verify or prove named absence`, async t => {
    const f = await fixture(t, entrance), input = program({connector: 'x', resource: 'r'}, 'i0');
    input.stages[0].inputs = Object.fromEntries(Array.from({length: 1025}, (_, index) =>
      [`i${index}`, {connector: 'x', resource: 'r'}]));
    const result = await f.client.check(input, options);
    assert.equal(result.report.verdict, 'undetermined');
    assert.deepEqual(result.report.reasons, []);
    assert.deepEqual(result.report.coverage, {limits: [{code: 'analysis_budget_exhausted'}], unresolved: []});
    assert.deepEqual(result.report.scope, {kind: 'bound_input'});
    assert.deepEqual(sdk.getCheckInput(result, 'program').value, input);
    f.assertCheckOnly();
  });

  test(`${entrance}: current authority is rechecked without transferring older disclosure`, async t => {
    const root = await mkdtemp(new URL('authority-', scratch).pathname);
    t.after(() => rm(root, {recursive: true, force: true}));
    const accountFile = join(root, 'account.json'); await writeFile(accountFile, account());
    const f = await fixture(t, entrance, {accountFile}), input = program();
    const original = await f.client.check(input, options);
    assert.equal(original.report.verdict, 'invalid');
    await writeFile(accountFile, account('deny'));
    const denied = await f.client.check(input, options);
    assert.equal(denied.report.verdict, 'undetermined');
    assert.deepEqual(denied.report.reasons, []);
    assert.deepEqual(denied.report.coverage, {limits: [], unresolved: protectedSource});
    assert.notEqual(original.report.context_ref, denied.report.context_ref);
    assert.equal(sdk.getCheckInput(structuredClone(original), 'program'), undefined);
    assert.equal(sdk.getCheckFixes(structuredClone(original)), undefined);
    const changed = await f.client.check(program({connector: 'other', resource: 'r', view: 'records'}), options);
    assert.equal(sdk.resolveCheckLocation(changed, original.report.reasons[0].location), undefined);
    assert.ok(sdk.resolveCheckLocation(original, original.report.reasons[0].location));
    f.assertCheckOnly();
  });
}
