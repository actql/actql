// Focused faults reuse the existing strict named-assertion verifier and guard.
// Import errors, exceptions, timeouts and unselected tests are infrastructure failures.
import {spawnSync} from 'node:child_process';
import {readFileSync, writeFileSync} from 'node:fs';
import {mutationAcceptance} from './check-disclosure-mutations.mjs';

const path = 'packages/sdk/operation-formats.mjs';
const unit = 'packages/sdk/operation-formats.test.mjs';
const target = (name, id, operator = 'strictEqual') => ({name, assertions: [{id, operator}]});
const facts = 'operation formats retain typed facts, original lookup references and unknown outcomes without I/O';
const mutations = [
  {name: 'original lookup facts dropped for display', path, file: unit,
    from: '  const presentation = getOperationPresentationInfo({locale});',
    to: '  delete snapshot.next;\n  const presentation = getOperationPresentationInfo({locale});',
    targets: [target(facts, 'operation-format-facts', 'deepStrictEqual')]},
  {name: 'copies gain formatting custody', path: 'packages/sdk/index.mjs', file: unit,
    from: "formatOperationExplanation(explainSubmission(result), 'submission', options)",
    to: "formatOperationExplanation(explainSubmission(result) ?? result, 'submission', options)",
    targets: [target(facts, 'operation-format-custody')]},
  {name: 'control and bidi escapes omitted', path, file: unit,
    from: '/[<>&\\u007f-\\u009f\\u061c\\u200e\\u200f\\u2028-\\u202e\\u2066-\\u2069]/gu',
    to: '/a^/gu', targets: [target('operation format escaping retains control and markup bytes as data', 'operation-format-escaping', 'doesNotMatch')]},
  {name: 'oversized incomplete facts returned as display', path, file: unit,
    from: 'return utf8.encode(output).length <= maxBytes ? output : undefined;', to: 'return output;',
    targets: [target('operation format budgets refuse to drop unresolved effects or original lookup facts', 'operation-format-budget')]},
  {name: 'public returned row count reset by presentation', path, file: 'adapters/host-node/client-read-progress.test.mjs',
    from: '  const presentation = getOperationPresentationInfo({locale});',
    to: '  if (snapshot.rowsYielded !== undefined) snapshot.rowsYielded = 0;\n  const presentation = getOperationPresentationInfo({locale});',
    targets: ['local', 'https'].map(entrance => target(
      `${entrance}: 120 yielded rows survive a real delivery-owner failure`, 'operation-read-public-format', 'deepStrictEqual'))},
];
const args = process.argv.slice(2);
if (args.length && (args.length !== 2 || args[0] !== '--match' || !args[1])) {
  throw new Error('Usage: check-operation-format-mutations.mjs [--match name-substring]');
}
const selected = mutations.filter(item => !args.length || item.name.includes(args[1]));
if (!selected.length) throw new Error('No operation format mutations selected');
const run = item => {
  const escape = text => text.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&');
  const result = spawnSync(process.execPath,
    ['scripts/local-checks.mjs', 'test', 'node', '--timeout-seconds', '120', '--',
      '--test-name-pattern', `^(?:${item.targets.map(value => escape(value.name)).join('|')})$`, item.file],
    {encoding: 'utf8', timeout: 130000, maxBuffer: 16 * 1024 * 1024});
  return mutationAcceptance(result, item.targets, item.file);
};
const results = [];
for (const item of selected) {
  const original = readFileSync(item.path, 'utf8');
  if (original.split(item.from).length !== (item.occurrences ?? 1) + 1) throw new Error(`Mutation anchor not unique: ${item.name}`);
  if (!run(item)) throw new Error(`Baseline failed: ${item.name}`);
  let rejected;
  try {
    writeFileSync(item.path, original.replaceAll(item.from, item.to));
    rejected = !run(item);
  } finally {
    writeFileSync(item.path, original);
  }
  const restoredAccepted = run(item);
  results.push({name: item.name, rejected, restoredAccepted, targets: item.targets});
  if (!rejected || !restoredAccepted) throw new Error(`Undetected or unrestored mutation: ${item.name}`);
}
console.log(JSON.stringify({mutations: results}, null, 2));
