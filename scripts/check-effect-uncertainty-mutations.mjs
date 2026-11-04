// Reuse the strict named-assertion guard. Infrastructure failures cannot
// establish that an unsafe diagnostic mutation was detected.
import {spawnSync} from 'node:child_process';
import {readFileSync, writeFileSync} from 'node:fs';
import {mutationAcceptance} from './check-disclosure-mutations.mjs';

const path = 'packages/sdk/operation-presentation.mjs';
const boundary = 'adapters/host-node/client-effect-uncertainty.test.mjs';
const unit = 'packages/sdk/effect-uncertainty.test.mjs';
const publicCases = ['local', 'https'].map(entrance => ({
  name: `${entrance}: unresolved Effect keeps its identity after computation stops`,
  assertions: [{id: 'effect-explanation', operator: 'deepStrictEqual'},
    {id: 'operation-effect-public-locale', operator: 'deepStrictEqual'}],
}));
const controlCases = ['status', 'wait', 'reconcile'].map(operation => ({
  name: `${operation}: Effect uncertainty retains only validated Owner observations`,
  assertions: [{id: 'effect-control', operator: 'deepStrictEqual'}],
}));
const custodyCases = [{
  name: 'Local response reuse cannot rebind an earlier Effect explanation to another Run',
  assertions: [{id: 'effect-custody', operator: 'deepStrictEqual'},
    {id: 'effect-custody', operator: 'strictEqual'}],
}];
const copiedShapeCases = kinds => ['status', 'wait', 'reconcile'].flatMap(operation =>
  kinds.map(kind => ({
    name: `Local ${operation}: Effect custody refuses ${kind} clone failure or shape loss`,
    assertions: [{id: 'effect-copied-shape', operator: 'strictEqual'}],
  })));
const ownerCases = ['local', 'https'].map(entrance => ({
  name: `${entrance}: unresolved Effect keeps its identity after computation stops`,
  assertions: [{id: 'effect-no-resend', operator: 'strictEqual'}],
}));
const physicalExchange = `    const response = await receive({
      ...operation,
      secret,
      ca,
      cert,
      key,
      signal,
      maxResponseBytes,
      binding,
      retainRunResponseOriginal,
      observeResponseBytes,
    });`;
const ownerObservationCase = (name, id) => [{name, assertions: [{id, operator: 'strictEqual'}]}];
const ownerObservationUnit = 'packages/sdk/owner-observations.test.mjs';
const mutations = [
  ['SDK Owner observation explains independent views as atomic',
    "...answer, owners, observation: 'owner_views',",
    "...answer, owners, consistency: 'atomic', observation: 'owner_views',", ownerObservationUnit,
    ownerObservationCase('SDK explains retention_expired from the original Owner facts without I/O', 'owner-consistency')],
  ['SDK Owner observation turns retained history gaps into current-only views',
    'history: advice(view.history, ownerHistoryAdvice[view.history.kind])',
    "history: advice({...view.history, kind: 'not_provided'}, ownerHistoryAdvice[view.history.kind])", ownerObservationUnit,
    ownerObservationCase('SDK explains retention_expired from the original Owner facts without I/O', 'owner-history-kind')],
  ['SDK Owner observation grants copied responses explanation custody',
    "ownerObservationExplanations.get(result), 'ownerObservations', options",
    "ownerObservationExplanations.get(result) ?? result, 'ownerObservations', options", ownerObservationUnit,
    ownerObservationCase('SDK explains retention_expired from the original Owner facts without I/O', 'owner-copy'), false, 'packages/sdk/internal/run-observation.mjs'],
  ['SDK Owner observation fabricates a protected stream identity',
    "if (view.kind === 'unavailable') return advice(view, view.problem === undefined ? [",
    "if (view.kind === 'unavailable') return advice({...view, ownerRef: {kind: view.owner, scopeCid: 'private', streamCid: 'private'}}, view.problem === undefined ? [", ownerObservationUnit,
    [{name: 'SDK keeps snapshot acquisition, protected streams and unmatched cursors separate',
      assertions: [{id: 'owner-protected', operator: 'deepStrictEqual'}]}]],
  ['a lost Effect reply automatically resends the authorized physical write',
    physicalExchange,
    `    const physicalOptions = { ...operation, secret, ca, cert, key, signal, maxResponseBytes,
      binding, retainRunResponseOriginal, observeResponseBytes };
    const response = await receive(physicalOptions).catch(() => receive(physicalOptions));`,
    boundary, ownerCases, false, 'adapters/site-node/https-credential-resource.mjs'],
  ['an unresolved Effect is presented as successful',
    "observation: 'effect_outcome_unknown',", "observation: 'succeeded',", boundary, publicCases],
  ['the retained Effect names are erased',
    'effects: [...state.next_action.effects],', 'effects: [],', boundary, publicCases],
  ['reconciliation advice becomes permission to submit again',
    "controlRevision: state.control.revision}),\n      next: {operation: 'reconcile', ref: {...ref}},",
    "controlRevision: state.control.revision}),\n      next: {operation: 'submit', ref: {...ref}},", boundary, publicCases],
  ['the original Run reference is replaced',
    "controlRevision: state.control.revision}),\n      next: {operation: 'reconcile', ref: {...ref}},",
    "controlRevision: state.control.revision}),\n      next: {operation: 'reconcile', ref: {...ref, namespaceId: 'wrong-run'}},", boundary, publicCases],
  ['the original Effect reconciliation candidate becomes a status lookup',
    "controlRevision: state.control.revision}),\n      next: {operation: 'reconcile', ref: {...ref}},",
    "controlRevision: state.control.revision}),\n      next: {operation: 'status', ref: {...ref}},", unit, controlCases],
  ['absent or unknown physical stop is presented as confirmed',
    "physicalStop: state.control?.physical_stop ?? 'unknown',",
    "physicalStop: 'confirmed',", unit, controlCases],
  ['a reused Local response rebinds an earlier observation to another Run',
    'export const captureResponse = (value, captured = new Map()) => {',
    'export const captureResponse = (value, captured = new Map()) => { return value;',
    unit, custodyCases, false, 'packages/sdk/internal/data.mjs'],
  ['a Local Effect reply clone failure loses the SDK refusal',
    "      try { state = captureResponse(state); }\n" +
      "      catch { throw rejectedRunObservation(ref, operation, 'malformed_response'); }",
    "      try { state = captureResponse(state); }\n      catch (cause) { throw cause; }",
    unit, copiedShapeCases(['proxy']), false, 'packages/sdk/internal/run-observation.mjs'],
  ['a Local Effect reply bypasses native shape-loss admission',
    "        if (!(operation === 'wait' ? validRunWaitContract(state, body.since)\n" +
      "          : validRunState(state))) throw rejectedRunObservation(ref, operation, problem);",
    '', unit, copiedShapeCases(['date', 'control-date', 'action-date']), false,
    'packages/sdk/internal/run-observation.mjs'],
];

