// Bounded mutations of SDK input custody reuse the exact named-assertion guard.
// Import, timeout and unselected-test failures never establish detection.
import {spawnSync} from 'node:child_process';
import {readFileSync, writeFileSync} from 'node:fs';
import {mutationAcceptance} from './check-disclosure-mutations.mjs';

const path = 'packages/sdk/index.mjs';
const acceptance = 'adapters/host-node/client-submission-input.test.mjs';
const expected = phase => ['local', 'https'].map(entrance => ({
  name: `${entrance}: program submission inputs survive ${phase}`,
  assertions: [{id: 'submission-input', operator: 'deepStrictEqual'}],
}));
const mutations = [
  ['unknown submit loses its original input',
    '  if (input) submissionInputs.set(result, input);', '', 'after-commit'],
  ['original supplied parameters are replaced by null',
    'const snapshot = freezeInput({...body, connection: selected.wire,',
    'const snapshot = freezeInput({...body, parameters: null, connection: selected.wire,',
    'after-commit'],
  ['accepted handle loses its original input',
    '    submissionInputs.set(result, snapshot);', '', 'acceptance'],
];
const accepted = phase => {
  const tests = expected(phase);
  const result = spawnSync(process.execPath, ['scripts/local-checks.mjs', 'test', 'node',
    '--timeout-seconds', '120', '--', '--test-name-pattern',
    `^(?:${tests.map(value => value.name).join('|')})$`, acceptance],
  {encoding: 'utf8', timeout: 130000, maxBuffer: 16 * 1024 * 1024});
  return mutationAcceptance(result, tests, acceptance);
};
const original = readFileSync(path, 'utf8');
const results = [];
try {
  for (const [name, from, to, phase] of mutations) {
    if (original.split(from).length !== 2) throw new Error(`Mutation anchor not unique: ${name}`);
    writeFileSync(path, original.replace(from, to));
    results.push({name, phase, rejected: !accepted(phase)});
  }
} finally {
  writeFileSync(path, original);
}
const restoredAccepted = accepted('after-commit') && accepted('acceptance');
console.log(JSON.stringify({mutations: results, restoredAccepted}, null, 2));
if (!restoredAccepted || results.some(result => !result.rejected)) process.exitCode = 1;
