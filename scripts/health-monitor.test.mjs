import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, readFile, writeFile, mkdir, readdir, rename, symlink, unlink, readlink, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';
import {compileFunction, runInNewContext} from 'node:vm';
import {parse as parseJavaScript} from 'acorn';
import {parse} from 'yaml';
import {compareReports, finishReport, markdown, summarize, exitStatus, digest, measurementProfile} from './health-monitor-report.mjs';
import {parseArguments, requiredQuickMetrics, missingReleaseInputs, recordGuardExit, applyComparison, environmentIdentity, verifyPythonInstalledAfter, verifyNativeInstalledAfter, fixtureIdentities} from './health-monitor.mjs';
import {packDistributionPackages} from './measure-distribution-artifacts.mjs';
import {formalCollectorVerdict, pythonRuntimeIdentity, assertPythonCollectorRuntime, pythonInstalledInventory} from './health-monitor-release.mjs';
import {quickNodeMetrics,execute,distributionMetrics,mockWorkflowMetrics,observeInstalledHealthNodeModules} from './health-monitor-adapters.mjs';
import {projectTemplateFiles} from '../packages/native-cli/lib/project-template.mjs';
import {twoModelDealReviewFiles} from './fixtures/deal-review-two-models.mjs';
import {createOwnedScratch} from './owned-scratch.mjs';
import {createHash} from 'node:crypto';
import {inventory} from './package-release.mjs';
import {verifyNodeBenchmarkPackages} from './benchmark-node-operations.mjs';
import {nodeWarmSmallQueryFixtures} from './benchmark-node-operations.mjs';
import * as releaseAdapters from './health-monitor-release.mjs';
import {nativeOperationsData} from './fixtures/health-native-operations.mjs';
import {mockProjectWorkflowChecks, startMockProjectSource} from '../adapters/host-node/fixtures/mock-project-effect-protocol.fixture.mjs';
import {terminalMockScenario} from '../adapters/host-node/fixtures/mock-project-terminal-public.mjs';

test('terminal Mock normal harness stages both public cases and refuses repeated cold work or close', async t => {
  // Explicit child-command outcomes test orchestration only. No installed
  // product, runtime, Resource, provider or business state is executed here.
  for (const variant of ['terminal-infer', 'terminal-content']) for (const fault of [undefined, 'model', 'close', 'same-pid']) {
    const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-terminal-harness-', label: 'terminal command-port component'});
    t.after(() => scratch.passed());
    const root = join(scratch.path, 'run'), consumer = join(scratch.path, 'consumer');
    await mkdir(root);await mkdir(join(consumer, 'node_modules'), {recursive: true});
    const phases = [], selected = terminalMockScenario(variant);let metric;
    const operation = mockWorkflowMetrics({prepared: {consumer}, root,
      repository: new URL('../', import.meta.url).pathname, variant, counts: {coldSamples: 1},
      onMetric: async value => {metric = value;},
      async command(_node, args, options) {
        const phase = args[1];phases.push(phase);assert.equal(options.timeout, 30000);
        const available = await readdir(join(options.cwd, 'mock'));
        if (phase === 'capture') {
          assert(available.includes('churn-risk.v1.answers.yaml'));
          assert.equal(await readFile(join(options.cwd, selected.path), 'utf8'), selected.source);
          assert.equal(await readFile(join(options.cwd, 'scripts/fixtures/external-rest/timed-installed-context.fixture.mjs'), 'utf8'),
            await readFile(new URL('./fixtures/external-rest/timed-installed-context.fixture.mjs', import.meta.url), 'utf8'));
        } else {
          assert(!available.includes('churn-risk.v1.answers.yaml'));
          await assert.rejects(readFile(join(options.cwd, selected.path)), {code: 'ENOENT'});
        }
        const pid = phase === 'capture' || fault === 'same-pid' ? 101 : 202;
        const value = {phase, variant, pid, status: 'passed', complete: true, submits: phase === 'capture' ? 1 : 0,
          resultReads: 1, lookupOriginal: true, savedFirst: phase === 'recover', originalRefBeforeWait: phase === 'capture',
          originalInputsAbsent: phase === 'recover', firstClose: {attempted: true, returned: true, calls: 1},
          aliveScopedFD: {before: 0, after: 0, pid}, workObservation: {complete: true,
            sourceAcquisitionStarts: phase === 'capture' ? selected.sourceStarts : 0,
            modelCallStarts: phase === 'capture' ? selected.modelStarts : 0, effectReplacementReturns: 0}};
        if (phase === 'recover' && fault === 'model') value.workObservation.modelCallStarts++;
        if (phase === 'recover' && fault === 'close') value.firstClose.returned = false;
        return {pid, code: 0, signal: null, stdout: JSON.stringify(value)};
      }});
    if (fault === undefined) assert.equal((await operation).samples[0].completed, true);
    else await assert.rejects(operation, {code: 'ERR_ASSERTION'});
    assert.deepEqual(phases, ['capture', 'recover']);
    assert.equal(metric.samples[0].verified, fault === undefined);
    const project = metric.samples[0].stateId;
    assert(!(await readdir(project)).includes('node_modules'), 'Return only our temporary consumer alias');
    const first = metric.samples[0].phases[0];
    assert.deepEqual(first.originalInputsRemovedAfterFirstClose, [selected.path, 'mock/churn-risk.v1.answers.yaml']);
    assert.equal(first.completed, true);
  }
});

test('terminal Mock parent carries only the selected Account scenario and rejects mislabeled original phases', async t => {
  // Real imported orchestration with explicit child outcomes, not an actor or
  // a normal Common/Account/Store acceptance. One sample per authored control.
  for (const accountScenario of ['default', 'explicit-operator-content']) {
    const faults = accountScenario === 'default' ? ['none', 'wrong-capture', 'wrong-recover']
      : ['none', 'missing-capture', 'wrong-capture', 'missing-recover', 'wrong-recover'];
    for (const fault of faults) {
      const scratch = await createOwnedScratch({parent:tmpdir(),prefix:'actql-terminal-account-parent-',label:'finite Account propagation component'});
      t.after(() => scratch.passed());
      const root = join(scratch.path,'run'), consumer = join(scratch.path,'consumer');
      await mkdir(root);await mkdir(join(consumer,'node_modules'),{recursive:true});
      const phases = [];let metric;
      const operation = mockWorkflowMetrics({prepared:{consumer},root,
        repository:new URL('../',import.meta.url).pathname,variant:'terminal-content',
        ...(accountScenario === 'default' ? {} : {accountScenario}),counts:{coldSamples:1},
        onMetric:async value => {metric = value;},
        async command(_node,args,options) {
          const phase = args[1];phases.push(phase);
          assert.equal(args.length,accountScenario === 'default' ? 4 : 5);
          assert.equal(args[4],accountScenario === 'default' ? undefined : accountScenario);
          assert.equal(options.timeout,30000);assert.equal(args[2],'terminal-content');
          const pid = phase === 'capture' ? 101 : 202;
          const value = {phase,variant:'terminal-content',pid,status:'passed',complete:true,
            submits:phase === 'capture' ? 1 : 0,resultReads:1,lookupOriginal:true,
            originalRefBeforeWait:phase === 'capture',savedFirst:phase === 'recover',
            originalInputsAbsent:phase === 'recover',firstClose:{attempted:true,returned:true,calls:1},
            aliveScopedFD:{before:0,after:0,pid},workObservation:{complete:true,
              sourceAcquisitionStarts:0,modelCallStarts:0,effectReplacementReturns:0}};
          if (accountScenario !== 'default') value.accountScenario = accountScenario;
          if (fault.endsWith(phase)) {
            if (fault.startsWith('missing')) delete value.accountScenario;
            else value.accountScenario = accountScenario === 'default' ? 'explicit-operator-content' : 'default';
          }
          return {pid,code:0,signal:null,stdout:JSON.stringify(value)};
        }});
      if (fault === 'none') {
        assert.equal((await operation).samples[0].verified,true);
        assert.equal(metric.accountScenario,accountScenario === 'default' ? undefined : accountScenario);
      } else await assert.rejects(operation,{code:'ERR_ASSERTION'});
      assert.deepEqual(phases,fault.endsWith('capture') ? ['capture'] : ['capture','recover']);
      assert.equal(metric.samples[0].verified,fault === 'none');
      const project = metric.samples[0].stateId;
      assert(!(await readdir(project)).includes('node_modules'));
      if (fault.endsWith('capture')) {
        assert.equal(metric.samples[0].phases[0].originalInputsRemovedAfterFirstClose,undefined);
        assert.equal(await readFile(join(project,'terminal.program.json'),'utf8'),terminalMockScenario('terminal-content').source);
        assert.equal(await readFile(join(project,'mock/churn-risk.v1.answers.yaml'),'utf8'),
          projectTemplateFiles('churn-risk-mock')['mock/churn-risk.v1.answers.yaml']);
      }
    }
  }
  let calls = 0;
  for (const [accountScenario,variant] of [['unsupported','terminal-content'],[null,'terminal-content'],
    ['explicit-operator-content','terminal-infer'],['explicit-operator-content','readme']]) {
    await assert.rejects(mockWorkflowMetrics({accountScenario,variant,command:async () => {calls++;}}),
      {code:'ERR_ASSERTION'});
  }
  assert.equal(calls,0);
});

test('terminal Mock harness stops first failed child and keeps original authored inputs', async t => {
  const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-terminal-first-failure-', label: 'terminal failure command-port component'});
  t.after(() => scratch.passed());
  const root = join(scratch.path, 'run'), consumer = join(scratch.path, 'consumer');
  await mkdir(root);await mkdir(join(consumer, 'node_modules'), {recursive: true});
  const primary = Error('OriginalChildUnknown');let calls = 0, metric;
  await assert.rejects(mockWorkflowMetrics({prepared: {consumer}, root, variant: 'terminal-infer',
    repository: new URL('../', import.meta.url).pathname, counts: {coldSamples: 1},
    onMetric: async value => {metric = value;},
    async command() {calls++;throw primary;}}), error => error === primary);
  assert.equal(calls, 1);assert.equal(metric.samples[0].completed, false);
  const project = metric.samples[0].stateId;
  assert.equal(await readFile(join(project, 'terminal.aql'), 'utf8'), terminalMockScenario('terminal-infer').source);
  assert((await readdir(join(project, 'mock'))).includes('churn-risk.v1.answers.yaml'));
  assert(!(await readdir(project)).includes('node_modules'));
});

test('terminal Mock harness protects a changed consumer alias before the cold child', async t => {
  const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-terminal-alias-', label: 'terminal alias component'});
  t.after(() => scratch.passed());
  const root = join(scratch.path, 'run'), consumer = join(scratch.path, 'consumer');
  await mkdir(root);await mkdir(join(consumer, 'node_modules'), {recursive: true});
  let calls = 0, project;
  await assert.rejects(mockWorkflowMetrics({prepared: {consumer}, root, variant: 'terminal-content',
    repository: new URL('../', import.meta.url).pathname, counts: {coldSamples: 1}, onMetric: async () => {},
    async command(_node, _args, options) {
      calls++;project = options.cwd;
      await unlink(join(project, 'node_modules'));await symlink('/unselected/component-only', join(project, 'node_modules'));
      return {pid: 101, code: 0, stdout: JSON.stringify({phase: 'capture', variant: 'terminal-content', pid: 101,
        status: 'passed', complete: true, submits: 1, resultReads: 1, lookupOriginal: true,
        savedFirst: false, originalRefBeforeWait: true, firstClose: {attempted: true, returned: true, calls: 1},
        aliveScopedFD: {before: 0, after: 0, pid: 101},
        workObservation: {complete: true, sourceAcquisitionStarts: 0, modelCallStarts: 0, effectReplacementReturns: 0}})};
    }}), error => error instanceof AggregateError && error.cause.code === 'ERR_ASSERTION');
  assert.equal(calls, 1);
  assert.equal(await readlink(join(project, 'node_modules')), '/unselected/component-only');
  assert.equal(await readFile(join(project, 'terminal.program.json'), 'utf8'), terminalMockScenario('terminal-content').source);
  assert.equal(await readFile(join(project, 'mock/churn-risk.v1.answers.yaml'), 'utf8'),
    projectTemplateFiles('churn-risk-mock')['mock/churn-risk.v1.answers.yaml']);
});

const policy = JSON.parse(await readFile(new URL('../benchmarks/health/config.json', import.meta.url)));
const samples = (ms, count = 10) => Array.from({length: count}, (_, iteration) => ({iteration,
  wallNs: ms * 1e6, cpuUserUs: 1, cpuSystemUs: 1, cpuScope: 'synthetic unit caller',
  peakRssBytes: 1024, rssScope: 'synthetic child RSS', verified: true, completed: true}));

const workflowSource = await readFile(new URL('../adapters/host-node/fixtures/mock-project-effect-public.mjs', import.meta.url), 'utf8');
const workflowSyntax = parseJavaScript(workflowSource, {ecmaVersion: 'latest', sourceType: 'module'});

