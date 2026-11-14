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
  {name: 'public check display omits terminal control escaping', path: 'packages/sdk/index.mjs',
    file: 'adapters/host-node/client-check.test.mjs',
    from: '/[\\u007f-\\u009f\\u061c\\u200e\\u200f\\u202a-\\u202e\\u2066-\\u2069]/gu',
    to: '/a^/gu', targets: ['local', 'http'].map(entrance => target(
      `${entrance}: actual check display keeps hostile declaration names as data`,
      'public-display-terminal', 'doesNotMatch'))},
  {name: 'public check display omits HTML markup escaping', path: 'packages/sdk/index.mjs',
    file: 'adapters/host-node/client-check.test.mjs',
    from: 'const checkHtml = value => value.replace(/[&<>"\']/gu, character =>',
    to: 'const checkHtml = value => value.replace(/a^/gu, character =>',
    targets: ['local', 'http'].map(entrance => target(
      `${entrance}: actual check display keeps hostile declaration names as data`,
      'public-display-html', 'doesNotMatch'))},
  {name: 'public check display omits Agent data escaping', path: 'packages/sdk/index.mjs',
    file: 'adapters/host-node/client-check.test.mjs',
    from: '/[<>&\\u007f-\\u009f\\u061c\\u200e\\u200f\\u2028-\\u202e\\u2066-\\u2069]/gu',
    to: '/a^/gu', targets: ['local', 'http'].map(entrance => target(
      `${entrance}: actual check display keeps hostile declaration names as data`,
      'public-display-agent', 'doesNotMatch'))},
  {name: 'expired retired identity is admitted as new work',
    path: 'adapters/host-node/client-request-journal.mjs',
    file: 'adapters/host-node/submission-epoch-public.test.mjs',
    from: 'const validity = control.clientSubmissionEpochValidity(handle, clock.observed_at);',
    to: "const validity = intentRetired.get().retired_count > 0 ? 'admissible' : control.clientSubmissionEpochValidity(handle, clock.observed_at);",
    // A prior lookup also fences expiry. Activate only after actual Owner
    // retirement, then bypass validity and retained-entry time checks;
    // authentication, scope, intent, custody and transaction checks remain.
    also: [{from: 'row.accepted_at >= epoch.expiresAt || !Number.isSafeInteger(row.revision)',
      to: '!Number.isSafeInteger(row.revision)'}],
    targets: ['local', 'https'].map(entrance => target(
      `${entrance}: expired retired submission cannot regain admission custody or create a Run`,
      'expired-admission-custody', 'deepStrictEqual'))},
  {name: 'original Request Source category exposes private metadata as a Host feature',
    path: 'adapters/host-node/client-program-preparation.mjs', file: 'adapters/host-node/client-preparation-disclosure.test.mjs',
    from: "source_unsupported: 'ClientProgramRejected'", to: "source_unsupported: 'ClientProgramUnsupported'",
    targets: [target('original Request source_unsupported retains its typed code without diagnostic rechecking',
      'request-source-category-private', 'strictEqual')]},
  {name: 'original Request execution silently selects an ownerless preparation',
    path: 'adapters/host-node/client-program-preparation.mjs', file: 'adapters/host-node/client-program-preparation-retirement.test.mjs',
    from: "typeof getFundedPreparation !== 'function'", to: 'false',
    targets: [target('execution preparation requires the original Request owner even when every old raw export exists',
      'request-funding-required', 'throws')]},
  {name: 'Source implementation lookup borrows an analysis budget fact',
    path: 'adapters/host-node/client-submission.mjs', file: 'adapters/host-node/client-submission.test.mjs',
    from: "? 'analysis_budget_exhausted' : 'implementation_limit'", to: "? 'analysis_budget_exhausted' : limit.code",
    targets: ['partial', 'completed'].map(kind => target(
      `retained Source implementation limit rechecks ${kind} original disclosure`,
      'submission-implementation-disclosure', 'deepStrictEqual'))},
  {name: 'Source implementation explanation loses its safe guidance',
    path: 'packages/sdk/index.mjs', file: 'packages/sdk/submission-explanations.test.mjs',
    from: "if (explanation.problem?.code === 'ClientProgramImplementationLimit' &&\n      explanation.problem.classification === 'implementation_limit')", to: 'if (false)',
    targets: ['not_accepted', 'preparation_failed'].map(phase => target(
      `submission implementation limit explains ${phase} without choosing the phase from its code`,
      'submission-implementation-guidance', 'deepStrictEqual'))},
  {name: 'submission analysis budget loses implementation-limit classification',
    path: 'adapters/host-node/client-submission.mjs', file: 'adapters/host-node/client-submission.test.mjs',
    from: "ClientProgramAnalysisLimit: 'implementation_limit'",
    to: "ClientProgramAnalysisLimit: 'operation_failed'",
    targets: [target('retained Source analysis budget rechecks original intent and current disclosure without preparation',
      'submission-budget-public', 'deepStrictEqual')]},
  {name: 'submission analysis budget ignores current public disclosure',
    path: 'adapters/host-node/client-submission.mjs', file: 'adapters/host-node/client-submission.test.mjs',
    from: "observed?.scope.kind === 'bound_input' && observed.coverage.limits.some(\n          limit => limit.code === (outcome.problem.code === 'ClientProgramAnalysisLimit'\n            ? 'analysis_budget_exhausted' : 'implementation_limit'))",
    to: 'true',
    targets: [target('retained Source analysis budget rechecks original intent and current disclosure without preparation',
      'submission-budget-disclosure', 'deepStrictEqual')]},
  {name: 'submission analysis budget loses safe SDK guidance',
    path: 'packages/sdk/index.mjs', file: 'packages/sdk/submission-explanations.test.mjs',
    from: "if (explanation.problem?.code === 'ClientProgramAnalysisLimit' &&\n      explanation.problem.classification === 'implementation_limit')",
    to: 'if (false)',
    targets: ['not_accepted', 'preparation_failed'].map(phase => target(
      `submission analysis budget explains ${phase} without choosing the phase from its code`,
      'submission-budget-guidance', 'deepStrictEqual'))},
  {name: 'submission disclosure reuses a previously visible Source problem',
    path: 'adapters/host-node/client-submission.mjs', file: 'adapters/host-node/client-submission.test.mjs',
    from: '    const projected = disclosable ? outcome : {...outcome,',
    to: '    const projected = true ? outcome : {...outcome,',
    targets: [target('retained Source input problems recheck original intent and current disclosure without preparation',
      'submission-disclosure', 'deepStrictEqual')]},
  {name: 'submission disclosure suppresses invalid input beside an unresolved Source',
    path: 'adapters/host-node/client-submission.mjs', file: 'adapters/host-node/client-check.test.mjs',
    from: "observed?.scope.kind === 'bound_input' && observed.verdict === 'invalid'",
    to: "observed?.scope.kind === 'bound_input' && observed.verdict === 'invalid' && observed.coverage.unresolved.length === 0",
    targets: ['local', 'http'].map(entrance => target(
      `${entrance}: original submission explanations hide private resolution and preserve independent input violations`,
      'submission-private-input', 'deepStrictEqual'))},
  {name: 'submission disclosure treats an undetermined report as invalid input',
    path: 'adapters/host-node/client-submission.mjs', file: 'adapters/host-node/client-submission.test.mjs',
    from: "observed?.scope.kind === 'bound_input' && observed.verdict === 'invalid'",
    to: "observed?.scope.kind === 'bound_input' && ['invalid', 'undetermined'].includes(observed.verdict)",
    targets: [target('submission disclosure does not derive invalid input from undetermined reporting',
      'submission-reporting', 'deepStrictEqual')]},
  {name: 'submission explanation converts accepted preparation failure into nonacceptance',
    path: 'packages/sdk/index.mjs', file: 'adapters/host-node/submission-epoch-public.test.mjs',
    from: "const observation = outcome.kind === 'unresolvable' ? 'history_unresolvable' : outcome.kind;",
    to: "const observation = outcome.kind === 'preparation_failed' ? 'not_accepted' : outcome.kind === 'unresolvable' ? 'history_unresolvable' : outcome.kind;",
    targets: ['local', 'https'].flatMap(entrance => [
      'an accepted unsupported pre-Run wait remains a preparation failure after reconnect',
      'durable input rejection explains nonacceptance and survives original lookup',
    ].map(name => target(`${entrance}: ${name}`, 'submission-public-phase', 'deepStrictEqual')))},
  {name: 'submission explanation drops admitted lookup facts',
    path: 'packages/sdk/index.mjs', file: 'packages/sdk/submission-explanations.test.mjs',
    from: 'return retainSubmissionExplanation(freezeInput(answer), answer, context);',
    to: 'return freezeInput(answer);',
    targets: ['not_accepted', 'preparation_failed', 'preparing', 'ready', 'unresolvable'].map(kind => target(
      `submission lookup explanation retains admitted ${kind} and the original epoch`, 'submission-lookup', 'deepStrictEqual'))},
  {name: 'submission explanation replaces a rejected lookup original with a fresh nonce',
    path: 'packages/sdk/index.mjs', file: 'packages/sdk/submission-explanations.test.mjs',
    from: 'hint: submissionObservationHint, next: submissionTarget(context)}));',
    to: "hint: submissionObservationHint, next: {...submissionTarget(context), submissionRef: {...context.submissionRef, nonce: 'fresh-submission'}}}));",
    targets: ['unknown branch', 'wrong nonce', 'malformed problem', 'changed clone'].map(fault => target(
      `submission lookup refuses ${fault} without acquiring outcome facts`, 'submission-rejected-reference', 'deepStrictEqual'))},
  {name: 'submission explanation presents local nondispatch as Owner rejection',
    path: 'packages/sdk/index.mjs', file: 'packages/sdk/submission-explanations.test.mjs',
    from: "if (input) submissionExplanations.set(result, freezeInput({observation: 'not_sent',",
    to: "if (input) submissionExplanations.set(result, freezeInput({observation: 'not_accepted',",
    targets: [target('known unsent submission explains dispatch only and has no Owner outcome', 'submission-unsent')]},
  {name: 'short query drops its existing Run observation explanation', path: 'packages/sdk/index.mjs',
    file: 'adapters/host-node/client-short-query-observation-failure.test.mjs',
    from: '    if (failure) runObservationFailures.set(error, failure);',
    to: '    if (failure) void error;',
    targets: ['local', 'https'].flatMap(entrance => ['sql', 'aql'].map(language => target(
      `${entrance}/${language}: short query observation failure preserves the original published Run without retry`,
      'query-run-public', 'deepStrictEqual')))},
  {name: 'short query changes the original lookup into a submit candidate', path: 'packages/sdk/index.mjs',
    file: 'packages/sdk/source-query-observation-failure.test.mjs',
    from: '    if (failure) runObservationFailures.set(error, failure);',
    to: "    if (failure) runObservationFailures.set(error, {...failure, next: {operation: 'submit'}});",
    targets: ['sql', 'aql'].flatMap(language => ['observation_unavailable', 'unknown_state', 'contract_mismatch', 'malformed_response'].map(problem => target(
      `${language}: short query retains ${problem} Run observation without retry`, 'query-run-failure', 'deepStrictEqual')))},
  {name: 'short query loses its original submission input', path: 'packages/sdk/index.mjs',
    file: 'packages/sdk/source-query-observation-failure.test.mjs',
    from: '    retainQueryResult(execution, error);', to: '    void execution;',
    targets: [target('short query valid failed state retains input without claiming failed observation',
      'query-failure-input', 'deepStrictEqual')]},
  {name: 'Run observation display drops the original lookup target', path,
    file: 'adapters/host-node/client-run-observation-unavailable.test.mjs',
    from: '  const presentation = getOperationPresentationInfo({locale});',
    to: "  if (domain === 'observation') delete snapshot.next;\n  const presentation = getOperationPresentationInfo({locale});",
    targets: ['local', 'https'].map(entrance => target(
      `${entrance}: unavailable Run observations preserve publication and original lookup`, 'run-format-public', 'deepStrictEqual'))},
  {name: 'Run observation display copies gain custody', path: 'packages/sdk/index.mjs',
    file: 'packages/sdk/run-observation-formats.test.mjs',
    from: "formatOperationExplanation(explainRunObservationFailure(error), 'observation', options)",
    to: "formatOperationExplanation(explainRunObservationFailure(error) ?? error, 'observation', options)",
    targets: ['status', 'wait', 'reconcile'].map(operation => target(
      `${operation}: Run failure formats preserve original classification and lookup without I/O`, 'run-format-custody'))},
  {name: 'Run observation display rewrites failure classification', path,
    file: 'packages/sdk/run-observation-formats.test.mjs',
    from: "const classification = domain === 'observation' ? facts.kind : facts.observation;",
    to: "const classification = domain === 'observation' ? 'success' : facts.observation;",
    targets: ['status', 'wait', 'reconcile'].map(operation => target(
      `${operation}: Run failure formats preserve original classification and lookup without I/O`, 'run-format-kind'))},

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
