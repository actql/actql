import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';

// Selected actual Host statements/methods with explicit original ports. These
// counters prove consumer order/custody, not physical admission or a full Host.
const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const exported = name => ast.body.find(node => node.type === 'ExportNamedDeclaration' &&
  node.declaration?.type === 'FunctionDeclaration' && node.declaration.id.name === name).declaration;
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
  visit(exported('openInstalledHost').body, node => {
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
    async prepareManagedCompute() {assert.deepEqual(log, ['journal']); log.push('compute');},
    requestPreparation() {assert.deepEqual(log, ['journal', 'compute']); log.push('receiver'); return receiver;},
  };
  const result = await opening()(preparation, undefined,
    async value => {assert.strictEqual(value, options); log.push('journal'); return journal;}, options);
  assert.strictEqual(result.journal, journal);
  assert.strictEqual(result.originalRequestPreparation, receiver);
  assert.deepEqual(log, ['journal', 'compute', 'receiver']);
});

test('legacy unprepared and existing Mock Source entries do not acquire a Compute replacement', async () => {
  const journal = {}, source = {}, open = opening();
  assert.deepEqual(await open(undefined, undefined, async () => journal, {}),
    {journal, originalRequestPreparation: undefined});
  const preparation = {
    prepareManagedCompute() {assert.fail('Source must retain its original joint purpose');},
    requestPreparation() {return source;},
  };
  const result = await open(preparation, source, async () => journal, {});
  assert.strictEqual(result.originalRequestPreparation, source);
});

function lifecycle({factory, beforeChild, beforeChildClose, current = () => {}, retire = () => {},
  controlClose = async () => ({pending: false})}) {
  const declarations = exported('connectEmbeddedLocal').body.body
    .filter(node => node.type === 'VariableDeclaration').flatMap(node => node.declarations);
  const initial = declarations.find(node => node.id.name === 'initialControl');
  const preparation = declarations.find(node => node.id.name === 'preparation');
  assert(initial && preparation);
  const properties = preparation.init.arguments[0].properties;
  const names = ['prepareManagedCompute', 'requestPreparation', 'sourcePreparation', 'bindSourceRequest'];
  const methods = names.map(name => {
    const property = properties.find(node => node.key.name === name); assert(property, name); return text(property);
  });
  const originals = {host: {}, installation: {}, generation: {}, supplier: {}, moduleLifetime: {}};
  const ports = {
    prepareManagedComputeInstallation: held => {assert.strictEqual(held, originals); return factory();},
    assertInitialControlHostPreparation: held => {assert.strictEqual(held, originals); current();},
    assertManagedComputeInstallationCurrent: (value, held) => {assert.strictEqual(held, originals); current(value);},
    assertSourceManagedInstallationCurrent: () => {assert.fail('Compute is not Source');},
    clientOperationError: code => Object.assign(new Error(code), {code}),
    retirePreparationReferences: retire, controlClose, originals,
    beforeChild, beforeChildClose,
  };
  return new Function(...Object.keys(ports), `
    let computeManaged, computeManagedClose, computeManagedFlight, observedClose;
    let sourceManaged=beforeChild, sourceManagedClose=beforeChildClose, hostJournal;
    let mockPreparation, control={}, duty, originalInstallation=originals.installation;
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
