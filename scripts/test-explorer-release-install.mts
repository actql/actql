// Install only the optional public entry into an empty consumer. ActQL comes
// from fixed private archives; third-party dependencies resolve normally.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {copyFile, mkdir, readFile, readdir, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createOwnedScratch} from './owned-scratch.mjs';
import {verifyPackageRelease} from './package-release.mjs';
import {openReleaseTestRegistry} from './release-test-registry.mjs';
import {auditPackedPackages} from './packed-package-boundaries.mjs';
import {checkoutState} from './packed-client-packages.mjs';
import {scaffoldProject} from '../packages/native-cli/lib/project-scaffold.mjs';

type ExecutionReceipt = {command: string; args: readonly string[]; startedAt: string;
  endedAt: string; code: number; stdout: string; stderr: string};
type ConsumerPackage = {version?: string; bin?: unknown; dependencies?: Record<string, string>;
  peerDependencies?: Record<string, string>; optionalDependencies?: Record<string, string>};

const [input, selection, evidenceInput] = process.argv.slice(2);
const savedContext = selection === '--saved-context';
const beforeRun = selection === '--before-run';
const dealReview = selection === '--deal-review';
const stop = selection === '--stop';
const interactive = savedContext || beforeRun || dealReview;
const hasEvidenceDirectory = interactive || stop;
assert(input && (process.argv.length === 3 || hasEvidenceDirectory && evidenceInput && process.argv.length === 5),
  'usage: test-explorer-release-install.mjs <Explorer-RC-directory> [--saved-context|--before-run|--deal-review|--stop <evidence-directory>]');
const directory = resolve(input);
const evidence = evidenceInput === undefined ? directory : resolve(evidenceInput);
const harness = hasEvidenceDirectory ? checkoutState(fileURLToPath(new URL('../', import.meta.url))) : undefined;
if (harness) {
  assert(harness.clean, 'Interactive Explorer acceptance requires clean test source');
  await mkdir(evidence);
}
const manifest = await verifyPackageRelease(directory);
assert.equal(manifest.cohort.version, 'actql-explorer-release-cohort/0.1');
if (stop || dealReview) {
  assert.equal(manifest.sourceSha, harness!.revision, 'Acceptance requires an exact source package cohort');
}
const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-explorer-install-',
  label: 'standalone Explorer fixed package installation'});
const consumer = scratch.path, registry = await openReleaseTestRegistry([{directory, manifest}]);
const environment: NodeJS.ProcessEnv = {...process.env, npm_config_cache: join(consumer, 'npm-cache'),
  npm_config_userconfig: join(consumer, 'npmrc'), npm_config_globalconfig: join(consumer, 'npmrc-global'),
  npm_config_update_notifier: 'false'};
for (const key of ['NODE_PATH', 'ACTQL_LOCAL_SOURCE_PROFILE', 'ACTQL_LOCAL_EFFECT_PROFILE',
  'ACTQL_PACKED_CLIENT_PACKAGES', 'npm_config_registry']) delete environment[key];
await writeFile(environment.npm_config_userconfig!,
  `registry=https://registry.npmjs.org/\n@actql:registry=${registry.url}\n`);
