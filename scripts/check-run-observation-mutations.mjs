// Focused faults reuse the existing strict named-assertion verifier and guard.
// Import errors, exceptions, timeouts and unselected tests are infrastructure failures.
import {spawnSync} from 'node:child_process';
import {readFileSync, writeFileSync} from 'node:fs';
import {mutationAcceptance} from './check-disclosure-mutations.mjs';

const path = 'packages/sdk/index.mjs';
const unit = 'packages/sdk/run-observation-protocol.test.mjs';
const publicTests = 'adapters/host-node/client-cancel-response-loss.test.mjs';
const target = (name, id, operator = 'strictEqual') => ({name, assertions: [{id, operator}]});
const unitTargets = id => ['status', 'wait', 'reconcile'].map(operation => target(
  `${operation}: rejected Run observations distinguish unknown state from malformed known facts`, id, 'deepStrictEqual'));
const publicTargets = ['in-process', 'https'].map(entrance => target(
  `${entrance}: uninterpretable Run observations retain only the original authorized lookup`, 'run-protocol-public-rejection'));
const validationCopyFaults = [
  [['status', 'wait', 'reconcile'], 'response-capture-run', 'strictEqual',
    'return retainEffectUncertainty(observation, ref);', 'return retainEffectUncertainty(state, ref);'],
  [['lookupRequest'], 'response-capture-lookup', 'deepStrictEqual',
    'return retainRequestLookupExplanation(freezeInput(observation), context);',
    'return retainRequestLookupExplanation(freezeInput(answer), context);'],
  [['held submit'], 'response-capture-held', 'deepStrictEqual',
    '      admitted = observation;\n      const held', '      const held'],
  [['cancel'], 'response-capture-cancel', 'deepStrictEqual',
    '  return value;\n};\n\nconst unordered',
    '  return copy;\n};\n\nconst unordered'],
  [['deliveryAttempt'], 'response-capture-delivery', 'deepStrictEqual',
    'return retainDeliveryExplanation(freezeInput(observation), {',
    'return retainDeliveryExplanation(freezeInput(answer), {'],
  [['check'], 'response-capture-check', 'deepStrictEqual',
    '        outcome = observation;', ''],
  [['cancelRequest'], 'response-capture-request-cancel', 'deepStrictEqual',
    'return retainRequestCancellationExplanation(freezeInput(observation), context, observation.kind);',
    'return retainRequestCancellationExplanation(freezeInput(answer), context, answer.kind);'],
];
const originalSnapshotFaults = [
  [['status', 'wait', 'reconcile'], "        if (structuralKey(observation) !== observedKey) {\n          throw rejectedRunObservation(ref, operation, 'malformed_response');\n        }"],
  [['lookupRequest'], "      if (structuralKey(observation) !== observedKey) throw retainRequestLookupFailure(new ClientError('InvalidHostRequestLookup'), context, 'lookup_uninterpretable');"],
  [['held submit'], "        if (structuralKey(observation) !== observedKey) fail('InvalidHostAdmission');"],
  [['cancel'], 'structuralKey(value) !== observedKey', 'false'],
  [['deliveryAttempt'], "            if (structuralKey(observation) !== observedKey) fail('InvalidHostAttemptLookup');"],
  [['check'], '        if (structuralKey(observation) !== observedKey) reject();'],
  [['cancelRequest'], "        if (structuralKey(observation) !== observedKey) throw new ClientError('InvalidHostRequestCancellation');"],
];
const mutations = [
  {name: 'control public observation accepts a previous real Owner reply', path,
    file: 'adapters/host-node/client-run-control-revisions.test.mjs',
    from: 'control.revision < latestControl.revision', to: 'false',
    targets: [target('https: real publication and physical-stop revisions retain private SDK control custody',
      'run-control-public-revision')]},
  {name: 'control public observation borrows a mutable returned value', path,
    file: 'adapters/host-node/client-run-control-revisions.test.mjs',
    from: 'latestControl = freezeInput({...control});', to: 'latestControl = control;',
    targets: ['local', 'https'].map(entrance => target(
      `${entrance}: real publication and physical-stop revisions retain private SDK control custody`,
      'run-control-public-custody'))},
  {name: 'control observation accepts an older revision', path,
    file: 'packages/sdk/run-control-revisions.test.mjs',
    from: 'control.revision < latestControl.revision', to: 'false',
    targets: ['status', 'wait', 'reconcile'].map(operation => target(
      `${operation}: an older Run control revision cannot replace a newer observation`,
      'run-control-revision', 'strictEqual'))},
  {name: 'control observation accepts contradictory facts at the same revision', path,
    file: 'packages/sdk/run-control-revisions.test.mjs',
    from: 'structuralKey(control) !== structuralKey(latestControl)', to: 'false',
    targets: ['cancellation_requested', 'physical_stop'].map(field => target(
      `same revision cannot change the original ${field} fact`, 'run-control-conflict', 'strictEqual'))},
  {name: 'control observation does not retain the latest completed revision', path,
    file: 'packages/sdk/run-control-revisions.test.mjs',
    from: 'latestControl = freezeInput({...control});', to: '',
    targets: ['status', 'wait', 'reconcile'].map(operation => target(
      `${operation}: a delayed older reply is rejected after a newer concurrent observation`,
      'run-control-completion-order', 'strictEqual'))},
  {name: 'control observation borrows a mutable returned value', path,
    file: 'packages/sdk/run-control-revisions.test.mjs',
    from: 'latestControl = freezeInput({...control});', to: 'latestControl = control;',
    targets: [target('mutating a previously returned observation cannot replace the private control revision',
      'run-control-custody', 'strictEqual')]},
  {name: 'unavailable Run observation loses original SDK custody', path,
    file: 'adapters/host-node/client-run-observation-unavailable.test.mjs',
    from: "  runObservationFailures.set(error, freezeInput({kind: 'unavailable',",
    to: "  new WeakMap().set(error, freezeInput({kind: 'unavailable',",
    targets: ['local', 'https'].map(entrance => target(
      `${entrance}: unavailable Run observations preserve publication and original lookup`,
      'run-unavailable-public', 'deepStrictEqual'))},
  {name: 'unavailable Run observation substitutes another original Run', path,
    file: 'packages/sdk/run-observation-unavailable.test.mjs',
    from: "problem: 'observation_unavailable', operation,\n    next: {operation: 'status', ref: {...ref}},",
    to: "problem: 'observation_unavailable', operation,\n    next: {operation: 'status', ref: {...ref, runDefinitionCid: `sha256:${'0'.repeat(64)}`}},",
    targets: [target('Run observation reused failures and later success do not rebind earlier targets',
      'run-unavailable-custody', 'deepStrictEqual')]},
  {name: 'unavailable Run observation exposes a private transport cause', path,
    file: 'packages/sdk/run-observation-unavailable.test.mjs',
    from: '  try { error = requestCancellationCause(failure); }',
    to: '  try { error = Object.assign(requestCancellationCause(failure), {cause: failure}); }',
    targets: ['status', 'wait', 'reconcile'].map(operation => target(
      `${operation}: unavailable Run observation retains only the original read-only target`,
      'run-unavailable-disclosure', 'doesNotMatch'))},
  {name: 'unavailable Run observation propagates unreadable failure metadata', path,
    file: 'packages/sdk/run-observation-unavailable.test.mjs',
    from: "  catch { error = new ClientError('ClientTransportUnknown'); }",
    to: '  catch { throw failure; }',
    targets: ['code', 'status'].map(field => target(
      `unreadable ${field} metadata cannot replace an unavailable Run observation`,
      'run-unavailable-metadata', 'deepStrictEqual'))},
  {name: 'unavailable Run observation is misclassified as malformed received facts', path,
    file: 'packages/sdk/run-observation-unavailable.test.mjs',
    from: "  runObservationFailures.set(error, freezeInput({kind: 'unavailable',",
    to: "  runObservationFailures.set(error, freezeInput({kind: 'protocol_failure',",
    targets: ['status', 'wait', 'reconcile'].map(operation => target(
      `${operation}: unavailable Run observation retains only the original read-only target`,
      'run-unavailable-facts', 'deepStrictEqual'))},
  {name: 'delivery lookup failure drops original custody', path,
    file: 'adapters/host-node/client-delivery-lookup-failure.test.mjs',
    from: '  deliveryExplanations.set(error, freezeInput({observation,',
    to: '  new WeakMap().set(error, freezeInput({observation,',
    targets: ['local', 'https'].map(entrance => target(
      `${entrance}: rejected Delivery lookups preserve original read custody and published Run`,
      'delivery-lookup-public-facts', 'deepStrictEqual'))},
  {name: 'delivery lookup failure substitutes a foreign read operation', path,
    file: 'packages/sdk/delivery-lookup-failure.test.mjs',
    from: '  deliveryExplanations.set(error, freezeInput({observation,',
    to: "  next = {...next, attemptId: 'foreign-read'};\n  deliveryExplanations.set(error, freezeInput({observation,",
    targets: [target('delivery lookup reused errors and subsequent success preserve earlier uncertainty',
      'delivery-lookup-original-target', 'deepStrictEqual')]},
  {name: 'delivery lookup failure retains a private transport cause', path,
    file: 'packages/sdk/delivery-lookup-failure.test.mjs',
    from: '  const error = requestCancellationCause(cause);',
    to: '  const error = Object.assign(requestCancellationCause(cause), {cause});',
    targets: [target('delivery lookup exchange failures retain only original authorized lookup advice',
      'delivery-lookup-failure-disclosure', 'doesNotMatch')]},
  {name: 'cancellation lookup drops the admitted explanation', path,
    file: 'adapters/host-node/client-cancellation-public.test.mjs',
    from: "return retainCancellationExplanation(freezeInput(owned), context,\n            owned.kind === 'found' ? owned.cancellation.kind : 'outcome_unknown',\n            owned.kind === 'found' ? owned.cancellation.revision : undefined);",
    to: 'return freezeInput(owned);',
    targets: ['local', 'https'].flatMap(entrance => ['before-commit', 'after-commit'].map(loss => target(
      `${entrance}: original cancellation lookup after ${loss} loss and process restart uses a successful Run`,
      'cancel-lookup-public', 'deepStrictEqual')))},
  {name: 'cancellation lookup turns unknown custody into a terminal observation', path,
    file: 'adapters/host-node/client-cancellation-public.test.mjs',
    from: "owned.kind === 'found' ? owned.cancellation.kind : 'outcome_unknown'",
    to: "owned.kind === 'found' ? owned.cancellation.kind : 'already_terminal'",
    targets: ['local', 'https'].map(entrance => target(
      `${entrance}: original cancellation lookup after before-commit loss and process restart uses a successful Run`,
      'cancel-lookup-public', 'deepStrictEqual'))},
  {name: 'cancellation lookup input reobserves the original operation identity', path,
    file: 'packages/sdk/cancellation-lookup-explanation.test.mjs',
    from: 'const capturedReference = captureResponse(reference);', to: 'const capturedReference = reference;',
    targets: [target('cancellation lookup captures the first cancelId before admission',
      'cancel-lookup-input-once', 'deepStrictEqual')]},
  {name: 'cancellation lookup input clone substitutes the original operation', path,
    file: 'packages/sdk/cancellation-lookup-explanation.test.mjs',
    from: 'cancelRef = freezeInput(detachResponse(capturedReference));',
    to: 'cancelRef = freezeInput(structuredClone(capturedReference));',
    targets: ['replacement', 'mutation'].map(fault => target(
      `cancellation lookup rejects input clone ${fault} before dispatch`, 'cancel-lookup-input-copy'))},
  {name: 'connection profile capture reobserves borrowed context', path,
    file: 'packages/sdk/profile-observation.test.mjs',
    from: '    profile = captureResponse(profile);', to: '',
    targets: [target('connection: profile fields are captured once before admission', 'profile-capture-once')]},
  ...['replacement', 'mutation'].map(fault => ({
    name: `connection profile verification admits ${fault} of the captured context`, path,
    file: 'adapters/host-node/client-profile-observation.test.mjs',
    from: fault === 'replacement'
      ? "    if (structuralKey(profile) !== observedKey) fail('InvalidHostProfile');"
      : "    if (structuralKey(observation) !== observedKey) fail('InvalidHostProfile');",
    to: '', targets: ['local', 'https'].map(entrance => target(
      `${entrance}: rejected profile ${fault} cannot start checking or issue a verdict`, `profile-public-${fault}`)),
  })),
  ...originalSnapshotFaults.map(([operations, from, to = '']) => ({
    name: `verification conversion changes the captured ${operations.join('/')} snapshot`,
    path, file: unit, from, to, targets: operations.map(operation => target(
      `${operation}: verification conversion cannot mutate the admitted snapshot`, 'response-capture-original')),
  })),
  {name: 'response capture reobserves borrowed getters during admission', path,
    file: 'packages/sdk/response-capture.test.mjs',
    from: 'const captureResponse = (value, captured = new Map()) => {',
    to: 'const captureResponse = (value, captured = new Map()) => { return value;',
    targets: ['status', 'wait', 'reconcile', 'lookup-request', 'submit', 'cancel', 'delivery-attempt']
      .map(operation => target(`${operation}: capture observes response getters once before admission`,
        'response-capture-once'))},
  {name: 'borrowed cancellation reference getters replace the first captured facts', path, file: publicTests,
    from: 'const captureResponse = (value, captured = new Map()) => {',
    to: 'const captureResponse = (value, captured = new Map()) => { return value;',
    targets: ['namespaceId', 'authorityScopeCid', 'runDefinitionCid'].map(field => target(
      `in-process: cancellation captures the first getter-backed ${field} association`,
      'cancel-reference-capture'))},
  ...validationCopyFaults.map(([operations, id, operator, from, to]) => ({
    name: `validation copy replaces the captured ${operations.join('/')} observation`, path, file: unit, from, to,
    targets: operations.map(operation => target(
      `${operation}: validation-copy getters cannot rebind admitted facts`, id, operator)),
  })),
  {name: 'borrowed response getters replace the first captured facts', path, file: unit,
    from: 'const captureResponse = (value, captured = new Map()) => {',
    to: 'const captureResponse = (value, captured = new Map()) => { return value;',
    targets: ['status', 'wait', 'reconcile', 'lookupRequest', 'held submit', 'cancel', 'deliveryAttempt'].map(operation => target(
      `${operation}: response fields are captured once before admission`,
      {status: 'response-capture-run', wait: 'response-capture-run', reconcile: 'response-capture-run',
        lookupRequest: 'response-capture-lookup', 'held submit': 'response-capture-held',
        cancel: 'response-capture-cancel', deliveryAttempt: 'response-capture-delivery'}[operation],
      ['status', 'wait', 'reconcile'].includes(operation) ? 'strictEqual' : 'deepStrictEqual'))},
  {name: 'first response capture uses a redirected clone', path, file: unit,
    from: 'const captureResponse = (value, captured = new Map()) => {',
    to: 'const captureResponse = (value, captured = new Map()) => { return globalThis.structuredClone(value);',
    targets: ['lookupRequest', 'held submit', 'cancel', 'deliveryAttempt', 'check'].map(operation => target(
      `${operation}: a well-shaped clone cannot replace captured facts`, 'response-capture-copy'))},
  {name: 'unknown state classified as a known failure', path, file: unit,
    from: "kind: problem === 'unknown_state' ? 'uninterpretable' : 'protocol_failure',",
    to: "kind: 'protocol_failure',", targets: unitTargets('run-protocol-kind')},
  {name: 'original Run lookup identity replaced', path, file: unit,
    from: "next: {operation: 'status', ref: {...ref}},\n  }));\n  return error;",
    to: "next: {operation: 'status', ref: {...ref, namespaceId: 'foreign-namespace'}},\n  }));\n  return error;",
    targets: unitTargets('run-protocol-ref')},
  {name: 'caller presentation edit changes observation kind', path, file: unit,
    from: "return localizeOperation(runObservationFailures.get(error), 'observation', options);",
    to: "const view = localizeOperation(runObservationFailures.get(error), 'observation', options); return view && {...view, kind: error.kind ?? view.kind};",
    targets: unitTargets('run-protocol-presentation')},
  {name: 'unknown state admission bypass', path, file: publicTests, occurrences: 2,
    from: 'if (!validRunState(state)) throw rejectedRunObservation(ref, operation, problem);',
    to: '', targets: publicTargets},
  {name: 'malformed known state admission bypass', path, file: publicTests, occurrences: 2,
    from: 'if (!validRunState(state)) throw rejectedRunObservation(ref, operation, problem);',
    to: "if (state.status !== 'running' && !validRunState(state)) throw rejectedRunObservation(ref, operation, problem);", targets: publicTargets},
  {name: 'valid copied Run facts replace the received observation', path, file: unit,
    from: "        if (structuralKey(state) !== observedKey) {\n          throw rejectedRunObservation(ref, operation, 'malformed_response');\n        }",
    to: '', targets: ['status', 'wait', 'reconcile'].flatMap(operation =>
      ['execution and publication', 'Run identity', 'observation time', 'control revision',
        'physical stop', 'Effect identity', 'Result availability'].map(fact => target(
        `${operation}: copied Run observation cannot replace ${fact}`, 'run-copy-preservation')))},
  {name: 'Effect presentation replaces admitted facts with a secondary copy', path, file: unit,
    from: '    effectUncertainties.set(state, freezeInput({',
    to: '    state = structuredClone(state);\n    effectUncertainties.set(state, freezeInput({',
    targets: ['status', 'wait', 'reconcile'].map(operation => target(
      `${operation}: later Effect projection cannot replace admitted Run facts`,
      'run-effect-projection-copy', 'deepStrictEqual'))},
  {name: 'public copied Run facts replace their original owner facts', path, file: publicTests,
    from: "        if (structuralKey(state) !== observedKey) {\n          throw rejectedRunObservation(ref, operation, 'malformed_response');\n        }",
    to: '', targets: ['local', 'https'].map(entrance => target(
      `${entrance}: copied Run observations retain original owner facts`, 'run-copy-public'))},
];
const args = process.argv.slice(2);
if (args.length && (args.length !== 2 || args[0] !== '--match' || !args[1])) {
  throw new Error('Usage: check-run-observation-mutations.mjs [--match name-substring]');
}
const selected = mutations.filter(item => !args.length || item.name.includes(args[1]));
if (!selected.length) throw new Error('No Run observation mutations selected');
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
