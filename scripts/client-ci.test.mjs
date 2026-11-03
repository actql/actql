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
import {types as nodeTypes} from 'node:util';
import './two-source-optional-effect.test.mjs';
import './composition-release-input.test.mjs';
import './table-ctas-result-controls.test.mjs';
import {parse} from 'yaml';
import {parse as parseJavaScript} from 'acorn';
import {optionalEffectCases} from './fixtures/two-source-optional-effect.mjs';
import {compositionProgram, compositionTemplate, compositionExpectations, compositionText, compositionTextTemplate} from
  './fixtures/composed-infer-effect-input.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const {jobs} = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
const normal = "${{ github.event.repository.visibility == 'public' && toJSON(github.event.repository.private) == 'false' && !inputs.performance_matrix && !inputs.packed_query_evidence_probe && needs.select-targets.outputs.profile == 'full' }}";
const groups = ['client-packages', 'client-distribution', 'client-packed', 'client-salesforce'];
const consumers = ['client-distribution', 'client-packed'];
const runs = name => jobs[name].steps.filter(step => step.run).map(step => step.run.trim());
const run = (script, env) => spawnSync('bash', ['-eo', 'pipefail', '-c', script], {
  cwd: root, env: {...process.env, ...env}, encoding: 'utf8',
});

// Evaluate the existing CLI selection prelude, including its admission flags.
// The expected cases below remain independently authored, never read from output.
function fixtureSelection(script, flags, expression) {
  const start = script.indexOf('const admissionHttpsOnly = process.argv');
  const end = script.indexOf('const inferEnabled =');
  assert.ok(start >= 0 && end > start, 'complete registered CLI selection prelude');
  return JSON.parse(runInNewContext(script.slice(start, end) +
    '\nJSON.stringify(' + expression + ')',
  {process: {argv: ['node', 'harness', ...flags]}, optionalEffectCases}));
}

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
  const selection = flags => fixtureSelection(script, flags, 'compositionCases');
  assert.deepEqual(selection([]), ['source', 'infer', 'infer-model-approval', 'infer-text', 'infer-graph-node', 'infer-graph-edge', 'read-approval']);
  assert.deepEqual(selection(['--two-source-effect']), ['two-source']);
  assert.deepEqual(selection(['--composed-infer']), ['infer', 'infer-text']);
  assert.deepEqual(selection(['--model-approval-only']), ['infer-model-approval']);
  assert.deepEqual(selection(['--composed-text']), ['infer-text']);
  assert.deepEqual(selection(['--composed-graph-node']), ['infer-graph-node']);
  assert.deepEqual(selection(['--composed-graph-edge']), ['infer-graph-edge']);
  assert.deepEqual(selection(['--composed-graph']), ['infer-graph-node', 'infer-graph-edge']);
  assert.deepEqual(selection(['--two-source-read-approval']), ['read-approval']);
  assert.deepEqual(selection(['--optional-effect-only']), []);

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

