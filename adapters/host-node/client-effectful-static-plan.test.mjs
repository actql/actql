import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {createServer} from 'node:https';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import * as rawMoon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {withFixtureConnector} from '../host-common/connector-manifest.fixture.mjs';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';
import {installNodeClientProgramPreparation} from './client-program-preparation.mjs';
import {installClientStaticPlan} from './client-interactive-plan.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {createClientHttpHandler} from './client-http.mjs';
import {connectInProcess} from '../../packages/sdk/host-port.mjs';
import {connect} from '../../packages/sdk/index.mjs';
import {fixtureCertificates} from '../site-node/https-exchange-fixture.mjs';
import {planReadModel} from '../../packages/explorer-ui/read-model.mjs';

const cid = body => `sha256:${createHash('sha256').update(canonicalText(body)).digest('hex')}`;
const program = {version: 'actql/0.1', id: 'readonly-update', stages: [{id: 'source', inputs: {},
  steps: [{values: {schema: {id: {type: 'string', nullable: false}, value: {type: 'number', nullable: false}},
    rows: [{id: 'original-id', value: 1}]}, as: 'selected'}],
  results: {out: {from: 'selected', fields: ['id', 'value']}},
  effects: {save: {update: {target: 'connector://crm/account', mapping: 'mapping:crm.account.v1',
    from: {result: 'out'}, id: 'id', set: {Name: {field: 'value'}}}}}}],
  results: {published: {from: {stage: 'source', result: 'out'}}}};
async function fixture() {
  const environmentBody = JSON.parse(await readFile(new URL('../../packages/sdk/fixtures/values.environment.json', import.meta.url)));
  const targetSchema = {additional_properties: false, fields: {Id: {nullable: false, type: 'string'},
    Name: {nullable: true, type: 'number'}}, nullable: false, type: 'object'};
  const mapping = {connector_manifest_cid: withFixtureConnector(environmentBody, 'connector://crm/account'),
    conversions: [], mapping_ref: 'mapping:crm.account.v1', minimum_approval: 'required',
    permission_rules: [{effect_kind: 'update', permissions: ['scope:update'], selector_class: 'id', write_fields: ['Name']}],
    primary_identity: 'Id', required_fields: [], required_permissions: [],
    resource_identity_cid: `sha256:${'b'.repeat(64)}`, row_mapping: {Name: {field: 'value', null_behavior: 'reject'}},
    schema: 'actql.mapping_contract/0.1', target_ref: 'connector://crm/account',
    target_schema: targetSchema, target_schema_identity: cid(targetSchema), version: 'fixture', writable_fields: ['Name']};
  const mappingCid = cid(mapping);
  environmentBody.mapping_contracts = [{...mapping, mapping_contract_cid: mappingCid}];
  delete environmentBody.evidence_bundle_cid;
  const environmentCid = cid(environmentBody);
  environmentBody.evidence_bundle_cid = environmentCid;
  let starts = 0;
  // Observe every exported execution/acquisition entry, without installing a
  // replacement executor, Store or permit. The ordinary checker/compiler run.
  const moon = new Proxy(rawMoon, {get(target, name) {
    const value = target[name];
    if (typeof value === 'function' && /^(?:clientProgram(?:Start|Open|IssueAcquired|Dispatch)|run)/u.test(name)) {
      return (...args) => {starts++; return value(...args);};
    }
    return value;
  }});
  const environment = moon.clientProgramCheckEnvironment(canonicalText(environmentBody), environmentCid,
    false, false, true, false, false, false, false);
  assert.ok(environment);
  const prepare = installNodeClientProgramPreparation({moon, environment, allowEffects: true});
  let allowed = true, currentCalls = 0, corrupt = false;
  const ordinary = runtimeCore(moon).publicationControl;
  const plan = installClientStaticPlan({moon, prepare,
    authorize: () => {currentCalls++; return allowed;},
    control: {readCheckedClientStaticPlan(...args) {
      const wire = ordinary.readCheckedClientStaticPlan(...args);
      if (!corrupt) return wire;
      const changed = JSON.parse(wire);
      changed.program_definition_cid = `sha256:${'f'.repeat(64)}`;
      return JSON.stringify(changed);
    }}});
  return {plan, mappingCid, environmentCid, starts: () => starts, currentCalls: () => currentCalls,
    revoke: () => {allowed = false;}, corrupt: () => {corrupt = true;}};
}
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'volatile', scopeRef: 'effectful-static-test', capabilities: [],
  limits: {maxReadWireBytes: 65536, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 65536, maxRows: 10, maxBatchRows: 10, maxBatchRetainedValueBytes: 2048}};

