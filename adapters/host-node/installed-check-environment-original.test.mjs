import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {parse} from 'acorn';
import {canonicalJson, contentCid} from './local-account-config.mjs';
import * as environmentOwner from './installed-check-environment.mjs';
import {withFixtureConnector} from '../host-common/connector-manifest.fixture.mjs';
import {canonicalJson as canonicalValueJson} from '../../packages/sdk/host-port.mjs';

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

test('same-call zero or single member sorting keeps its original no-hash path', () => {
  const f = measured(), member = {index: 1}, duplicate = {...member};
  assert.deepEqual(f.merge([], []), []);
  assert.strictEqual(f.merge([member], [])[0], member);
  assert.strictEqual(f.merge([member], [duplicate])[0], duplicate);
  assert.equal(f.memberHashes.size, 0);
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

const hostSource = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const hostAst = parse(hostSource, {ecmaVersion: 'latest', sourceType: 'module'});
const compositionBlocks = [], finalBlocks = [];
const call = (statement, name) => statement.type === 'ExpressionStatement' &&
  statement.expression.type === 'CallExpression' && statement.expression.callee.name === name;
const compositionCheck = statement => statement.type === 'VariableDeclaration' &&
  statement.declarations.some(value => value.id.name === 'composedEnvironment' &&
    value.init?.callee?.name === 'composeInstalledSourceEnvironment');
const finalCheck = statement => statement.type === 'ExpressionStatement' &&
  statement.expression.type === 'AssignmentExpression' && statement.expression.left.name === 'environment' &&
  statement.expression.right.type === 'CallExpression' &&
  statement.expression.right.callee.property?.name === 'clientProgramCheckEnvironmentWithGraphProfile';
function hostBlocks(node) {
  if (node === null || typeof node !== 'object') return;
  if (node.type === 'BlockStatement') {
    if (node.body.some(compositionCheck)) compositionBlocks.push(node);
    if (node.body.some(finalCheck)) finalBlocks.push(node);
  }
  for (const value of Object.values(node)) {
    if (Array.isArray(value)) value.forEach(hostBlocks);
    else if (value !== null && typeof value === 'object') hostBlocks(value);
  }
}
hostBlocks(hostAst);
assert.equal(compositionBlocks.length, 1); assert.equal(finalBlocks.length, 1);
const compositionBlock = compositionBlocks[0], finalBlock = finalBlocks[0];
const compositionStart = compositionBlock.body.find(compositionCheck);
const compositionEnd = compositionBlock.body.find(statement => call(statement, 'verifyInstalledConnectorBindings'));
const finalStart = finalBlock.body[0];
const finalEnd = finalBlock.body.find(finalCheck);
assert(compositionStart && compositionEnd && finalStart && finalEnd);
const compositionCode = hostSource.slice(compositionStart.start, compositionEnd.end);
const finalCode = hostSource.slice(finalStart.start, finalEnd.end);
const numericWire = readFileSync(new URL('../../spec/contracts/actql-numeric-reduction.json', import.meta.url), 'utf8');
const graphWire = readFileSync(new URL('../../spec/dependencies/actql-graph-laws.json', import.meta.url), 'utf8');
const bytesCid = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
function encoded(body, raw = false) {
  const cid = raw ? bytesCid(Buffer.from(canonicalValueJson(body), 'utf8')) : contentCid(body);
  return (raw ? canonicalValueJson : canonicalJson)({...body, evidence_bundle_cid: cid});
}
function withGraphDefaults(wire) {
  const {evidence_bundle_cid: ignored, ...document} = JSON.parse(wire);
  void ignored;
  document.host_policy_profile.capacity = {max_graph_construction_edges: 1000,
    max_graph_construction_input_rows: 1000, max_graph_construction_nodes: 1000,
    ...document.host_policy_profile.capacity};
  return encoded(document);
}

// Execute only the two unchanged-scope Host construction/checking blocks.
// Model/Task/Calendar selections below are explicit DATA ports; this does not
// construct or qualify those families, the initial admission or a Host/Run.
function hostHandoff(options = {}) {
  let environmentParses = 0, environmentHashes = 0;
  const finalCalls = [], phaseCalls = [], selectedWire = options.baseWire ?? baseWire;
  const initial = admission(), finalOriginal = {};
  const moon = {...initial.moon, clientProgramCheckEnvironment(...args) {
    // The actual record still owns this same selected namespace receiver.
    assert.strictEqual(this, moon);
    const [wire, cid, ...flags] = args;
    assert.deepEqual(flags, [false, false, true, false, false, false, false]);
    const original = {}; initial.calls.push({wire, cid, flags, original}); return original;
  }, clientProgramCheckEnvironmentWithGraphProfile(wire, cid, ...flags) {
    assert.strictEqual(this, moon); finalCalls.push({wire, cid, flags});
    if (Object.hasOwn(options, 'failure')) throw options.failure;
    return options.refuse ? undefined : finalOriginal;
  }};
  const taskView = {projectEnvironmentForRuntime(runtime, wire, cid) {
    assert.strictEqual(this, taskView); assert.strictEqual(runtime, moon);
    assert.equal(JSON.parse(wire).evidence_bundle_cid, cid); phaseCalls.push('project');
    return {environmentWire: options.taskWire};
  }};
  const mockModels = options.mockTask ? {modelInstallationForRuntime(runtime, wire, cid) {
    assert.strictEqual(this, mockModels); assert.strictEqual(runtime, moon);
    assert.equal(JSON.parse(wire).evidence_bundle_cid, cid); phaseCalls.push('mock');
    return {environmentWire: options.taskWire};
  }} : undefined;
  const assets = new Map([['spec/contracts/actql-numeric-reduction.json', numericWire],
    ['spec/dependencies/actql-graph-laws.json', graphWire]]);
  const assertCurrent = () => phaseCalls.push('current');
  const context = {
    moon,
    // Explicit funded-constructor port for this lexical handoff fixture;
    // generated reservation ordering is covered by the actual bridge tests.
    composeInstalledSourceEnvironment(_services, runtime, base, source, effect) {
      phaseCalls.push('reserve');
      return environmentOwner.composeInstalledCheckEnvironmentOriginal(runtime, base, source, effect);
    },
    baseEnvironmentWire: selectedWire, sourceProfile: undefined, effectInstallation: undefined,
    installedEffect: undefined, installationServices: {}, project: options.taskWire ? {} : undefined,
    initialProjectTasks: options.mockTask ? taskView : undefined, mockModels, initialModelInstallation: undefined,
    modelProviders: undefined, assertProjectRuntime: assertCurrent,
    installedProjectOriginalsForRuntime() {return {modelRegistry: {}};},
    async loadInstalledProjectModelTasks(runtime, _project, _providers, limits) {
      assert.strictEqual(runtime, moon); assert.strictEqual(limits.assertCurrent, assertCurrent);
      phaseCalls.push('tasks'); return taskView;
    },
    installedModelEnvironment(runtime, base, wire) {
      assert.strictEqual(runtime, moon); assert.equal(base, selectedWire);
      return options.changedWire ?? wire;
    },
    reserveInstalledSourceEnvironment(_services, base, source, effect) {
      assert.equal(base, selectedWire); assert.equal(source, undefined); assert.equal(effect, undefined);
      phaseCalls.push('reserve');
    },
    verifyInstalledConnectorBindings(source, effect) {
      phaseCalls.push('bindings');
      if (Object.hasOwn(options, 'bindingFailure')) throw options.bindingFailure;
      return environmentOwner.verifyInstalledConnectorBindings(source, effect);
    },
    calendarArtifact: options.calendar, installedCalendarSelection(original) {
      assert.strictEqual(original, options.calendar); return options.calendarSelection;
    }, hostCapacityPolicy: options.hostCapacityPolicy,
    canonicalJson, canonicalValueJson, bytesCid, createHash, Buffer,
    contentCid(value) {
      if (value.version === 'actql-check-environment/0.1') environmentHashes++;
      return contentCid(value);
    },
    JSON: {parse(wire) {
      const parsed = JSON.parse(wire);
      if (parsed.version === 'actql-check-environment/0.1') environmentParses++;
      return parsed;
    }},
    preparation: {readAsset(path) {assert(assets.has(path), path); phaseCalls.push('asset'); return assets.get(path);}},
    readFile() {assert.fail('No pathname fallback');}, join() {assert.fail('No pathname fallback');}, packageRoot: 'unused',
  };
  const run = new Function(...Object.keys(context), `return async function(){
    let environmentWire, effectiveHostCapacityPolicyCid, environmentBody, environmentEvidenceCid;
    let projectTasks = initialProjectTasks, modelInstallation = initialModelInstallation;
    let environment, evidenceCid;
    ${compositionCode}
    ${finalCode}
    return {environmentWire, evidenceCid, environment, effectiveHostCapacityPolicyCid, environmentBody};
  };`)(...Object.values(context));
  return {run, finalCalls, phaseCalls, finalOriginal, get parses() {return environmentParses;},
    get hashes() {return environmentHashes;}};
}

test('actual Host handoff keeps final flags/checking and avoids reparsing its unchanged composer input', async () => {
  const f = hostHandoff(), result = await f.run();
  assert.equal(result.environmentWire, withGraphDefaults(baseWire));
  assert.equal(result.evidenceCid, JSON.parse(result.environmentWire).evidence_bundle_cid);
  assert.strictEqual(result.environment, f.finalOriginal);
  assert.equal(f.parses, 0, 'The existing owner already supplied this body and evidence CID');
  assert.equal(f.hashes, 1, 'Adding the original missing graph fields still hashes the changed body');
  assert.equal(f.finalCalls.length, 1, 'Different graph/text flags still require the final Core check');
  assert.deepEqual(f.finalCalls[0].flags, [true, true, true, true, true, false, false,
    contentCid(JSON.parse(numericWire)), contentCid(JSON.parse(graphWire))]);
  assert.equal(result.environmentBody, undefined, 'The startup-only body alias is cut before final admission');
});

test('actual Host handoff reuses exact encoding only when its complete policy input is unchanged', async () => {
  const wire = withGraphDefaults(baseWire), policy = JSON.parse(wire).host_policy_profile.capacity;
  const f = hostHandoff({baseWire: wire, hostCapacityPolicy: policy}), result = await f.run();
  assert.equal(result.environmentWire, wire);
  assert.equal(result.effectiveHostCapacityPolicyCid, contentCid(policy));
  assert.equal(f.parses, 0); assert.equal(f.hashes, 0);
  assert.equal(f.finalCalls.length, 1);
});

test('actual Host handoff does not reuse the composer body for a changed installation document', async () => {
  const changedWire = installed('changed-installation'), f = hostHandoff({changedWire});
  const result = await f.run();
  assert.equal(result.environmentWire, withGraphDefaults(changedWire));
  assert.equal(f.parses, 1); assert.equal(f.hashes, 1); assert.equal(f.finalCalls.length, 1);
  assert.deepEqual(JSON.parse(result.environmentWire).connector_catalogs.map(value => value.connector_id), ['changed-installation']);
});

test('actual Host handoff retains each selected Task output wire and its returned evidence CID', async () => {
  const taskWire = withGraphDefaults(installed('task-output'));
  for (const mockTask of [false, true]) {
    const f = hostHandoff({taskWire, mockTask}), result = await f.run();
    assert.equal(result.environmentWire, taskWire);
    assert.equal(result.evidenceCid, JSON.parse(taskWire).evidence_bundle_cid);
    assert.equal(f.parses, 1); assert.equal(f.finalCalls.length, 1);
    assert.equal(f.phaseCalls.filter(value => value === (mockTask ? 'mock' : 'project')).length, 1);
  }
});

test('actual Host Task handoff preserves binding failure before parsing its new document', async () => {
  const bindingFailure = new Error('original binding validation failed');
  const rejected = hostHandoff({taskWire: '{', bindingFailure});
  await assert.rejects(rejected.run(), error => error === bindingFailure);
  assert.deepEqual(rejected.phaseCalls, ['reserve', 'tasks', 'project', 'bindings']);
  assert.equal(rejected.finalCalls.length, 0);
  const malformed = hostHandoff({taskWire: '{'});
  await assert.rejects(malformed.run(), SyntaxError);
  assert.deepEqual(malformed.phaseCalls, ['reserve', 'tasks', 'project', 'bindings']);
  assert.equal(malformed.finalCalls.length, 0, 'Malformed Task wire refuses before final assets or admission');
});

test('actual Host handoff preserves selected Calendar semantic bytes and its distinct final flag', async () => {
  const calendarSelection = {label: 'cafe\u0301'}, calendar = {};
  const f = hostHandoff({calendar, calendarSelection}), result = await f.run();
  const {evidence_bundle_cid: ignored, ...expected} = JSON.parse(withGraphDefaults(baseWire));
  void ignored;
  expected.host_policy_profile.calendar = calendarSelection;
  assert.equal(result.environmentWire, encoded(expected, true));
  assert.equal(JSON.parse(result.environmentWire).host_policy_profile.calendar.label, 'cafe\u0301');
  assert.equal(f.finalCalls.length, 1); assert.equal(f.finalCalls[0].flags[5], true);
  assert.equal(f.parses, 0);
});

test('actual Host handoff preserves final checker refusal and original thrown values', async () => {
  const declined = hostHandoff({refuse: true});
  assert.equal((await declined.run()).environment, undefined);
  assert.equal(declined.finalCalls.length, 1);
  for (const failure of [new Error('original final check failed'), undefined, null]) {
    const f = hostHandoff({failure}); let caught = false;
    try {await f.run();} catch (error) {caught = true; assert.strictEqual(error, failure);}
    assert(caught); assert.equal(f.finalCalls.length, 1);
  }
});