for (const deal of [false, true]) {
  const template = deal ? 'deal-review-mock' : 'churn-risk-mock';
  test(`public Mock workflow ${template} keeps independent typed review and exact-write oracles`, async () => {
    // Execute only the original fixture's pure assertions with authored DATA.
    // No connect, Core mock, model result or workflow phase runs here.
    const checks = await mockProjectWorkflowChecks({template});
    const ids = deal ? ['006Acme', '006Globex'] : ['001Acme', '001Globex'];
    const before = deal ? [
      {id: ids[0], name: 'Acme Corp - Renewal', StageName: 'Proposal', NextStep: null},
      {id: ids[1], name: 'Globex - Expansion', StageName: 'Negotiation', NextStep: 'Legal review'},
    ] : [
      {id: ids[0], Churn_Risk__c: 'low', Risk_Reason__c: null},
      {id: ids[1], Churn_Risk__c: 'medium', Risk_Reason__c: null},
    ];
    const answers = deal ? [
      {changed: true, stage: 'Negotiation', next_step: 'Send revised pricing by Friday'},
      {changed: true, stage: 'Closed Lost', next_step: 'Revisit next fiscal year'},
    ] : [
      {level: 'high', reason: 'falling usage and a competitor evaluation'},
      {level: 'high', reason: 'support tickets about pricing'},
    ];
    const changes = deal ? [
      {StageName: 'Negotiation', NextStep: 'Send revised pricing by Friday'},
      {StageName: 'Closed Lost', NextStep: 'Revisit next fiscal year'},
    ] : answers.map(answer => ({Churn_Risk__c: 'high', Risk_Reason__c: answer.reason}));
    const rows = before.map((row, index) => ({...row, ...(deal
      ? {review: {outcome: 'ok', value: answers[index]}}
      : {active_users: index === 0 ? '4' : '12', risk: {outcome: 'ok', value: answers[index]}})}));
    checks.checkRows(rows);
    const wrong = structuredClone(rows);
    wrong[0][deal ? 'review' : 'risk'].outcome = 'error';
    assert.throws(() => checks.checkRows(wrong));
    assert.throws(() => checks.checkRows(rows.slice(1)));
    const cid = digit => 'sha256:' + digit.repeat(64);
    const summary = {reviewProjectionCid: cid('1'), requiredArtifact: {cid: cid('2')}, requirements: []};
    const ref = {authorityScopeCid: cid('3')};
    const review = {version: 'actql-review-projection/0.1', review_projection_cid: cid('1'),
      effect_preview_cid: cid('2'), authority_scope_cid: cid('3'), approval_claims: [],
      authoring_context_cid: cid('4'), redaction_policy_cid: cid('5'), sensitivity: 'restricted',
      retention_class: 'approval-evidence', encryption_required: true, displayed_authoring_context: {},
      displayed_permissions: [], displayed_scope: {effects: [{kind: 'update',
        target: 'connector://salesforce/' + (deal ? 'Opportunity' : 'Account'), count: 2}]},
      displayed_rows: before.map((row, index) => ({target_row_identity: row.id,
        row_preview_cid: cid('6'), preview_strength: 'full_diff', target_guard: {state: 'version', version_cid: cid('7')},
        before: {state: 'present', value: row}, intended_changes: {state: 'present', value: changes[index]},
        after: {state: 'present', value: changes[index]}}))};
    checks.checkReview(review, summary, ref);
    const wrongReview = structuredClone(review);
    wrongReview.displayed_rows[0].after.value = {};
    assert.throws(() => checks.checkReview(wrongReview, summary, ref));
    const target = deal ? 'Opportunity' : 'Account';
    const untouched = {files: [{id: 'original-file', content_utf8: 'original document\n'}]};
    const original = JSON.stringify({salesforce: {[target]: {key: ['id'], rows: before}}, drive: untouched}, null, 2) + '\n';
    const expected = JSON.stringify({salesforce: {[target]: {key: ['id'], rows:
      before.map((row, index) => ({...row, ...changes[index]}))}}, drive: untouched}, null, 2) + '\n';
    assert.equal(checks.expectedBytes(original), expected);
  });

  test(`public Mock workflow caller selects ${template} without replacing a failed phase`, async () => {
    const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-workflow-selection-',
      label: 'Authored Mock selection only, no Host workflow execution'});
    const root = join(scratch.path, 'run'), consumer = join(scratch.path, 'consumer');
    await mkdir(root); await mkdir(join(consumer, 'node_modules'), {recursive: true});
    const primary = new Error('Selected original workflow was not executed');
    const observations = [];
    let calls = 0;
    await assert.rejects(mockWorkflowMetrics({prepared: {consumer}, root,
      repository: new URL('../', import.meta.url).pathname, counts: {coldSamples: 1},
      ...(deal ? {template} : {}), onMetric: metric => observations.push(metric),
      async command(executable, args, options) {
        calls++; assert.equal(executable, process.execPath);
        assert.equal(args[1], 'capture'); assert.equal(args[2], join(options.cwd, 'handoff.json'));
        assert.deepEqual(args.slice(3), deal ? [template] : []);
        const authored = projectTemplateFiles(template);
        for (const [name, bytes] of Object.entries(authored)) {
          assert.equal(await readFile(join(options.cwd, name), 'utf8'), bytes);
        }
        assert.equal(await readFile(args[0], 'utf8'), workflowSource);
        assert.equal(await readFile(join(options.cwd, 'mock-project-effect-protocol.fixture.mjs'), 'utf8'),
          await readFile(new URL('../adapters/host-node/fixtures/mock-project-effect-protocol.fixture.mjs', import.meta.url), 'utf8'));
        throw primary;
      }}), error => error === primary);
    assert.equal(calls, 1);
    assert.equal(observations.length, 1);
    assert.equal(observations[0].samples[0].completed, false);
    assert.equal(observations[0].samples[0].verified, false);
    assert.equal(observations[0].samples[0].phases.length, 1);
    assert.equal(observations[0].samples[0].phases[0].phase, 'capture');
    assert.equal(observations[0].samples[0].phases[0].completed, false);
    const project = join(root, `mock-project-${template}-readme-0`);
    assert.equal(JSON.parse(await readFile(join(project, 'capture.observation.json'), 'utf8')).completed, false);
    assert.equal((await readdir(project)).includes('node_modules'), false);
    await scratch.passed();
  });
}

async function healthAuthoringBinFixture(consumer) {
  const modules = join(consumer, 'node_modules');
  const local = join(modules, '@actql/local-node');
  const relativeTarget = '_build/connector-authoring/scripts/connector.mjs';
  const target = '../@actql/local-node/' + relativeTarget;
  const bin = join(modules, '.bin');
  const path = '.bin/actql-connector';
  await mkdir(dirname(join(local, relativeTarget)), {recursive: true});
  await writeFile(join(local, 'package.json'), JSON.stringify({
    name: '@actql/local-node', bin: {'actql-connector': relativeTarget},
  }));
  await writeFile(join(local, relativeTarget), '#!/usr/bin/env node\n', {mode: 0o755});
  await mkdir(bin);
  const alias = join(modules, path);
  await symlink(target, alias);
  return {modules, local, bin, alias, path, target};
}

test('browser distribution invokes the installed esbuild executable and retains import refusals', async () => {
  const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-health-browser-',
    label: 'Actual browser executable and closed import boundary'});
  const repository = join(scratch.path, 'repository'), consumer = join(scratch.path, 'consumer');
  await mkdir(join(repository, 'node_modules'), {recursive: true});
  const require = createRequire(import.meta.url);
  await symlink(dirname(require.resolve('esbuild/package.json')), join(repository, 'node_modules/esbuild'));
  const sdk = join(consumer, 'node_modules/@actql/sdk'), wire = join(consumer, 'node_modules/@actql/client-wire');
  await mkdir(sdk, {recursive: true}); await mkdir(wire, {recursive: true});
  await writeFile(join(wire, 'index.mjs'), 'export const answer = 42;\n');
  const source = "export {answer} from '../client-wire/index.mjs';\n";
  await writeFile(join(sdk, 'index.mjs'), source);
  const packages = ['sdk', 'client-wire'].map(name => ({name: '@actql/' + name, version: '0.0.0',
    files: [{path: 'index.mjs', bytes: name === 'sdk' ? Buffer.byteLength(source) : 26}], bytes: 1,
    sha256: digest(name), file: name + '.tgz'}));
  const prepared = {consumer, manifestPath: 'synthetic-no-package-acquisition', manifest: {packages}};
  const commands = [];
  const command = (executable, args, settings) => {
    commands.push({executable, args});
    assert.equal(executable, join(repository, 'node_modules/esbuild/bin/esbuild'));
    assert.equal(args[0], join(sdk, 'index.mjs'));
    return execute(executable, args, settings);
  };
  const root = join(scratch.path, 'success'); await mkdir(root);
  const installed = await healthAuthoringBinFixture(consumer);
  const payload = await Promise.all(['sdk', 'client-wire', 'local-node'].map(name =>
    inventory(join(installed.modules, '@actql', name))));
  const result = await distributionMetrics({repository, prepared, root, command, source: {sha: 'a'.repeat(40)}});
  assert.equal(result.metrics.find(row => row.id === 'installed:node-local').value,
    payload.flat().reduce((sum, row) => sum + row.bytes, 0));
  assert.deepEqual((await observeInstalledHealthNodeModules(consumer)).binLinks,
    [{path: installed.path, target: installed.target}]);
  await assert.rejects(inventory(installed.modules), /Release payload symlink: \.bin\/actql-connector/u);

  const collect = () => distributionMetrics({repository, prepared, root, command, source: {sha: 'a'.repeat(40)}});
  const unexpected = join(installed.bin, 'undocumented');
  await symlink(installed.target, unexpected);
  await assert.rejects(collect(), /Unexpected or missing installed command link/u);
  await unlink(unexpected);
  await unlink(installed.alias);
  await symlink('../@actql/local-node/package.json', installed.alias);
  await assert.rejects(collect(), /Installed command points to the wrong target/u);
  await unlink(installed.alias);
  await symlink(installed.target, installed.alias);
  const payloadAlias = join(installed.local, 'linked-payload.mjs');
  await symlink('package.json', payloadAlias);
  await assert.rejects(collect(), /Release payload symlink: @actql\/local-node\/linked-payload.mjs/u);
  await assert.rejects(inventory(installed.local), /Release payload symlink: linked-payload.mjs/u);
  await unlink(payloadAlias);
  const outside = join(consumer, 'outside-bin');
  await rename(installed.bin, outside);
  await symlink(outside, installed.bin);
  await assert.rejects(collect(), /Installed .bin must be a real directory/u);
  await unlink(installed.bin);
  await rename(outside, installed.bin);
  assert.equal((await import(pathToFileURL(join(root, 'browser.mjs')).href)).answer, 42);
  assert.equal(commands.length, 1);
  assert.equal(result.metrics.filter(row => row.id.startsWith('browser-')).length, 2);
  assert.ok(result.metrics.filter(row => row.id.startsWith('browser-')).every(row => row.required && row.value > 0));
  for (const [name, text] of [['node-builtin', "export {readFile} from 'node:fs';\n"],
    ['foreign-input', "export {answer} from '../../../foreign.mjs';\n"]]) {
    await writeFile(join(consumer, 'foreign.mjs'), 'export const answer = 42;\n');
    await writeFile(join(sdk, 'index.mjs'), text);
    const failed = join(scratch.path, name); await mkdir(failed);
    await assert.rejects(distributionMetrics({repository, prepared, root: failed, command, source: {sha: 'a'.repeat(40)}}));
  }
  assert.equal(commands.length, 3);
  await scratch.passed();
});

test('early distribution failure retains independent installed before and after observations', async () => {
  const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-health-early-distribution-',
    label: 'Collector failure and independent installed custody'});
  const text = await readFile(new URL('./health-monitor.mjs', import.meta.url), 'utf8');
  const start = text.indexOf('export async function executeMonitor(');
  const end = text.indexOf('\nexport async function main(', start);
  assert.ok(start >= 0 && end > start);
  const body = text.slice(start, end).replace('export ', '').replaceAll('import(', 'selectedImport(');
  for (const change of ['unchanged', 'payload', 'bin']) {
    const root = join(scratch.path, change), consumer = join(root, 'consumer');
    const product = join(consumer, 'node_modules/@actql/node'); await mkdir(product, {recursive: true});
    await writeFile(join(product, 'index.mjs'), 'export const value = 1;\n');
    const tar = Buffer.from('synthetic verifier input, never unpacked or installed');
    await writeFile(join(root, 'node.tgz'), tar);
    const manifest = {packages: [{name: '@actql/node', file: 'node.tgz', bytes: tar.length, sha256: digest(tar),
      integrity: 'sha512-' + createHash('sha512').update(tar).digest('base64'), files: await inventory(product)}]};
    const prepared = {consumer, manifest, manifestPath: join(root, 'manifest.json')};
    const installed = await healthAuthoringBinFixture(consumer);
    const before = await observeInstalledHealthNodeModules(consumer);
    const source = {sha: 'a'.repeat(40)}, environment = {scope: 'synthetic component ports'};
    const report = {source, environment, artifacts: [], metrics: [], errors: []};
    const primary = new Error('Original browser collector failure');
    const selected = runInNewContext('(' + body + ')', {
      repository: root, process, join, mkdir, structuredClone, jsonDigest: value => digest(JSON.stringify(value)),
      summarize: () => assert.fail('No runtime measurements in this component'),
      finishReport: value => value, saveReport: async () => {}, applyComparison: async () => {},
      sourceIdentity: () => source, environmentIdentity: async () => environment,
      verifyNativeInstalledAfter: async () => {}, verifyPythonInstalledAfter: async () => {},
      selectedImport: async specifier => {
        if (specifier === './benchmark-node-operations.mjs') return {verifyNodeBenchmarkPackages};
        assert.equal(specifier, './health-monitor-adapters.mjs');
        return {execute: () => assert.fail('No subprocess in this observation component'),
          prepareHealthPackages: async () => prepared, observeInstalledHealthNodeModules,
          distributionMetrics: async input => {
            assert.equal(input.installedInventory, report.installedInventoryBefore);
            assert.deepEqual(report.installedBinLinksBefore, before.binLinks);
            if (change === 'payload') await writeFile(join(product, 'index.mjs'), 'export const value = 2;\n');
            if (change === 'bin') await unlink(installed.alias);
            throw primary;
          }};
      },
    });
    await selected({mode: 'quick', options: {}, report, directory: root});
    assert.deepEqual(report.installedInventoryBefore, before.files);
    assert.equal(report.errors[0].target, 'collector'); assert.equal(report.errors[0].message, primary.message);
    if (change !== 'unchanged') {
      assert.notEqual(report.installedPayloadsUnchanged, true);
      assert.equal(report.errors[1].target, 'package-after');
      assert.doesNotMatch(report.errors[1].message, /Received undefined/u);
      if (change === 'bin') assert.match(report.errors[1].message, /Unexpected or missing installed command link/u);
    } else {
      assert.equal(report.installedPayloadsUnchanged, true);
      assert.deepEqual(report.installedInventoryAfter, before.files);
      assert.deepEqual(report.installedBinLinksAfter, before.binLinks);
      assert.equal(report.errors.length, 1);
    }
  }
  await scratch.passed();
});

test('missing Node comparison retains incomplete evidence without suppressing independent Native selection', async () => {
  const text = await readFile(new URL('./health-monitor-release.mjs', import.meta.url), 'utf8');
  const start = text.indexOf('export async function releaseMeasurements('); assert.ok(start >= 0);
  for (const failure of [undefined, new Error('Original synthetic Native collector failure')]) {
    const metrics = [], selections = [], options = {nativeManifest: '/synthetic/verified/native.json',
      nativeConsumer: '/synthetic/verified/consumer'};
    const selected = runInNewContext('(' + text.slice(start).replace('export ', '') + ')', {
      platform: () => 'unit-os', arch: () => 'unit-arch', release: () => 'unit-release',
      cpus: () => [{model: 'unit-cpu'}], totalmem: () => 1, process: {version: 'unit-node'},
      releaseNativeOperations: async input => {selections.push(input); if (failure) throw failure;},
    });
    const input = {options, prepared: {}, repository: '/synthetic/repository', root: '/synthetic/report',
      source: {sha: 'a'.repeat(40)}, command: () => assert.fail('No physical process may run in this routing test'),
      onMetric: async row => metrics.push(row)};
    if (failure) await assert.rejects(selected(input), error => error === failure);
    else await selected(input);
    assert.equal(selections.length, 1, 'Native selection must not depend on unrelated Node comparison controls');
    assert.equal(selections[0].options, options);
    assert.ok(metrics.some(row => row.id === 'formal-node-collector' && row.status === 'incomplete'));
    const warm = metrics.filter(row => row.target === 'native');
    assert.deepEqual(warm.map(row => row.id), ['warm-select', 'warm-result', 'warm-status', 'warm-join', 'warm-union', 'warm-decimal-sum', 'warm-parameters', 'warm-unicode']);
    assert.ok(warm.every(row => row.status === 'incomplete' && row.required && row.requiredSamples === 100 &&
      row.temperature === 'warm' && row.reason.includes('no retained-Host warm entry') && row.samples === undefined));
  }
});

