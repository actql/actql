// Typed JSON values through the real installed row Effect, checked Program,
// Preview, durable Ledger and restart. Only the provider transport and its
// credential Site are test doubles; neither performs network I/O. A neutral
// Mapping is intentional: Salesforce fields and the row-source declaration
// generator do not currently support JSON write fields.
// Source identities bind raw Effect literal keys before target typing.
// Checked Object fields still normalize identifiers; checked JSON payloads
// retain exact data keys. The fixture uses the existing inline literal form.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {inspect} from 'node:util';
import {withFixtureConnector} from
  '../host-common/connector-manifest.fixture.mjs';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {effectHost} from './fixtures/installed-row-effect.fixture.mjs';
import {createInstalledRowEffect} from './installed-row-effect.mjs';
import {createLocalAuthorizationGate} from './local-account-config.mjs';
import {currentEffectLiteralKeyVectors} from '../../scripts/effect-literal-key-vectors.mjs';

const target = 'connector://fixture/records';
const connection = 'fixture:records';
const mappingRef = 'mapping:fixture.records.json.v1';
const recordId = 'record-1';
const transportLimit = 16_384;
const stoppedCode = 'FixtureStoppedBeforeJsonProjection';

// Independent expected-byte encoder: fixtures already contain valid finite
// JSON values. In particular this does not call the SDK encoder under test.
const dataJson = value => {
  if (Array.isArray(value)) return `[${value.map(dataJson).join(',')}]`;
  if (value !== null && typeof value === 'object') {
    return `{${Object.keys(value).sort().map(key =>
      `${JSON.stringify(key)}:${dataJson(value[key])}`).join(',')}}`;
  }
  const wire = JSON.stringify(value);
  assert.notEqual(wire, undefined, 'fixture values must be JSON');
  return wire;
};
const cid = value => `sha256:${createHash('sha256')
  .update(dataJson(value), 'utf8').digest('hex')}`;
const withoutSelf = (value, key) => {
  const body = {...value};
  delete body[key];
  return cid(body);
};
const diagnostic = error => inspect(error, {depth: 8});

function programFor(payload) {
  return {version: 'actql/0.1', id: 'installed-json-update', stages: [{
    id: 'source', inputs: {}, steps: [
      {values: {schema: {id: {type: 'string', nullable: false}},
        rows: [{id: recordId}]}, as: 'selected'},
    ], results: {rows: {from: 'selected', fields: ['id']}},
    effects: {save: {update: {target, mapping: mappingRef,
      from: {result: 'rows'}, id: 'id', set: {payload: {literal: payload}}}}},
  }], results: {answer: {from: {stage: 'source', result: 'rows'}}}};
}

async function mappingEnvironment(payloadContract = {nullable: false, type: 'json'}, kind = 'update') {
  const environment = JSON.parse(await readFile(new URL(
    '../../spec/local-check-environment.json', import.meta.url), 'utf8'));
  const schema = {additional_properties: false, fields: {
    Id: {nullable: false, type: 'string'},
    payload: payloadContract,
  }, nullable: false, type: 'object'};
  const mapping = {
    connector_manifest_cid: withFixtureConnector(environment, target),
    conversions: [], mapping_contract_cid: '', mapping_ref: mappingRef,
    minimum_approval: 'none',
    permission_rules: [{effect_kind: kind, permissions: [`scope:${kind}`],
      selector_class: kind === 'create' ? 'none' : 'id', write_fields: ['payload']}],
    primary_identity: 'Id', required_fields: [],
    required_permissions: [],
    resource_identity_cid: cid({resource: target}),
    row_mapping: kind === 'create' ? {payload: {field: 'payload', null_behavior: 'reject'}} : {},
    schema: 'actql.mapping_contract/0.1', target_ref: target,
    target_schema: schema, target_schema_identity: cid(schema),
    version: 'fixture', writable_fields: ['payload'],
  };
  mapping.mapping_contract_cid = withoutSelf(mapping, 'mapping_contract_cid');
  environment.mapping_contracts = [mapping];
  environment.evidence_bundle_cid = withoutSelf(environment,
    'evidence_bundle_cid');
  const environmentWire = dataJson(environment);
  assert.ok(moon.clientProgramCheckEnvironment(environmentWire,
    environment.evidence_bundle_cid,
    false, false, true, false, false, false, false),
  'the neutral JSON Mapping must pass the actual Check Environment');
  return {environmentWire, mapping};
}

