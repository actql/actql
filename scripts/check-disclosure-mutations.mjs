// On-demand mutation run for the public check projection in MoonBit. Each
// mutation is applied to the source, the runtime is rebuilt and the public
// check acceptance must fail; the source is restored and the acceptance must
// pass again. Host-owner (JavaScript) mutations run in the acceptance itself.
// Run: node scripts/check-disclosure-mutations.mjs (needs `moon` on PATH).
import {execFileSync, spawnSync} from 'node:child_process';
import {readFileSync, realpathSync, writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {parseTestExecution} from './test-execution.mjs';

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

const targets = [
  ['a disclosable violation is reported beside a protected source', ['public-violation']],
  ['a disclosable violation is reported beside a protected source', ['protected-unresolved']],
  ['an exhausted analysis budget is undetermined, not invalid or failed', ['construction-budget']],
  ['parameter budgets are limits, never violations', ['binding-budget']],
  ['supplied type violations and missing values expose different typed facts', ['missing-value']],
  ['authored syntax locations retain exact UTF-8 input revisions', ['syntax-outcome', 'syntax-location']],
];

// Reuse the common reporter and nonzero-execution evidence. A process failure
// alone never establishes that an intended acceptance assertion detected a fault.
export function mutationAcceptance(result, expected, file = acceptance) {
  const fault = () => { throw new Error('Mutation verification infrastructure failure: ' +
    `${result.error?.code ?? result.signal ?? result.status}\n${result.stdout ?? ''}\n${result.stderr ?? ''}`); };
  if (result.error || result.signal || ![0, 1].includes(result.status)) fault();
  if (/Local check stopped:|evidence write failed/iu.test(result.stderr ?? '')) fault();
  // Selected acceptance cases have no diagnostic events. Reject any such
  // event, including asynchronous exceptions after an assertion has failed.
  if ((result.stdout ?? '').split(/\r?\n/u)
    .some(line => line.startsWith('ACTQL_TEST_DIAGNOSTIC '))) fault();
  let evidence, cases;
  try {
    evidence = parseTestExecution('node', result.stdout ?? '');
    cases = (result.stdout ?? '').split(/\r?\n/u)
      .filter(line => line.startsWith('ACTQL_TEST_CASE '))
      .map(line => JSON.parse(line.slice('ACTQL_TEST_CASE '.length)));
  } catch { fault(); }
  const counts = evidence.counts;
  if (counts.tests !== expected.length || counts.cancelled || counts.skipped || counts.todo ||
      cases.length !== expected.length || counts.passed + counts.failed !== expected.length) fault();
  const seen = new Set();
  for (const entry of cases) {
    const target = expected.find(value => value.name === entry.name);
    let sameFile = false;
    try { sameFile = typeof entry.file === 'string' && realpathSync(entry.file) === realpathSync(file); }
    catch { /* Unavailable files cannot establish target execution. */ }
    if (!target || seen.has(entry.name) || typeof entry.file !== 'string' ||
        !sameFile || typeof entry.passed !== 'boolean' ||
        entry.skipped || entry.todo) fault();
    seen.add(entry.name);
    if (!entry.passed && (entry.failureType !== 'testCodeFailure' ||
        entry.errorCode !== 'ERR_ASSERTION' ||
        !['strictEqual', 'deepStrictEqual'].includes(entry.operator) ||
        typeof entry.errorMessage !== 'string' ||
        !target.assertions.some(id => entry.errorMessage.startsWith(`[check-mutation:${id}]`)))) fault();
  }
  const failed = cases.filter(entry => !entry.passed).length;
  if (failed !== counts.failed || (result.status === 0
    ? failed !== 0 || !evidence.success : failed === 0 || evidence.success)) fault();
  return result.status === 0;
}

const expectedCases = ([name, assertions]) => ['local', 'http'].map(entrance =>
  ({name: `${entrance}: ${name}`, assertions}));

const build = () => execFileSync(process.execPath, ['scripts/local-checks.mjs',
  'build', 'moon', '--', '--target', 'js', '--release',
  'src/connectors_builtin_node'], {stdio: 'inherit'});
const accepted = target => {
  const expected = expectedCases(target);
  const escape = text => text.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&');
  const result = spawnSync(process.execPath, ['scripts/local-checks.mjs',
    'test', 'node', '--timeout-seconds', '120', '--', '--test-name-pattern',
    `^(?:${expected.map(value => escape(value.name)).join('|')})$`,
    acceptance], {encoding: 'utf8', timeout: 130000, maxBuffer: 16 * 1024 * 1024});
  return mutationAcceptance(result, expected);
};

export function checkDisclosureMutations() {
  const original = readFileSync(path, 'utf8');
  const results = [];
  try {
    for (const [index, [name, from, to]] of mutations.entries()) {
      if (original.split(from).length !== 2) {
        throw new Error(`Mutation anchor not unique: ${name}`);
      }
      writeFileSync(path, original.replace(from, to));
      build();
      results.push({name, rejected: !accepted(targets[index])});
    }
  } finally {
    writeFileSync(path, original);
    build();
  }
  const restored = targets.every(target => accepted(target));
  console.log(JSON.stringify({mutations: results, restoredAccepted: restored}, null, 2));
  if (!restored || results.some(result => !result.rejected)) process.exitCode = 1;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  checkDisclosureMutations();
}
