// Adapters for existing normal packages, literal collector fixtures and public
// workflow consumer. No alternate Executor or performance acceptance policy.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir, readFile, writeFile, readdir, lstat, symlink, unlink, copyFile} from 'node:fs/promises';
import {dirname, join, resolve, relative} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {gzipSync} from 'node:zlib';
import {createHash} from 'node:crypto';
import {packDistributionPackages} from './measure-distribution-artifacts.mjs';
import {inventory, unpack} from './package-release.mjs';
import {CLIENT_PACKAGES} from './packed-client-packages.mjs';
import {verifyNodeBenchmarkPackages, nodeWarmSmallQueryFixtures, nodeBenchmarkFailure} from './benchmark-node-operations.mjs';
import {projectTemplateFiles} from '../packages/native-cli/lib/project-template.mjs';
import {digest, jsonDigest, nodeColdStateKinds, nodeColdPublicPhases} from './health-monitor-report.mjs';

const self = fileURLToPath(import.meta.url);
export const healthFixtures = Object.freeze({
  select: {text: 'SELECT 1 AS id', expected: [{id: 1}]},
  join: nodeWarmSmallQueryFixtures.find(row => row.operation === 'warm-join'),
  aggregate: nodeWarmSmallQueryFixtures.find(row => row.operation === 'warm-decimal-sum'),
  status: {status: 'succeeded', revision: 'same original observed revision'},
  workflow: 'adapters/host-node/fixtures/mock-project-effect-public.mjs',
});

export async function execute(command, args, {cwd, raw, name, timeout = 600_000, env = process.env, observeFirstResult = false} = {}) {
  const start = process.hrtime.bigint();
  let stdout = '', stderr = '', overflow = false;
  const child = spawn(command, args, {cwd, env, stdio: ['ignore', 'pipe', 'pipe',...(observeFirstResult?['ipc']:[])]});
  const firstResults=[];
  if(observeFirstResult)child.on('message',value=>{
    if(value?.event==='first-result'&&value.pid===child.pid)firstResults.push(Number(process.hrtime.bigint()-start));
  });
  const collect = key => chunk => {
    if (Buffer.byteLength(stdout) + Buffer.byteLength(stderr) + chunk.length > 8 * 1024 ** 2) overflow = true;
    else if (key === 'stdout') stdout += chunk.toString(); else stderr += chunk.toString();
  };
  child.stdout.on('data', collect('stdout')); child.stderr.on('data', collect('stderr'));
  // The existing outer supervisor owns process-tree cancellation and deadlines.
  // A selected workflow phase keeps its existing 30s whole-child timer below.
  let timedOut = false;
  const timer = timeout ? setTimeout(() => {timedOut = true; child.kill('SIGTERM');}, timeout) : null;
  let terminal;
  try {
    terminal = await new Promise((accept, reject) => {
      child.once('error', reject); child.once('close', (code, signal) => accept({code, signal}));
    });
  } finally {if (timer) clearTimeout(timer);}
  const result = {...terminal, pid: child.pid, timedOut, overflow,
    wallNs: Number(process.hrtime.bigint() - start),
    ...(observeFirstResult?{firstResultNs:firstResults.length===1?firstResults[0]:null,firstResultNotifications:firstResults.length}:{}),
    stdout, stderr};
  if (raw) {
    await writeFile(join(raw, name + '.stdout'), stdout, {flag: 'wx', mode: 0o600});
    await writeFile(join(raw, name + '.stderr'), stderr, {flag: 'wx', mode: 0o600});
    await writeFile(join(raw, name + '.command.json'), JSON.stringify({command, args, cwd, ...result}, null, 2) + '\n', {flag: 'wx', mode: 0o600});
  }
  if (terminal.code !== 0 || terminal.signal || timedOut || overflow) {
    throw Object.assign(new Error(`${name ?? command}: ${timedOut ? 'whole-child timeout' : overflow ? 'output limit' : `exit ${terminal.code}/${terminal.signal}`}\n${stderr.slice(-4096)}`), {commandResult: result});
  }
  return result;
}

