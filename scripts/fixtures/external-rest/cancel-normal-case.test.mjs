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
import {setTimeout as delay} from 'node:timers/promises';
import {createInstalledFamilyScenario} from './fixture-source/adapters/host-node/fixtures/installed-family-scenario.fixture.mjs';
import {runInstalledFamilyProcess} from './fixture-source/adapters/host-node/fixtures/installed-family-process.fixture.mjs';
import {inventory} from '../../package-release.mjs';
import {normalNpmPackJsonArgs, parseNpmPackJson} from '../../packed-client-packages.mjs';
import {verifyNodeBenchmarkPackages, nodeBenchmarkFailure} from '../../benchmark-node-operations.mjs';
import {externalRestDefinition, externalRestProvider} from './provider.fixture.mjs';
import {externalRestConfiguration} from './configuration.mjs';
import {prepareExternalRestCohort} from './installed-modules.mjs';
import {publishStandardRestBarrier} from './cancel-conformance.mjs';

const selectedInput = process.env.ACTQL_REST_CONFORMANCE_INPUT;
assert(typeof selectedInput === 'string' && isAbsolute(selectedInput),
  'Select an explicit matching normal cohort; no old installation or state default');
const read = async path => JSON.parse(await readFile(path, 'utf8'));
const save = (path, value) => writeFile(path, JSON.stringify(value, null, 2) + '\n', {flag: 'wx'});
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const tool = promisify(execFile);
const root = fileURLToPath(new URL('../../../', import.meta.url));

