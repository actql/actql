// Scheduling contract for the split Client gate. These are the existing
// acceptance commands, not a replacement acceptance oracle.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, readFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {runInNewContext} from 'node:vm';
import {parse} from 'yaml';
import {compositionProgram, compositionTemplate, compositionExpectations, compositionText, compositionTextTemplate} from
  './fixtures/composed-infer-effect-input.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const {jobs} = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
const normal = "${{ !inputs.performance_matrix && !inputs.packed_query_evidence_probe && needs.select-targets.outputs.profile == 'full' }}";
const groups = ['client-packages', 'client-distribution', 'client-packed', 'client-salesforce'];
const consumers = ['client-distribution', 'client-packed'];
const runs = name => jobs[name].steps.filter(step => step.run).map(step => step.run.trim());
const run = (script, env) => spawnSync('bash', ['-eo', 'pipefail', '-c', script], {
  cwd: root, env: {...process.env, ...env}, encoding: 'utf8',
});

test('the submitted JSON fixture binds only the newly published MappingRef', () => {
  const original = structuredClone(compositionTemplate);
  const first = compositionProgram('fixture-mapping-first');
  const second = compositionProgram('fixture-mapping-second');
  const update = program => program.stages.find(stage => stage.id === 'apply').effects.save.update;
  assert.equal(update(first).mapping, 'fixture-mapping-first');
  assert.equal(update(second).mapping, 'fixture-mapping-second');
  update(first).mapping = update(second).mapping = '__PUBLICATION_MAPPING_REF__';
  assert.deepEqual(first, original);
  assert.deepEqual(second, original);
  assert.deepEqual(compositionTemplate, original);
  assert.throws(() => compositionProgram(''));
});

test('the authored text fixture binds only its published MappingRef', () => {
  for (const mapping of ['fixture-mapping-first', 'fixture-mapping-second']) {
    const text = compositionText(mapping);
    assert.equal(text.replace(mapping, '__PUBLICATION_MAPPING_REF__'), compositionTextTemplate);
    assert(text.includes('MAX_OUTPUT_ROWS 10'));
    assert(text.includes('|> ASSERT UNIQUE BY (id)'));
    assert(text.includes('|> EFFECT save UPDATE'));
    assert.equal(text.match(/WHERE id = id/gu).length, 2);
  }
  for (const mapping of ['', 'bad`reference', 'bad\nreference']) {
    assert.throws(() => compositionText(mapping));
  }
});

test('ordinary packed composition ships JSON and authored text with independent replay expectations', () => {
  const script = readFileSync(new URL('./test-packed-salesforce-source.mjs', import.meta.url), 'utf8');
  const selection = flags => JSON.parse(runInNewContext(script.slice(
    script.indexOf('const twoSourceEffect = process.argv'),
    script.indexOf('const inferEnabled =')) + '\nJSON.stringify(compositionCases)',
  {process: {argv: ['node', 'harness', ...flags]}}));
  assert.deepEqual(selection([]), ['source', 'infer', 'infer-text', 'read-approval']);
  assert.deepEqual(selection(['--two-source-effect']), ['two-source']);
  assert.deepEqual(selection(['--composed-infer']), ['infer', 'infer-text']);
  assert.deepEqual(selection(['--composed-text']), ['infer-text']);
  assert.deepEqual(selection(['--two-source-read-approval']), ['read-approval']);
  for (const name of ['composed-infer-effect.program.template.json',
    'composed-infer-effect.expected.json', 'composed-infer-effect.aql.template']) {
    assert(script.includes("'" + name + "'"), 'isolated consumer must receive ' + name);
  }
  assert.deepEqual(compositionExpectations.sourceReadSessions, [2, 0, 0, 0]);
  assert.deepEqual(compositionExpectations.modelInputs, [100, 200]);
  assert.deepEqual(compositionExpectations.effectWriteCounts, [0, 0, 1, 1]);
  assert.deepEqual(compositionExpectations.restartBoundaries,
    ['capture-waiting', 'approval-committed']);
});

test('packed Source approval keeps independent read and Effect restart counters', () => {
  const expected = JSON.parse(readFileSync(new URL(
    './fixtures/two-source-read-approval.expected.json', import.meta.url), 'utf8'));
  assert.deepEqual(expected.sourceProviderOpenCounts,
    [[1, 0], [1, 0], [1, 1], [1, 1], [1, 1], [1, 1]]);
  assert.deepEqual(expected.sourceReadSessions, [1, 0, 1, 0, 0, 0]);
  assert.deepEqual(expected.effectWriteCounts, [0, 0, 0, 0, 1, 1]);
  assert.deepEqual(expected.restartBoundaries, ['source-waiting',
    'source-approval-committed', 'capture-waiting', 'approval-committed']);
});

