// A deliberately small reviewed test family, not a generic dependency engine.
// Package tests compile every whitebox fixture, but execute only the listed
// files. A test-only edit cannot change the fixture implementations below.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {runFocusedTests} from './test-execution.mjs';

export const focusedFamily = 'query-fixed-requests';
export const focusedPackage = 'src/query_integration';
export const focusedPattern = /^src\/query_integration\/fixed_(?:compute|join)_[a-z0-9_]+_wbtest\.mbt$/u;
export const stableFocusedFiles = Object.freeze([
  'src/query_integration/fixed_compute_candidates_wbtest.mbt',
  'src/query_integration/fixed_join_request_wbtest.mbt',
]);
// Reviewed at b18632b6: source-only checked requests, mock acquisition,
// Local execution and DuckDB SQL preparation, without a database connection.
// Explicit fixture contract: changes require a review, never silently inherit
// eligibility from the filename. These pins are source classification, NOT
// cached test/proof results. Unknown fixture revisions fall back to full.
export const focusedFixtureObjects = Object.freeze({
  'src/query_integration/duckdb_compute_attempt_wbtest.mbt': '79903f4dc9e38d9ef0ac69e338860087cf44f354',
  'src/query_integration/duckdb_fixed_import_wbtest.mbt': 'e396c6f46e00da6ccdf4e3dbe5ea99c0549650ba',
  'src/query_integration/duckdb_native_query_wbtest.mbt': 'b32cbe013055b19be26c3db899181a95c0ea487e',
  'src/query_integration/engine_fixtures_wbtest.mbt': 'bd46554cf744ceefac430def17b0838852962721',
  'src/query_integration/managed_zero_input_request_wbtest.mbt': 'd34b2433e06929baa87f38d47c195b0432ab198b',
  'src/query_integration/moon.pkg': '2e6b65c232ada7395f4751dd1168c0f2ede3711f',
  'src/query_integration/pinned_engine_contracts_wbtest.mbt': '8523d648b3093ca4c715350c74f94546168eca39',
  'src/query_integration/query_capture_wbtest.mbt': '4075ab85106806651f9f625575506310d1ce0586',
  'src/query_integration/query_catalog_fixture_wbtest.mbt': 'cbbc97ea6f6bbb4ae75b98a2ac16f153b9fb0655',
  'src/query_integration/query_evidence_bodies_wbtest.mbt': '9a8a77418e581935bbbaccfa52e8959ab0788025',
  'src/query_integration/query_guards_wbtest.mbt': '6043c24abc394d9eccd159415a1c736f942fcb3d',
  'src/query_integration/query_issuer_wbtest.mbt': '06f7dad70324dd01879c13f9ff234ec56eb0fec5',
  'src/query_integration/query_material_wbtest.mbt': '0a4012b33c5367f73026cbf287eb16e73de3cfd5',
  'src/query_integration/query_program_catalog_wbtest.mbt': '651d6c5020e701eb2a8917a1f3d121920fd273c1',
  'src/query_integration/query_program_wbtest.mbt': '97e1554dcffce1a57b831ff429684361f2e70377',
  'src/query_integration/query_retention_wbtest.mbt': '928c05e1908af98b98adcdc684f6b127aa712220',
  'src/query_integration/query_sequence_wbtest.mbt': 'f8e7e2779818da423351d2cc57bdbf6b7aff7168',
  'src/query_integration/query_strategy_wbtest.mbt': 'd39877a0082a262cd989e86e81d938feb0fab731',
});
const allowedAliases = new Set(['connector', 'cost', 'duckdb', 'duckdb_compute',
  'execution', 'local_connector', 'numeric', 'pipeline', 'lower', 'mock', 'query']);
const allowedHelpers = new Set(['compute_test_limits', 'compute_test_sequence',
  'duckdb_captured_input', 'fixed_compute_attempt_limits', 'input_cursor',
  'native_compile_limits', 'prepared_sequence', 'query_capture_limits',
  'query_generated', 'query_issuer_attempt', 'query_issuer_fixture',
  'query_issuer_run', 'query_material_limits', 'registered_relation_contracts',
  'run_limits', 'strategy_for', 'typed_receiver', 'zero_input_request_owner']);
const builtins = new Set(['abort', 'assert_eq', 'assert_false', 'assert_true',
  'fail', 'physical_equal', 'for', 'if', 'let', 'match', 'while']);
const constructors = new Set(['Cost', 'Err', 'EstimatedFastest', 'Execution',
  'ForeignRequest', 'Guard', 'Import', 'Measurement', 'Number', 'Ok', 'Physical',
  'Proposed', 'Receiving', 'Request', 'Some', 'Step', 'Validation', 'ValueBytes']);
