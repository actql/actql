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
    '      | LexicalViolation(_, _)\n' +
    '      | QueryViolation(_, _)\n' +
    '      | TypeViolation(_, _, _, _)\n      | SuppliedViolation(_)\n' +
    '      | ConstraintViolation(_, _, _)\n' +
    '      | UndeclaredParameter(_, _))\n    }) {\n' +
    '    "invalid"',
    'if findings.iter().any(finding => !(finding is Limit(_))) {\n' +
    '    "invalid"'],
  ['an exhausted construction budget is reported as a failure',
    '        ) => findings.push(Limit("analysis_budget_exhausted"))\n' +
    '        // The Program built from accepted source: never blamed on the author.',
    '        ) => return Failed("check_internal")\n' +
    '        // The Program built from accepted source: never blamed on the author.'],
  ['a supplied-value budget is reported as a violation',
    'Budget => findings.push(Limit("analysis_budget_exhausted"))',
    'Budget => findings.push(Violation("supplied_value_invalid"))'],
  ['a missing value is reported as a violation',
    'Ok(NeedsBindings(missing)) => {\n            findings.push(Limit("bound_values_missing"))',
    'Ok(NeedsBindings(missing)) => {\n            findings.push(Violation("bound_values_missing"))'],
  ['an authored UTF-8 location is shifted by one byte',
    '@encode.number_value(writer, start.to_double())',
    '@encode.number_value(writer, (start + 1).to_double())'],
  ['a nested supplied pointer escapes slash before tilde',
    'name.replace_all(old="~", new="~0").replace_all(old="/", new="~1")',
    'name.replace_all(old="/", new="~1").replace_all(old="~", new="~0")'],
  ['a nested supplied pointer escapes only the first occurrence',
    'name.replace_all(old="~", new="~0").replace_all(old="/", new="~1")',
    'name.replace(old="~", new="~0").replace(old="/", new="~1")'],
  ['a nested expected type is replaced by the root type',
    'guard check_type_name(source) is Some(expected) else',
    'guard check_type_name(root_source) is Some(expected) else'],
  ['a supplied constraint loses its owned location',
    'return ConstraintViolation(name, constraint, pointer)',
    'return ConstraintViolation(name, constraint, None)'],
  ['a supplied numeric constraint is assigned to the duration family',
    'ParameterIssue(NumericConstraint, ..)) =>\n      Some("numeric")',
    'ParameterIssue(NumericConstraint, ..)) =>\n      Some("duration")'],
  ['a supplied constraint loses its typed explanation facts',
    'return ConstraintViolation(name, constraint, pointer)',
    'return SuppliedViolation(pointer)'],
  ['an unresolved column loses its retained authored location',
    '    Some(origin) =>\n      QueryViolation(\n' +
    '        @source_origin.start(origin).byte_offset,\n' +
    '        @source_origin.end(origin).byte_offset,\n      )',
    '    Some(_) => Violation("query_invalid")'],
  ['an unresolved column starts one byte after its authored token',
    '        @source_origin.start(origin).byte_offset,',
    '        @source_origin.start(origin).byte_offset + 1,'],
  ['a lexical escape is assigned to another issue family',
    'InvalidEscape => "invalid_escape"', 'InvalidEscape => "unexpected_end"'],
  ['a lexical violation loses its owned source position',
    'let range = diagnostic.span.map(span => (span.start_byte, span.end_byte))',
    'let range : (Int, Int)? = None'],
  ['a lexical violation loses its typed explanation',
    'LexicalViolation(_, _) => Some("query_lexical_invalid")',
    'LexicalViolation(_, _) => Some("query_syntax_invalid")'],
  ['an expression lowerer budget is reported as invalid input',
    '        ) => findings.push(Limit("analysis_budget_exhausted"))\n' +
    '        // Other failures of generated construction/admission and invalid',
    '        ) => findings.push(Violation("query_invalid"))\n' +
    '        // Other failures of generated construction/admission and invalid'],
  ['an expression lowerer budget is reported as checker failure',
    '        ) => findings.push(Limit("analysis_budget_exhausted"))\n' +
    '        // Other failures of generated construction/admission and invalid',
    '        ) => return Failed("check_internal")\n' +
    '        // Other failures of generated construction/admission and invalid'],
  ['an expression lowerer budget is silently verified',
    '        ) => findings.push(Limit("analysis_budget_exhausted"))\n' +
    '        // Other failures of generated construction/admission and invalid',
    '        ) => ()\n' +
    '        // Other failures of generated construction/admission and invalid'],
  ['an expression lowerer budget hides independent input violations',
    '        ) => findings.push(Limit("analysis_budget_exhausted"))\n' +
    '        // Other failures of generated construction/admission and invalid',
    '        ) => {\n          findings.clear()\n          findings.push(Limit("analysis_budget_exhausted"))\n        }\n' +
    '        // Other failures of generated construction/admission and invalid'],
];

