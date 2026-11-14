// One ordinary installed wait. No runtime producer or formal latency assessor.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFileSync, spawn} from 'node:child_process';
import {copyFile, mkdir, readFile, writeFile} from 'node:fs/promises';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';

const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const load = (root, name) => import(pathToFileURL(join(root, 'scripts', name)).href);
const save = (path, value) => writeFile(path, JSON.stringify(value, null, 2) + '\n', {flag: 'wx'});

export function verifyNodeWaitArchive(bytes, producer, expectedDigest) {
  assert.match(expectedDigest, /^[a-f0-9]{64}$/u);
  assert.equal(producer.artifactDigest, 'sha256:' + expectedDigest);
  assert(bytes.length > 0 && bytes.length <= 64 * 1024 ** 2);
  assert.equal(hash(bytes), expectedDigest, 'Original artifact ZIP digest differs');
}

// Retain only locations in verified installed members, never raw file URLs or
// state paths. Samples and inclusive stacks are observations, not call counts.
export function summarizeNodeWaitProfile(profile, consumer, packages) {
  assert(Array.isArray(profile.nodes) && profile.nodes.length <= 100000);
  assert(Array.isArray(profile.samples) && profile.samples.length > 0 && profile.samples.length <= 2000000);
  const members = new Map(packages.flatMap(pkg => pkg.files.map(file =>
    [pathToFileURL(join(consumer, 'node_modules', pkg.name, file.path)).href,
      {package: pkg.name, member: file.path, sha256: file.sha256}])));
  const nodes = new Map(), parent = new Map(), self = new Map(), inclusive = new Map();
  for (const node of profile.nodes) {
    assert(Number.isSafeInteger(node.id) && !nodes.has(node.id)); nodes.set(node.id, node);
    for (const child of node.children ?? []) {assert(!parent.has(child)); parent.set(child, node.id);}
  }
  for (const id of profile.samples) {assert(nodes.has(id)); self.set(id, (self.get(id) ?? 0) + 1);}
  for (const [id, samples] of self) {
    let current = id; const visited = new Set();
    while (current !== undefined) {
      assert(nodes.has(current) && !visited.has(current) && visited.size < 512);
      visited.add(current); inclusive.set(current, (inclusive.get(current) ?? 0) + samples);
      current = parent.get(current);
    }
  }
  const top = counts => [...counts].sort((a, b) => b[1] - a[1] || a[0] - b[0]).slice(0, 40)
    .map(([id, samples]) => {
      const frame = nodes.get(id).callFrame;
      const member = members.get(frame.url);
      const name = typeof frame.functionName === 'string' &&
        /^[A-Za-z0-9_$.:<> ()-]{0,160}$/u.test(frame.functionName) ? frame.functionName : '[unresolved]';
      return {functionName: name, samples, share: samples / profile.samples.length,
        ...(member ?? {package: null, member: null}),
        line: member && Number.isSafeInteger(frame.lineNumber) ? frame.lineNumber : null,
        column: member && Number.isSafeInteger(frame.columnNumber) ? frame.columnNumber : null};
    });
  return {samples: profile.samples.length, nodes: nodes.size, mainThreadOnly: true,
    topSelf: top(self), topInclusive: top(inclusive),
    qualification: 'Instrumented one-wait CPU samples; no call counts, causal speedup, percentile or worker/subprocess CPU claim.'};
}

async function downloadOriginalArtifact(options, producer) {
  const response = await fetch(`https://api.github.com/repos/${options.repository}/actions/artifacts/${options.artifactId}/zip`, {
    headers: {Accept: 'application/vnd.github+json', Authorization: `Bearer ${options.token}`,
      'X-GitHub-Api-Version': '2022-11-28'}, redirect: 'manual', signal: AbortSignal.timeout(30000)});
  assert.equal(response.status, 302, 'Original archive redirect unavailable');
  const location = new URL(response.headers.get('location'));
  assert.equal(location.protocol, 'https:');
  // The signed redirect needs no GitHub credential. Never forward it.
  const archive = await fetch(location, {redirect: 'error', signal: AbortSignal.timeout(90000)});
  assert(archive.ok && archive.body, 'Original archive unavailable');
  const chunks = []; let bytes = 0;
  for await (const chunk of archive.body) {
    bytes += chunk.length; assert(bytes <= 64 * 1024 ** 2, 'Original archive exceeds finite diagnostic bound');
    chunks.push(chunk);
  }
  const result = Buffer.concat(chunks); verifyNodeWaitArchive(result, producer, options.expectedDigest);
  return result;
}

