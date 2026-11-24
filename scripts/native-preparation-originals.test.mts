// Source-only byte/receipt controls. No fixture below is executed or loaded.
import assert from 'node:assert/strict';
import test from 'node:test';
import type {TestContext} from 'node:test';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {chmodSync,cpSync,existsSync,lstatSync,mkdirSync,mkdtempSync,readFileSync,realpathSync,rmSync,symlinkSync,writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {preparedNativeCommand,preparedNativeComponents,preparedNativeHttpReceipt} from './native-preparation-originals.mjs';
import * as originals from './native-preparation-originals.mjs';
import fs from 'node:fs';
import {syncBuiltinESMExports} from 'node:module';
import {prepareNativeRuntimeBundle,prepareNativeResidentSite} from './native-runtime-bundle-fixture.mjs';

type Fingerprint = {bytes: number; sha256: string};
type Descriptor = Fingerprint & {path: string};
type Selector = Parameters<typeof originals.exportNativeCompiledCommand>[3];
type CompileContext = {source: string; target: string; repository: string; moon_home: string;
  clang: string; sdk: string; systemTool?: Selector['systemTool']};
type BuildReceipt = {plan_only: boolean; moon_build_exit: number; completed_c_steps: number;
  compiler_profile: string; entry: string; installed_supplier: boolean};
type CommandManifest = {members: {file: string; original: Descriptor}[]};
type ProducerReceipt = {path: string; body: {source: string; inputs: Record<string, Fingerprint>;
  compiled_inputs: Record<string, Fingerprint & {resolved_path: string}>; library: Fingerprint}};
type OriginalHttpLibrary = Descriptor & Record<'dev' | 'ino' | 'mode', string | number>;
type HttpComponent = {source: string; target: string; minimumMacOS: string; loaded: number; initialized: number;
  installed_supplier: boolean; inputs: readonly Descriptor[]; upstream: unknown; library: OriginalHttpLibrary;
  ownedOpenSSLReceipt?: Descriptor; modelResolver?: {backend: string; addressLookup: string}};
type Prepared = Exclude<ReturnType<typeof preparedNativeCommand>, string>;
const fingerprint=(bytes: Buffer)=>({bytes:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex')});
const descriptor=(path: string)=>({path,...fingerprint(readFileSync(path))});
function fixture(t: TestContext) {
  const root=realpathSync(mkdtempSync(join(tmpdir(),'actql-native-prepared-originals-')));
  t.after(()=>rmSync(root,{recursive:true,force:true}));
  const header=join(root,'original.h'),clang=join(root,'compiler'),sdk=join(root,'SDK');
  writeFileSync(header,'original pinned public header');writeFileSync(clang,'compiler port');mkdirSync(sdk);
  const source='a'.repeat(40),target='darwin-arm64',selected={source,target,clang,sdk,moon_home:root};
  const command=join(root,'native_runtime_bundle'),components=join(root,'components');
  mkdirSync(command);mkdirSync(components);
  const executable=join(command,'emission/native/release/build/cmd/native_runtime_bundle/native_runtime_bundle.exe');
  mkdirSync(join(command,'emission/native/release/build/cmd/native_runtime_bundle'),{recursive:true});
  writeFileSync(executable,'Source-only command bytes');
  writeFileSync(join(command,'inputs.json'),JSON.stringify([descriptor(header),descriptor(clang)]));
  writeFileSync(join(command,'build.json'),JSON.stringify({source,target,entry:'src/cmd/native_runtime_bundle',
    plan_only:false,moon_build_exit:0,providers:1,executable:descriptor(executable)}));
  const receipts: Record<string, ProducerReceipt>={},body: {
    source: string; target: string; providers: number; loaded: boolean; initialized: boolean;
    producer_receipts: Record<string, Descriptor>; sqlite?: Descriptor; crypto?: Descriptor;
  }={source,target,providers:0,loaded:false,initialized:false,producer_receipts:{}};
  for(const name of ['sqlite','crypto'] as const) {
    const directory=join(components,name);mkdirSync(directory);
    const library=join(directory,'libactql_'+name+'_component.dylib');writeFileSync(library,'Source-only '+name+' component');
    const path=join(directory,name==='sqlite'?'process-producer.json':'producer.json');
    const pin=fingerprint(readFileSync(header));
    receipts[name]={path,body:{source,inputs:{[header]:pin},compiled_inputs:{[header]:{resolved_path:header,...pin}},
      library:fingerprint(readFileSync(library))}};
    body[name]=descriptor(library);
  }
  const record: {source: string; target: string; clang: string; sdk: string; moon_home: string;
    entries: Record<string, Descriptor>; components: object; http: Descriptor | null}=
    {source,target,clang,sdk,moon_home:root,entries:{},components:{},http:null};
  function publish() {
    for(const [name,item] of Object.entries(receipts)) {
      writeFileSync(item.path,JSON.stringify(item.body));body.producer_receipts[name]=descriptor(item.path);
    }
    writeFileSync(join(components,'bundle-components.json'),JSON.stringify(body));
    record.entries.native_runtime_bundle=descriptor(join(command,'build.json'));
    record.components=descriptor(join(components,'bundle-components.json'));
    writeFileSync(join(root,'preparation.json'),JSON.stringify(record));
  }
  publish();return {root,header,clang,sdk,source,target,selected,command,components,executable,receipts,body,record,publish};
}

test('same-source selected public artifacts retain both command and component input identities',t=>{
  const f=fixture(t);
  assert.equal(preparedNativeCommand(f.root,'native_runtime_bundle',f.selected),f.command);
  assert.equal(preparedNativeComponents(f.root,f.selected),f.components);
});

function httpPreparation(t: TestContext) {
  const f=fixture(t),directory=join(f.root,'http');
  mkdirSync(join(directory,'owned-tls/stage'),{recursive:true});
  mkdirSync(join(directory,'component/bundle'),{recursive:true});
  const recipe=JSON.parse(readFileSync(new URL('./native-http-component-source.json',import.meta.url)) as unknown as string) as {ownedOpenSSLSource: unknown; upstream: unknown};
  const pin=descriptor(f.header),library=join(directory,'component/bundle/libcurl.4.dylib');
  writeFileSync(library,'Source-only owned HTTP bytes; never loaded');
  const tlsPath=join(directory,'owned-tls/build.json'),componentPath=join(directory,'component/build.json');
  const tls={source:f.source,target:f.target,minimumMacOS:'11.0',loaded:0,inputs:[pin],
    stage:join(directory,'owned-tls/stage'),upstream:recipe.ownedOpenSSLSource,
    compiledLibraries:2,installedSupplier:false,files:[pin]};
  const identity=lstatSync(library);
  const component: HttpComponent={source:f.source,target:f.target,minimumMacOS:'11.0',loaded:0,initialized:0,
    installed_supplier:false,inputs:[pin],upstream:recipe.upstream,library:{...descriptor(library),
      dev:identity.dev,ino:identity.ino,mode:identity.mode}};
  const body: {source: string; target: string; minimumMacOS: string; loaded: number; initialized: number;
    installed_supplier: boolean; inputs: readonly Descriptor[]; tls?: Descriptor; component?: Descriptor}=
    {source:f.source,target:f.target,minimumMacOS:'11.0',loaded:0,initialized:0,
    installed_supplier:false,inputs:[pin]};
  function publish() {
    writeFileSync(tlsPath,JSON.stringify(tls));body.tls=descriptor(tlsPath);
    component.ownedOpenSSLReceipt=descriptor(tlsPath);
    writeFileSync(componentPath,JSON.stringify(component));body.component=descriptor(componentPath);
    writeFileSync(join(directory,'preparation.json'),JSON.stringify(body));
    f.record.http=descriptor(join(directory,'preparation.json'));f.publish();
  }
  publish();return {...f,tls,component,body,componentPath,library,publishHttp:publish};
}
test('Resident preparation retains the exact same-source owned TLS and HTTP originals',t=>{
  const f=httpPreparation(t);
  for(const key of ['dev','ino','mode'] as const)f.component.library[key]=String(f.component.library[key]);
  f.publishHttp();
  assert.equal(preparedNativeHttpReceipt(f.root,f.selected),f.componentPath);
});
test('Model HTTP cannot select a historical Resident preparation without the Model resolver', t => {
  const f = httpPreparation(t);
  assert.equal(preparedNativeHttpReceipt(f.root, f.selected), f.componentPath);
  assert.throws(() => preparedNativeHttpReceipt(f.root, f.selected, {requireModelResolver: true}),
    /did not select the Model resolver/u);
});
test('Remote HTTP cannot select a preparation stamped with a Model resolver', t => {
  const f = httpPreparation(t);
  f.component.modelResolver = {backend: 'c-ares', addressLookup: 'c-ares'};
  f.publishHttp();
  assert.throws(() => preparedNativeHttpReceipt(f.root, f.selected),
    /Remote HTTP requires the synchronous component original/u);
});

test('Remote HTTP preparation reuse requires an ancestor and the complete unchanged producer tree', t => {
  const directory = mkdtempSync(join(tmpdir(), 'actql-remote-http-source-'));
  t.after(() => rmSync(directory, {recursive: true, force: true}));
  const git = (...args: string[]) => execFileSync('git', ['-c', 'user.name=ActQL Test', '-c', 'user.email=test@example.com', ...args],
    {cwd: directory, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe']}).trim();
  const write = (path: string, bytes: string) => {
    mkdirSync(join(directory, path, '..'), {recursive: true});
    writeFileSync(join(directory, path), bytes);
  };
  const commit = (message: string) => {
    git('add', '.');
    git('commit', '-m', message);
    return git('rev-parse', 'HEAD');
  };
  git('init', '-q');
  const adapter = 'src/platform_native/http_client/component_tls_lifetime.c';
  for (const path of [
    'scripts/native-http-component-source.json',
    'scripts/prepare-native-resident-http-component.py',
    'scripts/produce-native-http-component.py',
    'scripts/produce-native-http-tls.py',
    'scripts/produce-native-remote-scoped-runtime.py',
    'scripts/fixtures/curl-release-key-27EDEAF22F3ABCEB50DB9A125CC908FDB71E12C2.asc',
    adapter, 'src/platform_native/http_client/component_tls_lifetime.h',
  ]) write(path, path);
  const original = commit('test: establish complete producer inputs');
  write('README.md', 'independent package source');
  const successor = commit('test: change unrelated package source');
  assert.doesNotThrow(() => originals.verifyRemoteHttpProducerInputs(original, successor, directory));
  assert.throws(() => originals.verifyRemoteHttpProducerInputs(successor, original, directory));
  write(adapter, 'changed TLS allocator input');
  const changed = commit('test: change one producer input');
  assert.throws(() => originals.verifyRemoteHttpProducerInputs(original, changed, directory), /producer inputs changed/u);
  rmSync(join(directory, adapter));
  const incomplete = commit('test: remove one producer input');
  assert.throws(() => originals.verifyRemoteHttpProducerInputs(original, incomplete, directory), /Incomplete Remote HTTP producer input tree/u);
});

test('Resident prepared originals refuse unsafe numbers or noncanonical decimal identities',t=>{
  for(const identity of [2**60,'01','+1','1e3','-1','18446744073709551616']) {
    const f=httpPreparation(t);f.component.library.ino=identity;f.publishHttp();
    assert.throws(()=>preparedNativeHttpReceipt(f.root,f.selected));
  }
});
test('Resident preparation refuses incomplete, foreign, old deployment or changed originals',t=>{
  for(const change of [(f: ReturnType<typeof httpPreparation>)=>{f.record.http=null;f.publish();},
    (f: ReturnType<typeof httpPreparation>)=>{f.tls.minimumMacOS='26.0';f.publishHttp();},
    (f: ReturnType<typeof httpPreparation>)=>{f.component.source='b'.repeat(40);f.publishHttp();},
    (f: ReturnType<typeof httpPreparation>)=>{(f.component.library.ino as number)++;f.publishHttp();},
    (f: ReturnType<typeof httpPreparation>)=>{writeFileSync(f.header,'changed original TLS compiler input');},
    (f: ReturnType<typeof httpPreparation>)=>{writeFileSync(f.library,'changed HTTP library');}]) {
    const f=httpPreparation(t);change(f);
    assert.throws(()=>preparedNativeHttpReceipt(f.root,f.selected));
  }
});
test('foreign source, target, compiler or command selection refuses without a substitute',t=>{
  const f=fixture(t);
  for(const changed of [{source:'b'.repeat(40)},{target:'linux-x64'},{clang:'/foreign/clang'},{sdk:'/foreign/SDK'}]) {
    assert.throws(()=>preparedNativeCommand(f.root,'native_runtime_bundle',{...f.selected,...changed}));
    assert.throws(()=>preparedNativeComponents(f.root,{...f.selected,...changed}));
  }
  assert.throws(()=>preparedNativeCommand(f.root,'native_remote_resident_site',f.selected));
  assert.throws(()=>preparedNativeCommand(f.root,'native_client',f.selected));
});
test('changed original source input or emitted command bytes cannot be reused',t=>{
  for(const what of ['header','executable'] as const) {
    const f=fixture(t);writeFileSync(f[what],'changed original bytes');
    assert.throws(()=>preparedNativeCommand(f.root,'native_runtime_bundle',f.selected),/Original preparation input/u);
  }
});
test('a compiler-observed overlapping header cannot erase the original component pin during reuse',t=>{
  const f=fixture(t);writeFileSync(f.header,'changed during the compiler invocation');
  for(const item of Object.values(f.receipts))item.body.compiled_inputs[f.header]={
    resolved_path:f.header,...fingerprint(readFileSync(f.header))};
  f.publish();
  assert.throws(()=>preparedNativeComponents(f.root,f.selected),/Original preparation input/u);
});
test('changed receipt bytes or incomplete preparation cannot be adopted',t=>{
  const f=fixture(t);writeFileSync(join(f.command,'build.json'),'changed receipt');
  assert.throws(()=>preparedNativeCommand(f.root,'native_runtime_bundle',f.selected),/Original preparation input/u);
  rmSync(join(f.root,'preparation.json'));
  assert.throws(()=>preparedNativeComponents(f.root,f.selected),/ENOENT/u);
});

function compiledCommandFixture(t: TestContext,entry='native_runtime_bundle',preparationEntry=false) {
  const root=realpathSync(mkdtempSync(join(tmpdir(),'actql-command-adoption-')));
  t.after(()=>rmSync(root,{recursive:true,force:true}));
  const origin=join(root,'origin'),receiver=join(root,'receiver');
  const put=(path: string,body: string)=>{mkdirSync(join(path,'..'),{recursive:true});writeFileSync(path,body);return path;};
  const context: CompileContext={source:'a'.repeat(40),target:'darwin-arm64',repository:join(origin,'repository'),
    moon_home:join(origin,'moon'),clang:join(origin,'tools/clang'),sdk:join(origin,'SDK')};
  const header=put(join(context.repository,'src/original.h'),'exact original Source header');
  put(join(context.repository,'toolchain.json'),'exact pinned toolchain');
  put(join(context.moon_home,'bin/moon'),'exact original Moon tool');
  put(context.clang,'exact original Clang tool');
  put(join(context.sdk,'SDKSettings.json'),'exact original ABI');
  const directory=join(origin,'command');mkdirSync(directory);
  const generated=put(join(directory,'derived-read-source/original.h'),'exact original generated allocator header');
  const executable=put(join(directory,`emission/native/release/build/cmd/${entry}/${entry}.exe`),
    'explicit inert compiled-command port, never executed');
  chmodSync(executable,0o700);
  const generatedC=put(executable.slice(0,-4)+'.c','explicit original generated C port');
  const selected=[context.clang,'-O2','-o',executable,generatedC];
  put(join(directory,'commands.json'),JSON.stringify([selected]));
  const step=join(directory,'cc-0.json');
  put(step,JSON.stringify({original:['original',generatedC],selected,exit:0,output:descriptor(executable)}));
  put(join(directory,'cc-plan.json'),JSON.stringify({steps:[{original:['original',generatedC],selected,receipt:step}],
    allocator_inputs:[descriptor(generated)]}));
  const inputs=[header,join(context.repository,'toolchain.json'),join(context.moon_home,'bin/moon'),
    context.clang,join(context.sdk,'SDKSettings.json'),generated,join(directory,'cc-plan.json')].map(descriptor);
  put(join(directory,'inputs.json'),JSON.stringify(inputs));
  const body={source:context.source,target:context.target,entry:'src/cmd/'+entry,plan_only:false,moon_build_exit:0,
    compiler_backend:'pinned ordinary C (MOONBIT_NEW_NATIVE=0)',compiler_profile:'ordinary Moon --release --strip',
    providers:1,core_modules:1,commands_completed:1,completed_c_steps:1,
    installed_supplier:false,normal_profile:null,runtime_cases:0,public_e2e:0,
    executable:descriptor(executable),generated_c:descriptor(generatedC)};
  put(join(directory,'build.json'),JSON.stringify(body));
  mkdirSync(receiver);
  for(const name of ['repository','moon','tools','SDK'])cpSync(join(origin,name),join(receiver,name),{recursive:true});
  const current={...context,repository:join(receiver,'repository'),moon_home:join(receiver,'moon'),
    clang:join(receiver,'tools/clang'),sdk:join(receiver,'SDK')};
  const artifact=join(root,'offered'),received=join(root,'received-input'),destination=join(receiver,preparationEntry?entry:'prepared');
  const calls: [string, readonly string[]][]=[];
  const execute=(command: string,args: readonly string[])=>{
    calls.push([command,args]);
    if(command==='git')return args[0]==='rev-parse'?current.source+'\n':'';
    if(command==='xcrun')return (args[0]==='--find'?current.clang:current.sdk)+'\n';
    assert.fail('Received compiled DATA must not invoke another producer: '+command);
  };
  const publish=()=>{
    assert.equal(typeof originals.exportNativeCompiledCommand,'function');
    const offered=originals.exportNativeCompiledCommand(directory,artifact,entry,context);
    cpSync(artifact,received,{recursive:true});
    return {...offered,path:join(received,'command.json')};
  };
  const receive=(input: Parameters<typeof originals.receiveNativeCompiledCommand>[0] | undefined,
    overrides: NonNullable<Parameters<typeof prepareNativeRuntimeBundle>[2]> = {})=>(entry==='native_runtime_bundle'?prepareNativeRuntimeBundle:prepareNativeResidentSite)(
    current.repository,destination,{platform:'darwin',arch:'arm64',moonHome:current.moon_home,execute,
      preparation:null,compiledInput:input,...overrides});
  return {root,origin,directory,body,context,current,artifact,received,destination,calls,publish,receive,put,receiver};
}

test('compiled command adoption keeps origin bytes and creates a fresh receiver without producer or old paths',t=>{
  for(const entry of ['native_runtime_bundle','native_remote_resident_site']) {
    const f=compiledCommandFixture(t,entry),originReceipt=readFileSync(join(f.directory,'build.json'));
    const input=f.publish();
    assert(readFileSync(join(f.artifact,'origin-build.json')).equals(originReceipt));
    rmSync(f.origin,{recursive:true});
    const binary=f.receive(input);
    assert.equal(binary,join(f.destination,'received-command.exe'));
    assert.equal(readFileSync(binary,'utf8'),'explicit inert compiled-command port, never executed');
    assert(!existsSync(join(f.destination,'build.json')),'old physical producer receipt must not be fabricated');
    const current=JSON.parse(readFileSync(join(f.destination,'received.json')) as unknown as string),identity=lstatSync(binary,{bigint:true});
    assert.equal(current.kind,'received-native-command');assert.equal(current.source,f.current.source);
    assert.equal(current.executable.path,binary);assert.equal(current.executable.ino,String(identity.ino));
    assert.equal(current.executable.dev,String(identity.dev));
    assert(readFileSync(join(f.received,'origin-build.json')).equals(originReceipt));
    assert(f.calls.every(([name])=>name==='git'||name==='xcrun'));
  }
});

test('compiled command adoption refuses changed source target current tools ABI and explicit mode ambiguity',t=>{
  for(const change of [(f: ReturnType<typeof compiledCommandFixture>)=>{f.current.source='b'.repeat(40);},(f: ReturnType<typeof compiledCommandFixture>)=>{f.put(f.current.clang,'changed compiler');},
    (f: ReturnType<typeof compiledCommandFixture>)=>{f.put(join(f.current.repository,'src/original.h'),'changed Source');},
    (f: ReturnType<typeof compiledCommandFixture>)=>{f.put(join(f.current.moon_home,'bin/moon'),'changed Moon');},
    (f: ReturnType<typeof compiledCommandFixture>)=>{f.put(join(f.current.sdk,'SDKSettings.json'),'changed ABI');}]) {
    const f=compiledCommandFixture(t),input=f.publish();change(f);
    assert.throws(()=>f.receive(input));assert(!existsSync(f.destination));
  }
  const f=compiledCommandFixture(t),input=f.publish();
  assert.throws(()=>f.receive(input,{platform:'linux',arch:'x64'}));
  assert.throws(()=>f.receive(input,{preparation:f.artifact}));
  assert(!existsSync(f.destination));
});

test('compiled command adoption refuses altered transferred bytes receipt and generated input before publication',t=>{
  for(const change of [(f: ReturnType<typeof compiledCommandFixture>)=>f.put(join(f.received,'command.json'),'changed manifest'),
    (f: ReturnType<typeof compiledCommandFixture>)=>f.put(join(f.received,'origin-build.json'),'changed receipt'),
    (f: ReturnType<typeof compiledCommandFixture>)=>{const body=(JSON.parse(readFileSync(join(f.received,'command.json')) as unknown as string) as CommandManifest);
      f.put(join(f.received,body.members.find(x=>x.original.path.endsWith('.exe'))!.file),'changed compiled binary');},
    (f: ReturnType<typeof compiledCommandFixture>)=>{const body=(JSON.parse(readFileSync(join(f.received,'command.json')) as unknown as string) as CommandManifest);
      f.put(join(f.received,body.members.find(x=>x.original.path.endsWith('derived-read-source/original.h'))!.file),'changed generated input');}]) {
    const f=compiledCommandFixture(t),input=f.publish();change(f);
    assert.throws(()=>f.receive(input));assert(!existsSync(f.destination));
  }
});

test('compiled command export and adoption refuse incomplete execution foreign entry symlinks and existing receivers',t=>{
  for(const change of [(body: BuildReceipt)=>{body.plan_only=true;},(body: BuildReceipt)=>{body.moon_build_exit=1;},
    (body: BuildReceipt)=>{body.completed_c_steps=0;},(body: BuildReceipt)=>{body.compiler_profile='foreign profile';},
    (body: BuildReceipt)=>{body.entry='src/cmd/native_client';},(body: BuildReceipt)=>{body.installed_supplier=true;}]) {
    const f=compiledCommandFixture(t);change(f.body);f.put(join(f.directory,'build.json'),JSON.stringify(f.body));
    assert.throws(()=>f.publish());assert(!existsSync(f.artifact));
  }
  const f=compiledCommandFixture(t),input=f.publish();mkdirSync(f.destination);
  assert.throws(()=>f.receive(input));assert.deepEqual(Object.keys(JSON.parse(readFileSync(input.path) as unknown as string)).includes('members'),true);
  const other=compiledCommandFixture(t),offered=other.publish();
  const body=JSON.parse(readFileSync(offered.path) as unknown as string) as CommandManifest,member=body.members.find(x=>x.original.path.endsWith('.exe'));
  const path=join(other.received,member!.file);rmSync(path);symlinkSync(join(other.directory,'emission/native/release/build/cmd/native_runtime_bundle/native_runtime_bundle.exe'),path);
  assert.throws(()=>other.receive(offered));assert(!existsSync(other.destination));
});

test('compiled command input scope refuses unknown files before payload reads',t=>{
  for(const path of ['/unavailable/private/state.sqlite','/unavailable/keys.json','/unavailable/arbitrary-tool']) {
    const f=compiledCommandFixture(t),file=join(f.directory,'inputs.json');
    const inputs=JSON.parse(readFileSync(file) as unknown as string) as Descriptor[];inputs.push({path,bytes:1,sha256:'0'.repeat(64)});
    f.put(file,JSON.stringify(inputs));
    assert.throws(()=>f.publish(),/Unknown stable compiler input/u);
    assert(!existsSync(f.artifact));
  }
});

test('compiled command external tools bind the current selected bytes and original finite receiver budget',t=>{
  const f=compiledCommandFixture(t),tool=f.put(join(f.root,'current-tools/python3'),'original selected interpreter');
  const file=join(f.directory,'inputs.json'),inputs=JSON.parse(readFileSync(file) as unknown as string) as Descriptor[];
  inputs.push(descriptor(tool));f.put(file,JSON.stringify(inputs));
  const selected: [string, string][]=[];
  f.context.systemTool=(role,target)=>{selected.push([role,target]);return tool;};
  const input=f.publish();f.current.systemTool=f.context.systemTool;
  assert.throws(()=>originals.receiveNativeCompiledCommand(input,f.destination,'native_runtime_bundle',f.current,{seconds:0}));
  assert(!existsSync(f.destination));
  const changed=f.put(join(f.root,'changed-tools/python3'),'changed selected interpreter');
  f.current.systemTool=()=>changed;
  assert.throws(()=>originals.receiveNativeCompiledCommand(input,f.destination,'native_runtime_bundle',f.current));
  assert(!existsSync(f.destination));f.current.systemTool=f.context.systemTool;
  const binary=originals.receiveNativeCompiledCommand(input,f.destination,'native_runtime_bundle',f.current,{seconds:1});
  assert.equal(readFileSync(binary,'utf8'),'explicit inert compiled-command port, never executed');
  assert(selected.every(([role,target])=>role==='python'&&target==='darwin-arm64'));
});

test('compiled command retains original allocator objects declared by the actual C plan outside general source inventory',t=>{
  const f=compiledCommandFixture(t),object=f.put(join(f.directory,'derived-read-source/libmoonbitrun.o'),'original copied runtime object');
  const planPath=join(f.directory,'cc-plan.json'),plan=JSON.parse(readFileSync(planPath) as unknown as string) as {allocator_inputs: Descriptor[]};
  plan.allocator_inputs.push(descriptor(object));f.put(planPath,JSON.stringify(plan));
  const inputPath=join(f.directory,'inputs.json'),inputs=JSON.parse(readFileSync(inputPath) as unknown as string) as Descriptor[];
  const at=inputs.findIndex(x=>x.path===planPath);inputs[at]=descriptor(planPath);f.put(inputPath,JSON.stringify(inputs));
  const originalInputs=readFileSync(inputPath),input=f.publish();
  assert(readFileSync(inputPath).equals(originalInputs));
  const record=JSON.parse(readFileSync(input.path) as unknown as string) as CommandManifest;assert(record.members.some(x=>x.original.path===object));
  rmSync(f.origin,{recursive:true});
  assert.equal(readFileSync(f.receive(input),'utf8'),'explicit inert compiled-command port, never executed');
});

function receivedPreparation(t: TestContext) {
  const f=compiledCommandFixture(t,'native_runtime_bundle',true),input=f.publish(),binary=f.receive(input);
  const path=join(f.receiver,'preparation.json');
  f.put(path,JSON.stringify({source:f.current.source,target:f.current.target,clang:f.current.clang,sdk:f.current.sdk,
    moon_home:f.current.moon_home,entries:{native_runtime_bundle:descriptor(join(f.destination,'received.json'))},
    components:null,http:null}));
  const select=()=>preparedNativeCommand(f.receiver,'native_runtime_bundle',f.current) as Prepared;
  return {...f,binary,input,select};
}

test('received preparation keeps one checked immutable scope but rechecks current executable and external mutation',t=>{
  const f=receivedPreparation(t),originalRead=fs.readFileSync;let inventoryReads=0;
  fs.readFileSync=(function(this: unknown,path: Parameters<typeof originalRead>[0],
    ...args: [options?: Parameters<typeof originalRead>[1]]){if(String(path)===join(f.received,'origin-inputs.json'))inventoryReads++;
    return originalRead.call(this,path,...args);}) as typeof originalRead;syncBuiltinESMExports();
  try {
    const first=f.select();assert.equal(first.kind,'received');assert.equal(first.binary,f.binary);
    assert.equal(inventoryReads,1);assert.deepEqual(f.select(),first);assert.equal(inventoryReads,1);
    f.put(join(f.current.repository,'src/original.h'),'changed current source');
    assert.throws(f.select);assert.equal(inventoryReads,2);
  } finally {fs.readFileSync=originalRead;syncBuiltinESMExports();}
});

test('received preparation refuses replaced executable or foreign context without invoking a producer',t=>{
  for(const change of [(f: ReturnType<typeof receivedPreparation>)=>{f.put(f.binary,'changed current executable');},
    (f: ReturnType<typeof receivedPreparation>)=>{f.current.source='b'.repeat(40);},(f: ReturnType<typeof receivedPreparation>)=>{f.current.target='linux-x64';}]) {
    const f=receivedPreparation(t);assert.equal(f.select().binary,f.binary);change(f);
    assert.throws(f.select);assert(f.calls.every(([name])=>name==='git'||name==='xcrun'));
  }
});

test('received command factory consumes the checked preparation without copy or producer and still refuses changed input',t=>{
  const f=receivedPreparation(t),before=lstatSync(f.binary,{bigint:true});
  const consume=()=>f.receive(undefined,{preparation:f.receiver});
  assert.equal(consume(),f.binary);assert.equal(consume(),f.binary);
  const after=lstatSync(f.binary,{bigint:true});
  for(const key of ['dev','ino','mtimeNs','ctimeNs'] as const)assert.equal(after[key],before[key]);
  f.put(join(f.current.repository,'src/original.h'),'changed actual Source input');
  assert.throws(consume);assert(f.calls.every(([name])=>name==='git'||name==='xcrun'));
});
