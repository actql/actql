import assert from 'node:assert/strict';
import {mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {connectorSourceCheckPlan, parseConnectorCheckArguments} from './check-connector.mjs';
import {assertInterfaceCoverage, javascriptInterface} from './interface-inventory.mjs';

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'actql-connector-check-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const files = {
    'src/connectors/example/host-bundle.json': '{"installation":{}}',
    'src/connectors/other/host-bundle.json': 'unselected malformed declaration',
    '.github/workflows/ci.yml': 'jobs:\n  lint:\n    timeout-minutes: 20\n',
    'adapters/connectors/example/test/page.test.mjs': 'import "node:test";\n',
    'src/connectors/example/catalog/page_wbtest.mbt': 'test "page" {}\n',
  };
  for (const [path, text] of Object.entries(files)) {
    mkdirSync(join(root, path, '..'), {recursive: true});
    writeFileSync(join(root, path), text);
  }
  return root;
}

test('author selection checks complete normal generation without selecting or writing a partial assembly', t => {
  const root = fixture(t), file = 'adapters/connectors/example/test/page.test.mjs';
  const plan = connectorSourceCheckPlan(root, {name: 'example', tests: [file]});
  assert.deepEqual(plan.steps[0].args, ['scripts/connector-node-bundles.mjs']);
  assert.equal(plan.steps[0].command, process.execPath);
  assert.deepEqual(plan.selection.declaredRoles, ['host']);
  assert.deepEqual(plan.selection.tests, [{kind: 'node', path: file}]);
  assert.match(plan.selection.qualification, /no installed or provider acceptance/u);
  assert.equal(plan.timeoutSeconds, 1200);
  assert.equal(plan.heavy, false);
  assert.equal(readFileSync(join(root, 'src/connectors/other/host-bundle.json'), 'utf8'),
    'unselected malformed declaration');
});

test('Node and Moon files share the existing nonzero guard and one whole-sequence budget', t => {
  const root = fixture(t), node = 'adapters/connectors/example/test/page.test.mjs';
  const moon = 'src/connectors/example/catalog/page_wbtest.mbt';
  const options = parseConnectorCheckArguments(['example', '--stage', 'source',
    '--test', node, '--test', moon, '--timeout-seconds', '90']);
  const plan = connectorSourceCheckPlan(root, options);
  assert.equal(plan.timeoutSeconds, 90);
  assert.equal(plan.steps.length, 3);
  assert.deepEqual(plan.steps[1].args.slice(3), ['node', node]);
  assert.deepEqual(plan.steps[2].args.slice(3), ['moon', '--target', 'js', moon]);
  for (const step of plan.steps.slice(1)) assert.match(step.args[2], /runFocusedTests/u);
  assert.deepEqual(parseConnectorCheckArguments(['--help']), {help: true});
});

test('missing connectors, duplicate aliases and non-test paths refuse before execution', t => {
  const root = fixture(t), file = 'adapters/connectors/example/test/page.test.mjs';
  for (const name of ['missing', '../example', undefined]) {
    assert.throws(() => connectorSourceCheckPlan(root, {name, tests: [file]}), /Connector/u);
  }
  for (const tests of [[], [file, './' + file], ['../outside.test.mjs'],
    [join(root, file)], ['src/connectors/example/host-bundle.json'], ['missing.test.mjs']]) {
    assert.throws(() => connectorSourceCheckPlan(root, {name: 'example', tests}), /test file/u);
  }
  assert.throws(() => connectorSourceCheckPlan(root, {name: 'example', tests: [file],
    timeoutSeconds: '0'}), /positive/u);
});

test('unsupported stages and flags cannot silently turn installed acceptance into source checks', () => {
  for (const args of [[], ['example', '--stage', 'installed', '--test', 'x.test.mjs'],
    ['example', '--stage', 'source'], ['example', '--stage', 'source', '--test'],
    ['example', '--stage', 'source', '--test', '--write'],
    ['example', '--stage', 'source', '--stage', 'source', '--test', 'x.test.mjs'],
    ['example', '--stage', 'source', '--write', 'true', '--test', 'x.test.mjs'],
    ['example', '--stage', 'source', '--test', 'x.test.mjs', '--test', 'x.test.mjs']]) {
    assert.throws(() => parseConnectorCheckArguments(args));
  }
});

test('the author command has exact syntax coverage and existing ten-attribute Owner references', () => {
  const root = fileURLToPath(new URL('../', import.meta.url)), module = 'scripts/check-connector.mjs';
  const body = readFileSync(join(root, module), 'utf8');
  const syntax = {module, sha256: createHash('sha256').update(body).digest('hex'),
    ...javascriptInterface(body)};
  const {declarations} = JSON.parse(readFileSync(join(root,
    'scripts/interface-owners/connector-generation/interface-boundaries.json'), 'utf8'));
  assert.equal(assertInterfaceCoverage({root, modules: [syntax], declarations}), 1);
  assert.deepEqual(syntax.compilerFields, []);
});
