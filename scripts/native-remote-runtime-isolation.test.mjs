import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
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
  const before=JSON.parse(execFileSync('git',['show','b492d5071d:scripts/ci-native-background-groups.json'],{cwd:repository,encoding:'utf8'}));
  const after=JSON.parse(readFileSync(new URL('./ci-native-background-groups.json',import.meta.url)));
  assert.deepEqual(after.native,before.native);
  assert.equal(after['native-macos'].length,2);
  const inventory=groups=>groups.flatMap(group=>group.steps).sort((a,b)=>a.name.localeCompare(b.name));
  assert.deepEqual(inventory(after['native-macos']),inventory(before['native-macos']));
  const remote=after['native-macos'].find(group=>group.steps.some(step=>step.id==='native-remote'));
  const http=after['native-macos'].find(group=>group.steps.some(step=>step.id==='native-http'));
  assert.notEqual(remote.name,http.name);assert.equal(remote.steps.at(-1).id,'native-remote');
});
