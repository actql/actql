// Source-only byte/receipt controls. No fixture below is executed or loaded.
import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {lstatSync,mkdirSync,mkdtempSync,readFileSync,realpathSync,rmSync,writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {preparedNativeCommand,preparedNativeComponents,preparedNativeHttpReceipt} from './native-preparation-originals.mjs';

const fingerprint=bytes=>({bytes:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex')});
const descriptor=path=>({path,...fingerprint(readFileSync(path))});
function fixture(t) {
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
  const receipts={},body={source,target,providers:0,loaded:false,initialized:false,producer_receipts:{}};
  for(const name of ['sqlite','crypto']) {
    const directory=join(components,name);mkdirSync(directory);
    const library=join(directory,'libactql_'+name+'_component.dylib');writeFileSync(library,'Source-only '+name+' component');
    const path=join(directory,name==='sqlite'?'process-producer.json':'producer.json');
    const pin=fingerprint(readFileSync(header));
    receipts[name]={path,body:{source,inputs:{[header]:pin},compiled_inputs:{[header]:{resolved_path:header,...pin}},
      library:fingerprint(readFileSync(library))}};
    body[name]=descriptor(library);
  }
  const record={source,target,clang,sdk,moon_home:root,entries:{},components:{},http:null};
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

function httpPreparation(t) {
  const f=fixture(t),directory=join(f.root,'http');
  mkdirSync(join(directory,'owned-tls/stage'),{recursive:true});
  mkdirSync(join(directory,'component/bundle'),{recursive:true});
  const recipe=JSON.parse(readFileSync(new URL('./native-http-component-source.json',import.meta.url)));
  const pin=descriptor(f.header),library=join(directory,'component/bundle/libcurl.4.dylib');
  writeFileSync(library,'Source-only owned HTTP bytes; never loaded');
  const tlsPath=join(directory,'owned-tls/build.json'),componentPath=join(directory,'component/build.json');
  const tls={source:f.source,target:f.target,minimumMacOS:'11.0',loaded:0,inputs:[pin],
    stage:join(directory,'owned-tls/stage'),upstream:recipe.ownedOpenSSLSource,
    compiledLibraries:2,installedSupplier:false,files:[pin]};
  const identity=lstatSync(library);
  const component={source:f.source,target:f.target,minimumMacOS:'11.0',loaded:0,initialized:0,
    installed_supplier:false,inputs:[pin],upstream:recipe.upstream,library:{...descriptor(library),
      dev:identity.dev,ino:identity.ino,mode:identity.mode}};
  const body={source:f.source,target:f.target,minimumMacOS:'11.0',loaded:0,initialized:0,
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
  for(const key of ['dev','ino','mode'])f.component.library[key]=String(f.component.library[key]);
  f.publishHttp();
  assert.equal(preparedNativeHttpReceipt(f.root,f.selected),f.componentPath);
});
test('Resident prepared originals refuse unsafe numbers or noncanonical decimal identities',t=>{
  for(const identity of [2**60,'01','+1','1e3','-1','18446744073709551616']) {
    const f=httpPreparation(t);f.component.library.ino=identity;f.publishHttp();
    assert.throws(()=>preparedNativeHttpReceipt(f.root,f.selected));
  }
});
test('Resident preparation refuses incomplete, foreign, old deployment or changed originals',t=>{
  for(const change of [f=>{f.record.http=null;f.publish();},
    f=>{f.tls.minimumMacOS='26.0';f.publishHttp();},
    f=>{f.component.source='b'.repeat(40);f.publishHttp();},
    f=>{f.component.library.ino++;f.publishHttp();},
    f=>{writeFileSync(f.header,'changed original TLS compiler input');},
    f=>{writeFileSync(f.library,'changed HTTP library');}]) {
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
  for(const what of ['header','executable']) {
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
