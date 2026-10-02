// On-demand mutation run for the public check projection in MoonBit. Each
// mutation is applied to the source, the runtime is rebuilt and the public
// check acceptance must fail; the source is restored and the acceptance must
// pass again. Host-owner (JavaScript) mutations run in the acceptance itself.
// Run: node scripts/check-disclosure-mutations.mjs (needs `moon` on PATH).
import {execFileSync, spawnSync} from 'node:child_process';
import {readFileSync, writeFileSync} from 'node:fs';

const path = 'src/connectors_builtin_node/client_check.mbt';
const acceptance = 'adapters/host-node/client-check.test.mjs';
const mutations = [
  ['a protected obligation hides the disclosable violation',
    'QueryLowering(UnknownRelation) =>\n' +
    '          findings.push(Unresolved("source_resolution"))',
    'QueryLowering(UnknownRelation) => {\n' +
    '          findings.clear()\n' +
    '          findings.push(Unresolved("source_resolution"))\n' +
    '        }'],
  ['an unresolved obligation is reported as a violation',
    'if findings.iter().any(finding => finding is Violation(_)) {\n' +
    '    "invalid"',
    'if findings.iter().any(finding => !(finding is Limit(_))) {\n' +
    '    "invalid"'],
  ['an exhausted construction budget is reported as a failure',
    '          )\n        ) => findings.push(Limit("analysis_budget_exhausted"))',
    '          )\n        ) => return Failed("check_internal")'],
  ['a missing value is reported as a violation',
    'Ok(NeedsBindings(_)) => findings.push(Limit("bound_values_missing"))',
    'Ok(NeedsBindings(_)) => findings.push(Violation("bound_values_missing"))'],
];

const build = () => execFileSync('moon', ['build', '--target', 'js',
  '--release', 'src/connectors_builtin_node'], {stdio: 'inherit'});
const accepted = () => spawnSync(process.execPath, ['--test', acceptance],
  {stdio: 'ignore'}).status === 0;

const original = readFileSync(path, 'utf8');
const results = [];
try {
  for (const [name, from, to] of mutations) {
    if (original.split(from).length !== 2) {
      throw new Error(`Mutation anchor not unique: ${name}`);
    }
    writeFileSync(path, original.replace(from, to));
    build();
    results.push({name, rejected: !accepted()});
  }
} finally {
  writeFileSync(path, original);
  build();
}
const restored = accepted();
console.log(JSON.stringify({mutations: results, restoredAccepted: restored},
  null, 2));
if (!restored || results.some(result => !result.rejected)) process.exitCode = 1;