async function artifact(root, output) {
  const {inspectPerformancePackageProducer} = await load(root, 'ordinary-operation-packages.mjs');
  const options = {repository: process.env.GITHUB_REPOSITORY, sourceSha: process.env.PACKAGE_EVENT_HEAD_SHA,
    runId: process.env.PACKAGE_RUN_ID, artifactId: process.env.PACKAGE_ARTIFACT_ID,
    token: process.env.GITHUB_TOKEN, expectedDigest: process.env.PACKAGE_ARCHIVE_SHA256};
  assert.match(process.env.PACKAGE_BUILD_SOURCE_SHA, /^[a-f0-9]{40}$/u);
  const producer = await inspectPerformancePackageProducer(options);
  await save(join(output, 'producer.json'), producer);
  const bytes = await downloadOriginalArtifact(options, producer);
  const archive = join(output, 'original.zip'); await writeFile(archive, bytes, {flag: 'wx'});
  const packages = join(output, 'packages'); await mkdir(packages);
  execFileSync('python3', ['-c', `import zipfile,pathlib,json,hashlib,sys
p=pathlib.Path(sys.argv[2])
with zipfile.ZipFile(sys.argv[1]) as z:
 m=json.loads(z.read('packed-client-packages.json'))
 names=['packed-client-packages.json']+['actql-'+k+'-0.0.0-development.tgz' for k in ['client-wire','sdk','run-host-core','local-node','node']]
 assert sorted(z.namelist())==sorted(names)
 assert sorted(m['tarballs'])==sorted(['client-wire','sdk','run-host-core','local-node','node'])
 for n in names:
  assert z.getinfo(n).file_size<=64*1024**2
  data=z.read(n)
  if n.endswith('.tgz'):
   key=n[len('actql-'):-len('-0.0.0-development.tgz')]
   assert hashlib.sha256(data).hexdigest()==m['tarballs'][key]
  (p/n).write_bytes(data)
`, archive, packages], {timeout: 30000, maxBuffer: 1024 * 1024});
  const binding = await inspectPerformancePackageProducer({...options, packages, adapter: 'node'});
  assert.equal(binding.sourceSha, process.env.PACKAGE_BUILD_SOURCE_SHA);
  await save(join(output, 'source.json'), binding);
}