async function installationFor(t, {changeRequestValue, payloadContract, beforePayload,
  stopBeforeProjection = false, responsePayload = {ok: true},
  requestChildMode, targetReadOutcome = 'allow', kind = 'update'} = {}) {
  const {environmentWire, mapping} = await mappingEnvironment(payloadContract, kind);
  const root = await mkdtemp(join(tmpdir(), 'actql-installed-row-json-'));
  const closers = [];
  const effects = [];
  const preparedValues = [];
  const sends = [];
  const projections = [];
  const requestChildren = [];
  const preparedBefore = new WeakMap();
  let writeGrants = 0;
  let readGrants = 0;
  let before = {payload: beforePayload ?? {$json: {previous: true}}};
  let stopPending = stopBeforeProjection;
  const description = {version: 'fixture-json-update/0.1', resource: 'records',
    writable_fields: ['payload']};
  const observationCid = cid(description);
  const requestCid = request => cid({operation: kind, target,
    ...(kind === 'create' ? {} : {selector: request.target}), value: request.value,
    ...(request.beforeVersionCid === undefined ? {} : {before_version_cid: request.beforeVersionCid})});
  const requestFor = (value, selector, beforeVersionCid) => {
    assert.equal(selector, kind === 'create' ? undefined : recordId);
    preparedValues.push(structuredClone(value));
    const requestValue = changeRequestValue === undefined
      ? structuredClone(value) : changeRequestValue(value);
    const wire = dataJson(requestValue);
    assert.ok(Buffer.byteLength(wire, 'utf8') <= transportLimit,
      'fixture request exceeds the explicit provider byte limit');
    return Object.freeze({value: requestValue, target: selector, wire,
      ...(beforeVersionCid === undefined ? {} : {beforeVersionCid})});
  };
  t.after(async () => {
    try {
      for (const close of closers.reverse()) await close();
    } finally {
      for (const effect of effects) effect.close();
      if (process.env.ACTQL_TEST_PRESERVE_SCRATCH !== '1') await rm(root, {recursive: true, force: true});
      else t.diagnostic(`Retained original row Effect fixture: ${root}`);
    }
  });
  const accountConfiguration = dataJson({
    version: 'actql-execution-account-config/0.1',
    account_id: 'installed-json-fixture', entries: [{
      entry_id: 'update-json', outcome: 'allow', exclusions: [],
      principal: {all: true}, connection: {any_of: [connection]},
      resource: {any_of: ['records']}, operation: {any_of:
        targetReadOutcome === 'allow' ? ['effect', 'read'] : ['effect']},
    }, ...(targetReadOutcome === 'allow' ? [] : [{
      entry_id: 'z-read-refusal', outcome: targetReadOutcome, exclusions: [],
      principal: {all: true}, connection: {any_of: [connection]},
      resource: {any_of: ['records']}, operation: {any_of: ['read']},
    }])],
  });
  const load = async () => {
    const authorization = await createLocalAuthorizationGate({
      accountConfiguration, principal: 'principal-a'});
    // This Site grants only the authorized fixture send. The provider double
    // below needs no secret and has no callResource/network capability.
    const site = {
      issueReadGrant({operation, decision, resource}) {
        assert.equal(operation, 'fixture:read');
        assert.equal(resource, 'records');
        assert.equal(decision.action, 'dispatch');
        assert.equal(decision.boundary, 'acquisition');
        assert.equal(decision.tuple.connection, connection);
        readGrants++;
        return Object.freeze({});
      },
      issueEffectGrant({operation, decision, resource, subjectCid}) {
        assert.equal(operation, `fixture:${kind}`);
        assert.equal(resource, 'records');
        assert.equal(decision.action, 'dispatch');
        assert.equal(decision.boundary, 'effect_commit');
        assert.equal(decision.subjectCid, subjectCid);
        assert.equal(decision.tuple.connection, connection);
        writeGrants++;
        return Object.freeze({});
      },
      close: () => authorization.close(),
    };
    try {
      const effect = await createInstalledRowEffect({moon,
        mappings: [{resource: 'records', mappingRef,
          mappingCid: mapping.mapping_contract_cid, body: dataJson(mapping)}],
        environmentWire, connectorId: 'fixture',
        connectorRegistration: 'fixture', connectorRevision: 'fixture',
        connection, site, authorization,
        runtimeBundleCid: cid({runtime: 'installed-json-fixture'}),
        bindingCid: cid({binding: 'installed-json-fixture'}),
        ledgerRoot: join(root, 'effect-ledger'),
        driver: {
          kinds: [kind], writeOperation: () => `fixture:${kind}`,
          targetRead: {operation: 'fixture:read'},
          describe: async () => description,
          prepareRequest({value, selector}) {
            const request = requestFor(value, selector);
            return {request, requestCid: requestCid(request)};
          },
          ...(requestChildMode === undefined ? {} : {prepareRequestChild(context) {
            const original = {context, pending: true, prepares: 0, releases: 0,
              allowRetire: requestChildMode !== 'pending-failure'};
            requestChildren.push(original);
            const retire = () => {
              original.releases++;
              if (!original.allowRetire) return false;
              original.pending = false;
            };
            return Object.freeze({
              async prepare() {
                original.prepares++;
                if (kind === 'create') {
                  assert.equal(context.rowIndex, undefined);
                  assert.equal(context.authorizationForRow, undefined);
                } else {
                assert.equal(context.rowIndex, 0);
                context.assertCurrent?.();
                // A substituted argument cannot choose another row's grant.
                const authorization = await context.authorizationForRow(999);
                context.assertCurrent?.();
                assert.match(authorization.useId, /-0-\d+$/u,
                  'the child cannot substitute another row index into its read use');
                }
                const observed = structuredClone(before);
                if (requestChildMode === 'failure' || requestChildMode === 'pending-failure') {
                  throw Object.assign(new Error('FixtureGuardedPrepareFailed'),
                    {code: 'FixtureGuardedPrepareFailed'});
                }
                const request = requestFor(context.value, context.selector, kind === 'create' ? undefined : cid(observed));
                preparedBefore.set(request, observed);
                return {request, requestCid: requestCid(request)};
              },
              release: retire, retry: retire,
              status: () => ({pending: original.pending}),
            });
          }}),
          requestFacts: request => ({value: request.value, target: request.target}),
          async observeTargets({entries, authorizationForRow}) {
            assert.equal(entries.length, 1, 'fixture target reads are bounded');
            const original = preparedBefore.get(entries[0].request);
            if (original !== undefined) {
              preparedBefore.delete(entries[0].request);
              return [{identity: recordId, versionCid: cid(original), before: original}];
            }
            await authorizationForRow(0);
            assert.equal(entries[0].target, recordId);
            return [{identity: recordId, versionCid: cid(before),
              before: structuredClone(before)}];
          },
          recoveryEntry: () => ({kind: 'fixture-json-update', observationCid,
            wire: dataJson(description)}),
          recoverRequests({durable, body}) {
            assert.deepEqual(durable.connectorRecovery, [{memberIndex: 0,
              kind: 'fixture-json-update', observationCid,
              wire: dataJson(description)}]);
            assert.equal(body.effects.length, 1);
            assert.equal(body.effects[0].changes.length, 1);
            return {currents: [description], requests: [
              body.effects[0].changes.map(change => requestFor(
                change.after.value, change.target_row_identity))]};
          },
          requestCid,
          async send({request}) {
            assert.ok(Buffer.byteLength(request.wire, 'utf8') <= transportLimit);
            assert.equal(request.target, kind === 'create' ? undefined : recordId);
            sends.push(request.wire);
            before = structuredClone(request.value);
            const body = Buffer.from(dataJson({record_id: recordId,
              echoed: request.value.payload, opaque: responsePayload}), 'utf8');
            assert.ok(body.byteLength <= transportLimit,
              'fixture response exceeds the explicit provider byte limit');
            return {observation: {useCid: cid({credential_use: sends.length}),
              statusCode: 201, body}, headers: undefined};
          },
          project({observation}) {
            assert.equal(observation.statusCode, 201);
            assert.ok(observation.body.byteLength <= transportLimit);
            projections.push(Buffer.from(observation.body).toString('utf8'));
            // The common owner records the physical response before this
            // hook, so a stop here must recover without another send.
            if (stopPending) {
              stopPending = false;
              throw Object.assign(new Error(stoppedCode), {code: stoppedCode});
            }
            return {kind: 'typed-success-response', outcome: {
              state: 'applied', result: JSON.parse(projections.at(-1))}};
          },
          footprint: () => ({providerNamespace: 'fixture',
            resourceKind: 'record', boundaryCid: cid({boundary: target})}),
        }});
      effects.push(effect);
      return effect;
    } catch (error) {
      site.close();
      throw error;
    }
  };
  return {root, load, preparedValues, sends, projections,
    requestChildren,
    writeGrants: () => writeGrants, readGrants: () => readGrants,
    onClose: close => closers.push(close)};
}

