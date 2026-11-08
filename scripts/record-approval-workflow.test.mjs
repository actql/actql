// Fixture contract tests only. These doubles prove oracle/phase ordering and
// failure preservation, not provider authentication or ordinary Run acceptance.
import assert from 'node:assert/strict';
import test from 'node:test';
import {copyFile, mkdir, mkdtemp, readFile, rm, stat, writeFile} from 'node:fs/promises';
import {generateKeyPairSync, verify} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {salesforceUpdateCase, hubspotUpdateCase, kintoneUpdateCase} from './fixtures/record-approval/cases.mjs';
import {runRecordUpdateApprovalPhase} from './fixtures/record-approval/workflow.mjs';
import {runRecordApprovalCommand} from './fixtures/record-approval/command.mjs';
import {hubspotApprovalProvider} from './fixtures/hubspot-approval/provider.mjs';
import {mockProjectFiles as salesforceMock} from './fixtures/salesforce-approval/mock-project.mjs';
import {mockProjectFiles as hubspotMock} from './fixtures/hubspot-approval/mock-project.mjs';
import {runSalesforceApprovalPhase} from './fixtures/salesforce-approval/workflow.mjs';
import {runHubSpotApprovalPhase} from './fixtures/hubspot-approval/workflow.mjs';
import {mockProjectFiles as kintoneMock} from './fixtures/kintone-approval/mock-project.mjs';
import {runKintoneApprovalPhase} from './fixtures/kintone-approval/workflow.mjs';

const cid = mark => 'sha256:' + mark.repeat(64);
const selection = {recordId: 'record-1', previousName: 'before', nextName: 'after'};
async function definition(connector) {
  const files = await Promise.all(['update.aql', 'read.aql'].map(name =>
    readFile(new URL(`./fixtures/${connector}-approval/${name}`, import.meta.url), 'utf8')));
  return ({salesforce: salesforceUpdateCase, hubspot: hubspotUpdateCase, kintone: kintoneUpdateCase}[connector])(
    {update: files[0], read: files[1]}, selection);
}
function publicDouble(value) {
  const events = [], saved = new Map(), ref = {authorityScopeCid: cid('a'), original: 'effect'};
  const summary = {reviewProjectionCid: cid('b'), requiredArtifact: {cid: cid('c')},
    requirements: [{original: 'claim'}], checkpointCid: cid('d')};
  const checkpoint = {id: 'checkpoint', checkpoint_cid: cid('d')};
  const body = {version: 'actql-review-projection/0.1',
    review_projection_cid: cid('b'), effect_preview_cid: cid('c'), authority_scope_cid: cid('a'),
    approval_claims: [{original: 'claim'}], displayed_scope: {
      effects: [{kind: 'update', target: value.review.target, count: 1}]},
    displayed_rows: [{target_row_identity: value.review.identity, preview_strength: 'full_diff',
      row_preview_cid: cid('e'), target_guard: {state: 'version', version_cid: cid('f')},
      before: {state: 'present', value: {...value.review.before, independent_extra_field: 'retained'}},
      intended_changes: {state: 'present', value: {...value.review.changes}},
      after: {state: 'present', value: {...value.review.changes}}}]};
  let approved = false, number = 0;
  const effect = {ref, async wait() {
    events.push('effect:wait');return approved ? {status: 'succeeded', run_id: 'same-run'}
      : {status: 'waiting_checkpoint', run_id: 'same-run', checkpoint};
  }, async status() {
    events.push('effect:status');return approved ? {status: 'succeeded', run_id: 'same-run'}
      : {status: 'waiting_checkpoint', run_id: 'same-run', checkpoint};
  }, result(name) {assert.equal(name, value.effect.resultName);events.push('effect:result');
    return {async all() {events.push('effect:rows');return structuredClone(value.effect.expectedRows);}};}};
  const client = {async startSource(document, options) {
    if (document === value.effect.document) {
      events.push('submit:effect');assert.equal(options.stopBefore, 'commit');
      assert.deepEqual(options.parameters, value.effect.parameters);return effect;
    }
    assert.equal(document, value.read.document);events.push('submit:read');number++;
    assert.deepEqual(options.parameters, value.read.parameters);
    return {ref: {original: 'read-' + number}, async wait() {events.push('read:wait');return {status: 'succeeded'};},
      result(name) {assert.equal(name, value.read.resultName);return {async all() {
        events.push('read:rows');return structuredClone(approved ? value.read.afterRows : value.read.beforeRows);
      }};}};
  }, async checkpoints(actual) {assert.deepEqual(actual, {checkpointId: 'checkpoint'});return {items: [summary]};},
  async reviewCheckpoint(actual) {assert.deepEqual(actual, summary);events.push('review');return {bytes: Buffer.from(JSON.stringify(body))};},
  async attach(actual) {assert.deepEqual(actual, ref);events.push('attach');return effect;},
  async close() {events.push('close');}};
  return {client, events, saved, body, effect,
    async load(name) {events.push('load:' + name);assert(saved.has(name));return structuredClone(saved.get(name));},
    async save(name, data) {events.push('save:' + name);assert(!saved.has(name));saved.set(name, structuredClone(data));},
    async approve(actual, captured) {assert.strictEqual(actual, client);assert.deepEqual(captured.ref, ref);
      events.push('approve');approved = true;return {results: [{status: 'committed'}]};}};
}
async function phase(which, value, f, changes = {}) {
  return runRecordUpdateApprovalPhase({phase: which, definition: value, ...f, ...changes});
}