test('Release selects the existing Native operations collector instead of combined CLI routes', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-health-native-selection-'));
  const manifest = join(root, 'native.json'), packages = join(root, 'node.json'), controls = join(root, 'controls.json');
  const source = {sha: 'a'.repeat(40)}, manifestBytes = '{"synthetic":"never executed Native DATA"}';
  await writeFile(manifest, manifestBytes); await writeFile(packages, '{}');
  const environment = {platform: 'unit-os', arch: 'unit-arch', osRelease: 'unit-release', node: 'unit-node',
    cpuModel: 'unit-cpu', logicalCpus: 1, memoryBytes: 1};
  await writeFile(controls, JSON.stringify({sourceSha: source.sha, cohortSha256: digest('{}'), environment, load: 'isolated'}));
  const text = await readFile(new URL('./health-monitor-release.mjs', import.meta.url), 'utf8');
  const start = text.indexOf('export async function releaseMeasurements('); assert.ok(start >= 0);
  const selected = runInNewContext('(' + text.slice(start).replace('export ', '') + ')', {
    assert, readFile, writeFile, join, digest, jsonDigest: value => digest(JSON.stringify(value)),
    platform: () => 'unit-os', arch: () => 'unit-arch', release: () => 'unit-release',
    cpus: () => [{model: 'unit-cpu'}], totalmem: () => 1, process: {version: 'unit-node', resourceUsage: () => ({maxRSS: 1})},
    runNodeWarmBenchmark: async () => ({latency: []}), runNodeProcessBenchmark: async () => ({latency: []}),
    formalCollectorVerdict: releaseAdapters.formalCollectorVerdict,
    releaseNativeOperations: releaseAdapters.releaseNativeOperations,
  });
  const metrics = [], commands = [];
  await selected({options: {nodeControls: controls, nativeManifest: manifest, nativeConsumer: join(root, 'unused-consumer'), load: 'isolated'},
    prepared: {manifestPath: packages, consumer: join(root, 'unused-node')}, repository: new URL('../', import.meta.url).pathname,
    root, source, command: async (_executable, args) => {
      commands.push(args);
      assert.ok(args.includes('--selection') && args.includes('native-operations'), 'Use the existing separate Native CLI operation selection');
      assert.equal(args.includes('--operation'), false, 'Do not execute the older combined routes too');
      const output = args[args.indexOf('--output') + 1]; await mkdir(output);
      await writeFile(join(output, 'measurements.json'), JSON.stringify(nativeOperationsData(source.sha, digest(manifestBytes))));
      return {stdout: ''};
    }, onMetric: async row => metrics.push(row)});
  assert.equal(commands.length, 1);
  assert.deepEqual(metrics.filter(row => row.target === 'native' && row.temperature === 'cold').map(row => [row.id, row.samples.length, row.requiredSamples]),
    [['cold-new-run', 100, 100], ['cold-result', 100, 100]]);
  assert.equal(metrics.filter(row => row.target === 'native' && row.id.startsWith('warm-')).length, 8);
  assert.ok(metrics.filter(row => row.target === 'native' && row.id.startsWith('warm-')).every(row => row.status === 'incomplete'));
  const report = fixture('release');
  for (const metric of metrics.filter(row => row.target === 'native')) {
    const index = report.metrics.findIndex(row => row.target === metric.target && row.id === metric.id);
    assert.ok(index >= 0); report.metrics[index] = metric;
  }
  finishReport(report);
  const warm = report.verdicts.filter(row => row.target === 'native' && row.metric.startsWith('warm-'));
  assert.equal(warm.length, 8); assert.ok(warm.every(row => row.status === 'incomplete' && row.reason.includes('no retained-Host warm entry')));
});

async function nativeReleaseDataCase({make = (source, cohort) => nativeOperationsData(source, cohort), commandError, omitRaw = false} = {}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-health-native-report-')), manifest = join(root, 'native.json');
  const manifestBytes = '{"synthetic":"source-tool-only"}', source = {sha: 'a'.repeat(40)};
  await writeFile(manifest, manifestBytes);
  const raw = make(source.sha, digest(manifestBytes)), rawBytes = JSON.stringify(raw), metrics = [];
  let commands = 0;
  const run = () => releaseAdapters.releaseNativeOperations({options: {nativeManifest: manifest,
    nativeConsumer: join(root, 'never-executed-consumer'), load: 'isolated'},
  root, source, repository: new URL('../', import.meta.url).pathname,
  command: async (executable, args, settings) => {
    commands++;
    assert.equal(executable, 'python3'); assert.equal(settings.name, 'formal-native-operations');
    assert.equal(settings.timeout, 0); assert.equal(args[args.indexOf('--selection') + 1], 'native-operations');
    assert.equal(args[args.indexOf('--mode') + 1], 'final'); assert.equal(args.includes('--operation'), false);
    assert.equal(args[args.indexOf('--load') + 1], 'isolated');
    if (!omitRaw) {const output = args[args.indexOf('--output') + 1]; await mkdir(output);
      await writeFile(join(output, 'measurements.json'), rawBytes);}
    if (commandError) throw commandError;
    return {stdout: ''};
  }, onMetric: async row => metrics.push(row)});
  return {root, raw, rawBytes, metrics, run, commands: () => commands};
}

test('Native Release retains separate references, exact raw evidence and existing assessment purpose', async () => {
  const fixture = await nativeReleaseDataCase(), assessment = await fixture.run();
  assert.equal(fixture.commands(), 1); assert.equal(assessment.status, 'passed');
  assert.equal(assessment.purpose, 'native-cli-latency-functional-only');
  assert.equal(assessment.fullPerformanceAccepted, false); assert.equal(assessment.releaseAccepted, false);
  const [init, first, fresh, saved] = fixture.metrics;
  assert.deepEqual([init.id, init.kind, init.value, init.observedCount], ['init-separate', 'reference', 3, 1]);
  assert.deepEqual([first.id, first.kind, first.value, first.observedCount], ['first-query-separate', 'reference', 80, 1]);
  assert.deepEqual([fresh.id, saved.id], ['cold-new-run', 'cold-result']);
  assert.equal(new Set(fresh.samples.concat(saved.samples).map(row => row.pid)).size, 200);
  assert.deepEqual(fresh.samples, fixture.raw.latency[0].samples); assert.deepEqual(saved.samples, fixture.raw.latency[1].samples);
  assert.equal(await readFile(fresh.evidence, 'utf8'), fixture.rawBytes, 'original collector report is never rewritten');
  const stored = JSON.parse(await readFile(fresh.formalAssessment));
  assert.equal(stored.rawSha256, digest(fixture.rawBytes)); assert.deepEqual(stored.assessment, assessment);
  const profile = measurementProfile('release', {platform: 'linux', architecture: 'x64'});
  assert.deepEqual(profile.filter(row => row.target === 'native' && row.temperature === 'cold').map(row => [row.id, row.requiredSamples]),
    [['cold-new-run', 100], ['cold-result', 100]]);
  assert.equal(profile.some(row => row.target === 'native' && ['first-init', 'cold-existing'].includes(row.id)), false);
  assert.deepEqual(profile.filter(row => row.target === 'python' && row.temperature === 'cold').map(row => [row.id, row.requiredSamples]),
    [['first-init', 30], ['cold-existing', 30]]);
});

test('Native Release preserves partial failed samples and the original command error without retry', async () => {
  const original = new Error('Synthetic original CLI failure, not a product observation');
  const fixture = await nativeReleaseDataCase({commandError: original, make: (source, cohort) => {
    const report = nativeOperationsData(source, cohort);
    report.firstFailure = {operation: 'cold-new-run', name: 'SyntheticFailure', message: original.message};
    report.latency = [report.latency[0]]; report.latency[0].samples = [report.latency[0].samples[0]];
    Object.assign(report.latency[0].samples[0], {completed: false, verified: false});
    report.latency[0].stoppedEarly = true; report.functional.rows = [{...report.functional.rows[0], completed: false}];
    report.publicCallAttempts = {init: 1, run: 2, result: 0}; return report;
  }});
  await assert.rejects(fixture.run(), error => error === original); assert.equal(fixture.commands(), 1);
  const fresh = fixture.metrics.find(row => row.id === 'cold-new-run'), saved = fixture.metrics.find(row => row.id === 'cold-result');
  assert.equal(fresh.samples.length, 1); assert.equal(fresh.samples[0].verified, false); assert.equal(fresh.status, 'error');
  assert.ok(fresh.reason.includes(original.message));
  assert.equal(saved.samples, undefined, 'unobserved route cannot become an empty successful population');
  assert.equal(saved.status, 'error'); assert.equal(await readFile(fresh.evidence, 'utf8'), fixture.rawBytes);
  const assessment = JSON.parse(await readFile(fresh.formalAssessment)).assessment;
  assert.equal(assessment.status, 'failed'); assert.equal(assessment.fullPerformanceAccepted, false);
  const absent = await nativeReleaseDataCase({commandError: original, omitRaw: true});
  await assert.rejects(absent.run(), error => error === original); assert.equal(absent.commands(), 1); assert.equal(absent.metrics.length, 0);
});

test('Native Release rejects foreign identity and keeps incomplete and slow assessor results distinct', async () => {
  for (const mutate of [r => r.sourceSha = 'b'.repeat(40), r => r.cohortSha256 = 'b'.repeat(64),
    r => r.mode = 'diagnostic', r => r.environmentSha256 = 'b'.repeat(64),
    r => r.latency[1].samples[0].publicRunId = 'foreign-synthetic-run']) {
    const fixture = await nativeReleaseDataCase({make: (source, cohort) => {const report = nativeOperationsData(source, cohort); mutate(report); return report;}});
    await assert.rejects(fixture.run()); assert.equal(fixture.commands(), 1); assert.equal(fixture.metrics.length, 0);
  }
  const incomplete = await nativeReleaseDataCase({make: (source, cohort) => {
    const report = nativeOperationsData(source, cohort); report.installedPayloadsUnchanged = undefined; return report;
  }});
  assert.equal((await incomplete.run()).status, 'incomplete'); assert.ok(incomplete.metrics.every(row => row.status === 'incomplete'));
  const slow = await nativeReleaseDataCase({make: (source, cohort) => nativeOperationsData(source, cohort, 250)});
  assert.equal((await slow.run()).status, 'failed'); assert.ok(slow.metrics.every(row => row.status === 'regression'));
  const cleanup = await nativeReleaseDataCase({make: (source, cohort) => {
    const report = nativeOperationsData(source, cohort); report.cleanup.closed = false; return report;
  }});
  await cleanup.run(); assert.ok(cleanup.metrics.every(row => row.status === 'error'));
});

test('Release Native statistics retain the original 100-sample minimum without promoting Quick', async () => {
  const text = await readFile(new URL('./health-monitor.mjs', import.meta.url), 'utf8');
  const start = text.indexOf('const pythonReleaseMetrics = new Set();');
  const end = text.indexOf('  const command =', start);
  assert.ok(start >= 0 && end > start);
  for (const [mode, count, requiredSamples, expectedP95] of [['release', 50, 100, null], ['quick', 10, 10, null], ['release', 100, 100, 10]]) {
    const report = {metrics: []};
    const observe = await runInNewContext('(async () => {' + text.slice(start, end) + 'return onMetric;})()', {
      report, mode, summarize, structuredClone, directory: '/unused', saveReport: async () => {}, finishReport: value => value,
    });
    await observe({id: 'cold-new-run', target: 'native', kind: 'latency', temperature: 'cold', requiredSamples, samples: samples(10, count)});
    assert.equal(report.metrics[0].statistics.p95Ms, expectedP95);
  }
});
function fixture(mode = 'quick') {
  const report = {format: 'actql-health/0.1', mode, source: {sha: 'a'.repeat(40), dirty: false},
    environment: {platform: 'linux', architecture: 'x64', osRelease: 'test-os', cpuModel: 'unit CPU', logicalCpus: 2,
      node: 'test-node', nodeExecutableSha256: '0'.repeat(64), python: 'test-python', moon: 'test-moon',
      toolchainSha256: '1'.repeat(64), buildSettings: {profile: 'release', load: 'isolated'}},
    methodologySha256: '2'.repeat(64), baseline: {id: 'synthetic-unit-only', reviewed: true, reason: 'test vector, never a product baseline'},
    artifacts: [{name: 'test', sourceSha: 'a'.repeat(40), sha256: '3'.repeat(64)}], errors: [],
    metrics: []};
  if (mode === 'release') report.environment.pythonRuntime = {version: '3.12.12', executableSha256: '5'.repeat(64)};
  report.metrics = measurementProfile(mode, report.environment).map(row => ({...row, evidence: 'synthetic unit only',
    fixtureSha256: '4'.repeat(64), ...(row.kind === 'latency' ? {samples: samples(10, row.requiredSamples)} : {value: 1000})}));
  if (mode === 'release') {
    report.comparison = {available: true, comparable: true, baselineId: 'synthetic-unit-only', status: 'pass'};
    for (const metric of report.metrics.filter(row => row.kind === 'latency')) {
      const kind = metric.id.startsWith('warm-') ? (metric.id === 'warm-status' ? 'public-status' : 'public-result')
        : metric.target === 'native' ? 'cli-result-exit' : 'process-result-close';
      for (const row of metric.samples) row.publicTiming = kind === 'process-result-close'
        ? {kind, startNs: 1, observedNs: 2, closeStartNs: 3, closeEndNs: 4, endNs: 5}
        : kind === 'cli-result-exit' ? {kind, startNs: 1, exitNs: 2, observedNs: 3, endNs: 4}
          : {kind, startNs: 1, observedNs: 2, endNs: 3};
    }
  }
  if (mode === 'release') report.metrics.push({id: 'synthetic-contained.wasm', target: 'python', kind: 'size',
    artifactKind: 'wasm', value: 1000, unit: 'bytes', required: true, fixtureSha256: '4'.repeat(64), evidence: 'synthetic unit only'});
  if (mode === 'release') {
    const files = [{path: 'synthetic-unit-only', bytes: 1000, mode: 0o644, sha256: '7'.repeat(64)}];
    const installed = {roots: ['synthetic-unit-only'], files, bytes: 1000, sha256: digest(JSON.stringify(files))};
    report.artifacts.push({name: 'python-products-installed', artifactKind: 'installed', sourceSha: report.source.sha,
      sha256: installed.sha256, installedBytes: installed.bytes, installedInventory: installed});
    report.pythonInstalledInventoryAfter = structuredClone(installed);
    report.pythonInstalledPayloadsUnchanged = true;
    const native = {sourceSha: report.source.sha, cohortSha256: '8'.repeat(64), platform: 'linux-x64-gnu',
      packages: Object.fromEntries(['actql', '@actql/cli-linux-x64-gnu'].map(name => [name,
        {installedBytes: 1000, payloads: 1, inventorySha256: '9'.repeat(64)}]))};
    report.artifacts.push({name: 'native-products-installed', artifactKind: 'installed', sourceSha: report.source.sha,
      sha256: digest(JSON.stringify(native)), installedBytes: 2000, installedInventory: native});
    report.nativeInstalledInventoryAfter = structuredClone(native);
    report.nativeInstalledPayloadsUnchanged = true;
  }
  report.sourceAfter = structuredClone(report.source); report.environmentAfter = structuredClone(report.environment);
  report.installedPayloadsUnchanged = true; return report;
}
test('size thresholds retain target, absolute and relative growth', () => {
  for (const [growth, expected] of [[0.09, 'pass'], [0.10, 'warning'], [0.25, 'regression']]) {
    const base = fixture(), current = fixture(); current.metrics[0].value = 1000 * (1 + growth);
    const result = compareReports(base, current, policy);
    assert.equal(result.status, expected); assert.equal(result.verdicts[0].target, '@actql/client-wire');
    assert.equal(result.verdicts[0].absoluteDelta, growth * 1000);
  }
});
test('Browser gzip has its own 5/15 percent thresholds', () => {
  const base = fixture(), current = fixture();
  const metric = current.metrics.find(row => row.id === 'browser-gzip');
  metric.value = 1050; assert.equal(compareReports(base, current, policy).status, 'warning');
  metric.value = 1150; assert.equal(compareReports(base, current, policy).status, 'regression');
});
test('Quick latency requires both relative and absolute warning conditions; warning exits zero', () => {
  for (const [cold, before, after, expected] of [[false, 1, 2, 'pass'], [false, 10, 13, 'warning'],
    [true, 10, 40, 'pass'], [true, 100, 150, 'warning']]) {
    const base = fixture(), current = fixture();
    for (const [report, ms] of [[base, before], [current, after]]) {
      const metric = report.metrics.find(row => row.id === (cold ? 'cold-new-state-public-open' : 'warm-select'));
      metric.samples = samples(ms, metric.requiredSamples);
    }
    const comparison = compareReports(base, current, policy); assert.equal(comparison.status, expected);
    current.comparison = comparison; assert.equal(finishReport(current).exitCode, 0);
  }
});
test('RSS 20 percent is a warning, not a CI failure', () => {
  const base = fixture(), current = fixture();
  current.metrics.find(row => row.id === 'peak-rss').value = 1200;
  assert.equal(compareReports(base, current, policy).status, 'warning');
  assert.equal(exitStatus('warning'), 0);
});
test('CPU, toolchain, fixture, build or dirty mismatch refuses comparison', () => {
  for (const mutate of [r => r.environment.cpuModel = 'other CPU', r => r.environment.node = 'other version',
    r => r.environment.buildSettings.profile = 'debug', r => r.methodologySha256 = 'different', r => r.source.dirty = true,
    r => r.artifacts[0].sourceSha = 'b'.repeat(40), r => r.environment.moon = null]) {
    const current = fixture(); mutate(current);
    const result = compareReports(fixture(), current, policy);
    assert.equal(result.status, 'incomplete'); assert.equal(result.comparable, false);
  }
});

