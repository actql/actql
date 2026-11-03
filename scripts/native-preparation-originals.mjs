// Retained public build inputs from one exact source/target, never Host/Read or
// capacity authority. A refusal never rebuilds or substitutes another artifact.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {lstatSync, readFileSync, realpathSync} from 'node:fs';
import {isAbsolute, join} from 'node:path';
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
