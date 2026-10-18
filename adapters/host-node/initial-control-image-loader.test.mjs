import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdirSync, mkdtempSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

const capture = fileURLToPath(new URL('./initial-control-image-source.cjs', import.meta.url));
const loader = fileURLToPath(new URL('./initial-control-image-loader.cjs', import.meta.url));
function fixture(t, files = {'original.mjs': 'export const value = "original";\n'}, type = 'module') {
  const root = mkdtempSync(join(tmpdir(), 'actql-initial-image-loader-'));
  t.after(() => rmSync(root, {recursive: true}));
  const images = join(root, 'images'); mkdirSync(images);
  const sources = {'package.json': JSON.stringify({name: 'independent-image-fixture', type}), ...files};
  const facts = [];
  for (const [path, source] of Object.entries(sources)) {
    mkdirSync(dirname(join(images, path)), {recursive: true}); writeFileSync(join(images, path), source);
    const bytes = Buffer.from(source);
    facts.push({path, expected: {bytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex')}});
  }
  const preload = join(root, 'preload.cjs'), entry = join(root, 'entry.mjs');
  return {root, images, sources, facts, run(body, after = '', before = '') {
    // Disposable preloads exercise real Node hooks, not the selected ActQL
    // envelope, original Host, operational admission or normal funding.
    writeFileSync(preload, [
      before,
      "const fs = require('node:fs');",
      'const {captureInitialControlImageSource} = require(' + JSON.stringify(capture) + ');',
      'const {installInitialControlImageLoader} = require(' + JSON.stringify(loader) + ');',
      'const root = ' + JSON.stringify(images) + ', facts = ' + JSON.stringify(facts) + ';',
      "const captured=facts.map(({path,expected})=>({path,captured:captureInitialControlImageSource(require('node:path').join(root,path),expected)}));",
      'globalThis.originalImageLoader=installInitialControlImageLoader([{root,images:captured}]);',
      after,
    ].join('\n'));
    writeFileSync(entry, body);
    const value = spawnSync(process.execPath, ['--require', preload, entry], {
      cwd: root, env: {...process.env, NODE_OPTIONS: undefined}, encoding: 'utf8', timeout: 20000});
    assert.equal(value.error, undefined);
    return value;
  }};
}

test('actual ESM compilation uses captured Source instead of a replaced pathname body', t => {
  const f = fixture(t), result = f.run([
    "import assert from 'node:assert/strict';",
    "import {value} from './images/original.mjs';",
    "assert.equal(value,'original'); originalImageLoader.assertCurrent();",
  ].join('\n'), "fs.writeFileSync(require('node:path').join(root,'original.mjs'),'export const value=\"replacement\";');");
  assert.equal(result.status, 0, result.stderr);
});

test('actual CommonJS compilation and original manifest type use captured Sources', t => {
  const f = fixture(t, {'original.js': 'module.exports={value:"original-commonjs"};\n'}, 'commonjs');
  const result = f.run([
    "import assert from 'node:assert/strict';",
    "import original from './images/original.js';",
    "assert.equal(original.value,'original-commonjs'); originalImageLoader.assertCurrent();",
  ].join('\n'), [
    "fs.writeFileSync(require('node:path').join(root,'original.js'),'module.exports={value:\"replacement\"};');",
    "fs.writeFileSync(require('node:path').join(root,'package.json'),'{\"type\":\"module\"}');",
  ].join('\n'));
  assert.equal(result.status, 0, result.stderr);
});

test('JSON module body is captured rather than reparsed from a replaced physical asset', t => {
  const f = fixture(t, {'original.json': '{"value":"original-json"}'});
  const result = f.run([
    "import assert from 'node:assert/strict';",
    "import original from './images/original.json' with {type:'json'};",
    "assert.equal(original.value,'original-json'); originalImageLoader.assertCurrent();",
  ].join('\n'), "fs.writeFileSync(require('node:path').join(root,'original.json'),'{not the original JSON');");
  assert.equal(result.status, 0, result.stderr);
});

test('captured JSON metadata keeps its original nested records and arrays immutable', t => {
  const f = fixture(t, {'original.json': '{"policy":{"maxRows":1},"fields":[{"name":"original"}]}'});
  const result = f.run([
    "import assert from 'node:assert/strict';",
    'assert.ok(Object.isFrozen(originalJson.policy));',
    'assert.ok(Object.isFrozen(originalJson.fields));',
    'assert.ok(Object.isFrozen(originalJson.fields[0]));',
    'assert.throws(()=>{originalJson.policy.maxRows=100000;},TypeError);',
    'assert.throws(()=>{originalJson.fields[0].name="replacement";},TypeError);',
    'assert.equal(originalJson.policy.maxRows,1);',
    'assert.equal(originalJson.fields[0].name,"original");',
    'originalImageLoader.assertCurrent();',
  ].join('\n'), [
    'globalThis.originalJson=require(require("node:path").join(root,"original.json"));',
    'originalImageLoader.captureLoadedModules();',
  ].join('\n'));
  assert.equal(result.status, 0, result.stderr);
});

test('a nested JSON value changed before capture cannot substitute captured Source metadata', t => {
  const f = fixture(t, {'original.json': '{"policy":{"maxRows":1}}'});
  const result = f.run('throw new Error("EntryMustNotRun");', [
    'const original=require(require("node:path").join(root,"original.json"));',
    'original.policy.maxRows=100000;',
    'originalImageLoader.captureLoadedModules();',
  ].join('\n'));
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /InitialControlImageLoaderChanged/);
  assert.doesNotMatch(result.stderr, /EntryMustNotRun/);
});

test('JSON metadata handoff preserves BOM Unicode null and negative zero without freezing prototypes', t => {
  const f = fixture(t, {'original.json': '\uFEFF{"__proto__":{"value":"原本"},"values":[null,-0,true,"\\ud83d\\udc3e"]}'});
  const result = f.run([
    "import assert from 'node:assert/strict';",
    'assert.equal(Object.getPrototypeOf(originalJson),Object.prototype);',
    'assert.equal(Object.hasOwn(originalJson,"__proto__"),true);',
    'assert.equal(originalJson.__proto__.value,"原本");',
    'assert.ok(Object.isFrozen(originalJson.__proto__));',
    'assert.deepEqual(originalJson.values,[null,-0,true,"🐾"]);',
    'assert.equal(Object.isFrozen(Object.prototype),false);',
    'assert.equal(Object.isFrozen(Array.prototype),false);',
    'originalImageLoader.assertCurrent();',
  ].join('\n'), [
    'globalThis.originalJson=require(require("node:path").join(root,"original.json"));',
    'originalImageLoader.captureLoadedModules();',
  ].join('\n'));
  assert.equal(result.status, 0, result.stderr);
});

test('covered modules cannot import an uncaptured sibling even when it exists on disk', t => {
  const f = fixture(t, {'original.mjs': 'export {value} from "./foreign.mjs";\n'});
  const result = f.run("await import('./images/original.mjs');",
    "fs.writeFileSync(require('node:path').join(root,'foreign.mjs'),'export const value=\"foreign\";');");
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /UncapturedInitialControlImage/);
});

test('captured bodies cannot silently acquire a dependency outside all selected image domains', t => {
  const f = fixture(t, {'original.mjs': 'export {value} from "../foreign.mjs";\n'});
  writeFileSync(join(f.root, 'foreign.mjs'), 'export const value="foreign-domain";');
  const result = f.run("await import('./images/original.mjs');");
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /UncapturedInitialControlDependency/);
});