test('each Client group retains its acceptance commands exactly once', () => {
  assert.deepEqual(runs('client-distribution'), ['npm run check:distribution-client']);
  assert.deepEqual(runs('client-packed'), [
    'npm run check:packed-embedded-checkpoint',
    'node scripts/test-packed-single-infer.mjs',
    'node scripts/test-packed-acquired-infer.mjs',
    'node --test scripts/packed-query-evidence.test.mjs\nnode scripts/test-packed-public-query.mjs',
    'node scripts/test-packed-result-description.mjs',
    'node scripts/test-packed-salesforce-source.mjs',
  ]);
  assert.deepEqual(runs('client-salesforce'), [
    'node scripts/build-runtime-packages.mjs local-node',
    'npm run check:salesforce-site',
    'node adapters/connectors/salesforce/test/run-computation-probe.mjs',
    'node scripts/test-acquired-effect-computation-probe.mjs',
    `for boundary in before-effect-source effect-source before-effect-capture effect-capture before-publication-private publication-private; do
  node scripts/test-effect-capture-host-crash.mjs "$boundary"
done
for boundary in effect-source effect-capture publication-private; do
  node scripts/test-effect-capture-crash.mjs "$boundary"
done`,
  ]);
  const distribution = jobs['client-distribution'].steps.find(step => step.run === 'npm run check:distribution-client');
  assert.deepEqual(distribution.env, {TMPDIR: '${{ github.workspace }}/_build'});
  for (const name of groups) {
    assert.equal(jobs[name].if, normal);
    assert.equal(jobs[name]['runs-on'], 'ubuntu-24.04');
    assert.equal(jobs[name]['timeout-minutes'], 30);
    assert.equal(jobs[name].strategy, undefined, 'no fail-fast sibling cancellation');
    for (const step of jobs[name].steps.filter(step => step.run)) {
      assert.equal(step.if, undefined, 'all acceptance commands remain unconditional');
      assert.equal(step['continue-on-error'], undefined);
    }
  }
  assert.deepEqual(jobs['client-salesforce'].needs, ['select-targets', 'preflight']);
  const manifest = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
  assert(!manifest.scripts['check:local-node-assets'].includes('test-packed-salesforce-source'),
    'the packed composition acceptance moves from Host into the artifact consumer exactly once');
});

test('one producer uploads only manifest and tarballs; consumers select its immutable artifact ID', () => {
  assert.deepEqual(runs('client-packages'), ['node scripts/packed-client-packages.mjs "$RUNNER_TEMP/actql-client-packages"']);
  const producer = jobs['client-packages'];
  const upload = producer.steps.find(step => step.id === 'packages');
  assert.equal(upload.uses, 'actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02');
  assert.equal(upload.with.name, 'actql-client-packages-${{ github.run_id }}-${{ github.run_attempt }}-${{ github.sha }}');
  assert.equal(upload.with['if-no-files-found'], 'error');
  assert.equal(upload.with['retention-days'], 7);
  assert.deepEqual(upload.with.path.trim().split('\n'), [
    'packed-client-packages.json', ...['client-wire', 'sdk', 'run-host-core', 'local-node', 'node']
      .map(name => `actql-${name}-0.0.0-development.tgz`),
  ].map(name => '${{ runner.temp }}/actql-client-packages/' + name));
  assert.deepEqual(producer.outputs, {'artifact-id': '${{ steps.packages.outputs.artifact-id }}'});
  for (const name of consumers) {
    assert.deepEqual(jobs[name].needs, ['select-targets', 'preflight', 'client-packages']);
    const download = jobs[name].steps.find(step => step.name === 'Download the exact Client package artifact');
    assert.equal(download.uses, './.github/actions/download-client-packages');
    assert.deepEqual(download.with, {
      'artifact-id': '${{ needs.client-packages.outputs.artifact-id }}',
      path: '${{ runner.temp }}/actql-client-packages',
    });
    assert.equal(jobs[name].env, undefined, 'runner context is unavailable in job-level env');
    assert(!jobs[name].steps.some(step => /cache@/.test(step.uses ?? '')));
  }
});

