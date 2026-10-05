// Bounded SDK input and operation explanations reuse the named-assertion guard.
// Import, timeout and unselected-test failures never establish detection.
import {spawnSync} from 'node:child_process';
import {readFileSync, writeFileSync} from 'node:fs';
import {mutationAcceptance} from './check-disclosure-mutations.mjs';

const path = 'packages/sdk/index.mjs';
const acceptance = 'adapters/host-node/client-submission-input.test.mjs';
const cancellationAcceptance = 'adapters/host-node/client-cancel-response-loss.test.mjs';
const checkAcceptance = 'adapters/host-node/client-check.test.mjs';
const expected = (phase, assertion = 'submission-input') => {
  if (phase === 'cancellation-custody') return [{
    name: 'in-process: reused cancellation replies preserve each original Run observation',
    assertions: [{id: assertion, operator: 'deepStrictEqual'}],
  }];
  if (phase.startsWith('check-outcome-')) {
    const name = phase === 'check-outcome-reporting'
      ? 'check outcome explanations preserve reporting boundaries'
      : 'check outcome explanations preserve partial and unavailable boundaries';
    return ['local', 'http'].map(entrance => ({name: `${entrance}: ${name}`,
      assertions: [{id: assertion, operator: phase === 'check-outcome-validation'
        ? 'strictEqual' : 'deepStrictEqual'}]}));
  }
  if (phase.startsWith('cancellation-')) {
    const name = phase === 'cancellation-recorded'
      ? 'Run cancellation explanations retain recorded control facts'
      : 'Run cancellation uncertainty retains read-only observation advice';
    return ['in-process', 'https'].map(entrance => ({
      name: `${entrance}: ${name}`,
      assertions: [{id: assertion, operator: 'deepStrictEqual'}],
    }));
  }
  return ['local', 'https'].map(entrance => ({
    name: `${entrance}: program submission inputs survive ${phase}`,
    assertions: [{id: assertion, operator: 'deepStrictEqual'}],
  }));
};
const mutations = [
  ['unknown submit loses its original input',
    '  if (input) submissionInputs.set(result, input);', '', 'after-commit'],
  ['original supplied parameters are replaced by null',
    'const snapshot = freezeInput({...body, connection: selected.wire,',
    'const snapshot = freezeInput({...body, parameters: null, connection: selected.wire,',
    'after-commit'],
  ['accepted handle loses its original input',
    '    submissionInputs.set(result, snapshot);', '', 'acceptance'],
  ['unknown acceptance is presented as a held request',
    "submissionLookupExplanation('acceptance_unknown', input)",
    "submissionLookupExplanation('request_held', input)",
    'after-commit', 'submission-explanation'],
  ['submission explanation loses the original lookup identity',
    'requestId: input.requestId,', 'requestId: "wrong-request",',
    'after-commit', 'submission-explanation'],
  ['submission explanation exposes a private transport cause',
    "submissionLookupExplanation('acceptance_unknown', input));",
    "freezeInput({...submissionLookupExplanation('acceptance_unknown', input), cause: cause.message}));",
    'after-commit', 'submission-explanation'],
  ['received Run reference is presented as unknown acceptance',
    "observation: 'run_reference_received',", "observation: 'acceptance_unknown',",
    'acceptance', 'submission-explanation'],
  ['cancellation acceptance is presented as physical stop and release',
    "accepted: 'The Host recorded a Run cancellation request. Refresh Run state for physical stop, Effects and release.'",
    "accepted: 'The Run has stopped and all resources have been released.'",
    'cancellation-recorded', 'cancel-explanation'],
  ['unknown cancellation is presented as confirmed acceptance',
    'cancellationExplanations.set(result, freezeInput({observation,',
    "cancellationExplanations.set(result, freezeInput({observation: observation === 'outcome_unknown' ? 'accepted' : observation,",
    'cancellation-unknown', 'cancel-unknown-explanation'],
  ['cancellation observation advice targets another Run',
    "next: {operation: 'status', ref: context.ref}",
    "next: {operation: 'status', ref: {...context.ref, runDefinitionCid: 'sha256:' + '0'.repeat(64)}}",
    'cancellation-recorded', 'cancel-explanation'],
  ['unknown cancellation recommends another cancellation write',
    "next: {operation: 'status', ref: context.ref}",
    "next: {operation: 'cancel', ref: context.ref}",
    'cancellation-unknown', 'cancel-unknown-explanation'],
  ['cancellation explanation exposes a private transport message',
    'summary: summaries[observation],',
    'summary: result.cause?.message ?? summaries[observation],',
    'cancellation-unknown', 'cancel-unknown-explanation'],
  ['local cancellation response-format failure loses uncertainty',
    "        if (value instanceof Response) {\n" +
    "          throw retainCancellationExplanation(new ClientError('InvalidLocalHostPortResponse'),\n" +
    "            cancellationContext, 'outcome_unknown');\n        }",
    "        if (value instanceof Response) fail('InvalidLocalHostPortResponse');",
    'cancellation-unknown', 'cancel-unknown-explanation'],
  ['cancellation response reuse changes an earlier Run observation',
    'const received = structuredClone(response);', 'const received = response;',
    'cancellation-custody', 'cancel-custody'],
  ['check reporting budget is blamed on an invalid input',
    'The reporting budget could not produce a complete bound check report.',
    'The submitted input is invalid.', 'check-outcome-reporting', 'check-outcome-explanation'],
  ['check verification is presented as execution and release success',
    'The report verifies only its bound checking scope and context.',
    'Execution and release succeeded.', 'check-outcome-reporting', 'check-outcome-explanation'],
  ['check partial report is presented as complete',
    "reportExplanation(outcome.partial_report, 'partial')",
    "reportExplanation(outcome.partial_report, 'complete')",
    'check-outcome-partial', 'check-outcome-partial'],
  ['check unavailable is presented as completed',
    "return freezeInput({outcome: 'unavailable',",
    "return freezeInput({outcome: 'completed',",
    'check-outcome-unavailable', 'check-outcome-unavailable'],
  ['check explanation bypasses malformed outcome validation',
    '  if (!validCheckOutcome(outcome)) return undefined;', '',
    'check-outcome-validation', 'check-outcome-invalid'],

];
const accepted = (phase, assertion) => {
  const tests = expected(phase, assertion);
  const file = phase.startsWith('check-outcome-') ? checkAcceptance
    : phase.startsWith('cancellation-') ? cancellationAcceptance : acceptance;
  const result = spawnSync(process.execPath, ['scripts/local-checks.mjs', 'test', 'node',
    '--timeout-seconds', '120', '--', '--test-name-pattern',
    `^(?:${tests.map(value => value.name).join('|')})$`, file],
  {encoding: 'utf8', timeout: 130000, maxBuffer: 16 * 1024 * 1024});
  return mutationAcceptance(result, tests, file);
};
const args = process.argv.slice(2);
if (args.length && (args.length !== 2 || args[0] !== '--match' || !args[1])) {
  throw new Error('Usage: check-submission-input-mutations.mjs [--match name-substring]');
}
const selected = mutations.filter(([name]) => args.length === 0 || name.includes(args[1]));
if (!selected.length) throw new Error('No SDK mutations selected');
const original = readFileSync(path, 'utf8');
const results = [];
try {
  for (const [name, from, to, phase, assertion] of selected) {
    if (original.split(from).length !== 2) throw new Error(`Mutation anchor not unique: ${name}`);
    writeFileSync(path, original.replace(from, to));
    results.push({name, phase, rejected: !accepted(phase, assertion)});
  }
} finally {
  writeFileSync(path, original);
}
const restorations = new Map(selected.map(([, , , phase, assertion]) =>
  [phase + ':' + (assertion ?? 'submission-input'), {phase, assertion}]));
const restoredAccepted = [...restorations.values()].every(({phase, assertion}) => accepted(phase, assertion));
console.log(JSON.stringify({mutations: results, restoredAccepted}, null, 2));
if (!restoredAccepted || results.some(result => !result.rejected)) process.exitCode = 1;
