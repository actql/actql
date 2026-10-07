// Bounded SDK input and operation explanations reuse the named-assertion guard.
// Import, timeout and unselected-test failures never establish detection.
import {spawnSync} from 'node:child_process';
import {readFileSync, writeFileSync} from 'node:fs';
import {mutationAcceptance} from './check-disclosure-mutations.mjs';

const path = 'packages/sdk/index.mjs';
const acceptance = 'adapters/host-node/client-submission-input.test.mjs';
const cancellationAcceptance = 'adapters/host-node/client-cancel-response-loss.test.mjs';
const checkAcceptance = 'adapters/host-node/client-check.test.mjs';
const sdkAcceptance = 'packages/sdk/index.test.mjs';
const requestAcceptance = 'packages/sdk/request-observation.test.mjs';
const preparationAcceptance = 'adapters/host-node/remote-checkpoint-host.test.mjs';
const expected = (phase, assertion = 'submission-input') => {
  if (phase.startsWith('request-cancel-')) {
    const names = {
      'request-cancel-admission': ['clone changes request identity', 'clone changes known branch', 'clone changes Run reference', 'clone throws'].map(fault => `request cancellation rejects ${fault}`),
      'request-cancel-snapshot': ['request cancellation snapshots detach reused response and Run references'],
      'request-cancel-custody': ['accepted', 'already_requested', 'already_terminal'].flatMap(kind => [false, true].map(withRun => `request cancellation retains ${kind} ${withRun ? 'with Run' : 'without Run'} without stop or release claims`)),
      'request-cancel-failure': ['request cancellation failures detach reused credential errors without choosing outcome from their codes'],
      'request-cancel-private': ['request cancellation failure keeps safe recovery metadata without borrowed private causes'],
      'request-cancel-parse': ['request cancellation malformed HTTP body remains an uninterpretable response rather than a failed exchange'],
      'request-cancel-stop': ['local', 'https'].map(entrance => `${entrance}: request cancellation acceptance retains an unconfirmed physical stop`),
      'request-cancel-public': ['local', 'https'].map(entrance => `${entrance}: request cancellation acceptance retains an unconfirmed physical stop`),
      'request-cancel-loss': ['local', 'https'].flatMap(entrance => ['before-dispatch', 'after-commit'].map(phase => `${entrance}: request cancellation loss ${phase} keeps the original lookup without inventing acceptance`)),
      'request-cancel-preparation': ['C5: a cancellation after the physical start reservation releases nothing early'],
    }[phase];
    if (!names) throw new Error('Unknown request-cancellation mutation selection');
    return names.map(name => ({name, assertions: [{id: assertion,
      operator: phase === 'request-cancel-private' ? 'doesNotMatch'
        : ['request-cancel-public', 'request-cancel-loss', 'request-cancel-preparation'].includes(phase)
        ? 'deepStrictEqual' : 'strictEqual'}]}));
  }
  if (phase.startsWith('request-')) {
    const names = {
      'request-snapshot': ['request lookup snapshots detach a reused held checkpoint'],
      'request-error-custody': ['request lookup failures detach a reused credential exception for each call'],
      'request-admission': ['request lookup rejects clone changes a field', 'request lookup rejects reply cannot be cloned'],
      'request-held-admission': ['submission uncertainty retains original lookup when held clone changes its admitted branch', 'submission uncertainty retains original lookup when held reply cannot be cloned'],
      'request-held-state': ['held submit explanations retain the admitted preparation state'],
      'request-ended-public': ['rejected answers end the request without a Run; answers are per item'],
      'request-absent-public': ['local', 'https'].map(entrance => `${entrance}: program submission inputs survive before-dispatch`),
      'request-custody': ['absent', 'unknown', 'found', 'waiting_checkpoint', 'resuming', 'ended'].map(label => `request observation retains ${label} without inferring execution or resend permission`),
    }[phase];
    if (!names) throw new Error('Unknown request mutation selection');
    return names.map(name => ({name, assertions: [{id: assertion, operator: 'strictEqual'}]}));
  }
  if (phase === 'check-expression-type') return ['local', 'http'].map(entrance => ({
    name: `${entrance}: expression type rejections explain only owned expected domains`,
    assertions: [{id: assertion, operator: 'deepStrictEqual'}],
  }));
  if (phase === 'check-operation-parameter') return ['local', 'http'].map(entrance => ({
    name: `${entrance}: operation parameter violations explain owned domains and input origins`,
    assertions: [{id: assertion, operator: 'deepStrictEqual'}],
  }));
  if (phase === 'check-frame-explanation') return ['local', 'http'].map(entrance => ({
    name: `${entrance}: check explains owned invalid frame bounds`,
    assertions: [{id: assertion, operator: 'deepStrictEqual'}],
  }));
  if (phase === 'check-locale-snapshot') return [{
    name: 'check locale lookup cannot replace a copied observation during presentation',
    assertions: [{id: assertion, operator: 'strictEqual'}],
  }];
  if (phase === 'check-locale-control' || phase === 'check-locale-fallback') {
    return ['local', 'http'].map(entrance => ({
      name: `${entrance}: check locales preserve observations and safe fallback`,
      assertions: [{id: assertion, operator: 'deepStrictEqual'}],
    }));
  }
  if (phase === 'check-problem-explanation') return ['local', 'http'].map(entrance => ({
    name: `${entrance}: check Problems retain opaque attempt correlation`,
    assertions: [{id: assertion, operator: 'strictEqual'}],
  }));
  if (phase === 'check-schema-pin') return ['local', 'http'].map(entrance => ({
    name: `${entrance}: check outcome pins refuse mismatches with unchanged reason identity`,
    assertions: [{id: assertion, operator: 'strictEqual'}],
  }));
  if (phase === 'check-location-domain') return ['local', 'http'].map(entrance => ({
    name: `${entrance}: known check locations reject another submitted document`,
    assertions: [{id: assertion, operator: 'deepStrictEqual'}],
  }));
  if (phase === 'check-shape') {
    return [{name: 'local: check reply custody refuses uncloneable values and copied shape loss',
      assertions: [{id: assertion, operator: 'strictEqual'}]}];
  }
  if (phase === 'check-custody') {
    return ['preserve original syntax inputs and positions',
      'retain structured and partial input custody'].map(name => ({
      name: `local: reused check replies ${name}`,
      assertions: [{id: assertion, operator: 'strictEqual'}],
    }));
  }
  if (phase.startsWith('cancellation-clone:')) return [{
    name: `in-process: cancellation ${phase.slice('cancellation-clone:'.length)} retains original Run uncertainty`,
    assertions: [{id: assertion, operator: 'strictEqual'}],
  }];
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
  if (phase.startsWith('frontier-')) {
    const name = phase === 'frontier-context' || phase === 'frontier-order'
      ? 'typed Requirement frontiers retain context and ignore presentation order'
      : 'supplementation checks stop unchanged frontiers and bound changing contexts';
    return (phase === 'frontier-order' ? ['http'] : ['local', 'http']).map(entrance => ({
      name: `${entrance}: ${name}`,
      assertions: [{id: assertion, operator: phase === 'frontier-stalled'
        ? 'deepStrictEqual' : 'strictEqual'}],
    }));
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
  ['request cancellation malformed body becomes an exchange failure',
    '      try { answer = await controlValue(response); }\n      catch { throw uninterpretableRequestCancellation(context); }',
    "      try { answer = await controlValue(response); }\n      catch { throw retainRequestCancellationExplanation(new ClientError('CancellationUnknown', {requestId}), context, 'outcome_unknown', 'exchange_failed'); }",
    'request-cancel-parse', 'request-cancel-parse'],
  ['request cancellation raw causes leak private values',
    "}) : new ClientError('CancellationUnknown', {requestId, cause: requestCancellationCause(cause)});",
    "}) : new ClientError('CancellationUnknown', {requestId, cause});",
    'request-cancel-private', 'request-cancel-private-cause'],
  ['request cancellation copied reply skips revalidation',
    "if (!validRequestCancellation(answer, requestId) ||\n            answer.kind !== original.kind || answer.revision !== original.revision ||\n            ['namespaceId', 'authorityScopeCid', 'runDefinitionCid'].some(field =>\n              answer.ref?.[field] !== original.ref?.[field]))",
    'if (false)', 'request-cancel-admission', 'request-cancel-admission'],
  ['request cancellation response is frozen without detaching',
    '      const original = {kind: answer.kind, revision: answer.revision,\n        ref: answer.ref === undefined ? undefined : {...answer.ref}};\n      try {\n        answer = structuredClone(answer);',
    '      const original = {kind: answer.kind, revision: answer.revision,\n        ref: answer.ref === undefined ? undefined : {...answer.ref}};\n      try {\n        answer = answer;',
    'request-cancel-snapshot', 'request-cancel-detached'],
  ['request cancellation copied observations acquire custody',
    'const requestCancellationExplanations = new WeakMap();',
    'const requestCancellationExplanations = {values: new Map(), set(key, value) {this.values.set(JSON.stringify(key), value);}, get(key) {return this.values.get(JSON.stringify(key));}};',
    'request-cancel-custody', 'request-cancel-custody'],
  ['request cancellation failure reuses the credential exception',
    "? new ClientError(cause.code, {\n            ...(cause.status === undefined ? {} : {status: cause.status}),\n            ...(cause.cause === undefined ? {} : {cause: requestCancellationCause(cause.cause)}),\n          })",
    '? cause', 'request-cancel-failure', 'request-cancel-failure-custody'],
  ['request cancellation acceptance claims physical stop and release',
    '    requestId: context.requestId, ...(problem === undefined ? {} : {problem}),',
    '    requestId: context.requestId, stopped: true, resourcesReleased: true, ...(problem === undefined ? {} : {problem}),',
    'request-cancel-stop', 'request-cancel-physical-claim'],
  ['request cancellation accepted becomes already terminal',
    'return retainRequestCancellationExplanation(freezeInput(answer), context, answer.kind);',
    "return retainRequestCancellationExplanation(freezeInput(answer), context, 'already_terminal');",
    'request-cancel-public', 'request-cancel-public'],
  ['request cancellation response loss becomes accepted',
    "'outcome_unknown', 'exchange_failed');", "'accepted');",
    'request-cancel-loss', 'request-cancel-loss'],
  ['request cancellation preparation response becomes already terminal',
    'return retainRequestCancellationExplanation(freezeInput(answer), context, answer.kind);',
    "return retainRequestCancellationExplanation(freezeInput(answer), context, 'already_terminal');",
    'request-cancel-preparation', 'request-cancel-preparation'],
  ['request observation failures reuse the borrowed exception',
    '  const retained = new ClientError(code,\n    Number.isInteger(status) && status >= 100 && status <= 599 ? {status} : {});',
    '  const retained = error;', 'request-error-custody', 'request-failure-custody'],
  ['request observation loses detached checkpoint custody',
    "      try { answer = structuredClone(answer); }", "      try {}", 'request-snapshot', 'request-lookup-detached'],
  ['request observation skips copied-response revalidation',
    "      if (!validRequestLookup(answer, requestId)) throw retainRequestLookupFailure(new ClientError('InvalidHostRequestLookup'), context, 'lookup_uninterpretable');", '', 'request-admission', 'request-lookup-admission'],
  ['request observation permits a copied held reply to change its branch',
    "admitted?.kind !== 'held' || !validSubmitReply(admitted, selected.wire, requestId)",
    "!validSubmitReply(admitted, selected.wire, requestId)", 'request-held-admission', 'request-held-admission'],
  ['request observation loses the submitted held preparation state',
    "observation: 'request_held', preparationState: answer.state,",
    "observation: 'request_held', preparationState: undefined,", 'request-held-state', 'request-held-state'],
  ['request observation presents ended preparation as resuming',
    'preparationState: answer.state,', "preparationState: answer.state === 'ended' ? 'resuming' : answer.state,",
    'request-ended-public', 'request-ended-public'],
  ['request observation treats lookup absence as a Run reference',
    "const observation = answer.kind === 'found' ? 'run_reference_received' :\n" +
      "    answer.kind === 'not_found' ? 'lookup_unresolved'",
    "const observation = answer.kind === 'found' ? 'run_reference_received' :\n" +
      "    answer.kind === 'not_found' ? 'run_reference_received'",
    'request-absent-public', 'request-public-observation'],
  ['request observation copies acquire original custody',
    'const requestLookupExplanations = new WeakMap();',
    'const requestLookupExplanations = {values: new Map(), set(key, value) {this.values.set(JSON.stringify(key), value);}, get(key) {return this.values.get(JSON.stringify(key));}};',
    'request-custody', 'request-observation-custody'],

  ['check expression type explanation loses its required domain',
    'Use an expression with number type for the rejected argument.',
    'Correct the argument count.', 'check-expression-type', 'expression-type-explanation'],
  ['check operation parameter explanation loses its positive lower bound',
    'Supply an integer from 1 through 9007199254740991.',
    'Supply any finite number.', 'check-operation-parameter', 'operation-parameter-explanation'],
  ['check frame explanation loses its owned interval condition',
    'The analytic ROWS frame boundaries do not form a valid interval.',
    'The query violates an unspecified contract.',
    'check-frame-explanation', 'check-frame-explanation'],
  ['check locale changes an observed invalid verdict into verification',
    "return freezeInput({outcome: 'completed', summary, hint, report});",
    "return freezeInput({outcome: 'completed', summary, hint, report: {...report, verdict: options?.locale === 'ja' ? 'verified' : report.verdict}});",
    'check-locale-control', 'check-locale-control'],
  ['check unsupported locale loses its safe English fallback',
    "if (requested === 'ja' || requested === 'ja-JP') locale = 'ja';",
    "locale = 'ja';", 'check-locale-fallback', 'check-locale-fallback'],
  ['check locale reads copied observation fields after locale lookup',
    "const report = reportExplanation(outcome.report, 'complete');\n" +
      "    const [summary, hint] = localizeCheck(`completed.${report.verdict}`,\n" +
      "      explanations[report.verdict], options);",
    "const verdict = outcome.report.verdict;\n" +
      "    const [summary, hint] = localizeCheck(`completed.${verdict}`,\n" +
      "      explanations[verdict], options);\n" +
      "    const report = reportExplanation(outcome.report, 'complete');",
    'check-locale-snapshot', 'check-locale-snapshot'],
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
    'received = structuredClone(response);', 'received = response;',
    'cancellation-custody', 'cancel-custody'],
  ['cancellation clone failure leaks an unassociated error',
    'try { received = structuredClone(response); }',
    'received = structuredClone(response); try {}',
    'cancellation-clone:clone throws', 'cancel-clone-invalid'],
  ['cancellation clone erasure bypasses shape validation',
    'if (!validCancellation(received) ||',
    'if (false ||',
    'cancellation-clone:clone erases fields', 'cancel-clone-invalid'],
  ...['namespaceId', 'authorityScopeCid', 'runDefinitionCid'].map(field => [
    `cancellation clone bypasses ${field} association`,
    `received.ref.${field} !== ref.${field}`,
    'false',
    `cancellation-clone:clone changes ${field}`, 'cancel-clone-invalid',
  ]),
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

  ['check response reuse overwrites original input custody',
    '      try { outcome = structuredClone(outcome); }\n' +
      "      catch { fail('InvalidHostCheckOutcome'); }\n", '',
    'check-custody', 'check-response-custody'],

  ['copied check response loses its wire shape without refusal',
    "      catch { fail('InvalidHostCheckOutcome'); }\n" +
      "      if (!validCheckOutcome(outcome)) fail('InvalidHostCheckOutcome');",
    "      catch { fail('InvalidHostCheckOutcome'); }",
    'check-shape', 'check-copied-shape'],

  ['check response accepts a known location in another input document',
    "      if (!validCheckOutcome(outcome)) fail('InvalidHostCheckOutcome');\n" +
      "      // Own this call's value before binding or freezing it. A Local Host may\n" +
      "      // reuse its response object without replacing a previous SDK observation.\n" +
      "      try { outcome = structuredClone(outcome); }\n" +
      "      catch { fail('InvalidHostCheckOutcome'); }\n" +
      "      if (!validCheckOutcome(outcome)) fail('InvalidHostCheckOutcome');",
    "      try { outcome = structuredClone(outcome); }\n" +
      "      catch { fail('InvalidHostCheckOutcome'); }",
    'check-location-domain', 'known-location-domain'],

  ['check Problem explanation loses its opaque correlation',
    "return freezeInput({outcome: 'failed', summary, hint, correlationRef, problem,",
    "return freezeInput({outcome: 'failed', summary, hint, problem,",
    'check-problem-explanation', 'check-problem-explanation'],
  ['check outcome bypasses its schema identity pin',
    'valid(value, schemas.check_outcome) && value.outcome_schema_cid === checkOutcomeSchemaCid;',
    'valid(value, schemas.check_outcome);',
    'check-schema-pin', 'check-outcome-pin'],

  ['frontier comparison discards the bound context',
    'return structuralKey(left) === structuralKey(right);',
    'return structuralKey({...left, contextRef: "ignored"}) === structuralKey({...right, contextRef: "ignored"});',
    'frontier-context', 'frontier-context'],
  ['frontier comparison treats presentation order as progress',
    'requirements: unordered(report.requirements.map(({code, facts}) =>\n      ({code, facts}))),',
    'requirements: report.requirements.map(({code, facts}) => ({code, facts})),',
    'frontier-order', 'frontier-order'],
  ['frontier session repeats an unchanged obligation set',
    'previous && structuralKey(previous) === structuralKey(frontier)', 'false',
    'frontier-stalled', 'frontier-stalled'],
  ['frontier session resets the attempt cap after changing context',
    'const frontier = getCheckRequirementFrontier(outcome);',
    'const frontier = getCheckRequirementFrontier(outcome);\n' +
      '        if (previous && previous.contextRef !== frontier?.contextRef) attempts = 1;',
    'frontier-budget', 'frontier-budget-count'],

];
const accepted = (phase, assertion) => {
  const tests = expected(phase, assertion);
  const file = phase === 'request-cancel-preparation' ? preparationAcceptance
    : ['request-cancel-public', 'request-cancel-stop', 'request-cancel-loss'].includes(phase) ? cancellationAcceptance
    : phase === 'request-ended-public' ? preparationAcceptance
    : phase === 'request-absent-public' ? acceptance
    : phase.startsWith('request-') ? requestAcceptance
    : phase === 'check-locale-snapshot' ? sdkAcceptance
    : phase.startsWith('frontier-') || phase.startsWith('check-') ? checkAcceptance
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
const mutationPath = phase => phase === 'check-schema-pin'
  ? 'packages/client-wire/client-host.generated.js'
  : phase === 'check-locale-fallback' ? 'packages/sdk/check-presentation.mjs' : path;
const originals = new Map(selected.map(([, , , phase]) => mutationPath(phase))
  .map(file => [file, readFileSync(file, 'utf8')]));
const results = [];
try {
  for (const [name, from, to, phase, assertion] of selected) {
    const file = mutationPath(phase);
    const original = originals.get(file);
    if (original.split(from).length !== 2) throw new Error(`Mutation anchor not unique: ${name}`);
    writeFileSync(file, original.replace(from, to));
    results.push({name, phase, rejected: !accepted(phase, assertion)});
    writeFileSync(file, original);
  }
} finally {
  for (const [file, original] of originals) writeFileSync(file, original);
}
const restorations = new Map(selected.map(([, , , phase, assertion]) =>
  [phase + ':' + (assertion ?? 'submission-input'), {phase, assertion}]));
const restoredAccepted = [...restorations.values()].every(({phase, assertion}) => accepted(phase, assertion));
console.log(JSON.stringify({mutations: results, restoredAccepted}, null, 2));
if (!restoredAccepted || results.some(result => !result.rejected)) process.exitCode = 1;
