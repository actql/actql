// Scheduling/input guards only. Real package acceptance runs in its own job.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'yaml';
import {parse as parseJavaScript} from 'acorn';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {nativeCliTestCohort, requireNativeCliCiInputs, requireNativeHostAuthorizationReceipt, runInstalledNativeCliTransport}
  from './ci-native-cli-installed.mjs';
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
  assert(owner.indexOf('assert.equal(artifact.localRuntime, undefined)') < owner.indexOf('await runInstalledNativeCliTransport(binary, env)'));
  const run = owner.indexOf('await runInstalledNativeCliTransport(binary, env)');
  assert(owner.indexOf('assert.equal(hash(await readFile(binary)), artifact.binarySha256)') < run);
  assert(owner.indexOf('assert.equal(hash(await readFile(binary)), artifact.binarySha256)', run) > run);
  assert(run < owner.indexOf('await registry.close()'));
});

test('same installed Remote binary reaches the unchanged transport fixture and preserves failure or signal', async () => {
  const environment = Object.freeze({PATH: process.env.PATH, HOME: '/fresh-consumer/home', TMPDIR: '/fresh-consumer/tmp'});
  for (const mode of ['success', 'failure', 'signal']) {
    let calls = 0;
    const outcome = await runInstalledNativeCliTransport('/same-installed/versioned-native', environment, {
      launch(command, args, options) {
        calls++;
        assert.equal(command, process.execPath);
        assert(args[0].endsWith('/scripts/test-native-client.mjs'));
        assert.equal(args.length, 1);
        assert.equal(options.env.ACTQL_TEST_NATIVE_CLIENT_BINARY, '/same-installed/versioned-native');
        assert.deepEqual(options.env, {...environment, ACTQL_TEST_NATIVE_CLIENT_BINARY: '/same-installed/versioned-native'});
        assert.equal(options.stdio, 'inherit');
        assert.equal(options.timeout, undefined, 'Only the original enclosing CI deadline applies');
        return spawn(process.execPath, ['-e', mode === 'signal'
          ? 'process.kill(process.pid,"SIGTERM")' : `process.exit(${mode === 'success' ? 0 : 7})`],
        {stdio: 'ignore'});
      },
    }).then(() => ({success: true}), error => ({success: false, error}));
    assert.equal(calls, 1);
    assert.equal(outcome.success, mode === 'success');
    if (mode !== 'success') assert.match(outcome.error.message, /Original Native Client transport/u);
  }
  assert.equal(environment.ACTQL_TEST_NATIVE_CLIENT_BINARY, undefined);
  for (const primary of [undefined, new Error('original launch error')]) {
    const outcome = await runInstalledNativeCliTransport('/same-installed', environment,
      {launch() {throw primary;}}).then(() => ({rejected: false}), reason => ({rejected: true, reason}));
    assert.equal(outcome.rejected, true); assert.equal(outcome.reason, primary);
  }
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
