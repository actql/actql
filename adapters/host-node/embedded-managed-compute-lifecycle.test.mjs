import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';

// Selected actual Host statements/methods with explicit original ports. These
// counters prove consumer order/custody, not physical admission or a full Host.
const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const declared = name => {
  const matches = ast.body.map(node => node.type === 'ExportNamedDeclaration' ? node.declaration : node)
    .filter(node => node?.type === 'FunctionDeclaration' && node.id.name === name);
  assert.equal(matches.length, 1, name);
  return matches[0];
};
const text = node => source.slice(node.start, node.end);
const AsyncFunction = Object.getPrototypeOf(async function() {}).constructor;
function visit(node, callback) {
  if (node === null || typeof node !== 'object') return;
  if (typeof node.type === 'string') callback(node);
  for (const child of Object.values(node)) {
    if (Array.isArray(child)) for (const value of child) visit(value, callback);
    else if (child && typeof child === 'object') visit(child, callback);
  }
}
function opening() {
  let statements;
  visit(declared('openInstalledHost').body, node => {
    if (node.type !== 'BlockStatement') return;
    const index = node.body.findIndex(value => value.type === 'ExpressionStatement' &&
      value.expression.type === 'AssignmentExpression' && value.expression.left.name === 'journal' &&
      value.expression.right.type === 'AwaitExpression' &&
      value.expression.right.argument.callee?.name === 'openHostRequestJournal');
    if (index >= 0) statements = node.body.slice(index, index + 3);
  });
  assert(statements);
  assert.equal(statements[1].type, 'IfStatement');
  assert.equal(statements[2].declarations[0].id.name, 'originalRequestPreparation');
  return new AsyncFunction('preparation', 'originalSourcePreparation', 'openHostRequestJournal',
    'journalOptions', 'let journal;' + statements.map(text).join('\n') +
    ';return {journal, originalRequestPreparation};');
}

test('actual Host acquires its same Journal before Compute and before publishing the SDK receiver', async () => {
  const journal = {}, receiver = {}, options = {}, log = [];
  const preparation = {
    async prepareResultPublication() {assert.deepEqual(log, ['journal']); log.push('result');},
    async prepareManagedCompute() {assert.deepEqual(log, ['journal', 'result']); log.push('compute');},
    requestPreparation() {assert.deepEqual(log, ['journal', 'result', 'compute']); log.push('receiver'); return receiver;},
  };
  const result = await opening()(preparation, undefined,
    async value => {assert.strictEqual(value, options); log.push('journal'); return journal;}, options);
  assert.strictEqual(result.journal, journal);
  assert.strictEqual(result.originalRequestPreparation, receiver);
  assert.deepEqual(log, ['journal', 'result', 'compute', 'receiver']);
});

test('legacy unprepared and existing Mock Source entries do not acquire a Compute replacement', async () => {
  const journal = {}, source = {}, open = opening();
  assert.deepEqual(await open(undefined, undefined, async () => journal, {}),
    {journal, originalRequestPreparation: undefined});
  const preparation = {
    prepareResultPublication() {},
    prepareManagedCompute() {assert.fail('Source must retain its original joint purpose');},
    requestPreparation() {return source;},
  };
  const result = await open(preparation, source, async () => journal, {});
  assert.strictEqual(result.originalRequestPreparation, source);
});

function lifecycle({factory, beforeChild, beforeChildClose, current = () => {}, retire = () => {},
  runtime = {}, source, controlClose = async () => ({pending: false})}) {
  const declarations = declared('connectEmbeddedLocal').body.body
    .filter(node => node.type === 'VariableDeclaration').flatMap(node => node.declarations);
  const initial = declarations.find(node => node.id.name === 'initialControl');
  const preparation = declarations.find(node => node.id.name === 'preparation');
  assert(initial && preparation);
  const properties = preparation.init.arguments[0].properties;
  const names = ['prepareManagedCompute', 'requestPreparation', 'sourcePreparation',
    'bindSourceRequest', 'prepareManagedComputeRun'];
  const methods = names.map(name => {
    const property = properties.find(node => node.key.name === name); assert(property, name); return text(property);
  });
  const originals = {host: {}, installation: {}, generation: {}, supplier: {}, moduleLifetime: {}};
  const ports = {
    prepareManagedComputeInstallation: held => {assert.strictEqual(held, originals); return factory();},
    assertInitialControlHostPreparation: held => {assert.strictEqual(held, originals); current();},
    assertManagedComputeInstallationCurrent: (value, held) => {assert.strictEqual(held, originals); current(value);},
    assertSourceManagedInstallationCurrent: (value, held) => {
      assert.strictEqual(value, source); assert.strictEqual(held, originals); current(value);
    },
    clientOperationError: code => Object.assign(new Error(code), {code}),
    retirePreparationReferences: retire, controlClose, originals, runtime,
    checked: value => value,
    beforeChild, beforeChildClose, source,
  };
  return new Function(...Object.keys(ports), `
    let computeManaged, computeManagedClose, computeManagedFlight, observedClose;
    let resultPublication, resultPublicationClose, resultPublicationFlight;
    let sourceManaged=source??beforeChild, sourceManagedClose=source?.close??beforeChildClose, hostJournal;
    let moon=runtime, mockPreparation=source===undefined?undefined:{}, projectSourcePreparation;
    let control={}, duty, originalInstallation=originals.installation;
    const host=originals.host, record={}, adopted=true;
    const profiles={bindSourceRequest(...args){record.lineage=args;}};
    const initialControl=${text(initial.init)};
    const preparation={${methods.join(',\n')}};
    return {preparation,initialControl,record};
  `)(...Object.values(ports));
}