test('Release methodology identity binds actual cold and Native Python collector sources', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-health-methodology-'));
  const quickFiles = ['scripts/benchmark-node-operations.mjs', 'scripts/node-benchmark-evidence.mts',
    'adapters/host-node/fixtures/mock-project-effect-public.mjs',
    'adapters/host-node/fixtures/mock-project-effect-protocol.fixture.mjs',
    'packages/native-cli/lib/project-template.mjs', 'scripts/health-monitor-adapters.mts',
    'scripts/health-monitor.mjs', 'scripts/health-monitor-report.mts', 'scripts/measure-distribution-artifacts.mts',
    'scripts/package-release.mjs', 'scripts/package-inventory.mts', 'scripts/installed-connector-bin.mts',
    'scripts/connector-authoring-toolkit.mts', 'scripts/operation-performance.mjs', 'scripts/operation-performance-sample-summary.mts', 'scripts/ordinary-operation-packages.mjs'];
  const releaseOnly = ['scripts/benchmark-node-process-operations.mjs', 'scripts/benchmark-ordinary-processes.py',
    'scripts/health-monitor-release.mjs', 'scripts/health-release-artifacts.py', 'scripts/native-cli-release.mjs',
    'scripts/python-release-latency-policy.mts', 'scripts/health-python-release-evidence.mts',
    'scripts/python_release_cohort.py', 'scripts/build-python-product-wheels.py', 'scripts/release-version.mts'];
  const files = [...quickFiles, ...releaseOnly];
  for (const file of files) {
    await mkdir(join(root, file, '..'), {recursive: true}); await writeFile(join(root, file), 'authored source-tool DATA\n');
  }
  const identities = mode => fixtureIdentities(mode, {root});
  const original = await identities('release');
  assert.deepEqual(Object.keys(original).sort(), [...files].sort());
  for (const file of files) {
    await writeFile(join(root, file), 'changed actual collector timing boundary DATA\n');
    const changed = await identities('release');
    assert.notEqual(digest(JSON.stringify(changed)), digest(JSON.stringify(original)), file + ' must change methodology identity');
    await writeFile(join(root, file), 'authored source-tool DATA\n');
  }
  const quick = await identities('quick');
  for (const file of releaseOnly) assert.equal(quick[file], undefined,
    'unselected Release-only sources are not Quick collector inputs');
  assert.deepEqual(Object.keys(quick).sort(), [...quickFiles].sort());
  await assert.rejects(identities('other'), /Unknown measurement methodology mode/u);
  const base = fixture('release'), current = fixture('release');
  base.methodologySha256 = digest(JSON.stringify(original));
  await writeFile(join(root, releaseOnly[0]), 'different actual cold collector DATA');
  current.methodologySha256 = digest(JSON.stringify(await identities('release')));
  assert.equal(compareReports(base, current, policy).comparable, false);
  assert.match(compareReports(base, current, policy).reasons.join(';'), /methodology/u);
});

test('Release pre-admission report retains its actual selected methodology file hashes', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-health-methodology-report-')), output = join(root, 'report');
  const result = spawnSync(process.execPath, [new URL('./health-monitor.mjs', import.meta.url).pathname,
    'release', '--output', output], {encoding: 'utf8'});
  assert.equal(result.status, 2, result.stderr);
  const report = JSON.parse(await readFile(join(output, 'report.json')));
  assert.equal(report.status, 'incomplete'); assert.equal(report.guardExitCode, undefined);
  assert(Object.hasOwn(report.methodologyFiles, 'adapters/host-node/fixtures/mock-project-effect-protocol.fixture.mjs'));
  assert(Object.hasOwn(report.methodologyFiles, 'scripts/health-release-artifacts.py'));
  for (const [file, hash] of Object.entries(report.methodologyFiles)) {
    assert.equal(hash, digest(await readFile(new URL('../' + file, import.meta.url))));
  }
  assert.equal(report.methodologySha256, digest(JSON.stringify({policy: report.config, fixtureFiles: report.methodologyFiles})));
  assert.ok(report.metrics.some(row => row.id === 'required-release-inputs'));
  assert.match(await readFile(join(output, 'summary.md'), 'utf8'), /incomplete/u);
});
test('different source SHAs compare when each artifact is bound to its actual source', () => {
  const current = fixture(); current.source.sha = current.artifacts[0].sourceSha = 'b'.repeat(40);
  current.sourceAfter = structuredClone(current.source);
  assert.equal(compareReports(fixture(), current, policy).comparable, true);
});
test('missing samples, required observations and unreviewed baselines cannot pass', () => {
  const report = fixture(); report.metrics = requiredQuickMetrics();
  assert.equal(finishReport(report).status, 'incomplete'); assert.equal(report.exitCode, 2);
  const base = fixture(); delete base.baseline;
  assert.equal(compareReports(base, fixture(), policy).comparable, false);
  report.metrics = fixture().metrics;
  const metric = report.metrics.find(row => row.id === 'warm-select'); metric.samples = samples(1, 9);
  assert.equal(finishReport(report).status, 'incomplete');
  metric.samples[0].verified = false; assert.equal(finishReport(report).status, 'error');
});
test('first run has no invented baseline or regression-free claim; optional platform missing is explicit', () => {
  const report = fixture(); report.comparison = {available: false};
  report.metrics.push({id: 'native', target: 'native', kind: 'size', required: false, status: 'incomplete', reason: 'unmeasured'});
  assert.equal(finishReport(report).exitCode, 0);
  assert.match(markdown(report), /Comparison unavailable/); assert.match(markdown(report), /unmeasured/);
  assert.equal(report.formalAcceptance, false);
});
test('summary keeps all samples/range and withholds small-sample formal p95', () => {
  const rows = [1, 2, 3, 4, 20].map(ms => samples(ms, 1)[0]);
  const summary = summarize(rows, 30);
  assert.equal(summary.medianMs, 3); assert.equal(summary.p95Ms, null);
  assert.deepEqual(summary.referenceRangeMs, [1, 20]); assert.equal(rows.length, 5);
});
test('normal pack adapter uses actual JSON filenames/versions, not a development filename', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-health-pack-unit-'));
  const names = ['client-wire', 'sdk', 'node', 'run-host-core', 'local-node']; let calls = 0;
  const packages = await packDistributionPackages({repository: root, destination: root,
    run: async (cmd, args, cwd) => {
      const name = names[calls++], file = `actual-${name}-1.2.3.tgz`;
      assert.equal(cmd, 'npm'); assert.equal(args[0], 'pack'); assert.equal(cwd, join(root, 'packages', name));
      assert(args.includes('--foreground-scripts=false'));
      await writeFile(join(root, file), 'unit');
      return {stdout: JSON.stringify([{name: '@actql/' + name, version: '1.2.3', filename: file, size: 4}])};
    }});
  assert.equal(calls, 5); assert(packages.every(row => row.file.endsWith('1.2.3.tgz') && row.sha256 === digest('unit')));
});
test('Compare runs offline with no git/npm/moon executables and never changes its inputs', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-health-compare-unit-'));
  const base = join(root, 'base.json'), current = join(root, 'current.json'), output = join(root, 'out');
  const before = JSON.stringify(fixture()); await writeFile(base, before); await writeFile(current, before);
  const result = spawnSync(process.execPath, [new URL('./health-monitor.mjs', import.meta.url).pathname,
    'compare', '--base', base, '--current', current, '--output', output], {env: {...process.env, PATH: '/nonexistent'}, encoding: 'utf8'});
  assert.equal(result.status, 0, result.stderr); assert.equal(await readFile(base, 'utf8'), before);
  assert.equal(await readFile(current, 'utf8'), before);
  assert.deepEqual((await readdir(output)).sort(), ['report.json', 'summary.md']);
});

async function writePythonHealthOriginals(directory, report, python) {
  const source = report.source.sha;
  const output = spawnSync(python, ['-I', '-B', '-c', `
import hashlib, json, pathlib, sys, zipfile
root = pathlib.Path(sys.argv[1]); (root / 'wheels').mkdir(parents=True)
source = sys.argv[2]; version = '0.0.3'; wheels = []
for name, requires in [('actql-sdk', ['httpx==0.28.1', 'rfc8785==0.1.4']),
                       ('actql-local-runtime', ['wasmtime==38.0.0']),
                       ('actql', ['actql-sdk==0.0.3', 'actql-local-runtime==0.0.3'])]:
    stem = name.replace('-', '_') + '-' + version
    tag = 'py3-none-manylinux_2_28_x86_64' if name == 'actql-local-runtime' else 'py3-none-any'
    wheel = root / 'wheels' / (stem + '-' + tag + '.whl')
    with zipfile.ZipFile(wheel, 'w') as archive:
        archive.writestr(stem + '.dist-info/METADATA', f'Name: {name}\\nVersion: {version}\\n' +
                         ''.join('Requires-Dist: ' + item + '\\n' for item in requires))
        archive.writestr(stem + '.dist-info/WHEEL', 'Tag: ' + tag + '\\n')
        if name == 'actql':
            for entry in ['__init__.py', '__init__.pyi', 'py.typed']:
                archive.writestr('actql/' + entry, '')
    contents = wheel.read_bytes()
    wheels.append(dict(distribution=name, file=wheel.name, bytes=len(contents), sha256=hashlib.sha256(contents).hexdigest()))
cohort = dict(source_sha=source, package_version=version, platform='linux-x64', core_abi=91, wheels=wheels,
              host_capacity_sha256=None, runtime_executed=False, public_local_accepted=False,
              recovery_accepted=False, published=False)
for name in ('artifact', 'module', 'duckdb', 'image', 'engine_recipe'):
    cohort[name + '_sha256'] = 'a' * 64
cohort['release_metadata'] = dict(version=version, source_package_version='0.0.0.dev0',
    source_artifact_sha256='b' * 64, transforms=[dict(file=name, before_sha256='b' * 64, after_sha256='a' * 64)
    for name in ['stages/python-product/pyproject.toml', 'stages/python-sdk/pyproject.toml',
                 'stages/python-local-runtime/pyproject.toml', 'stages/python-local-runtime/src/actql_local_runtime/artifact.json']])
(root / 'cohort.json').write_text(json.dumps(cohort))
`, directory, source], {encoding: 'utf8', timeout: 15_000});
  assert.equal(output.status, 0, output.stderr);
  const path = join(directory, 'cohort.json'), cohortBytes = await readFile(path);
  const cohort = JSON.parse(cohortBytes), cohortSha256 = digest(cohortBytes);
  report.pythonReleaseCohort = {path, sha256: cohortSha256};
  for (const wheel of cohort.wheels) report.artifacts.push({name: wheel.distribution, version: cohort.package_version,
    sourceSha: source, artifactKind: 'wheel', file: wheel.file, acquisitionBytes: wheel.bytes, sha256: wheel.sha256});
  const {version, executableSha256} = report.environment.pythonRuntime;
  for (const metric of report.metrics.filter(row => row.target === 'python' && row.kind === 'latency')) {
    const wallMs = {'warm-result': 300, 'cold-existing': 1000}[metric.id] ?? 10;
    for (const sample of metric.samples) sample.wallNs = wallMs * 1e6;
    const raw = {sourceSha: source, cohortSha256, executionPath: 'python-sdk',
      protocol: {adapter: 'python', operation: metric.id}, environment: {python: version, pythonExecutableSha256: executableSha256},
      installedPayloadsUnchanged: true, cleanup: {closed: true},
      latency: [{operation: metric.id, mode: 'final', profiled: false, fixtureSha256: metric.fixtureSha256, samples: metric.samples}]};
    const bytes = JSON.stringify(raw);
    metric.evidence = join(directory, metric.id + '.json');
    metric.evidenceSha256 = digest(bytes);
    await writeFile(metric.evidence, bytes);
  }
}

