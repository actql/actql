// Focused three-language wire conformance; no Host/engine/product producer.
import {fileURLToPath} from 'node:url';
import {dirname, join} from 'node:path';
import {runLocalCheck} from './local-checks-guard.mjs';

if(process.argv.length!==2)throw Error('Usage: node scripts/check-public-wire-codecs.mjs');
const root=fileURLToPath(new URL('../',import.meta.url));
const env={PATH:process.env.MOON_HOME
  ? join(process.env.MOON_HOME,'bin')+':'+dirname(process.execPath)+':'+process.env.PATH
  : dirname(process.execPath)+':'+process.env.PATH};
process.exitCode=await runLocalCheck({root,heavy:false,timeoutSeconds:180,graceSeconds:5,
 resources:{memoryBytes:1073741824,diskBytes:268435456,cpuThreads:1},steps:[
 ...['generate-python-client-wire.mjs','generate-client-host-wire.mjs',
   'generate-client-publication-wire.mjs','generate-interactive-run-control-wire.mjs'].map(file=>({
    name:file+' freshness',command:process.execPath,args:['scripts/'+file,'--check'],env,
   })),
 {name:'Independent JS/Python vectors and mutations',command:process.execPath,args:[
  '--input-type=module','-e',
  "import {runFocusedTests} from './scripts/test-execution.mjs'; process.exitCode=runFocusedTests('node',process.argv.slice(1),{cwd:process.cwd()});",'--',
  '--test-concurrency=1','scripts/public-wire-language-vectors.test.mjs',
  'scripts/public-wire-language-mutations.test.mjs','scripts/python-client-wire-codec.test.mjs',
 ],env},
 {name:'Actual Native production codec vectors',command:process.execPath,
  args:['scripts/prepare-native-public-wire-vectors.mjs'],env},
]});