const zero = '0'.repeat(40);
const object = /^[0-9a-f]{40}$/u;
const gitDefault = args => execFileSync('git', args, {encoding: 'utf8', maxBuffer: 32 * 1024 * 1024});
const fields = (value, names) => value && Object.keys(value).sort().join(',') === [...names].sort().join(',');
function identity(value, absent = false) {
  return fields(value, ['mode', 'object']) && (absent
    ? value.mode === '000000' && value.object === zero
    : value.mode === '100644' && object.test(value.object) && value.object !== zero);
}
export function eligibleFocusedChanges(paths, changes) {
  return Array.isArray(paths) && paths.length > 0 && new Set(paths).size === paths.length
    && paths.every(path => typeof path === 'string' && focusedPattern.test(path))
    && Array.isArray(changes) && changes.length === paths.length
    && changes.every((change, index) => fields(change, ['path', 'before', 'after'])
      && change.path === paths[index] && identity(change.after)
      && (identity(change.before) || identity(change.before, true))
      && change.before.object !== change.after.object);
}
export function focusedPlan(paths) {
  return {family: focusedFamily, package: focusedPackage,
    files: [...new Set([...paths, ...stableFocusedFiles])].sort()};
}
export function validateFocusedTests(paths, changes, plan) {
  assert(eligibleFocusedChanges(paths, changes), 'Invalid focused test change inventory');
  assert.deepEqual(plan, focusedPlan(paths), 'Incomplete or unknown focused family');
  return plan;
}

