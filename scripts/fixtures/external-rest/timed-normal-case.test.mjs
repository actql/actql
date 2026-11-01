// Prepared ordinary case: no artifact, config, keys or Host is a default.
// Execute only with a deliberately matching normal cohort and actual normal
// Source/initialization backing. Source validation does not run this case.
import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdir, readFile, writeFile, lstat} from 'node:fs/promises';
import {isAbsolute, join, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {performance} from 'node:perf_hooks';
import {createInstalledFamilyScenario} from './fixture-source/adapters/host-node/fixtures/installed-family-scenario.fixture.mjs';
import {runInstalledFamilyProcess} from './fixture-source/adapters/host-node/fixtures/installed-family-process.fixture.mjs';
import {inventory} from '../../package-release.mjs';
import {normalNpmPackJsonArgs, parseNpmPackJson} from '../../packed-client-packages.mjs';
import {verifyNodeBenchmarkPackages, nodeBenchmarkFailure} from '../../benchmark-node-operations.mjs';
import {externalRestDefinition, externalRestProvider} from './provider.fixture.mjs';
import {externalRestConfiguration} from './configuration.mjs';
import {prepareExternalRestCohort} from './installed-modules.mjs';

const selectedInput = process.env.ACTQL_REST_CONFORMANCE_INPUT;
assert(typeof selectedInput === 'string' && isAbsolute(selectedInput),
  'Select an explicit matching normal cohort; no old installation or state default');
const read = async path => JSON.parse(await readFile(path, 'utf8'));
const save = (path, value) => writeFile(path, JSON.stringify(value, null, 2) + '\n', {flag: 'wx'});
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const tool = promisify(execFile);
const root = fileURLToPath(new URL('../../../', import.meta.url));

// Select each named case separately through the existing bounded/nonzero guard,
// Values first; stop at the first failure rather than scheduling a new campaign.
for (const requestKind of ['values', 'source']) {
test(`W1 timed ${requestKind} keeps original invocation time through normal Result and cold Saved`, async t => {
  const originalSelection = await read(selectedInput);
  const selected = {...originalSelection, outputRoot: originalSelection.outputRoot + '-timed-' + requestKind};
  assert.deepEqual(Object.keys(selected).sort(), ['kind', 'sourceSha', 'sourceTree', 'manifestPath',
    'manifestSha256', 'outputRoot', 'accountConfigurationPath', 'mode'].sort());
  assert.equal(selected.kind, 'actql-standard-rest-normal/0.1');
  assert.equal(selected.mode, 'paged', 'The timed Source oracle retains all three authored rows');
  for (const field of ['sourceSha', 'sourceTree']) assert.match(selected[field], /^[0-9a-f]{40}$/u);
  assert.match(selected.manifestSha256, /^[0-9a-f]{64}$/u);
  for (const field of ['manifestPath', 'outputRoot', 'accountConfigurationPath']) assert(isAbsolute(selected[field]));
  // Verify the selected bytes before npm lifecycle or fixture/key creation.
  // Installed payload correspondence remains the original separate check.
  const cohort = await prepareExternalRestCohort(selected);
  const {manifest, artifactManifestPath, originalBindings, offeredTarballs} = cohort;
  await assert.rejects(lstat(selected.outputRoot), {code: 'ENOENT'});
  await mkdir(selected.outputRoot, {mode: 0o700});
  const output = selected.outputRoot, consumer = join(output, 'consumer'), commands = [];
  const provider = externalRestProvider({mode: selected.mode});
  const accountConfigurationWire = await readFile(selected.accountConfigurationPath, 'utf8');
  const report = {sourceSha: selected.sourceSha, sourceTree: selected.sourceTree,
    manifestSha256: selected.manifestSha256, mode: selected.mode, requestKind, casePassed: false,
    normalReadPassed: false, originalSavedPassed: false, fixtureTLSClosed: false,
    installedPayloadCheckAttempted: false, installedPayloadsUnchanged: false, commands};
  await save(join(output, 'offered-source-bindings.json'), originalBindings);
  await save(join(output, 'offered-tarballs-before.json'), offeredTarballs);
  let family, primary, before, expectedPlugin, pluginRoot;
  const env = {...process.env, npm_config_cache: join(output, 'npm-cache')};
  const runTool = async (name, command, args, cwd) => {
    const startedAt = new Date().toISOString();
    try {
      const result = await tool(command, args, {cwd, env, maxBuffer: 8 * 1024 * 1024});
      commands.push({name, command, args, cwd, startedAt, endedAt: new Date().toISOString(), code: 0});
      await save(join(output, name + '.json'), {stdout: result.stdout, stderr: result.stderr});
      return result.stdout;
    } catch (cause) {
      commands.push({name, command, args, cwd, startedAt, endedAt: new Date().toISOString(),
        failure: nodeBenchmarkFailure(cause)});
      await save(join(output, name + '.json'), {failure: nodeBenchmarkFailure(cause),
        stdout: String(cause.stdout ?? ''), stderr: String(cause.stderr ?? '')});
      throw cause;
    }
  };
  try {
    const originalSource = (await tool('git', ['rev-parse', 'HEAD'], {cwd: root})).stdout.trim();
    assert.equal((await tool('git', ['status', '--porcelain'], {cwd: root})).stdout, '',
      'Authoring tools must stay frozen while the ordinary case runs');
    await save(join(output, 'author-framework-source-before.json'), {source: originalSource, clean: true});
    family = await createInstalledFamilyScenario(t, {scratchParent: output,
      scenario: {id: 'standard-rest-timed-' + requestKind}, accountConfigurationWire,
      ...(requestKind === 'source' ? {provider, maxRequestBytes: 4096} : {routes: []})});
    await save(join(output, 'fixture-paths.json'), {paths: family.paths,
      resourceHttps: family.resourceHttps, providerTokenPath: family.providerTokenPath});
    const introductionStart = performance.now(), connectorTarballs = [];
    let connectorTarRecord = {};
    if (requestKind === 'source') {
      const author = join(output, 'author'), packageRoot = join(output, 'connector-package');
      const cli = join(root, 'scripts/connector.mjs');
      await runInstalledFamilyProcess({script: cli, args: ['init', author, 'acme'], cwd: root, env,
      output: join(output, 'author-init-process.json')});
      commands.push({name: 'author-init', command: process.execPath, args: [cli, 'init', author, 'acme']});
      const definitionPath = join(author, 'connector.json');
      await writeFile(definitionPath, JSON.stringify(externalRestDefinition(family.resourceHttps.origin), null, 2) + '\n');
      await runInstalledFamilyProcess({script: cli, args: ['build', definitionPath, packageRoot], cwd: root, env,
      output: join(output, 'author-build-process.json')});
      commands.push({name: 'author-build', command: process.execPath, args: [cli, 'build', definitionPath, packageRoot]});
      expectedPlugin = await inventory(packageRoot);
      const artifacts = join(output, 'artifacts');
      await mkdir(artifacts);
      const packed = parseNpmPackJson(await runTool('pack-connector', 'npm',
      normalNpmPackJsonArgs(['pack', '--offline', '--json', '--pack-destination', artifacts]), packageRoot))[0];
      assert.equal(packed.name, '@actql-connectors/acme');
      const connectorTar = join(artifacts, packed.filename), tarBytes = await readFile(connectorTar);
      connectorTarballs.push(connectorTar);
      connectorTarRecord = {connectorTarSha256: sha(tarBytes), connectorTarIntegrity: packed.integrity};
      assert.equal(packed.integrity, 'sha512-' + createHash('sha512').update(tarBytes).digest('base64'));
    }
    await mkdir(consumer);await writeFile(join(consumer, 'package.json'), '{"private":true,"type":"module"}\n');
    await runTool('install-normal', 'npm', ['install', '--offline', '--no-audit', '--no-fund',
      ...manifest.packages.map(pkg => join(dirname(artifactManifestPath), pkg.file)),
      ...connectorTarballs], consumer);
    before = await verifyNodeBenchmarkPackages(manifest, artifactManifestPath, consumer);
    if (requestKind === 'source') {
      pluginRoot = join(consumer, 'node_modules/@actql-connectors/acme');
      assert.deepEqual(await inventory(pluginRoot), expectedPlugin);
    }
    await save(join(output, 'installed-before.json'), {framework: before,
      connector: expectedPlugin ?? [], ...connectorTarRecord});
    const prepared = externalRestConfiguration(family, {connectorId: 'rest-acme',
      profileVersion: 'actql-installed-acme-rest-source/0.1'});
    if (requestKind === 'source') for (const [name, value] of Object.entries(prepared.files)) {
      await family.writeProjectInput(name, JSON.stringify(value));
    }
    const descriptor = join(output, 'consumer.json'), resultRoot = join(output, 'public');
    await save(descriptor, {requestKind, consumerRoot: consumer,
      ...(requestKind === 'source' ? {connectorPackage: '@actql-connectors/acme', connectorId: 'rest-acme',
        fixtureSecretPath: family.providerTokenPath} : {}),
      outputRoot: resultRoot, mode: selected.mode,
      installation: requestKind === 'source' ? prepared.installation
        : {directory: prepared.installation.directory, authorization: prepared.installation.authorization},
      stateRoots: requestKind === 'source' ? [family.paths.state, family.paths.credentialJournal] : [family.paths.state]});
    const child = fileURLToPath(new URL('./timed-consumer.mjs', import.meta.url));
    const childEnv = {...env, HOME: family.paths.home};
    await runInstalledFamilyProcess({script: child, args: [descriptor, 'read'], cwd: family.paths.project,
      env: childEnv, output: join(output, 'read-process.json')});
    const first = await read(join(resultRoot, 'read/outcome.json'));
    assert.equal(first.passed, true);assert.equal(first.publicCloseAcknowledged, true);assert.equal(first.scopedStateFd0, true);
    if (requestKind === 'source') provider.assertRequests();
    else assert.deepEqual(provider.requests(), []);
    assert.equal((await read(join(resultRoot, 'read/timed-consumer-report.json'))).passed, true);
    report.normalReadPassed = true;
    const firstRequests = provider.requests();
    const observedSource = (await tool('git', ['rev-parse', 'HEAD'], {cwd: root})).stdout.trim();
    assert.equal(observedSource, originalSource);
    const changedFrameworkFiles = (await tool('git', ['status', '--porcelain'], {cwd: root})).stdout;
    assert.equal(changedFrameworkFiles, '');
    const coreOrHostDiff = (await tool('git', ['diff', '--name-only', originalSource, '--',
      'src', 'adapters/host-node', 'adapters/host-common', 'adapters/site-node'], {cwd: root})).stdout
      .split('\n').filter(Boolean);
    await save(join(output, 'author-framework-source-after.json'), {source: observedSource,
      clean: changedFrameworkFiles === '', changedCoreOrHostFiles: coreOrHostDiff});
    // Retain actual fixture timing separately from the query's original time.
    // This is neither human author effort nor performance acceptance.
    await save(join(output, 'timed-observation-scope.json'), {requestKind,
      compilerInvocations: {observable: false, value: null},
      internalModuleInitializationCount: {observable: false, value: null},
      authoringMetrics: 'Not selected for W1', automatedIntroductionMs: performance.now() - introductionStart,
      timeScope: 'Functional fixture only, not latency/performance acceptance'});
    await runInstalledFamilyProcess({script: child, args: [descriptor, 'saved'], cwd: family.paths.project,
      env: childEnv, output: join(output, 'saved-process.json')});
    const saved = await read(join(resultRoot, 'saved/outcome.json'));
    assert.equal(saved.passed, true);assert.equal(saved.publicCloseAcknowledged, true);assert.equal(saved.scopedStateFd0, true);
    assert.equal((await read(join(resultRoot, 'saved/consumer-binding.json'))).secretResolutions, 0);
    assert.deepEqual(provider.requests(), firstRequests);
    assert.equal((await read(join(resultRoot, 'saved/timed-consumer-report.json'))).passed, true);
    report.originalSavedPassed = true;
    report.casePassed = true;
  } catch (cause) {primary = cause;report.failure = nodeBenchmarkFailure(cause);}
  finally {
    report.providerRequests = provider.requests();
    if (before !== undefined) {
      report.installedPayloadCheckAttempted = true;
      try {
        const after = await verifyNodeBenchmarkPackages(manifest, artifactManifestPath, consumer);
        const connector = pluginRoot === undefined ? [] : await inventory(pluginRoot);
        await save(join(output, 'installed-after.json'), {framework: after, connector});
        assert.deepEqual(after, before);
        assert.deepEqual(connector, expectedPlugin ?? []);
        report.installedPayloadsUnchanged = true;
      } catch (cause) {
        report.payloadVerificationFailure = nodeBenchmarkFailure(cause);
        primary ??= cause;report.casePassed = false;
      }
    }
    if (family !== undefined) {
      try {await family.https.close();report.fixtureTLSClosed = true;}
      catch (cause) {report.fixtureCloseFailure = nodeBenchmarkFailure(cause);primary ??= cause;report.casePassed = false;}
    }
    await save(join(output, 'report.json'), report);
  }
  if (primary) throw primary;
});
}
