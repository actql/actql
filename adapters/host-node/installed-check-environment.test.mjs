import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {withFixtureConnector} from
  '../host-common/connector-manifest.fixture.mjs';
import {canonicalJson, contentCid} from './local-account-config.mjs';
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
