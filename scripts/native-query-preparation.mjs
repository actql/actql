// Same-job default Native Query software only. Moon still owns discovery,
// incremental freshness, its output lock and each original test execution.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {existsSync, lstatSync, mkdirSync, readFileSync, readdirSync, readlinkSync, realpathSync, writeFileSync} from 'node:fs';
import {delimiter, dirname, isAbsolute, join, sep} from 'node:path';
import {copyNativePreparationTools} from './native-preparation-originals.mjs';
import {installationFiles} from './moonbit-installation.mjs';
import {originalDescriptor, verifyOriginal} from './native-preparation-originals.mjs';

export const nativeQueryPackages=Object.freeze(['src/query_integration','src/native_values_integration']);
const command=['test',...nativeQueryPackages,'--target','native'];
const compilerEnvironment=env=>Object.fromEntries(Object.entries(env).filter(([key])=>
  /^MOON/u.test(key)&&key!=='MOON_HOME'||['CC','CXX','AR','CFLAGS','CXXFLAGS','CPPFLAGS','LDFLAGS',
    'CPATH','C_INCLUDE_PATH','CPLUS_INCLUDE_PATH','LIBRARY_PATH','SDKROOT','MACOSX_DEPLOYMENT_TARGET',
    'LD_PRELOAD','DYLD_INSERT_LIBRARIES'].includes(key)).sort());
const run=(repository,env,tool,args)=>execFileSync(tool,args,
  {cwd:repository,env,encoding:'utf8',timeout:60000,maxBuffer:16*1024**2}).trim();
function files(root,accept=()=>true) {
  return readdirSync(root,{withFileTypes:true}).sort((a,b)=>a.name.localeCompare(b.name)).flatMap(item=>{
    const path=join(root,item.name);
    if(item.isDirectory())return files(path,accept);
    assert(item.isFile(),'Query software must not contain an output alias');
    return accept(path)?[path]:[];
  });
}
const softwareFiles=root=>files(root,path=>/\.(?:exe|mbt|c|o|a|core|mi)$/u.test(path)||
  /\/__(?:internal|whitebox|blackbox)_test_info\.json$/u.test(path));
