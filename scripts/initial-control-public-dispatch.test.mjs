import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';

const root = fileURLToPath(new URL('../', import.meta.url));
for (const name of ['node', 'local-node']) {
  const original = fileURLToPath(new URL('../packages/' + name + '/initial-control-public-dispatch.cjs', import.meta.url));
  function child(args) {
    const result = spawnSync(process.execPath, args, {encoding: 'utf8',
      env: {PATH: process.env.PATH}, timeout: 10000});
    assert.equal(result.error, undefined);
    assert.equal(result.signal, null);
    assert.equal(result.status, 0, result.stderr);
  }
  test(name + ' ordinary private dispatch import does not load a wrapper or Root', () => {
    child(['-e', `const assert=require('node:assert/strict');const file=${JSON.stringify(original)};
const value=require(file);assert.equal(value.selectedInitialControlHostPreparation,undefined);
assert.ok(Object.isFrozen(value));assert.equal(Object.getPrototypeOf(value),null);
assert.deepEqual(Object.keys(value),['selectedInitialControlHostPreparation']);
assert.equal(Object.keys(require.cache).some(path=>path.endsWith('/selected-infer-startup.cjs')),false);
assert.equal(Object.keys(require.cache).some(path=>path.endsWith('/infer-trusted-node-preload.cjs')),false);`]);
  });
  test(name + ' late native-looking cache or caller table cannot become the selected original', () => {
    child(['-e', `const assert=require('node:assert/strict'),path=require('node:path');const file=${JSON.stringify(original)};
const wrapper=path.join(path.dirname(file),'selected-infer-startup.cjs');let calls=0;
require.cache[wrapper]={filename:wrapper,isPreloading:true,exports:{selectedInitialControlHostPreparation(){calls++;}}};
const value=require(file);assert.equal(value.selectedInitialControlHostPreparation,undefined);assert.equal(calls,0);`]);
  });
  test(name + ' another real preload cannot supply the private wrapper-parent original', t => {
    const dir = mkdtempSync(join(tmpdir(), 'actql-private-dispatch-parent-'));
    t.after(() => rmSync(dir, {recursive: true}));
    const entry = join(dir, 'entry.cjs'), preload = join(dir, 'preload.cjs');
    writeFileSync(preload, `globalThis.value=require(${JSON.stringify(original)});`);
    writeFileSync(entry, `require('node:assert/strict').equal(value.selectedInitialControlHostPreparation,undefined);`);
    child(['--require', preload, entry]);
  });
  test(name + ' actual wrapper child refusal preserves the same raw input and original function', t => {
    const directory = mkdtempSync(join(tmpdir(), 'actql-private-dispatch-child-'));
    t.after(() => rmSync(directory, {recursive: true}));
    const packageRoot = join(directory, 'node_modules/@actql', name);
    mkdirSync(packageRoot, {recursive: true});
    for (const file of ['selected-infer-startup.cjs', 'initial-control-public-dispatch.cjs']) {
      writeFileSync(join(packageRoot, file), readFileSync(join(root, 'packages', name, file)));
    }
    writeFileSync(join(packageRoot, 'package.json'), JSON.stringify({name: '@actql/' + name,
      exports: {'./selected-infer-startup': './selected-infer-startup.cjs'}}));
    // Explicit child control, not the selected operational Root or Host. The
    // actual wrapper/forwarder executes, and must preserve receiver/raw/cause.
    const body = `const assert=require('node:assert/strict');globalThis.childReceiver=module.exports;
globalThis.originalCause=Object.freeze(new Error('OriginalChildRefusal'));
module.exports.selectedInitialControlHostPreparation=module.exports.connectInitialControlHostPreparation=function(kind,raw){
assert.equal(this,childReceiver);assert.equal(kind,'open');assert.equal(raw,globalThis.rawOriginal);throw originalCause;};`;
    if (name === 'node') {
      const childRoot = join(packageRoot, 'node_modules/@actql/local-node');
      mkdirSync(childRoot, {recursive: true});
      writeFileSync(join(childRoot, 'package.json'), JSON.stringify({exports: {'./selected-infer-startup': './child.cjs'}}));
      writeFileSync(join(childRoot, 'child.cjs'), body);
    } else {
      mkdirSync(join(packageRoot, 'adapters/host-node'), {recursive: true});
      writeFileSync(join(packageRoot, 'adapters/host-node/infer-trusted-node-preload.cjs'), body);
    }
    const entry = join(directory, 'entry.cjs');
    writeFileSync(entry, `const assert=require('node:assert/strict');
const table=require(${JSON.stringify(join(packageRoot, 'initial-control-public-dispatch.cjs'))});
assert.equal(typeof table.selectedInitialControlHostPreparation,'function');let reads=0;
globalThis.rawOriginal=new Proxy({},{get(){reads++;throw new Error('RawGet');},ownKeys(){reads++;throw new Error('RawKeys');}});
assert.throws(()=>table.selectedInitialControlHostPreparation('open',rawOriginal),e=>e===originalCause);
const wrapper=require.resolve('@actql/${name}/selected-infer-startup');
require.cache[wrapper].exports={selectedInitialControlHostPreparation(){throw new Error('Replacement');}};
childReceiver.selectedInitialControlHostPreparation=childReceiver.connectInitialControlHostPreparation=()=>{throw new Error('Replacement');};
assert.throws(()=>table.selectedInitialControlHostPreparation('open',rawOriginal),e=>e===originalCause);assert.equal(reads,0);`);
    const result = spawnSync(process.execPath, ['--require', '@actql/' + name + '/selected-infer-startup', entry],
      {cwd: directory, env: {PATH: process.env.PATH}, encoding: 'utf8', timeout: 10000});
    assert.equal(result.error, undefined);assert.equal(result.status, 0, result.stderr);
  });
}
