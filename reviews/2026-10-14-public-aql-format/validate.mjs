import {execFileSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
const run=(command,args,env={})=>execFileSync(command,args,{stdio:'inherit',timeout:30000,env:{...process.env,...env}});
run('_build/public-aql-python313/bin/python',['-m','unittest','discover','-s','packages/python-sdk/tests','-p','test_public_aql_format.py','-v'],{PYTHONPATH:'packages/python-sdk/src'});
run('_build/public-aql-python313/bin/python',['-m','mypy','--strict','--follow-imports','silent','packages/python-sdk/tests/public_aql_format_typing.py'],{MYPYPATH:'packages/python-sdk/src'});
run(process.execPath,['node_modules/typescript/lib/tsc.js','--noEmit','--strict','--module','NodeNext','--moduleResolution','NodeNext','--target','ES2022','packages/sdk/public-aql-format.typecheck.mts']);
run(process.execPath,['scripts/generate-python-client-wire.mjs','--check']);
run(process.execPath,['scripts/update-document-metadata.mjs']);
run(process.execPath,['scripts/check-actql-spec-family.mjs']);
run('git',['diff','--check']);

for(const path of ['src/source_frontend/lower.mbt','src/source_frontend/lower_test.mbt']){
 const formatted=execFileSync(join(process.env.MOON_HOME,'bin/moonfmt'),[path],{timeout:30000});
 assert.deepEqual(formatted,readFileSync(path),`Pinned format: ${path}`);
}
