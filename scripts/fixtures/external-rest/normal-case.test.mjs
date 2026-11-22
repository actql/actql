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
import {createAuthorRestProvider, readAuthorRestCase, readRestConformanceInput} from './conformance-input.mjs';
import {readAuthorPackage, selectAuthorPackage, stageAuthorDefinition, stagePackedAuthorPackage} from './author-package.mjs';
import {normalNpmPackJsonArgs, parseNpmPackJson} from '../../packed-client-packages.mjs';
import {verifyNodeBenchmarkPackages, nodeBenchmarkFailure} from '../../benchmark-node-operations.mjs';
import {externalRestDefinition, externalRestProvider} from './provider.fixture.mjs';
import {externalRestConfiguration} from './configuration.mjs';
import {prepareExternalRestCohort} from './installed-modules.mjs';
import {isInstalledAuthoringToolkit, observeInstalledAuthoringToolkit} from '../../connector-authoring-toolkit.mjs';
import {notionUsersProvider,notionUsersConfiguration} from './notion-users.fixture.mjs';

const selectedInput = process.env.ACTQL_REST_CONFORMANCE_INPUT;
assert(typeof selectedInput === 'string' && isAbsolute(selectedInput),
  'Select an explicit matching normal cohort; no old installation or state default');
const read = async path => JSON.parse(await readFile(path, 'utf8'));
const save = (path, value) => writeFile(path, JSON.stringify(value, null, 2) + '\n', {flag: 'wx'});
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const tool = promisify(execFile);
const root = fileURLToPath(new URL('../../../', import.meta.url));

