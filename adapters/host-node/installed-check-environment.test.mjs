import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {withFixtureConnector} from
  '../host-common/connector-manifest.fixture.mjs';
import {canonicalJson, contentCid} from './local-account-config.mjs';
import {installedModelEnvironment} from './installed-model.mjs';
import {composeInstalledCheckEnvironment,
  verifyInstalledConnectorBindings} from
  './installed-check-environment.mjs';

const moon = await import(new URL('../../_build/js/release/build/' +
  'connectors_builtin_node/connectors_builtin_node.js', import.meta.url));
const baseWire = (await readFile(new URL('../../spec/' +
  'local-check-environment.json', import.meta.url), 'utf8')).trimEnd();

function installed(connector, version = 'fixture') {
  const body = JSON.parse(baseWire);
  withFixtureConnector(body, `connector://${connector}/records`);
  if (version !== 'fixture') {
    const catalog = body.connector_catalogs[0];
    catalog.connector_version = version;
    const {catalog_cid: _, ...catalogBody} = catalog;
    catalog.catalog_cid = contentCid(catalogBody);
    body.connector_manifest.connectors[0].connector_version = version;
  }
  delete body.evidence_bundle_cid;
  return canonicalJson({...body, evidence_bundle_cid: contentCid(body)});
}

test('installed environment combines distinct closed connector catalogs',
  () => {
    const wire = composeInstalledCheckEnvironment(moon, baseWire,
      installed('source'), installed('effect'));
    const body = JSON.parse(wire);
    assert.deepEqual(body.connector_catalogs.map(value =>
      value.connector_id).sort(), ['effect', 'source']);
    assert.deepEqual(body.connector_manifest.connectors.map(value =>
      value.connector_id).sort(), ['effect', 'source']);
    const {evidence_bundle_cid: evidenceCid, ...preimage} = body;
    assert.equal(evidenceCid, contentCid(preimage));
    assert.notEqual(moon.clientProgramCheckEnvironment(wire, evidenceCid,
      false, false, true, false, false, false, false), undefined);
  });

test('identical installed declaration is shared once, not reauthorized',
  () => {
    const source = installed('shared');
    assert.equal(composeInstalledCheckEnvironment(moon, baseWire,
      source, source), source);
  });

test('same connector ID with another Catalog is refused before execution',
  () => {
    assert.throws(() => composeInstalledCheckEnvironment(moon, baseWire,
      installed('shared'), installed('shared', 'changed')),
    {code: 'InstalledCheckEnvironmentConflict'});
  });

test('a changed policy profile cannot be widened by composition', () => {
  const changed = JSON.parse(installed('effect'));
  changed.host_policy_profile.capacity.max_effect_items += 1;
  delete changed.evidence_bundle_cid;
  const wire = canonicalJson({...changed,
    evidence_bundle_cid: contentCid(changed)});
  assert.throws(() => composeInstalledCheckEnvironment(moon, baseWire,
    installed('source'), wire),
  {code: 'InstalledCheckEnvironmentConflict'});
});

test('matching Catalogs cannot hide a different Site or principal', () => {
  const environmentWire = installed('shared');
  const binding = value => ({environmentWire,
    connectorBindings: [{connectorId: 'shared', bindingCid:
      contentCid({site: value})}]});
  assert.doesNotThrow(() => verifyInstalledConnectorBindings(
    binding('same'), binding('same')));
  assert.throws(() => verifyInstalledConnectorBindings(
    binding('site-a'), binding('site-b')),
  {code: 'InstalledCheckEnvironmentConflict'});
  assert.throws(() => verifyInstalledConnectorBindings(
    binding('same'), {environmentWire}),
  {code: 'InstalledCheckEnvironmentConflict'});
});


const reseal = (wire, change) => {
  const {evidence_bundle_cid: ignored, ...body} = JSON.parse(wire);
  void ignored;
  change(body);
  return canonicalJson({...body, evidence_bundle_cid: contentCid(body)});
};
const assertAdmitted = wire => {
  const {evidence_bundle_cid: evidenceCid} = JSON.parse(wire);
  assert.notEqual(moon.clientProgramCheckEnvironment(wire, evidenceCid,
    false, false, true, false, false, false, false), undefined,
  '[installed-environment:independent-admission]');
};
// Existing independently authored ModelTask contract, not composer output.
const taskSource = await readFile(new URL(
  '../../src/stage_results/infer_program_test.mbt', import.meta.url), 'utf8');
