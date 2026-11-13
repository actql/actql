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

test('Native Linux command lane forwards an absent SDK and retains its actual entry budget',t=>{
  const f={...fixture(t),target:'linux-x64',selection:'bundle',sdk:null};let checked=0;
  prepareNativeConstructionLane('commands',f,{
    bundle:(_repository,path,options)=>{
      if(options.compiledInput) {mkdirSync(path);writeFileSync(join(path,'received.json'),'received Linux DATA');}
      else assert.equal(options.seconds,900);
    },
    exportCommand:(_directory,path,entry,context)=>{
      checked++;assert.equal(context.target,'linux-x64');assert.equal(context.sdk,undefined);
      return {path:join(path,'command.json'),entry};
    },
  });
  assert.equal(checked,1);
});

test('Native parallel preparation refuses a shared tool-output alias before copying or starting either lane',async t=>{
  const f=fixture(t),donor=join(f.repository,'protected-donor');mkdirSync(donor);
  symlinkSync(donor,join(f.repository,'.toolchains'),'dir');let touched=false;
  await assert.rejects(()=>prepareNativeParallel(f,{
    copyTools:()=>{touched=true;return {};},startLane:async()=>{touched=true;return {};},
  }));
  assert.equal(touched,false);assert.equal(existsSync(join(f.destination,'command-tool-copy.json')),false);
});

test('three-lane Darwin preparation joins the failed Query and both original owners before refusing Ready',async t=>{
  const f={...fixture(t),lanes:3},started=[],copies=[],finished=[];
  let releaseCommands,releaseComponents;
  const commands=new Promise(resolve=>{releaseCommands=resolve;});
  const components=new Promise(resolve=>{releaseComponents=resolve;});
  const original=new Error('original Query compiler failure');
  const operation=prepareNativeParallel(f,{
    copyTools:(from,to)=>{copies.push([from,to]);return {from,to};},
    startLane:async(lane,options)=>{
      started.push(lane);
      assert.equal(copies.length,2,'both checked snapshots precede any mutable Core build');
      if(lane==='query') {
        assert.equal(options.moonHome,copies[1][1]);
        assert.notEqual(options.moonHome,f.moonHome);
        assert.notEqual(options.moonHome,copies[0][1]);
        throw original;
      }
      await (lane==='commands'?commands:components);finished.push(lane);
      return lane==='commands'?{entries:{original:'command'}}:{components:'original component'};
    },
  });
  assert.deepEqual(started,['commands','components','query']);
  let settled=false;operation.then(()=>{settled=true;},()=>{settled=true;});
  await new Promise(resolve=>setImmediate(resolve));assert.equal(settled,false);
  releaseComponents();await new Promise(resolve=>setImmediate(resolve));assert.equal(settled,false);
  releaseCommands();await assert.rejects(operation,error=>error===original);
  assert.deepEqual(finished,['components','commands']);
  assert.equal(existsSync(join(f.destination,'preparation.json')),false);
});

test('three-lane Darwin preparation joins started owners even when a launch throws synchronously',async t=>{
  const f={...fixture(t),lanes:3},started=[];let release;
  const held=new Promise(resolve=>{release=resolve;});
  const original=new Error('same synchronous launch error');
  const operation=prepareNativeParallel(f,{copyTools:()=>({}),startLane:lane=>{
    started.push(lane);
    if(lane==='components')throw original;
    return held.then(()=>lane==='query'?{queryReceipt:'same receipt'}:{entries:{same:'command'}});
  }});
  assert.deepEqual(started,['commands','components','query']);
  let settled=false;operation.then(()=>{settled=true;},()=>{settled=true;});
  await new Promise(resolve=>setImmediate(resolve));assert.equal(settled,false);
  release();await assert.rejects(operation,error=>error===original);
  assert.equal(existsSync(join(f.destination,'preparation.json')),false);
});

test('three-lane Query calls the unchanged constructor once with its selected tool and original environment',async t=>{
  const f={...fixture(t),lanes:3},calls=[];
  const receipt=join(f.destination,'query-software.json');
  const query=prepareNativeConstructionLane('query',f,{query:(...args)=>{calls.push(args);return receipt;}});
  assert.deepEqual(query,{queryReceipt:receipt});assert.equal(calls.length,1);
  assert.deepEqual(calls[0],[f.repository,f.destination,{env:{...process.env,MOON_HOME:f.moonHome}}]);
  const commands={entries:{same:'original command'}},components={components:'same components',
    httpReceipt:'same HTTP',portableReceipt:'same portable'};
  const result=await prepareNativeParallel(f,{copyTools:()=>({}),startLane:async lane=>
    lane==='commands'?commands:lane==='components'?components:query});
  assert.deepEqual(result,{...commands,...components,...query});
  assert.equal(existsSync(join(f.destination,'preparation.json')),false,
    'only the enclosing CLI publishes the complete index and environment');
});

test('three-lane preparation refuses unsupported selections before copying or starting work',async t=>{
  for(const change of [{target:'linux-x64'},{selection:'bundle'},{selection:'resident'}]) {
    const f={...fixture(t),lanes:3,...change};let touched=false;
    const ports={copyTools:()=>{touched=true;},startLane:()=>{touched=true;}};
    await assert.rejects(prepareNativeParallel(f,ports));assert.equal(touched,false);
    assert.throws(()=>prepareNativeConstructionLane('query',f,{query:()=>{touched=true;}}));
    assert.equal(touched,false);assert.equal(existsSync(join(f.repository,'.toolchains')),false);
  }
  const f=fixture(t);
  assert.throws(()=>prepareNativeConstructionLane('query',f,{query:()=>assert.fail('not selected')}));
});

test('three-lane preparation retains a failed Query tool snapshot without starting a mutable lane',async t=>{
  const f={...fixture(t),lanes:3};let copies=0,started=0;
  const original=new Error('original Query tool copy failed');
  await assert.rejects(prepareNativeParallel(f,{copyTools:()=>{
    if(++copies===2)throw original;
    return {};
  },startLane:()=>{started++;}}),error=>error===original);
  assert.equal(copies,2);assert.equal(started,0);
  assert.equal(existsSync(join(f.destination,'command-tool-copy.json')),true);
  assert.equal(existsSync(join(f.destination,'preparation.json')),false);
});

test('three-lane Query refuses a missing constructor receipt without substituting another build',t=>{
  const f={...fixture(t),lanes:3};let calls=0;
  assert.throws(()=>prepareNativeConstructionLane('query',f,{query:()=>{calls++;}}),
    /Missing original Query preparation receipt/);
  assert.equal(calls,1);assert.equal(existsSync(join(f.destination,'preparation.json')),false);
});