function describe(paths) {
  return paths.map(path=>{
    const selected=realpathSync(path),stat=lstatSync(selected);
    return {selectedPath:path,...(stat.size===0?{path:selected,bytes:0}:originalDescriptor(selected)),mode:stat.mode};
  });
}
function verify(paths,records) {
  assert.deepEqual(records.map(x=>x.selectedPath),paths,'Query input/output inventory changed');
  for(const item of records) {
    assert.equal(realpathSync(item.selectedPath),item.path,'Query input/output target changed');
    assert.equal(lstatSync(item.path).mode,item.mode,'Query input/output mode changed');
    if(item.bytes===0)assert.equal(lstatSync(item.path).size,0);
    else verifyOriginal(item);
  }
}
function selection(repository,env,jobs) {
  assert(jobs===undefined||jobs===1,'Query construction requires one selected job');
  const selectedCommand=jobs===undefined?command:[...command,'-j','1'];
  repository=realpathSync(repository);
  const git=args=>run(repository,env,'git',args);
  assert.equal(git(['status','--porcelain']),'','Query preparation requires unchanged clean source');
  const source=git(['rev-parse','HEAD']);assert.match(source,/^[a-f0-9]{40}$/u);
  const home=realpathSync(env.MOON_HOME);
  const tracked=git(['ls-files','-z']).split('\0').filter(Boolean).map(path=>join(repository,path));
  const sourceAliases=[];
  const paths=tracked.flatMap(path=>{
    const target=realpathSync(path);
    if(!lstatSync(target).isDirectory())return [path];
    assert(lstatSync(path).isSymbolicLink(),'Unrecognized tracked source directory: '+path);
    assert(target.startsWith(repository+sep),'Tracked directory alias leaves the original source: '+path);
    // Retain this alias as link DATA, not as a regular-file descriptor. Its
    // target leaves already belong to the same Git inventory below; never
    // recurse through aliases or silently omit an original source input.
    const members=tracked.filter(member=>member.startsWith(target+sep)&&!lstatSync(realpathSync(member)).isDirectory());
    assert(members.length>0,'Tracked directory alias requires original tracked target files: '+path);
    sourceAliases.push({path,link:readlinkSync(path),target,members});
    return [];
  });
  const tools=['cc','c++','ar','bash','uname',...(process.platform==='darwin'?['xcrun','brew']:[])];
  const resolved=tools.map(name=>{
    // The original Query linker resolves these same system tools through PATH.
    // Missing optional brew retains its existing fallback search.
    try{return [name,realpathSync(run(repository,env,'/bin/sh',['-c','command -v "$1"','query-tool',name]))];}
    catch(error){if(name==='brew')return [name,null];throw error;}
  });
  const sdk=process.platform==='darwin'?run(repository,env,'xcrun',['--show-sdk-path']):null;
  const overrides=['CC','CXX','AR','MOON_CC'].filter(name=>env[name]!==undefined).map(name=>
    [name,realpathSync(run(repository,env,'/bin/sh',['-c','command -v "$1"','query-tool',env[name]]))]);
  let openssl=null;
  if(process.platform==='darwin') {
    // Same prefix/fallback and two link libraries as native-cxx-link-driver.sh.
    if(resolved.find(([name])=>name==='brew')?.[1]) {
      try{openssl=run(repository,env,'brew',['--prefix','openssl@3'])||null;}catch{/* Existing driver fallback. */}
    }
    openssl??=['/opt/homebrew/opt/openssl@3','/usr/local/opt/openssl@3']
      .find(path=>existsSync(join(path,'include/openssl')))??null;
  }
  const installation=describe([...installationFiles,'installed.json'].map(path=>join(home,path)))
    .map(({bytes,sha256,mode},index)=>({file:[...installationFiles,'installed.json'][index],bytes,sha256,mode}));
  return {identity:{repository,source,platform:process.platform,arch:process.arch,installation,sourceAliases,
    environment:compilerEnvironment(env),tools:resolved,overrides,sdk,openssl,command:selectedCommand},
    paths:[...new Set([...paths,...resolved.flatMap(([,path])=>path===null?[]:[path]),
      ...overrides.map(([,path])=>path),...(openssl===null?[]:[...files(join(openssl,'include/openssl')),
        join(openssl,'lib/libssl.dylib'),join(openssl,'lib/libcrypto.dylib')])])].sort()};
}