for (const connector of ['salesforce', 'hubspot', 'kintone']) {
  test(`shared ${connector} fixture preserves original reference, explicit approval and Saved-first order`, async () => {
    const value = await definition(connector), f = publicDouble(value);
    await phase('capture', value, f);
    assert(f.events.indexOf('save:submitted') < f.events.indexOf('effect:wait'));
    assert(!f.events.includes('approve'));
    await phase('approve', value, f);
    const split = f.events.length;await phase('recover', value, f);
    const recovered = f.events.slice(split);
    assert(recovered.indexOf('effect:rows') < recovered.indexOf('effect:status'));
    assert(!recovered.some(x => x.startsWith('submit:') || x === 'approve'));
    assert.deepEqual(f.saved.get('submitted').ref, f.saved.get('recovered').ref);
    assert.equal(f.events.filter(x => x === 'close').length, 3);
    assert.equal(f.events.filter(x => x === 'approve').length, 1);
  });
  test(`shared ${connector} fixture rejects a changed sealed Review before operator approval`, async () => {
    const value = await definition(connector), f = publicDouble(value);
    await phase('capture', value, f);
    f.body.displayed_rows[0].intended_changes.value = {changed: 'unapproved'};
    const split = f.events.length;
    await assert.rejects(phase('approve', value, f));
    assert(!f.events.slice(split).includes('approve'));
    assert.equal(f.events.at(-1), 'close');
  });
  test(`shared ${connector} fixture refuses an uncommitted approval before wait or Result`, async () => {
    const value = await definition(connector), f = publicDouble(value);
    await phase('capture', value, f);const split = f.events.length;
    await assert.rejects(phase('approve', value, f, {approve: async () => ({results: [{status: 'refused'}]})}));
    assert(!f.events.slice(split).some(x => ['effect:wait', 'effect:result', 'submit:read'].includes(x)));
    assert.equal(f.events.at(-1), 'close');
  });
  test(`shared ${connector} fixture cannot retarget a saved reference to another Program`, async () => {
    const value = await definition(connector), f = publicDouble(value);
    await phase('capture', value, f);await phase('approve', value, f);
    const changed = structuredClone(value);changed.effect.document += '\n-- changed';
    const split = f.events.length;await assert.rejects(phase('recover', changed, f));
    assert(!f.events.slice(split).includes('attach'));
    assert.equal(f.events.at(-1), 'close');
  });
}

for (const primary of [undefined, null, false, 0, '']) {
  test(`shared fixture preserves original falsy rejection ${String(primary)} through cleanup`, async () => {
    const value = await definition('salesforce');let closed = 0, rejected = false;
    try {await runRecordUpdateApprovalPhase({phase: 'capture', definition: value,
      client: {async startSource() {throw primary;}, async close() {closed++;}}});}
    catch (error) {rejected = true;assert.strictEqual(error, primary);}
    assert(rejected);assert.equal(closed, 1);
  });
}
test('shared fixture keeps original and cleanup failures separately even for undefined primary', async () => {
  const cleanup = new Error('original cleanup pending'), value = await definition('hubspot');
  await assert.rejects(runRecordUpdateApprovalPhase({phase: 'capture', definition: value,
    client: {async startSource() {throw undefined;}, async close() {throw cleanup;}}}), error => {
      assert(error instanceof AggregateError);assert.deepEqual(error.errors, [undefined, cleanup]);
      assert(Object.hasOwn(error, 'cause'));assert.equal(error.cause, undefined);return true;
    });
});

