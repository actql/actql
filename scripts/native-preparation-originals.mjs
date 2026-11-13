// Retained public build inputs from one exact source/target, never Host/Read or
// capacity authority. A refusal never rebuilds or substitutes another artifact.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {chmodSync, constants, copyFileSync, lstatSync, mkdirSync, readFileSync, realpathSync, writeFileSync} from 'node:fs';
import {basename, dirname, isAbsolute, join, relative, resolve, sep} from 'node:path';
import {fileURLToPath} from 'node:url';

function data(path, item) {
  assert.equal(typeof path, 'string'); assert(isAbsolute(path));
  const before=lstatSync(path,{bigint:true});
  assert(before.isFile() && !before.isSymbolicLink());
  assert(before.size>0n && before.size<=512n*1024n*1024n);
  const bytes=readFileSync(path),after=lstatSync(path,{bigint:true});
  for(const key of ['dev','ino','size','mode','mtimeNs','ctimeNs'])assert.equal(after[key],before[key]);
  if(item!==undefined) {
    assert(Number.isSafeInteger(item.bytes) && item.bytes>0);
    assert.match(item.sha256,/^[0-9a-f]{64}$/u);
    assert.equal(bytes.length,item.bytes,'Original preparation input byte count changed');
    assert.equal(createHash('sha256').update(bytes).digest('hex'),item.sha256,
      'Original preparation input digest changed');
    for(const key of ['dev','ino','mode'])if(item[key]!==undefined) {
      if(typeof item[key]==='string')assert.match(item[key],/^(?:0|[1-9][0-9]{0,19})$/u);
      else assert(Number.isSafeInteger(item[key]) && item[key]>=0);
      const expected=BigInt(item[key]);assert(expected<=0xffffffffffffffffn);
      assert.equal(before[key],expected);
    }
  }
  return bytes;
}
export function originalDescriptor(path) {
  const bytes=data(path);
  return {path,bytes:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex')};
}
export function verifyOriginal(item) { data(item.path,item); }
function json(path,item) {
  const bytes=data(path,item);assert(bytes.length<=32*1024*1024);
  return JSON.parse(bytes.toString('utf8'));
}
function inventory(value) {
  assert(value && typeof value==='object');
  if(Array.isArray(value)) {
    assert(value.length>0);for(const item of value)verifyOriginal(item);
  } else {
    assert(Object.keys(value).length>0);
    for(const [path,item] of Object.entries(value)) {
      if(item.resolved_path!==undefined)assert.equal(realpathSync(path),item.resolved_path);
      verifyOriginal({path:item.resolved_path??path,bytes:item.bytes,sha256:item.sha256});
    }
  }
}
function index(root,selected) {
  root=realpathSync(root);
  const record=json(join(root,'preparation.json'));
  assert.deepEqual(Object.keys(record).sort(),
    ['clang','components','entries','http','moon_home','sdk','source','target']);
  assert(Object.keys(record.entries).length>0);
  for(const entry of Object.keys(record.entries))assert(['native_runtime_bundle','native_remote_resident_site'].includes(entry));
  for(const key of ['source','target','clang'])assert.equal(record[key],selected[key]);
  assert.equal(record.sdk,selected.sdk??null);
  if(selected.moon_home!==undefined)assert.equal(record.moon_home,selected.moon_home);
  return {root,record};
}
export function verifyNativeHttpPreparation(path,selected,item) {
  const directory=realpathSync(join(path,'..')),body=json(path,item);
  for(const key of ['source','target'])assert.equal(body[key],selected[key]);
  const minimum=selected.target==='darwin-arm64'?'11.0':null;
  assert.equal(body.minimumMacOS,minimum);
  assert.equal(body.loaded,0);assert.equal(body.initialized,0);assert.equal(body.installed_supplier,false);
  inventory(body.inputs);
  assert.equal(body.tls.path,join(directory,'owned-tls/build.json'));
  assert.equal(body.component.path,join(directory,'component/build.json'));
  const tls=json(body.tls.path,body.tls),component=json(body.component.path,body.component);
  const recipe=json(fileURLToPath(new URL('./native-http-component-source.json',import.meta.url)));
  for(const receipt of [tls,component]) {
    assert.equal(receipt.source,selected.source);assert.equal(receipt.target,selected.target);
    assert.equal(receipt.minimumMacOS,minimum);assert.equal(receipt.loaded,0);
    inventory(receipt.inputs);
  }
  assert.equal(tls.stage,join(directory,'owned-tls/stage'));
  assert.deepEqual(tls.upstream,recipe.ownedOpenSSLSource);
  assert.equal(tls.compiledLibraries,2);assert.equal(tls.installedSupplier,false);
  inventory(tls.files);
  assert.deepEqual(component.upstream,recipe.upstream);
  assert.equal(component.initialized,0);assert.equal(component.installed_supplier,false);
  for(const key of ['path','bytes','sha256'])assert.equal(component.ownedOpenSSLReceipt[key],body.tls[key]);
  assert.equal(component.library.path,join(directory,'component/bundle',
    selected.target==='darwin-arm64'?'libcurl.4.dylib':'libcurl.so.4'));
  verifyOriginal(component.library);
  return body.component.path;
}
export function preparedNativeHttpReceipt(root,selected) {
  const {root:canonical,record}=index(root,selected);
  assert(record.http,'Complete original HTTP preparation is required for Resident');
  const path=join(canonical,'http/preparation.json');assert.equal(record.http.path,path);
  return verifyNativeHttpPreparation(path,selected,record.http);
}
export function preparedNativeCommand(root,entry,selected) {
  const {root:canonical,record}=index(root,selected);
  assert(['native_runtime_bundle','native_remote_resident_site'].includes(entry));
  const directory=join(canonical,entry),item=record.entries[entry];assert(item);
  if(entry==='native_remote_resident_site')assert(record.http,'Resident requires complete original HTTP preparation');
  assert.equal(item.path,join(directory,'build.json'));
  const body=json(item.path,item);
  assert.equal(body.source,selected.source);assert.equal(body.target,selected.target);
  assert.equal(body.entry,'src/cmd/'+entry);assert.equal(body.plan_only,false);
  assert.equal(body.moon_build_exit,0);assert.equal(body.providers,1);
  assert.equal(body.executable.path,join(directory,'emission/native/release/build/cmd',entry,entry+'.exe'));
  inventory(json(join(directory,'inputs.json')));
  verifyOriginal(body.executable);
  return directory;
}
export function preparedNativeComponents(root,selected) {
  const {root:canonical,record}=index(root,selected),directory=join(canonical,'components');
  assert.equal(record.components.path,join(directory,'bundle-components.json'));
  const body=json(record.components.path,record.components);
  assert.equal(body.source,selected.source);assert.equal(body.target,selected.target);
  assert.equal(body.providers,0);assert.equal(body.loaded,false);assert.equal(body.initialized,false);
  for(const name of ['sqlite','crypto']) {
    const path=join(directory,name,name==='sqlite'?'process-producer.json':'producer.json');
    assert.equal(body.producer_receipts[name].path,path);
    const producer=json(path,body.producer_receipts[name]);
    assert.equal(producer.source??producer.source_sha,selected.source);
    inventory(producer.inputs);
    if(producer.compiled_inputs!==undefined)inventory(producer.compiled_inputs);
    for(const aliases of [producer.compiler_tool_aliases,
      producer.static_source?.compiler_tool_aliases].filter(value=>value!==undefined)) {
      for(const [alias,item] of Object.entries(aliases)) {
        assert.equal(realpathSync(alias),item.resolved_path);
        const current=lstatSync(alias,{bigint:true});
        for(const [field,original] of [['dev','st_dev'],['ino','st_ino'],
          ['mtimeNs','st_mtime_ns'],['ctimeNs','st_ctime_ns']]) {
          assert.equal(typeof item[original],'string');
          assert.equal(current[field],BigInt(item[original]));
        }
      }
    }
    assert.equal(body[name].path,join(directory,name,
      'libactql_'+name+'_component'+(selected.target==='darwin-arm64'?'.dylib':'.so')));
    verifyOriginal(body[name]);
    assert.equal(body[name].bytes,producer.library.bytes);
    assert.equal(body[name].sha256,producer.library.sha256);
  }
  return directory;
}

const commandEntries=['native_runtime_bundle','native_remote_resident_site'];
const digest=bytes=>({bytes:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex')});
const within=(path,root)=>path===root||path.startsWith(root+sep);
function stableCommandInput(path,roots) {
  assert(typeof path==='string'&&isAbsolute(path)&&resolve(path)===path);
  if(path===roots.clang)return {role:'clang'};
  const kind=['directory','repository','moon_home','sdk'].filter(key=>roots[key]!==null&&within(path,roots[key]))
    .sort((a,b)=>roots[b].length-roots[a].length)[0];
  const name=kind?relative(roots[kind],path).split(sep).join('/'):basename(path);
  if(kind==='directory')return {kind,name};
  if(kind==='repository'&&(name==='toolchain.json'||name==='moon.mod'||
    name==='scripts/produce-native-remote-scoped-runtime.py'||
    /^src\/cmd\/(?:native_runtime_bundle|native_remote_resident_site)\/initial_control_recipe(?:\.linux-x64)?\.json$/u.test(name)||
    /^src\/.+\.(?:mbt|pkg|c|h|inc)$/u.test(name)||
    /^packages\/python-local-runtime\/native\/pre-root\/.+\.(?:mi|core|c|h|inc|json|py|patch)$/u.test(name)))return {kind,name};
  if(kind==='moon_home'&&(['installed.json','bin/moon','bin/moonc','lib/libmoonbitrun.o','lib/libbacktrace.a',
    'lib/moonbit_simdutf.o','lib/simdutf.o'].includes(name)||
    /^(?:include|lib\/runtime|lib\/core\/_build\/native\/release\/bundle)\/.+\.(?:mi|core|c|h|inc|json|py|patch)$/u.test(name)))return {kind,name};
  if(kind==='sdk'&&name==='SDKSettings.json')return {kind,name};
  if(!kind) {
    if(/^python3(?:\.\d+)?$/u.test(name))return {role:'python'};
    if(/^(?:[a-z0-9_]+-)*ar$/u.test(name))return {role:'ar'};
    if(name==='libtool')return {role:'libtool'};
  }
  assert.fail('Unknown stable compiler input');
}
function commandSystemTool(role,target) {
  assert(['python','ar','libtool'].includes(role));
  if(target==='darwin-arm64'&&role!=='python')return realpathSync('/Library/Developer/CommandLineTools/usr/bin/'+role);
  const name=role==='python'?'python3':role;
  return realpathSync(execFileSync('/bin/sh',['-c','command -v '+name],{encoding:'utf8',timeout:5000}).trim());
}
function commandContext(entry,selected) {
  assert(commandEntries.includes(entry),'Closed compiled command entry required');
  assert.match(selected.source,/^[0-9a-f]{40}$/u);
  assert(['darwin-arm64','linux-x64'].includes(selected.target));
  return {repository:realpathSync(selected.repository),moon_home:realpathSync(selected.moon_home),
    clang:realpathSync(selected.clang),sdk:selected.sdk===undefined?null:realpathSync(selected.sdk)};
}
function commandBody(body,entry,selected,directory) {
  for(const key of ['source','target'])assert.equal(body[key],selected[key]);
  assert.equal(body.entry,'src/cmd/'+entry);assert.equal(body.plan_only,false);
  assert.equal(body.moon_build_exit,0);assert.equal(body.providers,1);assert.equal(body.core_modules,1);
  assert.equal(body.compiler_backend,'pinned ordinary C (MOONBIT_NEW_NATIVE=0)');
  assert.equal(body.compiler_profile,'ordinary Moon --release --strip');
  assert.equal(body.installed_supplier,false);assert.equal(body.normal_profile,null);
  assert.equal(body.runtime_cases,0);assert.equal(body.public_e2e,0);
  for(const key of ['commands_completed','completed_c_steps'])assert(Number.isSafeInteger(body[key])&&body[key]>0);
  assert.equal(body.executable.path,join(directory,'emission/native/release/build/cmd',entry,entry+'.exe'));
  assert.equal(body.generated_c.path,body.executable.path.slice(0,-4)+'.c');
}
function checkedCommandFiles(body,inputs,commands,read,directory) {
  assert(Array.isArray(inputs)&&inputs.length>0);assert(Array.isArray(commands));
  assert.equal(commands.length,body.commands_completed);
  assert.equal(new Set(inputs.map(x=>x.path)).size,inputs.length,'Duplicate original compiler input');
  const planItem=inputs.find(x=>x.path===join(directory,'cc-plan.json'));assert(planItem);
  const plan=JSON.parse(read(planItem).toString('utf8'));
  assert(Array.isArray(plan.steps)&&plan.steps.length===body.completed_c_steps);
  const outputs=[body.executable,body.generated_c];
  for(const item of plan.allocator_inputs) {
    const sourceInput=inputs.find(x=>x.path===item.path);
    if(sourceInput)assert.deepEqual(sourceInput,item);
    else {
      assert(isAbsolute(item.path)&&resolve(item.path)===item.path&&within(item.path,directory));
      read(item);outputs.push(item);
    }
  }
  for(const step of plan.steps) {
    assert(commands.some(x=>JSON.stringify(x)===JSON.stringify(step.selected)));
    assert(isAbsolute(step.receipt)&&resolve(step.receipt)===step.receipt&&within(step.receipt,directory));
    const receiptBytes=read({path:step.receipt});
    const receipt=JSON.parse(receiptBytes.toString('utf8'));
    assert.equal(receipt.exit,0);assert.deepEqual(receipt.selected,step.selected);
    outputs.push({path:step.receipt,...digest(receiptBytes)},receipt.output);
  }
  return outputs;
}

// An inert command image, not a prepared Host. Origin receipts retain their
// literal producer paths; only this bounded transport inventory is relocatable.
export function exportNativeCompiledCommand(directory,destination,entry,selected) {
  const roots={...commandContext(entry,selected),directory:realpathSync(directory)};
  const body=json(join(directory,'build.json')),inputs=json(join(directory,'inputs.json'));
  const commands=json(join(directory,'commands.json'));
  commandBody(body,entry,selected,roots.directory);
  for(const item of inputs) {
    const shape=stableCommandInput(item.path,roots);
    if(shape.role&&shape.role!=='clang')assert.equal(realpathSync(item.path),
      (selected.systemTool??commandSystemTool)(shape.role,selected.target));
    verifyOriginal(item);
  }
  const outputs=checkedCommandFiles(body,inputs,commands,item=>data(item.path,item.sha256===undefined?undefined:item),roots.directory);
  const members=new Map();
  for(const item of [...inputs.filter(x=>within(x.path,roots.directory)),...outputs]) {
    assert(isAbsolute(item.path)&&resolve(item.path)===item.path&&within(item.path,roots.directory));verifyOriginal(item);
    if(members.has(item.path))assert.deepEqual(members.get(item.path),item);
    else members.set(item.path,item);
  }
  const executable=lstatSync(body.executable.path);assert((executable.mode&0o111)!==0);
  mkdirSync(destination,{mode:0o700});mkdirSync(join(destination,'members'),{mode:0o700});
  const transfer=(from,file,item)=>{
    copyFileSync(from,join(destination,file),constants.COPYFILE_EXCL);
    return {file,...digest(data(join(destination,file),item))};
  };
  const record={kind:'native-compiled-command-input',source:selected.source,target:selected.target,entry,roots,
    receipt:transfer(join(directory,'build.json'),'origin-build.json'),
    inputs:transfer(join(directory,'inputs.json'),'origin-inputs.json'),
    commands:transfer(join(directory,'commands.json'),'origin-commands.json'),members:[]};
  for(const [index,item] of [...members.values()].entries()) {
    const file='members/'+String(index).padStart(6,'0');
    transfer(item.path,file,item);record.members.push({file,original:item});
  }
  for(const item of inputs)verifyOriginal(item);
  const path=join(destination,'command.json');writeFileSync(path,JSON.stringify(record)+'\n',{flag:'wx',mode:0o600});
  return originalDescriptor(path);
}

export function receiveNativeCompiledCommand(input,destination,entry,selected,{seconds=600}={}) {
  assert(Number.isSafeInteger(seconds)&&seconds>0&&seconds<=1800);
  const deadline=performance.now()+seconds*1000;
  const check=()=>assert(performance.now()<deadline,'Original compiled-input verification budget exhausted');
  const current=commandContext(entry,selected),record=json(input.path,input);
  assert.deepEqual(Object.keys(record).sort(),['commands','entry','inputs','kind','members','receipt','roots','source','target']);
  assert.equal(record.kind,'native-compiled-command-input');assert.equal(record.entry,entry);
  for(const key of ['source','target'])assert.equal(record[key],selected[key]);
  assert.deepEqual(Object.keys(record.roots).sort(),['clang','directory','moon_home','repository','sdk']);
  for(const path of Object.values(record.roots).filter(x=>x!==null))assert(isAbsolute(path)&&resolve(path)===path);
  const artifact=realpathSync(dirname(input.path));
  const readNamed=(item,name)=>{
    check();assert.equal(item.file,name);const bytes=data(join(artifact,name),item);check();return bytes;
  };
  const receiptBytes=readNamed(record.receipt,'origin-build.json');
  const body=JSON.parse(receiptBytes),inputs=JSON.parse(readNamed(record.inputs,'origin-inputs.json'));
  const commands=JSON.parse(readNamed(record.commands,'origin-commands.json'));
  commandBody(body,entry,selected,record.roots.directory);
  assert(Array.isArray(record.members));
  const members=new Map();
  for(const [index,item] of record.members.entries()) {
    check();
    assert.equal(item.file,'members/'+String(index).padStart(6,'0'));
    assert(isAbsolute(item.original.path)&&resolve(item.original.path)===item.original.path&&within(item.original.path,record.roots.directory));
    assert(!members.has(item.original.path));
    data(join(artifact,item.file),item.original);members.set(item.original.path,item);
  }
  const staticInputs=[];
  const read=item=>{
    check();const shape=stableCommandInput(item.path,record.roots);
    if(shape.kind==='directory') {
      const member=members.get(item.path);assert(member,'Missing original generated compiler input');
      if(item.sha256!==undefined)assert.deepEqual(member.original,item);
      return data(join(artifact,member.file),member.original);
    }
    const path=shape.role==='clang'?current.clang:shape.role
      ?(selected.systemTool??commandSystemTool)(shape.role,selected.target):join(current[shape.kind],shape.name);
    assert(isAbsolute(path)&&realpathSync(path)===path);
    staticInputs.push({path,bytes:item.bytes,sha256:item.sha256});
    return data(path,item);
  };
  for(const item of inputs)read(item);
  const outputs=checkedCommandFiles(body,inputs,commands,read,record.roots.directory);
  const expected=new Map();
  for(const item of [...inputs.filter(x=>within(x.path,record.roots.directory)),...outputs]) {
    if(expected.has(item.path))assert.deepEqual(expected.get(item.path),item,'Conflicting original compiler output');
    expected.set(item.path,item);
  }
  assert.equal(expected.size,members.size);
  for(const [path,item] of expected)assert.deepEqual(members.get(path)?.original,item);
  // Publication starts only after the complete selected source/tool/ABI and
  // successful original compiler closure has been checked. No old inode is used.
  check();mkdirSync(destination,{mode:0o700});
  const binary=join(destination,'received-command.exe');
  copyFileSync(join(artifact,members.get(body.executable.path).file),binary,constants.COPYFILE_EXCL);
  chmodSync(binary,0o700);data(binary,body.executable);
  for(const item of staticInputs)verifyOriginal(item);
  check();
  const stat=lstatSync(binary,{bigint:true});
  const binding={kind:'received-native-command',source:selected.source,target:selected.target,entry,
    originInput:{...input},executable:{...originalDescriptor(binary),
      dev:String(stat.dev),ino:String(stat.ino),mode:String(stat.mode)}};
  writeFileSync(join(destination,'received.json'),JSON.stringify(binding)+'\n',{flag:'wx',mode:0o600});
  return binary;
}
