import './native-preparation-originals.test.mjs';
import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync as executeChild,spawn as spawnChild} from 'node:child_process';
import {once} from 'node:events';
import {runInNewContext} from 'node:vm';
import {createHash} from 'node:crypto';
import {lstatSync,mkdirSync,mkdtempSync,readFileSync,realpathSync,rmSync,symlinkSync,writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {prepareNativeRuntimeBundle, prepareNativeRuntimeBundleLibraries} from './native-runtime-bundle-fixture.mjs';
import * as selectedEntries from './native-runtime-bundle-fixture.mjs';

function residentLaunchSource() {
  const source=readFileSync(new URL('./test-native-resident-site.mjs',import.meta.url),'utf8');
  const declaration=/^const siteProcessEnvironment = .*;$/mu.exec(source)?.[0]??'';
  const start=source.indexOf('  const startSite = '),end=source.indexOf('  const waitFor = ',start);
  assert(start>=0 && end>start);
  const install=source.indexOf('  execFileSync(bundleTool, [...bundleCommon, \'install\'');
  const installed=source.indexOf('  const [registry, values, fragment]',install);
  assert(install>=0 && installed>install);
  return {declaration,startSite:source.slice(start,end),install:source.slice(install,installed)};
}

function assertSelectedChildEnvironment(value) {
  assert.equal(value.PATH,'/usr/bin:/bin');assert.equal(value.LANG,'C');
  assert.equal(value.ACTQL_PRODUCER_ONLY,undefined);
  assert(!Object.keys(value).some(name=>name.startsWith('LD_') || name==='GLIBC_TUNABLES'));
}

test('Resident original process launch does not inherit the Python producer loader environment',async t=>{
  const f=fixture(t,'linux');
  const parent={PATH:'/original-python-tools',LANG:'producer-language',
    LD_LIBRARY_PATH:'/hosted/python/lib',ACTQL_PRODUCER_ONLY:'original-producer'};
  const running=new Set(),source=residentLaunchSource(),calls=[];
  const start=runInNewContext(source.declaration+'\n'+source.startSite+'\nstartSite;',{
    root:f.root,common:['--publication-root','original-publication','--journal','original-journal',
      '--poll-url','original-poll','--observation-url','original-observation'],
    executable:'original-Resident',receiver:{origin:'https://receiver.invalid'},
    gateway:{origin:'https://gateway.invalid'},siteKey:'original-site',join,once,running,
    spawn:(command,args,options)=>{
      calls.push({command,args});
      if(options.env)assert.deepEqual(Object.keys(options.env).sort(),['LANG','PATH']);
      // The real OS child observes the ORIGINAL caller options; no Native
      // Runtime or authority is supplied by this explicit process port.
      return spawnChild(process.execPath,['-e',
        'console.log(JSON.stringify({kind:"environment",value:process.env}))'],
        {...options,env:options.env??parent});
    },
  });
  const original=start();
  const closed=once(original.child,'close');
  await original.exited;await closed;
  assert.equal(original.child.exitCode,0,original.stderr());
  assert.equal(original.child.signalCode,null);
  assert.equal(original.child.stdout.readableEnded,true);
  assert.equal(original.child.stderr.readableEnded,true);
  assert.equal(running.size,0);
  assert.equal(calls[0].command,'original-Resident');
  assert.equal(calls[0].args[0],'run');
  assertSelectedChildEnvironment(original.lines[0].value);
  assert.equal(parent.LD_LIBRARY_PATH,'/hosted/python/lib');
});

test('Resident bundle install and activation use the same explicit original child environment',t=>{
  const source=residentLaunchSource(),observed=[];
  const parent={PATH:'/producer-tools',LANG:'producer-language',LD_LIBRARY_PATH:'/hosted/python/lib'};
  runInNewContext(source.declaration+'\n'+source.install,{
    bundleTool:'original-installer',bundleCommon:['--store-root','original-root'],
    envelope:{runtimeBundleCid:'original-bundle'},bundleInput:'original-input',
    execFileSync:(command,args,options)=>{
      assert.equal(command,'original-installer');
      if(options.env)assert.deepEqual(Object.keys(options.env).sort(),['LANG','PATH']);
      const wire=executeChild(process.execPath,['-e','console.log(JSON.stringify(process.env))'],
        {...options,env:options.env??parent,stdio:'pipe',encoding:'utf8'});
      observed.push({args,environment:JSON.parse(wire)});
    },
  });
  assert.equal(observed.length,2);
  assert.equal(observed[0].args[2],'install');assert.equal(observed[1].args[2],'activate');
  for(const call of observed)assertSelectedChildEnvironment(call.environment);
  assert.equal(parent.LD_LIBRARY_PATH,'/hosted/python/lib');
});

function fixture(t, platform, entry = 'native_runtime_bundle', preparation = false) {
  const root=realpathSync(mkdtempSync(join(tmpdir(),'actql-bundle-producer-port-')));
  t.after(()=>rmSync(root,{recursive:true,force:true}));
  const tool=join(root,'tool');mkdirSync(tool);
  const compiler=join(tool,'cc'),sdk=join(tool,'SDK');
  writeFileSync(compiler,'selected compiler');mkdirSync(sdk);
  symlinkSync(compiler,join(tool,'compiler-alias'));
  symlinkSync(sdk,join(tool,'SDK-alias'));
  const source='a'.repeat(40),destination=join(root,preparation?entry:'selected');
  const executable=join(destination,`emission/native/release/build/cmd/${entry}/${entry}.exe`);
  const calls=[];let originalFailure,receiptEntry=entry;
  const execute=(command,args)=>{
    calls.push([command,args]);
    if(command==='git')return args[0]==='rev-parse'?source+'\n':'';
    if(command==='xcrun')return join(tool,args[0]==='--find'?'compiler-alias':'SDK-alias')+'\n';
    if(command==='sh')return join(tool,'compiler-alias')+'\n';
    assert.equal(command,'python3');
    assert.equal(args[0],join(root,'scripts/produce-native-remote-scoped-runtime.py'));
    assert.equal(args[args.indexOf('--entry')+1],'src/cmd/'+entry);
    assert.equal(args[args.indexOf('--target')+1],platform==='darwin'?'darwin-arm64':'linux-x64');
    assert.equal(args[args.indexOf('--source')+1],source);
    assert.equal(args[args.indexOf('--clang')+1],compiler);
    assert.equal(args.includes('--sdk'),platform==='darwin');
    if(platform==='darwin')assert.equal(args[args.indexOf('--sdk')+1],sdk);
    if(originalFailure)throw originalFailure;
    const bytes=Buffer.from('explicit Source-only artifact port; never executable');
    mkdirSync(join(destination,'emission/native/release/build/cmd',entry),{recursive:true});
    writeFileSync(executable,bytes,{mode:0o700});
    writeFileSync(join(destination,'build.json'),JSON.stringify({source,entry:'src/cmd/'+receiptEntry,
      target:platform==='darwin'?'darwin-arm64':'linux-x64',plan_only:false,moon_build_exit:0,providers:1,
      executable:{path:executable,bytes:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex')}}));
    return '';
  };
  return {root,tool,destination,executable,calls,execute,fail(error){originalFailure=error;},
    receiptEntry(value){receiptEntry=value;}};
}

test('Resident consumers select their original producer entry and receipt on both actual platforms',t=>{
  for(const [platform,arch] of [['darwin','arm64'],['linux','x64']]){
    const f=fixture(t,platform,'native_remote_resident_site');
    assert.equal(selectedEntries.prepareNativeResidentSite(f.root,f.destination,
      {execute:f.execute,platform,arch,moonHome:f.tool}),f.executable);
    assert.equal(f.calls.filter(([command])=>command==='python3').length,1);
    assert(!f.calls.some(([command])=>command==='moon'));
  }
});
test('Resident producer refusal propagates without selecting a raw executable',t=>{
  const f=fixture(t,'darwin','native_remote_resident_site');
  const original=Object.assign(new Error('original Resident producer refusal'),{status:9});
  f.fail(original);
  assert.throws(()=>selectedEntries.prepareNativeResidentSite(f.root,f.destination,
    {execute:f.execute,platform:'darwin',arch:'arm64',moonHome:f.tool}),error=>error===original);
  assert.equal(f.calls.filter(([command])=>command==='python3').length,1);
});
test('Resident preparation rejects a valid bundle receipt for a different original entry',t=>{
  const f=fixture(t,'darwin','native_remote_resident_site');
  f.receiptEntry('native_runtime_bundle');
  assert.throws(()=>selectedEntries.prepareNativeResidentSite(f.root,f.destination,
    {execute:f.execute,platform:'darwin',arch:'arm64',moonHome:f.tool}),/Expected values to be strictly equal/u);
});

function httpFixture(t,target) {
  const root=realpathSync(mkdtempSync(join(tmpdir(),'actql-resident-http-receipt-')));
  t.after(()=>rmSync(root,{recursive:true,force:true}));
  const path=join(root,'original-component'),bytes=Buffer.from('explicit receipt port; never loaded');
  writeFileSync(path,bytes);
  const metadata=lstatSync(path);
  const recipeBytes=readFileSync(new URL('./native-http-component-source.json',import.meta.url));
  const receipt={source:'b'.repeat(40),target,minimumMacOS:target==='darwin-arm64'?'11.0':null,
    recipe_sha256:createHash('sha256').update(recipeBytes).digest('hex'),
    upstream:JSON.parse(recipeBytes).upstream,loaded:0,initialized:0,installed_supplier:false,
    inputs:['component_tls_lifetime.c','component_tls_lifetime.h'].map(name=>{
      const relative='src/platform_native/http_client/'+name;
      const bytes=readFileSync(new URL('../'+relative,import.meta.url));
      return {path:'/original-producer/'+relative,bytes:bytes.length,
        sha256:createHash('sha256').update(bytes).digest('hex')};
    }),
    ownedOpenSSLReceipt:{path:join(root,'original-tls-receipt')},
    library:{path,bytes:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex'),
      dev:metadata.dev,ino:metadata.ino,mode:metadata.mode}};
  const receiptPath=join(root,'build.json');
  const save=()=>writeFileSync(receiptPath,JSON.stringify(receipt));
  save();return {path,receiptPath,receipt,save};
}

test('Resident HTTP selection retains an original owned component on each actual target',t=>{
  for(const [platform,arch,target] of [['darwin','arm64','darwin-arm64'],['linux','x64','linux-x64']]){
    const f=httpFixture(t,target);
    assert.equal(selectedEntries.prepareNativeResidentHttpLibrary({receiptPath:f.receiptPath,platform,arch,
      execute:()=>{assert.equal(platform,'darwin');return '14.0';}}),f.path);
  }
});
test('Resident HTTP refuses stock, foreign, initialized or changed originals before loading',t=>{
  const changes=[f=>{f.receipt.ownedOpenSSLReceipt=null;},f=>{f.receipt.target='linux-x64';},
    f=>{f.receipt.initialized=1;},f=>{f.receipt.recipe_sha256='0'.repeat(64);},
    f=>{f.receipt.inputs[0].sha256='0'.repeat(64);},
    f=>{f.receipt.minimumMacOS='26.0';},
    f=>{writeFileSync(f.path,'changed component');}];
  for(const change of changes){
    const f=httpFixture(t,'darwin-arm64');change(f);f.save();
    assert.throws(()=>selectedEntries.prepareNativeResidentHttpLibrary({receiptPath:f.receiptPath,
      platform:'darwin',arch:'arm64',execute:()=> '14.0'}));
  }
  assert.throws(()=>selectedEntries.prepareNativeResidentHttpLibrary({receiptPath:'',
    platform:'darwin',arch:'arm64'}),/original owned HTTP component receipt/u);
});

test('Resident HTTP keeps the original macOS 26 component profile only on an actual compatible OS',t=>{
  const f=httpFixture(t,'darwin-arm64');f.receipt.minimumMacOS='26.0';f.save();
  assert.equal(selectedEntries.prepareNativeResidentHttpLibrary({receiptPath:f.receiptPath,
    platform:'darwin',arch:'arm64',execute:()=> '26.0.1'}),f.path);
  assert.throws(()=>selectedEntries.prepareNativeResidentHttpLibrary({receiptPath:f.receiptPath,
    platform:'darwin',arch:'arm64',execute:()=> '14.7.2'}),/exceeds this actual macOS/u);
});

test('Resident HTTP retains decimal original identities and refuses rounding or noncanonical values',t=>{
  const f=httpFixture(t,'darwin-arm64');
  for(const key of ['dev','ino','mode'])f.receipt.library[key]=String(f.receipt.library[key]);
  f.save();
  const select=()=>selectedEntries.prepareNativeResidentHttpLibrary({receiptPath:f.receiptPath,
    platform:'darwin',arch:'arm64',execute:()=> '14.0'});
  assert.equal(select(),f.path);
  for(const identity of [2**60,'01','+1','1e3','-1','18446744073709551616']) {
    f.receipt.library.ino=identity;f.save();assert.throws(select);
  }
});

test('bundle consumers select the same existing producer for actual Darwin and explicit Linux entry recipes',t=>{
  for(const [platform,arch] of [['darwin','arm64'],['linux','x64']]){
    const f=fixture(t,platform);
    assert.equal(prepareNativeRuntimeBundle(f.root,f.destination,{execute:f.execute,platform,arch,moonHome:f.tool}),f.executable);
    assert.equal(f.calls.filter(([command])=>command==='python3').length,1);
    assert(!f.calls.some(([command])=>command==='moon'));
  }
});
test('a selected bundle producer failure propagates without raw build or artifact fallback',t=>{
  const f=fixture(t,'darwin'),original=Object.assign(new Error('original selected producer refusal'),{status:7});
  f.fail(original);
  assert.throws(()=>prepareNativeRuntimeBundle(f.root,f.destination,{execute:f.execute,platform:'darwin',arch:'arm64',moonHome:f.tool}),error=>error===original);
  assert.equal(f.calls.filter(([command])=>command==='python3').length,1);
  assert(!f.calls.some(([command])=>command==='moon'));
});
test('foreign platform selection refuses before a compiler or source query',t=>{
  const f=fixture(t,'darwin');
  assert.throws(()=>prepareNativeRuntimeBundle(f.root,f.destination,{execute:f.execute,platform:'linux',arch:'arm64',moonHome:f.tool}),/No selected bundle command recipe/u);
  assert.deepEqual(f.calls,[]);
});

test('verified preparation reuse and refusal never call another producer',t=>{
  const f=fixture(t,'darwin','native_runtime_bundle',true);
  prepareNativeRuntimeBundle(f.root,f.destination,{execute:f.execute,platform:'darwin',arch:'arm64',moonHome:f.tool});
  const item=path=>({path,bytes:readFileSync(path).length,
    sha256:createHash('sha256').update(readFileSync(path)).digest('hex')});
  const compiler=join(f.tool,'cc');
  writeFileSync(join(f.destination,'inputs.json'),JSON.stringify([item(compiler)]));
  writeFileSync(join(f.root,'preparation.json'),JSON.stringify({source:'a'.repeat(40),target:'darwin-arm64',
    clang:compiler,sdk:join(f.tool,'SDK'),moon_home:f.tool,
    entries:{native_runtime_bundle:item(join(f.destination,'build.json'))},components:{},http:null}));
  const execute=(command,args)=>{assert.notEqual(command,'python3');return f.execute(command,args);};
  const reuse=()=>prepareNativeRuntimeBundle(f.root,f.destination,
    {execute,platform:'darwin',arch:'arm64',moonHome:f.tool,preparation:f.root});
  assert.equal(reuse(),f.executable);
  writeFileSync(compiler,'changed original compiler');
  assert.throws(reuse,/Original preparation input/u);
  assert.equal(f.calls.filter(([command])=>command==='python3').length,1);
});

test('bundle libraries use the original component producers and verify their original bytes',t=>{
  for (const corrupt of [false,true]) {
    const f=fixture(t,'darwin');
    const destination=join(f.root,'components');
    const execute=(command,args)=>{
      if(command!=='python3')return f.execute(command,args);
      assert.equal(args[0],join(f.root,'scripts/prepare-native-runtime-bundle-components.py'));
      assert.equal(args[args.indexOf('--openssl-prefix')+1],f.tool);
      assert.equal(args[args.indexOf('--target')+1],'darwin-arm64');
      const receipt={source:'a'.repeat(40),target:'darwin-arm64',providers:0,loaded:false,initialized:false};
      for(const name of ['sqlite','crypto']) {
        mkdirSync(join(destination,name),{recursive:true});
        const path=join(destination,name,'original.dylib'),bytes=Buffer.from('Source-only '+name+' bytes');
        writeFileSync(path,bytes);
        receipt[name]={path,bytes:bytes.length,sha256:corrupt?'0'.repeat(64):createHash('sha256').update(bytes).digest('hex')};
      }
      writeFileSync(join(destination,'bundle-components.json'),JSON.stringify(receipt));
      return '';
    };
    const prepare=()=>prepareNativeRuntimeBundleLibraries(f.root,destination,
      {execute,platform:'darwin',arch:'arm64',opensslPrefix:f.tool,darwinCryptoProfile:'homebrew26'});
    if(corrupt)assert.throws(prepare,/Expected values to be strictly equal/u);
    else assert.deepEqual(prepare(),{sqliteLibrary:join(destination,'sqlite/original.dylib'),
      cryptoLibrary:join(destination,'crypto/original.dylib')});
  }
});