for (const [connector, builder, resource, idField, valueField] of [
  ['salesforce', salesforceMock, 'Account', 'Id', 'Name'],
  ['hubspot', hubspotMock, 'companies', 'id', 'name'],
  ['kintone', kintoneMock, 'inquiries', '$id', 'Subject'],
]) test(`shared ${connector} mock supplies explicit unchanged Program aliases and required approval`, () => {
  const files = builder(selection), catalog = JSON.parse(files['mock/catalog.json']).connections[connector];
  assert.equal(catalog.writes[0].approval, 'required');
  assert.deepEqual(catalog.writes[0].writable_fields, [valueField]);
  assert.equal(catalog.writes[0].primary_identity, idField);
  const rows = JSON.parse(files['mock/data.json'])[connector][resource].rows;
  assert.deepEqual(rows[0], {[idField]: selection.recordId, [valueField]: 'before'});
  assert.equal(rows.length, 2);assert.notEqual(rows[1][idField], selection.recordId);
});

for (const [connector, runPhase] of [
  ['salesforce', runSalesforceApprovalPhase], ['hubspot', runHubSpotApprovalPhase],
  ['kintone', runKintoneApprovalPhase],
]) {
  for (const [name, invalid] of [
    ['missing record', {...selection, recordId: undefined}],
    ['unchanged values', {...selection, nextName: selection.previousName}],
  ]) test(`shared ${connector} case ${name} closes its connected Client without submission`, async () => {
    const value = await definition(connector), f = publicDouble(value);
    await assert.rejects(runPhase({phase: 'capture', ...f, selection: invalid,
      programs: {update: value.effect.document, read: value.read.document}}), TypeError);
    assert.deepEqual(f.events, ['close']);
    assert.equal(f.saved.size, 0);
  });

  test(`shared ${connector} invalid case retains primary and cleanup failure separately`, async () => {
    const cleanup = new Error('Original close pending');
    let closes = 0;
    await assert.rejects(runPhase({phase: 'capture', selection: {}, programs: {},
      client: {async close() {closes++; throw cleanup;}}}), error => {
      assert(error instanceof AggregateError);
      assert(error.errors[0] instanceof TypeError);
      assert.strictEqual(error.cause, error.errors[0]);
      assert.strictEqual(error.errors[1], cleanup);
      return true;
    });
    assert.equal(closes, 1);
  });

  for (const phase of ['capture', 'recover']) {
    test(`shared ${connector} ${phase} entry does not load its configured absent approval key`, async t => {
      // Exercise the exact public-consumer entry in a fresh process. Only its
      // Client and phase implementation are explicit doubles: no Host, state,
      // provider, signature, approval or ordinary acceptance is claimed here.
      const root = await mkdtemp(join(tmpdir(), 'actql-approval-entry-'));
      t.after(() => rm(root, {recursive: true, force: true}));
      await writeFile(join(root, 'package.json'), '{"private":true,"type":"module"}\n');
      const dependency = join(root, 'node_modules/@actql/node');
      await mkdir(dependency, {recursive: true});
      await writeFile(join(dependency, 'package.json'),
        '{"name":"@actql/node","type":"module","exports":"./index.mjs"}\n');
      await writeFile(join(dependency, 'index.mjs'),
        "import {writeFile} from 'node:fs/promises';" +
        "export async function connect(){return {async close(){" +
        "await writeFile(process.env.ACTQL_FIXTURE_CLOSE_MARKER,'closed',{flag:'wx'});}};}\n");
      const folder = new URL(`./fixtures/${connector}-approval/`, import.meta.url);
      const entry = join(root, connector + '-approval');
      const shared = join(root, 'record-approval');
      await mkdir(entry);
      await mkdir(shared);
      for (const name of ['command.mjs', 'cases.mjs']) {
        await copyFile(new URL('./fixtures/record-approval/' + name, import.meta.url), join(shared, name));
      }
      for (const name of ['run.mjs', 'update.aql', 'read.aql']) {
        await copyFile(new URL(name, folder), join(entry, name));
      }
      const exportName = {salesforce: 'runSalesforceApprovalPhase', hubspot: 'runHubSpotApprovalPhase',
        kintone: 'runKintoneApprovalPhase'}[connector];
      await writeFile(join(entry, 'workflow.mjs'),
        "import assert from 'node:assert/strict';" +
        `export async function ${exportName}({phase,client,approve}){` +
        `assert.equal(phase,${JSON.stringify(phase)});assert.equal(typeof approve,'function');` +
        "await client.close();}\n");
      await writeFile(join(root, 'consumer.json'), JSON.stringify({selection,
        connect: {mode: 'local'}, signer: {keyId: 'operator', reviewerId: 'reviewer',
          privateKeyPath: join(root, 'absent-approval.key')}}));
      const marker = join(root, 'close-returned');
      const child = spawnSync(process.execPath, [join(entry, 'run.mjs'), phase,
        join(root, 'consumer.json'), join(root, 'receipt')], {cwd: root,
        env: {...process.env, NODE_OPTIONS: '', NODE_PATH: '', ACTQL_FIXTURE_CLOSE_MARKER: marker},
        encoding: 'utf8', timeout: 10000, maxBuffer: 64 * 1024});
      assert.equal(child.error, undefined);
      assert.equal(child.status, 0, child.stderr);
      assert.equal(child.signal, null);
      assert.equal(await readFile(marker, 'utf8'), 'closed');
      assert.deepEqual(JSON.parse(child.stdout), {phase, status: 'passed', publicClientClose: 'returned'});
    });
  }
}

