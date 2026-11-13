import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';

const repository=new URL('../',import.meta.url);
const source=readFileSync(new URL('./test-native-remote-runtime.mjs',import.meta.url),'utf8');
function nodes(value,predicate,result=[]) {
  if(value&&typeof value==='object') {
    if(predicate(value))result.push(value);
    for(const child of Object.values(value)) {
      if(Array.isArray(child))for(const item of child)nodes(item,predicate,result);
      else if(child&&typeof child==='object')nodes(child,predicate,result);
    }
  }
  return result;
}
const ast=parse(source,{ecmaVersion:'latest',sourceType:'module'}),value=x=>x?.type==='Literal'?x.value:undefined;
test('remote Native outputs and tool homes remain private for all five stripped entrances and unstripped Query',()=>{
  const calls=nodes(ast,n=>n.type==='CallExpression'&&['execFileSync','spawn'].includes(n.callee?.name)&&n.arguments[0]?.name==='moon');
  const native=calls.filter(call=>call.arguments[1]?.type==='ArrayExpression'&&call.arguments[1].elements.some(x=>value(x)==='native'));
  assert.equal(native.length,5);
  for(const call of native) {
    assert(call.arguments[1].elements.some(x=>x.type==='SpreadElement'&&x.argument.name==='nativeTargetArguments'));
    assert(call.arguments[1].elements.some(x=>value(x)==='--strip'));
    const env=call.arguments[2].properties.find(x=>x.key.name==='env').value;
    assert.equal(env.type,'CallExpression');assert.equal(env.callee.name,'nativeEnvironment');
  }
  const query=nodes(ast,n=>n.type==='CallExpression'&&n.callee?.name==='runNativeQueryTests');assert.equal(query.length,1);
  const options=query[0].arguments[2];
  assert(options.properties.some(p=>p.key.name==='targetDirectory'&&source.slice(p.value.start,p.value.end)==="join(root, 'native-query-build')"));
  assert(source.includes("copyNativePreparationTools(process.env.MOON_HOME, nativeMoonHome"));
  assert(source.includes("join(root, 'native-strip-build')"));
  assert(source.includes("join(root, 'compiler-tool')"));
});

test('macOS remote scheduling retains every exact original step in the same two slots with the HTTP lane independent',()=>{
  const original=JSON.parse(readFileSync(new URL('./fixtures/ci-native-obligations.json',import.meta.url)));
  const after=JSON.parse(readFileSync(new URL('./ci-native-background-groups.json',import.meta.url)));
  assert.equal(after['native-macos'].length,2);
  for(const family of ['native','native-macos']) {
    const actual=after[family].flatMap(group=>group.steps).filter(step=>/^(?:Test |Verify registered)/u.test(step.name));
    assert.equal(actual.length,original.jobs[family].length);
    for(const expected of original.jobs[family]) {
      const found=actual.filter(step=>step.name===expected.name);assert.equal(found.length,1);
      assert.equal(createHash('sha256').update(found[0].run).digest('hex'),expected.commandSha256);
      assert.deepEqual(found[0].env??{},expected.env);
    }
  }
  assert(after.native.find(group=>group.name==='runtime').steps.some(step=>step.id==='native-remote'));
  const remote=after['native-macos'].find(group=>group.steps.some(step=>step.id==='native-remote'));
  const http=after['native-macos'].find(group=>group.steps.some(step=>step.id==='native-http'));
  assert.notEqual(remote.name,http.name);assert.equal(remote.steps.at(-1).id,'native-remote');
  assert.equal(http.steps.find(step=>step.id==='native-http').timeoutMinutes,115);
});

test('all overlapping portable consumers select their existing verified original before importing its returned URL',()=>{
  for(const path of ['test-native-http-client.mjs','test-native-remote-runtime.mjs','test-native-runtime-bundle-cli.mjs']) {
    const body=readFileSync(new URL(path,import.meta.url),'utf8');
    const tree=parse(body,{ecmaVersion:'latest',sourceType:'module'});
    const core=nodes(tree,n=>n.type==='CallExpression'&&n.callee.name==='prepareNativeResidentPortableCore');
    assert.equal(core.length,1);
    const callback=core[0].arguments[1].properties.find(p=>p.key.name==='prepare').value;
    const builds=nodes(callback,n=>n.type==='CallExpression'&&n.callee.name==='execFileSync');assert.equal(builds.length,1);
    assert.deepEqual(builds[0].arguments[1].elements.slice(0,5).map(value),
      ['build','--target','js','--release','src/connectors_builtin_node']);
    assert(body.includes('const portableCorePath = prepareNativeResidentPortableCore('));
    assert(body.includes('await import(pathToFileURL(portableCorePath).href)'));
  }
});
