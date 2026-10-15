// Project independent application originals into portable test inputs.
// Never regenerate expected request output from the product implementation.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {join} from 'node:path';
import {program, configuration} from './fixtures/first-m1-common-materials.mjs';
const installation=configuration(JSON.parse(readFileSync('spec/local-check-environment.json','utf8')));
const inputs=[['first_m1_current_environment',installation.environmentWire],
  ['first_m1_current_environment_cid',JSON.parse(installation.environmentWire).evidence_bundle_cid],
  ['first_m1_current_program',JSON.stringify(program)],
  ['first_m1_current_execution',installation.executionContracts[0].bodyWire],
  ['first_m1_current_execution_cid',installation.executionContracts[0].cid],
  ...installation.dependencyBodies.map((entry,index)=>[
    ['first_m1_current_prompt','first_m1_current_retry','first_m1_current_backoff'][index],entry.bodyWire])];
let source='// Generated independent first-M1 application originals; static DATA only.\n';
for(const [name,wire] of inputs)source+=`\n///|\nlet ${name} : String =\n  #|${wire}\n`;
assert.ok(process.env.MOON_HOME,'Pinned MoonBit formatter required');
source=execFileSync(join(process.env.MOON_HOME,'bin/moonfmt'),['-'],{input:source,encoding:'utf8'});
const target='src/client_infer_host/first_m1_original_request.generated_wbtest.mbt';
if(process.argv.includes('--write'))writeFileSync(target,source);
assert.equal(readFileSync(target,'utf8'),source,'Stale first-M1 original request inputs');
console.log('First-M1 originals match the independent application fixture.');