test('Source approval narrowing preserves ordinary optional Effect pairs and restart outputs', () => {
  const script = readFileSync(new URL('./test-packed-salesforce-source.mjs', import.meta.url), 'utf8');
  const selection = flags => fixtureSelection(script, flags, 'optionalCases');
  assert.deepEqual(selection([]), ['native-json', 'broad-text']);
  assert.deepEqual(selection(['--optional-effect-only']), ['native-json', 'broad-text']);
  for (const flag of ['--two-source-read-approval', '--two-source-effect',
    '--composed-infer', '--composed-text']) assert.deepEqual(selection([flag]), []);
  const output = script.match(/process\.stdout\.write\((boundary[^,]+),/u)?.[1];
  assert.ok(output, 'the same termination driver must serve both approval paths and the pure pair');
  for (const [boundary, expected] of [
    ['source-waiting', 'held\\n'], ['capture-waiting', 'held\\n'], ['completed', 'held\\n'],
    ['source-approval-committed', 'approved\\n'], ['approval-committed', 'approved\\n'],
  ]) assert.equal(runInNewContext(output, {boundary}), expected);
  assert.ok(script.includes("name === 'effect_resume_failed' || name === 'source_resume_failed'"));
  assert.ok(script.includes("optionalKind && name === 'acquisition_completed'"));
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

test('packed Source approval preserves the credential Site account identity', () => {
  const script = readFileSync(new URL('./test-packed-salesforce-source.mjs', import.meta.url), 'utf8');
  const accountConfiguration = JSON.stringify({
    version: 'actql-execution-account-config/0.1', account_id: 'shared-site-account',
    entries: [{entry_id: 'a-fixture-model', outcome: 'allow',
      principal: {all: true}, connection: {any_of: ['unused-model']},
      resource: {any_of: ['unused-task']}, operation: {any_of: ['infer']}, exclusions: []}],
  });
  const setup = script.slice(script.indexOf('const authorization = JSON.parse(readFileSync'),
    script.indexOf('const pendingScratch ='));
  const actual = JSON.parse(runInNewContext(setup + '\nJSON.stringify(authorization)', {
    readFileSync: () => JSON.stringify({accountConfiguration}),
    sourceReadApproval: true, modelApproval: false,
    process: {env: {}, argv: ['node', 'packed-fixture']},
  }));
  assert.equal(actual.accountConfiguration, accountConfiguration,
    'an unused Model rule must not make Host and Site configuration CIDs diverge');
  assert(script.includes('if (!sourceReadApproval) {\n    const model = await modelConfiguration'),
    'Source approval case still installs no Model');
});

test('packed Effect target reads keep distinct approval phases and independent provider counts', () => {
  const script = readFileSync(new URL('./test-packed-salesforce-source.mjs', import.meta.url), 'utf8');
  const select = flags => fixtureSelection(script, flags,
    '{targetReadApprovalEnabled, compositionCases, optionalCases}');
  assert.equal(select([]).targetReadApprovalEnabled, true);
  assert.deepEqual(select(['--target-read-approval']), {
    targetReadApprovalEnabled: true, compositionCases: [], optionalCases: []});
  assert.equal(select(['--two-source-read-approval']).targetReadApprovalEnabled, false);
  assert.deepEqual(select([]).compositionCases,
    ['source', 'infer', 'infer-model-approval', 'infer-text', 'infer-graph-node', 'infer-graph-edge', 'read-approval']);
  assert.deepEqual(select([]).optionalCases, ['native-json', 'broad-text']);
  const expected = JSON.parse(readFileSync(new URL(
    './fixtures/effect-target-read-approval.expected.json', import.meta.url), 'utf8'));
  assert.deepEqual(expected.targetReadCounts, [0, 0, 0, 0, 8, 8, 12, 12]);
  assert.deepEqual(expected.effectWriteCounts, [0, 0, 0, 0, 0, 0, 4, 4]);
  assert.equal(expected.writes.length, 4);
  assert.ok(script.includes("['target-answer', ['0'], 'approved']"));
  assert.ok(script.includes("['target-answer', ['1'], 'approved']"));
  assert.ok(script.includes("delete environment.ACTQL_LOCAL_SOURCE_PROFILE"));
  assert.ok(script.includes("'effect-target-read-approval.expected.json'"));
});

test('each Client group retains its acceptance commands exactly once', () => {
  assert.deepEqual(runs('client-distribution'), ['npm run check:distribution-client']);
  assert.deepEqual(runs('client-packed'), [
    'npm run check:packed-embedded-checkpoint',
    'node scripts/test-packed-single-infer.mjs',
    'node scripts/test-packed-infer-evaluation.mjs',
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
    ['packed-infer-evaluation', 'packed-infer-evaluation'],
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

test('admission-only flags narrow the existing Source case without ordinary Effect or Model selection', () => {
  const script = readFileSync(new URL('./test-packed-salesforce-source.mjs', import.meta.url), 'utf8');
  for (const flag of ['--admission-only', '--admission-https-only']) {
    assert.deepEqual(fixtureSelection(script, [flag],
      '{targetReadApprovalEnabled, compositionCases, optionalCases}'), {
      targetReadApprovalEnabled: false, compositionCases: ['source'], optionalCases: [],
    });
  }
});

// Pure fixture observation controls. These execute no Client, Host or Journal.
function checkpointObservationDeclarations() {
  const source = readFileSync(new URL('./fixtures/packed-embedded-checkpoint.mjs', import.meta.url), 'utf8');
  const ast = parseJavaScript(source, {ecmaVersion: 'latest', sourceType: 'module'});
  const functionSource = name => {
    const declaration = ast.body.find(node => node.type === 'FunctionDeclaration' && node.id.name === name);
    assert(declaration, `Missing actual fixture declaration ${name}`);
    return source.slice(declaration.start, declaration.end);
  };
  return {source, ast, functionSource};
}

test('packed checkpoint observation covers the configured retry inside the original child budget', () => {
  const {functionSource} = checkpointObservationDeclarations();
  const schedule = new Function('assert', functionSource('checkpointObservationSchedule') +
    ';return checkpointObservationSchedule;')(assert);
  assert.deepEqual(schedule(10000), {pollMs: 25, retryMs: 10100, polls: 808});
  assert.equal(schedule(10000).polls * schedule(10000).pollMs, 20200);
  assert(3 * 20200 < 120000);
  for (const invalid of [undefined, 0, -1, 999, 1000.5, 20000]) assert.throws(() => schedule(invalid));
});

test('packed checkpoint first diagnostic and public pending observations cannot overwrite each other', () => {
  const {source, ast, functionSource} = checkpointObservationDeclarations();
  const recordOriginal = new Function(functionSource('checkpointObservationRecord') +
    ';return checkpointObservationRecord;')();
  const records = [], events = [];
  const record = (kind, data) => recordOriginal(records, kind, data);
  const assignment = ast.body.find(node => node.type === 'ExpressionStatement' &&
    node.expression.type === 'AssignmentExpression' && node.expression.left.type === 'MemberExpression' &&
    node.expression.left.object.name === 'authorization' && node.expression.left.property.name === 'faultInjection');
  assert(assignment);
  const callback = source.slice(assignment.expression.right.start, assignment.expression.right.end);
  const observe = new Function('record', 'appendFileSync', `
    let firstResumeFailure, retryClaimAfterFailure=false, recoveryAfterFailure=false;
    return ${callback};`)(record, (path, value) => {assert.equal(path, 'embedded-events.log'); events.push(value);});
  record('first-lookup', {kind: 'held', state: 'resuming'});
  observe('resume_claimed', {generation: 1});
  observe('resume_failed', {code: 'OriginalResumeFailure'});
  observe('sweep_failed', {code: 'LaterDifferentFailure'});
  observe('resume_claimed', {generation: 2});
  observe('run_observed', {});
  record('first-lookup', {kind: 'found'});
  assert.deepEqual(records.find(item => item.kind === 'first-lookup').data, {kind: 'held', state: 'resuming'});
  assert.deepEqual(records.find(item => item.kind === 'first-resume-failure').data,
    {event: 'resume_failed', code: 'OriginalResumeFailure'});
  assert.deepEqual(records.find(item => item.kind === 'resume-claim-after-failure').data, {generation: 2});
  assert(records.some(item => item.kind === 'run-observed-after-failure'));
  assert.equal(records.some(item => item.kind === 'busy'), false, 'a held lookup is not a typed busy cause');
  assert.deepEqual(events, ['resume_claimed\n', 'resume_failed\n', 'sweep_failed\n',
    'resume_claimed\n', 'run_observed\n']);
});

test('packed checkpoint close records actual return and preserves the first pending failure', async () => {
  const {functionSource} = checkpointObservationDeclarations();
  const records = [], record = (kind, data) => records.push({kind, data});
  let release;
  const first = {close() {assert.equal(this, first); return new Promise(resolve => {release = resolve;});}};
  const owner = new Function('record', 'initialClient', 'nodeTypes', `let client=initialClient; const closedClients=new WeakSet();
    ${functionSource('checkpointFailureData')}
    ${functionSource('closeClient')}
    return {closeClient,setClient(value){client=value;}};`)(record, first, nodeTypes);
  const closing = owner.closeClient('first');
  assert.deepEqual(records, [{kind: 'close-attempt:first', data: {first: true}}]);
  release(); await closing;
  assert.deepEqual(records.at(-1), {kind: 'close-returned:first', data: {first: true}});
  const failure = Object.assign(new Error('same pending cleanup'), {code: 'ClientCleanupPending'});
  const pending = {close() {assert.equal(this, pending); throw failure;}};
  owner.setClient(pending);
  await assert.rejects(owner.closeClient('pending'), error => error === failure);
  assert.deepEqual(records.at(-1), {kind: 'close-failed:pending',
    data: {first: true, name: null, code: 'ClientCleanupPending'}});
  assert.equal(records.some(item => item.kind === 'close-returned:pending'), false);
});

test('packed checkpoint failure capture reads only own scalar DATA without getters or opaque causes', () => {
  const {functionSource} = checkpointObservationDeclarations();
  const capture = new Function('nodeTypes', functionSource('checkpointFailureData') +
    ';return checkpointFailureData;')(nodeTypes);
  let reads = 0;
  const error = new Error('original scalar code');
  Object.defineProperty(error, 'code', {get() {reads++; throw new Error('must not run');}});
  Object.defineProperty(error, 'cause', {get() {reads++; throw new Error('opaque cause');}});
  assert.deepEqual(capture(error), {name: null, code: null});
  const proxy = new Proxy({}, {getOwnPropertyDescriptor() {reads++; throw new Error('opaque proxy');}});
  for (const value of [proxy, undefined, null, 1, 'failure']) {
    assert.deepEqual(capture(value), {name: null, code: null});
  }
  assert.equal(reads, 0);
  assert.deepEqual(capture({name: 'OriginalPublicFailure', code: 'UnexpectedOriginalCode'}),
    {name: 'OriginalPublicFailure', code: 'UnexpectedOriginalCode'});
});

test('packed checkpoint dispatch capture excludes messages, identities, getters and opaque values', () => {
  const {functionSource} = checkpointObservationDeclarations();
  const capture = new Function('nodeTypes', functionSource('checkpointDispatchFailureData') +
    ';return checkpointDispatchFailureData;')(nodeTypes);
  let reads = 0;
  const getter = {get() {reads++; throw new Error('must not inspect');}};
  const detail = Object.create({primaryCode: 'InheritedCode', issueTag: 1});
  for (const key of ['primaryCode', 'issueTag', 'nestedIssueTag', 'ref', 'cause']) {
    Object.defineProperty(detail, key, getter);
  }
  assert.deepEqual(capture(detail), {});
  const proxy = new Proxy({}, {getOwnPropertyDescriptor() {reads++; throw new Error('opaque');}});
  for (const value of [proxy, undefined, null, 1, 'failure', () => {}]) {
    assert.equal(capture(value), undefined);
  }
  const original = {primaryCode: 'OriginalFailure:Preparation', issueTag: 12, nestedIssueTag: 5,
    code: 'private message', message: 'private payload', ref: {opaque: true}, cause: proxy};
  const data = capture(original);
  assert.deepEqual(data, {primaryCode: 'OriginalFailure:Preparation', issueTag: 12, nestedIssueTag: 5});
  assert(Object.isFrozen(data));
  original.primaryCode = 'LaterFailure';
  assert.equal(data.primaryCode, 'OriginalFailure:Preparation');
  for (const primaryCode of ['', 'private message', 'X'.repeat(129), proxy, 1]) {
    assert.deepEqual(capture({primaryCode}), {});
  }
  for (const issueTag of [-1, 65536, 1.5, NaN, Infinity, '12', proxy]) {
    assert.deepEqual(capture({issueTag, nestedIssueTag: issueTag}), {});
  }
  assert.deepEqual(capture({issueTag: 0, nestedIssueTag: 65535}), {issueTag: 0, nestedIssueTag: 65535});
  assert.equal(reads, 0);
});

test('packed checkpoint observes only the existing dispatch event and preserves its first DATA', () => {
  const {source, ast, functionSource} = checkpointObservationDeclarations();
  const assignment = ast.body.find(node => node.type === 'ExpressionStatement' &&
    node.expression.type === 'AssignmentExpression' && node.expression.left.type === 'MemberExpression' &&
    node.expression.left.object.name === 'authorization' && node.expression.left.property.name === 'observe');
  assert(assignment);
  const opening = ast.body.find(node => node.type === 'VariableDeclaration' &&
    node.declarations.some(declaration => declaration.id.name === 'open'));
  assert(assignment.end < opening.start, 'the existing observer is configured before the original connect');
  const callback = source.slice(assignment.expression.right.start, assignment.expression.right.end);
  const records = [];
  const observe = new Function('nodeTypes', 'records', `
    ${functionSource('checkpointDispatchFailureData')}
    ${functionSource('checkpointObservationRecord')}
    const record=(kind,data)=>checkpointObservationRecord(records,kind,data);
    return ${callback};`)(nodeTypes, records);
  const opaque = new Proxy({}, {get() {throw new Error('must not read unrelated events');}});
  assert.equal(observe('resume_failed', opaque), undefined);
  assert.equal(observe('dispatch_settlement_failed', opaque), undefined);
  assert.equal(observe('dispatch_failed', null), undefined);
  assert.equal(observe('dispatch_failed', {primaryCode: 'OriginalFailure', issueTag: 12}), undefined);
  for (let index = 0; index < 100; index++) observe('dispatch_failed', {primaryCode: 'LaterFailure'});
  assert.deepEqual(records, [{kind: 'diagnostic:dispatch_failed',
    data: {primaryCode: 'OriginalFailure', issueTag: 12}}]);
});
