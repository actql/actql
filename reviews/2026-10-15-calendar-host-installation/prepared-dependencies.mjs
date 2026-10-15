import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdirSync,existsSync,lstatSync,realpathSync,symlinkSync} from 'node:fs';
import {join} from 'node:path';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const source=process.argv[2];assert.match(source,/^[a-f0-9]{40}$/u);
const git=(...a)=>execFileSync('git',a,{encoding:'utf8'}).trim();
assert.equal(git('rev-parse','HEAD'),source);assert.equal(git('status','--porcelain'),'');
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:120,graceSeconds:5,
  steps:[{name:'Own locked build dependencies without lifecycle scripts',command:'npm',args:['ci','--ignore-scripts','--no-audit','--no-fund','--cache',join(process.cwd(),'_build/npm-cache')]}]});
if(process.exitCode===0){
 const root=realpathSync(process.cwd());mkdirSync('node_modules/@actql',{recursive:true});
 for(const name of ['client-wire','sdk','local-node','node']){
  const target=join(root,'packages',name),link=join(root,'node_modules/@actql',name);
  if(existsSync(link)){assert(lstatSync(link).isSymbolicLink());assert.equal(realpathSync(link),target);}
  else symlinkSync(target,link,'dir');
 }
 console.log('Own local unit/type links only; external packed consumers receive none.');
}
assert.equal(git('rev-parse','HEAD'),source);assert.equal(git('status','--porcelain'),'');