test('guarded request child binds the authorized before read before request Preview and apply', async t => {
  const installation = await installationFor(t, {requestChildMode: 'normal'});
  const host = await effectHost(t, installation, join(installation.root, 'host'),
    {effect: await installation.load()});
  const run = await host.run(programFor({next: true}), 'guarded-child');
  assert.equal(run.started.value.status, 'published');
  assert.equal(installation.requestChildren.length, 1,
    'guarded capture must use its installed original child rather than the pure fallback');
  const child = installation.requestChildren[0];
  assert.equal(child.prepares, 1);
  assert.equal(child.pending, true, 'request/GET backing remains held until original capture cleanup');
  assert.equal(installation.sends.length, 1);
  assert.equal(installation.writeGrants(), 1);
  const {stage} = host.outcomes[0];
  const change = JSON.parse(host.control.effectComputationPreviewWire(stage.preview)).effects[0].changes[0];
  assert.equal(change.target_guard.version_cid, cid({payload: {$json: {previous: true}}}));
  assert.deepEqual(change.before.value, {payload: {$json: {previous: true}}});
  await stage.releaseInputs();
  assert.equal(child.pending, false);
  assert.equal(child.releases, 1);
});

test('guarded request child preparation failure retains its original cleanup and sends nothing', async t => {
  const installation = await installationFor(t, {requestChildMode: 'failure'});
  const host = await effectHost(t, installation, join(installation.root, 'host'),
    {effect: await installation.load()});
  const failed = await host.run(programFor({next: true}), 'guarded-child-failure')
    .then(() => undefined, error => error);
  assert.equal(failed?.code, 'FixtureGuardedPrepareFailed', diagnostic(failed));
  assert.equal(installation.requestChildren.length, 1);
  assert.equal(installation.requestChildren[0].prepares, 1);
  assert.equal(installation.requestChildren[0].pending, false);
  assert.equal(installation.requestChildren[0].releases, 1);
  assert.deepEqual(installation.sends, []);
  assert.equal(installation.writeGrants(), 0);
});

