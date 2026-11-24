import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {mkdtemp, rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import test from 'node:test';
import {canonicalJson, contentCid} from './local-account-config.mjs';
import * as environmentOwner from './installed-check-environment.mjs';
import {withFixtureConnector} from '../host-common/connector-manifest.fixture.mjs';
import {createInstalledLoaderParent} from './fixtures/installed-loader-parent.fixture.mjs';
import {snapshotInstalledCalendar} from './installed-calendar.mjs';
import {calendarSourceArtifact, calendarSourceSelection, calendarSourceArtifactLimits}
  from '../../scripts/fixtures/calendar-source-input.mjs';
import {composeInstalledSourceEnvironment, readInstalledHostEnvironment,
  admitInstalledSourceFinalEnvironment, assertInstalledEnvironmentPublicationOriginal}
  from './installed-funded-environment.mjs';
import * as runtime from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';

const baseWire = readFileSync(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8').trimEnd();
function encoded(body) {
  delete body.evidence_bundle_cid;
  return canonicalJson({...body, evidence_bundle_cid: contentCid(body)});
}
function installed(connector) {
  const document = JSON.parse(baseWire);
  withFixtureConnector(document, `connector://${connector}/records`);
  return encoded(document);
}
function admission() {
  const calls = [];
  const moon = {clientProgramCheckEnvironment(wire, cid, ...flags) {
    assert.strictEqual(this, moon);
    assert.equal(JSON.parse(wire).evidence_bundle_cid, cid);
    assert.deepEqual(flags, [false, false, true, false, false, false, false]);
    const original = {};
    calls.push({wire, cid, flags, original});
    return original;
  }};
  return {moon, calls};
}

test('selected Environment original retains the exact runtime, body, wire, CID and admission', () => {
  assert.equal(typeof environmentOwner.composeInstalledCheckEnvironmentOriginal, 'function');
  const {moon, calls} = admission();
  const selected = environmentOwner.composeInstalledCheckEnvironmentOriginal(moon, baseWire);
  const {evidence_bundle_cid: cid, ...expected} = JSON.parse(baseWire);
  assert.strictEqual(selected.runtime, moon);
  assert.equal(selected.wire, baseWire); assert.equal(selected.evidenceCid, cid);
  assert.deepEqual(selected.body, expected);
  assert.strictEqual(selected.admitted, calls[0].original);
  assert(Object.isFrozen(selected));
  assert.equal(calls.length, 1);
  const other = environmentOwner.composeInstalledCheckEnvironmentOriginal(moon, baseWire);
  assert.notStrictEqual(other.admitted, selected.admitted);
  assert.equal(calls.length, 2, 'Equal bytes in another call are not a process-wide admitted cache');
});

test('selected Source/Effect identical inputs retain the same original document once', () => {
  const {moon, calls} = admission(), wire = installed('shared');
  const selected = environmentOwner.composeInstalledCheckEnvironmentOriginal(moon, baseWire, wire, wire);
  assert.equal(selected.wire, wire);
  assert.deepEqual(calls.map(value => value.wire), [baseWire, wire]);
  assert.strictEqual(selected.admitted, calls[1].original);
  assert.deepEqual(selected.body.connector_catalogs.map(value => value.connector_id), ['shared']);
});

test('selected Source/Effect records cannot replace base policy or conflicting Catalog selectors', () => {
  const wire = installed('shared');
  const changedPolicy = JSON.parse(wire);
  changedPolicy.host_policy_profile.capacity.max_effect_items++;
  delete changedPolicy.evidence_bundle_cid;
  assert.throws(() => environmentOwner.composeInstalledCheckEnvironmentOriginal(admission().moon,
    baseWire, wire, encoded(changedPolicy)), error => error.code === 'InstalledCheckEnvironmentConflict' &&
      error.cause === 'EnvironmentBase');
  const changedCatalog = JSON.parse(wire), catalog = changedCatalog.connector_catalogs[0];
  catalog.connector_version = 'changed';
  const {catalog_cid: ignored, ...catalogBody} = catalog;
  void ignored;
  catalog.catalog_cid = contentCid(catalogBody);
  changedCatalog.connector_manifest.connectors[0].connector_version = 'changed';
  delete changedCatalog.evidence_bundle_cid;
  assert.throws(() => environmentOwner.composeInstalledCheckEnvironmentOriginal(admission().moon,
    baseWire, wire, encoded(changedCatalog)), error => error.code === 'InstalledCheckEnvironmentConflict' &&
      error.cause === 'ConflictingSelector');
});

test('external wire encoding, CID and selected admission remain required', () => {
  const {moon, calls} = admission();
  for (const wire of ['{', baseWire + '\n', canonicalJson({...JSON.parse(baseWire),
    evidence_bundle_cid: 'sha256:' + '0'.repeat(64)})]) {
    assert.throws(() => environmentOwner.composeInstalledCheckEnvironment(moon, wire),
      {code: 'InstalledCheckEnvironmentConflict'});
  }
  assert.equal(calls.length, 0);
  assert.throws(() => environmentOwner.composeInstalledCheckEnvironment({
    clientProgramCheckEnvironment() {return undefined;},
  }, baseWire), {code: 'InstalledCheckEnvironmentConflict'});
  for (const cause of [new Error('original admission failed'), undefined, null]) {
    let caught = false;
    try {environmentOwner.composeInstalledCheckEnvironment({
      clientProgramCheckEnvironment() {throw cause;},
    }, baseWire);} catch (error) {caught = true; assert.strictEqual(error, cause);}
    assert(caught);
  }
});

// These use the installed Host's real initial Resource, Source material,
// generated constructors and nominal publication join. The loader parent has
// no provider or authorization substitute and closes its actual original.
const profiles = Object.freeze({textTime: false,
  numericProfileCid: contentCid(JSON.parse(readFileSync(new URL(
    '../../spec/contracts/actql-numeric-reduction.json', import.meta.url), 'utf8'))),
  graphLawCid: contentCid(JSON.parse(readFileSync(new URL(
    '../../spec/dependencies/actql-graph-laws.json', import.meta.url), 'utf8')))});

async function parentFixture(t, assertCurrent) {
  const root = await mkdtemp(join(tmpdir(), 'actql-final-environment-original-'));
  const parent = createInstalledLoaderParent({root, moon: runtime, assertCurrent});
  t.after(async () => {await parent.close(); await rm(root, {recursive: true, force: true});});
  parent.open();
  return parent;
}
function publication(final) {
  const prepared = runtime.clientProgramPreparePublicSourceEnvironment(final.admitted,
    JSON.stringify({environmentCid: final.evidenceCid, aliases: []}));
  assert.ok(prepared);
  return prepared;
}

test('funded Host final admission retains the exact original body wire CID and publication', async t => {
  const parent = await parentFixture(t), source = installed('original-source');
  const composed = composeInstalledSourceEnvironment(parent.services, runtime, baseWire, source);
  const final = admitInstalledSourceFinalEnvironment(parent.services, runtime, composed, profiles);
  assert.strictEqual(final.runtime, runtime);
  assert.strictEqual(final.body, composed.body);
  assert.equal(final.wire, source);
  assert.equal(final.evidenceCid, JSON.parse(source).evidence_bundle_cid);
  assert.notStrictEqual(final.admitted, composed.admitted);
  const prepared = publication(final);
  assert.doesNotThrow(() => assertInstalledEnvironmentPublicationOriginal(
    parent.services, runtime, final, prepared, source));
  assert.throws(() => assertInstalledEnvironmentPublicationOriginal(
    parent.services, runtime, composed, prepared, source), {code: 'ForeignInstalledEnvironmentOriginal'});
  await parent.close();
  assert.throws(() => assertInstalledEnvironmentPublicationOriginal(
    parent.services, runtime, final, prepared, source));
});

test('changed final Host policy constructs its own actual raw checker original', async t => {
  const parent = await parentFixture(t);
  const composed = composeInstalledSourceEnvironment(parent.services, runtime, baseWire);
  const body = JSON.parse(composed.wire);
  body.host_policy_profile.capacity.max_effect_items++;
  const wire = encoded(body);
  const final = readInstalledHostEnvironment(parent.services, runtime, wire,
    {...profiles, calendar: false});
  assert.equal(final.wire, wire);
  assert.notEqual(final.evidenceCid, composed.evidenceCid);
  assert.notStrictEqual(final.body, composed.body);
  assert.notStrictEqual(final.raw, composed.raw);
  assert.deepEqual(final.body.host_policy_profile, body.host_policy_profile);
  const prepared = publication(final);
  assert.doesNotThrow(() => assertInstalledEnvironmentPublicationOriginal(
    parent.services, runtime, final, prepared, wire));
  assert.throws(() => assertInstalledEnvironmentPublicationOriginal(
    parent.services, runtime, final, prepared, composed.wire), {code: 'ForeignInstalledEnvironmentOriginal'});
});

test('funded Calendar admission publishes the checker carrying the original artifact', async t => {
  const parent = await parentFixture(t);
  const body = JSON.parse(baseWire);
  body.host_policy_profile.calendar = calendarSourceSelection;
  const wire = encoded(body);
  const calendarArtifact = snapshotInstalledCalendar({
    selection: calendarSourceSelection,
    tableBytes: Buffer.from(calendarSourceArtifact.slice(0, -1)),
    limits: calendarSourceArtifactLimits,
    maxSelectionWork: 10000,
  });
  const base = readInstalledHostEnvironment(parent.services, runtime, wire,
    {...profiles, calendar: true});
  const admitted = readInstalledHostEnvironment(parent.services, runtime, wire,
    {...profiles, calendar: true, calendarArtifact});
  assert.equal(admitted.wire, wire);
  const prepared = publication(admitted);
  assert.doesNotThrow(() => assertInstalledEnvironmentPublicationOriginal(
    parent.services, runtime, admitted, prepared, wire));
  assert.throws(() => assertInstalledEnvironmentPublicationOriginal(
    parent.services, runtime, base, prepared, wire), {code: 'ForeignInstalledEnvironmentOriginal'});
  await parent.close();
});

test('funded Host final admission refuses copied foreign and no-longer-current originals', async t => {
  let current = true;
  const lost = new Error('OriginalInstallationLost');
  const a = await parentFixture(t, () => {if (!current) throw lost;});
  const b = await parentFixture(t);
  const original = composeInstalledSourceEnvironment(a.services, runtime, baseWire);
  composeInstalledSourceEnvironment(b.services, runtime, baseWire);
  assert.throws(() => admitInstalledSourceFinalEnvironment(a.services, runtime, {...original}, profiles),
    {code: 'ForeignInstalledEnvironmentOriginal'});
  assert.throws(() => admitInstalledSourceFinalEnvironment(b.services, runtime, original, profiles),
    {code: 'ForeignInstalledEnvironmentOriginal'});
  try {
    current = false;
    assert.throws(() => admitInstalledSourceFinalEnvironment(a.services, runtime, original, profiles),
      error => error === lost);
  } finally {current = true;}
});

test('actual final checker refuses invalid profile identity and its parent still retires', async t => {
  const parent = await parentFixture(t);
  const original = composeInstalledSourceEnvironment(parent.services, runtime, baseWire);
  assert.throws(() => admitInstalledSourceFinalEnvironment(parent.services, runtime, original,
    {...profiles, numericProfileCid: 'invalid'}), {code: 'InstalledCheckEnvironmentConflict'});
  assert.throws(() => admitInstalledSourceFinalEnvironment(parent.services, runtime, original, profiles),
    {code: 'ForeignInstalledEnvironmentOriginal'});
  await parent.close();
});
