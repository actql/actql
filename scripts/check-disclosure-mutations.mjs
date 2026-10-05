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
    '      | ExpressionViolation(_, _)\n' +
    '      | GraphViolation(_, _)\n' +
    '      | TypeViolation(_, _, _, _)\n      | SuppliedViolation(_)\n' +
    '      | DeclarationViolation(_)\n' +
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
    'Ok(NeedsBindings(missing)) => {\n        findings.push(Limit("bound_values_missing"))',
    'Ok(NeedsBindings(missing)) => {\n        findings.push(Violation("bound_values_missing"))'],
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
    'return ExpressionViolation(code, range)',
    'return ExpressionViolation(code, None)'],
  ['an unresolved column starts one byte after its authored token',
    '            @source_origin.start(origin).byte_offset,',
    '            @source_origin.start(origin).byte_offset + 1,'],
  ['a lexical escape is assigned to another issue family',
    'InvalidEscape => "invalid_escape"', 'InvalidEscape => "unexpected_end"'],
  ['a lexical violation loses its owned source position',
    'let range = diagnostic.span.map(span => (span.start_byte, span.end_byte))',
    'let range : (Int, Int)? = None'],
  ['a lexical violation loses its typed explanation',
    'LexicalViolation(_, _) => Some("query_lexical_invalid")',
    'LexicalViolation(_, _) => Some("query_syntax_invalid")'],
  ['an invalid declaration loses its owned location',
    'findings.push(DeclarationViolation(pointer))',
    'findings.push(DeclarationViolation(None))'],
  ['an invalid declaration points at the root instead of its failing member',
    'writer, "parameter_declarations", revision, pointer,',
    'writer, "parameter_declarations", revision, "",'],
  ['a source byte budget is treated as a syntax violation',
    'issue is (Limit(_) | Source(@source_origin.InputLimit))',
    'issue is Limit(_)'],
  ['a source byte budget becomes invalid after declaration exhaustion',
    'Err(QuerySyntax(diagnostic)) =>\n' +
    '              if check_syntax_budget(diagnostic.issue) {',
    'Err(QuerySyntax(diagnostic)) =>\n' +
    '              if diagnostic.issue is Limit(_) {'],
  ['absent declarations skip independently supplied binding',
    '  if supplied_admitted {',
    '  if supplied_admitted && context.parameter_declarations is Some(_) {'],
  ['absent declarations lose the supplied member location',
    'let fallback = SuppliedViolation(pointer)',
    'let fallback = SuppliedViolation(None)'],
  ['absent declarations discard a safe violation beside a protected Source',
    'QueryLowering(UnknownRelation) =>\n' +
    '          findings.push(Unresolved("source_resolution"))',
    'QueryLowering(UnknownRelation) => {\n' +
    '          if context.parameter_declarations is None { findings.clear() }\n' +
    '          findings.push(Unresolved("source_resolution"))\n' +
    '        }'],
  ['original structured keys are replaced by admitted spellings',
    'original.push(@source.Key(name))',
    'original.push(@source.Key(key))'],
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
  ['an expression diagnostic is assigned to another issue family',
    'UnknownReference => Some("unknown_reference")',
    'UnknownReference => Some("invalid_arguments")'],
  ['an expression diagnostic loses its authored range',
    'return ExpressionViolation(code, range)',
    'return ExpressionViolation(code, None)'],
  ['an expression diagnostic fabricates a protected reference violation',
    'QueryLowering(UnknownRelation) =>\n' +
    '          findings.push(Unresolved("source_resolution"))',
    'QueryLowering(UnknownRelation) => {\n' +
    '          findings.push(Unresolved("source_resolution"))\n' +
    '          findings.push(ExpressionViolation("unknown_reference", Some((7, 14))))\n' +
    '        }'],
  ['an expression diagnostic is reported as an analysis limit',
    'return ExpressionViolation(code, range)',
    'return Limit("analysis_budget_exhausted")'],
  ['a Graph components violation is reported as an implementation limit',
    'return GraphViolation("components", "invalid_kind")',
    'return Limit("implementation_limit")'],
  ['a Graph components violation loses its typed facts',
    'return GraphViolation("components", "invalid_kind")',
    'return Violation("program_invalid")'],
  ['a Graph components violation invents an authored SQL range',
    '@encode.string_value(writer, operation)\n          @encode.end_object(writer)',
    '@encode.string_value(writer, operation)\n          @encode.end_object(writer)\n' +
    '          write_check_text_location(writer, documents.source_revision, 0, 1)'],
  ['a Graph components violation exposes a private value as a code',
    'return GraphViolation("components", "invalid_kind")',
    'return Violation("private_kind_value")'],
  ['an unsupported function is reported as an authored violation',
    '        QueryLowering(Expression({ issue: UnsupportedFunction, .. })) =>\n' +
    '          findings.push(Limit("implementation_limit"))',
    '        QueryLowering(Expression({ issue: UnsupportedFunction, .. })) =>\n' +
    '          findings.push(Violation("query_invalid"))'],
  ['an unsupported function is reported as a checker failure',
    '        QueryLowering(Expression({ issue: UnsupportedFunction, .. })) =>\n' +
    '          findings.push(Limit("implementation_limit"))',
    '        QueryLowering(Expression({ issue: UnsupportedFunction, .. })) =>\n' +
    '          return Failed("check_internal")'],
  ['an unsupported function is silently verified',
    '        QueryLowering(Expression({ issue: UnsupportedFunction, .. })) =>\n' +
    '          findings.push(Limit("implementation_limit"))',
    '        QueryLowering(Expression({ issue: UnsupportedFunction, .. })) => ()'],
  ['an unsupported function hides an independent supplied violation',
    '        QueryLowering(Expression({ issue: UnsupportedFunction, .. })) =>\n' +
    '          findings.push(Limit("implementation_limit"))',
    '        QueryLowering(Expression({ issue: UnsupportedFunction, .. })) => {\n' +
    '          findings.clear()\n          findings.push(Limit("implementation_limit"))\n        }'],
  ['an unsupported function limit is fabricated behind protected resolution',
    'QueryLowering(UnknownRelation) =>\n' +
    '          findings.push(Unresolved("source_resolution"))',
    'QueryLowering(UnknownRelation) => {\n' +
    '          findings.push(Unresolved("source_resolution"))\n' +
    '          findings.push(Limit("implementation_limit"))\n        }'],

  ['a non-Boolean predicate is reported as an implementation limit',
    'return ExpressionViolation("expected_boolean", None)',
    'return Limit("implementation_limit")'],
  ['a non-Boolean predicate loses its owned requirement',
    'return ExpressionViolation("expected_boolean", None)',
    'return Violation("program_invalid")'],
  ['a non-Boolean predicate invents an original SQL range',
    'return ExpressionViolation("expected_boolean", None)',
    'return ExpressionViolation("expected_boolean", Some((0, 1)))'],
  ['a non-Boolean predicate is fabricated behind protected resolution',
    'QueryLowering(UnknownRelation) =>\n' +
    '          findings.push(Unresolved("source_resolution"))',
    'QueryLowering(UnknownRelation) => {\n' +
    '          findings.push(Unresolved("source_resolution"))\n' +
    '          findings.push(ExpressionViolation("expected_boolean", None))\n        }'],
  ['a non-Boolean predicate exposes a private value as its code',
    'return ExpressionViolation("expected_boolean", None)',
    'return Violation("private_predicate_value")'],
  ['a Subgraph selector violation is reported as an implementation limit',
    'return GraphViolation("subgraph", "invalid_node_selector")',
    'return Limit("implementation_limit")'],
  ['a Subgraph selector violation loses its typed facts',
    'return GraphViolation("subgraph", "invalid_node_selector")',
    'return Violation("program_invalid")'],
  ['a Subgraph selector violation invents an authored SQL range',
    '@encode.string_value(writer, operation)\n          @encode.end_object(writer)',
    '@encode.string_value(writer, operation)\n          @encode.end_object(writer)\n' +
    '          if operation == "subgraph" {\n' +
    '            write_check_text_location(writer, documents.source_revision, 0, 1)\n' +
    '          }'],
  ['a Subgraph selector violation exposes a private value as its code',
    'return GraphViolation("subgraph", "invalid_node_selector")',
    'return Violation("private_selector_value")'],
  ['an unsupported Subgraph selector is reported as invalid input',
    'UnsupportedImplementation =>\n          findings.push(Limit("implementation_limit"))',
    'UnsupportedImplementation =>\n          findings.push(Violation("program_invalid"))'],
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
  ['invalid declarations retain only their owned submitted locations',
    [strict('declaration-outcome'), deep('declaration-location')]],
  ['invalid declarations retain only their owned submitted locations',
    [strict('declaration-outcome'), deep('declaration-location')]],
  ...Array.from({length: 2}, () =>
    ['source byte exhaustion is a limit of the original bound check',
      [strict('source-byte-outcome'), strict('source-byte-verdict'),
        deep('source-byte-reasons'), deep('source-byte-coverage')]]),
  ['absent declarations still bind independently supplied input',
    [strict('absent-binding-verdict')]],
  ['absent declarations still bind independently supplied input',
    [deep('absent-binding-location')]],
  ['absent declarations still bind independently supplied input',
    [strict('absent-binding-verdict')]],
  ['structured locations keep original key spellings after admission',
    [deep('original-key-location')]],
  ['expression construction limits remain undetermined', [strict('expression-budget-verdict')]],
  ['expression construction limits remain undetermined', [strict('expression-budget-outcome')]],
  ['expression construction limits remain undetermined', [strict('expression-budget-verdict')]],
  ['expression construction limits remain undetermined', [strict('expression-budget-mixed')]],
  ['typed expression explanations retain original source ranges',
    [strict('expression-outcome'), strict('expression-verdict'), deep('expression-reason')]],
  ['typed expression explanations retain original source ranges',
    [strict('expression-outcome'), strict('expression-verdict'), deep('expression-reason')]],
  ['typed expression explanations retain original source ranges', [deep('expression-protected')]],
  ['typed expression explanations retain original source ranges', [strict('expression-verdict')]],
  ...Array.from({length: 4}, () =>
    ['Graph components expose typed argument violations',
      [strict('graph-argument-verdict'), deep('graph-argument-reason')]]),
  ['unsupported function lowering remains an implementation limit', [strict('function-limit-verdict')]],
  ['unsupported function lowering remains an implementation limit', [strict('function-limit-outcome')]],
  ['unsupported function lowering remains an implementation limit', [strict('function-limit-verdict')]],
  ['unsupported function lowering remains an implementation limit', [strict('function-limit-mixed')]],
  ['unsupported function lowering remains an implementation limit', [deep('function-limit-protected')]],
  ["non-Boolean predicates retain the common checker's requirement", [strict('predicate-verdict')]],
  ["non-Boolean predicates retain the common checker's requirement", [deep('predicate-reason')]],
  ["non-Boolean predicates retain the common checker's requirement", [deep('predicate-reason')]],
  ["non-Boolean predicates retain the common checker's requirement", [deep('predicate-disclosure')]],
  ["non-Boolean predicates retain the common checker's requirement", [deep('predicate-reason')]],
  ...Array.from({length: 5}, () =>
    ['Subgraph selector violations preserve the common Owner reason',
      [strict('subgraph-verdict'), deep('subgraph-reason'), strict('subgraph-limit-verdict')]]),
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
