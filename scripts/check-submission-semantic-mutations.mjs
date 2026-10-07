// Existing strict named-assertion verification separates faults from failures
// to build, import, select or execute the intended received-response cases.
import {spawnSync} from 'node:child_process';
import {readFileSync, writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {mutationAcceptance} from './check-disclosure-mutations.mjs';
import {runLocalCheck} from './local-checks-guard.mjs';

const selected = process.argv[2];
if (!['js', 'native'].includes(selected) || process.argv.length !== 3) {
  throw new Error('Usage: check-submission-semantic-mutations.mjs js|native');
}
const execute = "import {runFocusedTests} from './scripts/test-execution.mjs'; process.exitCode=runFocusedTests('node',process.argv.slice(1),{cwd:process.cwd()});";
const cases = ['location revision mismatch', 'location beyond original byte bound',
  'duplicate source documents', 'fix target revision mismatch', 'fix begins before EOF'];
const expected = cases.map(name => ({name: `${selected === 'js' ? 'JS ' : ''}submission check: ${name}`,
  assertions: [{id: selected === 'js' ? 'submission-semantic-js' : 'submission-semantic-refusal',
    operator: 'strictEqual'}]}));
const file = selected === 'js' ? 'packages/client-wire/submission-check-semantics.test.mjs'
  : 'scripts/test-native-client-wire.test.mjs';
const path = selected === 'js' ? 'packages/client-wire/client-host.generated.js'
  : 'src/cmd/native_client/wire.generated.mbt';
const from = selected === 'js' ? 'export const validCheckOutcomeContract = value => {'
  : '  if !wire_check_report_contract(value) {\n    return false\n  }';
const to = selected === 'js' ? from + ' return validCheckOutcomeShape(value);' : '';
const original = readFileSync(path, 'utf8');
if (original.split(from).length !== 2) throw new Error('SemanticMutationAnchorNotUnique');
const run = () => {
  const escaped = expected.map(value => value.name.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&'));
  const result = spawnSync(process.execPath, ['--input-type=module', '-e', execute, '--',
    '--test-name-pattern', `^(?:${escaped.join('|')})$`, file],
  {encoding: 'utf8', timeout: 45000, maxBuffer: 16 * 1024 * 1024});
  return mutationAcceptance(result, expected, file);
};
const build = () => {
  if (selected !== 'native') return;
  const result = spawnSync('moon', ['build', '--target', 'native', '--release', 'src/cmd/native_client'],
    {encoding: 'utf8', timeout: 120000, maxBuffer: 16 * 1024 * 1024});
  if (result.error || result.signal || result.status !== 0) {
    throw new Error(`SemanticMutationBuildFailed: ${result.stderr}`);
  }
};
const worker = async () => {
  console.log('Semantic mutation: baseline build and named cases');
  build();
  if (!run()) throw new Error('SemanticMutationBaselineFailed');
  let rejected;
  try {
    writeFileSync(path, original.replace(from, to));
    console.log('Semantic mutation: fault build and exact assertion detection');
    build(); rejected = !run();
  } finally {
    writeFileSync(path, original); build();
  }
  console.log('Semantic mutation: restored named cases');
  const restoredAccepted = run();
  console.log(JSON.stringify({target: selected, rejected, restoredAccepted, expected}, null, 2));
  if (!rejected || !restoredAccepted) throw new Error('SemanticMutationUndetectedOrUnrestored');
};
if (process.env.ACTQL_SEMANTIC_MUTATION_WORKER === selected) {
  await worker();
} else {
  process.exitCode = await runLocalCheck({root: process.cwd(), heavy: selected === 'native',
    timeoutSeconds: selected === 'native' ? 300 : 60, graceSeconds: 5,
    steps: [{name: `${selected} received-report semantic fault and restoration`,
      command: process.execPath, args: [fileURLToPath(import.meta.url), selected],
      env: {...process.env, ACTQL_SEMANTIC_MUTATION_WORKER: selected}}]});
}