test('guarded request child is not created when the original target read is denied', async t => {
  const installation = await installationFor(t, {requestChildMode: 'normal', targetReadOutcome: 'deny'});
  const host = await effectHost(t, installation, join(installation.root, 'host'),
    {effect: await installation.load()});
  const failed = await host.run(programFor({next: true}), 'guarded-child-denied')
    .then(() => undefined, error => error);
  assert.equal(failed?.code, 'InstalledRowEffectCheckNotAuthorized', diagnostic(failed));
  assert.deepEqual(installation.requestChildren, []);
  assert.equal(installation.readGrants(), 0);
  assert.equal(installation.writeGrants(), 0);
  assert.deepEqual(installation.sends, []);
});

test('guarded child cleanup pending retains the same failure and original cleanup handle', async t => {
  const installation = await installationFor(t, {requestChildMode: 'pending-failure'});
  const host = await effectHost(t, installation, join(installation.root, 'host'),
    {effect: await installation.load()});
  const failed = await host.run(programFor({next: true}), 'guarded-child-pending')
    .then(() => undefined, error => error);
  assert.equal(failed?.cleanupPending, true, diagnostic(failed));
  assert.equal(failed.primaryFailure?.code, 'FixtureGuardedPrepareFailed');
  assert.equal(installation.requestChildren.length, 1);
  const child = installation.requestChildren[0];
  assert.equal(child.pending, true);
  const handle = failed.cleanupHandle;
  assert.ok(handle);
  try {
    const held = await handle.retry();
    assert.equal(held.pending, true);
    assert.equal(failed.cleanupHandle, handle);
    assert.equal(child.pending, true);
    assert.equal(child.prepares, 1);
    assert.equal(installation.readGrants(), 1);
    assert.equal(installation.writeGrants(), 0);
    assert.deepEqual(installation.sends, []);
  } finally {
    child.allowRetire = true;
    const closed = await handle.retry();
    assert.equal(closed.pending, false);
    assert.equal(child.pending, false);
    assert.equal(child.prepares, 1);
  }
});