test('shared case construction preserves an undefined primary through failing close', async () => {
  const cleanup = new Error('Original close still pending');
  await assert.rejects(runRecordUpdateApprovalPhase({phase: 'capture',
    createDefinition() {throw undefined;}, client: {async close() {throw cleanup;}}}), error => {
    assert(error instanceof AggregateError);
    assert.deepEqual(error.errors, [undefined, cleanup]);
    assert(Object.hasOwn(error, 'cause'));
    assert.equal(error.cause, undefined);
    return true;
  });
});

test('kintone fixture retains a system record id above the exact Number range', async () => {
  const selected = {...selection, recordId: '9007199254740993'};
  const programs = Object.fromEntries(await Promise.all(['update', 'read'].map(async name =>
    [name, await readFile(new URL(`./fixtures/kintone-approval/${name}.aql`, import.meta.url), 'utf8')])));
  const value = kintoneUpdateCase(programs, selected);
  assert.equal(value.effect.parameters.record_id, '9007199254740993');
  assert.equal(value.effect.expectedRows[0].id, '9007199254740993');
  assert.equal(value.review.identity, '9007199254740993');
  const files = kintoneMock(selected);
  assert.equal(JSON.parse(files['mock/data.json']).kintone.inquiries.rows[0].$id, '9007199254740993');
});

async function commandFixture(t, connector, configuration = {selection, connect: {mode: 'local'}}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-approval-command-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const path = join(root, 'consumer.json');
  await writeFile(path, JSON.stringify(configuration), {mode: 0o600});
  const log = [], events = [];
  return {root, path, log, events,
    options: {argv: ['check', path, join(root, 'receipt')],
      programDirectory: new URL(`./fixtures/${connector}-approval/`, import.meta.url),
      createDefinition: {salesforce: salesforceUpdateCase, hubspot: hubspotUpdateCase,
        kintone: kintoneUpdateCase}[connector],
      connect: async () => {events.push('connect'); throw new Error('Unexpected connection');},
      runPhase: async () => {throw new Error('Unexpected workflow');}, log: value => log.push(value)}};
}

for (const connector of ['salesforce', 'hubspot', 'kintone']) {
  test(`shared ${connector} check validates its original case without connection or key IO`, async t => {
    const f = await commandFixture(t, connector, {selection, connect: {mode: 'local'},
      signer: {keyId: 'operator', reviewerId: 'reviewer', privateKeyPath: 'absent.key'}});
    await runRecordApprovalCommand(f.options);
    assert.deepEqual(f.events, []);
    assert.deepEqual(f.log, [{phase: 'check', status: 'ready', connected: false}]);
    await assert.rejects(readFile(join(f.root, 'receipt.submitted.json')), {code: 'ENOENT'});
  });

  test(`shared ${connector} command rejects an invalid original selection before connecting`, async t => {
    const f = await commandFixture(t, connector, {selection: {...selection, recordId: undefined},
      connect: {mode: 'local'}});
    f.options.argv[0] = 'capture';
    await assert.rejects(runRecordApprovalCommand(f.options), /InvalidRecordApprovalSelection/u);
    assert.deepEqual(f.events, []);
    assert.deepEqual(f.log, []);
  });
}

