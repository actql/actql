import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile, writeFile, copyFile, symlink, unlink, readlink, mkdir, mkdtemp, readdir, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {execFileSync} from 'node:child_process';
import {join, dirname} from 'node:path';
import {parse} from 'yaml';
import {parse as parseJavaScript} from 'acorn';
import {gateJobs, gateJobRequired, selectTargets, verifyGate} from './ci-targets.mjs';
import {mockWorkflowMetrics} from './health-monitor-adapters.mjs';
import {packedReadmeCases, packedCompositionCases} from './test-packed-readme-workflows.mjs';
import {packedEffectControlCases, assertMockEffectControlOutcome} from './packed-mock-effect-controls.mjs';
import {nodeBenchmarkFailure} from './benchmark-node-operations.mjs';
import {twoModelDealReviewFiles, twoModelWholeDealReviewFiles} from './fixtures/deal-review-two-models.mjs';
import {projectTemplateFiles} from '../packages/native-cli/lib/project-template.mjs';
import {createCommandEvidence, checkCommandEvidenceUpload} from './packed-query-evidence.mjs';
import {nativeCoreScopedTestEnvironment} from './native-core-test-selection.mjs';

const workflow = parse(await readFile(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
const name = 'client-readme-packed', job = workflow.jobs[name];
const repository = new URL('../', import.meta.url).pathname;
// Explicit command-port outcomes only; actual installed counters are produced
// by the fixture's configured Host observation, never by this test oracle.
const explicitWork = (phase, variant = 'readme') => ({complete: true,
  sourceAcquisitionStarts: phase === 'capture' ? 2 : 0,
  modelCallStarts: phase === 'capture' ? variant === 'readme' ? 2 : 4 : 0,
  effectReplacementReturns: phase === 'approve' ? 2 : 0});
const explicitStep = (phase, step) => ({phase, step, status: 'passed', timing: {
  startedAt: '2026-01-01T00:00:00.000Z', endedAt: '2026-01-01T00:00:00.001Z',
  wallNs: 1000000, cpuUserUs: 0, cpuSystemUs: 0, scope: 'Explicit test port, not a runtime measurement'}});

test('README call bounds come from authored joined rows and declared per-row Tasks rather than prior observations', () => {
  for (const template of ['churn-risk-mock', 'deal-review-mock']) {
    const files = projectTemplateFiles(template), data = JSON.parse(files['mock/data.json']);
    const config = JSON.parse(files['actql.config.json']), catalog = JSON.parse(files['mock/catalog.json']);
    assert.equal(Object.values(catalog.connections).reduce((sum, connection) => sum + connection.data.length, 0), 2);
    const left = template === 'churn-risk-mock' ? data.salesforce.Account.rows : data.salesforce.Opportunity.rows;
    const right = template === 'churn-risk-mock' ? data.snowflake.usage_30d.rows : data.drive.files.rows;
    assert.equal(left.length, 2); assert.equal(right.length, 2);
    const joined = left.flatMap(row => right.filter(other => template === 'churn-risk-mock'
      ? row.id === other.account_id : row.name === other.name));
    assert.equal(joined.length, 2);
    const tasks = JSON.parse(files['model-tasks.json']).tasks;
    assert.equal(Object.keys(tasks).length, 1);
    const answers = parse(files[Object.values(config.mock.answers)[0].replace(/^\.\//u, '')]).answers.by_key;
    assert.deepEqual(Object.keys(answers).sort(), left.map(row => row.id).sort());
    for (const value of Object.values(answers)) assert(template === 'churn-risk-mock' ? value.level === 'high' : value.changed === true);
  }
  for (const make of [twoModelDealReviewFiles, twoModelWholeDealReviewFiles]) {
    const files = make(), program = JSON.parse(files['deal-review.program.json']);
    assert.equal(Object.keys(JSON.parse(files['model-tasks.json']).tasks).length, 2);
    assert.equal(program.stages.flatMap(stage => stage.steps).filter(step => step.infer).length, 2);
    const answers = parse(files['mock/deal-review-confirm.v1.answers.yaml']).answers.by_key;
    assert.equal(Object.keys(answers).length, 2);
    assert(Object.values(answers).every(value => value.confirmed === true));
  }
});

test('distinct Whole producer fixture retains both Model Units and all public Result readers', async () => {
  const files = twoModelWholeDealReviewFiles(), program = JSON.parse(files['deal-review.program.json']);
  assert.deepEqual(program.stages.map(stage => stage.id), ['source_opportunities', 'review', 'confirm', 'apply']);
  assert.deepEqual(program.stages[1].inputs.opportunities,
    {result: {stage: 'source_opportunities', result: 'rows'}});
  assert.deepEqual(program.stages[0].inputs,
    {opportunities: {connector: 'salesforce', resource: 'Opportunity'}});
  assert.equal(program.stages.flatMap(stage => stage.steps).filter(step => step.infer !== undefined).length, 2);
  assert.deepEqual(program.stages[3].inputs.confirmed, {result: {stage: 'confirm', result: 'rows'}});
  assert.deepEqual(program.results?.updates, {from: {stage: 'apply', result: 'rows'}});
  assert.deepEqual(Object.keys(program.results), ['answer', 'main', 'updates']);
  const source = await readFile(new URL('../adapters/host-node/fixtures/mock-project-effect-public.mjs', import.meta.url), 'utf8');
  const original = parseJavaScript(source, {ecmaVersion: 'latest', sourceType: 'module'}).body
    .find(node => node.id?.name === 'readWholeResults');
  const read = new Function('assert', `return (${source.slice(original.start, original.end)});`)(assert);
  const sourceRows = [
    {id: '006Acme', name: 'Acme Corp - Renewal', StageName: 'Proposal', NextStep: null},
    {id: '006Globex', name: 'Globex - Expansion', StageName: 'Negotiation', NextStep: 'Legal review'},
  ];
  const updates = sourceRows.map(({name, ...row}) => ({...row, review: {outcome: 'ok', value: {}},
    confirmation: {outcome: 'ok', value: {confirmed: true}}}));
  const reviewed = updates.map(({confirmation, ...row}) => row);
  const roots = {answer: sourceRows, main: reviewed}, calls = [];
  const execution = {result(name) {calls.push(name); return {all: async () => roots[name]};}};
  assert.deepEqual(await read(execution, updates), roots);
  assert.deepEqual(calls, ['answer', 'main']);
  roots.main = [];
  await assert.rejects(read(execution, updates), {code: 'ERR_ASSERTION'});
});

test('existing collector keeps the distinct Whole fixture and original cold inputs separate', async t => {
  const {root, consumer} = await scratch(t), phases = [];
  const metric = await mockWorkflowMetrics({prepared: {consumer}, root, repository,
    counts: {coldSamples: 1}, template: 'deal-review-mock', variant: 'two-models-whole', onMetric() {},
    async command(executable, args, options) {
      const phase = args[1]; phases.push(phase);
      assert.equal(args.at(-1), 'two-models-whole');
      const input = join(options.cwd, 'deal-review.program.json');
      if (phase !== 'capture') await assert.rejects(readFile(input), {code: 'ENOENT'});
      else assert.equal(JSON.parse(await readFile(input, 'utf8')).stages[0].id, 'source_opportunities');
      const count = {capture: 10, approve: 11, recover: 7}[phase];
      return {pid: 20000 + phases.length, code: 0, signal: null, wallNs: 100,
        stdout: [...Array.from({length: count}, (_, index) => explicitStep(phase, `explicit-${index}`)),
          {phase, status: 'passed', firstFailedStep: null, firstClose: {attempted: true, returned: true},
            workObservation: explicitWork(phase, 'two-models-whole')}]
          .map(value => JSON.stringify(value)).join('\n')};
    }});
  assert.deepEqual(phases, ['capture', 'approve', 'recover']);
  assert.equal(metric.variant, 'two-models-whole');
  assert.equal(metric.samples[0].verified, true);
});

test('record fixture bounds use authored Whole binary and three-Source occurrences on the original Run only', async () => {
  const source = await readFile(new URL('../adapters/host-node/fixtures/work-observation.fixture.mjs', import.meta.url), 'utf8');
  const node = parseJavaScript(source, {ecmaVersion: 'latest', sourceType: 'module'}).body
    .find(value => value.type === 'ExportNamedDeclaration' && value.declaration?.id?.name === 'assertRecordWorkflowWork').declaration;
  const check = Function('assert', `return (${source.slice(node.start, node.end)});`)(assert);
  for (const [variant, starts] of [['whole-input', 1], ['binary-source', 2], ['three-source', 3]]) {
    for (const phase of ['capture', 'approve', 'recover']) {
      const writes = phase === 'approve' ? 1 : 0;
      const work = {complete: true, sourceAcquisitionStarts: phase === 'capture' ? starts : 0,
        modelCallStarts: 0, effectReplacementReturns: writes,
        totals: {sourceAcquisitionStarts: starts + 1, modelCallStarts: 0, effectReplacementReturns: writes}};
      check(work, {phase, variant});
      for (const changed of [
        {...work, complete: false}, {...work, modelCallStarts: 1},
        {...work, totals: {...work.totals, modelCallStarts: 1}},
        {...work, sourceAcquisitionStarts: work.sourceAcquisitionStarts + 1},
        {...work, effectReplacementReturns: writes + 1},
      ]) assert.throws(() => check(changed, {phase, variant}));
      if (phase === 'capture') assert.throws(() => check({...work, sourceAcquisitionStarts: starts - 1}, {phase, variant}));
      assert.throws(() => check(work, {phase, variant: 'inferred-from-observation'}));
    }
  }
});

test('record ordinary runner binds the exact selected fixture variant before the existing installed child', async () => {
  const source = await readFile(new URL('./test-packed-hubspot-source.mjs', import.meta.url), 'utf8');
  const tree = parseJavaScript(source, {ecmaVersion: 'latest', sourceType: 'module'});
  const pending = [tree], calls = [];
  while (pending.length) {
    const node = pending.pop();
    if (node.type === 'CallExpression' && node.callee?.name === 'runFocusedTests') calls.push(node);
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) pending.push(...value.filter(item => item?.type));
      else if (value?.type) pending.push(value);
    }
  }
  assert.equal(calls.length, 1); const [call] = calls;
  const invoke = Function('runFocusedTests', 'approval', 'mockConnector', 'application', 'expectedTests',
    'wholeMock', 'threeSourceMock', 'binarySourceMock', 'process', `return (${source.slice(call.start, call.end)});`);
  for (const [whole, three, binary, expected] of [
    [true, false, false, 'whole-input'], [false, true, false, 'three-source'],
    [false, false, true, 'binary-source'], [false, false, false, ''],
  ]) {
    let selected;
    invoke((_kind, files, options) => {selected = {files, options}; return 0;}, true, 'hubspot',
      '/own-fresh-consumer', 1, whole, three, binary, {env: {HARNESS_ONLY: 'true'}});
    assert.deepEqual(selected.files, ['scripts/fixtures/packed-record-approval-mock.mjs']);
    assert.equal(selected.options.expectedTests, 1);
    assert.equal(selected.options.env.ACTQL_RECORD_APPROVAL_MOCK_VARIANT, expected);
    assert.equal(selected.options.env.ACTQL_RECORD_APPROVAL_REMOVE_PROGRAMS, expected ? '1' : undefined);
  }
});

test('Whole three-Source and binary JOIN evidence preserves failed commands and requires original nonzero qualification', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-approval-evidence-'));
  t.after(() => rm(root, {recursive: true}));
  await mkdir(join(root, 'scripts'));
  const child = `
    const assert=require('node:assert/strict');
    assert.equal(process.argv[2],'--ci-evidence-child');
    assert.equal(process.argv[3],process.env.EVIDENCE_SELECTION);
    console.log('Bearer fixture-only-secret');
    const mode=process.env.EVIDENCE_MODE;
    if(mode==='exit'){console.error('OriginalFixtureFailure');process.exit(7);}
    if(mode==='signal'){process.kill(process.pid,'SIGTERM');}
    if(mode==='missing')process.exit(0);
    const receipt={fixtureVariant:mode==='variant'?'foreign':process.env.EVIDENCE_VARIANT,
      productSource:process.env.EVIDENCE_SOURCE,freshNormalInstall:true,expectedTests:1,observedExitCode:0,
      manifestSha256:'b'.repeat(64),actualCounts:{tests:1,passed:1,failed:0,cancelled:0,skipped:0,todo:0}};
    if(mode==='zero')receipt.actualCounts={tests:0,passed:0,failed:0,cancelled:0,skipped:0,todo:0};
    console.log('PACKED_HUBSPOT_PUBLIC '+JSON.stringify(receipt));
  `;
  await writeFile(join(root, 'scripts/test-packed-hubspot-source.mjs'), child.replace(
    "const assert=require('node:assert/strict');", "import assert from 'node:assert/strict';"));
  const git = args => execFileSync('git', args, {cwd: root, encoding: 'utf8', timeout: 5000});
  git(['init', '--quiet']); git(['add', 'scripts']);
  git(['-c', 'core.hooksPath=/dev/null', '-c', 'user.name=Evidence fixture',
    '-c', 'user.email=evidence@example.invalid', '-c', 'commit.gpgsign=false',
    'commit', '--quiet', '-m', 'test: retain explicit evidence command']);
  const sourceSha = git(['rev-parse', 'HEAD']).trim();
  const source = await readFile(new URL('./test-packed-hubspot-source.mjs', import.meta.url), 'utf8');
  const declaration = parseJavaScript(source, {ecmaVersion: 'latest', sourceType: 'module'}).body
    .map(value => value.type === 'ExportNamedDeclaration' ? value.declaration : value)
    .find(value => value?.type === 'FunctionDeclaration' && value.id.name === 'collectPackedApprovalEvidence');
  assert(declaration);
  const collect = Function('assert', 'createCommandEvidence', 'join', 'process',
    `return (${source.slice(declaration.start, declaration.end)});`)(assert, createCommandEvidence, join, process);
  for (const [selection, variant] of [['--mock-hubspot-whole-approval', 'whole-input'],
    ['--mock-hubspot-three-source-approval', 'three-source'],
    ['--mock-hubspot-binary-source-approval', 'binary-source']]) {
    for (const mode of ['pass', 'exit', 'signal', 'missing', 'variant', 'zero']) {
      const output = join(root, `${variant}-${mode}.output`);
      const invoke = () => collect({repository: root, selection, env: {...process.env,
        GITHUB_OUTPUT: output, EVIDENCE_SELECTION: selection, EVIDENCE_VARIANT: variant,
        EVIDENCE_MODE: mode, EVIDENCE_SOURCE: sourceSha, EVIDENCE_TEST_SECRET: 'fixture-only-secret'}});
      if (mode === 'pass') assert(invoke().startsWith('/'));
      else assert.throws(invoke);
      const record = await readFile(output, 'utf8');
      const directory = /^evidence-directory=(.+)$/mu.exec(record)?.[1]; assert(directory);
      const selected = checkCommandEvidenceUpload(directory);
      const summary = JSON.parse(await readFile(join(directory, 'summary.json'), 'utf8'));
      assert.equal(summary.status, mode === 'pass' ? 'passed' : 'failed');
      assert.equal(summary.complete, mode === 'pass');
      assert.equal(summary.qualification.qualified, mode === 'pass');
      assert.equal(summary.qualification.fixtureVariant, variant);
      assert.equal(summary.commands.length, 1);
      if (mode === 'exit') assert.equal(summary.commands[0].status, 7);
      if (mode === 'signal') assert.equal(summary.commands[0].signal, 'SIGTERM');
      const raw = await readFile(join(directory, '001.stdout.log'), 'utf8');
      assert(!raw.includes('fixture-only-secret')); assert(raw.includes('[REDACTED]'));
      assert(selected.includes('001.result.json')); assert(selected.includes('001.stderr.log'));
      assert(!selected.some(path => /qualification\.json|state|\.sqlite|keys|node_modules/u.test(path)));
    }
  }
});

test('Whole three-Source and binary JOIN CI always collects only the invocation bounded diagnostic directory', () => {
  const steps = workflow.jobs['client-packed'].steps;
  for (const [id, selection] of [
    ['packed-hubspot-whole', '--mock-hubspot-whole-approval'],
    ['packed-hubspot-three-source', '--mock-hubspot-three-source-approval'],
    ['packed-hubspot-binary-source', '--mock-hubspot-binary-source-approval'],
  ]) {
    const consumer = steps.find(step => step.id === id); assert(consumer);
    assert.equal(consumer.run, `node scripts/test-packed-hubspot-source.mjs --ci ${selection}`);
    assert.equal(consumer.if, "${{ !cancelled() && steps.client-inputs.outcome == 'success' }}");
    assert.equal(Object.values(workflow.jobs).flatMap(job => job.steps ?? [])
      .filter(step => step.run?.includes(selection)).length, 1, 'Each original consumer runs once');
    const upload = steps.find(step => step.with?.directory === `\${{ steps.${id}.outputs.evidence-directory }}`);
    assert(upload); assert(steps.indexOf(upload) > steps.indexOf(consumer));
    assert.equal(upload.if, `always() && steps.${id}.outputs.evidence-directory != ''`);
    assert.equal(upload.uses, './.github/actions/upload-packed-query-evidence');
    assert.equal(upload['continue-on-error'], undefined);
    assert.equal(consumer['continue-on-error'], undefined);
    assert(!Object.hasOwn(upload.with, 'path'), 'Never upload the private application/state scratch');
  }
  assert(workflow.jobs.client.needs.includes('client-packed'), 'Original consumers remain required');
});
test('required README job reuses the exact single producer on Node 22 and 24 with failure retention', () => {
  assert(job); assert.deepEqual(job.needs, ['select-targets', 'preflight', 'client-packages']);
  assert.equal(job.strategy['fail-fast'], false);
  assert.deepEqual(job.strategy.matrix.node, ['22.22.0', '24']);
  const input = job.steps.find(step => step.uses === './.github/actions/download-client-packages');
  assert.equal(input.with['artifact-id'], '${{ needs.client-packages.outputs.artifact-id }}');
  assert(job.steps.some(step => step.run === 'node scripts/test-packed-readme-workflows.mjs "$RUNNER_TEMP/client-readme-packed"'));
  assert(!job.steps.some(step => /npm pack|build:runtime|moon (?:build|test)/u.test(step.run ?? '')));
  assert(job.steps.every(step => !Object.hasOwn(step.env ?? {}, 'CI_PLAN')));
  const output = job.steps.find(step => step.uses?.startsWith('actions/upload-artifact@'));
  assert.equal(output.if, 'always()'); assert.equal(output.with['if-no-files-found'], 'error');
  assert(output.with.path.includes('raw/*')); assert(output.with.path.includes('*.observation.json'));
  assert(output.with.path.includes('mock-project-*/*.pending.json'));
  assert(output.with.path.includes('collection/*.pending.json'));
  assert(output.with.path.includes('mock-effect-control-*/*.observation.json'));
  assert(output.with.path.includes('mock-effect-control-*/*.before-close.json'));
  assert.deepEqual(workflow.jobs.check.needs, gateJobs);
  const basic = workflow.jobs.lint.steps.map(step => step.run ?? '').join('\n');
  assert(basic.includes('adapters/host-node/client-result-collection-policy.test.mjs'));
  assert(basic.includes('scripts/packed-readme-ci.test.mjs'));
  assert(basic.includes('scripts/native-cli-default-numeric.test.mjs'));
});

test('required README gate selects actual SDK Host Core schema and packaging PR inputs and rejects skipped failure', () => {
  const sha = 'a'.repeat(40);
  for (const path of ['packages/sdk/internal/result-read.mjs', 'adapters/host-node/embedded-local.mjs',
    'src/client_local_host/resource_policy.mbt', 'spec/contracts/actql-client-host.json',
    'scripts/packed-client-packages.mjs', 'scripts/packed-mock-effect-controls.mjs',
    'scripts/fixtures/mock-project-effect-cancel-public.mjs']) {
    const selection = selectTargets([path], {draft: false, event: 'pull_request'});
    assert.equal(gateJobRequired(selection, name), true, path);
    const results = Object.fromEntries(gateJobs.map(key => [key,
      {result: gateJobRequired(selection, key) ? 'success' : 'skipped'}]));
    const envelope = {sourceRevision: sha, selection};
    const context = {event: 'pull_request', sourceRevision: sha, draft: false};
    verifyGate(envelope, results, context);
    for (const result of ['failure', 'cancelled', 'skipped', undefined]) {
      assert.throws(() => verifyGate(envelope, {...results, [name]: {result}}, context), /client-readme-packed/u);
    }
  }
  assert.equal(gateJobRequired({profile: 'maintenance', event: 'pull_request'}, name), false);
  assert.equal(gateJobRequired({profile: 'draft', event: 'pull_request'}, name), false);
});

async function scratch(t) {
  // Authored callback-only fixture: no Host, Run, database or key is created.
  const root = await mkdtemp(join(tmpdir(), 'actql-readme-ci-unit-'));
  const consumer = join(root, 'consumer'); await mkdir(join(consumer, 'node_modules'), {recursive: true});
  t.after(() => rm(root, {recursive: true, force: true}));
  return {root, consumer};
}
test('required README cases use three distinct project paths and original independent phase counts', async t => {
  assert.deepEqual(packedReadmeCases, [
    {template: 'churn-risk-mock', variant: 'readme'},
    {template: 'deal-review-mock', variant: 'readme'},
    {template: 'deal-review-mock', variant: 'two-models'},
  ]);
  const {root, consumer} = await scratch(t), commands = [];
  for (const selected of packedReadmeCases) {
    let originalInputs;
    const metric = await mockWorkflowMetrics({prepared: {consumer}, root, repository,
      counts: {coldSamples: 1}, ...selected, onMetric() {},
      async command(executable, args, options) {
        commands.push({executable, args, options});
        assert.deepEqual(await readFile(join(options.cwd, 'work-observation.fixture.mjs')),
          await readFile(new URL('../adapters/host-node/fixtures/work-observation.fixture.mjs', import.meta.url)));
        const phase = args[1], expected = {capture: 10, approve: 11, recover: 7}[phase];
        if (phase === 'capture') {
          originalInputs = [selected.variant === 'two-models' ? 'deal-review.program.json'
            : selected.template === 'deal-review-mock' ? 'deal-review.aql' : 'churn-risk.aql',
          ...(await readdir(join(options.cwd, 'mock'))).filter(name => name.endsWith('.answers.yaml')).map(name => `mock/${name}`)];
        }
        for (const input of originalInputs) {
          if (phase !== 'capture') await assert.rejects(readFile(join(options.cwd, input)), {code: 'ENOENT'});
          else assert((await readFile(join(options.cwd, input))).length > 0);
        }
        // Recovery keeps the original configuration and physical target input.
        assert((await readFile(join(options.cwd, 'actql.config.json'))).length > 0);
        assert((await readFile(join(options.cwd, 'mock/data.json'))).length > 0);
        return {pid: 10000 + commands.length, code: 0, signal: null, wallNs: 100,
          stdout: [...Array.from({length: expected}, (_, n) => explicitStep(phase, `explicit-${n}`)),
            {phase, status: 'passed', firstFailedStep: null,
              workObservation: explicitWork(phase, selected.variant),
              firstClose: {attempted: true, returned: true}}].map(value => JSON.stringify(value)).join('\n')};
      }});
    assert.equal(metric.samples.length, 1); assert.equal(metric.samples[0].verified, true);
    assert.equal(metric.samples[0].phases.length, 3);
    const project = join(root, `mock-project-${selected.template}-${selected.variant}-0`);
    assert(!(await readdir(project)).includes('node_modules'));
    for (const phase of ['capture', 'approve', 'recover']) {
      const actual = JSON.parse(await readFile(join(project, `${phase}.observation.json`), 'utf8'));
      assert.equal(actual.completed, true); assert.equal(actual.exitCode, 0);
      assert.equal(actual.operations.length, {capture: 10, approve: 11, recover: 7}[phase]);
      assert(actual.operations.every(value => value.timing.wallNs === 1000000));
      if (phase === 'capture') {
        assert.equal(actual.inputRemoval.completed, true);
        assert.deepEqual([...actual.inputRemoval.paths].sort(), [...originalInputs].sort());
      }
      if (phase === 'approve') assert.equal(actual.originalInputsAbsentBeforeApproval, true);
      if (phase === 'recover') {
        assert.equal(actual.originalInputsAbsentBeforeSaved, true);
        assert.equal(actual.originalInputsAbsentAfterSaved, true);
      }
    }
  }
  assert.equal(commands.length, 9); assert.equal(new Set(commands.map(value => value.options.cwd)).size, 3);
  assert.equal(new Set(commands.map(value => value.options.name)).size, 9);
});

test('required README preserves inputs and never starts Saved after an unreturned FIRST close', async t => {
  const {root, consumer} = await scratch(t), phases = [];
  await assert.rejects(mockWorkflowMetrics({prepared: {consumer}, root, repository,
    counts: {coldSamples: 1}, onMetric() {},
    async command(_executable, args) {
      const phase = args[1]; phases.push(phase);
      return {pid: 10000 + phases.length, code: 0, signal: null, wallNs: 100,
        stdout: [...Array.from({length: phase === 'capture' ? 10 : 11}, (_, n) =>
          explicitStep(phase, `explicit-${n}`)),
        {phase, status: 'passed', firstFailedStep: null,
          firstClose: {attempted: true, returned: phase !== 'capture'}}].map(value => JSON.stringify(value)).join('\n')};
    }}), {code: 'ERR_ASSERTION'});
  assert.deepEqual(phases, ['capture']);
  const project = join(root, 'mock-project-churn-risk-mock-readme-0');
  for (const input of ['churn-risk.aql', 'mock/churn-risk.v1.answers.yaml']) assert((await readFile(join(project, input))).length > 0);
  const record = JSON.parse(await readFile(join(project, 'capture.observation.json'), 'utf8'));
  assert.equal(record.completed, false); assert.equal(record.exitCode, 0);
  assert.equal(record.inputRemoval, undefined);
});

test('required README never deletes replaced authored inputs or enters dependent Saved', async t => {
  const {root, consumer} = await scratch(t), phases = [];
  await assert.rejects(mockWorkflowMetrics({prepared: {consumer}, root, repository,
    counts: {coldSamples: 1}, onMetric() {},
    async command(_executable, args, options) {
      const phase = args[1]; phases.push(phase);
      if (phase === 'capture') await writeFile(join(options.cwd, 'mock/churn-risk.v1.answers.yaml'), 'changed input');
      return {pid: 10000 + phases.length, code: 0, signal: null, wallNs: 100,
        stdout: [...Array.from({length: phase === 'capture' ? 10 : 11}, (_, n) =>
          explicitStep(phase, `explicit-${n}`)),
        {phase, status: 'passed', firstFailedStep: null,
          workObservation: explicitWork(phase),
          firstClose: {attempted: true, returned: true}}].map(value => JSON.stringify(value)).join('\n')};
    }}), {code: 'ERR_ASSERTION'});
  assert.deepEqual(phases, ['capture']);
  const project = join(root, 'mock-project-churn-risk-mock-readme-0');
  assert.equal(await readFile(join(project, 'mock/churn-risk.v1.answers.yaml'), 'utf8'), 'changed input');
  assert((await readFile(join(project, 'churn-risk.aql'))).length > 0);
  const record = JSON.parse(await readFile(join(project, 'capture.observation.json'), 'utf8'));
  assert.equal(record.completed, false); assert.deepEqual(record.inputRemoval, {completed: false, paths: []});
});

test('README aggregate refuses missing lost or amplified actual work observation', async t => {
  for (const mode of ['missing', 'lost', 'source-restarted', 'model-restarted', 'write-repeated', 'untimed']) {
    const {root, consumer} = await scratch(t), phases = [];
    await assert.rejects(mockWorkflowMetrics({prepared: {consumer}, root, repository,
      counts: {coldSamples: 1}, onMetric() {},
      async command(_executable, args) {
        const phase = args[1]; phases.push(phase);
        let work = explicitWork(phase);
        if (phase === 'capture' && mode === 'missing') work = undefined;
        if (phase === 'capture' && mode === 'lost') work.complete = false;
        if (phase === 'approve' && mode === 'source-restarted') work.sourceAcquisitionStarts = 1;
        if (phase === 'approve' && mode === 'model-restarted') work.modelCallStarts = 1;
        if (phase === 'approve' && mode === 'write-repeated') work.effectReplacementReturns = 3;
        const expected = phase === 'capture' ? 10 : 11;
        const operations = Array.from({length: expected}, (_, n) => explicitStep(phase, `explicit-${n}`));
        if (phase === 'capture' && mode === 'untimed') delete operations[0].timing;
        return {pid: 123, code: 0, signal: null, wallNs: 10,
          stdout: [...operations,
            {phase, status: 'passed', firstFailedStep: null, workObservation: work,
              firstClose: {attempted: true, returned: true}}].map(value => JSON.stringify(value)).join('\n')};
      }}), {code: 'ERR_ASSERTION'});
    assert.deepEqual(phases, ['missing', 'lost', 'untimed'].includes(mode) ? ['capture'] : ['capture', 'approve']);
  }
});

test('required README aggregate refuses the old capture count before dependent phases', async t => {
  const {root, consumer} = await scratch(t), phases = [];
  await assert.rejects(mockWorkflowMetrics({prepared: {consumer}, root, repository,
    counts: {coldSamples: 1}, onMetric() {},
    async command(_executable, args) {
      const phase = args[1]; phases.push(phase);
      return {pid: 10000, code: 0, signal: null, wallNs: 100,
        stdout: [...Array.from({length: 9}, (_, n) => explicitStep(phase, `old-${n}`)),
          {phase, status: 'passed', firstFailedStep: null}].map(value => JSON.stringify(value)).join('\n')};
    }}), {code: 'ERR_ASSERTION'});
  assert.deepEqual(phases, ['capture']);
  const record = JSON.parse(await readFile(join(root,
    'mock-project-churn-risk-mock-readme-0/capture.observation.json'), 'utf8'));
  assert.equal(record.completed, false); assert.equal(record.exitCode, 0);
  assert.equal(record.expectedAssertions, 10);
});

test('failed README command retains original exit primary and first-close failure before assertions', async t => {
  const {root, consumer} = await scratch(t);
  const primary = Object.assign(new Error('Original workflow refusal'), {commandResult: {
    pid: 10000, code: 1, signal: null, wallNs: 100,
    stdout: JSON.stringify({phase: 'capture', status: 'failed', firstFailedStep: 'wait',
      code: 'OriginalRefusal', cleanupCode: 'ClientCleanupPending',
      firstClose: {attempted: true, returned: false},
      runObservation: {available: true, status: 'failed', terminalCode: 'OriginalRunRefusal'}})}});
  const observed = [];
  await assert.rejects(mockWorkflowMetrics({prepared: {consumer}, root, repository,
    counts: {coldSamples: 1}, onMetric: value => observed.push(value), command: async () => {throw primary;}}),
  error => error === primary);
  const actual = JSON.parse(await readFile(join(root,
    'mock-project-churn-risk-mock-readme-0/capture.observation.json'), 'utf8'));
  assert.equal(actual.completed, false); assert.equal(actual.exitCode, 1);
  assert.equal(actual.summary.code, 'OriginalRefusal'); assert.equal(actual.summary.cleanupCode, 'ClientCleanupPending');
  assert.deepEqual(actual.summary.firstClose, {attempted: true, returned: false});
  assert.deepEqual(actual.summary.runObservation,
    {available: true, status: 'failed', terminalCode: 'OriginalRunRefusal'});
  assert.equal(observed[0].samples[0].verified, false);
  assert.equal(observed[0].samples[0].phases.length, 1);
});

async function collectionBudgetPorts() {
  const source = await readFile(new URL('./fixtures/packed-result-collection.mjs', import.meta.url), 'utf8');
  const tree = parseJavaScript(source, {ecmaVersion: 'latest', sourceType: 'module'});
  const load = name => {
    const node = tree.body.find(value => value.type === 'FunctionDeclaration' && value.id.name === name);
    assert(node);
    return Function('assert', `return (${source.slice(node.start, node.end)});`)(assert);
  };
  const body = tree.body.find(value => value.type === 'TryStatement').block;
  // Execute the actual fixture with explicit public/diagnostic ports, not a
  // substitute Core, Ledger, installed acceptance, or successful budget run.
  return {project: load('originalBudgetRefusal'), program: load('collectionProgram'), budgetProgram: load('oversizedRowProgram'),
    run: Function('ports', `return (async () => {
      const {assert,report,span,open,phase,stateDir,capacityObservations,
        originalBudgetRefusal,getSubmissionOutcome,getSubmissionInput,getSubmissionAttempt,
        collectionProgram,oversizedRowProgram,save}=ports;
      let client; ${source.slice(body.start, body.end)}; return client;
    })();`)};
}

test('normal budget evidence requires the original pre-send snapshot and exact exceeded Core quantities', async () => {
  const {project} = await collectionBudgetPorts();
  const memory = {retainedBytes: 32768, executionBytes: 32768};
  const outcome = {};
  const fact = {phase: 'request_snapshot', dimension: 'retention', requiredRetentionBytes: '131072',
    requiredExecutionBytes: '65536', availableRetentionBytes: '32768', availableExecutionBytes: '32768'};
  assert.equal(project([fact], outcome, memory).verified, true);
  assert.equal(project([{...fact, dimension: 'retention', requiredRetentionBytes: '9223372036854775807'}],
    outcome, memory).requiredRetentionBytes, '9223372036854775807');
  for (const [observed, publicOutcome] of [
    [[], outcome], [[fact, fact], outcome], [[fact], undefined],
    [[fact], {outcome: {kind: 'not_accepted'}}],
    [[fact], {input: {original: true}}],
    [[fact], {attempt: {kind: 'refused'}}],
    [[{...fact, token: 'not-a-diagnostic-field'}], outcome],
    [[{...fact, phase: 'initialization'}], outcome],
    [[{...fact, phase: 'source_free_plan'}], outcome],
    [[{...fact, requiredRetentionBytes: '32768'}], outcome],
    [[{...fact, dimension: 'execution'}], outcome],
    [[{...fact, availableExecutionBytes: '32769'}], outcome],
    ...['-1', '+1', '01', '9223372036854775808', 703186240].map(value =>
      [[{...fact, requiredExecutionBytes: value}], outcome]),
  ]) assert.throws(() => project(observed, publicOutcome, memory));
});

test('normal budget fixture submits once and keeps unrelated public failure as primary', async () => {
  const {project, budgetProgram, run} = await collectionBudgetPorts();
  for (const mode of ['exact', 'no-diagnostic', 'unrelated', 'unexpected-run']) {
    const report = {cases: [], submits: 0}, observations = [], saved = [];
    const primary = Object.assign(new Error('Actual public refusal'), {code: 'MoonBitHostFailure',
      capacity: {phase: 'request_snapshot'}}); // A lookalike error field is insufficient.
    let submissions = 0;
    const execute = () => run({assert, report, phase: 'budget', stateDir: '/fresh-own-budget',
      capacityObservations: observations, originalBudgetRefusal: project, oversizedRowProgram: budgetProgram,
      span: async (_name, action) => action(), save: async (path, value) => saved.push({path, value}),
      async open(options) {
        assert.equal(options.stateDir, '/fresh-own-budget');
        assert.deepEqual(options.installation.requestMemory, {retainedBytes: 32768, executionBytes: 32768});
        assert.deepEqual(Object.keys(options.installation.authorization), ['observe']);
        return {async startSource(text, selection) {
          submissions++; assert.equal(text, budgetProgram()); assert.deepEqual(selection, {format: 'sql'});
          if (mode === 'unexpected-run') return {ref: {original: true}};
          if (mode !== 'no-diagnostic') options.installation.authorization.observe('preparation_capacity_refused',
            {phase: 'request_snapshot', dimension: 'retention', requiredRetentionBytes: '131072',
              requiredExecutionBytes: '65536', availableRetentionBytes: '32768', availableExecutionBytes: '32768'});
          throw primary;
        }};
      },
      getSubmissionOutcome(value) {
        if (mode === 'unexpected-run') return {kind: 'ready'};
        assert.equal(value, primary); return mode === 'unrelated' ? {kind: 'not_accepted'} : undefined;
      }, getSubmissionInput: () => undefined, getSubmissionAttempt: () => undefined});
    if (mode === 'exact') {await execute(); assert.equal(report.budgetRefusal.verified, true);}
    else if (mode === 'unexpected-run') {
      await assert.rejects(execute, {code: 'ERR_ASSERTION'});
      assert.deepEqual(saved.at(-1), {path: 'budget-unexpected-ref-before-close.json', value: {original: true}});
      assert.equal(report.budgetDisposition, 'run_returned'); assert.equal(report.budgetRunTerminal, 'unobserved');
    } else {
      await assert.rejects(execute, error => error === primary);
      assert.equal(report.budgetRefusal, undefined); assert(report.budgetControlFailure);
    }
    assert.equal(submissions, 1); assert.equal(report.submits, 1);
    assert.deepEqual(saved[0], {path: 'budget-input-before-submit.json', value: {format: 'sql', document: budgetProgram()}});
  }
});

test('normal budget parent refuses missing evidence pending close or wrong selected memory', async t => {
  const {root} = await scratch(t), load = await runnerFunctions();
  const run = load('runCollectionPhase', {readFile, join, assert, process, nodeBenchmarkFailure});
  for (const mode of ['exact', 'missing', 'outcome', 'memory', 'close', 'fd']) {
    const actual = {phase: 'budget', pid: 12001, sourceFreeMaxWork: 30000000,
      requestMemory: {retainedBytes: 32768, executionBytes: 32768}, submits: 1,
      complete: true, firstClose: 'returned', aliveScopedFD: {before: 0, after: 0},
      cases: [{inputUtf8Bytes: 40017, expectedRefusal: 'request_snapshot', complete: true}],
      budgetDisposition: 'pre_send_capture', budgetInputPublished: false,
      budgetInput: {utf8Bytes: 40017, utf16Units: 40017, arrayElements: 20000, original: 'budget-input-before-submit.json'},
      budgetRefusal: {verified: true, phase: 'request_snapshot', outcome: 'pre_send_capture', classification: 'resource_limit',
        dimension: 'retention', requiredRetentionBytes: '131072', requiredExecutionBytes: '65536',
        availableRetentionBytes: '32768', availableExecutionBytes: '32768'}};
    if (mode === 'missing') delete actual.budgetRefusal;
    if (mode === 'outcome') actual.budgetRefusal.outcome = 'unknown';
    if (mode === 'memory') actual.requestMemory.executionBytes = 1073741824;
    if (mode === 'close') actual.firstClose = 'pending';
    if (mode === 'fd') actual.aliveScopedFD.after = 1;
    const record = {phase: 'budget', completed: false};
    const execute = () => run({collection: root, record, async command() {
      return {pid: 12001, code: 0, stdout: JSON.stringify(actual)};
    }});
    if (mode === 'exact') {await execute(); assert.equal(record.completed, true);}
    else {await assert.rejects(execute); assert.equal(record.completed, false);}
  }
});

test('packed collection persists Program-removal failure after FIRST close and never removes in Saved', async () => {
  // Execute the actual fixture finalizer with explicit filesystem/close ports.
  // This verifies failure recording, not installed Host or Run behavior.
  const source = await readFile(new URL('./fixtures/packed-result-collection.mjs', import.meta.url), 'utf8');
  const finalizer = parseJavaScript(source, {ecmaVersion: 'latest', sourceType: 'module'})
    .body.find(value => value.type === 'TryStatement').finalizer;
  const runFinalizer = Function('client', 'span', 'report', 'cleanup', 'failed', 'phase', 'programs',
    'unlink', 'save', 'observeRecordApprovalDescriptors', 'setTimeout', 'stateDir', 'assert',
    `return (async () => ${source.slice(finalizer.start, finalizer.end)})();`);
  for (const phase of ['budget', 'capture', 'saved']) {
    const events = [], cleanup = [], report = {firstClose: 'unobserved'}, observations = [];
    const failure = Object.assign(new Error('Original Program removal failed'), {code: 'EACCES'});
    await runFinalizer({async close() {events.push('FIRST-close');}},
      async (_name, action) => action(), report, cleanup, false, phase, ['first.sql', 'second.sql'],
      async path => {events.push(path); if (path === 'second.sql') throw failure;},
      async (path, value) => observations.push({path, value: structuredClone(value)}),
      async () => ({openPaths: []}), async () => {}, '/authored-test-state', assert);
    assert.equal(observations.length, 3);
    assert.equal(observations[0].path, `${phase}.pending.json`);
    assert.equal(observations[0].value.firstClose, 'pending');
    const final = observations.at(-1);
    assert.equal(final.path, `${phase}.observation.json`);
    assert.equal(final.value.firstClose, 'returned');
    assert.deepEqual(final.value.aliveScopedFD, {before: 0, after: 0});
    if (phase === 'capture') {
      assert.deepEqual(events, ['FIRST-close', 'first.sql', 'second.sql']);
      assert.equal(cleanup[0], failure); assert.equal(report.originalProgramsRemovedAfterFirstClose, 1);
      assert.equal(final.value.complete, false);
      assert.deepEqual(final.value.cleanup, [{name: 'Error', code: 'EACCES'}]);
    } else {
      assert.deepEqual(events, ['FIRST-close']); assert.deepEqual(cleanup, []);
      assert.equal(final.value.complete, true);
    }
  }
});

test('collection saves its original primary before pending close and diagnostic failure never masks it', async () => {
  const source = await readFile(new URL('./fixtures/packed-result-collection.mjs', import.meta.url), 'utf8');
  const finalizer = parseJavaScript(source, {ecmaVersion: 'latest', sourceType: 'module'})
    .body.find(value => value.type === 'TryStatement').finalizer;
  const invoke = Function('client', 'span', 'report', 'cleanup', 'failed', 'phase', 'programs',
    'unlink', 'save', 'observeRecordApprovalDescriptors', 'setTimeout', 'stateDir', 'assert', 'primary', 'console',
    `return (async () => {${source.slice(finalizer.start + 1, finalizer.end - 1)}
      ${source.slice(finalizer.end)}})();`);
  for (const writeFails of [false, true]) {
    const primary = Object.assign(new Error('OriginalWaitRefusal'), {code: 'OriginalWaitRefusal'});
    const report = {phase: 'capture', pid: 123, firstFailedStep: 'wait-100000',
      primary: {name: primary.name, code: primary.code}, submits: 4};
    const events = [], stored = [];
    let release, entered;
    const closing = new Promise(resolve => {release = resolve;});
    const started = new Promise(resolve => {entered = resolve;});
    const result = invoke({async close() {events.push('close'); entered(); await closing;}},
      async (_name, action) => action(), report, [], true, 'capture', [],
      async () => assert.fail('Failed capture cannot remove input'),
      async (path, value) => {
        events.push('save'); stored.push({path, value: structuredClone(value)});
        if (writeFails) throw Object.assign(new Error('DiagnosticWriteRefused'), {code: 'EACCES'});
      }, async () => ({openPaths: []}), async () => {}, '/authored-state', assert, primary, {log() {}});
    // Install rejection handling before releasing the controlled close.
    const rejected = assert.rejects(result, error => error === primary);
    await started;
    assert.deepEqual(events, ['save', 'close']);
    assert.equal(stored[0].value.firstClose, 'pending');
    assert.deepEqual(stored[0].value.primary, {name: primary.name, code: primary.code});
    assert.equal(stored[0].value.complete, false);
    release(); await rejected;
    assert.equal(report.firstClose, 'returned');
    assert.equal(report.diagnosticErrors.length, writeFails ? 3 : 0);
    assert.equal(report.complete, false);
  }
});

test('budget failure keeps delivered quantities and completed phase bounds before pending FIRST close', async () => {
  // Execute the original child body with explicit public/filesystem ports.
  // This checks evidence custody, not real Core admission or installed cleanup.
  const source = await readFile(new URL('./fixtures/packed-result-collection.mjs', import.meta.url), 'utf8');
  const first = parseJavaScript(source, {ecmaVersion: 'latest', sourceType: 'module'}).body
    .find(value => value.type !== 'ImportDeclaration');
  const invoke = Function('ports', `return (async () => {
    const {assert,readFile,writeFile,unlink,join,setTimeout,open,getSubmissionOutcome,getSubmissionInput,getSubmissionAttempt,
      observeRecordApprovalDescriptors,process,console}=ports;
    ${source.slice(first.start)}
  })();`);
  const fact = {phase: 'source_free_plan', dimension: 'execution', requiredRetentionBytes: '203770432',
    requiredExecutionBytes: '703186240', availableRetentionBytes: '536870912', availableExecutionBytes: '536870912'};
  for (const mode of ['unrelated-public-failure', 'unexpected-run']) {
    const stored = [], events = [];
    const primary = Object.assign(new Error('Actual unrelated public failure'), {code: 'ClientHostFailure'});
    let release, entered, submissions = 0;
    const closing = new Promise(resolve => {release = resolve;});
    const started = new Promise(resolve => {entered = resolve;});
    const result = invoke({assert,join,
      process: {argv: ['node', 'fixture', 'budget', '/fresh-own/handoff.json'],
        pid: 123, cwd: () => '/fresh-own', hrtime: process.hrtime, cpuUsage: process.cpuUsage},
      console: {log() {}}, readFile: () => assert.fail('No Saved or input read'),
      unlink: () => assert.fail('No failed input removal'), setTimeout: async () => {},
      observeRecordApprovalDescriptors: async () => ({openPaths: []}),
      async writeFile(path, bytes) {events.push(`save:${path}`); stored.push({path, value: JSON.parse(bytes)});},
      getSubmissionOutcome(value) {
        if (mode !== 'unexpected-run') assert.strictEqual(value, primary);
        return undefined;
      }, getSubmissionInput: () => undefined, getSubmissionAttempt: () => undefined,
      async open(options) {
        return {async startSource() {
          submissions++;
          if (mode === 'unexpected-run') return {ref: {original: true}};
          options.installation.authorization.observe('preparation_capacity_refused', fact);
          throw primary;
        }, async close() {events.push('FIRST-close'); entered(); await closing;}};
      }});
    const rejected = assert.rejects(result, error => mode === 'unexpected-run'
      ? error.code === 'ERR_ASSERTION' : error === primary);
    await started;
    const pending = stored.find(value => value.path === 'budget.pending.json').value;
    assert.equal(pending.firstClose, 'pending'); assert.equal(pending.complete, false);
    assert.equal(pending.submits, 1); assert.equal(submissions, 1);
    assert.deepEqual(pending.capacityObservations, mode === 'unexpected-run' ? [] : [fact]);
    assert.deepEqual(pending.phases.map(value => value.name), ['open', 'submit-budget-refusal']);
    assert(pending.phases.every(value => value.wallNs > 0 && value.endedAt !== undefined));
    assert.equal(pending.budgetRefusal, undefined, 'Delivered quantities alone never certify a refusal');
    assert.equal(pending.primary.code, mode === 'unexpected-run' ? 'ERR_ASSERTION' : primary.code);
    assert(events.indexOf('save:budget.pending.json') < events.indexOf('FIRST-close'));
    if (mode === 'unexpected-run') assert.deepEqual(stored.find(value => value.path === 'budget-unexpected-ref-before-close.json'),
      {path: 'budget-unexpected-ref-before-close.json', value: {original: true}});
    release(); await rejected;
    const final = stored.at(-1).value;
    assert.equal(final.firstClose, 'returned'); assert.equal(final.complete, false);
    assert.deepEqual(final.capacityObservations, pending.capacityObservations);
  }
});

test('collection full stream drains all 100k original rows and refuses truncation or changed rows', async () => {
  const source = await readFile(new URL('./fixtures/packed-result-collection.mjs', import.meta.url), 'utf8');
  const declaration = parseJavaScript(source, {ecmaVersion: 'latest', sourceType: 'module'})
    .body.find(value => value.type === 'FunctionDeclaration' && value.id.name === 'drainOriginalRows');
  assert(declaration);
  const drain = Function('assert', `return (${source.slice(declaration.start, declaration.end)});`)(assert);
  for (const [count, changed] of [[100000, false], [99999, false], [100000, true]]) {
    let delivered = 0, closed = 0, opened = 0;
    const result = {rows() {opened++;return (async function* () {
      try {
        for (let n = 0; n < count; n++) {delivered++;yield {n: changed && n === 59999 ? 1 : 0};}
      } finally {closed++;}
    })();}};
    if (count === 100000 && !changed) {
      assert.deepEqual(await drain(result, 100000), {rows: 100000, complete: true});
      assert.equal(delivered, 100000);
    } else await assert.rejects(drain(result, 100000), {code: 'ERR_ASSERTION'});
    assert.equal(opened, 1); assert.equal(closed, 1);
  }
});

test('collection operation intervals retain actual monotonic and own-child CPU bounds on success and failure', async () => {
  const source = await readFile(new URL('./fixtures/packed-result-collection.mjs', import.meta.url), 'utf8');
  const declaration = parseJavaScript(source, {ecmaVersion: 'latest', sourceType: 'module'}).body
    .filter(value => value.type === 'VariableDeclaration').flatMap(value => value.declarations)
    .find(value => value.id.name === 'span'); assert(declaration);
  const report = {phases: []};
  const span = Function('report', 'process', `return (${source.slice(declaration.init.start, declaration.init.end)});`)(report, process);
  const primary = new Error('OriginalPublicOperationFailed');
  let called = 0;
  assert.equal(await span('original-all', async () => {called++; return 100000;}), 100000);
  await assert.rejects(span('original-Saved', async () => {called++; throw primary;}), error => error === primary);
  assert.equal(called, 2); assert.equal(report.firstFailedStep, 'original-Saved');
  assert.equal(report.phases.length, 2);
  for (const timing of report.phases) {
    assert(timing.wallNs > 0 && Number.isSafeInteger(timing.wallNs));
    assert(Number.isSafeInteger(timing.cpuUserUs) && timing.cpuUserUs >= 0);
    assert(Number.isSafeInteger(timing.cpuSystemUs) && timing.cpuSystemUs >= 0);
    assert(Date.parse(timing.endedAt) >= Date.parse(timing.startedAt));
    assert(timing.scope.includes('inclusive') && timing.scope.includes('overhead'));
  }
});

async function runnerFunctions(relative = './test-packed-readme-workflows.mjs') {
  const url = new URL(relative, import.meta.url);
  const source = await readFile(url, 'utf8');
  const declarations = parseJavaScript(source, {ecmaVersion: 'latest', sourceType: 'module'}).body
    .map(value => value.type === 'ExportNamedDeclaration' ? value.declaration : value)
    .filter(value => value?.type === 'FunctionDeclaration');
  return (name, ports) => {
    const node = declarations.find(value => value.id.name === name);
    assert(node, `Missing actual runner ${name}`);
    // Retain the original module coordinate when compiling its actual function
    // with explicit test ports; Function itself has no import.meta binding.
    const body = source.slice(node.start, node.end).replaceAll('import.meta.url',
      JSON.stringify(url.href));
    return Function(...Object.keys(ports), `return (${body});`)(...Object.values(ports));
  };
}

test('collection aggregate requires completed full stream independently of successful all collection', async t => {
  const {root} = await scratch(t), load = await runnerFunctions();
  const run = load('runCollectionPhase', {readFile, join, assert, process, nodeBenchmarkFailure});
  const actual = {phase: 'capture', pid: 123, complete: true, firstClose: 'returned',
    aliveScopedFD: {before: 0, after: 0}, submits: 5, sourceFreeMaxWork: 30000000,
    requestMemory: {retainedBytes: 1073741824, executionBytes: 1073741824},
    cases: [9999, 10000, 10001, 100000].map(count => ({count})),
    fullStream: {rows: 100000, complete: true},
    controls: {tighterRows: true, collectionBytes: true, wireBytes: true, rowWireBytes: true,
      rowBytes: true, originalChargeBeforeValidation: true, boundedBatches: true,
      batchBytes: true, earlyBreak: true, readerCancellation: true},
    oversizedRow: {rows: 1, arrayElements: 20000, expectedRefusal: 'ResultRowRetainedLimit', complete: true},
    originalProgramsRemovedAfterFirstClose: 5};
  for (const fullStream of [actual.fullStream, undefined, {rows: 99999, complete: true}]) {
    const record = {phase: 'capture'};
    const promise = run({collection: root, record, async command() {
      return {pid: 123, code: 0, wallNs: 10, stdout: JSON.stringify({...actual, fullStream})};
    }});
    if (fullStream === actual.fullStream) {
      await promise; assert.equal(record.status, 'passed'); assert.equal(record.completed, true);
    } else {
      await assert.rejects(promise, {code: 'ERR_ASSERTION'});
      assert.equal(record.status, 'failed'); assert.notEqual(record.completed, true);
    }
  }
});

test('collection timeout retains only its actual child pending primary and never infers close return', async t => {
  const {root} = await scratch(t), load = await runnerFunctions();
  const run = load('runCollectionPhase', {readFile, join, assert, process, nodeBenchmarkFailure});
  const failure = Object.assign(new Error('Whole child timeout'), {commandResult:
    {pid: 123, code: null, signal: 'SIGTERM', wallNs: 10, stdout: ''}});
  const original = {phase: 'capture', pid: 123, primary: {code: 'OriginalWaitRefusal'},
    firstClose: 'pending', complete: false};
  for (const partial of [original, {...original, pid: 456}, {...original, phase: 'saved'}]) {
    await writeFile(join(root, 'capture.pending.json'), JSON.stringify(partial));
    const record = {phase: 'capture'};
    await assert.rejects(run({collection: root, record, command: async () => {throw failure;}}),
      error => error === failure);
    assert.equal(record.status, 'failed'); assert.equal(record.completed, undefined);
    if (partial === original) {
      assert.deepEqual(record.partialObservation, original);
      assert.equal(record.partialObservation.firstClose, 'pending');
    } else {
      assert.equal(record.partialObservation, undefined); assert(record.partialObservationUnavailable);
    }
  }
});

test('README timeout retains the same child primary while close is still unconfirmed', async t => {
  for (const pid of [123, 456]) {
    const {root, consumer} = await scratch(t);
    const failure = Object.assign(new Error('Whole child timeout'), {commandResult:
      {pid: 123, code: null, signal: 'SIGTERM', wallNs: 10, stdout: ''}});
    let metric;
    await assert.rejects(mockWorkflowMetrics({prepared: {consumer}, root, repository,
      counts: {coldSamples: 1}, onMetric: value => {metric = value;},
      async command(_command, _args, options) {
        assert.equal(options.timeout, 30000);
        await writeFile(join(options.cwd, 'capture.pending.json'), JSON.stringify({phase: 'capture', pid,
          code: 'OriginalWaitRefusal', firstFailedStep: 'wait for original Checkpoint',
          firstClose: {attempted: true, returned: false, state: 'pending'}}));
        throw failure;
      }}), error => error === failure);
    const record = metric.samples[0].phases[0];
    assert.equal(record.completed, false);
    if (pid === 123) {
      assert.equal(record.partialObservation.code, 'OriginalWaitRefusal');
      assert.equal(record.partialObservation.firstClose.returned, false);
      assert.equal(record.partialObservation.firstClose.state, 'pending');
    } else {
      assert.equal(record.partialObservation, undefined); assert(record.partialObservationUnavailable);
    }
  }
});

test('independent normal consumers continue after collection and variant failure and retain all original errors', async t => {
  // Exercise the actual orchestration with explicit package and command ports;
  // these synthetic outcomes do not qualify product or installed execution.
  const {root, consumer} = await scratch(t), output = join(root, 'out'), calls = [];
  const load = await runnerFunctions();
  const collectionFailure = new Error('Original collection failure'), variantFailure = new Error('Original churn failure');
  const cleanupFailure = new Error('Original alias cleanup failure');
  const verifyNodeBenchmarkPackages = async () => {};
  const runReadmeCases = load('runReadmeCases', {verifyNodeBenchmarkPackages, assert, writeFile, join,
    nodeBenchmarkFailure, async mockWorkflowMetrics({template, variant, onMetric}) {
      calls.push({template, variant});
      const failed = template === 'churn-risk-mock';
      await onMetric({samples: [{completed: !failed, verified: !failed}]});
      if (failed) throw variantFailure;
    }});
  const before = {clean: true, revision: 'a'.repeat(40)};
  const run = load('runPackedReadmeWorkflows', {assert, isAbsolute: value => value.startsWith('/'),
    process: {env: {ACTQL_PACKED_CLIENT_PACKAGES: '/authored-normal-input'}, version: 'explicit-test',
      platform: 'explicit-test', arch: 'explicit-test'}, fileURLToPath: () => repository,
    URL, checkoutState: () => before, execFileSync: () => 'b'.repeat(40), mkdir, join, writeFile,
    packedReadmeCases, packedCompositionCases, packedEffectControlCases,
    runMockEffectControls: async ({records}) => records.forEach(record => {record.completed = true; record.status = 'passed';}),
    nodeBenchmarkFailure, execute: async () => assert.fail('No product command'),
    prepareHealthPackages: async () => ({consumer, manifest: {}, manifestPath: '/authored-manifest'}),
    runCollectionConsumer: async ({report, cleanup}) => {
      report.collection.find(value => value.phase === 'capture').status = 'failed';
      cleanup.push(cleanupFailure); throw collectionFailure;
    }, runReadmeCases, verifyNodeBenchmarkPackages});
  await assert.rejects(run(output), error => {
    assert(error instanceof AggregateError); assert.equal(error.cause, collectionFailure);
    assert.deepEqual(error.errors, [collectionFailure, variantFailure, cleanupFailure]); return true;
  });
  assert.deepEqual(calls, [...packedReadmeCases, ...packedCompositionCases]);
  const report = JSON.parse(await readFile(join(output, 'summary.json'), 'utf8'));
  assert.equal(report.complete, false);
  assert.deepEqual(report.cases.map(value => value.status), ['failed', 'passed', 'passed']);
  assert.deepEqual(report.compositions.map(value => value.status), ['passed']);
  const saved = report.collection.find(value => value.phase === 'saved');
  assert.equal(saved.status, 'unexecuted');
  assert.match(saved.unexecutedReason, /completed original 100000 Result/u);
  assert.equal(report.failures.length, 2); assert.equal(report.cleanup.length, 1);
});

test('required mixed Model Whole is distinct from README three and cannot pass failed or unexecuted', async t => {
  assert.equal(packedReadmeCases.length, 3);
  assert.deepEqual(packedCompositionCases, [{template: 'deal-review-mock', variant: 'two-models-whole'}]);
  assert(!packedReadmeCases.some(value => value.variant === 'two-models-whole'));
  for (const mode of ['passed', 'failed', 'unexecuted']) {
    const {root, consumer} = await scratch(t), output = join(root, 'out'), load = await runnerFunctions(), calls = [];
    const failure = new Error('OriginalMixedCompositionFailed'), prepared = {consumer, manifest: {}, manifestPath: '/exact-original'};
    const verifyNodeBenchmarkPackages = async (manifest, manifestPath, actual) => {
      assert.strictEqual(manifest, prepared.manifest); assert.equal(manifestPath, prepared.manifestPath);
      assert.equal(actual, consumer);
    };
    const runCases = load('runReadmeCases', {verifyNodeBenchmarkPackages, assert, writeFile, join,
      nodeBenchmarkFailure, async mockWorkflowMetrics({template, variant, onMetric, prepared: actual}) {
        assert.strictEqual(actual, prepared); calls.push({template, variant});
        const failed = mode === 'failed' && variant === 'two-models-whole';
        await onMetric({samples: [{completed: !failed, verified: !failed}]});
        if (failed) throw failure;
      }});
    const before = {clean: true, revision: 'a'.repeat(40)};
    const run = load('runPackedReadmeWorkflows', {assert, isAbsolute: value => value.startsWith('/'),
      process: {env: {ACTQL_PACKED_CLIENT_PACKAGES: '/authored-original'}, version: 'explicit-test',
        platform: 'explicit-test', arch: 'explicit-test'}, fileURLToPath: () => repository,
      URL, checkoutState: () => before, execFileSync: () => 'b'.repeat(40), mkdir, join, writeFile,
      packedReadmeCases, packedCompositionCases, packedEffectControlCases,
      runMockEffectControls: async ({records}) => records.forEach(record => {record.completed = true; record.status = 'passed';}),
      nodeBenchmarkFailure,
      execute: async () => assert.fail('No product command'), prepareHealthPackages: async () => prepared,
      runCollectionConsumer: async ({report}) => report.collection.forEach(row => {row.completed = true; row.status = 'passed';}),
      runReadmeCases: async options => {
        if (mode === 'unexecuted' && options.cases === options.report.compositions) return;
        await runCases(options);
      }, verifyNodeBenchmarkPackages});
    if (mode === 'passed') assert.equal((await run(output)).complete, true);
    else await assert.rejects(run(output), error => mode === 'failed' ? error === failure : error.code === 'ERR_ASSERTION');
    assert.deepEqual(calls, mode === 'unexecuted' ? packedReadmeCases : [...packedReadmeCases, ...packedCompositionCases]);
    const report = JSON.parse(await readFile(join(output, 'summary.json'), 'utf8'));
    assert.equal(report.complete, mode === 'passed');
    assert.equal(report.compositions[0].status, mode);
    assert(report.cases.every(value => value.completed));
  }
});

test('required normal install enables lifecycle explicitly and preserves original install failure', async t => {
  const {root} = await scratch(t);
  const source = await readFile(new URL('./health-monitor-adapters.mjs', import.meta.url), 'utf8');
  const node = parseJavaScript(source, {ecmaVersion: 'latest', sourceType: 'module'}).body
    .find(value => value.type === 'ExportNamedDeclaration' && value.declaration?.id?.name === 'prepareHealthPackages').declaration;
  const names = ['client-wire', 'sdk', 'run-host-core', 'local-node', 'node'];
  const manifest = {sourceSha: 'a'.repeat(40), packages: names.map(name =>
    ({name: '@actql/' + name, file: name + '.tgz'}))};
  const retained = join(root, 'original-manifest.json');
  await writeFile(retained, JSON.stringify(manifest));
  let verified = 0;
  // Exercise actual argument/routing code with an explicit verifier port.
  // No package bytes, npm execution or installation acceptance is fabricated.
  const prepare = Function('assert', 'mkdir', 'join', 'lstat', 'readFile', 'writeFile', 'CLIENT_PACKAGES',
    'resolve', 'dirname', 'verifyNodeBenchmarkPackages', `return (${source.slice(node.start, node.end)});`)(
    assert, mkdir, join, async () => ({isDirectory: () => false}), readFile, writeFile, names,
    value => value, dirname, async () => {verified++;});
  for (const mode of [undefined, false, true, 'install-failed']) {
    const directory = join(root, 'install-' + String(mode)); await mkdir(directory);
    const primary = new Error('Original lifecycle failure'), calls = [], before = verified;
    const execute = () => prepare({repository, root: directory, source: {sha: manifest.sourceSha, dirty: false},
      retained, ...(mode === undefined ? {} : {normalLifecycle: mode === 'install-failed' ? true : mode}),
      async command(command, args, options) {
        calls.push({command, args, options});
        if (mode === 'install-failed') throw primary;
      }});
    if (mode === 'install-failed') {
      await assert.rejects(execute, error => error === primary);
      assert.equal(verified, before, 'Never qualify a failed lifecycle install');
    } else {await execute(); assert.equal(verified, before + 1);}
    assert.equal(calls.length, 1); assert.equal(calls[0].command, 'npm');
    assert.deepEqual(calls[0].args.slice(0, 3), ['install', '--offline',
      mode === true || mode === 'install-failed' ? '--ignore-scripts=false' : '--ignore-scripts']);
    assert.equal(calls[0].args.filter(arg => arg.startsWith('--ignore-scripts')).length, 1);
    assert.equal(calls[0].options.name, 'install-node');
  }
});

test('failed shared package preparation records every dependent as unexecuted and runs no consumer', async t => {
  const {root} = await scratch(t), output = join(root, 'out'), load = await runnerFunctions();
  const failure = new Error('Original normal package mismatch'), before = {clean: true, revision: 'a'.repeat(40)};
  const run = load('runPackedReadmeWorkflows', {assert, isAbsolute: value => value.startsWith('/'),
    process: {env: {ACTQL_PACKED_CLIENT_PACKAGES: '/authored-normal-input'}, version: 'explicit-test',
      platform: 'explicit-test', arch: 'explicit-test'}, fileURLToPath: () => repository, URL,
    checkoutState: () => before, execFileSync: () => 'b'.repeat(40), mkdir, join, writeFile,
    packedReadmeCases, packedCompositionCases, packedEffectControlCases,
    runMockEffectControls: async ({records}) => records.forEach(record => {record.completed = true; record.status = 'passed';}),
    nodeBenchmarkFailure, execute: async () => assert.fail('No product command'),
    prepareHealthPackages: async options => {assert.equal(options.normalLifecycle, true); throw failure;},
    runCollectionConsumer: async () => assert.fail('No collection with failed shared input'),
    runReadmeCases: async () => assert.fail('No README with failed shared input'),
    verifyNodeBenchmarkPackages: async () => assert.fail('No successful prepared input')});
  await assert.rejects(run(output), error => error === failure);
  const report = JSON.parse(await readFile(join(output, 'summary.json'), 'utf8'));
  assert.deepEqual(report.collection.map(value => value.phase), ['budget', 'capture', 'saved']);
  assert.equal(report.complete, false);
  assert([...report.collection, ...report.cases, ...report.compositions, ...report.controls].every(value =>
    value.status === 'unexecuted' && value.completed === false && value.unexecutedReason));
  assert.equal(report.failures.length, 1);
});

test('failed collection capture never runs its dependent Saved and returns its exact software alias', async t => {
  const {root, consumer} = await scratch(t), load = await runnerFunctions(), commands = [];
  const failure = Object.assign(new Error('Original capture failure'), {commandResult:
    {pid: 123, code: 1, signal: null, wallNs: 10, stdout: ''}});
  const report = {collection: ['capture', 'saved'].map(phase =>
    ({phase, completed: false, status: 'unexecuted'}))}, cleanup = [];
  const runCollectionPhase = load('runCollectionPhase', {readFile, join, assert, process, nodeBenchmarkFailure});
  const completedCollectionCapture = load('completedCollectionCapture', {readFile, join, assert});
  const run = load('runCollectionConsumer', {join, dirname, mkdir, copyFile, writeFile,
    symlink, unlink, readlink, assert, process, nodeBenchmarkFailure, runCollectionPhase, completedCollectionCapture});
  await assert.rejects(run({prepared: {consumer}, root, repository, report, cleanup,
    async command(_executable, _args, options) {commands.push(options.name); throw failure;}}),
  error => error === failure);
  assert.deepEqual(commands, ['collection-capture']); assert.deepEqual(cleanup, []);
  assert.equal(report.collection[0].status, 'failed'); assert.equal(report.collection[0].exitCode, 1);
  assert.equal(report.collection[1].status, 'unexecuted');
  assert(!(await readdir(join(root, 'collection'))).includes('node_modules'));
});

test('required Native counter stays case-scoped and nonzero through the original dispatcher', async () => {
  const source = await readFile(new URL('./test-native-core.mjs', import.meta.url), 'utf8');
  const tree = parseJavaScript(source, {ecmaVersion: 'latest', sourceType: 'module'});
  const file = 'src/cmd/native_client/local_project_mock_physical_scoped_wbtest.mbt';
  const matches = [];
  function visit(node, parent) {
    if (node === null || typeof node !== 'object') return;
    if (node.type === 'CallExpression' && node.callee.name === 'spawnSync') {
      const environment = node.arguments[2]?.properties?.find(value => value.key?.name === 'env')?.value;
      const selected = environment?.properties?.find(value => value.type === 'SpreadElement' &&
        value.argument.type === 'CallExpression' &&
        value.argument.callee.name === 'nativeCoreScopedTestEnvironment');
      if (selected) matches.push({node, parent, selected});
    }
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(child => visit(child, node));
      else if (value && typeof value === 'object') visit(value, node);
    }
  }
  visit(tree, null); assert.equal(matches.length, 1);
  const {node, parent, selected} = matches[0];
  assert.equal(parent.callee.name, 'checkChild');
  assert(tree.body.some(value => value.type === 'ImportDeclaration' &&
    value.source.value === './native-core-test-selection.mjs' && value.specifiers.some(specifier =>
      specifier.imported?.name === 'nativeCoreScopedTestEnvironment' &&
      specifier.local.name === 'nativeCoreScopedTestEnvironment')));
  assert.equal(selected.argument.arguments.length, 1);
  assert.equal(selected.argument.arguments[0].type, 'Identifier');
  assert.equal(selected.argument.arguments[0].name, 'test');
  const environment = nativeCoreScopedTestEnvironment;
  assert.deepEqual(environment({source: file, index: 13}), {ACTQL_NATIVE_TIMINGS: '1'});
  for (const test of [{source: file, index: 12}, {source: file, index: 14},
    {source: 'src/platform_native/client_host/another.mbt', index: 13}]) {
    assert.deepEqual(environment(test), {});
  }
  const command = source.slice(node.start, node.end);
  assert(command.includes("runFocusedTests('moon'"));
  assert(command.includes('expectedTests: 1'));
  assert(gateJobs.includes('native')); assert(workflow.jobs.check.needs.includes('native'));
  assert.equal(workflow.jobs.native.env?.ACTQL_NATIVE_TIMINGS, undefined);
  assert(workflow.jobs.native.steps.every(step => step.env?.ACTQL_NATIVE_TIMINGS === undefined));
});


test('completed original collection Saved is independent of a later capture case failure', async t => {
  const {root, consumer} = await scratch(t), load = await runnerFunctions(), commands = [];
  const original = {ref: {nonce: 'authored-reference'}, resultName: 'actual-sole-result', count: 100000};
  const capture = {phase: 'capture', pid: 123, complete: false, firstClose: 'returned',
    aliveScopedFD: {before: 0, after: 0}, cleanup: [], cases: [{...original, complete: true}]};
  const failure = Object.assign(new Error('Later oversized case refused'), {commandResult:
    {pid: 123, code: 1, signal: null, wallNs: 10, stdout: ''}});
  const report = {collection: ['capture', 'saved'].map(phase =>
    ({phase, completed: false, status: 'unexecuted'}))}, cleanup = [];
  const runCollectionPhase = load('runCollectionPhase', {readFile, join, assert, process, nodeBenchmarkFailure});
  const completedCollectionCapture = load('completedCollectionCapture', {readFile, join, assert});
  const run = load('runCollectionConsumer', {join, dirname, mkdir, copyFile, writeFile,
    symlink, unlink, readlink, assert, process, nodeBenchmarkFailure, runCollectionPhase, completedCollectionCapture});
  await assert.rejects(run({prepared: {consumer}, root, repository, report, cleanup,
    async command(_executable, args, options) {
      assert.equal(options.timeout, 120000); commands.push(args[1]);
      if (args[1] === 'capture') {
        await writeFile(join(options.cwd, 'capture.observation.json'), JSON.stringify(capture));
        await writeFile(join(options.cwd, 'original.json'), JSON.stringify(original));
        throw failure;
      }
      assert.equal(args[1], 'saved');
      return {pid: 456, code: 0, signal: null, wallNs: 10, stdout: JSON.stringify({phase: 'saved',
        pid: 456, complete: true, firstClose: 'returned', aliveScopedFD: {before: 0, after: 0},
        submits: 0, sourceFreeMaxWork: 30000000,
        requestMemory: {retainedBytes: 1073741824, executionBytes: 1073741824},
        cases: [{count: 100000, complete: true}]})};
    }}), error => error === failure);
  assert.deepEqual(commands, ['capture', 'saved']);
  assert.equal(report.collection[0].status, 'failed'); assert.equal(report.collection[0].completed, false);
  assert.equal(report.collection[1].status, 'passed'); assert.equal(report.collection[1].completed, true);
  assert.deepEqual(cleanup, []);
  assert(!(await readdir(join(root, 'collection'))).includes('node_modules'));
  const collection = join(root, 'collection');
  assert(await completedCollectionCapture(collection, 123));
  for (const changed of [{...capture, firstClose: 'threw'}, {...capture, cleanup: [{code: 'pending'}]},
    {...capture, aliveScopedFD: {before: 1, after: 1}}, {...capture, cases: []}]) {
    await writeFile(join(collection, 'capture.observation.json'), JSON.stringify(changed));
    assert.equal(await completedCollectionCapture(collection, 123), false);
  }
  await writeFile(join(collection, 'capture.observation.json'), JSON.stringify(capture));
  await writeFile(join(collection, 'original.json'), JSON.stringify({...original, ref: {nonce: 'foreign'}}));
  assert.equal(await completedCollectionCapture(collection, 123), false);
});


test('small policy and oracle units run during Draft while normal required gates remain intact', () => {
  const steps = workflow.jobs.lint.steps;
  for (const name of ['Test collection budget and required packed README selection',
    'Test ordinary operation performance policy oracles', 'Test plain-init Native numeric result and refusal oracles']) {
    const step = steps.find(value => value.name === name); assert(step); assert.equal(step.if, undefined);
  }
  const collection = steps.find(value => value.name === 'Test collection budget and required packed README selection');
  for (const file of ['local-result-read-policy', 'client-result-collection-policy', 'request-memory-policy'])
    assert(collection.run.includes(`adapters/host-node/${file}.test.mjs`));
  const policy = steps.find(value => value.name === 'Test ordinary operation performance policy oracles');
  const rest = steps.find(value => value.name === 'Test ordinary operation performance assessment');
  assert(rest.if.includes('draft'));
  for (const file of ['scripts/operation-performance.test.mjs', 'scripts/benchmark-node-operations.test.mjs',
    'scripts/operation-performance-policy.test.mjs', 'scripts/operation-performance-native-control.test.mjs',
    'scripts/benchmark-node-process-operations.test.mjs', 'scripts/benchmark-node-sqlite.test.mjs',
    'scripts/benchmark-node-boundaries.test.mjs', 'scripts/node-operation-fs-trace.test.mjs',
    'scripts/operation-performance-priority-transition.test.mjs', 'scripts/operation-performance-transition-ci.test.mjs',
    'scripts/native-approval-performance.test.mjs']) {
    const occurrences = [...policy.run.split(/\s+/u), ...rest.run.split(/\s+/u)].filter(value => value === file);
    assert.equal(occurrences.length, 1, file);
  }
  assert(gateJobs.includes('client-readme-packed')); assert.deepEqual(workflow.jobs.check.needs, gateJobs);
});

test('small original Model failure and preclose units run once in Draft lint without a runtime supplier', () => {
  const files = ['adapters/host-node/infer-model-effect-control.test.mjs',
    'adapters/host-node/acquired-effect-unknown-primary.test.mjs',
    'adapters/host-node/mock-project-effect-public.test.mjs',
    'adapters/host-common/observation.test.mjs'];
  const step = workflow.jobs.lint.steps.find(value => value.name === 'Test original Model failure and workflow observation');
  assert(step, 'The actual small original failure cases must have a CI caller');
  assert.equal(step.if, undefined);
  assert(!workflow.jobs.lint.if.includes('draft'));
  assert.equal(step.run, `node --test ${files.join(' ')}`);
  const commands = Object.values(workflow.jobs).flatMap(value => value.steps ?? [])
    .flatMap(value => (value.run ?? '').split(/\s+/u));
  for (const file of files) assert.equal(commands.filter(value => value === file).length, 1, file);
  assert(!/moon |npm (?:pack|run)|build-runtime/u.test(step.run));
  assert(gateJobs.includes('client-readme-packed'));
  assert.deepEqual(workflow.jobs.check.needs, gateJobs);
});

// Command-port evidence below checks driver selection and refusal of incomplete
// outcomes. It does not stand in for installed constructors or normal controls.
const explicitEffectControl = (mode, pid = 7000) => ({mode, pid, status: 'passed', originalRun: true,
  targetUnchanged: true, firstClose: {attempted: true, returned: true}, aliveScopedFD: {before: 0, after: 0},
  workObservation: {complete: true, sourceAcquisitionStarts: 0, modelCallStarts: 0, effectReplacementReturns: 0},
  ...(mode === 'approve-deny' ? {runStatus: 'waiting_checkpoint',
    refusal: {code: 'ExecutionAuthorizationDenied', action: 'deny', operation: 'sign'}}
    : {cancellationKind: 'accepted', runStatus: 'cancelled', physicalStop: 'confirmed', resultAvailable: false})});

test('normal Effect controls require original current refusals, zero actual writes and FIRST close', () => {
  assert.deepEqual(packedEffectControlCases, ['approve-deny', 'paused-cancel']);
  for (const mode of packedEffectControlCases) {
    assertMockEffectControlOutcome(explicitEffectControl(mode), mode, 7000);
    for (const mutate of [value => value.workObservation.complete = false,
      value => value.workObservation.effectReplacementReturns++, value => value.workObservation.modelCallStarts++,
      value => value.workObservation.sourceAcquisitionStarts++, value => value.targetUnchanged = false,
      value => value.firstClose.returned = false, value => value.aliveScopedFD.after++,
      value => value.originalRun = false, value => value.status = 'unknown', value => value.pid++]) {
      const value = explicitEffectControl(mode); mutate(value);
      assert.throws(() => assertMockEffectControlOutcome(value, mode, 7000));
    }
  }
  const deny = explicitEffectControl('approve-deny'); deny.refusal.operation = 'write';
  assert.throws(() => assertMockEffectControlOutcome(deny, deny.mode, deny.pid));
});

test('normal Effect driver selects each fresh two-Model capture and public control exactly once', async t => {
  const {root, consumer} = await scratch(t), load = await runnerFunctions('./packed-mock-effect-controls.mjs');
  const prepared = {consumer, manifest: {}, manifestPath: '/exact-unchanged-normal-input'}, calls = [];
  const workflowSource = await readFile(join(repository, 'adapters/host-node/fixtures/mock-project-effect-public.mjs'), 'utf8');
  const run = load('runControl', {assert, mkdir, writeFile, readFile, copyFile, symlink, readlink, unlink, join, dirname,
    twoModelDealReviewFiles, packedEffectControlCases, assertMockEffectControlOutcome, process, nodeBenchmarkFailure,
    verifyNodeBenchmarkPackages: async (...args) => assert.deepEqual(args, [prepared.manifest, prepared.manifestPath, consumer])});
  for (const mode of packedEffectControlCases) {
    const record = {mode, phases: []};
    await run({prepared, root, repository, record, async command(_exe, args, options) {
      assert.equal(options.timeout, 30000);
      assert.equal(await readlink(join(options.cwd, 'node_modules')), join(consumer, 'node_modules'));
      const capture = args[1] === 'capture'; calls.push([mode, capture ? 'capture' : 'control']);
      assert.equal((await readFile(join(options.cwd, 'capture-original.mjs'), 'utf8')), workflowSource);
      if (capture) {
        assert.deepEqual(args.slice(1), ['capture', join(options.cwd, 'handoff.json'), 'deal-review-mock', 'two-models']);
        assert.equal(JSON.parse(await readFile(join(options.cwd, 'model-tasks.json'), 'utf8')).tasks['model-task:deal-review-confirm.v1'],
          './model-tasks/deal-review-confirm.v1.yaml');
      } else assert.deepEqual(args.slice(1), [join(options.cwd, 'handoff.json'), mode]);
      const rows = capture ? [...Array.from({length: 10}, (_, i) => explicitStep('capture', String(i))),
        {phase: 'capture', status: 'passed', firstFailedStep: null, firstClose: {attempted: true, returned: true},
          workObservation: explicitWork('capture', 'two-models')},
        {phase: 'capture', event: 'after-first-close', pid: 7000, aliveScopedFD: {after: 0}}]
        : [explicitEffectControl(mode)];
      return {pid: 7000, code: 0, signal: null, stdout: rows.map(value => JSON.stringify(value)).join('\n')};
    }});
    assert(record.phases.every(phase => phase.completed));
    await assert.rejects(readlink(join(root, `mock-effect-control-${mode}`, 'node_modules')), {code: 'ENOENT'});
  }
  assert.deepEqual(calls, packedEffectControlCases.flatMap(mode => [[mode, 'capture'], [mode, 'control']]));
});

test('normal Effect driver retains failed capture and does not dispatch its public action', async t => {
  const {root, consumer} = await scratch(t), load = await runnerFunctions('./packed-mock-effect-controls.mjs');
  const failure = new Error('Original captured Run failed'), record = {mode: 'paused-cancel', phases: []};
  const run = load('runControl', {assert, mkdir, writeFile, readFile, copyFile, symlink, readlink, unlink, join, dirname,
    twoModelDealReviewFiles, packedEffectControlCases, assertMockEffectControlOutcome, process, nodeBenchmarkFailure,
    verifyNodeBenchmarkPackages: async () => {}});
  let calls = 0;
  await assert.rejects(run({prepared: {consumer}, root, repository, record, async command(_exe, args) {
    calls++; assert.equal(args[1], 'capture'); throw failure;
  }}), error => error === failure);
  assert.equal(calls, 1); assert.equal(record.phases.length, 1); assert.equal(record.phases[0].completed, false);
  await assert.rejects(readlink(join(root, 'mock-effect-control-paused-cancel', 'node_modules')), {code: 'ENOENT'});
});

test('required normal controls preserve original errors and cannot pass an unexecuted control', async t => {
  const load = await runnerFunctions('./packed-mock-effect-controls.mjs'), failure = new Error('Original denial unknown');
  const records = packedEffectControlCases.map(mode => ({mode, completed: false, status: 'unexecuted'})), failures = [];
  const run = load('runMockEffectControls', {assert, packedEffectControlCases, nodeBenchmarkFailure,
    runControl: async ({record}) => {if (record.mode === 'approve-deny') throw failure;}});
  await run({records, failures});
  assert.deepEqual(failures, [failure]); assert.deepEqual(records.map(value => value.status), ['failed', 'passed']);
  assert.equal(records[0].completed, false);
  const {root, consumer} = await scratch(t), output = join(root, 'out'), runner = await runnerFunctions();
  const before = {clean: true, revision: 'a'.repeat(40)};
  const execute = runner('runPackedReadmeWorkflows', {assert, isAbsolute: value => value.startsWith('/'),
    process: {env: {ACTQL_PACKED_CLIENT_PACKAGES: '/normal-original'}, version: 'explicit-test'},
    fileURLToPath: () => repository, URL, checkoutState: () => before, execFileSync: () => 'b'.repeat(40),
    mkdir, join, writeFile, packedReadmeCases, packedCompositionCases, packedEffectControlCases, nodeBenchmarkFailure,
    execute: async () => assert.fail('No product command'), prepareHealthPackages: async () => ({consumer}),
    runCollectionConsumer: async ({report}) => report.collection.forEach(row => row.completed = true),
    runReadmeCases: async ({report, cases = report.cases}) => cases.forEach(row => row.completed = true),
    runMockEffectControls: async () => {}, verifyNodeBenchmarkPackages: async () => {}});
  await assert.rejects(execute(output), {code: 'ERR_ASSERTION'});
  const report = JSON.parse(await readFile(join(output, 'summary.json'), 'utf8'));
  assert.equal(report.complete, false); assert(report.controls.every(value => !value.completed && value.status === 'unexecuted'));
});

test('normal Effect control timeout retains only the same child primary and never calls close an ACK', async t => {
  const {root, consumer} = await scratch(t), load = await runnerFunctions('./packed-mock-effect-controls.mjs');
  const final = {...explicitEffectControl('paused-cancel'), status: 'failed', primaryCode: 'OriginalCurrentRefusal',
    firstClose: {attempted: true, returned: false}};
  const failure = Object.assign(new Error('Original control timeout'),
    {commandResult: {pid: 7000, code: 1, stdout: JSON.stringify(final)}});
  for (const partialPid of [7000, 7001]) {
    const parent = join(root, String(partialPid)); await mkdir(parent);
    const record = {mode: 'paused-cancel', phases: []};
    const run = load('runControl', {assert, mkdir, writeFile, readFile, copyFile, symlink, readlink, unlink, join, dirname,
      twoModelDealReviewFiles, packedEffectControlCases, assertMockEffectControlOutcome, process, nodeBenchmarkFailure,
      verifyNodeBenchmarkPackages: async () => {}});
    await assert.rejects(run({prepared: {consumer}, root: parent, repository, record,
      async command(_exe, args, options) {
        if (args[1] !== 'capture') {
          await writeFile(join(options.cwd, 'handoff.json.cancel.before-close.json'), JSON.stringify({
            phase: 'cancel', pid: partialPid, failed: true, primaryCode: 'OriginalCurrentRefusal',
            firstClose: {attempted: false, returned: false}}));
          throw failure;
        }
        return {pid: 6000, code: 0, stdout: [...Array.from({length: 10}, (_, i) => explicitStep('capture', String(i))),
          {phase: 'capture', status: 'passed', firstFailedStep: null, firstClose: {attempted: true, returned: true},
            workObservation: explicitWork('capture', 'two-models')},
          {phase: 'capture', event: 'after-first-close', pid: 6000, aliveScopedFD: {after: 0}}]
          .map(value => JSON.stringify(value)).join('\n')};
      }}), error => error === failure);
    const result = record.phases[1]; assert.equal(result.completed, false);
    assert.equal(result.actual.primaryCode, 'OriginalCurrentRefusal');
    assert.equal(result.actual.firstClose.returned, false);
    assert.equal(result.exitCode, 1);
    if (partialPid === 7000) {
      assert.equal(result.partialObservation.primaryCode, 'OriginalCurrentRefusal');
      assert.deepEqual(result.partialObservation.firstClose, {attempted: false, returned: false});
    } else assert.equal(result.partialObservation, undefined);
  }
});
