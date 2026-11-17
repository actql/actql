import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {runInNewContext} from 'node:vm';
import {parse} from 'yaml';
import {parse as parseJavaScript} from 'acorn';
import {validatePackedPublicQueryArguments} from './packed-public-query-options.mjs';
import {tablePublicTestGroups} from './table-public-acceptance-cases.mjs';
import './packed-public-query-profile.test.mjs';

const workflow = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
const job = workflow.jobs['client-packed'];
const condition = (expression, group, ready = true) => runInNewContext(
  expression.replace(/^\$\{\{\s*|\s*\}\}$/gu, '')
    .replace(/\.([a-z]+(?:-[a-z]+)+)/gu, "['$1']"), {
    matrix: {group}, cancelled: () => false, always: () => true,
    steps: new Proxy({}, {get: () => ({outcome: ready ? 'success' : 'failure',
      outputs: {'evidence-directory': '/owned'}})}),
  }, {timeout: 100});

test('every packed campaign has exactly one matrix owner and one same-run package producer', () => {
  assert.deepEqual(job.strategy.matrix.group, ['connectors', 'infer', 'query-portable-1', 'query-portable-2', 'query-portable-3', 'query-native']);
  assert.equal(job.strategy['fail-fast'], false);
  assert.equal(job['continue-on-error'], undefined);
  assert(job.needs.includes('client-packages'));
  const download = job.steps.filter(step => step.uses === './.github/actions/download-client-packages');
  assert.equal(download.length, 1);
  assert.equal(download[0].with['artifact-id'], '${{ needs.client-packages.outputs.artifact-id }}');
  const campaigns = job.steps.filter(step => step.name?.startsWith('Test '));
  assert.deepEqual(campaigns.map(step => step.name), [
    'Test packed Table Source inventory and cold Saved',
    'Test packed Local runtime assets', 'Test packed Sheets',
    'Test packed HubSpot record approval and original Saved',
    'Test packed kintone record approval and original Saved',
    'Test packed Salesforce mock approval and original Saved',
    'Test packed HubSpot mock approval and original Saved',
    'Test packed HubSpot Whole-input mock approval and original Saved',
    'Test packed three-Source HubSpot mock approval and original Saved',
    'Test packed binary Whole JOIN HubSpot mock approval and original Saved',
    'Test packed kintone mock approval and original Saved',
    'Test packed Embedded Local Checkpoint and Named Result',
    'Test packed single INFER capture and replay',
    'Test packed named INFER evaluation with traces off and unsampled',
    'Test packed acquired INFER capture and replay',
    'Test raw public SQL and Pipe through packed Local and HTTP',
    'Test committed Result descriptions through packed Local and HTTP',
    'Test the complete packed Native Graph campaign',
  ]);
  for (const step of campaigns) {
    assert.equal(job.strategy.matrix.group.filter(group => condition(step.if, group)).length, step.id === 'packed-query' || step.name === 'Retain packed public query evidence' ? 3 : 1, step.name);
    assert.equal(job.strategy.matrix.group.filter(group => condition(step.if, group, false)).length, 0, step.name);
  }
  for (const step of job.steps.filter(step => step.uses === './.github/actions/upload-packed-query-evidence'))
    assert.equal(job.strategy.matrix.group.filter(group => condition(step.if, group)).length, step.id === 'packed-query' || step.name === 'Retain packed public query evidence' ? 3 : 1, step.name);
  const aggregate = workflow.jobs.client;
  assert(aggregate.needs.includes('client-packed'));
  assert(aggregate.steps[0].run.includes('const ok = result === "success";'));
});