async function inside(root, output) {
  assert.equal(process.platform, 'linux'); assert.equal(process.arch, 'x64');
  assert.equal(process.version, 'v22.22.0'); assert(process.getuid() !== 0);
  const {checkoutState} = await load(root, 'packed-client-packages.mjs');
  const {prepareHealthPackages} = await load(root, 'health-monitor-adapters.mjs');
  const {verifyNodeBenchmarkPackages} = await load(root, 'benchmark-node-operations.mjs');
  const binding = JSON.parse(await readFile(join(output, 'source.json')));
  const source = checkoutState(root);
  assert.deepEqual(source, {revision: binding.sourceSha, clean: true});
  const normal = join(output, 'packages', 'packed-client-packages.json');
  assert.equal(hash(await readFile(normal)), binding.manifestSha256);
  const report = {qualification: 'One instrumented ordinary-package wait; not formal performance acceptance',
    sourceSha: source.revision, sourceTreeSha: binding.sourceTreeSha, manifestSha256: binding.manifestSha256,
    diagnosticSha256: hash(await readFile(fileURLToPath(import.meta.url))), complete: false};
  // An outer timeout may prevent the final report; this never asserts a stop
  // or close and remains separate from the final observed result.
  await save(join(output, 'cpu-pending.json'), report);
  let stage = 'default-lifecycle installation';
  const command = async (command, args, {cwd, name}) => {
    const child = spawn(command, args, {cwd, env: {...process.env,
      PATH: dirname(process.execPath) + ':' + process.env.PATH,
      npm_config_cache: join(output, 'npm-cache')}, stdio: ['ignore', 'pipe', 'pipe']});
    let count = 0; const chunks = [];
    for (const stream of [child.stdout, child.stderr]) stream.on('data', chunk => {
      count += chunk.length; if (count <= 4 * 1024 ** 2) chunks.push(chunk);
    });
    const code = await new Promise((yes, no) => {child.on('error', no); child.on('close', yes);});
    await writeFile(join(output, name + '.log'), Buffer.concat(chunks), {flag: 'wx'});
    assert(count <= 4 * 1024 ** 2 && code === 0, 'Original consumer command failed: ' + name);
  };
  try {
    const installed = join(output, 'installed'); await mkdir(installed);
    const prepared = await prepareHealthPackages({repository: root, root: installed,
      source: {sha: source.revision, dirty: false}, retained: normal, command, normalLifecycle: true});
    report.packages = prepared.manifest.packages.map(({name, sha256, integrity, files}) =>
      ({name, sha256, integrity, files: files.length}));
    const actor = join(prepared.consumer, 'diagnostic.mjs');
    await copyFile(join(output, 'actor.mjs'), actor);
    await copyFile(join(root, 'scripts/fixtures/record-approval/scoped-fds.fixture.mjs'),
      join(prepared.consumer, 'scoped-fds.fixture.mjs'));
    report.actorSha256 = hash(await readFile(actor));
    stage = 'one original wait';
    await command(process.execPath, [actor, output], {cwd: prepared.consumer, name: 'consumer'});
    report.consumer = JSON.parse(await readFile(join(output, 'consumer.json')));
    stage = 'unchanged installed payload';
    await verifyNodeBenchmarkPackages(prepared.manifest, prepared.manifestPath, prepared.consumer);
    assert.deepEqual(checkoutState(root), source);
    report.installedPayloadUnchanged = true;
    stage = 'same-profile attribution';
    const bytes = await readFile(join(output, 'wait.cpuprofile'));
    assert(bytes.length <= 64 * 1024 ** 2); report.profileSha256 = hash(bytes);
    report.cpu = summarizeNodeWaitProfile(JSON.parse(bytes), prepared.consumer, prepared.manifest.packages);
    report.complete = report.consumer.complete && report.cpu.samples > 0;
  } catch (error) {
    report.failure = {stage, name: error.name, code: error.code ?? null};
    // Preserve the original failed child report without another product call.
    try {report.consumer = JSON.parse(await readFile(join(output, 'consumer.json')));} catch { /* Unexecuted or incomplete child. */ }
  } finally {await save(join(output, 'cpu.json'), report);}
  assert(report.complete, 'Original wait CPU diagnostic incomplete');
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [mode, root, output, ...extra] = process.argv.slice(2);
  assert(root && output && extra.length === 0);
  if (mode === 'artifact') await artifact(resolve(root), resolve(output));
  else if (mode === 'inside') await inside(resolve(root), resolve(output));
  else {
    assert.equal(mode, 'collect');
    const {runLocalCheck} = await load(root, 'local-checks-guard.mjs');
    process.exitCode = await runLocalCheck({root, heavy: true,
      heavyResources: {memoryBytes: 6 * 1024 ** 3, diskBytes: 1024 ** 3, cpuThreads: 1},
      timeoutSeconds: 600, graceSeconds: 10, steps: [{name: 'one installed Node wait CPU diagnostic',
        command: process.execPath, args: [fileURLToPath(import.meta.url), 'inside', root, output]}]});
  }
}
