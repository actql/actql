// Optional installer/export acceptance only: no Moon/Core runtime preparation,
// Provider request, numerical profile or public Result is exercised here.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdtemp, mkdir, readFile, writeFile, realpath} from 'node:fs/promises';
import {dirname, join, resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';

const repository = fileURLToPath(new URL('../', import.meta.url));
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const npm = join(dirname(process.execPath), '../lib/node_modules/npm/bin/npm-cli.js');
const scratch = await mkdtemp(join(tmpdir(), 'actql-a-optional-provider-'));
console.log('OPTIONAL_PROVIDER_CUSTODY', scratch);
const cache = join(scratch, 'cache'), artifacts = join(scratch, 'artifacts');
await mkdir(cache); await mkdir(artifacts);
// No caller credential/configuration variables or NODE_PATH reach npm/child
// consumers. Registry dependency acquisition is distinct from Provider I/O.
const env = {PATH: `${dirname(process.execPath)}:/usr/bin:/bin`, LANG: 'C',
  npm_config_cache: cache, npm_config_userconfig: '/dev/null',
  npm_config_globalconfig: '/dev/null', npm_config_registry: 'https://registry.npmjs.org',
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
test('external optional package has only the original installer export',()=>{
  assert.deepEqual(Object.keys(entry),[${JSON.stringify(factory)}]);
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
`;
  await writeFile(join(consumer, 'acceptance.test.mjs'), acceptance);
  const focused = 'import{runFocusedTests}from' + JSON.stringify(new URL('./test-execution.mjs', import.meta.url).href) +
    ';process.exitCode=runFocusedTests("node",process.argv.slice(1),{cwd:process.cwd(),timeout:30000});';
  const output = run(process.execPath, ['--input-type=module', '-e', focused, '--', 'acceptance.test.mjs'], consumer);
  console.log(output.trim());
  const summary = output.split('\n').filter(line => line.startsWith('ACTQL_TEST_SUMMARY '))
    .map(line => JSON.parse(line.slice('ACTQL_TEST_SUMMARY '.length))).at(-1);
  assert.equal(summary.success, true); assert.equal(summary.counts.tests, 3); assert.equal(summary.counts.passed, 3);
  const declaration = `import {${factory},type ${directory === 'provider-http' ? 'HttpChatRegistrationOptions' : 'OpenAIChatRegistrationOptions'}} from ${JSON.stringify(name)};
declare const original: ${directory === 'provider-http' ? 'HttpChatRegistrationOptions' : 'OpenAIChatRegistrationOptions'};
const callback: (runtime:unknown)=>readonly object[]=${factory}(original);
void callback;
// @ts-expect-error Original installation is not optional.
${factory}({providerId:'unfunded'});
// @ts-expect-error A send function is not part of the package entry.
import {startSdkTransport} from ${JSON.stringify(name)};
void startSdkTransport;
`;
  await writeFile(join(consumer, 'consumer.typecheck.mts'), declaration);
  run(process.execPath, [join(repository, 'node_modules/typescript/bin/tsc'), '--noEmit', '--strict',
    '--module', 'NodeNext', '--moduleResolution', 'NodeNext', '--target', 'ES2022', 'consumer.typecheck.mts'], consumer);
  const closure = [];
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
      closure.push({path,version:actual.version});
    }
    for (const path of ['dist/index.js', 'dist/index.mjs']) {
      const sdk = createRequire(join(installed, 'package.json')).resolve('@ai-sdk/openai');
      const sdkRoot = dirname(dirname(sdk));
      assert.equal(hash(await readFile(join(sdkRoot, path))),
        hash(await readFile(join(packageRoot, 'node_modules/@ai-sdk/openai', path))), path);
    }
  } else {
    assert.deepEqual(manifest.dependencies, {});
    const consumerLock = JSON.parse(await readFile(join(consumer, 'package-lock.json'), 'utf8'));
    assert.deepEqual(Object.keys(consumerLock.packages).sort(), ['', 'node_modules/@actql/provider-http']);
  }
  results.push({name,source,tarball,bytes:bytes.length,sha256:hash(bytes),integrity:metadata.integrity,
    consumer,tests:3,typecheck:true,closure});
}
assert.equal(run('git', ['rev-parse', 'HEAD'], repository).trim(), source);
assert.equal(run('git', ['status', '--porcelain'], repository).trim(), '');
const receipt = {source,packages:results,newPublicE2E:0,normalNumericProfile:null,
  providerIO:0,moonOrRuntimeBuild:0,qualification:'External optional installer/import/refusal only; no Host Run, ACK/current-cut, live model or Named Result.'};
await writeFile(join(scratch, 'receipt.json'), JSON.stringify(receipt,null,2)+'\n');
console.log('OPTIONAL_PROVIDER_PACKS', JSON.stringify(receipt));
