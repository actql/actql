import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {runLocalCheck} from './local-checks-guard.mjs';

const root=fileURLToPath(new URL('../',import.meta.url));
const child=(name,args,timeout)=>({name,command:process.execPath,args:[
  '--input-type=module','-e',
  `import {spawnSync} from 'node:child_process';const result=spawnSync('moon',${JSON.stringify(args)},`+
  `{stdio:'inherit',timeout:${timeout},killSignal:'SIGTERM'});process.exitCode=result.status??1;`,
]});
console.log('Binding verification source: '+execFileSync('git',['rev-parse','HEAD'],{cwd:root,encoding:'utf8'}).trim());
process.exitCode=await runLocalCheck({root,heavy:false,timeoutSeconds:180,graceSeconds:5,steps:[
  {name:'private compiler binding freshness',command:process.execPath,
    args:['scripts/generate-js-compiler-bindings.mjs','--check']},
  {name:'Owner action binding freshness',command:process.execPath,
    args:['scripts/generate-js-action-bindings.mjs','--check']},
  child('actual JS compiler and Owner probes',[
    'build','--target','js','--release','-j','1',
    'src/interface_binding_probe','src/interface_action_probe',
  ],150000),
  {name:'actual compiled conversion and action counterexamples',command:process.execPath,args:[
    '--input-type=module','-e',
    "import {runFocusedTests} from './scripts/test-execution.mjs';process.exitCode=runFocusedTests('node',"+
    "['scripts/js-compiler-binding-runtime.test.mjs','scripts/js-action-binding-runtime.test.mjs',"+
    "'adapters/host-common/publication-action.test.mjs','adapters/host-common/strategy-actions.test.mjs'],"+
    "{cwd:process.cwd(),timeout:30000,killSignal:'SIGTERM'});",
  ]},
]});