export function prepareNativeQuerySoftware(repository,destination,{env=process.env,moonHome=env.MOON_HOME,jobs,execute=execFileSync}={}) {
  env={...env,MOON_HOME:moonHome};
  repository=realpathSync(repository);destination=realpathSync(destination);
  const timings=[];let source=null;
  function observe(phase,operation) {
    const started=performance.now(),startedEpochMs=Date.now();let succeeded=false;
    try {const value=operation();succeeded=true;return value;}
    finally {
      const row={scope:'native-query-preparation',source,target:process.platform+'-'+process.arch,
        phase,startedEpochMs,endedEpochMs:Date.now(),
        milliseconds:Math.round(performance.now()-started),succeeded};
      timings.push(row);
      // Diagnostics cannot replace the original result/error or overwrite an
      // earlier preparation's evidence. Failed construction never publishes Ready.
      try {writeFileSync(join(destination,`phase-query-${timings.length}.timing.json`),
        JSON.stringify(row)+'\n',{flag:'wx',mode:0o600});}
      catch {try {console.error('Native Query preparation timing diagnostic unavailable');} catch {/* Observer only. */}}
    }
  }
  const {selected,inputs}=observe('input-admission',()=>{
    const selected=selection(repository,env,jobs);
    source=selected.identity.source;
    return {selected,inputs:describe(selected.paths)};
  });
  const {home,target,copy}=observe('tool-copy',()=>{
    const directory=join(destination,'query-software'),home=join(directory,'tool'),target=join(directory,'target');
    mkdirSync(directory,{mode:0o700});mkdirSync(target,{mode:0o700});
    const copy=copyNativePreparationTools(env.MOON_HOME,home,JSON.stringify({
      pin:JSON.parse(readFileSync(join(repository,'toolchain.json'))),platform:process.platform+'-'+process.arch}));
    return {home,target,copy};
  });
  const environment={...env,MOON_HOME:home,PATH:join(home,'bin')+delimiter+(env.PATH??'')};
  // Runtime prerequisites are deliberately absent here. This command only
  // constructs the complete two-package driver; it cannot execute any case.
  const args=[...selected.identity.command,'--target-dir',target,'--build-only'];
  const remaining=env.ACTQL_NATIVE_CI_DEADLINE===undefined?3600000:
    Math.min(3600000,Number(env.ACTQL_NATIVE_CI_DEADLINE)-Date.now());
  assert(Number.isSafeInteger(remaining)&&remaining>0,'Original Native job budget exhausted');
  observe('build-only',()=>execute(join(home,'bin/moon'),args,
    {cwd:repository,env:environment,stdio:'inherit',timeout:remaining}));
  observe('input-correspondence',()=>{
    assert.deepEqual(selection(repository,env,jobs),selected,'Query build inputs changed during preparation');
    verify(selected.paths,inputs);
  });
  const body=observe('output-retention',()=>{
    const outputs=softwareFiles(target);assert(outputs.some(path=>path.endsWith('.whitebox_test.exe')),
      'Query preparation must contain a real test executable');
    // Original source/tool copies and immutable generated code are retained at
    // their actual paths, never transported with a runtime fixture or Store.
    const toolPaths=copy.files.flatMap(item=>[item.from,item.to]).sort();
    return {identity:selected.identity,inputs,home,target,
      tools:describe(toolPaths),core:describe(softwareFiles(join(home,'lib/core/_build'))),
      outputs:describe(outputs)};
  });
  const receipt=join(destination,'query-software.json');
  writeFileSync(receipt,JSON.stringify({...body,timings})+'\n',{flag:'wx',mode:0o600});
  return receipt;
}

export function preparedNativeQuerySoftware(repository,env=process.env) {
  const path=env.ACTQL_TEST_NATIVE_QUERY_PREPARATION;
  if(path===undefined)return undefined;
  assert(typeof path==='string'&&isAbsolute(path)&&realpathSync(path)===path);
  const body=JSON.parse(readFileSync(path,'utf8'));
  assert.equal(body.home,join(dirname(path),'query-software/tool'));
  assert.equal(body.target,join(dirname(path),'query-software/target'));
  for(const directory of [body.home,body.target])assert.equal(realpathSync(directory),directory);
  const check=()=>{
    const jobs=env.ACTQL_TEST_NATIVE_QUERY_PREPARATION_JOBS;
    assert(jobs===undefined||jobs==='1','Invalid Query preparation construction mode');
    const selected=selection(repository,env,jobs===undefined?undefined:1);
    assert.deepEqual(selected.identity,body.identity,'Foreign Query source/toolchain/compiler settings');
    verify(selected.paths,body.inputs);
    verify(body.tools.map(item=>item.selectedPath),body.tools);
    verify(softwareFiles(join(body.home,'lib/core/_build')),body.core);
    verify(softwareFiles(body.target),body.outputs);
  };
  check();
  return {moon:join(body.home,'bin/moon'),targetDirectory:body.target,
    environment:{...env,MOON_HOME:body.home,PATH:join(body.home,'bin')+delimiter+(env.PATH??'')},verify:check};
}
