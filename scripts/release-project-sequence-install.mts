// Existing Native RC consumer's optional public Node companion. This is fixture
// preparation, not a runtime supplier, serialized trust proof or publication.
import assert from 'node:assert/strict';
import {copyFile, lstat, mkdir, readFile, readdir, writeFile} from 'node:fs/promises';
import {dirname, join, resolve} from 'node:path';
import {constants} from 'node:fs';
import {verifyPackageRelease, inventory} from './package-release.mjs';

type NodeManifest = Awaited<ReturnType<typeof verifyPackageRelease>>;
type CohortIdentity = {sourceSha: NodeManifest['sourceSha'];
  cohort: Pick<NodeManifest['cohort'], 'packageVersion'>};
type Report = {pid: number; [field: string]: unknown};
type Run<Output> = (command: string, args: readonly string[], cwd: string, timeout?: number) => Output;
type Exit = {code: number | null; signal: NodeJS.Signals | null; stderr?: string; pid?: number};
type Label = {template: string; family: string; ordinal: number; phase: string};
type Preparation = {directory: string; nativeManifest: CohortIdentity;
  originalNodeManifest: NodeManifest; originalNodeManifestBytes: Buffer; root: string;
  repository: string; registry: {url: string}; run: Run<Promise<Exit>>;
  verifySource: () => void | Promise<void>; verifyManifest?: typeof verifyPackageRelease};
type Lock = {packages: Record<string, {dependencies?: Record<string, string>; version?: string;
  integrity?: string; link?: boolean; resolved: string}>};

export function assertReleaseProjectCohort(native: CohortIdentity, node: NodeManifest) {
  assert.equal(node.sourceSha, native.sourceSha, 'Sequence Node and Native must share the exact candidate');
  assert.equal(node.cohort.packageVersion, native.cohort.packageVersion);
  assert.deepEqual(node.cohort.packages, ['client-wire', 'sdk', 'local-node', 'node']);
  assert.deepEqual(node.packages.map(item => item.name).sort(),
    ['@actql/client-wire', '@actql/local-node', '@actql/node', '@actql/sdk']);
}

export function runReleaseProjectCli<Output>(run: Run<Output>, launcher: string, args: readonly string[], project: string) {
  // The original initializer creates the project; its cwd must already exist.
  // All later commands remain in that same independently owned project.
  return run(process.execPath, [launcher, ...args], args[0] === 'init' ? dirname(project) : project);
}

export async function prepareReleaseProjectNode({directory, nativeManifest, originalNodeManifest, originalNodeManifestBytes, root, repository,
  registry, run, verifySource, verifyManifest = verifyPackageRelease}: Preparation) {
  assert.equal(typeof verifySource, 'function');
  await verifySource();
  directory = resolve(directory);
  const manifest = await verifyManifest(directory);
  assert.deepEqual(manifest, originalNodeManifest, 'Use the exact Node cohort admitted before opening the registry');
  assertReleaseProjectCohort(nativeManifest, manifest);
  const originalManifest = await readFile(join(directory, 'release.json'));
  assert.deepEqual(originalManifest, originalNodeManifestBytes);
  const consumer = join(root, 'sequence-consumer'), observations = join(root, 'sequence-observations');
  const cases = join(root, 'sequence-cases');
  await mkdir(consumer); await mkdir(observations); await mkdir(cases); await mkdir(join(consumer, 'projects'));
  await writeFile(join(consumer, 'package.json'), '{"private":true,"type":"module"}\n', {flag: 'wx'});
  const installed = await run('npm', ['install', '--save-exact', '--ignore-scripts', '--engine-strict', '--no-audit', '--no-fund',
    `@actql/node@${manifest.cohort.packageVersion}`], consumer);
  assert.equal(installed.code, 0, installed.stderr); assert.equal(installed.signal, null);
  // Preserve the emitted fixture's relative imports in the installed consumer.
  const entry = 'scripts/fixtures/release-project-sequence-node.mjs';
  const fixtureBodies = new Map<string, Buffer>();
  for (const member of [entry, 'scripts/release-project-node-action.mjs',
    'adapters/host-node/fixtures/work-observation.fixture.mjs']) {
    const source = join(repository, member), destination = join(consumer, member);
    await mkdir(dirname(destination), {recursive: true});
    fixtureBodies.set(member, await readFile(source));
    await copyFile(source, destination, constants.COPYFILE_EXCL);
  }

  async function verify() {
    await verifySource();
    for (const [name, bytes] of fixtureBodies) assert.deepEqual(await readFile(join(consumer, name)), bytes,
      'Prepared sequence fixture changed');
    assert.deepEqual(await readFile(join(directory, 'release.json')), originalManifest);
    assert.deepEqual(await verifyManifest(directory), manifest);
    const scope = join(consumer, 'node_modules/@actql');
    for (const path of [consumer, join(consumer, 'node_modules'), scope]) {
      const value = await lstat(path); assert(value.isDirectory() && !value.isSymbolicLink());
    }
    assert.deepEqual((await readdir(scope)).sort(), [...manifest.cohort.packages].sort());
    const lock = JSON.parse(await readFile(join(consumer, 'package-lock.json'), 'utf8')) as Lock;
    assert.deepEqual(lock.packages[''].dependencies, {'@actql/node': manifest.cohort.packageVersion});
    assert.deepEqual(Object.keys(lock.packages).filter(path => /(?:^|\/)node_modules\/@actql\//u.test(path)).sort(),
      manifest.packages.map(item => 'node_modules/' + item.name).sort());
    for (const item of manifest.packages) {
      const path = join(consumer, 'node_modules', item.name), metadata = await lstat(path);
      assert(metadata.isDirectory() && !metadata.isSymbolicLink(), 'No source package link');
      assert.deepEqual(await inventory(path, '', {ignoreInstalledDependencies: true}), item.files);
      const installed = lock.packages['node_modules/' + item.name];
      assert.equal(installed.version, item.version); assert.equal(installed.integrity, item.integrity);
      assert.notEqual(installed.link, true);
      const url = new URL(installed.resolved);
      assert.equal(url.origin, new URL(registry.url).origin);
      assert.equal(url.pathname, '/archives/' + item.file);
      assert(!url.username && !url.password && !url.search && !url.hash);
    }
  }
  await verify();
  let serial = 0;
  const node = async (request: unknown, project: string, label: Label) => {
    await verify();
    const base = join(observations, `${label.template}-${label.family}-${label.ordinal}-${label.phase}-${++serial}`);
    const input = base + '.request.json', output = base + '.response.json';
    await writeFile(input, JSON.stringify(request) + '\n', {flag: 'wx', mode: 0o600});
    let primary: unknown, failed = false, response: Report | undefined;
    try {
      const child = await run(process.execPath, [join(consumer, entry), input, output], project, 30_000);
      assert.equal(child.code, 0, child.stderr); assert.equal(child.signal, null);
      response = JSON.parse(await readFile(output, 'utf8')) as Report;
      assert.equal(response.pid, child.pid, 'Node report belongs to the actual exited child');
    } catch (cause) {primary = cause; failed = true;}
    try {await verify();} catch (cause) {if (!failed) {primary = cause; failed = true;}}
    if (failed) throw primary;
    return response;
  };
  return {consumer, projects: join(consumer, 'projects'), observations, cases, manifest, verify, node};
}
