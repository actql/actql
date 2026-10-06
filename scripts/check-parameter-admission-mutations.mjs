// Focused faults reuse the existing strict named-assertion verifier and guard.
// Import errors, exceptions, timeouts and unselected tests are infrastructure failures.
import {spawnSync} from 'node:child_process';
import {readFileSync, writeFileSync} from 'node:fs';
import {mutationAcceptance} from './check-disclosure-mutations.mjs';

const path = 'packages/sdk/index.mjs';
const publicTests = 'adapters/host-node/client-check.test.mjs';
const target = (name, id, operator = 'strictEqual') => ({name, assertions: [{id, operator}]});
const admissionTargets = (id, operator) => ['local', 'http'].map(entrance => target(
  `${entrance}: missing parameter Requirements expose admitted recursive declaration conditions`, id, operator));
const mutations = [
  {name: 'admitted numeric minimum changed during projection', path: 'src/connectors_builtin_node/client_check_requirements.mbt', file: publicTests,
    from: '@encode.key(writer, "minimum")\n          @encode.number_value(writer, bound)',
    to: '@encode.key(writer, "minimum")\n          @encode.number_value(writer, bound + 1.0)',
    targets: admissionTargets('admission-public-facts', 'deepStrictEqual'), build: true},
  {name: 'private annotation text exposed in a rule path', path: 'src/connectors_builtin_node/client_check_requirements.mbt', file: publicTests,
    from: '  for part in path {',
    to: '  let exposed = path.copy()\n  exposed.push(Field("private-admission-note"))\n  for part in exposed {',
    targets: admissionTargets('admission-public-disclosure', 'doesNotMatch'), build: true},
  {name: 'copies recover original admission custody', path, file: publicTests,
    from: "if (!checkInputs.has(outcome) || outcome.outcome !== 'completed' ||\n      typeof parameter !== 'string') return undefined;",
    to: "if (outcome.outcome !== 'completed' ||\n      typeof parameter !== 'string') return undefined;",
    targets: admissionTargets('admission-public-custody')},
  {name: 'constraint row order resets the supplementation frontier', path, file: publicTests,
    from: 'constraints: unordered(facts.admission.constraints)', to: 'constraints: facts.admission.constraints',
    targets: ['local', 'http'].map(entrance => target(
      `${entrance}: Requirement rule ordering cannot create supplementation progress`, 'admission-public-frontier', 'deepStrictEqual'))},
];
const args = process.argv.slice(2);
if (args.length && (args.length !== 2 || args[0] !== '--match' || !args[1])) {
  throw new Error('Usage: check-parameter-admission-mutations.mjs [--match name-substring]');
}
const selected = mutations.filter(item => !args.length || item.name.includes(args[1]));
if (!selected.length) throw new Error('No parameter admission mutations selected');
const run = item => {
  const escape = text => text.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&');
  const result = spawnSync(process.execPath,
    ['scripts/local-checks.mjs', 'test', 'node', '--timeout-seconds', '120', '--',
      '--test-name-pattern', `^(?:${item.targets.map(value => escape(value.name)).join('|')})$`, item.file],
    {encoding: 'utf8', timeout: 130000, maxBuffer: 16 * 1024 * 1024});
  return mutationAcceptance(result, item.targets, item.file);
};
const build = item => {
  if (!item.build) return;
  const result = spawnSync(process.execPath, ['--input-type=module', '-e',
    `import {runLocalCheck} from './scripts/local-checks-guard.mjs'; process.exitCode=await runLocalCheck({root:process.cwd(),timeoutSeconds:180,graceSeconds:5,heavy:false,steps:[{name:'reporting producer mutation build',command:process.execPath,args:['scripts/build-runtime-packages.mjs','run-host-core','local-node']}]});`],
    {encoding: 'utf8', timeout: 190000, maxBuffer: 16 * 1024 * 1024});
  if (result.status !== 0 || result.error || result.signal) {
    throw new Error(`Mutation build infrastructure failed: ${item.name}`, {cause: result.error});
  }
};
const results = [];
for (const item of selected) {
  const original = readFileSync(item.path, 'utf8');
  if (original.split(item.from).length !== (item.occurrences ?? 1) + 1) throw new Error(`Mutation anchor not unique: ${item.name}`);
  if (!run(item)) throw new Error(`Baseline failed: ${item.name}`);
  let rejected;
  try {
    writeFileSync(item.path, original.replaceAll(item.from, item.to));
    build(item);
    rejected = !run(item);
  } finally {
    writeFileSync(item.path, original);
    build(item);
  }
  const restoredAccepted = run(item);
  results.push({name: item.name, rejected, restoredAccepted, targets: item.targets});
  if (!rejected || !restoredAccepted) throw new Error(`Undetected or unrestored mutation: ${item.name}`);
}
console.log(JSON.stringify({mutations: results}, null, 2));
