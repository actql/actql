// Typed JSON values through the real installed row Effect, checked Program,
// Preview, durable Ledger and restart. Only the provider transport and its
// credential Site are test doubles; neither performs network I/O. A neutral
// Mapping is intentional: Salesforce fields and the row-source declaration
// generator do not currently support JSON write fields.
// The fixture Program uses already-canonical JSON keys. Arbitrary authored
// JSON-key preservation is not established by these tests: inline Effect
// literals currently normalize keys, while the source-free Effect opener
// does not support typed-literal derive Programs.
// Exact opaque provider response/outcome keys are tested separately below.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {inspect} from 'node:util';
import {withFixtureConnector} from
  '../host-common/connector-manifest.fixture.mjs';
import {effectHost, moon} from
  '../connectors/salesforce/test/installed-salesforce-effect.fixture.mjs';
import {createInstalledRowEffect} from './installed-row-effect.mjs';
import {createLocalAuthorizationGate} from './local-account-config.mjs';

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

async function mappingEnvironment() {
  const environment = JSON.parse(await readFile(new URL(
    '../../spec/local-check-environment.json', import.meta.url), 'utf8'));
  const schema = {additional_properties: false, fields: {
    Id: {nullable: false, type: 'string'},
    payload: {nullable: false, type: 'json'},
  }, nullable: false, type: 'object'};
  const mapping = {
    connector_manifest_cid: withFixtureConnector(environment, target),
    conversions: [], mapping_contract_cid: '', mapping_ref: mappingRef,
    minimum_approval: 'none',
    permission_rules: [{effect_kind: 'update', permissions: ['scope:update'],
      selector_class: 'id', write_fields: ['payload']}],
    primary_identity: 'Id', required_fields: [],
    required_permissions: [],
    resource_identity_cid: cid({resource: target}),
    row_mapping: {},
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

async function installationFor(t, {changeRequestValue,
  stopBeforeProjection = false, responsePayload = {ok: true}} = {}) {
  const {environmentWire, mapping} = await mappingEnvironment();
  const root = await mkdtemp(join(tmpdir(), 'actql-installed-row-json-'));
  const closers = [];
  const effects = [];
  const preparedValues = [];
  const sends = [];
  const projections = [];
  let writeGrants = 0;
  let readGrants = 0;
  let before = {payload: {$json: {previous: true}}};
  let stopPending = stopBeforeProjection;
  const description = {version: 'fixture-json-update/0.1', resource: 'records',
    writable_fields: ['payload']};
  const observationCid = cid(description);
  const requestCid = request => cid({operation: 'update', target,
    selector: request.target, value: request.value});
  const requestFor = (value, selector) => {
    assert.equal(selector, recordId);
    preparedValues.push(structuredClone(value));
    const requestValue = changeRequestValue === undefined
      ? structuredClone(value) : changeRequestValue(value);
    const wire = dataJson(requestValue);
    assert.ok(Buffer.byteLength(wire, 'utf8') <= transportLimit,
      'fixture request exceeds the explicit provider byte limit');
    return Object.freeze({value: requestValue, target: selector, wire});
  };
  t.after(async () => {
    try {
      for (const close of closers.reverse()) await close();
    } finally {
      for (const effect of effects) effect.close();
      await rm(root, {recursive: true, force: true});
    }
  });
  const accountConfiguration = dataJson({
    version: 'actql-execution-account-config/0.1',
    account_id: 'installed-json-fixture', entries: [{
      entry_id: 'update-json', outcome: 'allow', exclusions: [],
      principal: {all: true}, connection: {any_of: [connection]},
      resource: {any_of: ['records']}, operation: {any_of: ['effect', 'read']},
    }],
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
        assert.equal(operation, 'fixture:update');
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
          kinds: ['update'], writeOperation: () => 'fixture:update',
          targetRead: {operation: 'fixture:read'},
          describe: async () => description,
          prepareRequest({value, selector}) {
            const request = requestFor(value, selector);
            return {request, requestCid: requestCid(request)};
          },
          requestFacts: request => ({value: request.value, target: request.target}),
          async observeTargets({entries, authorizationForRow}) {
            assert.equal(entries.length, 1, 'fixture target reads are bounded');
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
            assert.equal(request.target, recordId);
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
    writeGrants: () => writeGrants, readGrants: () => readGrants,
    onClose: close => closers.push(close)};
}

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
