// Optional installer/export acceptance only: no Moon/Core runtime preparation,
// Provider request, numerical profile or public Result is exercised here.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdtemp, mkdir, readFile, writeFile, realpath} from 'node:fs/promises';
import {dirname, join, relative} from 'node:path';
import {tmpdir} from 'node:os';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';

const repository = fileURLToPath(new URL('../', import.meta.url));
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const npm = join(dirname(process.execPath), '../lib/node_modules/npm/bin/npm-cli.js');
const scratch = await realpath(await mkdtemp(join(tmpdir(), 'actql-a-optional-provider-')));
console.log('OPTIONAL_PROVIDER_CUSTODY', scratch);
const cache = join(scratch, 'cache'), artifacts = join(scratch, 'artifacts');
await mkdir(cache); await mkdir(artifacts);
const userConfig = join(scratch, 'npm-user-config');
const globalConfig = join(scratch, 'npm-global-config');
await writeFile(userConfig, ''); await writeFile(globalConfig, '');
// No caller credential/configuration variables or NODE_PATH reach npm/child
// consumers. Registry dependency acquisition is distinct from Provider I/O.
const env = {PATH: `${dirname(process.execPath)}:/usr/bin:/bin`, LANG: 'C',
  npm_config_cache: cache, npm_config_userconfig: userConfig,
  npm_config_globalconfig: globalConfig, npm_config_registry: 'https://registry.npmjs.org',
  npm_config_audit: 'false', npm_config_fund: 'false'};
