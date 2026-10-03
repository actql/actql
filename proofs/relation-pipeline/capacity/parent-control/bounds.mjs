import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { currentSlotsCeiling } from '../backing/model.mjs';
import { parentStartupLayout } from '../backing/parent-layout.mjs';
const inventory = JSON.parse(readFileSync(new URL('./allocations.json', import.meta.url)));
function fields(source, name) {
  const body = source.match(new RegExp(`(?:priv )?struct ${name} \\{\\n([\\s\\S]*?)\\n\\}`))?.[1];
  assert(body, `Missing parent accounting state ${name}`);
  const clean = body.replace(/\/\/[^\n]*/g, '');
  const matches = [...clean.matchAll(/^  (?:mut )?(\w+)\s*:/gm)];
  return matches.map((m, i) => ({ name: m[1], type: clean.slice(m.index + m[0].length,
    matches[i + 1]?.index ?? clean.length).trim().replace(/\s+/g, ' ') }));
}
export function checkParentCensus(read) {
  assert.equal(inventory.version, 'actql-native-parent-allocation-census/0.1');
  for (const state of inventory.sourceFields) {
    assert.deepEqual(fields(read(state.path).toString(), state.struct), state.fields,
      `Unreviewed parent/edge field or type ${state.struct}`);
  }
  const source = read('src/connectors/local/selected_relation_provider.mbt').toString();
  const constructor = source.match(/fn bounded_relation_chain_execution\([\s\S]*?\nfn selected_relation_provider\(/)?.[0];
  assert(constructor, 'Missing chain allocation constructor');
  assert.deepEqual([...constructor.matchAll(/^  let (\w+)(?:\s*:[^=\n]+)?\s*=\s*Ref\(/gm)].map(m => m[1]),
    inventory.chainReferences, 'Changed parent Ref ownership');
  assert.deepEqual(constructor.split('\n').filter(line => /^  let \w+(?:\s*:[^=\n]+)?\s*=\s*Ref\(/.test(line))
    .map(line => line.trim().replace(/\s+/g, ' ')), inventory.chainReferenceDeclarations, 'Changed parent Ref source representation');
  const issues = read('src/connectors/local/managed_provider.mbt').toString()
    .match(/enum ManagedProviderWorkIssue \{\n([\s\S]*?)\n\}/)?.[1];
  assert(issues);
  assert.deepEqual(issues.trim().split('\n').map(line => line.trim()), inventory.workIssueVariants,
    'Reported-work scalar payload premise changed');
  const selection = source.match(/for\s+provider in \[([\s\S]*?)\]\s*\{/);
  assert(selection, 'Missing complete provider construction list');
  assert.deepEqual([...selection[1].matchAll(/\b(\w+_provider)\(/g)].map(m => m[1]),
    inventory.providerConstructors, 'Unreviewed provider-selection allocation');
  assert.equal(inventory.included.length, 7, 'Incomplete parent/edge allocation roles');
  return inventory;
}
// This is a retained-core component, not a whole-parent bound. Its explicit
// Ref premise is one declared field of at most eight payload bytes in the
// pinned primitive/reference ABI (header eight, total at most sixteen).
export function retainedParentCoreBound(count) {
  assert(Number.isSafeInteger(count) && count >= 2 && count <= 2147483647,
    'Outside admitted Int32 serial-chain length');
  const layout = parentStartupLayout();
  const fixed = {
    references: 10n * (8n + 8n), owner: BigInt(layout.blocks.owner),
    callbacks: BigInt(layout.callbacks), environment: BigInt(layout.blocks.startEnvironment),
    reportedWorkOverlap: 2n * 16n,
    // Cleanup replaces [] while the old owner is still held by the store.
    arrayOwnersOverlap: 2n * 24n,
    backingHeadersOverlap: 2n * 8n,
  };
  const slots = currentSlotsCeiling(count, 1);
  const backingPayloadOverlap = 2n * 8n * slots;
  const bytes = Object.values(fixed).reduce((sum, value) => sum + value, backingPayloadOverlap);
  assert(bytes <= 9223372036854775807n, 'Parent core expression overflow');
  return { subject: 'retained native parent core only', count, slots, fixed,
    backingPayloadOverlap, bytes, unit: 'requested object header and source/ABI payload bytes',
    premises: ['ten single-field primitive/reference Refs have payload at most eight bytes',
      'immutable callback/environment layouts match the pinned source ABI',
      'at most two reported-work records coexist during replacement',
      'at most two children array owners and two backing buffers coexist',
      'children high-water length is at most the input step count'],
    fullParentUpper: false, completePipelineUpper: false };
}
export const encodeCoreBound = bound => JSON.parse(JSON.stringify(bound,
  (_, value) => typeof value === 'bigint' ? value.toString() : value));
export function inspectParentCorePhases(testCase, startup, facts, target) {
  assert.equal(target, 'native', 'Retained-core ABI is native only');
  const count = testCase.steps.length, bound = retainedParentCoreBound(count);
  assert.equal(startup.count, count);
  const token = value => assert(typeof value === 'string' && /^[1-9][0-9]*$/.test(value)
    && BigInt(value) <= 18446744073709551615n, 'Invalid native backing identity');
  token(startup.parent);
  assert(facts.length > 0, 'Missing actual parent lifecycle observations');
  const stack = [];
  let prototype, maxObservedCoreUpper = 0n;
  for (const f of facts) {
    assert.equal(f.kind, 'parent core observation'); assert.equal(f.parent, startup.parent);
    token(f.environment); token(f.array); token(f.backing);
    assert.equal(f.count, count); assert([1, 2, 3, 4, 5, 6].includes(f.phase));
    assert.equal(f.roots.length, 11); assert.equal(f.callbacks.length, 5);
    f.roots.forEach(token); f.callbacks.forEach(token);
    assert.equal(f.roots[0], f.parent);
    const owned = [...f.roots, ...f.callbacks, f.environment, f.array, f.backing];
    assert.equal(new Set(owned).size, owned.length, 'Different retained-core roles alias unexpectedly');
    const stable = { roots: f.roots, callbacks: f.callbacks, environment: f.environment };
    if (prototype) assert.deepEqual(stable, prototype, 'Actual immutable parent captures changed');
    else prototype = stable;
    assert.equal(f.indexedBytes, 496); assert.equal(f.scalarRefs, 7); assert.equal(f.reportedScalar, true);
    assert(Number.isSafeInteger(f.position) && f.position >= 0 && f.position < count);
    for (const bit of [f.pending, f.terminal, f.reclaimed]) assert(bit === 0 || bit === 1);
    assert(Number.isSafeInteger(f.children) && f.children >= 0 && f.children <= count);
    assert(Number.isSafeInteger(f.childrenSlots) && f.childrenSlots >= f.children);
    assert(BigInt(f.childrenSlots) <= bound.slots, 'Children backing exceeds input-derived capacity');
    assert.equal(typeof f.staticBacking, 'boolean');
    assert(!f.staticBacking || f.childrenSlots === 0);
    assert.equal(f.backingStorageBytes, 8 + 8 * f.childrenSlots);
    assert.equal(f.dynamicBackingBytes, f.staticBacking ? 0 : f.backingStorageBytes);
    if (f.reclaimed) { assert.equal(f.terminal, 1); assert.equal(f.children, 0); }
    else assert(f.children >= 1, 'Started child holders disappeared before parent reclamation');
    const current = BigInt(f.indexedBytes) + BigInt(f.scalarRefs) * 16n + 16n + BigInt(f.dynamicBackingBytes);
    assert(current <= bound.bytes, 'Observed core source/ABI envelope exceeds its input-derived bound');
    if (current > maxObservedCoreUpper) maxObservedCoreUpper = current;
    if (f.phase % 2) stack.push(f.phase + 1);
    else assert.equal(stack.pop(), f.phase, 'Unbound before/after parent callback observation');
  }
  assert.equal(stack.length, 0);
  assert(facts.some(f => f.phase === 5 && !f.terminal));
  assert(facts.some(f => f.phase === 6 && !f.reclaimed));
  assert(facts.some(f => f.phase === 1 && f.terminal));
  assert(facts.some(f => f.children === count), 'No observed real handoff to all children');
  assert(facts.filter(f => f.phase === 6 && f.reclaimed).length >= 2, 'Missing actual cleanup/retry observations');
  return { recipe: encodeCoreBound(bound), actualPhases: facts.length,
    maxObservedCoreSourceUpper: maxObservedCoreUpper.toString(),
    scope: 'finite normal chain, premature cleanup, terminal advance and repeated successful cleanup; scalar extents remain source/ABI premises',
    completeParentCorrespondence: false, completePipelineUpper: false };
}