test('same Host Compute preparation is one sticky flight and retains its original before current refusal', async () => {
  let factoryCalls = 0, closes = 0, controls = 0;
  const marker = new Error('OriginalCurrentRefusal');
  const raw = {close() {assert.strictEqual(this, raw); closes++; return {pending: false};}};
  const f = lifecycle({factory: async () => {factoryCalls++; return raw;},
    current: value => {if (value === raw) throw marker;}, controlClose: () => {controls++; return {pending: false};}});
  const first = f.preparation.prepareManagedCompute(), second = f.preparation.prepareManagedCompute();
  assert.strictEqual(first, second);
  await assert.rejects(first, error => error === marker);
  assert.strictEqual(f.record.computeManaged, raw);
  assert.strictEqual(f.preparation.prepareManagedCompute(), first);
  assert.equal(factoryCalls, 1);
  await f.initialControl.close();
  assert.equal(closes, 1); assert.equal(controls, 1);
});

test('captured Compute close cannot be replaced during a preceding child await', async () => {
  let release, entered, replacementCalls = 0, originalCloses = 0;
  const wait = new Promise(resolve => {release = resolve;});
  const enteredFlight = new Promise(resolve => {entered = resolve;});
  const raw = {close() {assert.strictEqual(this, raw); originalCloses++; return {pending: false};}};
  const f = lifecycle({factory: async () => raw, beforeChild: {},
    beforeChildClose: async () => {entered(); await wait; return {pending: false};}});
  await f.preparation.prepareManagedCompute();
  const closing = f.initialControl.close();
  await enteredFlight;
  raw.close = () => {replacementCalls++; return {pending: false};};
  release(); await closing;
  assert.equal(originalCloses, 1); assert.equal(replacementCalls, 0);
});

test('unobserved close getter failure retains the original and permits its same cleanup retry', async () => {
  const marker = new Error('UnobservedClose'); let reads = 0, closes = 0;
  const raw = {get close() {
    if (++reads === 1) throw marker;
    return function() {assert.strictEqual(this, raw); closes++; return {pending: false};};
  }};
  const f = lifecycle({factory: async () => raw});
  await assert.rejects(f.preparation.prepareManagedCompute(), error => error === marker);
  assert.strictEqual(f.record.computeManaged, raw);
  await f.initialControl.close();
  assert.equal(reads, 2); assert.equal(closes, 1);
});

test('pending Compute close retains its original and blocks final control retirement', async () => {
  let closes = 0, controls = 0;
  const raw = {close() {closes++; return {pending: closes === 1};}};
  const f = lifecycle({factory: async () => raw, controlClose: () => {controls++; return {pending: false};}});
  await f.preparation.prepareManagedCompute();
  await assert.rejects(f.initialControl.close(), error => error.code === 'InstalledComputePreparationCleanupPending');
  assert.equal(controls, 0); assert.strictEqual(f.record.computeManaged, raw);
  await f.initialControl.close();
  assert.equal(closes, 2); assert.equal(controls, 1);
});

