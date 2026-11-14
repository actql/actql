// Focused observation faults reuse the existing strict named-assertion verifier.
// Infrastructure failures and unselected tests never count as mutation detection.
import {spawnSync} from 'node:child_process';
import {readFileSync, writeFileSync} from 'node:fs';
import {mutationAcceptance} from './check-disclosure-mutations.mjs';
const target = (name, id, operator = 'strictEqual') => ({name, assertions: [{id, operator}]});
const phases = ['not_accepted', 'preparation_failed'];
const sdk = 'packages/sdk/internal/submission-observation.mjs';
const tests = 'packages/sdk/submission-check-observations.test.mjs';
const mutations = [
  {name: 'reference-only lookup acquires original input observation',
    path: 'adapters/host-node/client-submission.mjs', file: 'adapters/host-node/client-submission.test.mjs',
    from: 'if (!projectsProblem && originalObservation === undefined) return outcome;',
    to: `if (!projectsProblem && originalObservation === undefined) {
      const intent = immutable(JSON.parse(retained.intentWire));
      if (!supportsCheckObservation(intent)) return outcome;
      return immutable({...outcome, checkObservation: await checkSubmissionInput?.({
        principalId: value.principalId, connection: value.connection,
        kind: intent.kind === 'program' ? 'program' : 'text', scope: 'bound_input',
        input: intent.input, parameters: intent.parameters})});
    }`,
    targets: [target('reference-only lookup returns original acceptance without diagnostic enrichment',
      'submission-check-lookup-contract', 'fail')]},
  {name: 'original submission loses its transient checked observation', path: sdk, file: tests,
    from: 'submissionCheckObservations.set(error, freezeInput(checkObservation));',
    to: 'void checkObservation;',
    targets: [...phases.map(phase => target(
      `submission check binds original UTF-8 syntax bytes without changing ${phase}`,
      'submission-check-observation', 'deepStrictEqual')), ...phases.map(phase => target(
        `missing submission requirements bind pre-await declarations without changing ${phase}`,
        'submission-missing-verdict'))]},
  {name: 'missing submission observation loses typed value requirements', path: sdk, file: tests,
    from: 'submissionCheckObservations.set(error, freezeInput(checkObservation));',
    to: "submissionCheckObservations.set(error, freezeInput(checkObservation.report?.verdict === 'undetermined' ? {...checkObservation, report: {...checkObservation.report, requirements: []}} : checkObservation));",
    targets: phases.map(phase => target(
      `missing submission requirements bind pre-await declarations without changing ${phase}`,
      'submission-missing-requirement', 'deepStrictEqual'))},
  {name: 'submission check accepts input metadata without original byte binding', path: sdk, file: tests,
    from: '!bindCheckObservation(checkObservation, {kind: body.kind, input: body.input, parameters: body.parameters})',
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
  {name: 'public mixed submission loses its original observation', path: sdk,
    file: 'adapters/host-node/client-check.test.mjs',
    from: 'submissionCheckObservations.set(error, freezeInput(checkObservation));',
    to: 'void checkObservation;',
    targets: ['local', 'http'].map(entrance => target(
      `${entrance}: missing submitted bindings never mask an independent wrong value`, 'submission-mixed-outcome'))},
  {name: 'public mixed submission downgrades a definite violation to missing input', path: sdk,
    file: 'adapters/host-node/client-check.test.mjs',
    from: 'submissionCheckObservations.set(error, freezeInput(checkObservation));',
    to: "submissionCheckObservations.set(error, freezeInput(checkObservation.report?.verdict === 'invalid' ? {...checkObservation, report: {...checkObservation.report, verdict: 'undetermined'}} : checkObservation));",
    targets: ['local', 'http'].map(entrance => target(
      `${entrance}: missing submitted bindings never mask an independent wrong value`, 'submission-mixed-verdict'))},
  {name: 'public submission limits lose their original input observation', path: sdk,
    file: 'adapters/host-node/client-check.test.mjs',
    from: 'submissionCheckObservations.set(error, freezeInput(checkObservation));',
    to: 'void checkObservation;',
    targets: ['local', 'http'].flatMap(entrance => [
      target(`${entrance}: original submission separates checker budget from later acquisition refusal`,
        'submission-budget-observation'),
      target(`${entrance}: original submission projects implementation limits only from public checking`,
        'submission-implementation-observation'),
    ])},
];
mutations.push(
  {name: 'Program pointer loses its original node', path: 'packages/sdk/internal/check-observation.mjs',
    file: 'packages/sdk/structured-program-check-observations.test.mjs',
    from: 'return Object.freeze({...location, input: original});',
    to: "return Object.freeze({...location, pointer: '', input: original});",
    targets: phases.map(phase => target(
      `structured Program original snapshot and Unicode pointer survive ${phase}`, 'program-pointer'))},
  {name: 'Program definite violation becomes missing input', path: sdk,
    file: 'adapters/host-node/client-submission-input.test.mjs',
    from: 'submissionCheckObservations.set(error, freezeInput(checkObservation));',
    to: "submissionCheckObservations.set(error, freezeInput(checkObservation.report?.verdict === 'invalid' ? {...checkObservation, report: {...checkObservation.report, verdict: 'undetermined'}} : checkObservation));",
    targets: ['local', 'https'].map(entrance => target(
      `${entrance}: structured Program supplied violations coexist with missing declarations`, 'program-mixed-verdict'))},
  {name: 'Program protected Source cause escapes through the original Problem',
    path: 'adapters/host-node/client-submission.mjs', file: 'adapters/host-node/client-submission-input.test.mjs',
    from: "if (projectsProblem && intent.kind === 'program' && observed?.coverage.unresolved.length > 0) disclosable = false;",
    to: 'void observed;',
    targets: ['local', 'https'].map(entrance => target(
      `${entrance}: structured Program protected Sources retain only independent public obligations`,
      'program-protected-problem', 'deepStrictEqual'))},
);
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
