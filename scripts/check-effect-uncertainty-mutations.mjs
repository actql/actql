// Reuse the strict named-assertion guard. Infrastructure failures cannot
// establish that an unsafe diagnostic mutation was detected.
import {spawnSync} from 'node:child_process';
import {readFileSync, writeFileSync} from 'node:fs';
import {mutationAcceptance} from './check-disclosure-mutations.mjs';

const path = 'packages/sdk/index.mjs';
const boundary = 'adapters/host-node/client-effect-uncertainty.test.mjs';
const unit = 'packages/sdk/effect-uncertainty.test.mjs';
const publicCases = ['local', 'https'].map(entrance => ({
  name: `${entrance}: unresolved Effect keeps its identity after computation stops`,
  assertions: [{id: 'effect-explanation', operator: 'deepStrictEqual'}],
}));
const controlCases = ['status', 'wait', 'reconcile'].map(operation => ({
  name: `${operation}: Effect uncertainty retains only validated Owner observations`,
  assertions: [{id: 'effect-control', operator: 'deepStrictEqual'}],
}));
const custodyCases = [{
  name: 'Local response reuse cannot rebind an earlier Effect explanation to another Run',
  assertions: [{id: 'effect-custody', operator: 'deepStrictEqual'}],
}];
const mutations = [
  ['an unresolved Effect is presented as successful',
    "observation: 'effect_outcome_unknown',", "observation: 'succeeded',", boundary, publicCases],
  ['the retained Effect names are erased',
    'effects: [...state.next_action.effects],', 'effects: [],', boundary, publicCases],
  ['read-only advice becomes permission to submit again',
    "next: {operation: 'status', ref: {...ref}},",
    "next: {operation: 'submit', ref: {...ref}},", boundary, publicCases],
  ['the original Run reference is replaced',
    "next: {operation: 'status', ref: {...ref}},",
    "next: {operation: 'status', ref: {...ref, namespaceId: 'wrong-run'}},", boundary, publicCases],
  ['absent or unknown physical stop is presented as confirmed',
    "physicalStop: state.control?.physical_stop ?? 'unknown',",
    "physicalStop: 'confirmed',", unit, controlCases],
  ['a reused Local response rebinds an earlier observation to another Run',
    '    state = structuredClone(state);', '', unit, custodyCases],
];

const accepted = (file, expected) => {
  const escape = value => value.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&');
  const result = spawnSync(process.execPath, ['scripts/local-checks.mjs', 'test', 'node',
    '--timeout-seconds', '120', '--', '--test-name-pattern',
    `^(?:${expected.map(value => escape(value.name)).join('|')})$`, file],
  {encoding: 'utf8', timeout: 130_000, maxBuffer: 16 * 1024 * 1024});
  return mutationAcceptance(result, expected, file);
};
const original = readFileSync(path, 'utf8');
const results = [];
try {
  for (const [name, from, to, file, expected] of mutations) {
    if (original.split(from).length !== 2) throw new Error(`Mutation anchor not unique: ${name}`);
    writeFileSync(path, original.replace(from, to));
    results.push({name, rejected: !accepted(file, expected)});
  }
} finally { writeFileSync(path, original); }
const restoredAccepted = accepted(boundary, publicCases) &&
  accepted(unit, controlCases) && accepted(unit, custodyCases);
console.log(JSON.stringify({mutations: results, restoredAccepted}, null, 2));
if (!restoredAccepted || results.some(result => !result.rejected)) process.exitCode = 1;
