// Small faults reuse the existing named-test/assertion verifier. Infrastructure
// failures cannot count as detection, and every source/runtime is restored.
import {readFileSync, writeFileSync} from 'node:fs';
import {execFileSync, spawnSync} from 'node:child_process';
import {mutationAcceptance} from './check-disclosure-mutations.mjs';
const file = 'adapters/host-node/client-check.test.mjs';
const core = 'src/connectors_builtin_node/client_check.mbt';
const factsCase = 'numeric profile requirements preserve the common checking frontier';
const protectedCase = 'protected source resolution hides numeric profile requirements';
const targets = (name, id, operator) => ['local', 'http'].map(entrance => ({
  name: `${entrance}: ${name}`, assertions: [{id, operator}]}));
const mutations = [
  {name: 'known numeric profile condition is omitted', path: core,
    from: 'findings.push(NumericProfileRequired)\n        findings.push(Limit("checking_context_missing"))',
    to: 'findings.push(Limit("checking_context_missing"))',
    targets: targets(factsCase, 'numeric-requirement-facts', 'deepStrictEqual')},
  {name: 'numeric profile absence is blamed on caller input', path: core,
    from: 'findings.push(NumericProfileRequired)\n        findings.push(Limit("checking_context_missing"))',
    to: 'findings.push(NumericProfileRequired)\n        findings.push(Violation("query_input_invalid"))',
    targets: targets(factsCase, 'numeric-requirement-verdict', 'strictEqual')},
  {name: 'protected source resolution fabricates a context selection', path: core,
    from: 'findings.push(Unresolved("source_resolution"))',
    to: '{ findings.push(Unresolved("source_resolution")); findings.push(NumericProfileRequired) }',
    targets: targets(protectedCase, 'numeric-requirement-protected', 'deepStrictEqual')},
  {name: 'copied response acquires original context custody', path: 'packages/sdk/index.mjs',
    from: "export function getCheckContextRequirements(outcome) {\n  if (!checkInputs.has(outcome) || outcome.outcome !== 'completed') return undefined;",
    to: "export function getCheckContextRequirements(outcome) {\n  if (outcome.outcome !== 'completed') return undefined;",
    targets: targets(factsCase, 'numeric-requirement-custody', 'strictEqual')},
];
const build = () => execFileSync(process.execPath, ['scripts/local-checks.mjs', 'build', 'moon',
  '--timeout-seconds', '180', '--', '--target', 'js', '--release', 'src/connectors_builtin_node'], {stdio: 'inherit'});
const run = item => {
  const escape = text => text.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&');
  const result = spawnSync(process.execPath, ['scripts/local-checks.mjs', 'test', 'node',
    '--timeout-seconds', '120', '--', '--test-name-pattern',
    `^(?:${item.targets.map(target => escape(target.name)).join('|')})$`, file],
  {encoding: 'utf8', timeout: 130000, maxBuffer: 16 * 1024 * 1024});
  return mutationAcceptance(result, item.targets, file);
};
const results = [];
for (const item of mutations) {
  const original = readFileSync(item.path, 'utf8');
  if (original.split(item.from).length !== 2) throw new Error(`Mutation anchor not unique: ${item.name}`);
  if (!run(item)) throw new Error(`Baseline failed: ${item.name}`);
  let rejected;
  try {
    writeFileSync(item.path, original.replace(item.from, item.to));
    if (item.path === core) build();
    rejected = !run(item);
  } finally {
    writeFileSync(item.path, original);
    if (item.path === core) build();
  }
  const restoredAccepted = run(item);
  results.push({name: item.name, rejected, restoredAccepted, targets: item.targets});
  if (!rejected || !restoredAccepted) throw new Error(`Undetected or unrestored mutation: ${item.name}`);
}
console.log(JSON.stringify({mutations: results}, null, 2));
