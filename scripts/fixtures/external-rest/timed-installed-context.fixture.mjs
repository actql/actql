// Same installed Node/Host SDK identity, before importing any product module.
// This is conformance input inspection, not a Host, issuer or runtime fallback.
import assert from 'node:assert/strict';
import {lstat,realpath} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {join,relative,isAbsolute,sep} from 'node:path';
export async function resolveInstalledCompletionModules(consumerRoot) {
 assert(isAbsolute(consumerRoot));
 const modules=join(consumerRoot,'node_modules');
 assert(!(await lstat(modules)).isSymbolicLink(),'CompletionWorkspaceAliasRefused');
 assert.equal(await realpath(modules),modules,'CompletionWorkspaceAliasRefused');
 const consumer=createRequire(join(consumerRoot,'package.json'));
 const resolveNormal=async(require,name)=>{
  const original=require.resolve(name),path=await realpath(original),suffix=relative(modules,path);
  assert(suffix!==''&&suffix!=='..'&&!suffix.startsWith('..'+sep)&&!isAbsolute(suffix),'CompletionWorkspaceAliasRefused');
  assert.equal(original,path,'CompletionWorkspaceAliasRefused');
  let current=modules;
  for(const piece of suffix.split(sep)) {current=join(current,piece);assert(!(await lstat(current)).isSymbolicLink(),'CompletionWorkspaceAliasRefused');}
  return path;
 };
 const node=await resolveNormal(consumer,'@actql/node'),host=await resolveNormal(consumer,'@actql/local-node');
 const sdk=await resolveNormal(createRequire(node),'@actql/sdk');
 assert.equal(await resolveNormal(createRequire(host),'@actql/sdk'),sdk,'CompletionSdkNamespaceMismatch');
 assert.equal(await resolveNormal(consumer,'@actql/sdk'),sdk,'CompletionSdkNamespaceMismatch');
 return Object.freeze({node,host,sdk});
}