test('Compute SDK lineage is the same view while Mock Source selection stays absent', async () => {
  const raw = {close: () => ({pending: false})};
  const f = lifecycle({factory: async () => raw});
  await f.preparation.prepareManagedCompute();
  assert.strictEqual(f.preparation.requestPreparation(), raw);
  assert.strictEqual(f.preparation.sourcePreparation(), undefined);
  const original = {}, derived = {};
  f.preparation.bindSourceRequest(original, derived);
  assert.strictEqual(f.record.lineage[3], original);
  assert.strictEqual(f.record.lineage[4], derived);
  await f.initialControl.close();
  assert.throws(() => f.preparation.requestPreparation(), error => error.code === 'NodeManagedRunAdmissionUnavailable');
});

function managedRunPorts(overrides = {}) {
  const admission = {}, value = {}, log = [];
  const runtime = {
    clientProgramNodeManagedRunPrepare(original, prepared) {log.push(['prepare', original, prepared]); return admission;},
    clientProgramInstalledManagedRunBegin(held, prepared, request) {
      assert.strictEqual(held, admission); log.push(['begin', prepared, request]); return value;
    },
    clientProgramInstalledManagedRunCheck(held, prepared, request) {
      assert.strictEqual(held, value); log.push(['check', prepared, request]);
    },
    clientProgramInstalledManagedRunRetire(held) {assert.strictEqual(held, value); log.push(['retire']);},
    clientProgramNodeManagedRunCleanup(held) {assert.strictEqual(held, admission); log.push(['cleanup']);},
    ...overrides,
  };
  return {runtime, admission, value, log};
}

test('actual preparation binds one original Run and closes it before its same Root', async () => {
  const p = managedRunPorts(), original = {}, prepared = {}, request = {};
  let preparations = 0;
  const raw = {prepareRun(value) {assert.strictEqual(value, prepared); preparations++; return original;},
    close() {assert.deepEqual(p.log.at(-1), ['retire']); return {pending: false};}};
  const f = lifecycle({runtime: p.runtime, factory: async () => raw});
  await f.preparation.prepareManagedCompute();
  const value = f.preparation.prepareManagedComputeRun(p.runtime, prepared, request);
  assert.strictEqual(value, p.value);
  assert.strictEqual(f.preparation.prepareManagedComputeRun(p.runtime, prepared, request), value);
  assert.equal(preparations, 1);
  assert.strictEqual(f.record.computeRuns.get(prepared).original, original);
  assert.throws(() => f.preparation.prepareManagedComputeRun({}, prepared, request),
    error => error.code === 'ForeignInstalledComputePreparation');
  // Cleanup is the captured original, not the later property value.
  p.runtime.clientProgramInstalledManagedRunRetire = () => assert.fail('replacement retire');
  await f.initialControl.close();
  assert.equal(preparations, 1);
});

test('failed begin retains the admission and original cleanup through Unknown without reissuing', async () => {
  const marker = new Error('OriginalBeginUnknown'), pending = new Error('OriginalCleanupPending');
  const p = managedRunPorts({clientProgramInstalledManagedRunBegin() {throw marker;}});
  let preparations = 0, rootCloses = 0, cleanups = 0;
  p.runtime.clientProgramNodeManagedRunCleanup = function(value) {
    assert.strictEqual(this, p.runtime); assert.strictEqual(value, p.admission);
    if (++cleanups === 1) throw pending;
  };
  const raw = {prepareRun() {preparations++; return {};}, close() {rootCloses++; return {pending: false};}};
  const f = lifecycle({runtime: p.runtime, factory: async () => raw});
  await f.preparation.prepareManagedCompute();
  const prepared = {}, request = {};
  assert.throws(() => f.preparation.prepareManagedComputeRun(p.runtime, prepared, request), error => error === marker);
  assert.strictEqual(f.record.computeRuns.get(prepared).admission, p.admission);
  assert.throws(() => f.preparation.prepareManagedComputeRun(p.runtime, prepared, request), error => error === marker);
  p.runtime.clientProgramNodeManagedRunCleanup = () => assert.fail('replacement cleanup');
  await assert.rejects(f.initialControl.close(), error => error === pending);
  assert.equal(rootCloses, 0); assert.equal(preparations, 1);
  await f.initialControl.close();
  assert.equal(rootCloses, 1); assert.equal(preparations, 1); assert.equal(cleanups, 2);
});