const strict = id => ({id, operator: 'strictEqual'});
const deep = id => ({id, operator: 'deepStrictEqual'});
const targets = [
  ['a disclosable violation is reported beside a protected source', [deep('public-violation')]],
  ['a disclosable violation is reported beside a protected source',
    [strict('protected-outcome'), deep('protected-unresolved')]],
  ['an exhausted analysis budget is undetermined, not invalid or failed',
    [strict('construction-outcome'), deep('construction-budget')]],
  ['parameter budgets are limits, never violations', [deep('binding-budget')]],
  ['supplied type violations and missing values expose different typed facts', [strict('missing-value')]],
  ['authored syntax locations retain exact UTF-8 input revisions',
    [strict('syntax-outcome'), deep('syntax-location')]],
  ['nested supplied type facts follow the submitted contract and path',
    [strict('nested-outcome'), deep('nested-type')]],
  ['nested supplied type facts follow the submitted contract and path',
    [strict('nested-outcome'), deep('nested-type')]],
  ['nested supplied type facts follow the submitted contract and path',
    [strict('nested-outcome'), deep('nested-type')]],
  ['supplied constraint locations retain the binder path without private values',
    [strict('constraint-outcome'), deep('constraint-location')]],
  ['supplied constraint locations retain the binder path without private values',
    [strict('constraint-outcome'), deep('constraint-location')]],
  ['supplied constraint locations retain the binder path without private values',
    [strict('constraint-outcome'), deep('constraint-location')]],
  ['unresolved column expressions retain authored source positions',
    [strict('column-outcome'), strict('column-verdict'), deep('column-location')]],
  ['unresolved column expressions retain authored source positions',
    [strict('column-outcome'), strict('column-verdict'), deep('column-location')]],
  ...Array.from({length: 3}, () =>
    ['typed lexical explanations retain the submitted token position',
      [strict('lexical-outcome'), strict('lexical-verdict'), deep('lexical-reason')]]),
  ['expression construction limits remain undetermined', [strict('expression-budget-verdict')]],
  ['expression construction limits remain undetermined', [strict('expression-budget-outcome')]],
  ['expression construction limits remain undetermined', [strict('expression-budget-verdict')]],
  ['expression construction limits remain undetermined', [strict('expression-budget-mixed')]],
];

// Reuse the common reporter and nonzero-execution evidence. A process failure
// alone never establishes that an intended acceptance assertion detected a fault.
export function mutationAcceptance(result, expected, file = acceptance) {
  const fault = () => { throw new Error('Mutation verification infrastructure failure: ' +
    `${result.error?.code ?? result.signal ?? result.status}\n${result.stdout ?? ''}\n${result.stderr ?? ''}`); };
  if (result.error || result.signal || ![0, 1].includes(result.status)) fault();
  if (!Array.isArray(expected) || expected.length === 0) fault();
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
        typeof entry.errorMessage !== 'string' ||
        !target.assertions.some(({id, operator}) => entry.operator === operator &&
          entry.errorMessage.startsWith(`[check-mutation:${id}]`)))) fault();
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

export function checkDisclosureMutations(match) {
  const selected = mutations.map((mutation, index) => ({mutation, target: targets[index]}))
    .filter(({mutation: [name]}) => match === undefined || name.includes(match));
  if (selected.length === 0) throw new Error('No disclosure mutations selected');
  const original = readFileSync(path, 'utf8');
  const results = [];
  try {
    for (const {mutation: [name, from, to], target} of selected) {
      if (original.split(from).length !== 2) {
        throw new Error(`Mutation anchor not unique: ${name}`);
      }
      writeFileSync(path, original.replace(from, to));
      build();
      results.push({name, rejected: !accepted(target)});
    }
  } finally {
    writeFileSync(path, original);
    build();
  }
  const restored = selected.every(({target}) => accepted(target));
  console.log(JSON.stringify({mutations: results, restoredAccepted: restored}, null, 2));
  if (!restored || results.some(result => !result.rejected)) process.exitCode = 1;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  if (args.length && (args.length !== 2 || args[0] !== '--match' || !args[1])) {
    throw new Error('Usage: check-disclosure-mutations.mjs [--match name-substring]');
  }
  checkDisclosureMutations(args[1]);
}