test('shared command validates signer configuration without reading its key or connecting', async t => {
  const f = await commandFixture(t, 'kintone', {selection, connect: {mode: 'local'},
    signer: {keyId: 'operator', privateKeyPath: 'absent.key'}});
  await assert.rejects(runRecordApprovalCommand(f.options), /InvalidRecordApprovalSigner/u);
  assert.deepEqual(f.events, []);
  assert.deepEqual(f.log, []);
});

test('shared command malformed JSON error does not repeat configuration contents', async t => {
  const f = await commandFixture(t, 'kintone');
  const privateText = 'do-not-repeat-this-configuration-value';
  await writeFile(f.path, '{"private":"' + privateText + '",');
  await assert.rejects(runRecordApprovalCommand(f.options), error => {
    assert.equal(error.message, 'InvalidRecordApprovalConfiguration');
    assert.equal(String(error.stack).includes(privateText), false);
    assert.equal(error.cause, undefined);
    return true;
  });
  assert.deepEqual(f.events, []);
});

test('shared command signs only explicit approval with a configuration-relative operator key', async t => {
  const f = await commandFixture(t, 'kintone', {selection, connect: {mode: 'local'},
    signer: {keyId: 'operator', reviewerId: 'reviewer', privateKeyPath: 'keys/operator.pem'}});
  const {privateKey, publicKey} = generateKeyPairSync('ed25519');
  await mkdir(join(f.root, 'keys'));
  await writeFile(join(f.root, 'keys/operator.pem'),
    privateKey.export({format: 'pem', type: 'pkcs8'}), {mode: 0o600});
  const captured = {summary: {original: 'sealed-checkpoint'}, ref: {authorityScopeCid: cid('a')}};
  const bytes = Buffer.from('original-public-resolution-preimage');
  let called = false;
  const client = {resolveCheckpoints: async (decisions, {signer}) => {
    called = true;
    assert.deepEqual(decisions, [{checkpoint: captured.summary, decision: 'approved'}]);
    assert.equal(signer.keyId, 'operator');
    assert.equal(signer.reviewerId, 'reviewer');
    assert.equal(signer.authorityScopeCid, captured.ref.authorityScopeCid);
    assert(verify(null, bytes, publicKey, signer.sign(bytes)));
    return {results: [{status: 'committed'}]};
  }};
  f.options.argv[0] = 'approve';
  f.options.connect = async () => client;
  f.options.runPhase = async ({approve, client: selected, phase}) => {
    assert.equal(phase, 'approve');
    assert.strictEqual(selected, client);
    assert.equal(called, false);
    await approve(selected, captured);
  };
  await runRecordApprovalCommand(f.options);
  assert.equal(called, true);
  assert.deepEqual(f.log, [{phase: 'approve', status: 'passed', publicClientClose: 'returned'}]);
});

test('shared command keeps receipt creation exclusive and private with the original prefix', async t => {
  const f = await commandFixture(t, 'kintone');
  f.options.argv[0] = 'capture';
  f.options.connect = async () => ({});
  f.options.runPhase = async ({save, load}) => {
    const original = {ref: {original: 'first-run'}};
    await save('submitted', original);
    assert.deepEqual(await load('submitted'), original);
    await assert.rejects(save('submitted', {ref: {original: 'replacement'}}), {code: 'EEXIST'});
    assert.deepEqual(await load('submitted'), original);
  };
  await runRecordApprovalCommand(f.options);
  assert.equal((await stat(join(f.root, 'receipt.submitted.json'))).mode & 0o777, 0o600);
});

test('shared command never prints success when its original workflow fails', async t => {
  const f = await commandFixture(t, 'kintone');
  const primary = new Error('Original workflow failed');
  f.options.argv[0] = 'capture';
  f.options.connect = async () => ({});
  f.options.runPhase = async () => {throw primary;};
  await assert.rejects(runRecordApprovalCommand(f.options), error => error === primary);
  assert.deepEqual(f.log, []);
});

test('shared command check does not import a configured operator module', async t => {
  const f = await commandFixture(t, 'kintone', {selection, connect: {mode: 'local'},
    operatorModulePath: 'not-yet-configured-operator.mjs'});
  await runRecordApprovalCommand(f.options);
  assert.deepEqual(f.events, []);
  assert.deepEqual(f.log, [{phase: 'check', status: 'ready', connected: false}]);
});