test('installed JSON update preserves approved value and exact recovered outcome keys',
  async t => {
    // Inline Program literals currently require canonical keys. The provider
    // response is independent opaque data and deliberately uses both spellings.
    const payload = {é: 1, nested: [{line: 'unchanged'}]};
    // JSON.parse makes __proto__ an own data property. Every paired key below
    // is distinct JSON data, including inside arrays and an ordinary $json.
    const responsePayload = JSON.parse('{"é":1,"e\\u0301":2,' +
      '"line\\r\\nkey":3,"line\\nkey":4,"lone\\rkey":5,' +
      '"":null,"__proto__":{"constructor":"data"},' +
      '"nested":[{"$json":{"é":"composed","e\\u0301":"decomposed"}},' +
      '{"text":"e\\u0301\\r\\nunchanged"}]}');
    const expectedValue = {payload: {$json: payload}};
    const expectedResult = {record_id: recordId, echoed: {$json: payload},
      opaque: responsePayload};
    const installation = await installationFor(t, {stopBeforeProjection: true,
      responsePayload});
    const state = join(installation.root, 'host');
    const firstEffect = await installation.load();
    const first = await effectHost(t, installation, state, {effect: firstEffect});
    const stopped = await first.run(programFor(payload), 'json-restart')
      .then(() => undefined, error => error);
    assert.equal(stopped?.code, stoppedCode, diagnostic(stopped));
    assert.equal(installation.sends.length, 1);
    assert.equal(installation.writeGrants(), 1);
    assert.ok(installation.readGrants() >= 2,
      'Preview and preflight must both read the guarded target');
    assert.equal(installation.sends[0], dataJson(expectedValue));
    assert.deepEqual(installation.preparedValues, [expectedValue]);

    const {stage} = first.outcomes[0];
    const previewWire = first.control.effectComputationPreviewWire(stage.preview);
    const change = JSON.parse(previewWire).effects[0].changes[0];
    assert.deepEqual(change.after, {state: 'present', value: expectedValue});
    assert.deepEqual(change.intended_changes,
      {state: 'present', value: expectedValue});
    assert.equal(change.target_row_identity, recordId,
      'update correlation remains a scalar primary identity');
    assert.deepEqual(change.before,
      {state: 'present', value: {payload: {$json: {previous: true}}}});
    const claim = stage.apply.members[0].claims[0];
    const stored = stage.apply.ledger.readClaimedResponse(claim);
    assert.ok(stored, 'physical response must be durable before projection');
    assert.equal(Buffer.from(stored.responseBytes).toString('utf8'),
      installation.projections[0]);
    assert.deepEqual(JSON.parse(installation.projections[0]), expectedResult);
    assert.equal(stage.apply.ledger.readClaimedOutcome(claim), undefined,
      'interrupted projection must not fabricate a typed outcome');
    const continuation = JSON.parse(stage.continuationWire);
    const runDefinitionCid = stopped.accepted.ref.runDefinitionCid;
    await first.close();
    firstEffect.close();

    const second = await effectHost(t, installation, state,
      {effect: await installation.load()});
    const resumed = await second.resume('json-restart', runDefinitionCid,
      continuation).then(value => value, error => ({error}));
    assert.equal(resumed.error, undefined, diagnostic(resumed.error));
    assert.equal(resumed.result.status, 'published');
    assert.equal(second.outcomes.length, 1);
    assert.equal(installation.sends.length, 1,
      'recovery must not repeat the physical send');
    assert.equal(installation.writeGrants(), 1,
      'stored-response recovery must not acquire another write grant');
    assert.deepEqual(installation.preparedValues, [expectedValue, expectedValue],
      'recovery rebuilds the request from the exact approved Preview');
    assert.deepEqual(installation.projections,
      [installation.projections[0], installation.projections[0]]);
    assert.equal(second.control.effectComputationPreviewWire(
      resumed.stage.preview), previewWire);
    const recoveredClaim = resumed.stage.receipt.members[0].rowOwners[0].claim;
    const saved = resumed.stage.receipt.ledger.readClaimedOutcome(recoveredClaim);
    assert.ok(saved, 'recovered typed outcome must be stored in the Ledger');
    assert.deepEqual(JSON.parse(saved.outcomeJson).typed_outcome,
      {state: 'applied', result: expectedResult});
  });