test('Release Health comparison and offline replay use the selected policy from both original wheel cohorts', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-health-python-compare-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const locator = spawnSync('python3', ['-I', '-B', '-c', 'import sys; print(sys.executable)'], {encoding: 'utf8'});
  assert.equal(locator.status, 0, locator.stderr);
  const python = locator.stdout.trim(), base = fixture('release'), current = fixture('release');
  current.source.sha = 'b'.repeat(40); current.sourceAfter.sha = current.source.sha;
  for (const artifact of current.artifacts) artifact.sourceSha = current.source.sha;
  const native = current.artifacts.find(row => row.name === 'native-products-installed');
  native.installedInventory.sourceSha = current.source.sha;
  native.sha256 = digest(JSON.stringify(native.installedInventory));
  current.nativeInstalledInventoryAfter = structuredClone(native.installedInventory);
  await writePythonHealthOriginals(join(root, 'base-cohort'), base, python);
  await writePythonHealthOriginals(join(root, 'current-cohort'), current, python);
  const basePath = join(root, 'base.json'), currentPath = join(root, 'current.json');
  const baseBytes = JSON.stringify(base), currentBytes = JSON.stringify(current);
  await writeFile(basePath, baseBytes); await writeFile(currentPath, currentBytes);
  await applyComparison(current, {base: basePath, python});
  assert.equal(current.comparison.comparable, true, JSON.stringify(current.comparison.reasons));
  assert.equal(current.comparison.status, 'pass');
  const replay = (label, currentFile) => {
    const output = join(root, label);
    const result = spawnSync(process.execPath, [new URL('./health-monitor.mjs', import.meta.url).pathname,
      'compare', '--base', basePath, '--current', currentFile, '--output', output, '--python', python],
    {env: {...process.env, PATH: '/nonexistent'}, encoding: 'utf8', timeout: 30_000});
    return {result, output};
  };
  const valid = replay('valid', currentPath);
  assert.equal(valid.result.status, 0, valid.result.stderr);
  const compared = JSON.parse(await readFile(join(valid.output, 'report.json')));
  for (const metric of ['warm-result', 'cold-existing']) {
    assert.equal(compared.verdicts.find(row => row.target === 'python' && row.metric === metric)?.status, 'pass');
  }
  assert.equal(await readFile(basePath, 'utf8'), baseBytes);
  assert.equal(await readFile(currentPath, 'utf8'), currentBytes);

  const foreign = structuredClone(current);
  foreign.pythonReleaseCohort = base.pythonReleaseCohort;
  await assert.rejects(applyComparison(foreign, {base: basePath, python}), /cohort differs from the selected source/u);
  const modified = structuredClone(current);
  modified.metrics.find(row => row.target === 'python' && row.id === 'warm-result').samples[0].wallNs++;
  await assert.rejects(applyComparison(modified, {base: basePath, python}), /samples differ from their original measurements/u);
  const archived = join(root, 'base-cohort', 'wheels', base.artifacts.find(row => row.artifactKind === 'wheel').file);
  const originalWheel = await readFile(archived);
  await writeFile(archived, Buffer.concat([originalWheel, Buffer.from('changed')]));
  try {
    await assert.rejects(applyComparison(structuredClone(current), {base: basePath, python}), /Python release wheel bytes changed/u);
  } finally {await writeFile(archived, originalWheel);}
  const missing = structuredClone(current);
  delete missing.pythonReleaseCohort;
  const missingPath = join(root, 'missing.json');
  await writeFile(missingPath, JSON.stringify({...missing, latencyProfile: 'python-v0.0.3-public'}));
  const refused = replay('refused', missingPath);
  assert.equal(refused.result.status, 3, refused.result.stderr);
  assert.match(refused.result.stderr, /Missing original Python Health cohort/u);
  for (const artifact of missing.artifacts.filter(row => row.artifactKind === 'wheel')) artifact.version = '0.0.1';
  await applyComparison(missing, {base: basePath, python});
  assert.equal(missing.comparison.comparable, false);
  assert.match(missing.comparison.reasons.join('\n'), /current: incomplete required profile measurements/u);
});
test('source/config and gated workflow declare exact Quick 10/5 and fail closed', async () => {
  assert.deepEqual(policy.quick, {warmSamples: 10, coldSamples: 5});
  assert.deepEqual(policy.release, {warmSamples: 100, coldSamples: 30});
  const workflow = await readFile(new URL('../.github/workflows/health-monitor.yml', import.meta.url), 'utf8');
  assert.doesNotMatch(workflow, /ACTQL_MAIN_CI_ENABLED/);
  assert.match(workflow, /repository.visibility == 'public'/);
  assert.match(workflow, /toJSON\(github.event.repository.private\) == 'false'/);
  assert.match(workflow, /retention-days: 30/); assert.match(workflow, /npm run health:quick/);
  assert.doesNotMatch(workflow, /ACTQL_HEALTH_MONITOR_ENABLED/);
  const guard = "github.event.repository.visibility == 'public' && toJSON(github.event.repository.private) == 'false'";
  for (const job of Object.values(parse(workflow).jobs)) {
    assert(job.if.startsWith('${{ ' + guard));
    for (const [visibility, privateFlag, expected] of [
      ['public', false, true],
      [undefined, false, false], ['private', true, false],
      ['public', undefined, false], ['public', null, false],
      ['public', 'false', false], ['public', false, true]]) {
      assert.equal(runInNewContext(guard, {
        github: {event: {repository: {visibility, private: privateFlag}}}, toJSON: JSON.stringify}), expected);
    }
  }
});
test('invalid flags and missing Release fixtures are explicit rather than a successful stub', () => {
  assert.throws(() => parseArguments(['compare', '--base', 'x']));
  assert.throws(() => parseArguments(['quick', '--cap', '0']));
  assert.equal(parseArguments(['release']).mode, 'release');
});
test('empty reports and missing before/after evidence cannot qualify a baseline', () => {
  const current = fixture(); current.metrics = [];
  assert.equal(finishReport(current).status, 'incomplete');
  assert.equal(compareReports(fixture(), current, policy).comparable, false);
  const base = fixture(); delete base.sourceAfter;
  assert.equal(compareReports(base, fixture(), policy).comparable, false);
});
test('CLI parse failure still saves JSON/Markdown and preserves an existing output', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-health-error-unit-'));
  const output = join(root, 'existing'); await mkdir(output); await writeFile(join(output, 'sentinel'), 'keep');
  const result = spawnSync(process.execPath, [new URL('./health-monitor.mjs', import.meta.url).pathname,
    'compare', '--base', join(root, 'absent'), '--current', join(root, 'absent'), '--output', output], {encoding: 'utf8'});
  assert.equal(result.status, 3); assert.equal(await readFile(join(output, 'sentinel'), 'utf8'), 'keep');
  const path = result.stderr.match(/Report: (.+)/u)?.[1]; assert.ok(path, result.stderr);
  const report = JSON.parse(await readFile(join(path, 'report.json')));
  assert.equal(report.status, 'error'); assert.ok(report.errors[0].message);
  assert.match(await readFile(join(path, 'summary.md'), 'utf8'), /Error \(runner\)/);
});
test('original failed formal observations are errors; incomplete assessments stay incomplete', () => {
  assert.equal(formalCollectorVerdict({firstFailure: {message: 'original arithmetic refusal'}, latency: []}).status, 'error');
  assert.equal(formalCollectorVerdict({latency: [{samples: [{verified: false}]}]}).status, 'error');
  assert.equal(formalCollectorVerdict({latency: [], assessments: []}).status, 'incomplete');
  assert.equal(formalCollectorVerdict({latency: [{samples: samples(1)}]}).status, 'incomplete');
  assert.equal(formalCollectorVerdict({latency: [{samples: samples(1)}], assessments: [{status: 'failed'}]}).status, 'regression');
});
test('original failed warm samples are retained without a cold retry or new public operation', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-health-failed-unit-')), emitted = [];
  const original = new Error('original synthetic unit failure'); let commands = 0;
  await assert.rejects(quickNodeMetrics({root, prepared: {consumer: 'unit-only'}, counts: {warmSamples: 10, coldSamples: 5},
    command: async () => {
      commands++;
      await writeFile(join(root, 'warm-observation.json'), JSON.stringify({cleanup: {closed: true},
        metrics: [{id: 'warm-select', samples: [{...samples(1, 1)[0], verified: false, completed: false, error: 'original'}]}]}));
      throw original;
    }, onMetric: async row => emitted.push(row)}), error => error === original);
  assert.equal(commands, 1); assert.equal(emitted[0].samples[0].error, 'original');
  assert.equal(emitted[0].samples[0].verified, false);
});
test('Release missing mandatory platform inputs exits incomplete before any Runtime build', async () => {
  assert.equal(missingReleaseInputs({}).length, 7);
  const root = await mkdtemp(join(tmpdir(), 'actql-health-release-unit-')), output = join(root, 'run');
  const result = spawnSync(process.execPath, [new URL('./health-monitor.mjs', import.meta.url).pathname,
    'release', '--output', output], {encoding: 'utf8'});
  assert.equal(result.status, 2, result.stderr);
  const report = JSON.parse(await readFile(join(output, 'report.json')));
  assert.equal(report.status, 'incomplete');
  assert.match(report.metrics.find(row => row.id === 'required-release-inputs').reason, /no build or formal workload started/);
  assert.equal(report.artifacts.length, 0); assert.equal(report.guardExitCode, undefined);
});
test('original guard exit is recorded for both normal success and admission refusal', () => {
  const success = finishReport(fixture()); recordGuardExit(success, 0);
  assert.equal(success.guardExitCode, 0); assert.equal(success.status, 'pass');
  const refused = finishReport(fixture()); recordGuardExit(refused, 1);
  assert.equal(refused.guardExitCode, 1); assert.equal(refused.status, 'error');
  assert.match(refused.errors[0].message, /Original guard exited 1/);
});
test('collector errors disqualify a reviewed baseline even with complete measurements', () => {
  const base = fixture(); base.errors.push({target: 'collector', message: 'original cleanup failure'});
  finishReport(base); assert.equal(base.status, 'error');
  const result = compareReports(base, fixture(), policy);
  assert.equal(result.comparable, false); assert.match(result.reasons.join(';'), /collector\/guard/);
});
test('fixed Quick inventory cannot lose Aggregate or mark all required observations optional', () => {
  const current = fixture(); current.metrics = current.metrics.filter(row => row.id !== 'warm-aggregate');
  for (const row of current.metrics) row.required = false;
  assert.equal(finishReport(current).status, 'incomplete');
  assert.equal(compareReports(fixture(), current, policy).comparable, false);
});
test('saved reports cannot reduce fixed ten warm or five cold samples to one', () => {
  for (const id of ['warm-select', 'cold-new-state-process-first-result-close']) {
    const current = fixture(), metric = current.metrics.find(row => row.id === id);
    metric.samples = metric.samples.slice(0, 1); metric.requiredSamples = 1; metric.required = false;
    assert.equal(finishReport(current).status, 'incomplete');
    assert.equal(compareReports(fixture(), current, policy).comparable, false);
  }
});
test('build and artifact-reuse reference timing never gates compatible size or runtime metrics', () => {
  const base = fixture(), current = fixture();
  base.metrics.push({id: 'build-packaging', target: 'distribution', kind: 'reference', value: 100, unit: 'ms',
    required: true, evidence: 'unit', fixtureSha256: digest('normal prepack')});
  current.metrics.push({...base.metrics.at(-1), value: 1, fixtureSha256: digest('verified artifact reuse')});
  const result = compareReports(base, current, policy);
  assert.equal(result.status, 'pass'); assert.equal(result.comparable, true);
  assert(!result.verdicts.some(row => row.metric === 'build-packaging'));
});
test('saved size regression preserves its expected guard exit and remains comparable on round trip', () => {
  const base = fixture(), current = fixture(); current.metrics[0].value = 1250;
  current.comparison = compareReports(base, current, policy); finishReport(current); recordGuardExit(current, 1);
  const restored = JSON.parse(JSON.stringify(current));
  assert.equal(restored.status, 'regression'); assert.equal(restored.errors.length, 0);
  const result = compareReports(base, restored, policy);
  assert.equal(result.comparable, true); assert.equal(result.status, 'regression');
  const mismatch = finishReport(fixture()); mismatch.guardExitCode = 1;
  assert.equal(compareReports(base, mismatch, policy).comparable, false);
});
test('ordinary Python short-query fixtures exactly match the Node independent literal and parameter oracles', () => {
  const script = new URL('./benchmark-ordinary-processes.py', import.meta.url).pathname;
  const result = spawnSync('python3', ['-I', '-B', '-c',
    'import json,runpy,sys;print(json.dumps(runpy.run_path(sys.argv[1])["SMALL_QUERIES"]))', script], {encoding: 'utf8'});
  assert.equal(result.status, 0, result.stderr);
  const fixtures = JSON.parse(result.stdout);
  for (const operation of ['warm-join', 'warm-union', 'warm-decimal-sum', 'warm-parameters', 'warm-unicode']) {
    // Python accepts bindings in sql keyword arguments; Node uses the separate
    // bindings argument. Compare their values without equating API shapes.
    const {parameters, ...nodeFixture} = nodeWarmSmallQueryFixtures.find(row => row.operation === operation);
    const pythonFixture = parameters === undefined ? nodeFixture
      : {...nodeFixture, options: {...nodeFixture.options, parameters}};
    assert.deepEqual(fixtures[operation], pythonFixture);
  }
});
test('installed and raw-browser bytes report deltas without inventing an unspecified size gate', () => {
  for (const id of ['installed:node-local', 'browser-raw']) {
    const base = fixture(), current = fixture(); current.metrics.find(row => row.id === id).value = 5000;
    const result = compareReports(base, current, policy), delta = result.verdicts.find(row => row.metric === id);
    assert.equal(result.status, 'pass'); assert.equal(delta.absoluteDelta, 4000);
    assert.equal(delta.relativeDelta, 4); assert.match(delta.reason, /no configured gate/);
  }
});
test('zero-option measurement selects an existing reviewed platform baseline without changing it', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-health-default-unit-'));
  const directory = join(root, 'benchmarks/health/baselines'); await mkdir(directory, {recursive: true});
  const path = join(directory, 'linux-x64.json');
  for (const mode of ['quick', 'release']) {
    const base = fixture(mode), report = fixture(mode);
    const bytes = JSON.stringify(base); await writeFile(path, bytes);
    await applyComparison(report, {}, root);
    assert.equal(report.comparison.available, true); assert.equal(report.comparison.comparable, true);
    assert.equal(report.comparison.baselineId, base.baseline.id);
    assert.equal(report.comparison.baselineSelection, 'default'); assert.equal(report.comparison.baselinePath, path);
    assert.equal(report.comparison.baselineSha256, digest(bytes)); assert.equal(finishReport(report).exitCode, 0);
    assert.equal(await readFile(path, 'utf8'), bytes);
  }
});
test('absent default baseline remains measurement-only and never creates or adopts a baseline', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-health-absent-unit-')), report = fixture();
  await applyComparison(report, {}, root);
  assert.equal(report.comparison.available, false); assert.equal(report.comparison.baselineSelection, 'default');
  assert.equal(finishReport(report).exitCode, 0);
  assert.deepEqual(await readdir(root), []);
});
test('explicit baseline overrides the default and a missing override never falls back', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-health-override-unit-'));
  const directory = join(root, 'benchmarks/health/baselines'); await mkdir(directory, {recursive: true});
  const defaultPath = join(directory, 'linux-x64.json'); await writeFile(defaultPath, '{malformed default');
  const explicit = join(root, 'selected.json'), base = fixture(); base.baseline.id = 'synthetic-explicit-unit-only';
  await writeFile(explicit, JSON.stringify(base));
  const report = fixture(); await applyComparison(report, {base: explicit}, root);
  assert.equal(report.comparison.comparable, true); assert.equal(report.comparison.baselineSelection, 'explicit');
  assert.equal(report.comparison.baselineId, base.baseline.id); assert.equal(report.comparison.baselinePath, explicit);
  const missing = fixture();
  await assert.rejects(applyComparison(missing, {base: join(root, 'absent.json')}, root), {code: 'ENOENT'});
  assert.equal(finishReport(missing).status, 'error');
  assert.equal(await readFile(defaultPath, 'utf8'), '{malformed default');
});
test('incompatible or unreviewed default evidence is rejected, not treated as optional absence', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-health-incompatible-unit-'));
  const directory = join(root, 'benchmarks/health/baselines'); await mkdir(directory, {recursive: true});
  const path = join(directory, 'linux-x64.json');
  for (const mismatch of ['cpu', 'review', 'mode']) {
    const base = fixture(), report = fixture();
    if (mismatch === 'cpu') {base.environment.cpuModel = 'other CPU'; base.environmentAfter = structuredClone(base.environment);}
    else if (mismatch === 'review') delete base.baseline;
    else report.mode = 'release'; // Release uses the same default selection, retaining strict methodology compatibility.
    await writeFile(path, JSON.stringify(base)); await applyComparison(report, {}, root);
    assert.equal(report.comparison.available, true); assert.equal(report.comparison.comparable, false);
    assert.equal(report.comparison.baselineSelection, 'default'); assert.equal(finishReport(report).exitCode, 2);
    assert.ok(report.comparison.reasons.length);
  }
});
test('malformed default baseline preserves its error and never becomes a measurement-only pass', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-health-malformed-unit-'));
  const directory = join(root, 'benchmarks/health/baselines'); await mkdir(directory, {recursive: true});
  const path = join(directory, 'linux-x64.json');
  for (const bytes of ['{bad json', 'null']) {
    const report = fixture(); await writeFile(path, bytes);
    await assert.rejects(applyComparison(report, {}, root));
    assert.equal(report.comparison.available, true); assert.equal(report.comparison.comparable, false);
    assert.equal(report.comparison.status, 'error'); assert.equal(finishReport(report).exitCode, 3);
    assert.equal(await readFile(path, 'utf8'), bytes);
  }
});