const modelTask = JSON.parse(taskSource.match(/let body =\n\s+#\|(.+)/u)[1]);
const wires = {
  source: installed('source'), effect: installed('effect'),
  model: reseal(baseWire, body => {body.model_task_contracts = [modelTask];}),
};
const installationCases = [[], ['source'], ['effect'], ['source', 'effect'],
  ['model'], ['source', 'model'], ['effect', 'model'], ['source', 'effect', 'model']];
const composeCase = (roles, replacements = {}, base = baseWire) => {
  const selected = {...wires, ...replacements};
  const current = composeInstalledCheckEnvironment(moon, base,
    roles.includes('source') ? selected.source : undefined,
    roles.includes('effect') ? selected.effect : undefined);
  return roles.includes('model') ? installedModelEnvironment(moon, base,
    current, {environmentWire: selected.model}) : current;
};

for (const roles of installationCases) {
  const label = roles.join('+') || 'no adapters';
  test(`${label}: installation retains the Host base policy and all admitted roles`, () => {
    const wire = composeCase(roles), body = JSON.parse(wire);
    assertAdmitted(wire);
    assert.deepEqual(body.host_policy_profile, JSON.parse(baseWire).host_policy_profile);
    assert.deepEqual(body.connector_catalogs.map(value => value.connector_id).sort(),
      roles.filter(role => role !== 'model').sort());
    assert.deepEqual(body.model_task_contracts, roles.includes('model') ? [modelTask] : []);
    if (roles.length === 0) assert.equal(wire, baseWire);
    if (roles.length === 1 && roles[0] !== 'model') assert.equal(wire, wires[roles[0]]);
    for (const role of roles) assertAdmitted(wires[role]);
  });
  for (const role of roles) {
    test(`${label}: ${role} cannot replace the Host policy even when independently admitted`, () => {
      const changed = reseal(wires[role], body => {
        body.host_policy_profile.capacity.max_effect_items += 1;
      });
      assertAdmitted(changed);
      assert.throws(() => composeCase(roles, {[role]: changed}), error => {
        assert.equal(error.code, 'InstalledCheckEnvironmentConflict',
          '[installed-environment:base-policy]');
        assert.equal(error.cause, 'EnvironmentBase');
        return true;
      });
    });
    test(`${label}: ${role} still requires independent canonical environment admission`, () => {
      const document = JSON.parse(wires[role]);
      const invalid = [
        canonicalJson({...document, evidence_bundle_cid: 'sha256:' + '0'.repeat(64)}),
        wires[role] + '\n',
        reseal(wires[role], body => {body.version = 'actql-check-environment/future';}),
        reseal(wires[role], body => {body.source_views = null;}),
        reseal(wires[role], body => {body.future_installation_policy = {allow: true};}),
      ];
      for (const wire of invalid) assert.throws(() => composeCase(roles, {[role]: wire}),
        {code: 'InstalledCheckEnvironmentConflict'});
    });
  }
}

test('the Host can select its own admitted base policy without any adapters', () => {
  const changed = reseal(baseWire, body => {body.host_policy_profile.capacity.max_effect_items += 1;});
  assertAdmitted(changed);
  assert.equal(composeCase([], {}, changed), changed);
});

test('Model augmentation preserves conflicting-selector refusal', () => {
  const source = installed('shared');
  const model = reseal(installed('shared', 'changed'), body => {
    body.model_task_contracts = [modelTask];
  });
  assertAdmitted(source); assertAdmitted(model);
  assert.throws(() => installedModelEnvironment(moon, baseWire, source,
    {environmentWire: model}), {code: 'InstalledCheckEnvironmentConflict'});
});

test('Model augmentation does not replace physical Source and Effect binding checks', () => {
  const environmentWire = composeCase(['source', 'effect', 'model']);
  const binding = value => ({environmentWire,
    connectorBindings: ['source', 'effect'].map(connectorId =>
      ({connectorId, bindingCid: contentCid({site: value, connectorId})}))});
  assert.doesNotThrow(() => verifyInstalledConnectorBindings(binding('same'), binding('same')));
  assert.throws(() => verifyInstalledConnectorBindings(binding('first'), binding('second')),
    {code: 'InstalledCheckEnvironmentConflict'});
});