test('same ordinary Host retains separate Run records for successive prepared requests', async () => {
  const a = {}, b = {}, requests = new Map([[a, {}], [b, {}]]), retired = [];
  const runtime = {
    clientProgramNodeManagedRunPrepare(original, prepared) {assert.strictEqual(original, prepared); return prepared;},
    clientProgramInstalledManagedRunBegin(admission, prepared, request) {
      assert.strictEqual(admission, prepared); assert.strictEqual(request, requests.get(prepared)); return prepared;
    },
    clientProgramInstalledManagedRunCheck(run, prepared, request) {
      assert.strictEqual(run, prepared); assert.strictEqual(request, requests.get(prepared));
    },
    clientProgramInstalledManagedRunRetire(run) {retired.push(run);},
    clientProgramNodeManagedRunCleanup() {assert.fail('No failed admission');},
  };
  const raw = {prepareRun: prepared => prepared, close: () => ({pending: false})};
  const f = lifecycle({runtime, factory: async () => raw});
  await f.preparation.prepareManagedCompute();
  for (const prepared of [a, b, a]) assert.strictEqual(
    f.preparation.prepareManagedComputeRun(runtime, prepared, requests.get(prepared)), prepared);
  assert.equal(f.record.computeRuns.size, 2);
  await f.initialControl.close();
  assert.deepEqual(retired, [a, b]);
});

test('Source Host opens a source-free Run on its same joint parent and retires it before Root close', async () => {
  const p = managedRunPorts(), original = {}, prepared = {}, request = {};
  let preparations = 0, rootCloses = 0;
  const source = {prepareRun(value) {assert.strictEqual(value, prepared); preparations++; return original;},
    close() {assert.strictEqual(this, source); assert.deepEqual(p.log.at(-1), ['retire']);
      rootCloses++; return {pending: false};}};
  const f = lifecycle({runtime: p.runtime, source,
    factory: () => assert.fail('No replacement Compute installation')});
  assert.strictEqual(f.preparation.requestPreparation(), source);
  assert.strictEqual(f.preparation.sourcePreparation(), source);
  assert.strictEqual(f.preparation.prepareManagedComputeRun(p.runtime, prepared, request), p.value);
  assert.strictEqual(f.preparation.prepareManagedComputeRun(p.runtime, prepared, request), p.value);
  assert.equal(preparations, 1);
  await f.initialControl.close();
  assert.equal(rootCloses, 1);
});

test('Source Host retains failed source-free start cleanup without replacing its original parent', async () => {
  const marker = new Error('OriginalSourceHostBeginUnknown');
  const p = managedRunPorts({clientProgramInstalledManagedRunBegin() {throw marker;}});
  let cleanups = 0, rootCloses = 0, ready = false;
  p.runtime.clientProgramNodeManagedRunCleanup = function(admission) {
    assert.strictEqual(this, p.runtime); assert.strictEqual(admission, p.admission); cleanups++;
    if (!ready) throw marker;
  };
  const source = {prepareRun: () => ({}), close() {rootCloses++; return {pending: false};}};
  const f = lifecycle({runtime: p.runtime, source}), prepared = {}, request = {};
  assert.throws(() => f.preparation.prepareManagedComputeRun(p.runtime, prepared, request), error => error === marker);
  await assert.rejects(f.initialControl.close(), error => error === marker);
  assert.equal(rootCloses, 0);
  ready = true;
  await f.initialControl.close();
  assert.equal(cleanups, 2); assert.equal(rootCloses, 1);
});

const dispatchSource = readFileSync(new URL('./client-dispatch-owner.mjs', import.meta.url), 'utf8');
const dispatchAst = parse(dispatchSource, {ecmaVersion: 'latest', sourceType: 'module'});
function sourceFreeOpening() {
  const matches = [];
  visit(dispatchAst, node => {
    if (node.type === 'IfStatement' && dispatchSource.slice(node.test.start, node.test.end) ===
        '!acquiring && !inferring && !serializing') matches.push(node);
  });
  assert.equal(matches.length, 1);
  return new Function('held', 'moon', 'preparedProgram', 'requested', 'retainedRelationOutput', 'checked', `
    const acquiring=false, inferring=false, serializing=false;
    const managedComputeRequired=true;
    const registry='registry',values='values',fragment='fragment',ordered='ordered',entry={};let setup;
    ${dispatchSource.slice(matches[0].start, matches[0].end)}
    return {setup,entry};`);
}

test('actual dispatcher opens its opaque Run without the legacy accounting constructor', () => {
  const original = {}, prepared = {}, request = {}, setup = {}, open = sourceFreeOpening();
  for (const retained of [false, true]) {
    const moon = {clientProgramOpenInstalledManagedSourceFreeHost(...args) {
      assert.deepEqual(args, [original, prepared, request, 'registry', 'values', 'fragment', 'ordered', retained]);
      return setup;
    }, clientProgramOpenSourceFreeLocalHost() {assert.fail('accounting fallback');},
    clientProgramOpenSourceFreeLocalRetainedHost() {assert.fail('accounting fallback');}};
    const result = open({managedRun: original}, moon, prepared, request, retained, value => value);
    assert.strictEqual(result.setup, setup); assert.strictEqual(result.entry.pendingSetup, setup);
  }
});