test('queries cannot create a second compiled image while builtin dependencies remain normal', t => {
  const f = fixture(t, {'original.mjs': 'import {sep} from "node:path"; export const value=sep;'});
  const result = f.run([
    "import assert from 'node:assert/strict';",
    "assert.equal((await import('./images/original.mjs')).value,'/');",
    "await assert.rejects(import('./images/original.mjs?foreign-image'),{code:'UncapturedInitialControlImage'});",
    'originalImageLoader.assertCurrent();',
  ].join('\n'));
  assert.equal(result.status, 0, result.stderr);
});

test('application-time helper invocation refuses before reading caller records or installing another hook', t => {
  const f = fixture(t), result = f.run([
    "import assert from 'node:assert/strict';",
    "import {createRequire} from 'node:module';",
    'const {installInitialControlImageLoader}=createRequire(import.meta.url)(' + JSON.stringify(loader) + ');',
    "const packet=new Proxy([], {get(){throw new Error('CallerRead');}});",
    "assert.throws(()=>installInitialControlImageLoader(packet),{code:'InitialControlImageLoaderUnavailable'});",
    'originalImageLoader.assertCurrent();',
  ].join('\n'));
  assert.equal(result.status, 0, result.stderr);
});

test('registration through the published fence stays invalidated after deregistration', t => {
  const f = fixture(t), result = f.run([
    "import assert from 'node:assert/strict';",
    "import {registerHooks} from 'node:module';",
    'originalImageLoader.assertCurrent();',
    'const later=registerHooks({resolve(name,context,next){return next(name,context);}});',
    "assert.throws(()=>originalImageLoader.assertCurrent(),{code:'InitialControlImageLoaderChanged'});",
    'later.deregister();',
    "assert.throws(()=>originalImageLoader.assertCurrent(),{code:'InitialControlImageLoaderChanged'});",
    "await assert.rejects(import('./images/original.mjs'),{code:'InitialControlImageLoaderChanged'});",
  ].join('\n'));
  assert.equal(result.status, 0, result.stderr);
});

