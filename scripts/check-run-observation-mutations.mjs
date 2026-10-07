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
const mutations = [
  {name: 'borrowed response getters replace the first captured facts', path, file: unit,
    from: 'const captureHostResponse = value => cloneHostResponse(value);',
    to: 'const captureHostResponse = value => value;',
    targets: ['status', 'wait', 'reconcile', 'lookupRequest', 'held submit', 'cancel', 'deliveryAttempt'].map(operation => target(
      `${operation}: response fields are captured once before admission`,
      {status: 'response-capture-run', wait: 'response-capture-run', reconcile: 'response-capture-run',
        lookupRequest: 'response-capture-lookup', 'held submit': 'response-capture-held',
        cancel: 'response-capture-cancel', deliveryAttempt: 'response-capture-delivery'}[operation],
      ['status', 'wait', 'reconcile'].includes(operation) ? 'strictEqual' : 'deepStrictEqual'))},
  {name: 'first response capture uses a redirected clone', path, file: unit,
    from: 'const captureHostResponse = value => cloneHostResponse(value);',
    to: 'const captureHostResponse = value => globalThis.structuredClone(value);',
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