for (const entrance of ['local', 'https']) {
  test(`${entrance}: actual checked Effectful static projection reaches SDK and Explorer with execution zero`, async t => {
    const f = await fixture(); let submits = 0, server, client;
    const root = await mkdtemp(join(tmpdir(), 'actql-effect-static-public-'));
    const trust = getCACertificates('default');
    const operations = {authenticate: () => 'static-reader', authorizeConnection: () => true,
      negotiate: ({connection}) => ({...profile, mode: connection.mode, owner: connection.owner}), maxRowBytes: 1024,
      plan: f.plan, submit() {submits++; throw new Error('unexpected submit');}};
    let complete = false;
    t.after(async () => {
      await client?.close();
      if (server) {server.closeAllConnections(); await new Promise(resolve => server.close(resolve));}
      setDefaultCACertificates(trust);
      if (complete) await rm(root, {recursive: true, force: true});
      else t.diagnostic(`Failure fixture retained at ${root}`);
    });
    if (entrance === 'local') {
      client = await connectInProcess({mode: 'local', owner: 'local'}, createNodeInProcessClientHost(operations));
    } else {
      const cert = await fixtureCertificates(root);
      setDefaultCACertificates([...trust, cert.ca.toString('utf8')]);
      server = createServer({key: cert.key, cert: cert.cert}, createClientHttpHandler(operations));
      await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
      client = await connect({mode: 'remote', token: 'static-fixture',
        endpoint: `https://127.0.0.1:${server.address().port}/`});
    }
    const view = await client.plan(program);
    assert.equal(view.version, 'actql-effectful-static-plan-view/0.1');
    assert.equal(view.computation.scope, 'computation_component');
    assert.equal(view.check_environment_cid, f.environmentCid);
    assert.equal(view.effect_set.unit_id, 'source');
    assert.deepEqual(view.effect_set.members, [{member_ordinal: 0, stage_ordinal: 0, effect_id: 'save',
      effect_kind: 'update', failure_policy: 'halt', contract: {kind: 'mapping', reference: 'mapping:crm.account.v1',
        contract_cid: f.mappingCid, declared_target: 'connector://crm/account'},
      input: {kind: 'result', result_name: 'out'}, minimum_approval: {kind: 'contract_minimum', value: 'required'}}]);
    assert.equal(Object.isFrozen(view.effect_set.members), true);
    const model = planReadModel(view);
    assert.equal(model.effectful.observations.permission.state, 'unknown');
    assert.equal(model.effectful.observations.preview.state, 'unavailable');
    assert.equal(model.effectful.members[0].minimum_approval.value, 'required');
    assert.deepEqual(model.nodes.map(n => n.operator), ['values']);
    assert.equal(model.edges.length, 0);
    assert.equal(f.currentCalls(), 2);
    assert.equal(f.starts(), 0); assert.equal(submits, 0);
    f.corrupt();
    await assert.rejects(client.plan(program), {code: 'InvalidClientHostPlanView'});
    f.revoke();
    await assert.rejects(client.plan(program), {code: 'ClientConnectionDenied'});
    assert.equal(f.starts(), 0); assert.equal(submits, 0);
    complete = true;
  });
}