test('a retained pre-fence registration function is outside the property fence observation', t => {
  const f = fixture(t), result = f.run([
    "import assert from 'node:assert/strict';",
    "import {createRequire} from 'node:module';",
    "const NodeModule=createRequire(import.meta.url)('node:module');",
    'assert.equal(NodeModule.registerHooks,originalRegistrationFence);',
    'originalImageLoader.assertCurrent();',
    "assert.equal((await import('./images/original.mjs')).value,'retained-registration');",
    'originalImageLoader.assertCurrent();',
    'retainedRegistration.deregister();',
    'assert.equal(NodeModule.registerHooks,originalRegistrationFence);',
    'originalImageLoader.assertCurrent();',
  ].join('\n'), [
    'originalImageLoader.captureLoadedModules();',
    "globalThis.originalRegistrationFence=require('node:module').registerHooks;",
    'globalThis.retainedRegistration=retainedRegisterHooks({',
    "resolve(name,context,next){if(name.endsWith('/images/original.mjs'))return {url:new URL(name,context.parentURL).href,shortCircuit:true};return next(name,context);},",
    "load(url,context,next){if(url.endsWith('/images/original.mjs'))return {format:'module',source:'export const value=\"retained-registration\";',shortCircuit:true};return next(url,context);}",
    '});',
  ].join('\n'), "const retainedRegisterHooks=require('node:module').registerHooks;");
  assert.equal(result.status, 0, result.stderr);
});

test('the loader helper issues no operational admission or Host scope', t => {
  const f = fixture(t), result = f.run([
    "import assert from 'node:assert/strict';",
    "assert.deepEqual(Object.keys(originalImageLoader),['assertCurrent','captureLoadedModules']);",
    'assert.equal(originalImageLoader.begin,undefined);',
    'assert.equal(originalImageLoader.retainPreparation,undefined);',
    'assert.ok(Object.isFrozen(originalImageLoader));',
  ].join('\n'));
  assert.equal(result.status, 0, result.stderr);
});

test('a caller cache preseed cannot replace a captured CommonJS module original', t => {
  const f = fixture(t, {'original.cjs': 'module.exports={value:"original-cache"};'});
  const result = f.run([
    "import assert from 'node:assert/strict';",
    "import {createRequire} from 'node:module';",
    'const require=createRequire(import.meta.url), Module=require("node:module");',
    'const filename=require.resolve("./images/original.cjs"), fake=new Module(filename);',
    'fake.filename=filename; fake.loaded=true; fake.exports={value:"caller-copy"};',
    'Module._cache[filename]=fake;',
    'await assert.rejects(import("./images/original.cjs"),{code:"InitialControlImageLoaderChanged"});',
  ].join('\n'));
  assert.equal(result.status, 0, result.stderr);
});

test('a stock load replacement cannot retain the selected loader currentness', t => {
  const f = fixture(t), result = f.run([
    "import assert from 'node:assert/strict';",
    "import {createRequire} from 'node:module';",
    'const Module=createRequire(import.meta.url)("node:module");',
    'Module._load=function(){return {callerReplacement:true};};',
    'assert.throws(()=>originalImageLoader.assertCurrent(),{code:"InitialControlImageLoaderChanged"});',
  ].join('\n'));
  assert.equal(result.status, 0, result.stderr);
});

function eagerCommon(t, body, source = 'module.exports={value:"original-loaded"};') {
  const f = fixture(t, {'original.cjs': source});
  return f.run(body, [
    'globalThis.originalLoaded=require(require("node:path").join(root,"original.cjs"));',
    'originalImageLoader.captureLoadedModules();',
  ].join('\n'));
}

test('post-load capture binds the actual cache module and exports before entry', t => {
  const result = eagerCommon(t, [
    'import assert from "node:assert/strict";',
    'import {createRequire} from "node:module";',
    'const require=createRequire(import.meta.url), name=require.resolve("./images/original.cjs");',
    'const record=require.cache[name], original=record.exports;',
    'originalImageLoader.assertCurrent();',
    'assert.equal(original,originalLoaded);',
    'record.exports={value:"entry-replacement"};',
    'assert.throws(()=>originalImageLoader.assertCurrent(),{code:"InitialControlImageLoaderChanged"});',
    'record.exports=original;',
    'assert.throws(()=>originalImageLoader.assertCurrent(),{code:"InitialControlImageLoaderChanged"});',
  ].join('\n'));
  assert.equal(result.status, 0, result.stderr);
});