await writeFile(environment.npm_config_globalconfig!, '');
await writeFile(join(consumer, 'package.json'), '{"private":true,"type":"module"}\n');
async function run(command: string, args: readonly string[]) {
  const startedAt = new Date().toISOString();
  return new Promise<ExecutionReceipt>((resolve, reject) => {
    const child = spawn(command, args, {cwd: consumer, env: environment, stdio: ['ignore', 'pipe', 'pipe']});
    const timer = setTimeout(() => child.kill('SIGTERM'), 180000);
    let stdout = '', stderr = '', bytes = 0;
    for (const [stream, append] of [[child.stdout, (b: string) => {stdout += b;}], [child.stderr, (b: string) => {stderr += b;}]] as const) {
      stream.on('data', (chunk: Buffer) => {bytes += chunk.length;
        if (bytes > 8 * 1024 * 1024) child.kill('SIGTERM'); else append(chunk.toString());});
    }
    child.once('error', error => {clearTimeout(timer); reject(error);});
    child.once('close', (code, signal) => {
      clearTimeout(timer);
      if (code !== 0) {reject(Error(`Explorer consumer command failed ${code}/${signal}\n${stdout}\n${stderr}`)); return;}
      resolve({command, args, startedAt, endedAt: new Date().toISOString(), code, stdout, stderr});
    });
  });
}
try {
  const results = [await run('npm', ['install', '--no-audit', '--no-fund',
    `@actql/explorer@${manifest.cohort.packageVersion}`])];
  assert.deepEqual((await readdir(join(consumer, 'node_modules/@actql'))).sort(), [...manifest.cohort.packages].sort());
  for (const name of manifest.cohort.packages) {
    const metadata = JSON.parse(
      await readFile(join(consumer, 'node_modules/@actql', name, 'package.json')) as unknown as string,
    ) as ConsumerPackage;
    assert.equal(metadata.version, manifest.cohort.packageVersion);
    for (const field of ['dependencies', 'peerDependencies', 'optionalDependencies']) {
      for (const [dependency, version] of Object.entries(metadata[field as 'dependencies' | 'peerDependencies' | 'optionalDependencies'] ?? {})) {
        assert(!/^(?:file:|link:|workspace:)/u.test(version));
        if (dependency.startsWith('@actql/')) assert.equal(version, manifest.cohort.packageVersion);
      }
    }
    assert(!metadata.bin || !Object.hasOwn(metadata.bin, 'actql'));
  }
  assert.equal(JSON.parse(await readFile(join(consumer, 'node_modules/react/package.json')) as unknown as string).version, '19.3.0');
  results.push(await run('npm', ['ls', 'react', 'react-dom', '--all', '--json']));
  auditPackedPackages(consumer, manifest.cohort.packages);
  if (stop) {
    const fixture = join(consumer, 'stop.mjs');
    await copyFile(new URL('./fixtures/packed-explorer-stop.mjs', import.meta.url), fixture);
    results.push(await run(process.execPath, [fixture]));
  } else if (interactive) {
    const project = scaffoldProject(join(consumer, 'project'), savedContext ? 'churn-risk-mock' : 'deal-review-mock');
    const fixture = join(consumer, 'saved-context.mjs');
    await copyFile(new URL('./fixtures/packed-explorer-saved-context.mjs', import.meta.url), fixture);
    const phases = dealReview ? ['before', 'produce', 'restore'] : savedContext ? ['produce', 'restore'] : ['before'];
    for (const phase of phases) {
      results.push(await run(process.execPath, [fixture, phase, project.directory, evidence, ...(dealReview ? ['deal-review'] : [])]));
    }
  } else {
    results.push(await run(join(consumer, 'node_modules/.bin/actql-explorer'), ['--help']));
    await copyFile(new URL('./fixtures/explorer-installed-readonly.mjs', import.meta.url), join(consumer, 'read-only.mjs'));
    results.push(await run(process.execPath, ['read-only.mjs']));
  }
  assert(manifest.packages.every(p => registry.requested.includes(`archives/${p.file}`)));
  const receipt = {version: 'actql-explorer-install-acceptance/0.1', sourceSha: manifest.sourceSha,
    ...(harness === undefined ? {} : {harnessSourceSha: harness.revision}),
    artifacts: manifest.packages.map(({name, version, sha256, integrity}) => ({name, version, sha256, integrity})),
    consumer, node: process.version, platform: process.platform, arch: process.arch,
    registry: 'fixed-ActQL-loopback-and-normal-third-party-registry', publicPublication: false,
    installLockSha256: createHash('sha256').update(await readFile(join(consumer, 'package-lock.json'))).digest('hex'),
    browserInteractiveAcceptance: interactive, ...(stop ? {gatewayStopAcceptance: true} : {}), results};
  await writeFile(join(evidence, `explorer-install-${Date.now()}.json`), JSON.stringify(receipt, null, 2) + '\n', {flag: 'wx'});
  scratch.passed(); console.log(`Installed Explorer package acceptance passed: ${consumer}`);
} finally {await registry.close();}