test('Release comparison binds the selected Python runtime independently of its controller', () => {
  const runtime = {version: '3.12.12', executableSha256: '5'.repeat(64)};
  const withRuntime = value => {
    const report = fixture('release');
    report.environment.pythonRuntime = value;
    report.environmentAfter = structuredClone(report.environment);
    return report;
  };
  const base = withRuntime(runtime);
  for (const changed of [
    {...runtime, version: '3.13.0'},
    {...runtime, executableSha256: '6'.repeat(64)},
    undefined,
    {version: 'unavailable', executableSha256: 'unavailable'},
  ]) {
    const comparison = compareReports(base, withRuntime(changed), policy);
    assert.equal(comparison.comparable, false, 'controller identity cannot substitute for the selected venv runtime');
    assert.match(comparison.reasons.join(';'), /pythonRuntime/u);
  }
  for (const malformed of [
    {version: [runtime.version], executableSha256: runtime.executableSha256},
    {version: runtime.version, executableSha256: [runtime.executableSha256]},
    {version: runtime.version},
  ]) {
    assert.equal(compareReports(withRuntime(malformed), withRuntime(malformed), policy).comparable, false,
      'identical malformed runtime metadata cannot establish compatibility');
  }
  assert.equal(compareReports(base, withRuntime({...runtime}), policy).comparable, true);
});


test('Release identity observes only the selected Python interpreter metadata', async () => {
  const probe = spawnSync('python3', ['-I', '-B', '-c',
    'import json,platform,sys;print(json.dumps(dict(executable=sys.executable,version=platform.python_version())))'], {encoding: 'utf8'});
  assert.equal(probe.status, 0, probe.stderr);
  const selected = JSON.parse(probe.stdout), root = await mkdtemp(join(tmpdir(), 'actql-health-python-tool-'));
  await mkdir(join(root, 'bin'));
  await symlink(selected.executable, join(root, 'bin/python'));
  const expected = {version: selected.version,
    executableSha256: digest(await readFile(selected.executable))};
  assert.deepEqual(pythonRuntimeIdentity(root), expected);
  const observed = await environmentIdentity({pythonVenv: root, python: join(root, 'absent-controller')});
  assert.deepEqual(observed.pythonRuntime, expected);
  assert.match(observed.python, /^unavailable:/u, 'controller failure cannot substitute for selected runtime identity');
  assert.equal(Object.hasOwn(await environmentIdentity(), 'pythonRuntime'), false,
    'ordinary Quick without a venv retains its original environment shape');
  assert.throws(() => pythonRuntimeIdentity(join(root, 'absent')));
});

test('Release adapter rejects a collector using a different Python runtime', () => {
  const expected = {version: '3.12.12', executableSha256: '5'.repeat(64)};
  const original = {environment: {python: expected.version, pythonExecutableSha256: expected.executableSha256}};
  assert.doesNotThrow(() => assertPythonCollectorRuntime(original, expected));
  for (const changed of [
    {python: '3.13.0', pythonExecutableSha256: expected.executableSha256},
    {python: expected.version, pythonExecutableSha256: '6'.repeat(64)},
    {},
  ]) assert.throws(() => assertPythonCollectorRuntime({environment: changed}, expected));
});


test('missing selected Release interpreter saves its original error without starting a workload', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-health-python-missing-'));
  const result = spawnSync(process.execPath, [new URL('./health-monitor.mjs', import.meta.url).pathname,
    'release', '--python-venv', join(root, 'absent'), '--output', join(root, 'requested')], {encoding: 'utf8'});
  assert.equal(result.status, 3, result.stderr);
  const saved = result.stderr.match(/Report: (.+)/u)?.[1]; assert.ok(saved, result.stderr);
  const report = JSON.parse(await readFile(join(saved, 'report.json')));
  assert.equal(report.status, 'error');
  assert.match(report.errors[0].message, /ENOENT/u);
  assert.equal(report.guardExitCode, undefined, 'metadata failure precedes collector admission');
  assert.match(await readFile(join(saved, 'summary.md'), 'utf8'), /Error \(runner\)/u);
});


test('Native artifact adapter cannot publish installed observations before consumer verification', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-health-native-consumer-'));
  const manifestPath = join(root, 'release.json'), absent = join(root, 'absent-consumer');
  const source = 'a'.repeat(40);
  const manifest = {sourceSha: source, platforms: {'darwin-arm64': {}},
    packages: [{name: 'actql', version: '1.2.3', file: 'actql-1.2.3.tgz', bytes: 1,
      sha256: 'b'.repeat(64), files: [{path: 'package.json', bytes: 2}]}]};
  await writeFile(manifestPath, JSON.stringify(manifest));
  const text = await readFile(new URL('./health-monitor-release.mjs', import.meta.url), 'utf8');
  const start = text.indexOf('export async function releaseArtifacts(');
  const end = text.indexOf('export async function releaseMeasurements(', start);
  assert.ok(start >= 0 && end > start);
  // Isolate the existing adapter route. Archive verification is a fulfilled
  // dependency here; the real installed verifier is tested with tiny tar data.
  const selected = runInNewContext('(' + text.slice(start, end).replace('export ', '') + ')', {
    assert, readFile, join, platform: () => 'darwin', arch: () => 'arm64',
    verifyNativeCliRelease: async () => manifest, jsonDigest: value => digest(JSON.stringify(value)), digest,
  });
  const original = new Error('Selected installed consumer absent'), artifacts = [], metrics = [];
  let calls = 0;
  await assert.rejects(selected({options: {nativeManifest: manifestPath, nativeConsumer: absent},
    repository: root, source: {sha: source},
    command: async (_command, args) => {calls++; assert.ok(args.includes(absent)); throw original;},
    onArtifact: async row => artifacts.push(row), onMetric: async row => metrics.push(row)}), error => error === original);
  assert.equal(calls, 1);
  assert.equal(artifacts.length, 0, 'no unverified installed-size observation');
});


test('Native installed-byte inspection reuses the ordinary verifier without executable or SDK work', () => {
  const fixture = new URL('./fixtures/health-native-installed.py', import.meta.url).pathname;
  const inspector = new URL('./health-release-artifacts.py', import.meta.url).pathname;
  const result = spawnSync('python3', ['-I', '-B', fixture, inspector], {encoding: 'utf8'});
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(JSON.parse(result.stdout), {verifiedPackages: 2, refusedControls: 5, childExecutions: 0});
});


test('Native installed metrics cover only the selected platform while acquisition totals retain every package', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-health-native-sizes-'));
  const path = join(root, 'release.json'), source = 'a'.repeat(40);
  const names = ['@actql/cli-darwin-arm64', '@actql/cli-linux-x64-gnu', 'actql'];
  const manifest = {sourceSha: source, platforms: {'darwin-arm64': {}, 'linux-x64-gnu': {}},
    packages: names.map((name, i) => ({name, version: '1.2.3', file: `unit-${i}.tgz`, bytes: i + 10,
      sha256: 'b'.repeat(64), files: [{path: 'package.json', bytes: 2},
        {path: name === 'actql' ? 'bin/actql.mjs' : 'bin/actql-native-client', bytes: 3, sha256: 'c'.repeat(64)}]}))};
  const bytes = JSON.stringify(manifest); await writeFile(path, bytes);
  const text = await readFile(new URL('./health-monitor-release.mjs', import.meta.url), 'utf8');
  const start = text.indexOf('export async function releaseArtifacts('), end = text.indexOf('export async function releaseMeasurements(', start);
  const selected = runInNewContext('(' + text.slice(start, end).replace('export ', '') + ')', {
    assert, readFile, join, platform: () => 'darwin', arch: () => 'arm64',
    verifyNativeCliRelease: async () => manifest, jsonDigest: value => digest(JSON.stringify(value)), digest,
  });
  const installed = {sourceSha: source, cohortSha256: digest(bytes), platform: 'darwin-arm64',
    packages: Object.fromEntries(['actql', names[0]].map(name => [name,
      {installedBytes: 5, payloads: 2, inventorySha256: 'd'.repeat(64)}]))};
  const run = async observation => {
    const artifacts = [], metrics = [];
    const ready = await selected({options: {nativeManifest: path, nativeConsumer: join(root, 'consumer')},
      repository: root, source: {sha: source}, command: async () => ({stdout: JSON.stringify(observation)}),
      onArtifact: async row => artifacts.push(row), onMetric: async row => metrics.push(row)});
    return {ready, artifacts, metrics};
  };
  const result = await run(installed);
  assert.equal(result.ready, false, 'the absent Python cohort remains incomplete');
  assert.deepEqual(result.metrics.filter(row => row.target === 'native' && row.artifactKind === 'npm')
    .map(row => [row.id, row.value]), names.map((name, i) => [name, i + 10]));
  assert.deepEqual(result.metrics.filter(row => row.artifactKind === 'installed' && row.value !== undefined)
    .map(row => [row.id, row.value]), [['installed:' + names[0], 5], ['installed:actql', 5]]);
  const unmeasured = result.metrics.find(row => row.id === 'installed:' + names[1]);
  assert.equal(unmeasured.value, undefined); assert.equal(unmeasured.status, 'incomplete');
  assert.equal(unmeasured.required, false);
  const foreign = result.artifacts.find(row => row.name === names[1]);
  assert.equal(foreign.installedBytes, undefined); assert.equal(foreign.installedStatus, 'unmeasured');
  for (const changed of [{...installed, sourceSha: 'e'.repeat(40)}, {...installed, cohortSha256: 'e'.repeat(64)},
    {...installed, platform: 'linux-x64-gnu'}, {...installed, packages: {actql: installed.packages.actql}},
    {...installed, packages: {...installed.packages, actql: {...installed.packages.actql, installedBytes: 0}}}]) {
    await assert.rejects(run(changed));
  }
  const substituted = JSON.stringify({...manifest, unverifiedMetadata: 'different selected manifest'});
  await writeFile(path, substituted);
  await assert.rejects(run({...installed, cohortSha256: digest(substituted)}),
    /Selected Native manifest differs/u);
});

test('Release cannot omit its required installed Native payload metrics', () => {
  const current = fixture('release');
  current.metrics = current.metrics.filter(row => !(row.target === 'native' && row.artifactKind === 'installed'));
  assert.equal(finishReport(current).status, 'incomplete');
});

test('Release requires Native whole-run installed custody, including early collector failure', () => {
  const current = fixture('release');
  delete current.nativeInstalledInventoryAfter;
  delete current.nativeInstalledPayloadsUnchanged;
  assert.equal(finishReport(current).status, 'incomplete',
    'precollection payload verification alone is not an after observation');
});

test('Release rejects inconsistent Native installed snapshots and retains changed observations', () => {
  for (const mutate of [r => delete r.nativeInstalledInventoryAfter,
    r => delete r.nativeInstalledPayloadsUnchanged,
    r => r.artifacts.find(row => row.name === 'native-products-installed').sourceSha = 'b'.repeat(40),
    r => r.metrics.find(row => row.id === 'installed:actql').value++,
    r => r.artifacts.find(row => row.name === 'native-products-installed').installedBytes++]) {
    const current = fixture('release'); mutate(current);
    assert.equal(finishReport(current).status, 'incomplete');
  }
  const current = fixture('release'); current.nativeInstalledInventoryAfter.cohortSha256 = 'b'.repeat(64);
  assert.equal(finishReport(current).status, 'error');
  for (const mutate of [value => value.cohortSha256 = [value.cohortSha256],
    value => value.packages.actql.inventorySha256 = [value.packages.actql.inventorySha256]]) {
    const malformed = fixture('release');
    const artifact = malformed.artifacts.find(row => row.name === 'native-products-installed');
    mutate(artifact.installedInventory); artifact.sha256 = digest(JSON.stringify(artifact.installedInventory));
    malformed.nativeInstalledInventoryAfter = structuredClone(artifact.installedInventory);
    assert.equal(finishReport(malformed).status, 'incomplete', 'identical malformed snapshots cannot qualify');
  }
  assert.equal(finishReport(fixture('release')).status, 'pass');
});

test('Native after-check uses the original read-only verifier even after collector failure', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-health-native-after-'));
  const helper = new URL('./health-release-artifacts.py', import.meta.url).pathname;
  const data = spawnSync('python3', ['-I', '-B', new URL('./fixtures/health-native-installed.py', import.meta.url).pathname,
    helper, root], {encoding: 'utf8'});
  assert.equal(data.status, 0, data.stderr);
  const {fixture: supplied, childExecutions} = JSON.parse(data.stdout);
  assert.equal(childExecutions, 0);
  const before = {name: 'native-products-installed', sha256: digest(JSON.stringify(supplied.observation)),
    installedInventory: supplied.observation};
  const options = {nativeManifest: supplied.manifest, nativeConsumer: supplied.consumer};
  const original = {target: 'collector', message: 'Original selected workload failed'};
  const report = () => ({source: {sha: supplied.source}, artifacts: [structuredClone(before)],
    errors: [structuredClone(original)], installedPayloadsUnchanged: true});
  let inspections = 0;
  const command = async (executable, args, settings) => {
    assert.equal(executable, 'python3'); assert.equal(settings.name, 'inspect-native-after');
    assert.deepEqual(args, ['-I', '-B', helper, '--native-installed', supplied.manifest, supplied.consumer, supplied.source]);
    inspections++;
    const result = spawnSync(executable, args, {encoding: 'utf8'});
    if (result.status !== 0) throw new Error(result.stderr);
    return {stdout: result.stdout};
  };
  const stable = report(); await verifyNativeInstalledAfter(stable, options, command);
  assert.equal(stable.nativeInstalledPayloadsUnchanged, true);
  assert.deepEqual(stable.nativeInstalledInventoryAfter, supplied.observation);
  assert.deepEqual(stable.errors, [original]);
  const manifest = await readFile(supplied.manifest);
  await writeFile(supplied.manifest, JSON.stringify({...JSON.parse(manifest), changedMetadata: 'unit-only'}));
  const changed = report(); await verifyNativeInstalledAfter(changed, options, command);
  assert.equal(changed.nativeInstalledPayloadsUnchanged, false);
  assert.equal(changed.installedPayloadsUnchanged, false);
  assert.deepEqual(changed.errors[0], original); assert.equal(changed.errors[1].target, 'native-package-after');
  assert.notDeepEqual(changed.nativeInstalledInventoryAfter, supplied.observation);
  await writeFile(supplied.manifest, manifest);
  const binary = join(supplied.consumer, 'node_modules', '@actql/cli-' + supplied.observation.platform, 'bin/actql-native-client');
  await writeFile(binary, 'CHANGED SYNTHETIC DATA; NEVER EXECUTE');
  const failed = report(); await verifyNativeInstalledAfter(failed, options, command);
  assert.equal(failed.nativeInstalledPayloadsUnchanged, false);
  assert.deepEqual(failed.errors[0], original); assert.match(failed.errors[1].message, /Installed payload differs/u);
  const absent = {artifacts: [], errors: []}; await verifyNativeInstalledAfter(absent, options, command);
  assert.deepEqual(absent, {artifacts: [], errors: []}); assert.equal(inspections, 3);
});


