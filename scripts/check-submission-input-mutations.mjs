// Bounded SDK input and operation explanations reuse the named-assertion guard.
// Import, timeout and unselected-test failures never establish detection.
import {execFileSync, spawnSync} from 'node:child_process';
import {readFileSync, writeFileSync} from 'node:fs';
import {mutationAcceptance} from './check-disclosure-mutations.mjs';

const path = 'packages/sdk/index.mjs';
const acceptance = 'adapters/host-node/client-submission-input.test.mjs';
const cancellationAcceptance = 'adapters/host-node/client-cancel-response-loss.test.mjs';
const checkAcceptance = 'adapters/host-node/client-check.test.mjs';
const sdkAcceptance = 'packages/sdk/index.test.mjs';
const requestAcceptance = 'packages/sdk/request-observation.test.mjs';
const preparationAcceptance = 'adapters/host-node/remote-checkpoint-host.test.mjs';
const operationInputAcceptance = 'adapters/host-node/client-operation-input-rejection.test.mjs';
const expected = (phase, assertion = 'submission-input') => {
  if (phase === 'submission-attempt-custody') {
    return ['refused/authorization', 'refused/admission_capacity', 'refused/epoch_expired',
      'refused/epoch_not_yet_valid', 'conflict/intent', 'conflict/restart_decision'].map(outcome => ({
      name: `typed Submission ${outcome} explains only its original invocation`,
      assertions: [{id: assertion, operator: 'strictEqual'}],
    }));
  }
  if (phase === 'submission-attempt-refused' || phase === 'submission-attempt-conflict') {
    const name = phase === 'submission-attempt-refused'
      ? 'typed fresh-epoch refusal is distinct from the durable original acceptance'
      : 'typed Submission Conflict and AlreadySatisfied preserve the installed original Run';
    return ['local', 'https'].map(entrance => ({name: `${entrance}: ${name}`,
      assertions: [{id: assertion, operator: 'deepStrictEqual'}]}));
  }
  if (phase === 'unresolvable-restart') return ['local', 'https'].map(entrance => ({
    name: `${entrance}: explicit restart lookup restores the same linked Run after original processes exit`,
    assertions: [{id: assertion, operator: 'deepStrictEqual'}],
  }));
  if (phase === 'submission-copy') return [{
    name: 'SDK submitted outcome needs no verification clone after admission',
    assertions: [{id: 'request-held-admission', operator: 'strictEqual'}],
  }];
  if (phase.startsWith('operation-input-')) {
    const inputs = phase === 'operation-input-range' ? ['reversed bound range']
      : ['empty bound vector query', 'short bound vector query', 'long bound vector query'];
    return ['local', 'https'].flatMap(entrance => inputs.map(input => ({
      name: `${entrance}: ${input} is rejected before admission or Compute`,
      assertions: [{id: assertion, operator: 'strictEqual'}],
    })));
  }
  if (phase === 'request-record-loss') return ['local', 'https'].map(entrance => ({
    name: `${entrance}: missing submission record preserves uncertainty despite an already published Run`,
    assertions: [{id: assertion, operator: assertion === 'request-record-loss-kind' ? 'strictEqual' : 'deepStrictEqual'}],
  }));
  if (phase.startsWith('request-cancel-')) {
    const names = {
      'request-cancel-admission': ['request cancellation keeps its original outcome without a verification clone'],
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
      'request-admission': ['request lookup needs no verification clone after original capture'],
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
    return ['missing-version', 'invalid-outcome'].map(fault => ({
      name: `local: malformed original check reply ${fault} refuses before issuing a verdict`,
      assertions: [{id: assertion, operator: 'strictEqual'}]}));
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
  if (phase === 'cancellation-format') return [{
    name: 'in-process: Run cancellation uncertainty retains read-only observation advice',
    assertions: [{id: assertion, operator: 'strictEqual'}],
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
  if (phase === 'cancellation-attempt-custody') {
    return ['refused/authorization', 'refused/admission_capacity',
      'conflict/intent', 'conflict/control_revision'].map(outcome => ({
      name: `typed cancellation ${outcome} explains only its original invocation`,
      assertions: [{id: assertion, operator: 'strictEqual'}],
    }));
  }
  if (phase === 'cancellation-attempt-refused' || phase === 'cancellation-attempt-conflict') {
    const name = phase === 'cancellation-attempt-refused'
      ? 'Refused is invocation-local and does not consume cancellation custody'
      : 'stale relevant revision returns a correlated Conflict without a write';
    return ['in-process', 'https'].map(entrance => ({
      name: `${entrance}: ${name}`,
      assertions: [{id: assertion, operator: 'deepStrictEqual'}],
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
  ['typed Submission refusal loses its original invocation explanation',
    '          retainSubmissionAttemptExplanation(typedRejection, attempt, snapshot);',
    '', 'submission-attempt-refused', 'submit-attempt-refused', [], 'packages/sdk/internal/submission-observation.mjs'],
  ['typed Submission refusal claims globally unconsumed custody',
    "...(attempt.kind === 'refused' ? {guarantee: attempt.guarantee} : {}),",
    "...(attempt.kind === 'refused' ? {guarantee: 'submission_never_committed'} : {}),",
    'submission-attempt-refused', 'submit-attempt-refused', [], 'packages/sdk/operation-presentation.mjs'],
  ['typed Submission conflict targets a different original submission',
    '    next: submissionTarget(snapshot),',
    "    next: submissionTarget({...snapshot, submissionRef: {...snapshot.submissionRef, nonce: 'different-original'}}),",
    'submission-attempt-conflict', 'submit-attempt-conflict', [], 'packages/sdk/operation-presentation.mjs'],
  ['typed Submission copies acquire original explanation custody',
    'const submissionExplanations = new WeakMap();',
    'const submissionExplanations = {values: new Map(), set(key, value) {this.values.set(JSON.stringify(key), value);}, get(key) {return this.values.get(JSON.stringify(key));}};',
    'submission-attempt-custody', 'submit-attempt-custody', [], 'packages/sdk/internal/submission-observation.mjs'],
  ['an Unresolvable lookup silently acknowledges risk and restarts work',
    '      return retainSubmissionExplanation(freezeInput(answer), answer, context);',
    "      if (answer.kind === 'unresolvable' && unsafeRestartInput !== undefined) {\n" +
      '        const original = unsafeRestartInput; unsafeRestartInput = undefined;\n' +
      '        const restarted = await submit(original.kind, original.input, {parameters: original.parameters,\n' +
      '          submissionRef: newSubmission(), unresolvedHistory: {submissionRef: owned,\n' +
      "            acknowledgement: 'possible_prior_execution_and_effects'}});\n" +
      '        await restarted.wait({signal: AbortSignal.timeout(15000)});\n' +
      '      }\n' +
      '      return retainSubmissionExplanation(freezeInput(answer), answer, context);',
    'unresolvable-restart', 'unresolvable-no-restart', [], 'packages/sdk/internal/submission-observation.mjs'],
  ['known reversed operation range loses input classification',
    '        | Ranges(ReversedRange(_))\n', '',
    'operation-input-range', 'operation-input-public'],
  ['known vector query shape violation loses input classification',
    '        | Queries(InvalidQuery(_) | DimensionMismatch(_, _, _))', '',
    'operation-input-query', 'operation-input-public'],
  ['request record loss is presented as durable nonacceptance',
    "    answer.kind === 'not_found' ? 'lookup_unresolved'",
    "    answer.kind === 'not_found' ? 'not_accepted'",
    'request-record-loss', 'request-record-loss-kind', [], 'packages/sdk/operation-presentation.mjs'],
  ['request record loss recommends a new submission',
    "{operation: 'lookupRequest', requestId: context.requestId,\n          lookupContext: context.lookupContext},",
    "{operation: 'submit', requestId: context.requestId,\n          lookupContext: context.lookupContext},",
    'request-record-loss', 'request-record-loss-advice', [], 'packages/sdk/operation-presentation.mjs'],
  ['request cancellation malformed body becomes an exchange failure',
    "      try { answer = await responseValue(response); }\n      catch { throw uninterpretableRequestCancellation(context); }",
    "      try { answer = await responseValue(response); }\n      catch { throw retainRequestCancellationExplanation(new ClientError('CancellationUnknown', {requestId}), context, 'outcome_unknown', 'exchange_failed'); }",
    'request-cancel-parse', 'request-cancel-parse', [], 'packages/sdk/internal/submission-observation.mjs'],
  ['request cancellation raw causes leak private values',
    "}) : new ClientError('CancellationUnknown', {requestId, cause: requestCancellationCause(cause)});",
    "}) : new ClientError('CancellationUnknown', {requestId, cause});",
    'request-cancel-private', 'request-cancel-private-cause', [], 'packages/sdk/internal/submission-observation.mjs'],
  ["request cancellation copied reply skips revalidation",
    "try { answer = captureResponse(answer); }\n      catch { throw uninterpretableRequestCancellation(context); }",
    "try { answer = structuredClone(captureResponse(answer)); }\n      catch { throw uninterpretableRequestCancellation(context); }",
    "request-cancel-admission",
    "request-cancel-admission",
    [],
    "packages/sdk/internal/submission-observation.mjs"],
  ["request cancellation response is frozen without detaching",
    "try { answer = captureResponse(answer); }\n      catch { throw uninterpretableRequestCancellation(context); }",
    "try { answer = answer; }\n      catch { throw uninterpretableRequestCancellation(context); }",
    "request-cancel-snapshot",
    "request-cancel-detached",
    [],
    "packages/sdk/internal/submission-observation.mjs"],
  ['request cancellation copied observations acquire custody',
    'const requestCancellationExplanations = new WeakMap();',
    'const requestCancellationExplanations = {values: new Map(), set(key, value) {this.values.set(JSON.stringify(key), value);}, get(key) {return this.values.get(JSON.stringify(key));}};',
    'request-cancel-custody', 'request-cancel-custody', [], 'packages/sdk/internal/submission-observation.mjs'],
  ['request cancellation failure reuses the credential exception',
    "? new ClientError(cause.code, {\n            ...(cause.status === undefined ? {} : {status: cause.status}),\n            ...(cause.cause === undefined ? {} : {cause: requestCancellationCause(cause.cause)}),\n          })",
    '? cause', 'request-cancel-failure', 'request-cancel-failure-custody', [], 'packages/sdk/internal/submission-observation.mjs'],
  ['request cancellation acceptance claims physical stop and release',
    '    requestId: context.requestId, ...(problem === undefined ? {} : {problem}),',
    '    requestId: context.requestId, stopped: true, resourcesReleased: true, ...(problem === undefined ? {} : {problem}),',
    'request-cancel-stop', 'request-cancel-physical-claim', [], 'packages/sdk/operation-presentation.mjs'],
  ["request cancellation accepted becomes already terminal",
    "return retainRequestCancellationExplanation(freezeInput(answer), context, answer.kind);",
    "return retainRequestCancellationExplanation(freezeInput(answer), context, 'already_terminal');",
    "request-cancel-public",
    "request-cancel-public",
    [],
    "packages/sdk/internal/submission-observation.mjs"],
  ['request cancellation response loss becomes accepted',
    "'outcome_unknown', 'exchange_failed');", "'accepted');",
    'request-cancel-loss', 'request-cancel-loss', [], 'packages/sdk/internal/submission-observation.mjs'],
  ["request cancellation preparation response becomes already terminal",
    "return retainRequestCancellationExplanation(freezeInput(answer), context, answer.kind);",
    "return retainRequestCancellationExplanation(freezeInput(answer), context, 'already_terminal');",
    "request-cancel-preparation",
    "request-cancel-preparation",
    [],
    "packages/sdk/internal/submission-observation.mjs"],
  ['request observation failures reuse the borrowed exception',
    '  const retained = new ClientError(code,\n    Number.isInteger(status) && status >= 100 && status <= 599 ? {status} : {});',
    '  const retained = error;', 'request-error-custody', 'request-failure-custody', [], 'packages/sdk/internal/submission-observation.mjs'],
  ["request observation loses detached checkpoint custody",
    "try { answer = captureResponse(answer); }\n      catch { throw retainRequestLookupFailure(new ClientError('InvalidHostRequestLookup'), context, 'lookup_uninterpretable'); }",
    "try { answer = answer; }\n      catch { throw retainRequestLookupFailure(new ClientError('InvalidHostRequestLookup'), context, 'lookup_uninterpretable'); }",
    "request-snapshot",
    "request-lookup-detached",
    [],
    "packages/sdk/internal/submission-observation.mjs"],
  ["request observation skips copied-response revalidation",
    "try { answer = captureResponse(answer); }\n      catch { throw retainRequestLookupFailure(new ClientError('InvalidHostRequestLookup'), context, 'lookup_uninterpretable'); }",
    "try { answer = structuredClone(captureResponse(answer)); }\n      catch { throw retainRequestLookupFailure(new ClientError('InvalidHostRequestLookup'), context, 'lookup_uninterpretable'); }",
    "request-admission",
    "request-lookup-admission",
    [],
    "packages/sdk/internal/submission-observation.mjs"],
  ["submission observation permits a copied durable reply to change its branch",
    "attempt = captureResponse(await controlValue(response));",
    "attempt = structuredClone(captureResponse(await controlValue(response)));",
    "submission-copy",
    "request-held-admission",
    [],
    "packages/sdk/internal/submission-observation.mjs"],
  ['request observation loses the submitted held preparation state',
    "observation: 'request_held', preparationState: answer.state,",
    "observation: 'request_held', preparationState: undefined,", 'request-held-state', 'request-held-state', [], 'packages/sdk/operation-presentation.mjs'],
  ['request observation presents ended preparation as resuming',
    'preparationState: answer.state,', "preparationState: answer.state === 'ended' ? 'resuming' : answer.state,",
    'request-ended-public', 'request-ended-public', [], 'packages/sdk/operation-presentation.mjs'],
  ['request observation treats lookup absence as a Run reference',
    "const observation = answer.kind === 'found' ? 'run_reference_received' :\n" +
      "    answer.kind === 'not_found' ? 'lookup_unresolved'",
    "const observation = answer.kind === 'found' ? 'run_reference_received' :\n" +
      "    answer.kind === 'not_found' ? 'run_reference_received'",
    'request-absent-public', 'request-public-observation', [], 'packages/sdk/operation-presentation.mjs'],
  ['request observation copies acquire original custody',
    'const requestLookupExplanations = new WeakMap();',
    'const requestLookupExplanations = {values: new Map(), set(key, value) {this.values.set(JSON.stringify(key), value);}, get(key) {return this.values.get(JSON.stringify(key));}};',
    'request-custody', 'request-observation-custody', [], 'packages/sdk/internal/submission-observation.mjs'],

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
    'check-locale-control', 'check-locale-control', [], 'packages/sdk/check-presentation.mjs'],
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
    'check-locale-snapshot', 'check-locale-snapshot', [], 'packages/sdk/check-presentation.mjs'],
  ['unknown submit loses its original input',
    "const submissionUnknown = (context, cause) => {\n  const result = new ClientError('SubmissionUnknown', {...context, cause});\n  const input = submissionContexts.get(context);\n  if (input) submissionInputs.set(result, input);",
    "const submissionUnknown = (context, cause) => {\n  const result = new ClientError('SubmissionUnknown', {...context, cause});\n  const input = submissionContexts.get(context);", 'after-commit', undefined, [], 'packages/sdk/internal/submission-observation.mjs'],
  ["original supplied parameters are replaced by null",
    "const snapshot = Object.freeze({...body, requestId, connection: selected.wire,",
    "const snapshot = Object.freeze({...body, parameters: null, requestId, connection: selected.wire,",
    "after-commit",
    undefined,
    [],
    "packages/sdk/internal/submission-observation.mjs"],
  ['accepted handle loses its original input',
    '        submissionInputs.set(run, snapshot);', '', 'acceptance', undefined, [], 'packages/sdk/internal/submission-observation.mjs'],
  ['unknown acceptance is presented as a held request',
    "submissionLookupExplanation('acceptance_unknown', input)",
    "submissionLookupExplanation('request_held', input)",
    'after-commit', 'submission-explanation', [], 'packages/sdk/internal/submission-observation.mjs'],
  ['submission explanation loses the original lookup identity',
    'submissionRef: input.submissionRef}),',
    'submissionRef: {...input.submissionRef, nonce: "wrong-request"}}),',
    'after-commit', 'submission-explanation', [], 'packages/sdk/operation-presentation.mjs'],
  ['submission explanation exposes a private transport cause',
    "submissionLookupExplanation('acceptance_unknown', input));",
    "freezeInput({...submissionLookupExplanation('acceptance_unknown', input), cause: cause.message}));",
    'after-commit', 'submission-explanation', [], 'packages/sdk/internal/submission-observation.mjs'],
  ['received Run reference is presented as unknown acceptance',
    "observation: 'run_reference_received',", "observation: 'acceptance_unknown',",
    'acceptance', 'submission-explanation', [], 'packages/sdk/operation-presentation.mjs'],
  ['cancellation acceptance is presented as physical stop and release',
    "accepted: 'The Host recorded a Run cancellation request. Refresh Run state for physical stop, Effects and release.'",
    "accepted: 'The Run has stopped and all resources have been released.'",
    'cancellation-recorded', 'cancel-explanation', [], 'packages/sdk/operation-presentation.mjs'],
  ['typed cancellation refusal loses its invocation explanation',
    'return retainCancellationAttemptExplanation(received, context);',
    'return received;', 'cancellation-attempt-refused', 'cancel-attempt-refused', [], 'packages/sdk/internal/run-observation.mjs'],
  ['typed cancellation refusal claims global uncommitted custody',
    "...(result.kind === 'refused' ? {guarantee: result.guarantee} : {}),",
    "...(result.kind === 'refused' ? {guarantee: 'cancellation_never_committed'} : {}),",
    'cancellation-attempt-refused', 'cancel-attempt-refused', [], 'packages/sdk/operation-presentation.mjs'],
  ['typed cancellation conflict substitutes another expected revision',
    'attemptRef: context.attemptRef, cancelRef: context.cancelRef,',
    'attemptRef: context.attemptRef, cancelRef: {...context.cancelRef, expectedRevision: context.cancelRef.expectedRevision + 1},',
    'cancellation-attempt-conflict', 'cancel-attempt-conflict', [], 'packages/sdk/operation-presentation.mjs'],
  ['typed cancellation copies acquire original explanation custody',
    'const cancellationExplanations = new WeakMap();',
    'const cancellationExplanations = {values: new Map(), set(key, value) {this.values.set(JSON.stringify(key), value);}, get(key) {return this.values.get(JSON.stringify(key));}};',
    'cancellation-attempt-custody', 'cancel-attempt-custody', [], 'packages/sdk/internal/run-observation.mjs'],
  ["unknown cancellation is presented as confirmed acceptance",
    "return freezeInput({observation,\n    ...(revision === undefined ? {} : {revision}), summary: summaries[observation],",
    "return freezeInput({observation: observation === 'outcome_unknown' ? 'accepted' : observation,\n    ...(revision === undefined ? {} : {revision}), summary: summaries[observation],",
    "cancellation-unknown",
    "cancel-unknown-explanation",
    [],
    "packages/sdk/operation-presentation.mjs"],
  ['cancellation observation advice targets another Run',
    ": {operation: 'status', ref: context.ref}",
    ": {operation: 'status', ref: {...context.ref, runDefinitionCid: 'sha256:' + '0'.repeat(64)}}",
    'cancellation-recorded', 'cancel-explanation', [], 'packages/sdk/operation-presentation.mjs'],
  ['unknown cancellation recommends another cancellation write',
    "? {operation: 'lookupCancellation', cancelRef: context.cancelRef}",
    "? {operation: 'cancel', ref: context.ref}",
    'cancellation-unknown', 'cancel-unknown-explanation', [], 'packages/sdk/operation-presentation.mjs'],
  ['cancellation explanation exposes a private transport message',
    '...(revision === undefined ? {} : {revision}), summary: summaries[observation],',
    '...(revision === undefined ? {} : {revision}), summary: result.cause?.message ?? summaries[observation],',
    'cancellation-unknown', 'cancel-unknown-explanation', [], 'packages/sdk/operation-presentation.mjs'],
  ["local cancellation response-format failure loses uncertainty",
    "if (!wasCancellationDispatched(context)) throw cause;",
    "if (cause?.code === 'InvalidLocalHostPortResponse') throw new ClientError(cause.code);\n          if (!wasCancellationDispatched(context)) throw cause;",
    "cancellation-format",
    "cancel-format-uncertainty",
    [],
    "packages/sdk/internal/run-observation.mjs"],
  ["cancellation response reuse changes an earlier Run observation",
    "received = captureResponse(response);",
    "received = response;",
    "cancellation-custody",
    "cancel-custody",
    [["received = freezeInput(received);\n        return retainCancellationAttemptExplanation(received, context);","return retainCancellationAttemptExplanation(received, context);"]],
    "packages/sdk/internal/run-observation.mjs"],
  ['cancellation clone failure leaks an unassociated error',
    "        let received;\n        try {\n          received = captureResponse(response);",
    "        let received = structuredClone(captureResponse(response));\n        try {\n          received = captureResponse(response);",
    'cancellation-clone:clone throws', 'cancel-clone-invalid', [], 'packages/sdk/internal/run-observation.mjs'],
  ["cancellation clone erasure bypasses copy and shape validation",
    "if (!validCancellationAttempt(received, cancelRef, attemptRef)) fail('InvalidHostCancellation');",
    "if (false) fail('InvalidHostCancellation');",
    "cancellation-clone:clone erases fields",
    "cancel-clone-invalid",
    [],
    "packages/sdk/internal/run-observation.mjs"],
  ...['namespaceId', 'authorityScopeCid', 'runDefinitionCid'].map(field => [
    `cancellation clone bypasses ${field} association`,
    "if (!validCancellationAttempt(received, cancelRef, attemptRef)) fail('InvalidHostCancellation');",
    `if (!validCancellationAttempt(received, {...cancelRef, ${field}: received.cancellation.cancelRef.${field}}, attemptRef)) fail('InvalidHostCancellation');`,
    `cancellation-clone:clone changes ${field}`, 'cancel-clone-invalid', [],
    'packages/sdk/internal/run-observation.mjs',
  ]),
  ['check reporting budget is blamed on an invalid input',
    'The reporting budget could not produce a complete bound check report.',
    'The submitted input is invalid.', 'check-outcome-reporting', 'check-outcome-explanation', [], 'packages/sdk/check-presentation.mjs'],
  ['check verification is presented as execution and release success',
    "The report verifies only its selected checking scope and context.",
    'Execution and release succeeded.', 'check-outcome-reporting', 'check-outcome-explanation', [], 'packages/sdk/check-presentation.mjs'],
  ['check partial report is presented as complete',
    "reportExplanation(outcome.partial_report, 'partial')",
    "reportExplanation(outcome.partial_report, 'complete')",
    'check-outcome-partial', 'check-outcome-partial', [], 'packages/sdk/check-presentation.mjs'],
  ['check unavailable is presented as completed',
    "return freezeInput({outcome: 'unavailable',",
    "return freezeInput({outcome: 'completed',",
    'check-outcome-unavailable', 'check-outcome-unavailable', [], 'packages/sdk/check-presentation.mjs'],
  ['check explanation bypasses malformed outcome validation',
    'export function explainCheckOutcome(outcome, options) {\n  if (!validCheckOutcome(outcome)) return undefined;',
    'export function explainCheckOutcome(outcome, options) {',
    'check-outcome-validation', 'check-outcome-invalid', [], 'packages/sdk/check-presentation.mjs'],

  ["check response reuse overwrites original input custody",
    "try { outcome = captureResponse(outcome); }",
    "try { outcome = outcome; }",
    "check-custody",
    "check-response-custody",
    [],
    "packages/sdk/internal/check-observation.mjs"],

  ["copied check response loses its wire shape without refusal",
    "if (!validCheckOutcome(outcome)) reject();",
    "if (false) reject();",
    "check-shape",
    "check-copied-shape",
    [],
    "packages/sdk/internal/check-observation.mjs"],

  ["check response accepts a known location in another input document",
    "if (!validCheckOutcome(outcome)) reject();",
    "",
    "check-location-domain",
    "known-location-domain",
    [],
    "packages/sdk/internal/check-observation.mjs"],

  ['check Problem explanation loses its opaque correlation',
    "return freezeInput({outcome: 'failed', summary, hint, correlationRef, problem,",
    "return freezeInput({outcome: 'failed', summary, hint, problem,",
    'check-problem-explanation', 'check-problem-explanation', [], 'packages/sdk/check-presentation.mjs'],
  ['check outcome bypasses its schema identity pin',
    'valid(value, schemas.check_outcome) && value.outcome_schema_cid === checkOutcomeSchemaCid;',
    'valid(value, schemas.check_outcome);',
    'check-schema-pin', 'check-outcome-pin'],

  ['frontier comparison discards the bound context',
    'return structuralKey(left) === structuralKey(right);',
    'return structuralKey({...left, contextRef: "ignored"}) === structuralKey({...right, contextRef: "ignored"});',
    'frontier-context', 'frontier-context', [], 'packages/sdk/internal/check-observation.mjs'],
  ['frontier comparison treats presentation order as progress',
    "requirements: unordered(report.requirements.map(({code, facts}) =>\n      ({code, facts: facts.admission === undefined ? facts : {...facts,\n        admission: {...facts.admission, constraints: unordered(facts.admission.constraints)}}}))),",
    'requirements: report.requirements.map(({code, facts}) => ({code, facts})),',
    'frontier-order', 'frontier-order', [], 'packages/sdk/internal/check-observation.mjs'],
  ['frontier session repeats an unchanged obligation set',
    'previous && structuralKey(previous) === structuralKey(frontier)', 'false',
    'frontier-stalled', 'frontier-stalled', [], 'packages/sdk/internal/check-observation.mjs'],
  ['frontier session resets the attempt cap after changing context',
    'const frontier = getCheckRequirementFrontier(outcome);',
    'const frontier = getCheckRequirementFrontier(outcome);\n' +
      '        if (previous && previous.contextRef !== frontier?.contextRef) attempts = 1;',
    'frontier-budget', 'frontier-budget-count', [], 'packages/sdk/internal/check-observation.mjs'],

];
const accepted = (phase, assertion) => {
  const tests = expected(phase, assertion);
  const file = phase === 'unresolvable-restart' ? 'adapters/host-node/client-submission-custody-public.test.mjs'
    : phase === 'submission-attempt-custody' ? 'packages/sdk/submission-attempt.test.mjs'
    : phase === 'submission-attempt-refused' || phase === 'submission-attempt-conflict'
      ? 'adapters/host-node/submission-epoch-public.test.mjs'
    : phase === 'cancellation-attempt-custody' ? 'packages/sdk/cancel-identity.test.mjs'
    : phase === 'cancellation-attempt-refused' || phase === 'cancellation-attempt-conflict'
      ? 'adapters/host-node/client-cancellation-attempt-public.test.mjs'
    : phase === 'submission-copy' ? 'packages/sdk/submission-identity.test.mjs'
    : phase.startsWith('operation-input-') ? operationInputAcceptance
    : phase === 'request-cancel-preparation' ? preparationAcceptance
    : phase === 'request-record-loss' ? 'adapters/host-node/client-request-record-loss.test.mjs'
    : ['request-cancel-public', 'request-cancel-stop', 'request-cancel-loss'].includes(phase) ? cancellationAcceptance
    : phase === 'request-ended-public' ? preparationAcceptance
    : phase === 'request-absent-public' ? acceptance
    : phase.startsWith('request-') ? requestAcceptance
    : phase === 'check-locale-snapshot' ? sdkAcceptance
    : phase.startsWith('frontier-') || phase.startsWith('check-') ? checkAcceptance
    : phase.startsWith('cancellation-') ? cancellationAcceptance : acceptance;
  const escape = value => value.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&');
  const result = spawnSync(process.execPath, ['scripts/local-checks.mjs', 'test', 'node',
    '--timeout-seconds', '120', '--', '--test-name-pattern',
    `^(?:${tests.map(value => escape(value.name)).join('|')})$`, file],
  {encoding: 'utf8', timeout: 130000, maxBuffer: 16 * 1024 * 1024});
  return mutationAcceptance(result, tests, file);
};
const args = process.argv.slice(2);
if (args.length && (args.length !== 2 || args[0] !== '--match' || !args[1])) {
  throw new Error('Usage: check-submission-input-mutations.mjs [--match name-substring]');
}
const selected = mutations.filter(([name]) => args.length === 0 || name.includes(args[1]));
if (!selected.length) throw new Error('No SDK mutations selected');
// Split SDK owners are explicit recipe metadata, never guessed from a path.
const mutationPath = (phase, sourceFile) => sourceFile ?? (phase.startsWith('operation-input-')
  ? 'src/program_check/diagnostic_category.mbt'
  : ['check-expression-type', 'check-operation-parameter', 'check-frame-explanation'].includes(phase)
  ? 'packages/sdk/check-reason-catalog.generated.js' : phase === 'check-schema-pin'
  ? 'packages/client-wire/client-host.generated.js'
  : phase === 'check-locale-fallback' ? 'packages/sdk/check-presentation.mjs' : path);
const originals = new Map(selected.map(([, , , phase, , , sourceFile]) => mutationPath(phase, sourceFile))
  .map(file => [file, readFileSync(file, 'utf8')]));
// A parent local gate already owns the worktree lock. Keep this bounded
// compiler child in its process group rather than acquiring a nested gate.
const buildOperationInputRuntime = () => execFileSync('moon',
  ['build', '--target', 'js', '--release', 'src/connectors_builtin_node'],
  {stdio: 'inherit', timeout: 120000});
const groups = new Map(selected.map(([, , , phase, assertion]) =>
  [phase + ':' + (assertion ?? 'submission-input'), {phase, assertion}]));
const baselines = [...groups.values()].map(({phase, assertion}) =>
  ({phase, assertion, accepted: accepted(phase, assertion)}));
if (baselines.some(result => !result.accepted)) throw new Error('Mutation baseline refused');
const results = [];
try {
  for (const [name, from, to, phase, assertion, additional = [], sourceFile] of selected) {
    const file = mutationPath(phase, sourceFile);
    const original = originals.get(file);
    if (original.split(from).length !== 2) throw new Error(`Mutation anchor not unique: ${name}`);
    let altered = original.replace(from, to);
    // Some faults must bypass a second current defense to reach the same named assertion.
    for (const [anchor, replacement] of additional) {
      if (altered.split(anchor).length !== 2) throw new Error(`Additional fault anchor not unique: ${name}`);
      altered = altered.replace(anchor, replacement);
    }
    if (phase === 'unresolvable-restart') {
      for (const [anchor, replacement] of [
        ['  const submitIntent = (kind, input, options, sourceProducer, requestName) => {',
          '  let unsafeRestartInput;\n  const submitIntent = (kind, input, options, sourceProducer, requestName) => {'],
        ['    submissionInputs.set(pending, snapshot);',
          '    unsafeRestartInput = snapshot;\n    submissionInputs.set(pending, snapshot);'],
      ]) {
        if (altered.split(anchor).length !== 2) throw new Error(`Restart fault anchor not unique: ${name}`);
        altered = altered.replace(anchor, replacement);
      }
    }
    if (phase === 'operation-input-range') {
      const capacity = '                | InvalidSeriesCount(ReversedRange)\n';
      if (altered.split(capacity).length !== 2) throw new Error(`Capacity fault anchor not unique: ${name}`);
      altered = altered.replace(capacity, '');
    }
    writeFileSync(file, altered);
    if (phase.startsWith('operation-input-')) buildOperationInputRuntime();
    results.push({name, phase, rejected: !accepted(phase, assertion)});
    writeFileSync(file, original);
  }
} finally {
  for (const [file, original] of originals) writeFileSync(file, original);
  if (originals.has('src/program_check/diagnostic_category.mbt')) buildOperationInputRuntime();
}
const restoredSources = [...originals].every(([file, original]) => readFileSync(file, 'utf8') === original);
const restoredAccepted = [...groups.values()].every(({phase, assertion}) => accepted(phase, assertion));
console.log(JSON.stringify({baselines, mutations: results, restoredSources, restoredAccepted}, null, 2));
if (!restoredSources || !restoredAccepted || results.some(result => !result.rejected)) process.exitCode = 1;
