import {existsSync} from 'node:fs';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const normative = process.argv[2] === '--normative-write';
const nodeTests = process.argv[2] === '--node';
const freshness = process.argv[2] === '--freshness';
const generators = ['compilation-manifests','lag-identity-oracle','update-document-metadata','check-actql-spec-family','check-canonical-json'];
const format = ['--format','--format-write'].includes(process.argv[2]);
const write = process.argv[2] === '--format-write';
const selectedCase = process.argv[2] === '--case' ? process.argv[3] : null;
const info = process.argv[2] === '--info';
const compile = process.argv[2] === '--compile';
const target = compile ? process.argv[3] : 'js';
if (!['js','wasm','native'].includes(target)) throw new Error('Explicit supported target required');
const files = process.argv.slice(format || info || nodeTests ? 3 : selectedCase || compile ? 4 : 2);
if (!normative && !freshness && (!files.length || files.some(file => !existsSync(file)))) throw new Error('Explicit existing focused files are required');
const steps = normative ? generators.map(name => ({name: name,command:'node',args:['scripts/'+name+'.mjs','--write']}))
  : freshness ? generators.filter(name=>name!=='lag-identity-oracle').map(name=>({name:name,command:'node',args:['scripts/'+name+'.mjs']}))
  : nodeTests ? [{name:'Independent focused Node cases',command:'node',args:['--input-type=module','-e',runner,'node',...files]}]
  : format
  ? [{name:'Read-only changed fixture formatting',command:'moon',args:['fmt',...(write ? [] : ['--check']),...files]}]
  : info ? [{name:'Generate affected common interfaces',command:'moon',args:['info','--target','js',...files]}]
  : compile ? [{name:'Compile affected common API callers',command:'moon',args:['check','--target',target,...files]}]
  : [{name:'Explicit focused frontend cases',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js',...files,...(selectedCase ? ['--filter',selectedCase] : [])]}];
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps});