for (const [label, authoredKey, changedKey] of [
  ['NFC', 'é', 'e\u0301'],
  ['CRLF', 'line\nkey', 'line\r\nkey'],
  ['CR', 'line\nkey', 'line\rkey'],
]) {
  test(`installed JSON update refuses a ${label}-changed request before send`,
    async t => {
      const payload = {nested: [{[authoredKey]: 'same value'}]};
      const installation = await installationFor(t, {
        changeRequestValue(value) {
          const changed = structuredClone(value);
          const object = changed.payload.$json.nested[0];
          object[changedKey] = object[authoredKey];
          delete object[authoredKey];
          return changed;
        },
      });
      const host = await effectHost(t, installation,
        join(installation.root, 'host'), {effect: await installation.load()});
      const refused = await host.run(programFor(payload), `json-mismatch-${label}`)
        .then(() => undefined, error => error);
      assert.equal(refused?.code, 'ForeignInstalledRowEffectRequest',
        diagnostic(refused));
      assert.deepEqual(installation.preparedValues,
        [{payload: {$json: payload}}]);
      assert.deepEqual(installation.sends, []);
      assert.equal(installation.writeGrants(), 0);
      assert.deepEqual(installation.projections, []);
    });
}


for (const entrance of ['program', 'json', 'yaml']) {
  test(`raw Effect JSON keys survive ${entrance} Program Preview Ledger and restart`, async t => {
    const payload = {'é': 1, 'e\u0301': 2, '\r': 3, '\n': 4, '\r\n': 5,
      nested: [{$json: {'e\u0301': 'e\u0301\r\nvalue'}}]};
    const expectedValue = {payload: {$json: payload}};
    const installation = await installationFor(t, {stopBeforeProjection: true});
    const state = join(installation.root, 'host');
    const firstEffect = await installation.load();
    const first = await effectHost(t, installation, state, {effect: firstEffect});
    const program = programFor(payload);
    const stopped = await first.run(entrance === 'program' ? program : JSON.stringify(program),
      `raw-json-${entrance}`, entrance === 'program' ? {} : {kind: 'aql', format: entrance})
      .then(() => undefined, error => error);
    assert.equal(stopped?.code, stoppedCode, diagnostic(stopped));
    assert.deepEqual(installation.preparedValues, [expectedValue]);
    const {stage} = first.outcomes[0];
    const previewWire = first.control.effectComputationPreviewWire(stage.preview);
    assert.deepEqual(JSON.parse(previewWire).effects[0].changes[0].after.value, expectedValue);
    assert.equal(installation.sends[0], dataJson(expectedValue));
    const continuation = JSON.parse(stage.continuationWire);
    const runDefinitionCid = stopped.accepted.ref.runDefinitionCid;
    await first.close(); firstEffect.close();
    const second = await effectHost(t, installation, state,
      {effect: await installation.load()});
    const resumed = await second.resume(`raw-json-${entrance}`, runDefinitionCid, continuation);
    assert.equal(resumed.result.status, 'published');
    const claim = resumed.stage.receipt.members[0].rowOwners[0].claim;
    const saved = resumed.stage.receipt.ledger.readClaimedOutcome(claim);
    assert.deepEqual(JSON.parse(saved.outcomeJson).typed_outcome.result.echoed,
      {$json: payload});
    assert.equal(second.control.effectComputationPreviewWire(resumed.stage.preview), previewWire);
    assert.equal(installation.sends.length, 1);
  });
}