test('packed Table Source inventory requires private locked Python and the same-run packages', () => {
  const prepare = job.steps.find(step => step.id === 'table-python');
  const accept = job.steps.find(step => step.id === 'packed-table-source');
  const report = job.steps.find(step => step.id === 'packed-table-source-summary');
  assert.ok(prepare); assert.ok(accept); assert.ok(report);
  assert.equal(job['timeout-minutes'], 45);
  assert.equal(job.steps.find(step => step.uses === './.github/actions/setup-toolchain').with.python, 'true');
  assert.equal(prepare.run, 'python -m venv "$RUNNER_TEMP/table-python"\n' +
    '"$RUNNER_TEMP/table-python/bin/python" -m pip install --require-hashes ' +
    '-r adapters/connectors/local/iceberg/requirements.lock\n');
  assert.deepEqual(accept.env, {ACTQL_TABLE_PYTHON: '${{ runner.temp }}/table-python/bin/python',
    ACTQL_TABLE_CASE_GROUP: 'source-inventory'});
  assert.equal(accept.run, 'test -n "${ACTQL_PACKED_CLIENT_PACKAGES:-}"\n' +
    'test -z "${ACTQL_TABLE_NORMAL_RELEASE:-}"\n' +
    'node --test scripts/packed-table-private-input.test.mjs\n');
  for (const step of [prepare, accept, report]) {
    assert.equal(step['continue-on-error'], undefined);
    assert.equal(step['timeout-minutes'], undefined);
  }
  const evaluate = (step, {group = 'connectors', inputs = 'success', python = 'success',
    accepted = 'success', cancelled = false} = {}) => runInNewContext(
    step.if.replace(/^\$\{\{\s*|\s*\}\}$/gu, '').replace(/\.([a-z]+(?:-[a-z]+)+)/gu, "['$1']"), {
      matrix: {group}, cancelled: () => cancelled, always: () => true, success: () => false,
      steps: {'client-inputs': {outcome: inputs}, 'table-python': {outcome: python},
        'packed-table-source': {outcome: accepted}, unrelated: {outcome: 'failure'}},
    }, {timeout: 100});
  assert.equal(evaluate(prepare), true); assert.equal(evaluate(accept), true);
  for (const group of job.strategy.matrix.group.filter(group => group !== 'connectors')) {
    assert.equal(evaluate(prepare, {group}), false);
    assert.equal(evaluate(accept, {group}), false);
    assert.equal(evaluate(report, {group, accepted: 'failure'}), false);
  }
  for (const inputs of ['failure', 'cancelled', 'skipped', undefined]) {
    assert.equal(evaluate(prepare, {inputs: inputs ?? 'missing'}), false);
    assert.equal(evaluate(accept, {inputs: inputs ?? 'missing'}), false);
  }
  for (const python of ['failure', 'cancelled', 'skipped', 'missing'])
    assert.equal(evaluate(accept, {python}), false);
  assert.equal(evaluate(prepare, {cancelled: true}), false);
  assert.equal(evaluate(accept, {cancelled: true}), false);
  assert.equal(evaluate(report), false);
  assert.equal(evaluate(report, {python: 'failure', accepted: 'skipped'}), true);
  assert.equal(evaluate(report, {accepted: 'failure'}), true);
  assert.deepEqual(Object.keys(report.env), ['CLIENT_ARTIFACT_ID', 'TABLE_PYTHON_OUTCOME', 'TABLE_TEST_OUTCOME']);
  assert.match(report.run, /GITHUB_STEP_SUMMARY/u);
  assert.doesNotMatch(report.run, /(?:upload|\.codex-scratch|catalog\.db|source129\.json|\.key|cat )/u);
  const groups = tablePublicTestGroups(accept.env.ACTQL_TABLE_CASE_GROUP);
  assert.equal(groups.length, 1); assert.equal(groups[0].expected, 1);
  const syntax = parseJavaScript(readFileSync(new URL('../adapters/host-node/table-public-commit.test.mjs',
    import.meta.url), 'utf8'), {ecmaVersion: 'latest', sourceType: 'module'});
  const names = syntax.body.filter(node => node.type === 'ExpressionStatement' &&
    node.expression.type === 'CallExpression' && node.expression.callee.name === 'test')
    .map(node => node.expression.arguments[0].value).filter(name => typeof name === 'string');
  assert.deepEqual(names.filter(name => new RegExp(groups[0].pattern, 'u').test(name)),
    ['Table public129 Source views read real rows and retain SAME Saved after cold first-close']);
});

test('packed CI parts refuse narrowing, duplicate parts and ambient selective campaigns', () => {
  for (const part of ['portable', 'portable-1', 'portable-2', 'portable-3', 'native']) {
    assert.doesNotThrow(() => validatePackedPublicQueryArguments([`--ci-part=${part}`], {}));
    for (const extra of ['--quickstart-only', '--graph-native-only', '--ci-part=portable'])
      assert.throws(() => validatePackedPublicQueryArguments([`--ci-part=${part}`, extra], {}));
    assert.throws(() => validatePackedPublicQueryArguments([`--ci-part=${part}`], {ACTQL_TEST_ABS_ONLY: '1'}));
  }
  assert.throws(() => validatePackedPublicQueryArguments(['--ci-part=missing'], {}));
  const portable = job.steps.find(step => step.id === 'packed-query');
  const native = job.steps.find(step => step.id === 'packed-query-native');
  assert(portable.run.includes('--ci-part=${{ matrix.query-part }}'));
  assert.deepEqual(job.strategy.matrix.include, [1,2,3].map(part =>
    ({group: `query-portable-${part}`, 'query-part': `portable-${part}`})));
  assert(native.run.includes('--ci-part=native'));
  assert.equal(native.env.ACTQL_TEST_NATIVE_QUERY_COMPILER, 'clang-19');
});