export async function prepareHealthPackages({repository, root, source, retained, command}) {
  const destination = join(root, 'packages'); await mkdir(destination);
  let manifest;
  if (retained) {
    // The ordinary collector's manifest contains actual filenames and complete
    // installed inventories. A retained source mismatch never triggers rebuild.
    if ((await lstat(retained)).isDirectory()) retained = join(retained, 'packed-client-packages.json');
    manifest = JSON.parse(await readFile(retained));
    if (manifest.revision) {
      assert.equal(manifest.revision, source.sha, 'Original normal package source differs');
      assert.deepEqual(Object.keys(manifest.tarballs).sort(), [...CLIENT_PACKAGES].sort());
      const original = manifest, directory = dirname(retained), entries = await readdir(directory);
      manifest = {sourceSha: original.revision, originalManifestSha256: digest(await readFile(retained)), packages: []};
      for (const name of CLIENT_PACKAGES) {
        const matching = [];
        for (const file of entries.filter(file => file.endsWith('.tgz'))) {
          if (digest(await readFile(join(directory, file))) === original.tarballs[name]) matching.push(file);
        }
        assert.equal(matching.length, 1, `Exactly one original ${name} tarball required`);
        const file = matching[0], bytes = await readFile(join(directory, file));
        await copyFile(join(directory, file), join(destination, file));
        const unpacked = await unpack(join(destination, file), join(root, 'unpacked-' + name));
        const metadata = JSON.parse(await readFile(join(unpacked, 'package.json')));
        assert.equal(metadata.name, '@actql/' + name);
        manifest.packages.push({name: metadata.name, version: metadata.version, file, bytes: bytes.length,
          sha256: digest(bytes), integrity: 'sha512-' + createHash('sha512').update(bytes).digest('base64'), files: await inventory(unpacked)});
      }
      retained = join(destination, 'ordinary-operation-packages.json');
      await writeFile(retained, JSON.stringify(manifest, null, 2) + '\n', {flag: 'wx'});
    }
    assert.equal(manifest.sourceSha, source.sha, 'Retained packages must match selected source SHA');
    assert.equal(source.dirty, false, 'Retained packages require clean matching source');
  } else {
    const packages = await packDistributionPackages({repository, destination,
      run: (cmd, args, cwd) => command(cmd, args, {cwd, name: `pack-${packagesCounter++}`})});
    manifest = {sourceSha: source.sha, source, packages: []};
    for (const pkg of packages) {
      const directory = await unpack(pkg.path, join(root, 'unpacked-' + pkg.name.slice(7)));
      manifest.packages.push({...pkg, path: undefined, integrity: 'sha512-' + createHash('sha512').update(await readFile(pkg.path)).digest('base64'), files: await inventory(directory)});
    }
    retained = join(destination, 'ordinary-operation-packages.json');
    await writeFile(retained, JSON.stringify(manifest, null, 2) + '\n', {flag: 'wx'});
  }
  assert.deepEqual(manifest.packages.map(row => row.name).sort(), CLIENT_PACKAGES.map(name => '@actql/' + name).sort());
  const consumer = join(root, 'consumer'); await mkdir(consumer);
  await writeFile(join(consumer, 'package.json'), '{"private":true,"type":"module"}\n');
  await command('npm', ['install', '--offline', '--ignore-scripts', '--no-audit', '--no-fund', '--no-save', '--omit=optional',
    ...manifest.packages.map(row => {
      assert.equal(row.file, row.file.split('/').at(-1)); return resolve(dirname(retained), row.file);
    })], {cwd: consumer, name: 'install-node'});
  await verifyNodeBenchmarkPackages(manifest, retained, consumer);
  return {manifest, manifestPath: retained, consumer};
}
let packagesCounter = 0;