test('one generated npm REST connector uses ordinary Node Host and original cold Saved', async t => {
  const selected = readRestConformanceInput(selectedInput);
  const builtin = selected.mode === 'notion-users';
  const authorCase = selected.mode === 'author' ? readAuthorRestCase(selected.casePath, selected.caseSha256) : undefined;
  const selectedAuthor = authorCase && selectAuthorPackage(selected.casePath, authorCase);
  // Verify the selected bytes before npm lifecycle or fixture/key creation.
  // Installed payload correspondence remains the original separate check.
  const cohort = await prepareExternalRestCohort(selected);
  const {manifest, artifactManifestPath, originalBindings, offeredTarballs, hostPackageVersion} = cohort;
  const installedToolkit = isInstalledAuthoringToolkit(root);
  await assert.rejects(lstat(selected.outputRoot), {code: 'ENOENT'});
  await mkdir(selected.outputRoot, {mode: 0o700});
  const output = selected.outputRoot, consumer = join(output, 'consumer'), commands = [];
  const provider = authorCase ? createAuthorRestProvider(authorCase)
    : builtin ? notionUsersProvider() : externalRestProvider({mode: selected.mode});
  const accountConfigurationWire = await readFile(selected.accountConfigurationPath, 'utf8');
  const report = {sourceSha: selected.sourceSha, sourceTree: selected.sourceTree,
    manifestSha256: selected.manifestSha256, mode: selected.mode, casePassed: false,
    ...(authorCase ? {authorCase: {id: authorCase.id, sha256: selected.caseSha256,
      connector: authorCase.connector, schema: authorCase.schema}} : {}),
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
    const originalSource = installedToolkit ? await observeInstalledAuthoringToolkit(root, cohort) : {
      source: (await tool('git', ['rev-parse', 'HEAD'], {cwd: root})).stdout.trim(), clean: true};
    if (!installedToolkit) assert.equal((await tool('git', ['status', '--porcelain'], {cwd: root})).stdout, '',
      'Authoring tools must stay frozen while the ordinary case runs');
    await save(join(output, 'author-framework-source-before.json'), originalSource);
    let plugin = selectedAuthor?.bytes === undefined ? undefined
      : await stagePackedAuthorPackage(output, authorCase, selectedAuthor.bytes, hostPackageVersion);
    if (authorCase) await save(join(output, 'fixture-before.json'), provider.assertState('before'));
    family = await createInstalledFamilyScenario(t, {scratchParent: output,
      scenario: {id: 'standard-rest-' + (authorCase?.id ?? selected.mode)}, accountConfigurationWire,
      provider, maxRequestBytes: 4096, port: authorCase?.protocol.port});
    await save(join(output, 'fixture-paths.json'), {paths: family.paths,
      resourceHttps: family.resourceHttps, providerTokenPath: family.providerTokenPath});
    await mkdir(consumer);await writeFile(join(consumer, 'package.json'), '{"private":true,"type":"module"}\n');
    await runTool('install-normal-five', 'npm', ['install', '--offline', '--no-audit', '--no-fund',
      ...manifest.packages.map(pkg => join(dirname(artifactManifestPath), pkg.file))], consumer);
    before = await verifyNodeBenchmarkPackages(manifest, artifactManifestPath, consumer);
    // The author tool resolves only this consumer's already installed public
    // pure validator. No new Common build or framework pack occurs here.
    const author = join(consumer, 'author'), packageRoot = join(output, 'connector-package');
    const cli = join(root, 'scripts/connector.mjs'), introductionStart = performance.now();
    const authorCommandCwd = installedToolkit ? consumer : root;
    const registration = authorCase?.schema.registration ?? 'acme';
    const generated = !builtin && plugin === undefined;
    if (generated) {
      await runInstalledFamilyProcess({script: cli, args: ['init', author, registration], cwd: authorCommandCwd, env,
        output: join(output, 'author-init-process.json')});
      commands.push({name: 'author-init', command: process.execPath, args: [cli, 'init', author, registration]});
      const definitionPath = await stageAuthorDefinition(author,
        selectedAuthor ?? {definition: externalRestDefinition(family.resourceHttps.origin)},
        family.resourceHttps.origin);
      await runInstalledFamilyProcess({script: cli, args: ['build', definitionPath, packageRoot], cwd: authorCommandCwd, env,
        output: join(output, 'author-build-process.json')});
      commands.push({name: 'author-build', command: process.execPath, args: [cli, 'build', definitionPath, packageRoot]});
      // Freshness is the exposed author test, independent of the actual Run.
      if (authorCase) {
        await runTool('author-test', process.execPath, [cli, 'test', definitionPath, packageRoot], authorCommandCwd);
      }
      const artifacts = join(output, 'artifacts');
      await mkdir(artifacts);
      const packedOutput = parseNpmPackJson(await runTool('pack-connector', 'npm',
        normalNpmPackJsonArgs(['pack', '--offline', '--json', '--pack-destination', artifacts]), packageRoot));
      const packages = Array.isArray(packedOutput) ? packedOutput : Object.values(packedOutput);
      assert.equal(packages.length, 1);
      const [packed] = packages;
      const manifest = authorCase ? await readAuthorPackage(packageRoot, authorCase.schema, family.resourceHttps.origin, hostPackageVersion)
        : {name: '@actql-connectors/acme', profileVersion: 'actql-installed-acme-rest-source/0.1',
          files: await inventory(packageRoot)};
      assert.equal(packed.name, manifest.name);
      const tar = join(artifacts, packed.filename);
      const bytes = await readFile(tar);
      assert.equal(packed.integrity, 'sha512-' + createHash('sha512').update(bytes).digest('base64'));
      plugin = {...manifest, tar, bytes, integrity: packed.integrity};
    }
    // Use the same normal install and byte-for-byte payload checks for a
    // caller-supplied archive and for one built with the installed validator.
    if (plugin) {
      await runTool('install-normal-connector', 'npm', ['install', '--offline', '--no-audit', '--no-fund', plugin.tar], consumer);
      assert.deepEqual(await verifyNodeBenchmarkPackages(manifest, artifactManifestPath, consumer), before);
      expectedPlugin = plugin.files;
      pluginRoot = join(consumer, 'node_modules', plugin.name);
      assert.deepEqual(await inventory(pluginRoot), expectedPlugin);
      assert.equal(sha(await readFile(plugin.tar)), sha(plugin.bytes));
    }
    await save(join(output, 'installed-before.json'), {framework: before,
      ...(builtin ? {builtin: 'notion'} : {connector: expectedPlugin,
        connectorTarSha256: sha(plugin.bytes), connectorTarIntegrity: plugin.integrity})});
    const connectorId = authorCase?.connection ?? (builtin ? 'notion-users' : 'rest-acme');
    const prepared = builtin ? notionUsersConfiguration(family, {connectorId})
      : externalRestConfiguration(family, {connectorId, profileVersion: plugin.profileVersion});
    for (const [name, value] of Object.entries(prepared.files)) await family.writeProjectInput(name, JSON.stringify(value));
    const descriptor = join(output, 'consumer.json'), resultRoot = join(output, 'public');
    await save(descriptor, {consumerRoot: consumer, ...(builtin ? {family: 'notion-users'} : {connectorPackage: plugin.name}),
      ...(authorCase ? {author: {program: authorCase.program, parameters: authorCase.parameters,
        expected: {rows: authorCase.expected.rows}}} : {}),
      connectorId, outputRoot: resultRoot, mode: selected.mode,
      fixtureSecretPath: family.providerTokenPath, installation: prepared.installation,
      stateRoots: [family.paths.state, family.paths.credentialJournal]});
    const child = fileURLToPath(new URL('./consumer.mjs', import.meta.url));
    const childEnv = {...env, HOME: family.paths.home};
    await runInstalledFamilyProcess({script: child, args: [descriptor, 'read'], cwd: family.paths.project,
      env: childEnv, output: join(output, 'read-process.json')});
    const first = await read(join(resultRoot, 'read/outcome.json'));
    assert.equal(first.passed, true);assert.equal(first.publicCloseAcknowledged, true);assert.equal(first.scopedStateFd0, true);
    const firstTransport = family.https.seen();
    provider.assertRequests(firstTransport);
    if (authorCase) await save(join(output, 'fixture-after-read.json'), provider.assertState('after'));
    report.normalReadPassed = true;
    const firstRequests = provider.requests();
    let coreOrHostDiff;
    if (!installedToolkit) {
      const observedSource = (await tool('git', ['rev-parse', 'HEAD'], {cwd: root})).stdout.trim();
      assert.equal(observedSource, originalSource.source);
      const changedFrameworkFiles = (await tool('git', ['status', '--porcelain'], {cwd: root})).stdout;
      assert.equal(changedFrameworkFiles, '');
      coreOrHostDiff = (await tool('git', ['diff', '--name-only', originalSource.source, '--',
        'src', 'adapters/host-node', 'adapters/host-common', 'adapters/site-node'], {cwd: root})).stdout
        .split('\n').filter(Boolean);
      await save(join(output, 'author-framework-source-after.json'), {source: observedSource,
        clean: changedFrameworkFiles === '', changedCoreOrHostFiles: coreOrHostDiff});
    }
    // Record automated author effort only AFTER the first actual ordinary
    // read and close pass. This is not human typing time or latency acceptance.
    if (generated) {
      const definitionPath=join(author,'connector.json');
      const authorBytes = await readFile(definitionPath), definition = JSON.parse(authorBytes);
      await save(join(output, 'authoring-metrics.json'), {handwrittenConnectorFiles: ['connector.json'],
        handwrittenConnectorLines: authorBytes.toString('utf8').trimEnd().split('\n').length,
        handwrittenOptionalJsFiles: definition.transform === undefined ? 0 : 1,
        authorCallbacks: definition.transform === undefined ? 0 : 1,
        generatedFiles: expectedPlugin.map(file => file.path),
        commandsThroughFirstRead: commands.length + 1,
        automatedIntroductionSeconds: (performance.now() - introductionStart) / 1000,
        timeScope: 'CLI scaffold/build, generated package pack, fresh ordinary install, public read/first close',
        handwrittenConnectorMoonBitFiles: expectedPlugin.filter(file => /\.(?:mbt|mbti)$|(?:^|\/)moon\.(?:pkg|mod)$/u.test(file.path)).length,
        ...(coreOrHostDiff === undefined ? {authoringToolkit: 'installed'}
          : {perConnectorCoreOrHostEdits: coreOrHostDiff.length, changedCoreOrHostFiles: coreOrHostDiff}),
        mechanism: 'existing public installation.connectorTable; no source/Host patch or compiler command',
        normalSourceSha: selected.sourceSha, normalSourceTree: selected.sourceTree,
        humanTypingTimeMeasured: false, performanceAcceptance: false});
    }
    await runInstalledFamilyProcess({script: child, args: [descriptor, 'saved'], cwd: family.paths.project,
      env: childEnv, output: join(output, 'saved-process.json')});
    const saved = await read(join(resultRoot, 'saved/outcome.json'));
    assert.equal(saved.passed, true);assert.equal(saved.publicCloseAcknowledged, true);assert.equal(saved.scopedStateFd0, true);
    assert.equal((await read(join(resultRoot, 'saved/consumer-binding.json'))).secretResolutions, 0);
    assert.deepEqual(provider.requests(), firstRequests);
    assert.deepEqual(family.https.seen(), firstTransport);
    if (authorCase) await save(join(output, 'fixture-after-saved.json'), provider.assertState('after'));
    if (installedToolkit) {
      const observedSource = await observeInstalledAuthoringToolkit(root, cohort);
      assert.deepEqual(observedSource, originalSource);
      await save(join(output, 'author-framework-source-after.json'), observedSource);
    }
    report.originalSavedPassed = true;
    report.casePassed = true;
  } catch (cause) {primary = cause;report.failure = nodeBenchmarkFailure(cause);}
  finally {
    report.providerRequests = provider.requests();
    if (before !== undefined) {
      report.installedPayloadCheckAttempted = true;
      try {
        const after = await verifyNodeBenchmarkPackages(manifest, artifactManifestPath, consumer);
        const connector = pluginRoot===undefined?undefined:await inventory(pluginRoot);
        await save(join(output, 'installed-after.json'), {framework: after, connector});
        assert.deepEqual(after, before);
        if (pluginRoot !== undefined) assert.deepEqual(connector, expectedPlugin);
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
