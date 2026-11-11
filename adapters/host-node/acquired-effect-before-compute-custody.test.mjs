import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';

// Execute the existing coordination with explicit original-owner ports. These
// controls do not instantiate a Runtime or issue a physical Host/FD receipt.
const text = readFileSync(new URL('./acquired-effect-computation.mjs', import.meta.url), 'utf8');
const declarations = new Map();
function visit(node) {
  if (!node || typeof node !== 'object') return;
  if (node.type === 'VariableDeclarator' && node.id.type === 'Identifier') {
    if (declarations.has(node.id.name)) declarations.set(node.id.name, undefined);
    else declarations.set(node.id.name, node);
  }
  for (const value of Object.values(node)) {
    for (const child of Array.isArray(value) ? value : [value]) visit(child);
  }
}
visit(parse(text, {ecmaVersion: 'latest', sourceType: 'module'}));
function declaration(name, optional = false) {
  const node = declarations.get(name);
  if (optional && !node) return '';
  assert(node, `Unique original ${name}`);
  return `const ${text.slice(node.start, node.end)};`;
}

function fixture({entered = false, retired = true, cleanupFailure, returnedHost = true} = {}) {
  const events = [], managedRun = {}, checkedHost = returnedHost ? {} : undefined;
  const primary = new Error('OriginalSourceTaskBindingFailure');
  let released = retired;
  const ports = {managedRun, checkedHost, entered,
    captures: [{async close() {events.push('source');}}],
    moon: {
      clientProgramRetireInstalledEffectCapturedConsumers(original) {
        assert.strictEqual(original, managedRun);events.push('parent');
        if (cleanupFailure && !released) throw cleanupFailure;
        return {$tag: 1, _0: released};
      },
      clientProgramRefreshAcquiredEffectCleanup(original) {
        assert.strictEqual(original, checkedHost);events.push('refresh');return true;
      },
    },
    checked(result) {assert.equal(result.$tag, 1);return result._0;},
    async cleanupInfer() {events.push('model');return true;},
    observeUsage() {}, sourceContinuation: {async close() {events.push('continuation');}},
  };
  const body = `let execution,recovery,inferCapture,inferOperation,modelContinuation,modelToken,
    modelGroup,contentFamilyCleanup,contentFamily,contentRecovery,restoredModelOutput,keyedCleanup,
    originalPreparation,originalPreparationRetained=false,restoredModelHostAttempted=false;
    let computeEntered=entered,hostOpenAttempted=true;
    let unresolved=true,pending=true,settled=true,closed=false;
    ${declaration('retireUnenteredCompute', true)}
    ${declaration('custody')}
    return custody;`;
  const custody = new Function(...Object.keys(ports), body)(...Object.values(ports));
  return {custody, primary, events, release() {released = true;}};
}

test('a pre-Compute binding failure retires the same parent before its first Source close', async () => {
  const f = fixture();
  assert.equal(await f.custody.cleanup(), false, 'settlement cannot replace first close');
  await f.custody.close();
  assert.equal(await f.custody.cleanup(), true);
  assert.equal(f.custody.cleanupPending(), false);
  assert.equal(f.events[0], 'parent');
  assert.equal(f.events.filter(value => value === 'parent').length, 1);
  assert.equal(f.events.filter(value => value === 'source').length, 1);
  assert(f.events.indexOf('source') > f.events.indexOf('parent'));
});

test('a partial Host constructor without a returned wrapper keeps its actual parent retirement duty', async () => {
  const f = fixture({returnedHost: false});
  await f.custody.close();
  assert.equal(await f.custody.cleanup(), true);
  assert.equal(f.events[0], 'parent');
  assert.equal(f.events.filter(value => value === 'parent').length, 1);
  assert.equal(f.events.filter(value => value === 'source').length, 1);
  assert(!f.events.includes('refresh'));
});

for (const mode of ['pending', 'throw']) test(`pre-Compute ${mode} retirement retains Source and original cleanup responsibility`, async () => {
  const cleanupFailure = mode === 'throw' ? new Error('OriginalRetirementUnknown') : undefined;
  const f = fixture({retired: false, cleanupFailure});
  if (cleanupFailure) await assert.rejects(f.custody.close(), error => error === cleanupFailure);
  else await f.custody.close();
  assert.equal(f.custody.cleanupPending(), true);
  assert(!f.events.includes('source'));assert(!f.events.includes('model'));
  f.release();
  assert.equal(await f.custody.cleanup(), true);
  assert.equal(f.custody.cleanupPending(), false);
  assert.equal(f.events.filter(value => value === 'source').length, 1);
});

test('an entered Compute without its actual handoff remains unresolved', async () => {
  const f = fixture({entered: true});
  await f.custody.close();
  assert.equal(await f.custody.cleanup(), false);
  assert.equal(f.custody.cleanupPending(), true);
  assert(!f.events.includes('parent'));assert(!f.events.includes('source'));
});