test('Linux Release selects the original Python wheel platform through the actual ordinary verifier', async t => {
  const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-health-linux-platform-', label: 'Linux wheel platform control'});
  t.after(() => scratch.passed());
  const repository = new URL('../', import.meta.url).pathname;
  const prepared = spawnSync('python3', ['-I', '-B', join(repository, 'scripts/fixtures/health-python-installed.py'), scratch.path],
    {encoding: 'utf8'});
  assert.equal(prepared.status, 0, prepared.stderr);
  const fixture = JSON.parse(prepared.stdout), original = JSON.parse(await readFile(fixture.manifest));
  const text = await readFile(new URL('./health-monitor-release.mjs', import.meta.url), 'utf8');
  const start = text.indexOf('export async function releaseArtifacts('), end = text.indexOf('export async function releaseMeasurements(', start);
  const adapter = runInNewContext('(' + text.slice(start, end).replace('export ', '') + ')', {
    assert, readFile, join, platform: () => 'linux', arch: () => 'x64', jsonDigest: value => digest(JSON.stringify(value)),
    digest, pythonInstalledInventory, JSON,
  });
  const launch = `import json, platform, runpy, sys
platform.system = lambda: 'Linux'
platform.machine = lambda: 'x86_64'
ordinary = runpy.run_path(sys.argv[1])
assert ordinary['platform_key']() == 'linux-x64-gnu'
inspection = runpy.run_path(sys.argv[2])
print(json.dumps(inspection['inspect'](*sys.argv[3:])))`;
  const inspect = () => spawnSync('python3', ['-I', '-B', '-c', launch,
    join(repository, 'scripts/benchmark-ordinary-processes.py'), join(repository, 'scripts/health-release-artifacts.py'),
    fixture.manifest, fixture.consumer, fixture.source], {encoding: 'utf8', timeout: 15_000});
  let inspections = 0;
  const measure = async selection => {
    await writeFile(fixture.manifest, JSON.stringify({...original, platform: selection}));
    const artifacts = [], metrics = [];
    await adapter({options: {pythonManifest: fixture.manifest, pythonConsumer: fixture.consumer}, repository,
      source: {sha: fixture.source}, async command() {
        inspections++;
        const result = inspect(); assert.equal(result.status, 0, result.stderr); return {stdout: result.stdout};
      }, onArtifact: async row => artifacts.push(row), onMetric: async metric => metrics.push(metric)});
    return {artifacts, metrics};
  };
  const accepted = await measure('linux-x64');
  assert.equal(accepted.artifacts.filter(row => row.artifactKind === 'wheel').length, 3);
  assert.equal(accepted.metrics.find(row => row.id === 'installed:python-products')?.value, fixture.installedBytes);
  const nativeLabel = await measure('linux-x64-gnu');
  assert.equal(nativeLabel.artifacts.length, 0);
  assert.equal(nativeLabel.metrics.find(row => row.id === 'python-platform-artifacts')?.status, 'incomplete');
  assert.equal(inspections, 1);
  const directRefusal = inspect();
  assert.equal(directRefusal.status, 1, directRefusal.stderr);
  assert.match(directRefusal.stderr, /manifest\['platform'\] == platform_key\('python'\)/u);
});

test('Python installed sizes measure product namespaces instead of wheel expansion bytes', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-health-python-data-'));
  const prepared = spawnSync('python3', ['-I', '-B',
    new URL('./fixtures/health-python-installed.py', import.meta.url).pathname, root], {encoding: 'utf8'});
  assert.equal(prepared.status, 0, prepared.stderr);
  const fixture = JSON.parse(prepared.stdout);
  const selected = JSON.parse(await readFile(fixture.manifest, 'utf8'));
  const text = await readFile(new URL('./health-monitor-release.mjs', import.meta.url), 'utf8');
  const start = text.indexOf('export async function releaseArtifacts('), end = text.indexOf('export async function releaseMeasurements(', start);
  const adapter = runInNewContext('(' + text.slice(start, end).replace('export ', '') + ')', {
    assert, readFile, join,
    platform: () => selected.platform === 'darwin-arm64' ? 'darwin' : 'linux',
    arch: () => selected.platform === 'darwin-arm64' ? 'arm64' : 'x64',
    verifyNativeCliRelease: async () => {throw new Error('No Native selection');},
    jsonDigest: value => digest(JSON.stringify(value)), digest, pythonInstalledInventory, JSON,
  });
  const artifacts = [], metrics = [];
  await adapter({options: {pythonManifest: fixture.manifest, pythonConsumer: fixture.consumer},
    repository: new URL('../', import.meta.url).pathname, source: {sha: fixture.source},
    command: async (command, args) => {
      const result = spawnSync(command, args, {encoding: 'utf8'});
      assert.equal(result.status, 0, result.stderr); return {stdout: result.stdout};
    }, onArtifact: async row => artifacts.push(row), onMetric: async row => metrics.push(row)});
  const installed = metrics.find(row => row.id === 'installed:python-products');
  assert.ok(installed, 'an actual installed observation is required');
  assert.equal(installed.value, fixture.installedBytes);
  for (const name of ['actql', 'actql-sdk', 'actql-local-runtime']) {
    const wheel = artifacts.find(row => row.name === name);
    assert.equal(wheel.unpackedBytes, fixture.unpackedBytes[name]);
    assert.equal(wheel.verifiedPayloadBytes, fixture.verifiedPayloadBytes[name]);
    assert.equal(wheel.installedBytes, undefined, 'archive expansion is not actual installed size');
  }
  const report = {artifacts, errors: [], installedPayloadsUnchanged: true};
  await verifyPythonInstalledAfter(report, {pythonConsumer: fixture.consumer});
  assert.equal(report.pythonInstalledPayloadsUnchanged, true);
  assert.equal(report.errors.length, 0);
  await writeFile(join(fixture.consumer, 'actql-1.2.3.dist-info/INSTALLER'), 'changed installer metadata');
  const original = {target: 'collector', message: 'original source-tool error'};
  report.errors.push(original);
  await verifyPythonInstalledAfter(report, {pythonConsumer: fixture.consumer});
  assert.equal(report.pythonInstalledPayloadsUnchanged, false);
  assert.equal(report.installedPayloadsUnchanged, false);
  assert.equal(report.errors[0], original);
  assert.match(report.errors[1].message, /changed after collection/u);
});


test('Python product inventory deduplicates namespaces and refuses foreign paths or payload bindings', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-health-python-scope-'));
  const prepared = spawnSync('python3', ['-I', '-B',
    new URL('./fixtures/health-python-installed.py', import.meta.url).pathname, root], {encoding: 'utf8'});
  assert.equal(prepared.status, 0, prepared.stderr);
  const fixture = JSON.parse(prepared.stdout);
  const inspected = spawnSync('python3', ['-I', '-B',
    new URL('./health-release-artifacts.py', import.meta.url).pathname,
    fixture.manifest, fixture.consumer, fixture.source], {encoding: 'utf8'});
  assert.equal(inspected.status, 0, inspected.stderr);
  const artifacts = JSON.parse(inspected.stdout);
  const duplicate = artifacts.map(row => ({...row, installedRoots: [...row.installedRoots, fixture.roots[0]]}));
  assert.equal((await pythonInstalledInventory(fixture.consumer, duplicate)).bytes, fixture.installedBytes);
  for (const name of ['..', '../foreign', '/outside', 'a\\b', '']) {
    const changed = structuredClone(artifacts); changed[0].installedRoots.push(name);
    await assert.rejects(pythonInstalledInventory(fixture.consumer, changed), /Unsafe installed wheel namespace/u);
  }
  const alias = join(root, 'consumer-alias'); await symlink(fixture.consumer, alias, 'dir');
  await assert.rejects(pythonInstalledInventory(alias, artifacts), /consumer cannot be linked/u);
  const linked = join(fixture.consumer, 'linked-product');
  await symlink(join(fixture.consumer, 'actql'), linked, 'dir');
  const changed = structuredClone(artifacts); changed[0].installedRoots.push('linked-product');
  await assert.rejects(pythonInstalledInventory(fixture.consumer, changed), /namespace cannot be linked/u);
  const foreign = structuredClone(artifacts); foreign[0].verifiedPayloads[0].sha256 = 'f'.repeat(64);
  await assert.rejects(pythonInstalledInventory(fixture.consumer, foreign), /Verified Python payload changed/u);
});

test('Release cannot omit its actual Python product installed observation', () => {
  const current = fixture('release');
  current.metrics = current.metrics.filter(row => row.id !== 'installed:python-products');
  assert.equal(finishReport(current).status, 'incomplete');
});


test('Release requires consistent actual Python installed before and after observations', () => {
  const missing = fixture('release'); delete missing.pythonInstalledInventoryAfter;
  assert.equal(finishReport(missing).status, 'incomplete');
  const changed = fixture('release'); changed.pythonInstalledInventoryAfter.sha256 = 'f'.repeat(64);
  assert.equal(finishReport(changed).status, 'error');
  const inconsistent = fixture('release'); inconsistent.pythonInstalledInventoryAfter.files[0].bytes++;
  assert.equal(finishReport(inconsistent).status, 'incomplete');
});

test('Release public E2E rejects old two-second cold limits and a lone maximum over200ms', () => {
  for (const [id, target, p95, maximum] of [['cold-existing', 'node-local', 300, 400],
    ['first-init', 'python', 1000, 1000], ['warm-select', 'node-local', 5, 201]]) {
    const report = fixture('release'), metric = report.metrics.find(row => row.id === id && row.target === target);
    for (const row of metric.samples) row.wallNs = p95 * 1e6;
    metric.samples.at(-1).wallNs = maximum * 1e6;
    const checked = finishReport(report);
    assert.equal(checked.status, 'regression'); assert.equal(checked.exitCode, 1);
    assert(checked.verdicts.some(row => row.metric === id && row.target === target && /200ms/u.test(row.reason)));
  }
});
test('Release cannot pass without complete samples, matching artifacts and a reviewed regression baseline', () => {
  const absent = fixture('release'); delete absent.comparison;
  assert.equal(finishReport(absent).status, 'incomplete');
  const short = fixture('release'); short.metrics.find(row => row.id === 'warm-select').samples.pop();
  assert.equal(finishReport(short).status, 'incomplete');
  const foreign = fixture('release'); foreign.artifacts[0].sourceSha = 'f'.repeat(40);
  assert.equal(compareReports(fixture('release'), foreign, policy).comparable, false);
  const mismatched = fixture('release'); mismatched.environment.buildSettings.load = 'concurrent';
  mismatched.environmentAfter = structuredClone(mismatched.environment);
  assert.equal(compareReports(fixture('release'), mismatched, policy).comparable, false);
});
test('Release compares p95 and maximum as regressions even when the median is unchanged and under200ms', () => {
  const base = fixture('release'), current = fixture('release');
  for (const report of [base, current]) {
    const metric = report.metrics.find(row => row.id === 'warm-select' && row.target === 'node-local');
    for (const row of metric.samples) row.wallNs = 100e6;
  }
  current.metrics.find(row => row.id === 'warm-select' && row.target === 'node-local').samples.at(-1).wallNs = 190e6;
  const compared = compareReports(base, current, policy);
  assert.equal(compared.comparable, true); assert.equal(compared.status, 'regression');
  const row = compared.verdicts.find(row => row.metric === 'warm-select' && row.target === 'node-local');
  assert.deepEqual(row.statistics.medianMs, {before: 100, after: 100, absoluteDelta: 0});
  assert.deepEqual(row.statistics.maxMs, {before: 100, after: 190, absoluteDelta: 90});
  assert.equal(row.cpu.before.available, true); assert.equal(row.cpu.after.available, true);
});
test('Release refuses a timer stopped before Result or a Result materialized after close began', () => {
  for (const timing of [
    {kind: 'public-result', startNs: 1, observedNs: 300e6, endNs: 3},
    {kind: 'process-result-close', startNs: 1, observedNs: 8, closeStartNs: 3, closeEndNs: 9, endNs: 10},
  ]) {
    const report = fixture('release');
    const metric = report.metrics.find(row => row.id === (timing.kind === 'public-result' ? 'warm-select' : 'cold-existing') && row.target === 'node-local');
    metric.samples[0].publicTiming = timing;
    assert.equal(finishReport(report).status, 'regression');
  }
  const report = fixture('release'); delete report.metrics.find(row => row.id === 'warm-select').samples[0].publicTiming;
  assert.equal(finishReport(report).status, 'incomplete');
});

test('Release retains unavailable CPU/RSS and refuses unlike resource scopes', () => {
  for (const key of ['cpuScope', 'peakRssBytes', 'rssScope']) {
    const report = fixture('release'); delete report.metrics.find(row => row.id === 'warm-select').samples[0][key];
    assert.equal(finishReport(report).status, 'incomplete');
  }
  const base = fixture('release'), current = fixture('release');
  for (const row of current.metrics.find(row => row.id === 'warm-select').samples) row.cpuScope = 'foreign CPU scope';
  const compared = compareReports(base, current, policy);
  assert.equal(compared.status, 'incomplete');
  assert(compared.verdicts.some(row => /scopes differ/u.test(row.reason)));
});

test('Release reports malformed metric identity as error without bypassing the fixed profile', () => {
  for (const id of [undefined, null, 7, '']) {
    const report = fixture('release');
    report.metrics.find(row => row.id === 'warm-select' && row.target === 'node-local').id = id;
    const checked = finishReport(report);
    assert.equal(checked.status, 'error');
    assert(checked.verdicts.some(row => row.reason === 'Invalid measurement identity'));
  }
});


// Real collector children around a synthetic public-port module. These are
// clock/protocol tests, not ordinary ActQL performance or Source acceptance.
async function coldCollectorFixture(t,{unknown=false}={}) {
  const root=await mkdtemp(join(tmpdir(),'actql-health-cold-state-unit-'));
  const consumer=join(root,'consumer'),module=join(consumer,'node_modules/@actql/node');await mkdir(module,{recursive:true});
  const code=`import assert from 'node:assert/strict';import {mkdir,appendFile} from 'node:fs/promises';
export async function open({stateDir}) {
 await mkdir(stateDir,{recursive:true});const event=kind=>appendFile(stateDir+'/events',JSON.stringify({kind,pid:process.pid})+'\\n');
 await event('open');
 return {async startSource(text,options) {
  assert.equal(text,'SELECT 1 AS id');await event('submit');
  if(${unknown}&&options.requestId.startsWith('health-cold-existing-state-'))throw new Error('Synthetic Unknown; no resend');
  return {ref:{id:process.pid+'-'+options.requestId},wait:async()=>({status:'succeeded'}),
   status:async()=>({status:'succeeded',revision:1}),result:()=>({all:async()=>[{id:1}]})};
 },attach(){assert.fail('No Saved-only cold existing');},
 sql(text){return {all:async()=>text.includes('JOIN rhs')?[{id:1,label:'joined'}]:text.includes('SUM(amount)')?[{total:'4.00'}]:[{id:Number(text.match(/SELECT (\\d+) AS id/)?.[1]??1)}]};},
 async close(){await event('close');}};
}`;
  await writeFile(join(module,'index.mjs'),code);
  const commands=[],metrics=[];
  const command=async(executable,args,options)=>{commands.push(JSON.parse(args[2]));return execute(executable,args,{...options,timeout:10000});};
  return {root,commands,metrics,run:()=>quickNodeMetrics({root,prepared:{consumer},counts:{warmSamples:1,coldSamples:1},
    command,onMetric:async metric=>metrics.push(structuredClone(metric))})};
}