export async function distributionMetrics({repository, prepared, root, command, source, installedInventory}) {
  const artifacts = [], metrics = [];
  for (const pkg of prepared.manifest.packages) {
    const installed = pkg.files.reduce((sum, row) => sum + row.bytes, 0);
    artifacts.push({name: pkg.name, version: pkg.version, artifactKind: 'npm', sourceSha: source.sha,
      sha256: pkg.sha256, acquisitionBytes: pkg.bytes, installedBytes: installed, file: pkg.file,
      bundled: pkg.files.filter(row => /duckdb|wasmtime|\.wasm$|\.dylib$|\.so$/u.test(row.path))});
    metrics.push({id: 'tarball:' + pkg.name, kind: 'size', artifactKind: 'npm', target: pkg.name,
      value: pkg.bytes, unit: 'bytes', required: true, fixtureSha256: jsonDigest({kind: 'npm', name: pkg.name}), evidence: prepared.manifestPath});
  }
  const installed = installedInventory ?? await inventory(join(prepared.consumer, 'node_modules'));
  for (const [target, names] of [['node-local', CLIENT_PACKAGES], ['remote-sdk', ['sdk', 'client-wire']]]) {
    const value = target === 'node-local' ? installed.reduce((sum, row) => sum + row.bytes, 0)
      : prepared.manifest.packages.filter(row => names.includes(row.name.slice(7))).flatMap(row => row.files).reduce((sum, row) => sum + row.bytes, 0);
    metrics.push({id: 'installed:' + target, kind: 'size', artifactKind: 'installed', target, value,
      required: true, unit: 'bytes', fixtureSha256: jsonDigest(names), evidence: prepared.manifestPath});
  }
  const browser = join(root, 'browser.mjs'), meta = join(root, 'browser-meta.json');
  await command(join(repository, 'node_modules/esbuild/bin/esbuild'), [
    join(prepared.consumer, 'node_modules/@actql/sdk/index.mjs'), '--bundle', '--platform=browser',
    '--format=esm', '--target=es2022', '--outfile=' + browser, '--metafile=' + meta], {cwd: repository, name: 'browser-bundle'});
  const metadata = JSON.parse(await readFile(meta));
  assert(Object.keys(metadata.inputs).every(path => /node_modules\/@actql\/(?:sdk|client-wire)\//u.test(path)));
  assert(Object.values(metadata.outputs).every(row => row.imports.length === 0));
  const bytes = await readFile(browser);
  artifacts.push({name: 'remote-browser', artifactKind: 'browser', version: 'consumer-esm', sourceSha: source.sha,
    sha256: digest(bytes), acquisitionBytes: bytes.length, gzipBytes: gzipSync(bytes).length});
  for (const [id, kind, value] of [['browser-raw', 'browser', bytes.length], ['browser-gzip', 'browser-gzip', gzipSync(bytes).length]]) {
    metrics.push({id, kind: 'size', artifactKind: kind, target: 'remote-sdk', value, unit: 'bytes', required: true,
      fixtureSha256: jsonDigest({bundle: 'browser-esm-es2022', entry: '@actql/sdk'}), evidence: meta});
  }
  return {artifacts, metrics, installedInventory: installed};
}

const usage = () => ({peakRssBytes: process.resourceUsage().maxRSS * 1024,
  rssScope: 'Node resourceUsage.maxRSS high-water mark of this actual Node process; KiB converted to bytes; children excluded'});
export async function publicNodeSample(config) {
  let client, primary;
  assert(['warm','prepare-existing-state',...nodeColdStateKinds].includes(config.kind));
  const report = {pid: process.pid, kind: config.kind, stateDir:config.stateDir, metrics: [], cleanup: {closed: false},
    phaseSpans:[],unobservedHostPhases:['initial activation','Request prepare/check/compile/Plan','execution','durable publication'],
    phaseScope:'Public boundaries; activation/preparation inside submission, execution/publication inside wait/all-rows are unresolved, never exclusive sums'};
  const begin=name=>{const span={name,clock:'child-monotonic',parent:['product-import','public-open','first-close'].includes(name)?'public-lifecycle':'first-new-query',startNs:Number(process.hrtime.bigint()),endNs:null,completed:false};report.phaseSpans.push(span);return span;};
  const end=span=>{span.endNs=Number(process.hrtime.bigint());span.completed=true;};
  const save = () => writeFile(config.output, JSON.stringify({...report, ...usage(),
    processCpu: process.cpuUsage()}, null, 2) + '\n', {mode: 0o600});
  // Every state is created by the actual public Host, never seeded from an old Run.
  globalThis.fetch = async () => {throw new Error('UnexpectedNetworkInHealthFixture');};
  const started = process.hrtime.bigint();
  try {
    const importing=begin('product-import');
    const {open} = await import(pathToFileURL(join(config.consumer, 'node_modules/@actql/node/index.mjs')).href);end(importing);
    const opening=begin('public-open');client = await open({stateDir: config.stateDir});end(opening);
    report.importAndOpenNs = Number(process.hrtime.bigint() - started);
    const first = process.hrtime.bigint(),submitting=begin('new-run-submission');
    const original = await client.startSource(healthFixtures.select.text, {format: 'sql',
      requestId:`health-${config.kind}-${config.iteration??0}`});end(submitting);
    report.originalRunSha256 = jsonDigest(original.ref); // Actual original before wait.
    if(config.kind==='cold-existing-state') {
      assert.match(config.seedRunSha256,/^[0-9a-f]{64}$/u);
      assert.notEqual(report.originalRunSha256,config.seedRunSha256,'Cold-existing must submit a NEW query');
    }
    const waiting=begin('wait-execution-publication');
    assert.equal((await original.wait()).status, 'succeeded');end(waiting);
    const materializing=begin('all-result-rows');
    assert.deepEqual(await original.result('main').all(), healthFixtures.select.expected);end(materializing);
    report.publicTiming = {kind: 'process-result-close', startNs: Number(started),
      observedNs: Number(process.hrtime.bigint())};
    report.firstQueryNs = Number(process.hrtime.bigint() - first);
    report.firstQueryTiming={clock:'child-monotonic',parent:'public-lifecycle',startNs:Number(first),endNs:report.publicTiming.observedNs};
    if(config.notifyFirstResult===true) {
      assert(process.send,'Selected child must retain the original parent IPC');
      process.send({event:'first-result',pid:process.pid});
    }
    if (config.kind === 'warm') {
      const state = await original.status();
      for (const [id, fixture] of [['warm-select', healthFixtures.select], ['warm-join', healthFixtures.join],
        ['warm-aggregate', healthFixtures.aggregate], ['warm-saved', healthFixtures.select], ['warm-status', healthFixtures.status]]) {
        const metric = {id, samples: []}; report.metrics.push(metric);
        for (let iteration = 0; iteration < config.count; iteration++) {
          const cpu = process.cpuUsage(), start = process.hrtime.bigint();
          let error;
          try {
            if (id === 'warm-status') {
              const observed = await original.status();
              assert.deepEqual({status: observed.status, revision: observed.revision}, {status: 'succeeded', revision: state.revision});
            } else if (id === 'warm-saved') assert.deepEqual(await original.result('main').all(), fixture.expected);
            else {
              const text = id === 'warm-select' ? `SELECT ${iteration + 2} AS id` : fixture.text;
              assert.deepEqual(await client.sql(text).all(), id === 'warm-select' ? [{id: iteration + 2}] : fixture.expected);
            }
          } catch (cause) {error = cause;}
          const used = process.cpuUsage(cpu);
          const end = process.hrtime.bigint();
          metric.samples.push({iteration, pid: process.pid, wallNs: Number(end - start),
            cpuUserUs: used.user, cpuSystemUs: used.system, cpuScope: 'actual Node collector process',
            ...usage(),
            ...(!error ? {publicTiming: {kind: id === 'warm-status' ? 'public-status' : 'public-result',
              startNs: Number(start), observedNs: Number(end), endNs: Number(end)}} : {}),
            completed: !error, verified: !error, ...(error ? {error: nodeBenchmarkFailure(error)} : {})});
          await save();
          if (error) throw error; // No retry, replay or sampling until green.
        }
      }
    }
  } catch (error) {primary = error; report.failure = nodeBenchmarkFailure(error);}
  finally {
    if (client) {
      const closing=begin('first-close');
      const close = process.hrtime.bigint();
      if (report.publicTiming) report.publicTiming.closeStartNs = Number(close);
      try {await client.close(); report.cleanup.closed = true;end(closing);}
      catch (error) {primary ??= error; report.cleanup.failure = nodeBenchmarkFailure(error);}
      report.closeNs = Number(process.hrtime.bigint() - close);
      if (report.publicTiming) report.publicTiming.closeEndNs = Number(process.hrtime.bigint());
    }
    if (report.publicTiming) report.publicTiming.endNs = Number(process.hrtime.bigint());
    await save();
  }
  if (primary) throw primary;
  return report;
}

export async function quickNodeMetrics({prepared, root, repository, command, counts, onMetric}) {
  const warmOutput = join(root, 'warm-observation.json');
  let originalFailure;
  try {
    await command(process.execPath, [self, '--sample', JSON.stringify({kind: 'warm', count: counts.warmSamples,
      consumer: prepared.consumer, stateDir: join(root, 'warm-state'), output: warmOutput})], {cwd: root, name: 'node-warm'});
  } catch (error) {originalFailure = error;}
  // The child saves its original partial/failed samples before exiting. Publish
  // those observations too; never discard them behind the command exit error.
  let warm;
  try {warm = JSON.parse(await readFile(warmOutput));}
  catch (error) {throw originalFailure ?? error;}
  for (const metric of warm.metrics) {
    const fixture = healthFixtures[metric.id.slice(5)] ?? healthFixtures.select;
    await onMetric({...metric, kind: 'latency', target: 'node-local', temperature: 'warm', required: true, unit: 'ms',
      requiredSamples: counts.warmSamples, fixtureSha256: jsonDigest({fixture, count: counts.warmSamples}), evidence: warmOutput});
  }
  if (originalFailure) throw originalFailure;
  assert(warm.cleanup.closed);
  const peaks = [warm.peakRssBytes];
  // Preparation is an untimed setup for existing-state samples, by the SAME
  // installed candidate and its public open/query/all-rows/first-close path.
  // Cold-new below independently retains normal first initialization cost.
  const existingState=join(root,'cold-existing-state'),seedOutput=join(root,'cold-existing-preparation.json');
  let seedFailure,seedCommand;
  try {seedCommand=await command(process.execPath,[self,'--sample',JSON.stringify({kind:'prepare-existing-state',
    consumer:prepared.consumer,stateDir:existingState,output:seedOutput})],{cwd:root,name:'node-cold-existing-preparation'});}
  catch(error) {seedFailure=error;seedCommand=error.commandResult;}
  let seed;try {seed=JSON.parse(await readFile(seedOutput));}catch(error) {throw seedFailure??error;}
  await onMetric({id:'cold-existing-state-preparation',kind:'reference',target:'node-local',required:false,
    value:seedCommand?.wallNs===undefined?null:seedCommand.wallNs/1e6,unit:'ms',fixtureSha256:jsonDigest(healthFixtures.select),evidence:seedOutput,
    scope:'Same-candidate public preparation/close; excluded only from existing-state population, not from cold-new',
    ...((seedFailure||!seed.cleanup.closed)?{status:'error',reason:'Existing-state preparation or first close failed'}:{})});
  if(seedFailure)throw seedFailure;
  assert(seed.cleanup.closed&&seed.originalRunSha256&&seed.stateDir===existingState);
  peaks.push(seed.peakRssBytes);
  const pids=new Set([warm.pid,seed.pid]);
  for(const kind of nodeColdStateKinds) {
    const base={kind:'latency',target:'node-local',temperature:'cold',stateKind:kind,required:true,unit:'ms',
      requiredSamples:counts.coldSamples,fixtureSha256:jsonDigest({fixture:healthFixtures.select,stateKind:kind}),evidence:root};
    const cold={...base,id:`${kind}-process-first-result-close`,samples:[],
      scope:'Parent launch -> natural child exit, including public all rows and first close; collector setup/IPC/report overhead retained'};
    const firstResult={...base,id:`${kind}-process-first-result`,samples:[],
      scope:'Parent launch -> received actual all-rows notification; IPC delivery is included, not subtracted'};
    const phases=nodeColdPublicPhases.map(phase=>({...base,id:`${kind}-${phase}`,samples:[],
      scope:`Child public ${phase}; nested in parent whole-process time, not an exclusive CPU/work partition`}));
    for(let iteration=0;iteration<counts.coldSamples;iteration++) {
      const output=join(root,`${kind}-${iteration}.json`);
      let commandFailure,observation;
      try {observation=await command(process.execPath,[self,'--sample',JSON.stringify({kind,iteration,
        consumer:prepared.consumer,stateDir:kind==='cold-existing-state'?existingState:join(root,`cold-new-state-${iteration}`),
        ...(kind==='cold-existing-state'?{seedRunSha256:seed.originalRunSha256}:{}),notifyFirstResult:true,output})],
        {cwd:root,name:`node-${kind}-${iteration}`,observeFirstResult:true});}
      catch(error) {commandFailure=error;observation=error.commandResult;}
      let child;try {child=JSON.parse(await readFile(output));}catch(error) {throw commandFailure??error;}
      const valid=!commandFailure&&child.cleanup.closed&&child.pid===observation?.pid&&!pids.has(child.pid)&&
        child.kind===kind&&Number.isSafeInteger(observation.firstResultNs)&&observation.firstResultNs>=0&&
        observation.firstResultNs<=observation.wallNs&&observation.firstResultNotifications===1;
      pids.add(child.pid);
      assert(Number.isSafeInteger(observation?.wallNs),'Original parent process clock unavailable; raw child report retained');
      const sample={iteration,pid:child.pid,wallNs:observation.wallNs,
        cpuUserUs:child.processCpu.user,cpuSystemUs:child.processCpu.system,
        cpuScope:'Actual Node child through public close; final report write/exit excluded',
        peakRssBytes:child.peakRssBytes,rssScope:child.rssScope,publicTiming:child.publicTiming,
        completed:valid,verified:valid,firstResultNs:observation?.firstResultNs??null,
        stateKind:kind,stateDir:child.stateDir,preparation:kind==='cold-existing-state'?seedOutput:null,
        originalRunSha256:child.originalRunSha256,observation:output,
        phaseSpans:child.phaseSpans,firstQueryTiming:child.firstQueryTiming,unobservedHostPhases:child.unobservedHostPhases,
        ...(!valid?{error:child.failure??nodeBenchmarkFailure(commandFailure??new Error('Incomplete original child observation'))}:{})};
      cold.samples.push(sample);await onMetric(cold);peaks.push(child.peakRssBytes);
      if(Number.isSafeInteger(observation?.firstResultNs)) {
        firstResult.samples.push({...sample,wallNs:observation.firstResultNs,
          publicTiming:valid?{kind:'process-first-result',startNs:0,observedNs:observation.firstResultNs,endNs:observation.firstResultNs}:undefined});
      }else {firstResult.status='incomplete';firstResult.reason='No original all-rows notification; first Result unobserved';}
      await onMetric(firstResult);
      for(const [index,name] of nodeColdPublicPhases.entries()) {
        const span=child.phaseSpans?.find(span=>span.name===name);
        if(span?.completed===true)phases[index].samples.push({iteration,pid:child.pid,
          wallNs:span.endNs-span.startNs,completed:true,verified:true,cpuAvailable:false,observation:output});
        else {phases[index].status=span?'error':'incomplete';
          phases[index].reason=span?'Original phase did not complete':'Phase unexecuted after earlier original failure';}
        await onMetric(phases[index]);
      }
      if(!valid)throw commandFailure??new Error('Incomplete original cold observation');
    }
  }
  await onMetric({id: 'peak-rss', kind: 'rss', target: 'node-local', value: Math.max(...peaks), unit: 'bytes',
    required: true, fixtureSha256: jsonDigest({fixtures: healthFixtures, counts}), evidence: warmOutput,
    scope: warm.rssScope, observationsBytes: peaks});
  return warm;
}

export async function mockWorkflowMetrics({prepared, root, repository, command, counts, onMetric}) {
  const fixture = await readFile(join(repository, healthFixtures.workflow));
  const files = projectTemplateFiles('churn-risk-mock');
  const metric = {id: 'mock-workflow', kind: 'latency', target: 'node-local', temperature: 'cold', required: true,
    unit: 'ms', requiredSamples: counts.coldSamples, fixtureSha256: jsonDigest({fixture: digest(fixture), files}),
    samples: [], evidence: root};
  for (let iteration = 0; iteration < counts.coldSamples; iteration++) {
    const project = join(root, `mock-project-${iteration}`); await mkdir(project);
    for (const [name, bytes] of Object.entries(files)) {
      await mkdir(dirname(join(project, name)), {recursive: true}); await writeFile(join(project, name), bytes, {flag: 'wx'});
    }
    await writeFile(join(project, 'workflow.mjs'), fixture, {flag: 'wx'});
    await symlink(join(prepared.consumer, 'node_modules'), join(project, 'node_modules'), 'dir');
    const started = process.hrtime.bigint(), cpu = process.cpuUsage(), phases = [];
    try {
      for (const [phase, expected] of [['capture', 9], ['approve', 11], ['recover', 7]]) {
        const observation = await command(process.execPath, [join(project, 'workflow.mjs'), phase, join(project, 'handoff.json')],
          {cwd: project, name: `workflow-${iteration}-${phase}`, timeout: 30_000});
        const rows = observation.stdout.trim().split('\n').map(line => JSON.parse(line));
        assert.equal(rows.filter(row => row.step && row.status === 'passed').length, expected);
        assert.equal(rows.at(-1).status, 'passed'); assert.equal(rows.at(-1).firstFailedStep, null);
        phases.push({phase, pid: observation.pid, wallNs: observation.wallNs, assertions: expected});
      }
      const used = process.cpuUsage(cpu);
      metric.samples.push({iteration, pid: process.pid, stateId: project, wallNs: Number(process.hrtime.bigint() - started),
        cpuUserUs: used.user, cpuSystemUs: used.system,
        cpuScope: 'actual workflow coordinator process only; separately recorded phase child CPU excluded',
        completed: true, verified: true, phases});
    } catch (error) {
      const used = process.cpuUsage(cpu);
      metric.samples.push({iteration, pid: process.pid, stateId: project, wallNs: Number(process.hrtime.bigint() - started),
        cpuUserUs: used.user, cpuSystemUs: used.system,
        cpuScope: 'actual workflow coordinator process only; separately recorded phase child CPU excluded',
        completed: false, verified: false, phases, error: nodeBenchmarkFailure(error)});
      await onMetric(metric); throw error;
    } finally {await unlink(join(project, 'node_modules'));}
    await onMetric(metric);
  }
}

if (process.argv[1] && resolve(process.argv[1]) === self) {
  assert.equal(process.argv[2], '--sample');
  try {await publicNodeSample(JSON.parse(process.argv[3]));}
  catch (error) {console.error(JSON.stringify(nodeBenchmarkFailure(error))); process.exitCode = 1;}
  finally {if(process.connected)process.disconnect();}
}