test('packed evidence uploads remain always-on after their original command', () => {
  const steps = jobs['client-packed'].steps;
  for (const [id, name] of [['packed-infer', 'packed-single-infer'],
    ['packed-acquired-infer', 'packed-acquired-infer'],
    ['packed-query', 'packed-public-query'], ['packed-result-description', 'packed-result-description']]) {
    const command = steps.findIndex(step => step.id === id);
    const upload = steps[command + 1];
    assert(command >= 0);
    assert.equal(upload.uses, './.github/actions/upload-packed-query-evidence');
    assert.equal(upload.if, `always() && steps.${id}.outputs.evidence-directory != ''`);
    assert.deepEqual(upload.with, {
      directory: '${{ steps.' + id + '.outputs.evidence-directory }}',
      name: name + '-${{ github.sha }}',
    });
  }
});

test('the original client check succeeds only when every producer and acceptance group succeeds', () => {
  assert.deepEqual(jobs.client.needs, groups);
  assert.match(jobs.client.if, /always\(\)/u);
  assert.match(jobs.client.if, /!\(needs\.client-packages\.result == 'skipped'/u);
  assert(jobs.check.needs.includes('client'));
  const script = jobs.client.steps[0].run;
  const results = Object.fromEntries(groups.map(name => [name, {result: 'success'}]));
  assert.equal(run(script, {RESULTS: JSON.stringify(results)}).status, 0);
  for (const name of groups) {
    for (const result of ['failure', 'cancelled', 'skipped', 'in_progress', undefined]) {
      const candidate = {...results, [name]: {result}};
      const child = run(script, {RESULTS: JSON.stringify(candidate)});
      assert.equal(child.status, 1, `${name}: ${result}\n${child.stdout}\n${child.stderr}`);
    }
  }
  assert.equal(run(script, {RESULTS: '{}'}).status, 1);
});

test('local commands remain available for each independently retryable group', () => {
  for (const name of [...consumers, 'client-salesforce']) {
    const child = spawnSync(process.execPath, ['scripts/local-checks.mjs', 'run', name, '--dry-run'], {cwd: root, encoding: 'utf8'});
    assert.equal(child.status, 0, child.stderr);
    for (const command of runs(name)) assert(child.stdout.includes(command));
  }
});

// Empty artifact-ids would make the upstream action select every artifact.
// This guard also accepts the original producer ID in a consumer-only retry.
test('download fails closed before the action for empty, malformed or multiple IDs', () => {
  const action = parse(readFileSync(new URL('../.github/actions/download-client-packages/action.yml', import.meta.url), 'utf8'));
  assert.equal(action.runs.using, 'composite');
  assert.equal(action.runs.steps.length, 3);
  const [guard, download] = action.runs.steps;
  assert.equal(guard.env.ARTIFACT_ID, '${{ inputs.artifact-id }}');
  assert.equal(guard['continue-on-error'], undefined);
  assert.equal(download.if, undefined, 'download requires the preceding guard to succeed');
  assert.equal(download.uses, 'actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093');
  assert.deepEqual(download.with, {'artifact-ids': '${{ inputs.artifact-id }}', path: '${{ inputs.path }}', 'merge-multiple': true});
  for (const id of ['', ' ', '0', '-1', '01', '1,2', '1\n2', 'undefined', '1.2', '1e3', '${{ missing }}']) {
    assert.equal(run(guard.run, {ARTIFACT_ID: id}).status, 1, JSON.stringify(id));
  }
  for (const attempt of ['1', '2']) {
    assert.equal(run(guard.run, {ARTIFACT_ID: '987654321', GITHUB_RUN_ATTEMPT: attempt}).status, 0);
  }
});

test('runner-private package/cache environment is set only after successful download', t => {
  const action = parse(readFileSync(new URL('../.github/actions/download-client-packages/action.yml', import.meta.url), 'utf8'));
  const step = action.runs.steps[2];
  assert.equal(step.if, undefined);
  assert.equal(step['continue-on-error'], undefined);
  assert.equal(step.env.PACKAGES_PATH, '${{ inputs.path }}');
  const scratch = mkdtempSync(join(tmpdir(), 'client-ci-env-'));
  t.after(() => rmSync(scratch, {recursive: true, force: true}));
  const environment = join(scratch, 'github-env');
  const packages = join(scratch, 'artifact');
  assert.equal(run(step.run, {PACKAGES_PATH: packages, GITHUB_ENV: environment, RUNNER_TEMP: scratch}).status, 0);
  assert.equal(readFileSync(environment, 'utf8'),
    `ACTQL_PACKED_CLIENT_PACKAGES=${packages}\nACTQL_TEST_NPM_CACHE=${scratch}/actql-npm-cache\n`);
  for (const job of Object.values(jobs)) {
    for (const value of Object.values(job.env ?? {})) {
      assert(!/\$\{\{[^}]*\brunner\./u.test(String(value)), 'runner context cannot be resolved before assigning a job runner');
    }
  }
});
