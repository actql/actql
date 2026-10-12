import {existsSync} from 'node:fs';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const normative = process.argv[2] === '--normative-write';
const nodeTests = process.argv[2] === '--node';
const freshness = process.argv[2] === '--freshness';
const generators = ['compilation-manifests','lag-identity-oracle','update-document-metadata','check-actql-spec-family','check-canonical-json'];
const inventory = process.argv[2] === '--inventory-write';
const format = ['--format','--format-write'].includes(process.argv[2]);
const write = process.argv[2] === '--format-write';
const selectedCase = process.argv[2] === '--case' ? process.argv[3] : null;
const info = process.argv[2] === '--info';
const compile = process.argv[2] === '--compile';
const target = compile ? process.argv[3] : 'js';
if (!['js','wasm','native'].includes(target)) throw new Error('Explicit supported target required');
const files = process.argv.slice(format || info || nodeTests ? 3 : selectedCase || compile ? 4 : 2);
if (!normative && !freshness && !inventory && (!files.length || files.some(file => !existsSync(file)))) throw new Error('Explicit existing focused files are required');
const inventoryRunner = `import {readFileSync,writeFileSync} from 'node:fs'; import {registeredPublicQueryInventory} from './scripts/public-query-inventory.mjs'; const path='scripts/fixtures/public-query-inventory.json'; const previous=JSON.parse(readFileSync(path,'utf8')); const actual=await registeredPublicQueryInventory(); writeFileSync(path,JSON.stringify({...previous,...actual},null,2)+'\\n'); console.log(JSON.stringify(actual));`;
const formatRunner = `import assert from 'node:assert/strict'; import {readFileSync} from 'node:fs'; import {spawnSync} from 'node:child_process'; const write=process.argv[1]==='write'; for(const file of process.argv.slice(2)){const result=spawnSync('moonfmt',write?['-w',file]:[file],{encoding:'utf8'}); assert.equal(result.status,0,result.stderr); if(!write)assert.equal(result.stdout,readFileSync(file,'utf8'),file);} console.log('Pinned changed-file formatter verified');`;
const steps = inventory ? [{name:'Independent declared public inventory',command:'node',args:['--input-type=module','-e',inventoryRunner]}]
  : normative ? generators.map(name => ({name: name,command:'node',args:['scripts/'+name+'.mjs','--write']}))
  : freshness ? [...generators.filter(name=>name!=='lag-identity-oracle').map(name=>({name:name,command:'node',args:['scripts/'+name+'.mjs']})), {name:'Read-only six changed MoonBit files',command:'node',args:['--input-type=module','-e',formatRunner,'check','src/query_program/lag_source_test.mbt','src/query_syntax/lag_call_test.mbt','src/query_program/query_script_carriers.mbt','src/query_syntax/sga_call.mbt','src/query_syntax/sga_argument_roles.mbt','src/run_publication_host/client_values_run_materials_wbtest.mbt']}]
  : nodeTests ? [{name:'Independent focused Node cases',command:'node',args:['--input-type=module','-e',runner,'node',...files]}]
  : format
  ? [{name:'Pinned explicit source formatting',command:'node',args:['--input-type=module','-e',formatRunner,write?'write':'check',...files]}]
  : info ? [{name:'Generate affected common interfaces',command:'moon',args:['info','--target','js',...files]}]
  : compile ? [{name:'Compile affected common API callers',command:'moon',args:['check','--target',target,...files]}]
  : [{name:'Explicit focused frontend cases',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js',...files,...(selectedCase ? ['--filter',selectedCase] : [])]}];
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps});