function run(command, args, cwd) {
  const result = spawnSync(command, args, {cwd, env, encoding: 'utf8',
    timeout: 30000, killSignal: 'SIGTERM', maxBuffer: 8 * 1024 * 1024});
  if (result.error || result.status !== 0) {
    throw new Error(`OptionalProviderCommandFailed:${JSON.stringify({command,args,status:result.status,signal:result.signal})}\n${result.stdout ?? ''}\n${result.stderr ?? ''}`,
      {cause: result.error});
  }
  return result.stdout;
}
const source = run('git', ['rev-parse', 'HEAD'], repository).trim();
assert.equal(run('git', ['status', '--porcelain'], repository).trim(), '', 'Producer inputs must be clean');
const results = [];
for (const [directory, name, factory] of [
  ['provider-http', '@actql/provider-http', 'createInstalledHttpChatRegistration'],
  ['provider-ai-sdk', '@actql/provider-ai-sdk', 'createInstalledOpenAIChatRegistration'],
]) {
  const exports = directory === 'provider-ai-sdk'
    ? ['createInstalledOpenAIChatRegistration', 'createInstalledUndiciOpenAIChatRegistration']
    : [factory];
  const packageRoot = join(repository, 'packages', directory);
  const manifest = JSON.parse(await readFile(join(packageRoot, 'package.json'), 'utf8'));
  assert.equal(manifest.name, name);
  assert.equal(manifest.scripts, undefined, 'This JS-only optional package has no runtime producer');
  // Normal npm pack lifecycle: no ignore-scripts/prepack bypass.
  const metadata = JSON.parse(run(process.execPath,
    [npm, 'pack', '--json', '--pack-destination', artifacts], packageRoot))[0];
  const tarball = join(artifacts, metadata.filename);
  const bytes = await readFile(tarball);
  assert.equal(metadata.integrity, 'sha512-' + createHash('sha512').update(bytes).digest('base64'));
  const paths = metadata.files.map(entry => entry.path);
  for (const path of ['index.mjs', 'index.d.ts', 'LICENSE', 'README.md']) assert.ok(paths.includes(path));
  if (directory === 'provider-ai-sdk') assert.ok(paths.includes('_internal/original-materials.mjs'));
  assert.ok(paths.every(path => !path.startsWith('node_modules/') && !path.includes('.test.')));
  const consumer = join(scratch, directory);
  await mkdir(consumer);
  await writeFile(join(consumer, 'package.json'), '{"private":true,"type":"module"}\n');
  // Explicit package installation. Scripts are disabled for consumers only;
  // no implicit package acquisition occurs during ActQL request execution.
  run(process.execPath, [npm, 'install', '--ignore-scripts', '--no-audit', '--no-fund', tarball], consumer);
  const installed = join(consumer, 'node_modules', name);
  assert.equal(await realpath(installed), installed, 'Consumer must not borrow a repository symlink');
  for (const path of paths) {
    assert.equal(hash(await readFile(join(installed, path))), hash(await readFile(join(packageRoot, path))),
      `Changed installed artifact:${name}/${path}`);
  }
  const acceptance = `import test from 'node:test';
import assert from 'node:assert/strict';
import * as entry from ${JSON.stringify(name)};
test('external optional package has only the original installer exports',()=>{
  assert.deepEqual(Object.keys(entry),${JSON.stringify(exports)});
});
test('missing original Host binding refuses before physical fetch',()=>{
  let sends=0;
  const cid='sha256:'+'0'.repeat(64);
  const config={providerId:'models/unavailable',modelSelector:'unavailable',modelId:'unavailable',
    taskCid:cid,promptCid:cid,outputSchemaCid:cid,promptPayloadWire:'{}',
    originalReadInstallation:undefined,rawCaptureSelection:undefined,
    bindingOriginals:undefined,quantityCapacity:undefined,
    projectionLimits:{maxBytes:1000,maxNodes:100,maxDepth:10,maxFrames:20,maxWork:1000},
    requestLimits:{maxBytes:1000,maxHeaderBytes:128,maxHeaders:4},
    responseLimits:{maxBytes:1000,maxChunkBytes:128,maxChunks:10,maxHeaderBytes:128},
    fetch(){sends++;throw Error('UnexpectedProviderIO');},observeAt:()=> '2026-10-14T00:00:00.000Z',observeEgress(){},
    ${directory === 'provider-http' ? "endpoint:'https://fixture.invalid/v1/chat/completions',headers:[]" : "baseURL:'https://fixture.invalid/v1',apiKey:'fixture-only'"}};
  assert.throws(()=>entry[${JSON.stringify(factory)}](config),
    {message:${JSON.stringify(directory === 'provider-http' ? 'HTTPChatOriginalInstallationUnavailable' : 'OpenAIOriginalInstallationUnavailable')}});
  assert.equal(sends,0);
});
test('low-level transport cannot be imported through package exports',async()=>{
  await assert.rejects(import(${JSON.stringify(name + '/_internal/model-port.mjs')}),
    {code:'ERR_PACKAGE_PATH_NOT_EXPORTED'});
});
${directory === 'provider-ai-sdk' ? `
// Closed declaration DATA only. These fixtures do not issue a profile, grant,
// complete funding or Common receipt. No internal runtime import is available.
function materialsConfiguration() {
  const cid='sha256:'+'0'.repeat(64);
  const original={cid,wire:'{}'};
  return {providerId:'models/unavailable',modelSelector:'unavailable',modelId:'unavailable',
    baseURL:'https://fixture.invalid/v1',apiKey:'fixture-only',taskCid:cid,promptCid:cid,
    outputSchemaCid:cid,promptPayloadWire:'{}',bindingOriginals:undefined,quantityCapacity:undefined,
    projectionLimits:{maxBytes:1000,maxNodes:100,maxDepth:10,maxFrames:20,maxWork:1000},
    requestLimits:{maxBytes:1000,maxHeaderBytes:128,maxHeaders:4},
    responseLimits:{maxBytes:1000,maxChunkBytes:128,maxChunks:10,maxHeaderBytes:128},
    observeAt:()=> '2026-10-14T00:00:00.000Z',observeEgress(){},
    originalMaterials:{responseProfile:original,policyOriginals:{retention:original,metadata:original,clock:original,data:original},
      readerLimits:{maxBytes:1000,maxNodes:100,maxDepth:10,maxMembers:100,maxWork:1000},
      installation:{builder_id:'fixture',builder_revision:'1',codec_id:'fixture',codec_revision:'1',
        build_artifact_cid:cid,sdk:{package_name:'@ai-sdk/openai',version:'4.0.91',interface:'v4',lock_artifact_cid:cid},
        endpoint:'https://fixture.invalid/v1/chat/completions',http_method:'POST',streaming:false,
        validator_id:'fixture',validator_revision:'1',validator_artifact_cid:cid,completion_basis:'generation_finish'},
      originalReadInstallation:{bootstrap:{bootstrapRetainedBytes:1n,bootstrapExecutionBytes:0n,
        maxReservations:1,maxHoldings:1,maxDelegations:1},modelRetainedBytes:1n,modelExecutionBytes:0n,
        nodeInstallation:{runtimeArtifactCid:cid,layoutArtifactCid:cid,layout:{runtime_artifact_cid:cid,
          layout_artifact_cid:cid,program_definition_cid:cid,parameter_values_cid:cid,barrier_cid:cid,
          prepared_rows:1n,retained_bytes:1n,execution_bytes:0n}}},
      rawCaptureSelection:{selectedAt:'selection',availableUntil:'availability',deleteBy:'deletion',
        extensionCeilingAt:'ceiling',metadataDeleteBy:'metadata',selectionAvailable:()=>true}}};
}
test('installed DATA constructor needs no internal runtime and refuses null runtime or opaque mixing',()=>{
  const config=materialsConfiguration();
  const register=entry.createInstalledUndiciOpenAIChatRegistration(config);
  assert.equal(typeof register,'function');
  assert.throws(()=>register(null),{code:'OpenAIOriginalRuntimeUnavailable'});
  assert.throws(()=>entry.createInstalledUndiciOpenAIChatRegistration({...config,rawCaptureSelection:{}}),
    {code:'InvalidInstalledOpenAIChatConfiguration'});
  const noPolicy=materialsConfiguration();delete noPolicy.originalMaterials.policyOriginals.clock;
  assert.throws(()=>entry.createInstalledUndiciOpenAIChatRegistration(noPolicy),{code:'InvalidOpenAIOriginalMaterials'});
});
test('installed DATA callback preserves Common refusal without physical work or a fabricated opaque',()=>{
  const register=entry.createInstalledUndiciOpenAIChatRegistration(materialsConfiguration());let admissions=0;
  // Explicit Common-port double: actual Common/Host evidence is separate.
  const runtime=Object.fromEntries(['clientProgramStartOpenAIChatProjection','clientProgramAdvanceOpenAIChatProjection',
    'clientProgramRetireOpenAIChatProjection','clientProgramInstallAsyncModelProvider','clientProgramModelRequestGeneration',
    'clientProgramModelRequestPreflight','clientProgramModelAsyncPhysicalRequestPlan','clientProgramModelPhysicalCallForRequest',
    'clientProgramModelPhysicalPending','clientProgramModelPhysicalUnknown','clientProgramModelPhysicalSavedChat',
    'clientProgramAdmitEffectDependencyBody'].map(name=>[name,()=>assert.fail('No physical work')]));
  runtime.clientProgramReadModelResponseProfile=()=>{admissions++;return {$tag:0,_0:{}};};
  assert.throws(()=>register(runtime),{code:'OpenAIOriginalMaterialsRefused'});assert.equal(admissions,1);
  assert.throws(()=>register({...runtime}),{code:'OpenAIOriginalInstallationReused'});assert.equal(admissions,1);
});
` : ''}
`;
  await writeFile(join(consumer, 'acceptance.test.mjs'), acceptance);
  const focused = 'import{runFocusedTests}from' + JSON.stringify(new URL('./test-execution.mjs', import.meta.url).href) +
    ';process.exitCode=runFocusedTests("node",process.argv.slice(1),{cwd:process.cwd(),timeout:30000});';
  const output = run(process.execPath, ['--input-type=module', '-e', focused, '--', 'acceptance.test.mjs'], consumer);
  console.log(output.trim());
  const summary = output.split('\n').filter(line => line.startsWith('ACTQL_TEST_SUMMARY '))
    .map(line => JSON.parse(line.slice('ACTQL_TEST_SUMMARY '.length))).at(-1);
  const tests = directory === 'provider-ai-sdk' ? 5 : 3;
  assert.equal(summary.success, true); assert.equal(summary.counts.tests, tests); assert.equal(summary.counts.passed, tests);
  const declaration = `import {${factory},type ${directory === 'provider-http' ? 'HttpChatRegistrationOptions' : 'OpenAIChatRegistrationOptions'}} from ${JSON.stringify(name)};
declare const original: ${directory === 'provider-http' ? 'HttpChatRegistrationOptions' : 'OpenAIChatRegistrationOptions'};
const callback: (runtime:unknown)=>readonly object[]=${factory}(original);
void callback;
// @ts-expect-error Original installation is not optional.
${factory}({providerId:'unfunded'});
// @ts-expect-error A send function is not part of the package entry.
import {startSdkTransport} from ${JSON.stringify(name)};
void startSdkTransport;
${directory === 'provider-ai-sdk' ? `
import {createInstalledUndiciOpenAIChatRegistration,type UndiciOpenAIChatMaterialsRegistrationOptions} from '@actql/provider-ai-sdk';
declare const materials: UndiciOpenAIChatMaterialsRegistrationOptions;
const suppliedByHost: (runtime:unknown)=>readonly object[]=createInstalledUndiciOpenAIChatRegistration(materials);
void suppliedByHost;
// @ts-expect-error DATA and opaque selections are mutually exclusive.
createInstalledUndiciOpenAIChatRegistration({...materials,rawCaptureSelection:{}});
` : ''}
`;
  await writeFile(join(consumer, 'consumer.typecheck.mts'), declaration);
  run(process.execPath, [join(repository, 'node_modules/typescript/bin/tsc'), '--noEmit', '--strict',
    '--module', 'NodeNext', '--moduleResolution', 'NodeNext', '--target', 'ES2022', 'consumer.typecheck.mts'], consumer);
  const closure = [];
  const consumerLock = JSON.parse(await readFile(join(consumer, 'package-lock.json'), 'utf8'));
  if (directory === 'provider-ai-sdk') {
    const originalLock = await readFile(join(packageRoot, 'package-lock.json'));
    assert.deepEqual(await readFile(join(installed, 'npm-shrinkwrap.json')), originalLock);
    for (const [path, expected] of Object.entries(JSON.parse(originalLock).packages)) {
      if (path === '') continue;
      const chain = path.replace(/^node_modules\//u, '').split('/node_modules/');
      let issuer = installed;
      for (const dependency of chain) {
        let resolved = createRequire(join(issuer, 'package.json')).resolve(dependency);
        for (;;) {
          resolved = dirname(resolved);
          try {
            const body = JSON.parse(await readFile(join(resolved, 'package.json'), 'utf8'));
            if (body.name === dependency) { issuer = resolved; break; }
          } catch (error) { if (error.code !== 'ENOENT') throw error; }
          assert.notEqual(resolved, dirname(resolved), `Missing installed dependency:${dependency}`);
        }
      }
      assert.ok(issuer.startsWith(consumer + '/'), 'No repository/ambient hoist');
      const actual = JSON.parse(await readFile(join(issuer, 'package.json'), 'utf8'));
      assert.equal(actual.version, expected.version, path);
      const installedPath = relative(consumer, issuer);
      assert.equal(consumerLock.packages[installedPath].integrity, expected.integrity, path);
      closure.push({path,version:actual.version,integrity:expected.integrity});
    }
    // Use the actual pinned package export, not an invented alternate suffix.
    const sdk = createRequire(join(installed, 'package.json')).resolve('@ai-sdk/openai');
    const sdkRoot = dirname(dirname(sdk));
    const sdkEntry = relative(sdkRoot, sdk);
    assert.equal(hash(await readFile(sdk)),
      hash(await readFile(join(packageRoot, 'node_modules/@ai-sdk/openai', sdkEntry))), sdkEntry);
  } else {
    assert.deepEqual(manifest.dependencies, {});
    assert.deepEqual(Object.keys(consumerLock.packages).sort(), ['', 'node_modules/@actql/provider-http']);
  }
  results.push({name,source,tarball,bytes:bytes.length,sha256:hash(bytes),integrity:metadata.integrity,
    consumer,tests,typecheck:true,closure});
}
assert.equal(run('git', ['rev-parse', 'HEAD'], repository).trim(), source);
assert.equal(run('git', ['status', '--porcelain'], repository).trim(), '');
const receipt = {source,packages:results,newPublicE2E:0,normalNumericProfile:null,
  providerIO:0,moonOrRuntimeBuild:0,qualification:'External optional installer/import/refusal only; no Host Run, ACK/current-cut, live model or Named Result.'};
await writeFile(join(scratch, 'receipt.json'), JSON.stringify(receipt,null,2)+'\n');
console.log('OPTIONAL_PROVIDER_PACKS', JSON.stringify(receipt));
