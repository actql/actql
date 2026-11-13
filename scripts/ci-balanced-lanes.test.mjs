import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {runInNewContext} from 'node:vm';
import {parse} from 'yaml';
import {validatePackedPublicQueryArguments} from './packed-public-query-options.mjs';

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
  assert(source.includes("if (ciPart !== 'native' && portableExtras) console.log(run(process.execPath, ['--test'"),
    'Portable controls must not be executed again by the Native part');
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

test('Native fixture preparation uses original database/profile construction before returning without a Host', async () => {
  const source = readFileSync(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const start = source.indexOf('const canonical = value =>');
  const end = source.indexOf('// Observe actual native execution, never a diagnostic notification.', start);
  assert(start > 0 && end > start);
  assert(source.includes("if (prepareNativeGraph && profileName !== 'standard') continue;"));
  assert(source.includes("assert.equal(prepareNativeGraph, false, 'Standard Native Graph fixture was not prepared')"));
  const calls = [], writes = [];
  const environment = {source_views: [{contract_cid: 'original-view', output: {schema: {cid: 'original-schema'}}}],
    connector_capabilities: [{}], evidence_bundle_cid: 'old'};
  const connection = {run: async (...args) => calls.push(args), closeSync: () => calls.push('connection-close')};
  const body = source.slice(start, end).replaceAll('import.meta.url', 'fixtureUrl');
  await runInNewContext(`(async () => { ${body} throw new Error('Native preparation did not return'); })()`, {
    assert, createHash, prepareNativeGraph: true, scopeOnly: true, profileName: 'standard', transport: undefined,
    analyticCapacity: {max_original: 41}, sourceRows: [{id: 1, amount: 2}], worker: undefined,
    fixtureUrl: new URL('./fixtures/packed-public-query.mjs', import.meta.url).href, URL,
    readFile: async path => JSON.stringify(path === 'source-environment.json' ? environment :
      path === 'base-environment.json' ? {host_policy_profile: {capacity: {max_base: 7}}} : assert.fail(path)),
    sourceFixturePaths: () => ({database: '/original/records.duckdb', sourceProfilePath: '/original/source-profile.json'}),
    createRequire: () => name => {
      assert.equal(name, '@duckdb/node-api');
      return {DuckDBInstance: {create: async path => {
        assert.equal(path, '/original/records.duckdb');
        return {connect: async () => connection, closeSync: () => calls.push('instance-close')};
      }}};
    },
    writeFile: async (path, wire) => {
      assert.deepEqual(calls.slice(-2), ['connection-close', 'instance-close']);
      writes.push({path, profile: JSON.parse(wire)});
    },
    console: {log() {}},
  });
  assert.equal(writes.length, 1);
  assert.equal(writes[0].path, '/original/source-profile.json');
  const profile = writes[0].profile;
  assert.equal(profile.database, '/original/records.duckdb');
  assert.equal(profile.sourceRef, 'connector://crm/main/r#v');
  assert.equal(profile.queryAliases[0].sourceViewContractCid, 'original-view');
  assert.deepEqual(JSON.parse(profile.checkEnvironmentWire).host_policy_profile.capacity,
    {max_base: 7, max_original: 41});
  assert.equal(JSON.parse(profile.accountConfigurationWire).account_id, 'packed-query');
  assert.deepEqual(calls[0], ['CREATE TABLE records(id DOUBLE, amount DOUBLE)']);
  assert.deepEqual(Array.from(calls[1][1]), [1, 2]);
});
