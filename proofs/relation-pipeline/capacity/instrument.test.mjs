import assert from 'node:assert/strict';
import {mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {instrument, mutations, workspaceOverlay} from './instrument.mjs';
import {applyMutation} from '../sites.mjs';
import {tokens} from '../../../scripts/portable-core.mjs';

const packagePath = 'src/execution_relation/moon.pkg';
const targetClause = `targets: {
    "text_workspace_growth_js.mbt": ["js"],
    "text_workspace_growth_nonjs.mbt": ["not", "js"],
  }`;
const optionTail = `link: { "native": { "cc": "cc", "cc-link-flags": "-lm" } }`;
const packageFixture = `supported_targets = "+js+wasm+native"
// options(targets: {}) is commentary, not another compiler directive.
options(
  "native-stub": ["existing_stub.c"],
  ${targetClause},
  ${optionTail},
)
`;

test('capacity package instrumentation merges into the original literal options and keeps other DATA', () => {
  const changed = instrument(packagePath, packageFixture);
  const directives = tokens(changed).filter(token => token.kind === 'word' && token.value === 'options');
  assert.equal(directives.length, 1);
  assert(changed.includes(optionTail));
  assert(changed.includes('"native-stub": ["existing_stub.c","capacity_map_probe_stub.c"]'));
  const injected = '\n    "capacity_map_probe_native.mbt": ["native"],\n    "capacity_map_probe_portable.mbt": ["not","native"],\n  ';
  assert.equal(changed.replace(injected, '').includes(targetClause), true);
  assert.throws(() => instrument(packagePath, changed), /Observer target already present/);
  const production = readFileSync(new URL('../../../' + packagePath, import.meta.url), 'utf8');
  const merged = instrument(packagePath, production);
  for (const file of ['text_workspace_growth_js.mbt', 'text_workspace_growth_nonjs.mbt']) {
    assert.equal(merged.split(JSON.stringify(file)).length, 2);
  }
  assert.equal(tokens(merged).filter(token => token.kind === 'word' && token.value === 'options').length, 1);
});

test('capacity package instrumentation refuses ambiguous malformed and nonliteral injected fields', () => {
  for (const changed of [
    packageFixture + '\noptions(targets: {})\n',
    packageFixture.replace(targetClause, targetClause + ', ' + targetClause),
    packageFixture.replace('["js"]', '[js]'),
    packageFixture.replace('"existing_stub.c"', 'existing_stub'),
    packageFixture.replace('"existing_stub.c"', '"capacity_map_probe_stub.c"'),
    packageFixture.replace('"text_workspace_growth_js.mbt"', '"capacity_map_probe_native.mbt"'),
    packageFixture.replace(optionTail, 'link:'),
    packageFixture.slice(0, packageFixture.lastIndexOf(')')),
  ]) assert.throws(() => instrument(packagePath, changed));
});

test('optional package token ranges preserve the existing token DATA and exact literal spans', () => {
  const ranged = tokens(packageFixture, false, true);
  assert.deepEqual(ranged.map(({begin, end, ...token}) => token), tokens(packageFixture));
  for (const token of ranged) {
    const raw = packageFixture.slice(token.begin, token.end);
    assert.deepEqual(tokens(raw), [{kind: token.kind, value: token.value}]);
  }
});

test('injected package remains discoverable with real split target files in all required Moon targets', {timeout: 45_000}, t => {
  const root = mkdtempSync(join(tmpdir(), 'actql-capacity-options-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  mkdirSync(join(root, 'src'));
  writeFileSync(join(root, 'moon.mod'), 'name = "actql/capacity-options-probe"\nsource = "src"\n');
  const files = {
    'main.mbt': 'pub fn checked() -> Int { dimension() + probe() }\n',
    'text_workspace_growth_js.mbt': 'pub fn dimension() -> Int { 2 }\n',
    'text_workspace_growth_nonjs.mbt': 'pub fn dimension() -> Int { 1 }\n',
    'capacity_map_probe_native.mbt': 'pub fn probe() -> Int { 1 }\n',
    'capacity_map_probe_portable.mbt': 'pub fn probe() -> Int { 2 }\n',
    'existing_stub.c': 'int existing_capacity_stub(void) { return 0; }\n',
    'capacity_map_probe_stub.c': 'int capacity_map_stub(void) { return 0; }\n',
  };
  for (const [path, source] of Object.entries(files)) writeFileSync(join(root, 'src', path), source);
  const check = () => spawnSync('moon', ['check', '--target', 'all', '--deny-warn'], {
    cwd: root, env: process.env, encoding: 'utf8', timeout: 30_000,
  });
  writeFileSync(join(root, 'src/moon.pkg'), packageFixture + '\noptions(targets: {})\n');
  const duplicate = check();
  assert.ifError(duplicate.error);assert.equal(duplicate.signal, null);
  assert.notEqual(duplicate.status, 0);
  assert.match((duplicate.stderr ?? '') + (duplicate.stdout ?? ''), /Duplicate key.*options/su);
  writeFileSync(join(root, 'src/moon.pkg'), instrument(packagePath, packageFixture));
  const checked = check();
  assert.ifError(checked.error);assert.equal(checked.signal, null);
  assert.equal(checked.status, 0, (checked.stderr ?? '') + (checked.stdout ?? ''));
});

const path = 'src/execution_relation/producer_read_preparation.mbt';
const original = readFileSync(new URL('../../../' + path, import.meta.url), 'utf8');
const copy = mutations.find(entry => entry.name === 'handoff-copy-without-accounting');
assert.equal(copy.path, path);

test('the handoff copy observer replaces the complete original return without nesting statements in a record', () => {
  const mutated = applyMutation(original, copy);
  const healthy = instrument(path, original);
  const field = 'bound: cursor.bound,';
  assert.equal(healthy.split(field).length, 2);
  const expected = healthy.replace(field, `bound: ${copy.binding},`);
  assert.equal(instrument(path, mutated), expected);
  assert.equal(mutated.replace(copy.after, copy.before), original);
});

test('the handoff observer refuses changed and duplicated complete return anchors', () => {
  const mutated = applyMutation(original, copy);
  assert.throws(() => instrument(path, mutated.replace('schema: cursor.schema,', 'schema: foreign,')),
    /Ambiguous observation site/);
  assert.throws(() => instrument(path, mutated + '\n' + mutated), /Ambiguous observation site/);
});

const rowsPath = 'src/execution_relation/bounded_binding_rows.mbt';
const rows = readFileSync(new URL('../../../' + rowsPath, import.meta.url), 'utf8');
const workspace = '  let workspace = working_row_workspace(generated, max_entries)';
for (const offset of [-1, 0, 1]) {
  test(`workspace boundary ${offset} preserves the original Task growth attachment`, () => {
    const changed = workspaceOverlay(rows, offset);
    const expected = `${workspace}
  let capacity_n = bounded_binding_input_row_count(input)
  let capacity_peak = if capacity_n == 0 { 5 * output_width } else { Int::max(5 * output_width + 2 * capacity_n, 6 * output_width + capacity_n) }
  let workspace = if distinct && !dedupe { { ..workspace, limit: capacity_peak + (${offset}), } } else { workspace }`;
    assert.equal(rows.split(workspace).length, 2);
    assert.equal(changed, rows.replace(workspace, expected));
    assert.equal(changed.replace(expected, workspace), rows);
    assert.equal(changed.split(workspace).length, 2, 'The original growth-aware constructor runs once');
    assert.equal(changed.includes('let workspace = row_workspace('), false,
      'A detached workspace would drop the same Task growth owner');
  });
}
test('workspace boundaries refuse changed, missing and duplicate original constructors', () => {
  for (const changed of [rows.replace(workspace, ''), rows + '\n' + workspace,
    rows.replace(workspace, '  let workspace = working_row_workspace(foreign, max_entries)')]) {
    assert.throws(() => workspaceOverlay(changed, 0), /Ambiguous workspace boundary site/);
  }
});
test('workspace boundaries admit only the exact scientific offsets', () => {
  for (const offset of [-2, 2, 0.5, NaN, undefined, '0', '0) + foreign(']) {
    assert.throws(() => workspaceOverlay(rows, offset), /Unknown workspace boundary offset/);
  }
});
