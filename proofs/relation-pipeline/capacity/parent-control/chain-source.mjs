import assert from 'node:assert/strict';
import {reviewedFunction} from './provider-construction-source-review.mjs';

// Exact source-side capture inventory, not a general MoonBit free-variable
// analysis. Native correspondence must bind these roles to actual closures.
const parameterBindings = ['state', 'used', 'cancelled', 'terminal', 'reclaimed', 'cleanup_index',
  'sequence', 'inputs', 'execution', 'measurement', 'numeric', 'family',
  'max_value_bytes', 'count', 'reclaims_scratch', 'start_next'];
export const chainCaptureRoles = {
  startNext: ['state', 'used', 'sequence', 'execution', 'measurement', 'numeric', 'family', 'max_value_bytes', 'count'],
  advance: ['state', 'used', 'cancelled', 'terminal', 'sequence', 'inputs', 'execution', 'max_value_bytes', 'count', 'reclaims_scratch', 'start_next'],
  cancel: ['state', 'cancelled', 'terminal'],
  stopped: ['terminal'],
  cleanup: ['state', 'terminal', 'reclaimed', 'cleanup_index'],
  childWorkIssue: ['state'],
};
const clean = source => source.replace(/\/\/[^\n]*/g, '').replace(/"(?:\\.|[^"\\])*"/g, '""');
function argumentsOf(source) {
  const args = [];
  let start = 0, depth = 0;
  for (let i = 0; i < source.length; i++) {
    const c = source[i];
    if ('([{'.includes(c)) depth++;
    else if (')]}'.includes(c)) depth--;
    else if (c === ',' && depth === 0) { args.push(source.slice(start, i)); start = i + 1; }
    assert(depth >= 0, 'Unbalanced reviewed callback list');
  }
  assert.equal(depth, 0);
  assert.equal(source.slice(start).trim(), '', 'Missing callback trailing comma');
  return args;
}
export function checkChainSource(source) {
  const constructor = clean(reviewedFunction(source, 'bounded_relation_chain_execution_state'));
  const open = '  let start_next = fn(';
  const middle = '  Ok(\n    managed_provider_execution_with_child_work_issue(\n';
  const tail = '    ),\n  ).map(active => (active, state))\n}\n';
  assert.equal(constructor.split(open).length, 2, 'Missing current start_next environment');
  assert.equal(constructor.split(middle).length, 2, 'Changed actual chain owner construction');
  assert(constructor.endsWith(tail), 'Changed state-returning owner construction');
  const parts = argumentsOf(constructor.slice(constructor.indexOf(middle) + middle.length, -tail.length));
  assert.equal(parts.length, 5, 'Changed managed parent callback count');
  const bindings = [...new Set([...parameterBindings, ...[...constructor.matchAll(/^  let (\w+)(?:\s*:[^=\n]+)?\s*=/gm)].map(m => m[1])])];
  const callbacks = {startNext: constructor.slice(constructor.indexOf(open), constructor.indexOf(middle)),
    ...Object.fromEntries(['advance', 'cancel', 'stopped', 'cleanup', 'childWorkIssue'].map((name, i) => [name, parts[i]]))};
  for (const [name, body] of Object.entries(callbacks)) {
    const actual = bindings.filter(binding => new RegExp(`\\b${binding}\\b`).test(body));
    // Ignore the locally introduced function name, not an environment capture.
    if (name === 'startNext') actual.splice(actual.indexOf('start_next'), 1);
    assert.deepEqual(actual.toSorted(), chainCaptureRoles[name].toSorted(), `Unreviewed ${name} source captures`);
  }
  assert(constructor.includes('completed: Array::make(count, None)'), 'Changed fixed completed container');
  assert(constructor.includes('state.completed[state.position] = Some(output)'), 'Changed output occurrence custody');
  const cleanup = callbacks.cleanup;
  const wait = cleanup.indexOf('Ok(false) => return Ok(false)');
  const error = cleanup.indexOf('Err(issue) => return Err(issue)');
  const release = cleanup.indexOf('state.current = None');
  assert(wait >= 0 && error > wait && release > error, 'Child cleanup must succeed before dropping custody');
  for (const ordered of ['cancel_relation_chain_inputs(cursor)', 'state.input_preparation = None',
    'state.completed = []', 'state.children = []', 'reclaimed.val = true']) {
    assert(cleanup.indexOf(ordered) > release, `Changed post-cleanup ownership release ${ordered}`);
  }
  assert(!callbacks.cancel.includes('state.input_preparation = None'), 'Cancellation drops pending input custody');
  assert(!callbacks.cancel.includes('state.completed = []'), 'Cancellation drops completed output custody');
  return {captureRoles: chainCaptureRoles, sharedCapturesAreNotNewAllocations: true,
    completeNativeCorrespondence: false, completePhysicalUpper: false};
}
