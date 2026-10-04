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
    'if findings\n    .iter()\n    .any(finding => {\n' +
    '      finding\n      is (Violation(_)\n      | SyntaxViolation(_, _)\n' +
    '      | TypeViolation(_, _, _)\n      | UndeclaredParameter(_, _))\n    }) {\n' +
    '    "invalid"',
    'if findings.iter().any(finding => !(finding is Limit(_))) {\n' +
    '    "invalid"'],
  ['an exhausted construction budget is reported as a failure',
    '          )\n        ) => findings.push(Limit("analysis_budget_exhausted"))',
    '          )\n        ) => return Failed("check_internal")'],
  ['a supplied-value budget is reported as a violation',
    'Budget => findings.push(Limit("analysis_budget_exhausted"))',
    'Budget => findings.push(Violation("supplied_value_invalid"))'],
  ['a missing value is reported as a violation',
    'Ok(NeedsBindings(missing)) => {\n            findings.push(Limit("bound_values_missing"))',
    'Ok(NeedsBindings(missing)) => {\n            findings.push(Violation("bound_values_missing"))'],
  ['an authored UTF-8 location is shifted by one byte',
    '@encode.number_value(writer, start.to_double())',
    '@encode.number_value(writer, (start + 1).to_double())'],
];

const build = () => execFileSync(process.execPath, ['scripts/local-checks.mjs',
  'build', 'moon', '--', '--target', 'js', '--release',
  'src/connectors_builtin_node'], {stdio: 'inherit'});
const accepted = () => {
  const result = spawnSync(process.execPath, ['scripts/local-checks.mjs',
    'test', 'node', '--', '--test-name-pattern',
    'authored syntax|a disclosable violation|absent and denied|exhausted analysis budget|parameter budgets|supplied type',
    acceptance], {encoding: 'utf8'});
  // Only executed acceptance failures count as rejection. Compilation,
  // import, timeout and zero-selection failures are infrastructure faults.
  if (result.status !== 0 && !/fail [1-9][0-9]*/u.test(result.stdout)) {
    throw new Error(`Mutation acceptance did not run: ${result.stdout}\n${result.stderr}`);
  }
  return result.status === 0;
};

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