test('Quick cold existing and new states use separate actual public children and parent clocks',async t=>{
  const f=await coldCollectorFixture(t);await f.run();
  assert.deepEqual(f.commands.map(x=>x.kind),['warm','prepare-existing-state','cold-existing-state','cold-new-state']);
  const existing=f.metrics.find(x=>x.id==='cold-existing-state-process-first-result-close');
  const fresh=f.metrics.find(x=>x.id==='cold-new-state-process-first-result-close');
  assert.notEqual(existing.samples[0].pid,fresh.samples[0].pid);
  const seed=JSON.parse(await readFile(join(f.root,'cold-existing-preparation.json')));
  assert.equal(seed.cleanup.closed,true);assert.equal(existing.samples[0].stateDir,seed.stateDir);
  assert.notEqual(existing.samples[0].originalRunSha256,seed.originalRunSha256);
  assert.notEqual(fresh.samples[0].stateDir,seed.stateDir);
  for(const row of [existing.samples[0],fresh.samples[0]]) {
    assert.equal(row.verified,true);assert(row.firstResultNs>0&&row.firstResultNs<=row.wallNs);
    assert.deepEqual(row.phaseSpans.map(x=>x.name),['product-import','public-open','new-run-submission',
      'wait-execution-publication','all-result-rows','first-close']);
    for(let n=0;n<row.phaseSpans.length;n++) {
      const span=row.phaseSpans[n];assert(span.completed&&span.endNs>=span.startNs);
      if(n)assert(span.startNs>=row.phaseSpans[n-1].endNs);
    }
    assert(row.phaseSpans.reduce((sum,x)=>sum+x.endNs-x.startNs,0)<=row.wallNs);
    assert(row.unobservedHostPhases.includes('initial activation'));
  }
  assert.equal(measurementProfile('quick').filter(x=>x.id.endsWith('-process-first-result-close')).length,2);
});

test('Quick cold Unknown retains failed sample and unobserved first Result without a new-state retry',async t=>{
  const f=await coldCollectorFixture(t,{unknown:true});await assert.rejects(f.run(),/exit 1/);
  assert.deepEqual(f.commands.map(x=>x.kind),['warm','prepare-existing-state','cold-existing-state']);
  const metric=f.metrics.find(x=>x.id==='cold-existing-state-process-first-result-close');
  assert.equal(metric.samples.length,1);assert.equal(metric.samples[0].verified,false);
  assert.equal(metric.samples[0].firstResultNs,null);
  const first=f.metrics.find(x=>x.id==='cold-existing-state-process-first-result');
  assert.equal(first.samples.length,0);assert.equal(first.status,'incomplete');
  const failed=JSON.parse(await readFile(metric.samples[0].observation));
  assert.equal(failed.cleanup.closed,true);assert.match(failed.failure.message,/Synthetic Unknown/);
});


test('two-Model deal-review fixture preserves keyed Content and consumes the first original review before Effect', async () => {
  const original = projectTemplateFiles('deal-review-mock'), files = twoModelDealReviewFiles();
  const changed = Object.keys(files).filter(name => files[name] !== original[name]).sort();
  assert.deepEqual(changed, ['actql.config.json', 'deal-review.program.json', 'mock/deal-review-confirm.v1.answers.yaml',
    'model-tasks.json', 'model-tasks/deal-review-confirm.v1.yaml']);
  for (const name of Object.keys(original).filter(name => !changed.includes(name))) {
    assert.equal(files[name], original[name], name);
  }
  assert.equal(files['deal-review.aql'], original['deal-review.aql'], 'Original public text is unchanged');
  const program = JSON.parse(files['deal-review.program.json']);
  assert.deepEqual(program.stages.map(stage => stage.id), ['review', 'confirm', 'apply']);
  assert.equal(program.stages.flatMap(stage => stage.steps).filter(step => step.infer).length, 2);
  const [first, second, apply] = program.stages;
  assert.deepEqual(first.inputs, {
    opportunities: {connector: 'salesforce', resource: 'Opportunity'},
    files: {connector: 'drive', resource: 'files', request: {paths: null, glob: null}},
    contents: {connector: 'drive', resource: 'contents'}});
  assert.deepEqual(first.steps[1].join.on,
    [{left: 'resource', right: 'resource'}, {left: 'version', right: 'version'}]);
  assert.deepEqual(second.inputs, {reviewed: {result: {stage: 'review', result: 'rows'}}});
  assert.deepEqual(apply.inputs, {confirmed: {result: {stage: 'confirm', result: 'rows'}}});
  for (const stage of [first, second]) {
    assert.equal(stage.steps.filter(step => step.infer).length, 1);
    assert.deepEqual(stage.steps.find(step => step.assert_rows).assert_rows, {unique_by: ['id']});
  }
  assert.deepEqual(second.steps.find(step => step.infer).infer, {
    contract: 'model-task:deal-review-confirm.v1', key: 'id', input: {
      changed: {property: {value: {property: {value: {field: 'review'}, name: 'value'}}, name: 'changed'}},
      stage: {property: {value: {property: {value: {field: 'review'}, name: 'value'}}, name: 'stage'}},
      next_step: {property: {value: {property: {value: {field: 'review'}, name: 'value'}}, name: 'next_step'}}}});
  assert.deepEqual(second.steps.find(step => step.filter).filter, {and: [
    {eq: [{field: 'outcome'}, {literal: 'ok'}]},
    {property: {value: {field: 'value'}, name: 'confirmed'}}]});
  assert.equal(first.effects, undefined); assert.equal(second.effects, undefined);
  assert.equal(apply.effects.save.update.target, 'connector://salesforce/Opportunity');
  const publicFields = ['id', 'StageName', 'NextStep', 'review', 'confirmation'];
  assert.deepEqual(apply.steps, [
    {derive: {
      next_stage: {property: {value: {property: {value: {field: 'review'}, name: 'value'}}, name: 'stage'}},
      next_step: {property: {value: {property: {value: {field: 'review'}, name: 'value'}}, name: 'next_step'}}}},
    {select: [...publicFields, 'next_stage', 'next_step'], as: 'effect_input'},
    {select: publicFields, as: 'updates'},
  ]);
  assert.deepEqual(apply.results, {
    rows: {from: 'updates', fields: publicFields},
    effect_input: {from: 'effect_input', fields: [...publicFields, 'next_stage', 'next_step']},
  });
  assert.deepEqual(apply.effects.save.update.from, {result: 'effect_input'});
  assert.deepEqual(apply.effects.save.update.set, {
    StageName: {field: 'next_stage'}, NextStep: {field: 'next_step'}});
  assert.deepEqual(program.results, {updates: {from: {stage: 'apply', result: 'rows'}}});
  const task = parse(files['model-tasks/deal-review-confirm.v1.yaml']);
  assert.deepEqual(task.input, {changed: {type: 'boolean', nullable: true},
    stage: {type: 'string', nullable: true}, next_step: {type: 'string', nullable: true}});
  assert.deepEqual(task.output, {confirmed: 'boolean', stage: 'string', next_step: 'string'});
  assert.equal(JSON.parse(files['actql.config.json']).mock.answers['model-task:deal-review-confirm.v1'],
    './mock/deal-review-confirm.v1.answers.yaml');
  assert.equal(JSON.parse(files['model-tasks.json']).tasks['model-task:deal-review-confirm.v1'],
    './model-tasks/deal-review-confirm.v1.yaml');
  const checks = await mockProjectWorkflowChecks({template: 'deal-review-mock', variant: 'two-models'});
  const rows = [
    {id: '006Acme', StageName: 'Proposal', NextStep: null,
      review: {outcome: 'ok', value: {changed: true, stage: 'Negotiation', next_step: 'Send revised pricing by Friday'}},
      confirmation: {outcome: 'ok', value: {confirmed: true, stage: 'Negotiation', next_step: 'Send revised pricing by Friday'}}},
    {id: '006Globex', StageName: 'Negotiation', NextStep: 'Legal review',
      review: {outcome: 'ok', value: {changed: true, stage: 'Closed Lost', next_step: 'Revisit next fiscal year'}},
      confirmation: {outcome: 'ok', value: {confirmed: true, stage: 'Closed Lost', next_step: 'Revisit next fiscal year'}}},
  ];
  checks.checkRows(rows);
  for (const confirmation of [undefined, {outcome: 'error', value: null},
    {outcome: 'ok', value: {confirmed: false, stage: 'Negotiation', next_step: 'Send revised pricing by Friday'}},
    {outcome: 'ok', value: {confirmed: true, stage: 'foreign', next_step: 'Send revised pricing by Friday'}}]) {
    const wrong = structuredClone(rows); wrong[0].confirmation = confirmation;
    assert.throws(() => checks.checkRows(wrong));
  }
});

test('two-Model deal-review uses the same existing public workflow and retains its original failed phase', async () => {
  const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-two-model-workflow-',
    label: 'Two-Model authored caller selection only, no Host workflow execution'});
  const root = join(scratch.path, 'run'), consumer = join(scratch.path, 'consumer');
  await mkdir(root); await mkdir(join(consumer, 'node_modules'), {recursive: true});
  const primary = new Error('Original two-Model public workflow not executed');
  const observations = []; let calls = 0;
  await assert.rejects(mockWorkflowMetrics({prepared: {consumer}, root,
    repository: new URL('../', import.meta.url).pathname, counts: {coldSamples: 1},
    template: 'deal-review-mock', variant: 'two-models', onMetric: metric => observations.push(metric),
    async command(executable, args, options) {
      calls++; assert.equal(executable, process.execPath);
      assert.deepEqual(args.slice(1), ['capture', join(options.cwd, 'handoff.json'), 'deal-review-mock', 'two-models']);
      for (const [name, bytes] of Object.entries(twoModelDealReviewFiles())) {
        assert.equal(await readFile(join(options.cwd, name), 'utf8'), bytes);
      }
      assert.equal(await readFile(args[0], 'utf8'), workflowSource);
      throw primary;
    }}), error => error === primary);
  assert.equal(calls, 1);
  assert.equal(observations.length, 1);
  assert.equal(observations[0].samples[0].completed, false);
  assert.equal(observations[0].samples[0].phases.length, 1);
  assert.equal(observations[0].samples[0].phases[0].phase, 'capture');
  assert.equal(observations[0].samples[0].phases[0].completed, false);
  const project = join(root, 'mock-project-deal-review-mock-two-models-0');
  assert.equal(JSON.parse(await readFile(join(project, 'capture.observation.json'), 'utf8')).completed, false);
  assert.equal((await readdir(project)).includes('node_modules'), false);
  scratch.passed();
});

test('two-Model deal-review submits one unchanged structured Program through the existing public caller', async () => {
  const selected = twoModelDealReviewFiles()['deal-review.program.json'];
  const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-two-model-started-',
    label: 'Original public submission reference before wait, no Host execution'});
  const handoff = join(scratch.path, 'handoff');
  const steps = [], ref = Object.freeze({fixture: 'one-original-reference'});
  const original = Object.freeze({ref});
  let reads = 0, submissions = 0;
  const execution = await startMockProjectSource({template: 'deal-review-mock', variant: 'two-models',
    handoffPath: handoff,
    step: async (name, operation) => {steps.push(name); return operation();},
    readProgram: async (path, encoding) => {reads++; assert.equal(path, 'deal-review.program.json');
      assert.equal(encoding, 'utf8'); return selected;},
    writeHandoff: async (path, bytes, options) => {
      assert.equal(path, handoff + '.started');
      assert.deepEqual(options, {encoding: 'utf8', mode: 0o600, flag: 'wx'});
      assert.equal(bytes, JSON.stringify({ref, template: 'deal-review-mock', variant: 'two-models'}) + '\n');
      await writeFile(path, bytes, options);
    },
    client: {async startSource(document, options) {submissions++; assert.equal(document, selected);
      assert.deepEqual(options, {format: 'json', stopBefore: 'commit'}); return original;}},
  });
  assert.equal(execution, original); assert.equal(reads, 1); assert.equal(submissions, 1);
  assert.deepEqual(steps, ['read original README program', 'README startSource',
    'retain original accepted reference before wait']);
  assert.deepEqual(JSON.parse(await readFile(handoff + '.started', 'utf8')),
    {ref, template: 'deal-review-mock', variant: 'two-models'});
  scratch.passed();
});


test('public Mock refusal diagnostics read only the same original SDK observation and omit private data', () => {
  const node = workflowSyntax.body.find(node => node.type === 'FunctionDeclaration' &&
    node.id.name === 'submissionCheckDiagnostic');
  assert.ok(node, 'Original submission observation diagnostic must be connected');
  const original = new Error('Original refusal'); let calls = 0;
  let observation = {outcome: 'completed', report: {verdict: 'invalid',
    reasons: [{code: 'query_syntax_invalid', facts: {secret: 'private-payload'},
      location: {kind: 'structured', document_id: 'program', revision: 'private-revision',
        pointer: '/stages/2/effects/save/update/set/StageName'}}],
    requirements: [{code: 'source_required', location: {kind: 'text', document_id: 'source',
      revision: 'private-revision', start_byte: 3, end_byte: 9}}],
    coverage: {limits: [], unresolved: []}, context_ref: 'private-context',
    inputs: [{text: 'private-input'}]}};
  const project = compileFunction(workflowSource.slice(node.start, node.end) +
    '\nreturn submissionCheckDiagnostic;', ['getSubmissionCheckObservation'])(error => {
      assert.strictEqual(error, original); calls++; return observation;
    });
  assert.deepEqual(project(original), {available: true, outcome: 'completed', verdict: 'invalid', reasons: [
    {code: 'query_syntax_invalid', location: {kind: 'structured', document: 'program',
      pointer: '/stages/2/effects/save/update/set/StageName'}},
    {code: 'source_required', location: {kind: 'text', document: 'source', start_byte: 3, end_byte: 9}},
  ], truncated: false});
  assert.equal(calls, 1);
  observation = undefined;
  assert.deepEqual(project(original), {available: false}); assert.equal(calls, 2);
  observation = {outcome: 'completed', report: {verdict: 'invalid',
    reasons: Array.from({length: 40}, () => ({code: 'implementation_limit',
      facts: {payload: 'private-payload'}, location: {kind: 'structured', document_id: 'secret-id',
        pointer: '/literal/private payload'}})), requirements: [], coverage: {limits: [], unresolved: []}}};
  const bounded = project(original);
  assert.equal(bounded.reasons.length, 32); assert.equal(bounded.truncated, true);
  assert(!JSON.stringify(bounded).includes('private')); assert(!JSON.stringify(bounded).includes('secret-id'));
  const refused = compileFunction(workflowSource.slice(node.start, node.end) +
    '\nreturn submissionCheckDiagnostic;', ['getSubmissionCheckObservation'])(() => {throw original;});
  assert.deepEqual(refused(original), {available: false});
  assert.match(workflowSource, /submissionCheckDiagnostic\(cause\)/u);
  assert.match(workflowSource, /if \(failed\) throw primary;/u);
});