const literalKeyVectors = {cases: currentEffectLiteralKeyVectors()};

async function literalPreparation(payloadContract) {
  const {environmentWire} = await mappingEnvironment(payloadContract);
  const environment = moon.clientProgramCheckEnvironment(environmentWire,
    JSON.parse(environmentWire).evidence_bundle_cid,
    false, false, true, false, false, false, false);
  assert.ok(environment);
  // Only the authored JSON checker vectors below use this raw input port.
  // This returns no Request/Run owner or provider permission.
  return request => {
    const document = request.kind === 'program'
      ? JSON.stringify(request.input) : request.input.text;
    const outcome = moon.clientProgramPrepareEffectComputationWithParameters(
      document, 'json', environment, undefined, []);
    const original = moon.clientProgramEffectPreparationReady(outcome);
    assert.ok(original, moon.clientProgramEffectPreparationIssueCode(outcome));
    return original;
  };
}

test('raw Effect literal source identities match independent Stage and Program vectors', async () => {
  const prepare = await literalPreparation({type: 'json', nullable: true});
  for (const vector of literalKeyVectors.cases) {
    for (const kind of ['program', 'aql']) {
      const program = programFor(vector.payload);
      const prepared = prepare({kind, parameters: null,
        input: kind === 'program' ? program : {format: 'json', text: JSON.stringify(program)}});
      assert.equal(moon.clientProgramEffectDefinitionCid(prepared),
        vector.expected_definition_cid, `${vector.name}: ${kind} definition`);
      assert.equal(moon.clientProgramEffectSemanticsCid(prepared),
        vector.expected_program_cid, `${vector.name}: ${kind} semantics`);
    }
  }
});

test('Object field normalization does not make Program identity depend on the Mapping', async t => {
  const payloadContract = {type: 'object', nullable: false, additional_properties: false,
    fields: {é: {type: 'number', nullable: false}}};
  const prepareObject = await literalPreparation(payloadContract);
  const prepareJson = await literalPreparation({type: 'json', nullable: false});
  const identities = [];
  for (const name of ['nfc-key', 'nfd-key']) {
    const vector = literalKeyVectors.cases.find(item => item.name === name);
    const request = {kind: 'program', input: programFor(vector.payload), parameters: null};
    const objectIdentity = moon.clientProgramEffectDefinitionCid(prepareObject(request));
    assert.equal(objectIdentity, vector.expected_definition_cid);
    assert.equal(moon.clientProgramEffectDefinitionCid(prepareJson(request)), objectIdentity);
    identities.push(objectIdentity);
  }
  assert.notEqual(...identities);
  const installation = await installationFor(t, {payloadContract, beforePayload: {é: 0}});
  const host = await effectHost(t, installation, join(installation.root, 'host'),
    {effect: await installation.load()});
  const run = await host.run(programFor({'e\u0301': 1}), 'typed-object-normalization');
  assert.equal(run.started.value.status, 'published');
  assert.deepEqual(installation.preparedValues, [{payload: {é: 1}}]);
  assert.equal(installation.sends[0], '{"payload":{"é":1}}');
});

