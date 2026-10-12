import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
const files=['src/query_syntax/query.mbt','src/query_syntax/sga_call.mbt',
 'src/query_syntax/sga_argument_roles.mbt','src/query_program/query_script_carriers.mbt',
 'src/query_syntax/vector_pool_role_test.mbt','src/query_program/vector_pool_source_test.mbt'];
for(const file of files)assert.equal(execFileSync('moonfmt',[file],{encoding:'utf8'}),readFileSync(file,'utf8'),file);
execFileSync('git',['diff','--check','40d317c62482a9f3a49246722da1f1b8a6d17c71','HEAD','--','.',':(exclude)reviews/**'],{stdio:'inherit'});
console.log(JSON.stringify({authoredMoonFiles:files.length,formatMismatches:0,productSpecificationWhitespace:true,immutableRawReviewsExcluded:true}));
