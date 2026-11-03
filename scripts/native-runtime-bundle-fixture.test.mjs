import './native-preparation-originals.test.mjs';
import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {mkdirSync,mkdtempSync,readFileSync,realpathSync,rmSync,symlinkSync,writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {prepareNativeRuntimeBundle, prepareNativeRuntimeBundleLibraries} from './native-runtime-bundle-fixture.mjs';
import * as selectedEntries from './native-runtime-bundle-fixture.mjs';

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
    entries:{native_runtime_bundle:item(join(f.destination,'build.json'))},components:{}}));
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
