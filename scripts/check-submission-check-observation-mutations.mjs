// Focused observation faults reuse the existing strict named-assertion verifier.
// Infrastructure failures and unselected tests never count as mutation detection.
import {spawnSync} from 'node:child_process';
import {readFileSync, writeFileSync} from 'node:fs';
import {mutationAcceptance} from './check-disclosure-mutations.mjs';
const target = (name, id, operator = 'strictEqual') => ({name, assertions: [{id, operator}]});
const phases = ['not_accepted', 'preparation_failed'];
const sdk = 'packages/sdk/index.mjs';
const tests = 'packages/sdk/submission-check-observations.test.mjs';
const mutations = [
  {name: 'reference-only lookup acquires original input observation',
    path: 'adapters/host-node/client-submission.mjs', file: 'adapters/host-node/client-submission.test.mjs',
    from: "const observesInput = value.kind === 'aql' && value.intentCid === outcome.intentCid;",
    to: 'const observesInput = true;',
    targets: [target('reference-only lookup returns original acceptance without diagnostic enrichment',
      'submission-check-lookup-contract', 'fail')]},
  {name: 'original submission loses its transient checked observation', path: sdk, file: tests,
    from: 'submissionCheckObservations.set(error, freezeInput(checkObservation));',
    to: 'void checkObservation;',
    targets: phases.map(phase => target(
      `submission check binds original UTF-8 syntax bytes without changing ${phase}`,
      'submission-check-observation', 'deepStrictEqual'))},
  {name: 'submission check accepts input metadata without original byte binding', path: sdk, file: tests,
    from: '!bindCheckObservation(checkObservation, {input: body.input, parameters: body.parameters})',
    to: 'false',
    targets: ['wrong original byte length', 'split UTF-8 scalar'].map(fault => target(
      `submission check refuses ${fault} without acquiring report custody`, 'submission-check-binding'))},
  {name: 'transient input observation enters durable submission validation',
    path: 'packages/client-wire/index.mjs', file: 'packages/client-wire/submission-check-observations.test.mjs',
    from: 'value.checkObservation === undefined && submissionFactsMatch',
    to: 'submissionFactsMatch',
    targets: phases.map(phase => target(
      `submission checking is transient, not stored or reference-only ${phase}`, 'submission-check-persistence'))},
  {name: 'submission wire omits semantic input revision revalidation',
    path: 'packages/client-wire/index.mjs', file: 'packages/client-wire/submission-check-observations.test.mjs',
    from: '(value.checkObservation === undefined || validCheckOutcome(value.checkObservation)) &&',
    to: 'true &&',
    targets: phases.map(phase => target(
      `submission checking is transient, not stored or reference-only ${phase}`, 'submission-check-semantic'))},
];
const args = process.argv.slice(2);
if (args.length && (args.length !== 2 || args[0] !== '--match' || !args[1])) {
  throw new Error('Usage: check-submission-check-observation-mutations.mjs [--match name-substring]');
}
const selected = mutations.filter(item => !args.length || item.name.includes(args[1]));
if (!selected.length) throw new Error('No submission check mutations selected');
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
  const replacements = [{from: item.from, to: item.to, occurrences: item.occurrences}, ...(item.also ?? [])];
  for (const replacement of replacements) {
    if (original.split(replacement.from).length !== (replacement.occurrences ?? 1) + 1) throw new Error(`Mutation anchor not unique: ${item.name}`);
  }
  if (!run(item)) throw new Error(`Baseline failed: ${item.name}`);
  let rejected;
  try {
    const mutated = replacements.reduce((source, replacement) =>
      source.replaceAll(replacement.from, replacement.to), original);
    writeFileSync(item.path, mutated);
    rejected = !run(item);
  } finally {
    writeFileSync(item.path, original);
  }
  const restoredAccepted = run(item);
  results.push({name: item.name, rejected, restoredAccepted, targets: item.targets});
  if (!rejected || !restoredAccepted) throw new Error(`Undetected or unrestored mutation: ${item.name}`);
}
console.log(JSON.stringify({mutations: results}, null, 2));