const accepted = (file, expected) => {
  const escape = value => value.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&');
  const result = spawnSync(process.execPath, ['scripts/local-checks.mjs', 'test', 'node',
    '--timeout-seconds', '120', '--', '--test-name-pattern',
    `^(?:${expected.map(value => escape(value.name)).join('|')})$`, file],
  {encoding: 'utf8', timeout: 130_000, maxBuffer: 16 * 1024 * 1024});
  return mutationAcceptance(result, expected, file);
};
const originals = new Map(mutations.map(([, , , , , , mutationPath = path]) =>
  [mutationPath, readFileSync(mutationPath, 'utf8')]));
const results = [];
const args = process.argv.slice(2);
if (args.length && (args.length !== 2 || args[0] !== '--match' || !args[1])) {
  throw new Error('Usage: check-effect-uncertainty-mutations.mjs [--match name-substring]');
}
const selected = mutations.filter(([name]) => !args.length || name.includes(args[1]));
if (!selected.length) throw new Error('No operation observation mutations selected');
// Refuse stale anchors before starting any actual acceptance processes.
for (const [name, from, , , , , mutationPath = path] of mutations) {
  const original = originals.get(mutationPath);
  if (original.split(from).length !== 2) throw new Error(`Mutation anchor not unique: ${name}`);
}
const groups = new Map(selected.map(([, , , file, expected]) =>
  [JSON.stringify([file, expected]), {file, expected}]));
const baselines = [...groups.values()].map(({file, expected}) =>
  ({file, names: expected.map(test => test.name), accepted: accepted(file, expected)}));
if (baselines.some(result => !result.accepted)) throw new Error('Mutation baseline refused');
try {
  for (const [name, from, to, file, expected, , mutationPath = path] of selected) {
    const original = originals.get(mutationPath);
    if (original.split(from).length !== 2) throw new Error(`Mutation anchor not unique: ${name}`);
    let altered = original.replace(from, to);
    writeFileSync(mutationPath, altered);
    try { results.push({name, rejected: !accepted(file, expected)}); }
    finally { writeFileSync(mutationPath, original); }
  }
} finally {
  for (const [mutationPath, original] of originals) writeFileSync(mutationPath, original);
}
const restoredSources = [...originals].every(([target, original]) => readFileSync(target, 'utf8') === original);
const restorations = new Map(selected.map(([, , , file, expected]) =>
  [JSON.stringify([file, expected]), {file, expected}]));
const restoredAccepted = [...restorations.values()]
  .every(({file, expected}) => accepted(file, expected));
console.log(JSON.stringify({baselines, mutations: results, restoredSources, restoredAccepted}, null, 2));
if (!restoredSources || !restoredAccepted || results.some(result => !result.rejected)) process.exitCode = 1;
