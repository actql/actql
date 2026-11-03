// Retained public build inputs from one exact source/target, never Host/Read or
// capacity authority. A refusal never rebuilds or substitutes another artifact.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {lstatSync, readFileSync, realpathSync} from 'node:fs';
import {isAbsolute, join} from 'node:path';

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
    ['clang','components','entries','moon_home','sdk','source','target']);
  assert(Object.keys(record.entries).length>0);
  for(const entry of Object.keys(record.entries))assert(['native_runtime_bundle','native_remote_resident_site'].includes(entry));
  for(const key of ['source','target','clang'])assert.equal(record[key],selected[key]);
  assert.equal(record.sdk,selected.sdk??null);
  if(selected.moon_home!==undefined)assert.equal(record.moon_home,selected.moon_home);
  return {root,record};
}
export function preparedNativeCommand(root,entry,selected) {
  const {root:canonical,record}=index(root,selected);
  assert(['native_runtime_bundle','native_remote_resident_site'].includes(entry));
  const directory=join(canonical,entry),item=record.entries[entry];assert(item);
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