test('shared command forwards an explicit operator callback through the existing connection entrance', async t => {
  const f = await commandFixture(t, 'kintone', {selection, connect: {mode: 'local',
    installation: {directory: '/original/project/.actql'}}, operatorModulePath: 'operator.mjs'});
  await writeFile(join(f.root, 'operator.mjs'),
    `export function configureConnection(options) {
      return {...options, installation: {...options.installation,
        authorization: {original: () => 'original-operator-port'}}};
    }\n`);
  f.options.argv[0] = 'capture';
  f.options.connect = async options => {
    assert.equal(options.mode, 'local');
    assert.equal(options.installation.directory, '/original/project/.actql');
    assert.equal(options.installation.authorization.original(), 'original-operator-port');
    f.events.push('connect');
    return {};
  };
  f.options.runPhase = async () => f.events.push('workflow');
  await runRecordApprovalCommand(f.options);
  assert.deepEqual(f.events, ['connect', 'workflow']);
});

test('shared command rejects an incompatible operator module before connection', async t => {
  const f = await commandFixture(t, 'kintone', {selection, connect: {mode: 'local'},
    operatorModulePath: 'operator.mjs'});
  await writeFile(join(f.root, 'operator.mjs'), 'export const authorization = {};\n');
  f.options.argv[0] = 'capture';
  await assert.rejects(runRecordApprovalCommand(f.options), /InvalidRecordApprovalOperatorModule/u);
  assert.deepEqual(f.events, []);
  assert.deepEqual(f.log, []);
});

function hubspotProviderFixture() {
  const value = hubspotApprovalProvider({...selection, controlId: 'untouched-control'});
  const exchange = (pathname, body, authorized = true) => ({method: 'POST', pathname,
    authorized, body: JSON.stringify(body)});
  const apply = body => value.routes.find(route => route.pathname.endsWith('/batch/update'))
    .handle(exchange('/crm/v3/objects/companies/batch/update', body));
  const body = {inputs: [{id: selection.recordId, objectWriteTraceId: cid('a'),
    properties: {name: selection.nextName, actql_request_id: cid('b')}}]};
  return {value, exchange, apply, body};
}

test('HubSpot approval provider retains independent original records and accepts one exact marked update', () => {
  const f = hubspotProviderFixture(), before = f.value.snapshot();
  assert.equal(before.target.name, selection.previousName);
  assert.equal(before.writes, 0);
  const response = f.apply(f.body);
  assert.equal(response.body.status, 'COMPLETE');
  assert.equal(response.body.results[0].id, selection.recordId);
  const after = f.value.snapshot();
  assert.equal(after.writes, 1);
  assert.equal(after.target.name, selection.nextName);
  assert.equal(after.target.marker, cid('b'));
  assert.deepEqual(after.control, before.control);
  assert.throws(() => f.apply(f.body));
  assert.equal(f.value.snapshot().writes, 1);
});

test('HubSpot approval provider refuses wrong targets, values and markers without writing', () => {
  for (const mutate of [body => {body.inputs[0].id = 'other';},
    body => {body.inputs[0].properties.name = 'other';},
    body => {delete body.inputs[0].properties.actql_request_id;},
    body => {body.inputs[0].properties.actql_request_id = 'not-a-cid';},
    body => {body.inputs[0].extra = 'unapproved';}]) {
    const f = hubspotProviderFixture();
    mutate(f.body);
    assert.throws(() => f.apply(f.body));
    assert.equal(f.value.snapshot().writes, 0);
    assert.equal(f.value.snapshot().target.name, selection.previousName);
  }
});

test('HubSpot approval provider requires a credential-bearing request before target observation', () => {
  const f = hubspotProviderFixture();
  const path = '/crm/v3/objects/companies/batch/read';
  const read = f.value.routes.find(route => route.pathname === path);
  assert.throws(() => read.handle(f.exchange(path, {inputs: [{id: selection.recordId}], properties: ['name']}, false)));
  assert.equal(f.value.snapshot().writes, 0);
  assert.equal(f.value.snapshot().requests.length, 0);
  const response = read.handle(f.exchange(path, {inputs: [{id: selection.recordId}], properties: ['name']}));
  assert.equal(response.body.results[0].properties.name, selection.previousName);
});