test('one generated npm REST connector cancels during its held original second page', async t => {
  const selected = await read(selectedInput);
  assert.deepEqual(Object.keys(selected).sort(), ['kind', 'sourceSha', 'sourceTree', 'manifestPath',
    'manifestSha256', 'outputRoot', 'accountConfigurationPath', 'mode'].sort());
  assert.equal(selected.kind, 'actql-standard-rest-normal/0.1');
  assert.equal(selected.mode, 'paged');
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
  const originalProvider = externalRestProvider({mode: selected.mode});
  const heldReply = Promise.withResolvers();
  const provider = Object.freeze({...originalProvider, async handle(request) {
    const reply = originalProvider.handle(request);
    if (request.target === '/v1/customers?after=page-2') {
      await publishStandardRestBarrier(join(output, 'public/page2-entered.json'), JSON.stringify({page: 2, replyHeld: true,
        originalFirstPageAlreadyReturned: true, recordedRequests: originalProvider.requests()}, null, 2) + '\n');
      await heldReply.promise;
    }
    return reply;
  }});
  const accountConfigurationWire = await readFile(selected.accountConfigurationPath, 'utf8');
  const report = {sourceSha: selected.sourceSha, sourceTree: selected.sourceTree,
    manifestSha256: selected.manifestSha256, mode: selected.mode, casePassed: false,
    midPageCancellationPassed: false, originalSavedExecuted: false, fixtureTLSClosed: false,
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
      scenario: {id: 'standard-rest-' + selected.mode}, accountConfigurationWire,
      provider, maxRequestBytes: 4096});
    await save(join(output, 'fixture-paths.json'), {paths: family.paths,
      resourceHttps: family.resourceHttps, providerTokenPath: family.providerTokenPath});
    const author = join(output, 'author'), packageRoot = join(output, 'connector-package');
    const cli = join(root, 'scripts/connector.mjs'), introductionStart = performance.now();
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
    assert.equal(packed.integrity, 'sha512-' + createHash('sha512').update(tarBytes).digest('base64'));
    await mkdir(consumer);await writeFile(join(consumer, 'package.json'), '{"private":true,"type":"module"}\n');
    // Default npm lifecycle, exact selected five framework tars plus the new
    // generated JS package. No prepack/compiler/provider supplier is rerun.
    await runTool('install-normal-six', 'npm', ['install', '--offline', '--no-audit', '--no-fund',
      ...manifest.packages.map(pkg => join(dirname(artifactManifestPath), pkg.file)), connectorTar], consumer);
    before = await verifyNodeBenchmarkPackages(manifest, artifactManifestPath, consumer);
    pluginRoot = join(consumer, 'node_modules/@actql-connectors/acme');
    assert.deepEqual(await inventory(pluginRoot), expectedPlugin);
    await save(join(output, 'installed-before.json'), {framework: before, connector: expectedPlugin,
      connectorTarSha256: sha(tarBytes), connectorTarIntegrity: packed.integrity});
    const prepared = externalRestConfiguration(family, {connectorId: 'rest-acme',
      profileVersion: 'actql-installed-acme-rest-source/0.1'});
    for (const [name, value] of Object.entries(prepared.files)) await family.writeProjectInput(name, JSON.stringify(value));
    const descriptor = join(output, 'consumer.json'), resultRoot = join(output, 'public');
    await save(descriptor, {consumerRoot: consumer, connectorPackage: '@actql-connectors/acme',
      connectorId: 'rest-acme', outputRoot: resultRoot, mode: selected.mode,
      fixtureSecretPath: family.providerTokenPath, installation: prepared.installation,
      stateRoots: [family.paths.state, family.paths.credentialJournal]});
    const child = fileURLToPath(new URL('./cancel-consumer.mjs', import.meta.url));
    const childEnv = {...env, HOME: family.paths.home};
    const processFlight = runInstalledFamilyProcess({script: child, args: [descriptor, 'cancel'],
      cwd: family.paths.project, env: childEnv, output: join(output, 'cancel-process.json')});
    const processSettled = processFlight.then(value => ({closed: true, value}),
      cause => ({closed: true, failed: true, cause}));
    const markerStop = new AbortController();
    const marker = async () => {
      const signal = AbortSignal.any([AbortSignal.timeout(30000), markerStop.signal]);
      while (true) {
        signal.throwIfAborted();
        try { return {marker: await read(join(resultRoot, 'cancel-returned.json'))}; }
        catch (cause) { if (cause.code !== 'ENOENT') throw cause; }
        await delay(10, undefined, {signal});
      }
    };
    try {
      const reached = await Promise.race([marker(), processSettled]);
      heldReply.resolve();
      if (reached.failed) throw reached.cause;
      assert(reached.marker, 'Original child exited before the public cancellation returned');
      await save(join(output, 'page-barrier-release.json'), {released: true,
        onlyAfterOriginalPublicCancelReturned: true, observation: reached.marker});
      const terminal = await processSettled;
      if (terminal.failed) throw terminal.cause;
      const observed = await read(join(resultRoot, 'cancel/outcome.json'));
      const close = await read(join(resultRoot, 'cancel/first-close.json'));
      assert.equal(observed.passed, true);assert.equal(observed.scopedStateFd0, true);
      assert.equal(close.acknowledged, true);assert.equal(close.businessPassed, true);
      const state = await read(join(resultRoot, 'cancel/terminal-state.json'));
      assert.equal(state.status, 'cancelled');assert.equal(state.result_available, false);
      assert.equal(state.control.physical_stop, 'confirmed');
      provider.assertRequests();report.midPageCancellationPassed = true;
    } finally { markerStop.abort(); heldReply.resolve(); }
    report.casePassed = true;
  } catch (cause) {primary = cause;report.failure = nodeBenchmarkFailure(cause);}
  finally {
    heldReply.resolve();
    report.providerRequests = provider.requests();
    if (before !== undefined && pluginRoot !== undefined) {
      report.installedPayloadCheckAttempted = true;
      try {
        const after = await verifyNodeBenchmarkPackages(manifest, artifactManifestPath, consumer);
        const connector = await inventory(pluginRoot);
        await save(join(output, 'installed-after.json'), {framework: after, connector});
        assert.deepEqual(after, before);
        assert.deepEqual(connector, expectedPlugin);
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
