import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,rmSync,symlinkSync,lstatSync,existsSync,chmodSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {copyNativePreparationTools,prepareNativeConstructionLane,prepareNativeParallel} from './native-preparation-lanes.mjs';
import {installationFiles} from './moonbit-installation.mjs';

function fixture(t) {
  const repository=mkdtempSync(join(tmpdir(),'actql-preparation-lanes-'));
  t.after(()=>rmSync(repository,{recursive:true,force:true}));
  const destination=join(repository,'outputs'),moonHome=join(repository,'tools');
  mkdirSync(destination);mkdirSync(moonHome);
  writeFileSync(join(repository,'toolchain.json'),'{}');
  const put=(path,bytes='original')=>{mkdirSync(join(path,'..'),{recursive:true});writeFileSync(path,bytes);};
  return {repository,destination,moonHome,source:'a'.repeat(40),target:'darwin-arm64',selection:'all',
    seconds:900,residentSeconds:1200,httpJobs:2,put};
}

test('Native parallel preparation isolates actual tool copies and excludes mutable Core caches',t=>{
  const f=fixture(t),marker=JSON.stringify({pin:{},platform:f.target});
  for(const path of installationFiles) {
    f.put(join(f.moonHome,path));if(path.startsWith('bin/'))chmodSync(join(f.moonHome,path),0o755);
  }
  f.put(join(f.moonHome,'installed.json'),marker);
  f.put(join(f.moonHome,'lib/core/source.mbt'));
  f.put(join(f.moonHome,'lib/core/_build/native/release/build/shared-cache'),'unused cache');
  symlinkSync('source.mbt',join(f.moonHome,'lib/core/original-link'));
  const copy=join(f.repository,'copy'),result=copyNativePreparationTools(f.moonHome,copy,marker);
  assert(result.files.length>installationFiles.length);
  assert.equal(existsSync(join(copy,'lib/core/_build/native/release/build/shared-cache')),false);
  for(const path of installationFiles) {
    assert.equal(readFileSync(join(copy,path),'utf8'),'original');
    assert.notEqual(lstatSync(join(copy,path)).ino,lstatSync(join(f.moonHome,path)).ino);
  }
  assert.equal(readFileSync(join(copy,'lib/core/original-link'),'utf8'),'original');
  f.put(join(copy,'lib/core/source.mbt'),'lane-local change');
  assert.equal(readFileSync(join(f.moonHome,'lib/core/source.mbt'),'utf8'),'original');
  symlinkSync('/etc/hosts',join(f.moonHome,'outside'));
  assert.throws(()=>copyNativePreparationTools(f.moonHome,join(f.repository,'refused'),marker));
});

test('Native parallel preparation starts both independent owners and waits for failure closure without Ready',async t=>{
  const f=fixture(t),started=[],finished=[];let release;
  const held=new Promise(resolve=>{release=resolve;});
  const original=new Error('same original compiler failure');
  const operation=prepareNativeParallel(f,{copyTools:(from,to)=>({from,to}),startLane:async(lane,options)=>{
    started.push(lane);
    if(lane==='commands') {
      assert.notEqual(options.moonHome,f.moonHome);assert.equal(options.receiverMoonHome,f.moonHome);
      throw original;
    }
    assert.equal(options.moonHome,f.moonHome);await held;finished.push(lane);
    return {components:join(f.destination,'components')};
  }});
  assert.deepEqual(started,['commands','components']);
  let settled=false;operation.then(()=>{settled=true;},()=>{settled=true;});
  await new Promise(resolve=>setImmediate(resolve));assert.equal(settled,false);
  release();await assert.rejects(operation,error=>error===original);
  assert.deepEqual(finished,['components']);assert.equal(existsSync(join(f.destination,'preparation.json')),false);
  assert.equal(existsSync(join(f.destination,'command-tool-copy.json')),true);
});

test('Native parallel preparation keeps command profiles budgets original receipts and full component order',async t=>{
  const f=fixture(t),calls=[];
  const command=(repository,path,options)=>{
    assert.equal(repository,f.repository);assert.equal(options.preparation,null);
    if(options.compiledInput) {
      assert.equal(options.moonHome,f.moonHome);mkdirSync(path);
      writeFileSync(join(path,'received.json'),'received scope data');
      assert(options.seconds>0&&options.seconds<=1200);
    } else assert.equal(options.moonHome,'/isolated/tool');
    calls.push({kind:'command',path,options});
  };
  const commands=prepareNativeConstructionLane('commands',{...f,moonHome:'/isolated/tool',receiverMoonHome:f.moonHome},{
    bundle:command,resident:command,exportCommand:(_from,path,entry,context)=>{
      assert.equal(context.moon_home,'/isolated/tool');assert.equal(context.source,f.source);
      return {path:join(path,'command.json'),entry};
    },
  });
  assert.deepEqual(Object.keys(commands.entries),['native_runtime_bundle','native_remote_resident_site']);
  assert.equal(calls[0].options.seconds,900);assert.equal(calls[2].options.seconds,1200);
  calls.length=0;
  const components=prepareNativeConstructionLane('components',f,{
    libraries:(_repository,path,options)=>{calls.push('libraries');assert.equal(options.seconds,900);assert.equal(options.preparation,null);},
    http:(_repository,path,options)=>{calls.push('http');assert.equal(options.seconds,900);assert.equal(options.tlsJobs,2);
      assert.equal(options.tlsArchive,join(f.destination,'components/openssl-original.tar.gz'));return '/original/http/receipt';},
    portable:(_repository,path)=>{calls.push('portable');assert.equal(path,join(f.destination,'portable-runtime.json'));},
  });
  assert.deepEqual(calls,['libraries','http','portable']);
  const merged=await prepareNativeParallel(f,{copyTools:()=>({}),startLane:async lane=>lane==='commands'?commands:components});
  assert.deepEqual(merged,{...commands,...components});
  assert.equal(existsSync(join(f.destination,'preparation.json')),false,'Only the CLI complete owner publishes Ready');
});
