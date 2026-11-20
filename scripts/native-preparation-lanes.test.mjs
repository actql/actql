import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,rmSync,symlinkSync,lstatSync,existsSync,chmodSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {copyNativePreparationTools,prepareNativeConstructionLane,prepareNativeParallel,nativePreparationConsumerJobs} from './native-preparation-lanes.mjs';
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

test('Native Linux parallel preparation keeps command profiles budgets original receipts and full component order',async t=>{
  const f={...fixture(t),target:'linux-x64'},calls=[];
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
      assert.equal(options.tlsArchive,process.env.ACTQL_TEST_NATIVE_OPENSSL_SOURCE_ARCHIVE);return '/original/http/receipt';},
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

test('Native parallel preparation joins both original owners after either synchronous launch failure',async t=>{
  for(const failed of ['commands','components']) {
    const f=fixture(t),started=[],finished=[];let release;
    const held=new Promise(resolve=>{release=resolve;});
    const original=new Error('same '+failed+' launch failure');
    const operation=prepareNativeParallel(f,{copyTools:()=>({}),startLane:lane=>{
      started.push(lane);
      if(lane===failed)throw original;
      return held.then(()=>{finished.push(lane);return lane==='commands'?{entries:{same:'command'}}
        :{components:'same component'};});
    }});
    assert.deepEqual(started,['commands','components']);
    let settled=false;operation.then(()=>{settled=true;},()=>{settled=true;});
    await new Promise(resolve=>setImmediate(resolve));assert.equal(settled,false);
    release();await assert.rejects(operation,error=>error===original);
    assert.deepEqual(finished,[failed==='commands'?'components':'commands']);
    assert.equal(existsSync(join(f.destination,'preparation.json')),false);
    assert.equal(existsSync(join(f.destination,'query-tool-copy.json')),false);
  }
});

test('Darwin preparation assigns portable and bounded Query work to the same two dependency owners',t=>{
  const f=fixture(t),calls=[];
  const command=(repository,path,options)=>{
    assert.equal(repository,f.repository);
    calls.push(options.compiledInput?'received':'compiled');
    if(options.compiledInput) {mkdirSync(path);writeFileSync(join(path,'received.json'),'original command');}
  };
  const commands=prepareNativeConstructionLane('commands',
    {...f,moonHome:'/isolated/command-tool',receiverMoonHome:f.moonHome},{
      bundle:command,resident:command,exportCommand:()=>({original:true}),
      portable:(repository,path,options)=>{
        calls.push('portable');assert.equal(repository,f.repository);
        assert.equal(path,join(f.destination,'portable-runtime.json'));
        assert.equal(options.env.MOON_HOME,f.moonHome);
        assert.equal(options.jobs,1);
      },
    });
  assert.deepEqual(calls,['compiled','received','compiled','received','portable']);
  assert.equal(commands.portableReceipt,join(f.destination,'portable-runtime.json'));
  calls.length=0;
  const components=prepareNativeConstructionLane('components',f,{
    libraries:()=>calls.push('libraries'),http:()=>{calls.push('http');return '/original/http';},
    portable:()=>assert.fail('Portable work belongs to the original command owner'),
    query:(repository,path,options)=>{
      calls.push('query');assert.equal(repository,f.repository);assert.equal(path,f.destination);
      assert.equal(options.moonHome,f.moonHome);assert.equal(options.jobs,2);
      return join(path,'query-software.json');
    },
  });
  assert.deepEqual(calls,['libraries','http','query']);
  assert.equal(components.queryReceipt,join(f.destination,'query-software.json'));
  assert.equal(components.portableReceipt,undefined);
  const selected={...f,lanes:2,queryReceipt:components.queryReceipt,portableReceipt:commands.portableReceipt};
  assert.deepEqual(nativePreparationConsumerJobs(selected),{
    ACTQL_TEST_NATIVE_QUERY_PREPARATION_JOBS:'2',
    ACTQL_TEST_NATIVE_PORTABLE_PREPARATION_JOBS:'1',
  });
  for(const changed of [{target:'linux-x64'},{lanes:1},{selection:'bundle'}])
    assert.deepEqual(nativePreparationConsumerJobs({...selected,...changed}),{});
  for(const changed of [{queryReceipt:undefined},{portableReceipt:undefined},{queryReceipt:'/foreign/query-software.json'}])
    assert.throws(()=>nativePreparationConsumerJobs({...selected,...changed}));
});

test('Darwin Query or portable refusal still joins the other actual construction owner without Ready',async t=>{
  for(const failed of ['query','portable']) {
    const f=fixture(t),finished=[];let release;
    const held=new Promise(resolve=>{release=resolve;});
    const original=new Error('original '+failed+' preparation refusal');
    const command=(_repository,path,options)=>{
      if(options.compiledInput) {mkdirSync(path);writeFileSync(join(path,'received.json'),'original command');}
    };
    const ports={bundle:command,resident:command,exportCommand:()=>({original:true}),
      libraries:()=>{},http:()=>'/original/http',
      portable:()=>{if(failed==='portable')throw original;finished.push('portable');},
      query:(_repository,path)=>{if(failed==='query')throw original;finished.push('query');
        return join(path,'query-software.json');},
    };
    const operation=prepareNativeParallel(f,{copyTools:()=>({}),startLane:async(lane,options)=>{
      if(lane===(failed==='query'?'commands':'components'))await held;
      return prepareNativeConstructionLane(lane,options,ports);
    }});
    let settled=false;operation.then(()=>{settled=true;},()=>{settled=true;});
    await new Promise(resolve=>setImmediate(resolve));assert.equal(settled,false);
    release();await assert.rejects(operation,error=>error===original);
    assert.deepEqual(finished,[failed==='query'?'portable':'query']);
    assert.equal(existsSync(join(f.destination,'preparation.json')),false);
  }
});

test('Darwin component dependencies refuse before Query and cannot substitute a foreign Query receipt',t=>{
  for(const refusal of ['libraries','http','foreign']) {
    const f=fixture(t),calls=[],original=new Error('original '+refusal+' refusal');
    const execute=name=>{calls.push(name);if(refusal===name)throw original;};
    assert.throws(()=>prepareNativeConstructionLane('components',f,{
      libraries:()=>execute('libraries'),http:()=>execute('http'),
      query:()=>{calls.push('query');return '/foreign/query-software.json';},
    }),error=>refusal==='foreign'?error.code==='ERR_ASSERTION':error===original);
    assert.deepEqual(calls,refusal==='libraries'?['libraries']:refusal==='http'?['libraries','http']
      :['libraries','http','query']);
    assert.equal(existsSync(join(f.destination,'preparation.json')),false);
  }
});
