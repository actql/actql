import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const steps = process.argv.includes('--write') ? [
  {name:'Update actual WITH normative metadata from authored documents',command:'node',args:['scripts/update-document-metadata.mjs','--write']},
  {name:'Generate actual requirement family from registered sources',command:'node',args:['scripts/check-actql-spec-family.mjs','--write']},
] : [
  {name:'Read-only actual document metadata freshness',command:'node',args:['scripts/update-document-metadata.mjs']},
  {name:'Read-only actual normative imports and requirement family',command:'node',args:['scripts/check-actql-spec-family.mjs']},
  {name:'Independent normative import validation tests',command:'node',args:['--input-type=module','-e','import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests("node",process.argv.slice(1),{cwd:process.cwd()});','--','scripts/spec-family-imports.test.mjs']},
];
process.exitCode = await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps});
