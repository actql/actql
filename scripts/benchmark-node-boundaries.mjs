// A selected ordinary-package boundary collector, not a product implementation
// or a latency measurement. It never prepares packages or issues Host ports.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {constants} from 'node:fs';
import {lstat, mkdir, open as openFile, readFile, writeFile} from 'node:fs/promises';
import {arch, cpus, platform, release, totalmem} from 'node:os';
import {join, resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {nodeOperationProtocol, verifyNodeBenchmarkPackages} from './benchmark-node-operations.mjs';
import {assessBoundaries} from './operation-performance.mjs';

const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const identity = value => hash(Buffer.from(JSON.stringify(value)));
const cidHex = cid => {assert.match(cid, /^sha256:[0-9a-f]{64}$/u); return cid.slice(7);};
const errorRecord = error => ({name: error?.name ?? null, code: error?.code ?? null,
  message: error?.message ?? String(error), cleanupPending: error?.cleanupPending === true});

// This only locates the fault target in this collector's new state. It grants
// no authority and does not replace the product's typed/current Store checks.
async function mutateSelectedMaterial(stateDir, ref, output) {
  const publication = join(stateDir, 'publication');
  for (const directory of [stateDir, publication, ...['indexes', 'contracts', 'objects']
    .map(name => join(publication, name))]) {
    const info = await lstat(directory);
    assert(info.isDirectory() && !info.isSymbolicLink(), 'Fault target directory must be original');
  }
  const indexHash = createHash('sha256').update('actql-local-public-index-key/0.1\0');
  for (const text of [ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid]) {
    assert.equal(typeof text, 'string');
    const bytes = Buffer.from(text), length = Buffer.alloc(8);
    length.writeBigUInt64BE(BigInt(bytes.length)); indexHash.update(length).update(bytes);
  }
  const readObject = async path => {
    const file = await openFile(path, constants.O_RDONLY | constants.O_NOFOLLOW);
    try {
      const info = await file.stat();
      assert(info.isFile() && info.size <= 1024 ** 2, 'Selected fixture metadata exceeds bounded input');
      return JSON.parse(await file.readFile('utf8'));
    }
    finally {await file.close();}
  };
  const index = await readObject(join(publication, 'indexes', indexHash.digest('hex') + '.json'));
  assert.equal(index.namespace_id, ref.namespaceId);
  assert.equal(index.authority_scope_cid, ref.authorityScopeCid);
  assert.equal(index.run_definition_cid, ref.runDefinitionCid);
  assert.equal(index.durable_result_binding_cids?.length, 1, 'Selected seed must have one Result binding');
  const bindingCid = index.durable_result_binding_cids[0];
  const binding = await readObject(join(publication, 'contracts', cidHex(bindingCid) + '.json'));
  assert.equal(binding.run_definition_cid, ref.runDefinitionCid);
  const definition = await readObject(join(publication, 'contracts', cidHex(binding.result_definition_cid) + '.json'));
  assert.equal(definition.result_name, 'main');
  const materialCid = binding.material_generation_cid;
  const path = join(publication, 'objects', cidHex(materialCid));
  const file = await openFile(path, constants.O_RDWR | constants.O_NOFOLLOW);
  try {
    const before = await file.stat();
    assert(before.isFile() && before.size > 0 && before.size <= 1024 ** 2 && before.size === binding.byte_count,
      'Selected one-row fixture exceeds bounded material input');
    const bytes = await file.readFile();
    assert(bytes.length > 0 && bytes.length === binding.byte_count);
    assert.equal(hash(bytes), cidHex(materialCid));
    await writeFile(join(output, 'original-selected-generation.bin'), bytes, {flag: 'wx', mode: 0o600});
    const offset = bytes.length - 1, changed = Buffer.from([bytes[offset] ^ 1]);
    assert.equal((await file.write(changed, 0, 1, offset)).bytesWritten, 1);
    const after = await file.stat();
    assert.equal(after.dev, before.dev); assert.equal(after.ino, before.ino); assert.equal(after.size, before.size);
    return {bindingCid, resultDefinitionCid: binding.result_definition_cid, materialCid,
      bytes: bytes.length, offset, originalSha256: hash(bytes), device: before.dev, inode: before.ino};
  } finally {await file.close();}
}

export async function runNodeUsedMaterialBoundary({manifestPath, consumer, output, controlsPath, mode = 'diagnostic'}) {
  assert(['diagnostic', 'final'].includes(mode));
  consumer = resolve(consumer); output = resolve(output);
  const manifestBytes = await readFile(manifestPath), manifest = JSON.parse(manifestBytes);
  const controls = JSON.parse(await readFile(controlsPath));
  assert.match(manifest.sourceSha, /^[a-f0-9]{40}$/u);
  assert.equal(controls.sourceSha, manifest.sourceSha);
  assert.equal(controls.cohortSha256, hash(manifestBytes));
  const environment = {platform: platform(), arch: arch(), osRelease: release(), node: process.version,
    cpuModel: cpus()[0].model, logicalCpus: cpus().length, memoryBytes: totalmem()};
  assert.deepEqual(controls.environment, environment);
  const protocol = nodeOperationProtocol(mode);
  assert.equal(controls.historyProtocolSha256, identity(protocol), 'Boundary requires the complete shared experiment protocol');
  const before = await verifyNodeBenchmarkPackages(manifest, manifestPath, consumer);
  await mkdir(output, {mode: 0o700}); // Never reuse an existing state or output.
  const stateDir = join(output, 'new-state');
  const sectionIdentity = {cohortSha256: hash(manifestBytes), environmentSha256: identity(environment),
    historyProtocolSha256: controls.historyProtocolSha256};
  const report = {sourceSha: manifest.sourceSha, ...sectionIdentity, observedEnvironment: environment,
    historyProtocol: protocol, ordinaryPackageManifest: resolve(manifestPath), mode,
    boundaries: {...sectionIdentity, rows: []}, cleanup: {closed: false}, stateDir,
    selectedBoundaryPassed: false, latencyMeasured: false, fullAcceptance: false};
  const save = () => writeFile(join(output, 'boundaries.json'), JSON.stringify(report, null, 2) + '\n', {mode: 0o600});
  let client, active = 'public open';
  try {
    const {open} = await import(pathToFileURL(join(consumer, 'node_modules/@actql/node/index.mjs')));
    client = await open({stateDir});
    active = 'fresh seed and positive Result';
    const seed = protocol.boundaries.usedMaterial.seed;
    const original = await client.startSource(seed.source, {format: seed.format, requestId: 'boundary-original'});
    assert.equal((await original.wait()).status, 'succeeded');
    assert.deepEqual(await original.result(seed.result).all(), seed.expected);
    report.originalRun = original.ref;
    active = 'selected test-owned material mutation';
    report.mutation = await mutateSelectedMaterial(stateDir, original.ref, output);
    active = 'new public Result after used material changed';
    try {
      const value = await original.result(seed.result).all();
      report.observedBoundary = {case: 'used-row-tamper', outcome: 'succeeded', actualSha256: identity(value)};
    } catch (error) {
      report.observedBoundary = {case: 'used-row-tamper', outcome: 'rejected', error: errorRecord(error)};
    }
  } catch (error) {report.firstFailure = {step: active, ...errorRecord(error)};}
  finally {
    if (client !== undefined) {
      try {await client.close(); report.cleanup.closed = true;}
      catch (error) {report.cleanup.failure = errorRecord(error);}
    }
    try {
      assert.deepEqual(await verifyNodeBenchmarkPackages(manifest, manifestPath, consumer), before);
      report.installedPayloadsUnchanged = true;
    } catch (error) {report.packageFailure = errorRecord(error);}
    // Keep the observation, but never qualify it if cleanup or software
    // correspondence failed. A successful corrupt read remains a failing row.
    if (!report.firstFailure && report.cleanup.closed && report.installedPayloadsUnchanged && report.observedBoundary) {
      report.boundaries.rows.push(report.observedBoundary);
      report.selectedBoundaryPassed = report.observedBoundary.outcome === 'rejected';
    }
    report.assessment = assessBoundaries(report.boundaries.rows);
    await save();
  }
  return report;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const args = process.argv.slice(2), options = {};
    assert(args.length % 2 === 0);
    for (let n = 0; n < args.length; n += 2) {
      const key = {'--manifest': 'manifestPath', '--consumer': 'consumer', '--output': 'output',
        '--controls': 'controlsPath', '--mode': 'mode'}[args[n]];
      assert(key && !Object.hasOwn(options, key)); options[key] = args[n + 1];
    }
    for (const key of ['manifestPath', 'consumer', 'output', 'controlsPath']) assert(options[key]);
    const report = await runNodeUsedMaterialBoundary(options);
    console.log(JSON.stringify({sourceSha: report.sourceSha, selectedBoundaryPassed: report.selectedBoundaryPassed,
      assessment: report.assessment, fullAcceptance: false, latencyMeasured: false}));
    process.exitCode = report.selectedBoundaryPassed ? 0 : 1;
  } catch (error) {console.error(error.message); process.exitCode = 2;}
}
