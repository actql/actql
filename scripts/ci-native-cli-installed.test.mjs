// Scheduling/input guards only. Real package acceptance runs in its own job.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'yaml';
import {parse as parseJavaScript} from 'acorn';
import {createHash} from 'node:crypto';
import {nativeCliTestCohort, requireNativeCliCiInputs, requireNativeHostAuthorizationReceipt}
  from './ci-native-cli-installed.mjs';
import {runNativeInstallCommand} from './test-native-standalone-install.mjs';
import {admitNativeReleaseCohort} from './native-cli-release.mjs';
import {gateJobs, gateJobRequired, selectTargets} from './ci-targets.mjs';

const {jobs} = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
test('ordinary Native CLI installed acceptance is required by the final full CI gate', () => {
  const job = jobs['native-cli-installed'];
  assert.deepEqual(job.needs, ['select-targets', 'preflight', 'client-packages']);
  assert.equal(job['runs-on'], 'ubuntu-24.04');
  assert.match(job.if, /outputs\.profile == 'full'/u);
  assert.doesNotMatch(job.if, /always\(|failure\(|cancelled\(/u);
  assert.equal(job['continue-on-error'], undefined);
  assert.equal(job.steps.find(step => step.uses?.startsWith('actions/checkout@')).with['fetch-depth'], 0);
  assert(gateJobs.includes('native-cli-installed'));
  assert(jobs.check.needs.includes('native-cli-installed'));
  const full = selectTargets(['packages/native-cli/bin/actql.mjs']);
  assert.equal(gateJobRequired(full, 'native-cli-installed'), true);
  assert.equal(gateJobRequired(selectTargets(['packages/native-cli/bin/actql.mjs'], {draft: true}),
    'native-cli-installed'), false);
  const download = job.steps.find(step => step.uses === './.github/actions/download-client-packages');
  assert.equal(download.with['artifact-id'], '${{ needs.client-packages.outputs.artifact-id }}');
  const execution = job.steps.find(step => step.run?.startsWith('node scripts/ci-native-cli-installed.mjs'));
  assert(execution); assert.equal(execution.if, undefined);
  assert.equal(execution['continue-on-error'], undefined);
  assert.match(execution.run, /runner\.temp/u);
});

test('the Client gate requires the installed Remote transport owner and retires only its duplicate compiler', () => {
  const obligation = JSON.parse(readFileSync(new URL('./fixtures/ci-native-obligations.json', import.meta.url))).remoteClientTransport;
  assert.equal(jobs[obligation.previousJob], undefined);
  assert(jobs.client.needs.includes(obligation.owner));
  assert(jobs.check.needs.includes(obligation.owner));
  assert.equal(obligation.owner, 'native-cli-installed');
  const source = readFileSync(new URL('./test-native-client.mjs', import.meta.url));
  assert.equal(createHash('sha256').update(source).digest('hex'), obligation.scriptSha256);
  const local = JSON.parse(readFileSync(new URL('../package.json', import.meta.url))).scripts['check:distribution-client'];
  assert(local.includes(obligation.retiredCiBuild));
  assert(local.includes('node ' + obligation.script));
  const owner = readFileSync(new URL('./ci-native-cli-installed.mjs', import.meta.url), 'utf8');
  assert(owner.indexOf('assert.equal(artifact.localRuntime, undefined)') < owner.indexOf("await run(process.execPath, [join(repository, 'scripts/test-native-client.mjs')]"));
  const run = owner.indexOf("await run(process.execPath, [join(repository, 'scripts/test-native-client.mjs')]");
  assert(owner.indexOf('assert.equal(hash(await readFile(binary)), artifact.binarySha256)') < run);
  assert(owner.indexOf('assert.equal(hash(await readFile(binary)), artifact.binarySha256)', run) > run);
  assert(run < owner.indexOf('await registry.close()'));
});

test('same installed Remote transport uses the original bounded runner and records success failure and signal', async () => {
  const source = readFileSync(new URL('./ci-native-cli-installed.mjs', import.meta.url), 'utf8');
  const syntax = parseJavaScript(source, {sourceType: 'module', ecmaVersion: 'latest'});
  const owner = syntax.body.find(node => node.type === 'ExportNamedDeclaration' &&
    node.declaration?.id?.name === 'acceptInstalledNativeCli').declaration;
  const run = owner.body.body.find(node => node.type === 'VariableDeclaration' && node.declarations[0].id.name === 'run');
  const block = owner.body.body.find(node => node.type === 'TryStatement');
  const call = block.block.body.find(node => node.type === 'ExpressionStatement' &&
    source.slice(node.start, node.end).includes("join(repository, 'scripts/test-native-client.mjs')"));
  const rejection = owner.body.body.find(node => node.type === 'IfStatement' && node.test.name === 'rejected');
  assert(call);
  assert(rejection);
  assert(!source.includes('runInstalledNativeCliTransport'));
  const environment = Object.freeze({PATH: process.env.PATH, HOME: '/fresh-consumer/home', TMPDIR: '/fresh-consumer/tmp'});
  for (const mode of ['success', 'failure', 'signal']) {
    const records = [], reports = [];
    let calls = 0, childFailure;
    const ports = {
      repository: '/original-source', consumer: '/fresh-consumer', binary: '/same-installed/versioned-native',
      env: environment, process, join: (...parts) => parts.join('/'), records,
      source: {revision: 'a'.repeat(40)}, save: async value => {reports.push(value);},
      runNativeInstallCommand: async (command, args, options) => {
        calls++;
        assert.equal(command, process.execPath);
        assert.deepEqual(args, ['/original-source/scripts/test-native-client.mjs']);
        assert.equal(options.cwd, '/original-source');
        assert.deepEqual(options.env, {...environment, ACTQL_TEST_NATIVE_CLIENT_BINARY: '/same-installed/versioned-native'});
        assert.equal(options.expectedCode, undefined, 'Keep the original zero-exit requirement');
        assert.equal(options.state, undefined, 'Do not manufacture physical close evidence for the transport script');
        // Execute only a short owned Node fixture through the ACTUAL existing
        // bounded runner; this explicit child port is not a Native execution.
        const script = "require('fs').writeSync(1,'original transport stdout'+String.fromCharCode(10));" +
          "require('fs').writeSync(2,'original transport stderr'+String.fromCharCode(10));" +
          (mode === 'signal' ? 'process.kill(process.pid,"SIGTERM")' : `process.exit(${mode === 'success' ? 0 : 7})`);
        try {return await runNativeInstallCommand(command, ['-e', script], {cwd: process.cwd(), env: process.env});}
        catch (error) {childFailure = error; throw error;}
      },
    };
    const invoke = Function(...Object.keys(ports), `return (async () => {${source.slice(run.start, run.end)};${source.slice(call.start, call.end)}})();`);
    const outcome = await invoke(...Object.values(ports)).then(() => ({success: true}), error => ({success: false, error}));
    assert.equal(calls, 1); assert.equal(records.length, 1);
    assert.equal(outcome.success, mode === 'success');
    const record = records[0];
    assert.equal(record.stdout, 'original transport stdout' + String.fromCharCode(10));
    assert.equal(record.stderr, 'original transport stderr' + String.fromCharCode(10));
    assert(record.endedAt && record.startedAt);
    if (mode === 'success') {
      assert.equal(record.code, 0); assert.equal(record.signal, null);
      assert.equal(reports.length, 1); assert.equal(reports[0].records[0], record);
    } else {
      assert.equal(outcome.error, childFailure);
      assert.equal(outcome.error.commandRecord, record, 'Retain the SAME original failed command record');
      assert.equal(record.code, mode === 'signal' ? null : 7);
      assert.equal(record.signal, mode === 'signal' ? 'SIGTERM' : null);
      assert.equal(reports.length, 0, 'The existing outer rejection path publishes failure, never running success');
      const publish = Function(...Object.keys(ports), 'failure', 'rejected',
        `return (async () => {${source.slice(rejection.start, rejection.end)}})();`);
      const failed = await publish(...Object.values(ports), outcome.error, true).then(
        () => ({rejected: false}), error => ({rejected: true, error}));
      assert.equal(failed.rejected, true); assert.equal(failed.error, outcome.error);
      assert.equal(reports.length, 1); assert.equal(reports[0].status, 'failed');
      assert.equal(reports[0].records[0], record, 'The failed installed receipt retains original output/exit/Signal');
    }
  }
  assert.equal(environment.ACTQL_TEST_NATIVE_CLIENT_BINARY, undefined);
});

test('private CI cohort retains ordinary release validation without proposing a publication', () => {
  assert.deepEqual(admitNativeReleaseCohort(nativeCliTestCohort), nativeCliTestCohort);
  assert.equal(nativeCliTestCohort.packageVersion, '0.0.2-rc.0');
  assert.throws(() => requireNativeCliCiInputs({}, {clean: true}, 'linux', 'x64'), /normal Client package producer/u);
  assert.throws(() => requireNativeCliCiInputs({ACTQL_PACKED_CLIENT_PACKAGES: '/fixture'}, {clean: false}, 'linux', 'x64'), /clean source/u);
});

test('installed gate uses real producers and independent Host permissions rather than source overlays', () => {
  const source = readFileSync(new URL('./ci-native-cli-installed.mjs', import.meta.url), 'utf8');
  assert.match(source, /await buildNativeCliArtifact\(artifact/u);
  assert.match(source, /await prepareNativeCliRelease\(release/u);
  assert.match(source, /await packedClientPackage\(/u);
  assert.match(source, /release-native-host-authorization\.mjs/u);
  assert.match(source, /state: join\(host, 'host-state'\)/u);
  assert.match(source, /\['release-native-host\.mjs', launcher\]/u);
  assert.match(source, /cwd: launcherHost/u);
  assert(source.indexOf('await registry.close()') < source.indexOf('await save(receipt)'));
  assert.match(source, /new AggregateError\(\[failure, error\]/u);
  assert.match(source, /assert\.equal\(after\.mtimeMs, before\.mtimeMs\)/u);
  assert.match(source, /assert\.rejects\(stat\(target\), \{code: 'ENOENT'\}\)/u);
  assert.doesNotMatch(source, /publishPackageRelease|npm.*\['publish'|git.*\['push'/u);
});

const authorizationReceipt = () => ({version: 'actql-native-release-host-authorization/0.1', receipts: [
  {omitted: 'run-read', computes: 1, ref: {original: 'run'},
    clientCloseReturned: true, serverCloseReturned: true, hostCloseReturned: true,
    denials: ['wait', 'status', 'attach', 'lookup-submission'].map(operation =>
      ({operation, code: 'ClientConnectionDenied'})), rows: [{id: 1}, {id: 2}],
    resultReadAttempts: 2, pendingResultReads: [{attempt: 1, code: 'ResultAccessDenied', rowsYielded: 0}]},
  {omitted: 'result-main-read', computes: 1, ref: {original: 'run'},
    clientCloseReturned: true, serverCloseReturned: true, hostCloseReturned: true,
    denials: [{operation: 'read', code: 'ResultAccessDenied', rowsYielded: 0},
      {operation: 'result-describe', code: 'ResultAccessDenied'}]},
]});

test('installed authorization receipt requires both complete cases, counts, independent denials and close returns', () => {
  const original = authorizationReceipt();
  assert.equal(requireNativeHostAuthorizationReceipt(original), original);
  const firstRead = authorizationReceipt();
  firstRead.receipts[0].resultReadAttempts = 1; firstRead.receipts[0].pendingResultReads = [];
  assert.equal(requireNativeHostAuthorizationReceipt(firstRead), firstRead);
  for (const value of [undefined, {}, {version: original.version}, {...original, receipts: []},
    {...original, receipts: [original.receipts[0]]}, {...original, receipts: [original.receipts[0], original.receipts[0]]}])
    assert.throws(() => requireNativeHostAuthorizationReceipt(value));
  const reject = mutate => {const value = authorizationReceipt(); mutate(value); assert.throws(() => requireNativeHostAuthorizationReceipt(value));};
  for (const index of [0, 1]) {
    for (const count of [undefined, 0, 2]) reject(value => {value.receipts[index].computes = count;});
    for (const field of ['clientCloseReturned', 'serverCloseReturned', 'hostCloseReturned']) {
      reject(value => {delete value.receipts[index][field];});
      reject(value => {value.receipts[index][field] = false;});
    }
    reject(value => {delete value.receipts[index].denials;});
    reject(value => {value.receipts[index].denials = [];});
    reject(value => {delete value.receipts[index].ref;});
    reject(value => {value.receipts[index].ref = {};});
  }
  reject(value => {value.receipts[0].rows = [];});
  reject(value => {delete value.receipts[0].rows;});
  for (const attempts of [undefined, 0, 1.5, 301]) reject(value => {value.receipts[0].resultReadAttempts = attempts;});
  reject(value => {delete value.receipts[0].pendingResultReads;});
  reject(value => {value.receipts[0].pendingResultReads = [];});
  reject(value => {value.receipts[0].pendingResultReads[0].rowsYielded = 1;});
  reject(value => {value.receipts[1].denials[0].rowsYielded = 1;});
});

test('installed acceptance preserves undefined and primitive command rejections through original registry cleanup', async () => {
  const source = readFileSync(new URL('./ci-native-cli-installed.mjs', import.meta.url), 'utf8');
  const syntax = parseJavaScript(source, {sourceType: 'module', ecmaVersion: 'latest'});
  const original = syntax.body.find(node => node.type === 'ExportNamedDeclaration' &&
    node.declaration?.id?.name === 'acceptInstalledNativeCli').declaration;
  assert(source.slice(original.start, original.end).includes('requireNativeHostAuthorizationReceipt('));
  for (const primary of [undefined, null, false, 0, 'original primitive', new Error('original command')]) {
    for (const cleanupFailure of [false, true, 2]) {
      const cleanup = cleanupFailure === 2 ? undefined : new Error('registry cleanup'), reports = [];
      let commands = 0, closed = 0, passed = 0;
      const sourceState = {revision: 'a'.repeat(40), clean: true};
      const manifest = {sourceSha: sourceState.revision, artifacts: [{platform: 'linux-x64-gnu'}],
        cohort: {packageVersion: '0.0.2-rc.0'}};
      const ports = {
        assert, repository: '/owned-source', checkoutState: () => sourceState,
        requireNativeCliCiInputs: (environment, value) => requireNativeCliCiInputs(environment, value, 'linux', 'x64'),
        process: {env: {ACTQL_PACKED_CLIENT_PACKAGES: '/normal-source-packages'}},
        verifyNativeCliRelease: async () => manifest,
        createOwnedScratch: async () => ({path: '/owned-scratch', passed() {passed++;}}),
        tmpdir: () => '/owned-temp', join: (...parts) => parts.join('/'),
        releaseConsumerDestination: async () => '/owned-consumer', mkdir: async () => {},
        publicConsumerEnvironment: () => ({HOME: '/owned-home', TMPDIR: '/owned-tmp',
          npm_config_userconfig: '/owned-userconfig', npm_config_globalconfig: '/owned-globalconfig'}),
        openReleaseTestRegistry: async () => ({url: 'https://fixture-registry/', requested: [],
          async close() {closed++; if (cleanupFailure) throw cleanup;}}),
        writeFile: async (path, body) => {if (path.endsWith('installed-ci.json')) reports.push(JSON.parse(body));},
        runNativeInstallCommand: async () => {commands++; throw primary;},
      };
      const accept = Function(...Object.keys(ports), `return (${source.slice(original.start, original.end)});`)(...Object.values(ports));
      const outcome = await accept('/owned-release').then(
        value => ({rejected: false, value}), reason => ({rejected: true, reason}));
      assert.equal(outcome.rejected, true, 'undefined command rejection cannot mark a receipt passed');
      if (cleanupFailure) {
        assert(outcome.reason instanceof AggregateError);
        assert.equal(outcome.reason.errors.length, 2);
        assert.equal(outcome.reason.errors[0], primary); assert.equal(outcome.reason.errors[1], cleanup);
      } else assert.equal(outcome.reason, primary);
      assert.equal(commands, 1); assert.equal(closed, 1); assert.equal(passed, 0);
      assert.deepEqual(reports.map(value => value.status), ['failed']);
    }
  }
});
