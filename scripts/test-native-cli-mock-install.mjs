// Positive installed acceptance, never an expected refusal or a skip. CI runs
// this independently of source-free acceptance on the same prepared Native
// release. Missing suppliers or approval continuation are failures.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {createHash} from 'node:crypto';
import {lstat, mkdir, readFile, readdir, realpath, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {basename, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {promisify} from 'node:util';
import {platformKey} from '../packages/native-cli/bin/actql.mjs';
import {checkoutState} from './packed-client-packages.mjs';
import {verifyNativeCliRelease, withNativeMockReleaseAdmission, originalNativeMockReleaseAdmission} from './native-cli-release.mjs';
import {serveNativeMockCampaign} from './native-mock-campaign.mjs';
import {createOwnedScratch} from './owned-scratch.mjs';
import {openReleaseTestRegistry} from './release-test-registry.mjs';
import {approvalCallCounts, assertApprovalCallCounts, approvalResources, approvalPhases, publishNativeApprovalReceipt, nativeApprovalObservationOptions,
  nativeApprovalObservedCommand, retainNativeApprovalObservation, observeNativeMockHarnessPhase} from './native-approval-performance.mjs';
import {captureNativeMockCommand, mockTemplates, runNativeCliMockScenario, runNativeSharedFileMockScenario} from './native-cli-mock-scenario.mjs';
import {expectedChanges, nativeLauncherEnvelope, requireNativeMockWork} from './native-cli-mock-scenario.mjs';
import {nativeMockAcceptanceObservations} from '../packages/native-cli/lib/project-scaffold.mjs';
import {inventory, verifyPackageRelease} from './package-release.mjs';
import {assertReleaseProjectCohort, prepareReleaseProjectNode, retainReleaseProjectArchives, runReleaseProjectCli} from './release-project-sequence-install.mjs';
import {runReleaseProjectSequences, projectTargetSnapshot, requiredProjectReplacements, projectCliExpectedExit} from './release-project-sequences.mjs';
import {runOriginalMockRegressions} from './native-cli-mock-regressions.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
export function nativeMockInstallOptions(extra, platform) {
  if (extra.includes('--shared-file-mock')) {
    assert.deepEqual(extra, ['--shared-file-mock'], 'Shared-file Mock requires a separate acceptance invocation');
    return {sharedFileMock: true};
  }
  const selected = extra.findIndex(value => ['--release-project-sequences', '--original-mock-regressions'].includes(value));
  assert(selected < 0 || selected === extra.length - 2 && typeof extra[selected + 1] === 'string' && extra[selected + 1].length,
    'RC sequence selection requires exactly its Node RC directory');
  const options = nativeApprovalObservationOptions(selected < 0 ? extra : extra.slice(0, selected), platform);
  if (selected >= 0) {
    assert.equal(platform, 'darwin', 'The additional RC profile is the reported Mac consumer');
    options.projectSequenceNodeRelease = extra[selected + 1];
    if (extra[selected] === '--original-mock-regressions') options.originalMockRegressions = true;
  }
  return options;
}
export async function runNativeCliMockInstall(input, {measureResources = false, diagnoseSyscalls = false,
  releaseAdmission, projectSequenceNodeRelease, originalMockRegressions = false, sharedFileMock = false} = {}) {
  assert(input, 'Native mock acceptance requires its fixed release directory');
  assert(!originalMockRegressions || projectSequenceNodeRelease !== undefined,
    'Original Mock regressions require the exact Node companion');
  assert(!sharedFileMock || (!measureResources && !diagnoseSyscalls && !releaseAdmission && !projectSequenceNodeRelease && !originalMockRegressions),
    'Shared-file Mock requires its own fixed release admission');
  const syscallTool = diagnoseSyscalls ? {
    path: '/usr/bin/strace',
    sha256: createHash('sha256').update(await readFile('/usr/bin/strace')).digest('hex'),
    version: (await promisify(execFile)('/usr/bin/strace', ['--version'], {encoding: 'utf8', timeout: 5000})).stdout.trim(),
  } : undefined;
  const harnessPhases = [];
  const observe = (phase, action, template) => observeNativeMockHarnessPhase(harnessPhases, phase, action, template);
  const directory = resolve(input);
  if (releaseAdmission !== undefined) releaseAdmission = originalNativeMockReleaseAdmission(releaseAdmission, directory);
  const nativeManifestBytes = projectSequenceNodeRelease === undefined ? undefined
    : await readFile(join(directory, 'release.json'));
  const manifest = await observe('release-verification', async () => await (releaseAdmission ? releaseAdmission.verify() : verifyNativeCliRelease(directory)));
  const {source, glibc, platform, expectedArtifact} = await observe('source-platform-admission', () => {
    const source = checkoutState(repository);
    assert(source.clean, 'Installed mock acceptance requires clean source');
    assert.equal(source.revision, manifest.sourceSha, 'Fixtures and Native artifact must share the fixed source');
    const glibc = process.platform === 'linux' ? process.report.getReport().header.glibcVersionRuntime : undefined;
    const platform = platformKey({platform: process.platform, arch: process.arch, glibc});
    assert(manifest.platforms[platform], 'No fixed Native artifact for this platform');
    const expectedArtifact = manifest.artifacts.find(value => value.platform === platform);
    assert(expectedArtifact?.localRuntime, 'Mock acceptance requires the packaged Local runtime');
    return {source, glibc, platform, expectedArtifact};
  });
  let nodeDirectory, nodeManifest, nodeManifestBytes, nodeDevelopmentManifestBytes;
  if (projectSequenceNodeRelease !== undefined) {
    assert.equal(typeof projectSequenceNodeRelease, 'string'); assert(projectSequenceNodeRelease.length);
    assert.equal(platform, 'darwin-arm64', 'The additional RC cases select the reported Mac platform');
    assert.equal(Number(process.versions.node.split('.')[0]), 24, 'Use actual Node24, not a relabelled Node22 receipt');
    assert(!diagnoseSyscalls && releaseAdmission === undefined, 'RC sequences are separate from formal/diagnostic campaigns');
    nodeDirectory = resolve(projectSequenceNodeRelease);
    nodeManifestBytes = await readFile(join(nodeDirectory, 'release.json'));
    nodeDevelopmentManifestBytes = await readFile(join(nodeDirectory, 'development/packed-client-packages.json'));
    nodeManifest = await verifyPackageRelease(nodeDirectory);
    assert.deepEqual(JSON.parse(nodeManifestBytes), nodeManifest);
    assertReleaseProjectCohort(manifest, nodeManifest);
  }
  const scratch = await observe('scratch-creation', () => createOwnedScratch({parent: tmpdir(), prefix: 'actql-native-mock-install-',
    label: 'Native mock public workflow external installation'}));
  const registry = await observe('registry-open', () => openReleaseTestRegistry([{directory, manifest},
    ...(nodeManifest ? [{directory: nodeDirectory, manifest: nodeManifest}] : [])]));
  const root = scratch.path, prefix = join(root, 'global'), records = [], scenarios = [];
  // No inherited account, provider key, Host selection, library override, SDK or
  // private runtime path may rescue a missing installed Native implementation.
  const env = {PATH: process.env.PATH, HOME: join(root, 'home'), TMPDIR: join(root, 'tmp'), LANG: 'C.UTF-8',
    npm_config_registry: registry.url, npm_config_userconfig: join(root, 'npmrc'),
    npm_config_globalconfig: join(root, 'npmrc-global'), npm_config_cache: join(root, 'cache'),
    npm_config_proxy: '', npm_config_https_proxy: '', npm_config_update_notifier: 'false',
    NO_PROXY: '127.0.0.1,localhost'};
  const execute = promisify(execFile);
  let receipt, primary, failed = false;
  async function run(command, args, cwd = root, timeoutMs = 120_000) {
    const started = process.hrtime.bigint();
    const resources = measureResources && command === process.execPath && args[1] === 'approve'
      ? join(root, `approval-resources-${records.length}.txt`) : undefined;
    const syscalls = resources && diagnoseSyscalls ? join(root, `approval-syscalls-${records.length}.txt`) : undefined;
    const observed = nativeApprovalObservedCommand(command, args, {platform: process.platform, resources, syscalls});
    let result;
    try {
      const options = {cwd, env, timeout: timeoutMs, killSignal: 'SIGKILL', maxBuffer: 8 * 1024 * 1024};
      const captured = command === process.execPath
        ? await captureNativeMockCommand(observed.command, observed.args,
          {...options, stderrPath: join(root, `command-${records.length}.stderr`)})
        : await execute(observed.command, observed.args, options);
      result = {...captured, code: 0, signal: null};
    } catch (error) {
      result = {code: error.code ?? null, signal: error.signal ?? null, pid: error.pid ?? null,
        killed: error.killed ?? false, stdout: error.stdout ?? '', stderr: error.stderr ?? '',
        ...(error.exitCode !== undefined ? {childExitCode: error.exitCode} : {})};
    }
    const wallNs = Number(process.hrtime.bigint() - started);
    assert(Number.isSafeInteger(wallNs) && wallNs >= 0);
    const record = {command, args, cwd, timeoutMs, elapsedMs: wallNs / 1e6, wallNs, ...result};
    if (resources) {
      record.observationFiles = [];
      for (const [kind, file] of [['resources', resources], ['syscalls', syscalls]]) {
        if (!file) continue;
        try {
          record.observationFiles.push(await retainNativeApprovalObservation(file,
            join(directory, `approval-${kind}-${basename(root)}-${records.length}.txt`), kind));
        } catch (error) { record.resourceObservationIssue ??= error.message; }
      }
      if (result.code === 0 && result.signal === null) {
        try { record.resources = approvalResources(await readFile(resources, 'utf8'), process.platform); }
        catch (error) { record.resourceObservationIssue ??= error.message; }
      }
      record.measurement = {sampler: '/usr/bin/time', wallIncludesSampler: true,
        ...(diagnoseSyscalls ? {diagnosticOnly: true, acceptanceEligible: false,
          instrumentation: 'strace -f -c; Node launcher and waited Native child'} : {})};
    }
    records.push(record);
    // Persist before any assertion, including the first unsupported binding.
    await writeFile(join(root, 'commands.json'), `${JSON.stringify(records, null, 2)}\n`);
    return record;
  }

  try {
    await observe('installation', async () => {
      await mkdir(prefix);
      await mkdir(env.HOME);
      await mkdir(env.TMPDIR);
      await mkdir(join(root, 'empty-path'));
      await writeFile(join(root, 'npmrc'), `registry=${registry.url}\n@actql:registry=${registry.url}\n`);
      await writeFile(join(root, 'npmrc-global'), '');
      const installed = await run('npm', ['install', '-g', '--prefix', prefix, '--ignore-scripts',
        '--no-audit', '--no-fund', `actql@${manifest.cohort.packageVersion}`]);
      assert.equal(installed.code, 0, installed.stderr);
      assert.equal(installed.signal, null);
    });
    const packageRoot = join(prefix, 'lib/node_modules/actql');
    const launcher = join(prefix, 'bin/actql');
    const {platformRoot, artifact, binary} = await observe('installed-package-admission', async () => {
      assert.deepEqual((await readdir(join(packageRoot, 'node_modules/@actql'))).sort(), [`cli-${platform}`]);
      const platformRoot = join(packageRoot, 'node_modules/@actql', `cli-${platform}`);
      const artifact = JSON.parse(await readFile(join(platformRoot, 'artifact.json'), 'utf8'));
      assert.deepEqual(artifact, expectedArtifact);
      const binary = await readFile(join(platformRoot, 'bin/actql-native-client'));
      assert.equal(binary.length, manifest.platforms[platform].binaryBytes);
      assert.equal(createHash('sha256').update(binary).digest('hex'), manifest.platforms[platform].binarySha256);
      return {platformRoot, artifact, binary};
    });
    const verifyNativeArchives = nativeManifestBytes === undefined ? undefined
      : await retainReleaseProjectArchives(directory, manifest, nativeManifestBytes);
    const verifyNativeInputs = async () => {
      assert.deepEqual(checkoutState(repository), source);
      await verifyNativeArchives();
      for (const path of [prefix, packageRoot, platformRoot]) {
        const info = await lstat(path);
        assert(info.isDirectory() && !info.isSymbolicLink());
      }
      assert.equal(await realpath(launcher), await realpath(join(packageRoot, 'bin/actql.mjs')));
      assert.deepEqual((await readdir(join(packageRoot, 'node_modules/@actql'))).sort(), [`cli-${platform}`]);
      for (const [name, path] of [['actql', packageRoot], [`@actql/cli-${platform}`, platformRoot]]) {
        const item = manifest.packages.find(value => value.name === name);
        assert(item);
        assert.deepEqual(await inventory(path, '', {ignoreInstalledDependencies: true}), item.files);
      }
    };
    const preparedNode = nodeManifest ? await prepareReleaseProjectNode({directory: nodeDirectory,
      nativeManifest: manifest, originalNodeManifest: nodeManifest, originalNodeManifestBytes: nodeManifestBytes,
      originalNodeDevelopmentManifestBytes: nodeDevelopmentManifestBytes,
      root, repository, registry, run, verifySource: verifyNativeInputs}) : undefined;
    env.PATH = join(root, 'empty-path');
    env.ACTQL_NATIVE_TIMINGS = '1';
    env.ACTQL_NATIVE_ACCEPTANCE_OBSERVATIONS = '1';
    const runScenarioCommand = (args, cwd) => run(process.execPath, [launcher, ...args], cwd);
    if (sharedFileMock) {
      scenarios.push(await observe('shared-file-scenario', () => runNativeSharedFileMockScenario({root,
        launcherTimings: 'required', run: runScenarioCommand})));
    } else {
      for (const template of mockTemplates) scenarios.push(await observe('scenario', () => runNativeCliMockScenario({
        root, template, launcherTimings: 'required', run: runScenarioCommand}), template));
      assert.equal(scenarios.length, 2, 'Both README and Quickstart must finish without skips');
    }
    for (const scenario of scenarios) {
      const approvals = scenario.commands.filter(record => record.args.includes('approve'));
      assert.equal(approvals.length, 1);
      const approval = approvals[0];
      approval.validationCalls = approvalCallCounts(approval);
      approval.phases = approvalPhases(approval, {requireCompleted: false});
      assertApprovalCallCounts(approval.validationCalls, approval.acceptance.writes.length);
    }
    let projectSequences;
    if (preparedNode) {
      const verify = preparedNode.verify;
      const verifyRelease = async () => {
        await verify();
        await observe('release-verification', async () => {
          assert.deepEqual(await verifyNativeCliRelease(directory), manifest);
          await preparedNode.verifyRelease();
        });
        await verify();
      };
      const cli = async (args, cwd, label) => {
        await verify();
        const change = expectedChanges[label.template];
        let minimumWrites = change.rows.length;
        if (args[0] === 'approve') {
          minimumWrites = requiredProjectReplacements(label.template, (await projectTargetSnapshot(cwd)).bytes);
        }
        let value, primary, failed = false;
        try {value = await runReleaseProjectCli(run, launcher, args, cwd);
          assert.equal(value.code, projectCliExpectedExit(args, label), value.stderr); assert.equal(value.signal, null);
          const groups = nativeMockAcceptanceObservations(nativeLauncherEnvelope(value.stderr, 'required').native);
          assert(groups.length > 0, 'Missing original Native work observation');
          value.acceptance = requireNativeMockWork(args, groups, label.readonly ? 0 : change.rows.length,
            {minimumWrites: label.readonly ? 0 : minimumWrites});
        } catch (cause) {primary = cause; failed = true;}
        try {await verify();} catch (cause) {if (!failed) {primary = cause; failed = true;}}
        if (failed) throw primary;
        return value;
      };
      let sequenceFailure, sequenceFailed = false;
      try {
        projectSequences = await observe(originalMockRegressions ? 'original-mock-regressions' : 'release-project-sequences',
          () => (originalMockRegressions ? runOriginalMockRegressions : runReleaseProjectSequences)({
          root: preparedNode.projects, cli, node: preparedNode.node,
          persist: value => writeFile(join(preparedNode.cases, `${value.template}-${value.family}${value.name ? '-' + value.name : ''}.json`),
            JSON.stringify(value) + '\n', {flag: 'wx', mode: 0o600}),
        }));
        assert(projectSequences.length && projectSequences.every(value => value.complete));
      } catch (error) {sequenceFailure = error; sequenceFailed = true;}
      try {await verifyRelease();}
      catch (error) {if (!sequenceFailed) {sequenceFailure = error; sequenceFailed = true;}}
      if (sequenceFailed) throw sequenceFailure;
    }
    await observe('installed-integrity', async () => {
      assert.deepEqual(await readFile(join(platformRoot, 'bin/actql-native-client')), binary);
      assert.deepEqual(checkoutState(repository), source);
    });
    receipt = {version: 'actql-native-cli-install-acceptance/0.1',
      scope: sharedFileMock ? 'local-shared-file-mock-approval-recovery' : 'local-mock-approval-recovery',
      cliSourceSha: manifest.sourceSha, platform, node: process.version, glibc: glibc ?? null, artifact,
      scriptSha256: createHash('sha256').update(await readFile(fileURLToPath(import.meta.url))).digest('hex'),
      scenarioSha256: createHash('sha256').update(await readFile(new URL('./native-cli-mock-scenario.mjs', import.meta.url))).digest('hex'),
      cliPackages: manifest.packages.map(({name, version, sha256}) => ({name, version, sha256})),
      registry: 'private-loopback-fixed-RC', registryRequests: registry.requested,
      publicRegistryPublication: 'not-tested', harnessPhases, scenarios, records,
      ...(projectSequences ? {projectSequences, originalMockRegressions, nodeSourceSha: nodeManifest.sourceSha,
        nodePackages: nodeManifest.packages.map(({name, version, sha256, integrity}) => ({name, version, sha256, integrity}))} : {}),
      ...(diagnoseSyscalls ? {diagnosticOnly: true, acceptanceEligible: false,
        diagnostic: {purpose: 'native-approval-syscall-summary', tool: syscallTool,
          qualification: 'one instrumented workflow; not formal latency or a replacement for failed samples'}} : {}),
      unverified: ['live providers', 'crash or power-loss fault injection', 'other platforms',
        ...(projectSequences ? ['whole OS FD census and physical-stop ACK for additional sequence cases',
          'CLI static provider_io is its public projection; independent no-I/O component evidence remains separate'] : [])]};

  } catch (error) {primary = error; failed = true;}
  finally {
    try {await observe('registry-close', async () => { await registry.close(); });}
    catch (error) {
      if (!failed) throw error;
      console.error('Native Mock registry cleanup did not confirm after the original failure');
    }
  }
  if (failed) throw primary;
  releaseAdmission?.assertCurrent();
  // Successful evidence is published only after every child has exited and the
  // private registry has confirmed closure. Cleanup failure is not acceptance.
  const receiptFile = join(directory, `${diagnoseSyscalls ? 'mock-syscalls' : 'mock-install'}-${platform}-${Date.now()}.json`);
  await publishNativeApprovalReceipt({receipt, receiptFile, measureResources, scratch});

  return receiptFile;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [input, ...extra] = process.argv.slice(2);
  if (extra[0] === '--campaign-worker') {
    assert.equal(extra.length, 2);
    const count = Number(extra[1]);
    assert([3, 30].includes(count), 'Unknown Native Mock campaign population');
    await serveNativeMockCampaign(count, consume => withNativeMockReleaseAdmission(input, async admission => {
      for (let iteration = 0; iteration < count; iteration++) await consume(iteration,
        () => runNativeCliMockInstall(input, {measureResources: true, releaseAdmission: admission}));
    }));
  } else {
    const options = nativeMockInstallOptions(extra, process.platform);
    assert(input, 'usage: test-native-cli-mock-install.mjs <fixed-CLI-RC> ' +
      '[--measure-approval-resources] [--diagnose-approval-syscalls] ' +
      '[--release-project-sequences <Node-RC> | --original-mock-regressions <Node-RC>] ' +
      'or <fixed-CLI-RC> --shared-file-mock');
    await runNativeCliMockInstall(input, options);
  }
}
