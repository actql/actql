import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { currentSlotsCeiling } from '../backing/model.mjs';
import { parentStartupLayout } from '../backing/parent-layout.mjs';
import { providerConstructionBound } from './provider-construction.mjs';
import {checkChainSource} from './chain-source.mjs';
import {checkDriverRetirementSource} from './driver-retirement-source.mjs';
const inventory = JSON.parse(readFileSync(new URL('./allocations.json', import.meta.url)));
function fields(source, name) {
  const body = source.match(new RegExp(`(?:priv )?struct ${name} \\{\\n([\\s\\S]*?)\\n\\}`))?.[1];
  assert(body, `Missing parent accounting state ${name}`);
  const clean = body.replace(/\/\/[^\n]*/g, '');
  const matches = [...clean.matchAll(/^  (?:mut )?(\w+)\s*:/gm)];
  return matches.map((m, i) => ({ name: m[1], type: clean.slice(m.index + m[0].length,
    matches[i + 1]?.index ?? clean.length).trim().replace(/\s+/g, ' ') }));
}
export function checkChainCensus(read) {
  assert.equal(inventory.version, 'actql-native-parent-allocation-census/0.1');
  for (const state of inventory.sourceFields) {
    assert.deepEqual(fields(read(state.path).toString(), state.struct), state.fields,
      `Unreviewed parent/edge field or type ${state.struct}`);
  }
  const source = read('src/connectors/local/selected_relation_provider.mbt').toString();
  const constructor = source.match(/fn bounded_relation_chain_execution_state\([\s\S]*?\nfn selected_relation_provider\(/)?.[0];
  assert(constructor, 'Missing chain allocation constructor');
  assert.deepEqual([...constructor.matchAll(/^  let (\w+)(?:\s*:[^=\n]+)?\s*=\s*Ref\(/gm)].map(m => m[1]),
    inventory.chainReferences, 'Changed parent Ref ownership');
  const declarations = [...constructor.matchAll(/^  let \w+(?:\s*:[^=\n]+)?\s*=\s*Ref\(([\s\S]*?)\)(?=\n)/gm)]
    .map(match => match[0].trim().replace(/\s+/g, ' '));
  assert.deepEqual(declarations, inventory.chainReferenceDeclarations, 'Changed parent Ref source representation');
  checkChainSource(source);
  return inventory;
}
export function checkParentCensus(read) {
  checkChainCensus(read);
  checkDriverRetirementSource(read);
  const source = read('src/connectors/local/selected_relation_provider.mbt').toString();
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
  // The container-only formula also assumes no unreviewed copies, resizing or
  // alternate reset branch in the actual selected provider body.
  providerConstructionBound(read);
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
    references: 5n * (8n + 8n), owner: BigInt(layout.blocks.owner),
    state: BigInt(layout.blocks.state),
    callbacks: BigInt(layout.callbacks), environment: BigInt(layout.blocks.startEnvironment),
    reportedWorkOverlap: 2n * 16n,
    // Cleanup replaces [] while the old owner is still held by the store.
    arrayOwnersOverlap: 2n * 24n,
    backingHeadersOverlap: 2n * 8n,
    // The fixed completed backing is never grown or copied. Cleanup creates
    // a new Array owner with the process-static empty backing before store.
    completedArrayOwnersOverlap: 2n * 24n,
    completedDynamicBackingHeader: 8n,
  };
  const slots = currentSlotsCeiling(count, 1);
  const backingPayloadOverlap = 2n * 8n * slots + 8n * BigInt(count);
  const bytes = Object.values(fixed).reduce((sum, value) => sum + value, backingPayloadOverlap);
  assert(bytes <= 9223372036854775807n, 'Parent core expression overflow');
  return { subject: 'retained native parent core only', count, slots, fixed,
    backingPayloadOverlap, bytes, unit: 'requested object header and source/ABI payload bytes',
    premises: ['five single-field primitive Refs have payload at most eight bytes',
      'immutable callback/environment layouts match the pinned source ABI',
      'at most two reported-work records coexist during replacement',
      'at most two children array owners and two backing buffers coexist',
      'children high-water length is at most the input step count',
      'completed Array has exactly count nullable reference slots until all child cleanup succeeds',
      'completed Array is not copied or grown; only old/new Array owners overlap at reset',
      'completed payloads share child output identity and are outside this container-only component'],
    fullParentUpper: false, completePipelineUpper: false };
}
export const encodeCoreBound = bound => JSON.parse(JSON.stringify(bound,
  (_, value) => typeof value === 'bigint' ? value.toString() : value));
