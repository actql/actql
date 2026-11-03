import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {mkdirSync,mkdtempSync,realpathSync,rmSync,writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {prepareNativeRuntimeBundle} from './native-runtime-bundle-fixture.mjs';

function fixture(t, platform) {
  const root=realpathSync(mkdtempSync(join(tmpdir(),'actql-bundle-producer-port-')));
  t.after(()=>rmSync(root,{recursive:true,force:true}));
  const tool=join(root,'tool');mkdirSync(tool);
  const source='a'.repeat(40),destination=join(root,'selected');
  const executable=join(destination,'emission/native/release/build/cmd/native_runtime_bundle/native_runtime_bundle.exe');
  const calls=[];let originalFailure;
  const execute=(command,args)=>{
    calls.push([command,args]);
    if(command==='git')return args[0]==='rev-parse'?source+'\n':'';
    if(command==='xcrun')return args[0]==='--find'?'/actual/clang\n':'/actual/SDK\n';
    if(command==='sh')return '/actual/cc\n';
    assert.equal(command,'python3');
    assert.equal(args[0],join(root,'scripts/produce-native-remote-scoped-runtime.py'));
    assert.equal(args[args.indexOf('--entry')+1],'src/cmd/native_runtime_bundle');
    assert.equal(args[args.indexOf('--target')+1],platform==='darwin'?'darwin-arm64':'linux-x64');
    assert.equal(args[args.indexOf('--source')+1],source);
    assert.equal(args.includes('--sdk'),platform==='darwin');
    if(originalFailure)throw originalFailure;
    const bytes=Buffer.from('explicit Source-only artifact port; never executable');
    mkdirSync(join(destination,'emission/native/release/build/cmd/native_runtime_bundle'),{recursive:true});
    writeFileSync(executable,bytes,{mode:0o700});
    writeFileSync(join(destination,'build.json'),JSON.stringify({source,entry:'src/cmd/native_runtime_bundle',
      target:platform==='darwin'?'darwin-arm64':'linux-x64',plan_only:false,moon_build_exit:0,providers:1,
      executable:{path:executable,bytes:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex')}}));
    return '';
  };
  return {root,tool,destination,executable,calls,execute,fail(error){originalFailure=error;}};
}

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