for (const [label, payload, nullable, expected] of [
  ['SQL NULL', null, true, null],
  ['ordinary $json object', {$json: null}, false, {$json: {$json: null}}],
]) {
  test(`Effect literal preserves ${label} through Preview and outcome`, async t => {
    const installation = await installationFor(t,
      {payloadContract: {type: 'json', nullable}});
    const host = await effectHost(t, installation, join(installation.root, 'host'),
      {effect: await installation.load()});
    const run = await host.run(programFor(payload), `literal-${nullable ? 'null' : 'envelope'}`);
    assert.equal(run.started.value.status, 'published');
    assert.deepEqual(installation.preparedValues, [{payload: expected}]);
    const {stage} = host.outcomes[0];
    assert.deepEqual(JSON.parse(host.control.effectComputationPreviewWire(stage.preview))
      .effects[0].changes[0].after.value, {payload: expected});
    const saved = stage.receipt.ledger.readClaimedOutcome(stage.receipt.members[0].rowOwners[0].claim);
    assert.deepEqual(JSON.parse(saved.outcomeJson).typed_outcome.result.echoed, expected);
  });
}


function createChildProgram() {
  return {version: 'actql/0.1', id: 'installed-create-original-child', stages: [{
    id: 'source', inputs: {}, steps: [{values: {schema: {
      payload: {type: 'string', nullable: false}}, rows: [{payload: 'original create'}]}, as: 'selected'}],
    results: {rows: {from: 'selected', fields: ['payload']}},
    effects: {save: {create: {target, mapping: mappingRef, from: {result: 'rows'}}}},
  }], results: {answer: {from: {stage: 'source', result: 'rows'}}}};
}

test('CREATE uses its original request child and retains it through capture release', async t => {
  const installation = await installationFor(t, {kind: 'create',
    payloadContract: {type: 'string', nullable: false}, requestChildMode: 'normal'});
  const host = await effectHost(t, installation, join(installation.root, 'host'),
    {effect: await installation.load()});
  const run = await host.run(createChildProgram(), 'create-original-child');
  assert.equal(run.started.value.status, 'published');
  assert.equal(installation.requestChildren.length, 1,
    'CREATE must consume the installed original child rather than silently use the pure fallback');
  const child = installation.requestChildren[0];
  assert.equal(child.prepares, 1); assert.equal(child.pending, true);
  assert.equal(installation.sends.length, 1); assert.equal(installation.writeGrants(), 1);
  await host.outcomes[0].stage.releaseInputs();
  assert.equal(child.pending, false); assert.equal(child.releases, 1);
});

test('CREATE child preparation failure retires that original child without a write', async t => {
  const installation = await installationFor(t, {kind: 'create',
    payloadContract: {type: 'string', nullable: false}, requestChildMode: 'failure'});
  const host = await effectHost(t, installation, join(installation.root, 'host'),
    {effect: await installation.load()});
  const failure = await host.run(createChildProgram(), 'create-child-failure').catch(error => error);
  assert.equal(failure?.code, 'FixtureGuardedPrepareFailed', diagnostic(failure));
  assert.equal(installation.requestChildren.length, 1);
  assert.equal(installation.requestChildren[0].prepares, 1);
  assert.equal(installation.requestChildren[0].pending, false);
  assert.equal(installation.requestChildren[0].releases, 1);
  assert.equal(installation.writeGrants(), 0); assert.deepEqual(installation.sends, []);
});

test('CREATE child pending cleanup retains the original failure and parent duty until ACK', async t => {
  const installation = await installationFor(t, {kind: 'create',
    payloadContract: {type: 'string', nullable: false}, requestChildMode: 'pending-failure'});
  const host = await effectHost(t, installation, join(installation.root, 'host'),
    {effect: await installation.load()});
  const failure = await host.run(createChildProgram(), 'create-child-pending').catch(error => error);
  assert.equal(failure?.cleanupPending, true, diagnostic(failure));
  assert.equal(failure.primaryFailure?.code, 'FixtureGuardedPrepareFailed');
  const child = installation.requestChildren[0], handle = failure.cleanupHandle;
  assert.equal(child.pending, true); assert.ok(handle);
  try {
    assert.equal((await handle.retry()).pending, true);
    assert.equal(failure.cleanupHandle, handle); assert.equal(child.prepares, 1);
    assert.equal(installation.writeGrants(), 0); assert.deepEqual(installation.sends, []);
  } finally {
    child.allowRetire = true;
    assert.equal((await handle.retry()).pending, false);
    assert.equal(child.pending, false);
  }
});
