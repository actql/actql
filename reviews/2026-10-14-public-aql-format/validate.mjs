import {execFileSync} from 'node:child_process';
const run=(command,args,env={})=>execFileSync(command,args,{stdio:'inherit',timeout:30000,env:{...process.env,...env}});
run('_build/public-aql-python313/bin/python',['-m','unittest','discover','-s','packages/python-sdk/tests','-p','test_public_aql_format.py','-v'],{PYTHONPATH:'packages/python-sdk/src'});
run(process.execPath,['node_modules/typescript/lib/tsc.js','--noEmit','--strict','--module','NodeNext','--moduleResolution','NodeNext','--target','ES2022','packages/sdk/public-aql-format.typecheck.mts']);
run(process.execPath,['scripts/generate-python-client-wire.mjs','--check']);
run(process.execPath,['scripts/update-document-metadata.mjs']);
run(process.execPath,['scripts/check-actql-spec-family.mjs']);
run('git',['diff','--check']);
