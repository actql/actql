import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';
import {canonicalJson, contentCid} from './local-account-config.mjs';
import * as environmentOwner from './installed-check-environment.mjs';
import {withFixtureConnector} from '../host-common/connector-manifest.fixture.mjs';

// Actual composer bodies with explicit admission replies. No generated Common,
// Resource, Host, Account, provider or installed execution is represented.
const source = readFileSync(new URL('./installed-check-environment.mjs', import.meta.url), 'utf8');
const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const declarations = ast.body.flatMap(node => node.type === 'ImportDeclaration' ? []
  : [node.type === 'ExportNamedDeclaration' ? node.declaration : node]);
const body = declarations.map(node => source.slice(node.start, node.end)).join('\n');
const baseWire = readFileSync(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8').trimEnd();
function installed(connector) {
  const document = JSON.parse(baseWire);
  withFixtureConnector(document, `connector://${connector}/records`);
  delete document.evidence_bundle_cid;
  return canonicalJson({...document, evidence_bundle_cid: contentCid(document)});
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
function measured() {
  let parses = 0, environmentHashes = 0;
  const memberHashes = new Map();
  const selected = new Function('canonicalJson', 'contentCid', 'JSON', 'Buffer', `${body}
    return {wire: composeInstalledCheckEnvironment, merge: mergeMembers};`)(canonicalJson,
    value => {
      if (value.version === 'actql-check-environment/0.1') environmentHashes++;
      memberHashes.set(value, (memberHashes.get(value) ?? 0) + 1);
      return contentCid(value);
    }, {parse(wire) {parses++; return JSON.parse(wire);}}, Buffer);
  return {...selected, get parses() {return parses;}, get environmentHashes() {return environmentHashes;}, memberHashes};
}

test('composer does not reparse or rehash its own newly encoded Environment', () => {
  const f = measured(), {moon, calls} = admission();
  const wire = f.wire(moon, baseWire, installed('source'), installed('effect'));
  assert.equal(typeof wire, 'string');
  assert.equal(f.parses, 3, 'Only the three independently supplied documents are parsed');
  assert.equal(f.environmentHashes, 4, 'Three input CIDs and the newly composed body are hashed once');
  assert.equal(calls.length, 4, 'Independent inputs and final composed body still reach admission');
  const result = JSON.parse(wire);
  assert.deepEqual(result.connector_catalogs.map(value => value.connector_id).sort(), ['effect', 'source']);
});

test('same-call member sorting computes one CID per distinct retained member', () => {
  const f = measured(), members = Array.from({length: 32}, (_, index) => ({index}));
  const duplicate = {...members[7]}, right = [duplicate];
  const output = f.merge(members, right);
  assert.equal(output.length, members.length);
  assert.equal(f.memberHashes.size, members.length);
  assert([...f.memberHashes.values()].every(count => count === 1), 'Comparator cannot rehash retained members');
  assert.equal(f.memberHashes.has(members[7]), false, 'The original last-equal-body selection is preserved');
  assert.equal(output.includes(duplicate), true);
  const expected = [...members.slice(0, 7), duplicate, ...members.slice(8)]
    .map(member => ({member, cid: contentCid(member)}))
    .sort((a, b) => a.cid < b.cid ? -1 : a.cid > b.cid ? 1 : 0).map(({member}) => member);
  assert.deepEqual(output, expected);
});

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