test('equal exported references cannot substitute a foreign cache Module record', t => {
  const result = eagerCommon(t, [
    'import assert from "node:assert/strict";',
    'import {createRequire} from "node:module";',
    'const require=createRequire(import.meta.url), Module=require("node:module");',
    'const name=require.resolve("./images/original.cjs"), old=require.cache[name];',
    'const foreign=new Module(name); foreign.filename=name; foreign.loaded=true; foreign.exports=old.exports;',
    'require.cache[name]=foreign;',
    'assert.throws(()=>originalImageLoader.assertCurrent(),{code:"InitialControlImageLoaderChanged"});',
  ].join('\n'));
  assert.equal(result.status, 0, result.stderr);
});

test('an original undefined export cannot be replaced by an unobserved cache getter', t => {
  const result = eagerCommon(t, [
    'import assert from "node:assert/strict";',
    'import {createRequire} from "node:module";',
    'const require=createRequire(import.meta.url), name=require.resolve("./images/original.cjs");',
    'let reads=0;',
    'Object.defineProperty(require.cache[name],"exports",{get(){reads++;return undefined;}});',
    'assert.throws(()=>originalImageLoader.assertCurrent(),{code:"InitialControlImageLoaderChanged"});',
    'assert.equal(reads,0);',
  ].join('\n'), 'module.exports=undefined;');
  assert.equal(result.status, 0, result.stderr);
});

test('export descriptor replacement refuses without invoking the replacement getter', t => {
  const result = eagerCommon(t, [
    'import assert from "node:assert/strict";',
    'let calls=0;',
    'Object.defineProperty(originalLoaded,"value",{get(){calls++;return "entry-replacement";}});',
    'assert.throws(()=>originalImageLoader.assertCurrent(),{code:"InitialControlImageLoaderChanged"});',
    'assert.equal(calls,0);',
  ].join('\n'));
  assert.equal(result.status, 0, result.stderr);
});

test('original exported getters are captured and checked as descriptors without invocation', t => {
  const result = eagerCommon(t, [
    'import assert from "node:assert/strict";',
    'originalImageLoader.assertCurrent(); originalImageLoader.assertCurrent();',
    'assert.equal(globalThis.originalGetterCalls,0);',
  ].join('\n'), 'globalThis.originalGetterCalls=0;module.exports={get value(){originalGetterCalls++;return "original";}};');
  assert.equal(result.status, 0, result.stderr);
});

test('application-time post-load capture cannot resnapshot changed originals', t => {
  const result = eagerCommon(t, [
    'import assert from "node:assert/strict";',
    'assert.throws(()=>originalImageLoader.captureLoadedModules(),{code:"InitialControlImageLoaderUnavailable"});',
    'originalImageLoader.assertCurrent();',
    'originalLoaded.value="entry-replacement";',
    'assert.throws(()=>originalImageLoader.captureLoadedModules(),{code:"InitialControlImageLoaderUnavailable"});',
    'assert.throws(()=>originalImageLoader.assertCurrent(),{code:"InitialControlImageLoaderChanged"});',
  ].join('\n'));
  assert.equal(result.status, 0, result.stderr);
});

test('a captured but unevaluated CJS image does not gain post-entry module provenance', t => {
  const f = fixture(t, {'original.cjs': 'module.exports={value:"not-initialized"};'});
  const result = f.run([
    'import assert from "node:assert/strict";',
    'await assert.rejects(import("./images/original.cjs"),{code:"InitialControlImageLoaderChanged"});',
  ].join('\n'), 'originalImageLoader.captureLoadedModules();');
  assert.equal(result.status, 0, result.stderr);
});

test('post-load capture cannot adopt a cache preseed without original Source handoff', t => {
  const f = fixture(t, {'original.cjs': 'module.exports={value:"original-cache"};'});
  const result = f.run('throw new Error("MustNotReachEntry");', [
    'const Module=require("node:module"), filename=require.resolve(require("node:path").join(root,"original.cjs"));',
    'const fake=new Module(filename);fake.filename=filename;fake.loaded=true;fake.exports={value:"fake"};',
    'Module._cache[filename]=fake;',
    'originalImageLoader.captureLoadedModules();',
  ].join('\n'));
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /InitialControlImageLoaderChanged/);
  assert.doesNotMatch(result.stderr, /MustNotReachEntry/);
});