test('portable and Native packed parts preserve both original complete campaigns', async () => {
  const source = readFileSync(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  const syntax = parseJavaScript(source, {ecmaVersion: 'latest', sourceType: 'module'});
  const selectionNames = ['unionBudgetOnly', 'ciPart', 'portablePart', 'portableExtras'];
  const selection = syntax.body.filter(node => node.type === 'VariableDeclaration' &&
    node.declarations.length === 1 && selectionNames.includes(node.declarations[0].id.name));
  assert.deepEqual(selection.map(node => node.declarations[0].id.name), selectionNames);
  const campaign = syntax.body.find(node => node.type === 'ExpressionStatement' &&
    node.expression.type === 'AwaitExpression' &&
    node.expression.argument.callee?.name === 'withPackedQueryEvidence');
  assert(campaign);
  const controls = campaign.expression.argument.arguments.at(-1).body.body.filter(node =>
    node.type === 'IfStatement' && source.slice(node.start, node.end)
      .includes('scripts/analytic-offset-profiles.test.mjs'));
  assert.equal(controls.length, 1);
  const controlSource = [...selection, controls[0]].map(node => source.slice(node.start, node.end)).join('\n');
  const expectedControls = ['--test', 'scripts/analytic-offset-profiles.test.mjs',
    'scripts/distinct-join-order-source-input.test.mjs', 'scripts/graph-difference-source-input.test.mjs',
    'scripts/graph-relation-join-source-input.test.mjs', 'scripts/public-query-profiles.test.mjs',
    'scripts/packed-query-transports.test.mjs', 'scripts/graph-argument-check.test.mjs',
    'scripts/graph-argument-origin-literals.test.mjs'];
  for (const [args, selected] of [
    [[], true], [['--ci-part=portable'], true], [['--ci-part=portable-1'], true],
    [['--ci-part=portable-2'], false], [['--ci-part=portable-3'], false],
    [['--ci-part=native'], false], [['--union-budget-only'], false],
  ]) {
    validatePackedPublicQueryArguments(args, {});
    const calls = [];
    runInNewContext(controlSource, {
      process: {argv: ['node', 'driver.mjs', ...args], execPath: '/pinned/node'},
      repository: '/original-source', console: {log() {}},
      run: (command, files, directory) => {
        calls.push({command, files: Array.from(files), directory}); return '';
      },
    }, {timeout: 100});
    assert.deepEqual(calls, selected ? [{command: '/pinned/node', files: expectedControls,
      directory: '/original-source'}] : [], `Portable control ownership: ${JSON.stringify(args)}`);
  }
  const portableStart = source.indexOf("if (ciPart !== 'native' && portableExtras) {\nconsole.log(run('bash'");
  const portableEnd = source.indexOf('\nasync function exerciseNativeGraphSource', portableStart);
  assert(portableStart > 0 && portableEnd > portableStart);
  const portableOnly = source.slice(portableStart, portableEnd);
  assert(portableOnly.includes('quickstart.run'));
  assert(portableOnly.includes("['readme-acceptance.mjs']"));
  assert(portableOnly.includes("'missing-generated-asset.json'"));
  const start = source.indexOf("if (process.argv.includes('--graph-native-only')");
  const end = source.indexOf("if (process.argv.includes('--quickstart-only'))", start);
  assert(start > 0 && end > start);
  for (const [ciPart, args, expected] of [
    ['native', [], ['install', 'prepare', false]], ['portable', [], []],
    [undefined, [], []], [undefined, ['--graph-native-only'], ['install', true]],
  ]) {
    const calls = [];
    await runInNewContext(`(async () => { ${source.slice(start, end)} })()`, {
      process: {argv: args}, ciPart,
      installDuckDB: async () => calls.push('install'),
      console: {log() {}}, root: '/original-install', runtimeEnvironment: {original: 'environment'},
      run: (command, args, directory, environment) => {
        assert.deepEqual(Array.from(args), ['acceptance.mjs', '--prepare-native-graph-fixture']);
        assert.equal(directory, '/original-install'); assert.equal(environment.original, 'environment');
        calls.push('prepare'); return '';
      },
      exerciseNativeGraphSource: async value => calls.push(value),
    });
    assert.deepEqual(calls, expected);
  }
  const tail = source.slice(source.lastIndexOf("if (!portableCi)"), source.lastIndexOf('});'));
  for (const [ciPart, expected] of [['portable', 0], ['native', 1], [undefined, 1]]) {
    let calls = 0;
    await runInNewContext(`(async () => { ${tail} })()`, {ciPart, portableCi: ciPart === 'portable', exerciseNativeGraphSource: async () => calls++});
    assert.equal(calls, expected);
  }
  assert(source.includes("ACTQL_TEST_QUERY_EXPECT_FULL_CORPUS: process.argv.some(flag => flag.endsWith('-only')) ? '0' : '1'"));
});
