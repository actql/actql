// Focused faults reuse the existing strict named-assertion verifier and guard.
// Import errors, exceptions, timeouts and unselected tests are infrastructure failures.
import {spawnSync} from 'node:child_process';
import {readFileSync, writeFileSync} from 'node:fs';
import {mutationAcceptance} from './check-disclosure-mutations.mjs';

const path = 'src/connectors_builtin_node/client_check.mbt';
const publicTests = 'adapters/host-node/client-check.test.mjs';
const target = (name, id, operator = 'strictEqual') => ({name, assertions: [{id, operator}]});
const locationTargets = (id, operator) => ['local', 'http'].map(entrance => target(
  `${entrance}: function-limit locations retain caller bytes and cannot blame hidden dependencies`, id, operator));
const mutations = [
  {name: 'unsupported authored span replaced', path, file: publicTests,
    from: 'findings.push(FunctionLimit(check_authored_range(origin)))',
    to: 'findings.push(FunctionLimit(Some((0, 1))))',
    targets: locationTargets('function-position-bytes', 'deepStrictEqual'), build: true},
  {name: 'unresolved function form blamed on author', path, file: publicTests,
    from: 'findings.push(FunctionLimit(check_authored_range(origin)))',
    to: 'findings.push(Violation("query_invalid"))',
    targets: locationTargets('function-position-verdict'), build: true},
  {name: 'function material fabricated behind a protected relation', path, file: publicTests,
    from: 'QueryLowering(UnknownRelation) =>\n          findings.push(Unresolved("source_resolution"))',
    to: 'QueryLowering(UnknownRelation) => {\n          findings.push(Unresolved("source_resolution"))\n          findings.push(FunctionLimit(Some((7, 26))))\n        }',
    targets: locationTargets('function-position-protected', 'deepStrictEqual'), build: true},
  {name: 'SDK skips original limit boundary admission', path: 'packages/sdk/index.mjs', file: publicTests,
    from: 'for (const reason of [...report.reasons, ...(report.requirements ?? []), ...report.coverage.limits])',
    to: 'for (const reason of [...report.reasons, ...(report.requirements ?? [])])',
    targets: ['local', 'http'].map(entrance => target(
      `${entrance}: malformed function-limit locations reject as protocol observations`, 'function-position-admission', 'rejects'))},
];
const args = process.argv.slice(2);
if (args.length && (args.length !== 2 || args[0] !== '--match' || !args[1])) {
  throw new Error('Usage: check-function-limit-mutations.mjs [--match name-substring]');
}
const selected = mutations.filter(item => !args.length || item.name.includes(args[1]));
if (!selected.length) throw new Error('No function-limit mutations selected');
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
