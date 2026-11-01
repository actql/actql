import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdirSync} from 'node:fs';
import {dirname,join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {createOwnedScratch} from '../../../../scripts/owned-scratch.mjs';
const root=fileURLToPath(new URL('../../../../',import.meta.url));
let scratch,module;
test.before(async()=>{
  assert.equal(process.platform,'linux');assert.equal(process.arch,'x64');
  assert.equal(process.versions.node,'22.22.0');
  scratch=await createOwnedScratch({parent:join(root,'_build'),prefix:'local-files-linux-',
    label:'Linux Local Files syscall-boundary qualification'});
  module=join(scratch.path,'fault.node');
  const compiled=spawnSync('/usr/bin/gcc',['-std=c11','-D_GNU_SOURCE','-Wall','-Wextra','-Werror',
    '-O0','-g','-shared','-fPIC','-DNAPI_VERSION=8','-DNODE_GYP_MODULE_NAME=actql_files',
    '-I',resolve(dirname(process.execPath),'../include/node'),
    join(root,'adapters/host-node/native/fixtures/local-files-linux-publish-fault.c'),'-o',module],
    {encoding:'utf8',timeout:30000});
  assert.ifError(compiled.error);assert.equal(compiled.status,0,compiled.stderr);
});
test.after(()=>scratch?.passed());
const isolated=(name,code)=>{
  const directory=join(scratch.path,name);mkdirSync(directory);
  const child=spawnSync(process.execPath,['--input-type=module','-e',`
    import assert from 'node:assert/strict';import {createRequire} from 'node:module';
    import {readFileSync,writeFileSync,existsSync,symlinkSync,readlinkSync} from 'node:fs';
    import {prepareLocalFileWrite} from ${JSON.stringify(new URL('./root-file-writer.mjs',import.meta.url).href)};
    const fault=createRequire(import.meta.url)(${JSON.stringify(module)}),native=fault.operations;
    const directory=${JSON.stringify(directory)};
    const make=()=>prepareLocalFileWrite({native,rootPath:directory,path:'result',temporaryName:'.stage',maxBytes:8,assertCurrent(){}});
    ${code}`],{encoding:'utf8',timeout:10000});
  assert.ifError(child.error);assert.equal(child.signal,null);assert.equal(child.status,0,child.stdout+'\n'+child.stderr);
};
for(const [mode,label,code,renames] of [[1,'unsupported-kernel','LocalFilePublishFailed',1],
  [2,'unsupported-filesystem','LocalFilePublishFailed',1],[3,'file-sync','LocalFileSyncFailed',0]]){
  test(`Linux ${label} failure never publishes and cleans only original staging`,()=>isolated(label,`
    fault.select(${mode});const writer=make();writer.start();writer.write(Buffer.from('exact'));
    assert.throws(()=>writer.publish(),{code:${JSON.stringify(code)}});
    assert.equal(fault.renames(),${renames});assert.equal(existsSync(directory+'/result'),false);
    assert.throws(()=>writer.publish());assert.equal(fault.renames(),${renames});
    assert.equal(writer.close().pending,false);assert.equal(existsSync(directory+'/.stage'),false);
  `));
}
test('Linux post-rename directory sync failure retains published bytes without replay',()=>isolated('directory-sync',`
  fault.select(4);const writer=make();writer.start();writer.write(Buffer.from('exact'));
  assert.throws(()=>writer.publish(),{code:'LocalFilePublishDurabilityUnknown'});
  assert.equal(readFileSync(directory+'/result','utf8'),'exact');
  assert.throws(()=>writer.publish());assert.equal(fault.renames(),1);
  assert.equal(writer.close().pending,false);assert.equal(readFileSync(directory+'/result','utf8'),'exact');
`));
test('Linux ambiguous rename error remains pending without replay or destination deletion',()=>isolated('ambiguous',`
  fault.select(5);const writer=make();writer.start();writer.write(Buffer.from('exact'));
  assert.throws(()=>writer.publish(),{code:'LocalFilePublishFailed'});
  assert.equal(readFileSync(directory+'/result','utf8'),'exact');
  assert.throws(()=>writer.publish());assert.equal(fault.renames(),1);
  assert.equal(writer.close().pending,true);assert.equal(writer.close().pending,true);
  assert.equal(readFileSync(directory+'/result','utf8'),'exact');
  // This child exits with retained uncertain custody. Exit is not a close ACK.
`));
test('Linux create refuses dangling symlink and namespace contains full Files only',()=>isolated('symlink',`
  assert.deepEqual(Object.keys(native).sort(),['openFileRoot','openFileDirectory','openRootFile',
    'fileRootCurrent','fileRootStat','fileRootNext','fileRootRead','fileRootClose','fileRootEntryKind',
    'openRootFileWriter','fileRootWrite','fileRootPublish'].sort());
  symlinkSync(directory+'/absent',directory+'/result');
  const writer=make();writer.start();writer.write(Buffer.from('exact'));
  assert.throws(()=>writer.publish(),{code:'LocalFileDestinationExists'});
  assert.equal(writer.close().pending,false);assert.equal(existsSync(directory+'/absent'),false);
  assert.equal(readlinkSync(directory+'/result'),directory+'/absent');
`));
test('Linux same-root lock excludes another process and releases after original close',()=>isolated('process-lock',`
  const {spawnSync}=await import('node:child_process');
  const other=(blocked)=>{
    // The actual module path is passed as DATA, never a replacement provider.
    const code="const assert=require('node:assert/strict'),fs=require('node:fs');"+
      "const native=require(process.argv[1]).operations,root=native.openFileRoot(process.argv[2]);"+
      "const writer=native.openRootFileWriter(root,'.other','other',8);"+
      (blocked?"assert.throws(()=>native.fileRootCurrent(writer));assert.equal(fs.existsSync(process.argv[2]+'/.other'),false);":
        "native.fileRootCurrent(writer);native.fileRootWrite(writer,Buffer.from('other'));native.fileRootPublish(writer,false);")+
      "assert.equal(native.fileRootClose(writer).outcome,'closed');assert.equal(native.fileRootClose(root).outcome,'closed');";
    const result=spawnSync(process.execPath,['-e',code,${JSON.stringify(module ?? '')},directory],{encoding:'utf8',timeout:5000});
    assert.ifError(result.error);assert.equal(result.status,0,result.stderr);
  };
  const writer=make();writer.start();other(true);assert.equal(writer.close().pending,false);other(false);
  assert.equal(readFileSync(directory+'/other','utf8'),'other');
`));