// Only the simple test syntax used by this family is admitted. Strip ordinary
// strings/comments before inspecting code, so words like "native" and SQL/CID
// literals are not mistaken for backend execution. Interpolation and unfamiliar
// syntax fall back; this is not a replacement MoonBit parser or compiler.
export function focusedCode(source) {
  assert.equal(typeof source, 'string');
  let code = '';
  for (let i = 0; i < source.length;) {
    if (source.startsWith('//', i)) {
      const end = source.indexOf('\n', i);
      const next = end < 0 ? source.length : end;
      code += ' '.repeat(next - i); i = next;
    } else if (source[i] === '"') {
      const start = i;
      i++;
      let closed = false;
      while (i < source.length) {
        if (source[i] === '"') { i++; closed = true; break; }
        if (source[i] === '\\') {
          assert(source[i + 1] !== '{', 'Unreviewed interpolated expression');
          assert(i + 1 < source.length, 'Unterminated string escape');
          i += 2;
        } else { assert(source[i] !== '\n', 'Unreviewed multiline string'); i++; }
      }
      assert(closed, 'Unterminated string');
      code += '""' + ' '.repeat(i - start - 2);
    } else {
      assert(!source.startsWith('/*', i) && source[i] !== "'", 'Unreviewed literal or comment syntax');
      code += source[i++];
    }
  }
  return code;
}
export function focusedTestNames(source) {
  const code = focusedCode(source), names = [];
  for (const match of code.matchAll(/\btest\s+""/gu)) {
    const start = code.indexOf('"', match.index);
    let end = start + 1;
    while (source[end] !== '"') end += source[end] === '\\' ? 2 : 1;
    names.push(JSON.parse(source.slice(start, end + 1)));
  }
  assert.equal(new Set(names).size, names.length, 'Duplicate test names');
  return names;
}
export function checkFocusedSource(source, packageSymbols = []) {
  const code = focusedCode(source);
  assert(!/[^\x00-\x7f]/u.test(code), 'Unreviewed identifier syntax');
  assert(!/#|::|\b(?:extern|unsafe|fn|struct|enum|trait|impl|pub|priv|type|let\s+rec)\b/u.test(code),
    'Unreviewed declaration, target annotation or FFI');
  for (const [, alias] of code.matchAll(/@(\w+)/gu))
    assert(allowedAliases.has(alias), `Unreviewed imported boundary: @${alias}`);
  for (const [, name] of code.matchAll(/(?<![.\w@])([a-z_]\w*)\s*\(/gu))
    assert(allowedHelpers.has(name) || builtins.has(name), `Unreviewed callable: ${name}`);
  for (const [, name] of code.matchAll(/(?<![.\w@])([A-Z]\w*)\s*\(/gu))
    assert(constructors.has(name), `Unreviewed constructor: ${name}`);
  // Catch uncalled function references, including passing a native fixture as
  // a callback. The census is restricted to this one owning package.
  const names = new Set(code.match(/\b[A-Za-z_]\w*\b/gu) ?? []);
  for (const name of packageSymbols)
    assert(!names.has(name) || allowedHelpers.has(name) || name === 'FixedComputeTestTransport', `Unreviewed package symbol: ${name}`);
  let rest = code.trim(), tests = 0;
  while (rest) {
    const start = /^test\s+""\s*\{/u.exec(rest);
    assert(start, 'Only named test blocks are eligible');
    let depth = 1, i = start[0].length;
    for (; i < rest.length && depth > 0; i++) {
      if (rest[i] === '{') depth++;
      if (rest[i] === '}') depth--;
    }
    assert.equal(depth, 0, 'Unbalanced test block');
    tests++;
    rest = rest.slice(i).trim();
  }
  assert(tests > 0, 'No executable test declarations');
  return tests;
}

function packageContract(git) {
  const raw = git(['ls-tree', '-rz', 'HEAD', '--', focusedPackage]);
  assert(raw.endsWith('\0'), 'Missing or truncated package tree');
  const files = new Map();
  for (const entry of raw.slice(0, -1).split('\0')) {
    const match = /^(\d{6}) blob ([0-9a-f]{40})\t(.+)$/u.exec(entry);
    assert(match, 'Unsupported package tree entry');
    files.set(match[3], {mode: match[1], object: match[2]});
  }
  for (const [path, expected] of Object.entries(focusedFixtureObjects))
    assert.deepEqual(files.get(path), {mode: '100644', object: expected}, `Unreviewed fixture/package contract: ${path}`);
  const symbols = new Set();
  for (const [path, entry] of files) {
    if (!path.endsWith('.mbt')) continue;
    assert.equal(entry.mode, '100644', 'Nonregular package source');
    const source = git(['show', entry.object]);
    // Definitions only. Unsupported symbol declarations in a changed file are
    // rejected separately; unchanged files remain ordinary compiler inputs.
    for (const [, name] of source.matchAll(/^\s*(?:(?:pub|priv)\s+)?(?:fn|struct|enum|type|trait)\s+([A-Za-z_]\w*)/gmu))
      symbols.add(name);
    for (const [, name] of source.matchAll(/^(?:(?:pub|priv)\s+)?(?:let|const)\s+([A-Za-z_]\w*)/gmu))
      symbols.add(name);
  }
  return {files, symbols: [...symbols]};
}
export function readFocusedTests(paths, changes, git = gitDefault) {
  if (!eligibleFocusedChanges(paths, changes)) return null;
  try {
    const {files, symbols} = packageContract(git);
    for (const change of changes) {
      assert.deepEqual(files.get(change.path), change.after, 'Changed test identity differs from tested tree');
      if (!identity(change.before, true)) {
        const before = git(['show', change.before.object]), after = git(['show', change.after.object]);
        checkFocusedSource(before, symbols);
        const names = new Set(focusedTestNames(after));
        assert(focusedTestNames(before).every(name => names.has(name)), 'Removed or renamed test needs full coverage review');
      }
    }
    const plan = focusedPlan(paths);
    for (const path of plan.files) {
      const entry = files.get(path);
      assert(entry && entry.mode === '100644', 'Missing stable owning-family test');
      const source = git(['show', entry.object]);
      checkFocusedSource(source, symbols);
      focusedTestNames(source);
    }
    return plan;
  } catch { return null; }
}
export function runFocusedPlan(plan, {cwd = process.cwd(), run = runFocusedTests, check = execFileSync} = {}) {
  // File-level selections each retain the nonzero guard. One passing file must
  // never hide a new/changed file with zero discovered or skipped-only tests.
  assert.equal(plan.family, focusedFamily);
  assert.equal(plan.package, focusedPackage);
  assert(Array.isArray(plan.files) && plan.files.length > 0
    && plan.files.every(path => focusedPattern.test(path)));
  // Moon checks/builds the owning package and its imported compiled fixtures.
  // There is no Node runtime package or packed fixture used by this family.
  check('moon', ['check', '--target', 'js', '--deny-warn', focusedPackage], {cwd, stdio: 'inherit'});
  for (const path of plan.files) {
    const status = run('moon', ['--target', 'js', '--deny-warn', path], {cwd});
    assert.equal(status, 0, `Focused test did not pass: ${path}`);
  }
}
if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const plan = JSON.parse(process.env.CI_PLAN ?? 'null');
  assert.equal(plan?.sourceRevision, gitDefault(['rev-parse', 'HEAD']).trim(), 'Focused plan belongs to another checkout');
  const selection = plan?.selection;
  assert(['focused-tests', 'draft-focused'].includes(selection?.profile), 'Invalid focused execution profile');
  validateFocusedTests(selection.paths, selection.focusedChanges, selection.focusedTests);
  assert.deepEqual(readFocusedTests(selection.paths, selection.focusedChanges), selection.focusedTests,
    'Focused inputs or fixture contract changed');
  runFocusedPlan(selection.focusedTests);
}