test('actual dispatcher propagates missing/foreign/parked original refusal without fallback', () => {
  const marker = new Error('OriginalResourceParked'), original = {}, open = sourceFreeOpening();
  const legacy = () => assert.fail('accounting fallback');
  assert.throws(() => open({}, {clientProgramOpenSourceFreeLocalHost: legacy}, {}, {}, false,
    value => value), /InstalledManagedComputeRunUnavailable/);
  assert.throws(() => open({managedRun: original}, {clientProgramOpenSourceFreeLocalHost: legacy}, {}, {}, false,
    value => value), /InstalledManagedComputeHostUnavailable/);
  assert.throws(() => open({managedRun: original}, {clientProgramOpenSourceFreeLocalHost: legacy,
    clientProgramOpenInstalledManagedSourceFreeHost() {throw marker;}}, {}, {}, false, value => value),
    error => error === marker);
});

function singleSourceOpening() {
  const matches = [];
  visit(dispatchAst, node => {
    if (node.type === 'IfStatement' && node.test.type === 'Identifier' &&
        node.test.name === 'singleAccounted' && dispatchSource.slice(node.start, node.end)
          .includes('clientProgramPrepareSingleCapturedLocalInstalledLedger')) matches.push(node);
  });
  assert.equal(matches.length, 1);
  return new AsyncFunction('installedSource', 'moon', 'preparedProgram', 'requested', 'checked', `
    const singleAccounted=true, checkpoints=undefined, submission={},held={preparedSource:{}};
    const prepareAcquisition=()=>held.preparedSource;
    const registry='registry',values='values',fragment='fragment',ordered='ordered',entry={};let ledger;
    ${dispatchSource.slice(matches[0].start, matches[0].end)}
    return {ledger,entry};`);
}

test('single Source dispatcher keeps the original managed parent and singleton capacity arrays', async () => {
  const run = {}, capacity = {}, prepared = {}, request = {}, ledger = {}, open = singleSourceOpening();
  const source = {ledgerCapacity: () => ({managedRun: run, capacity, transferBytes: 3n, executionBytes: 5n})};
  const result = await open(source, {clientProgramInstalledManagedRunPrepareLedger(...args) {
    assert.deepEqual(args, [run, prepared, request, [capacity], [3n], [5n],
      'registry', 'values', 'fragment', 'ordered']); return ledger;
  }, clientProgramPrepareSingleCapturedLocalInstalledLedger() {assert.fail('Accounting fallback');}},
  prepared, request, value => value);
  assert.strictEqual(result.ledger, ledger); assert.strictEqual(result.entry.acquisitionLedger, ledger);
});

test('single Source dispatcher preserves managed missing/parked refusal instead of scalar fallback', async () => {
  const open = singleSourceOpening(), marker = new Error('OriginalResourceParked');
  const source = {ledgerCapacity: () => ({managedRun: {}, capacity: {}, transferBytes: 3n, executionBytes: 5n})};
  const legacy = () => assert.fail('Accounting fallback');
  await assert.rejects(open(source, {clientProgramPrepareSingleCapturedLocalInstalledLedger: legacy},
    {}, {}, value => value), /InstalledSingleSourceOriginalRunUnavailable/u);
  await assert.rejects(open(source, {clientProgramPrepareSingleCapturedLocalInstalledLedger: legacy,
    clientProgramInstalledManagedRunPrepareLedger() {throw marker;}}, {}, {}, value => value),
  error => error === marker);
});

test('unprepared single Source retains its existing accounting constructor and argument shape', async () => {
  const open = singleSourceOpening(), capacity = {}, prepared = {}, ledger = {};
  const source = {ledgerCapacity: () => ({capacity, transferBytes: 3n, executionBytes: 5n})};
  const result = await open(source, {clientProgramPrepareSingleCapturedLocalInstalledLedger(...args) {
    assert.deepEqual(args, [prepared, capacity, 3n, 5n, 'registry', 'values', 'fragment', 'ordered']);
    return ledger;
  }, clientProgramInstalledManagedRunPrepareLedger() {assert.fail('No managed original');}},
  prepared, {}, value => value);
  assert.strictEqual(result.ledger, ledger);
});
