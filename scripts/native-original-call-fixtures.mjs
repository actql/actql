// Admission inputs projected from independent Decision/profile bodies. No
// product output supplies the original-ID answer or lifecycle expectations.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {canonicalText} from './check-canonical-json.mjs';
import {decisionVectors} from './decision-vectors.mjs';
import {responseProfileVectors} from './model-response-profile-vectors.mjs';

const target='src/client_infer_host/native_original_call_fixture.generated_wbtest.mbt';
const hash=body=>'sha256:'+createHash('sha256').update(canonicalText(body)).digest('hex');
export function nativeOriginalCallFixture() {
  const {corpus}=decisionVectors();
  const {evidence_bundle_cid:ignored,...base}=JSON.parse(readFileSync('spec/local-check-environment.json','utf8'));
  void ignored;
  const body={...base,model_task_contracts:[corpus.task]};
  const environment={...body,evidence_bundle_cid:hash(body)};
  // Explicit two-key fixture capacities, not a changed production ceiling or
  // a normal physical profile. Single attempt per Slot remains one.
  const {self_cid:old,...unsigned}=corpus.execution;
  void old;
  const executionBody={...unsigned,max_total_attempts:2,
    max_total_token_reservation:256,max_total_wire_bytes:133072};
  const execution={...executionBody,self_cid:hash(executionBody)};
  const baseline=responseProfileVectors().corpus.cases.find(c=>c.id==='SDK native Decision');
  // The real checked Host ceiling is 1000 bytes, below the isolated profile
  // vector's 1024. Select a narrower private profile with its own original CID;
  // never widen the Host policy or reuse the old profile identity.
  const nativeBody=structuredClone(baseline.body);
  nativeBody.limits.request_bytes=1000;
  const nativeCid=hash(nativeBody);
  const native={body:nativeBody,wire:canonicalText({...nativeBody,self_cid:nativeCid}),expected_cid:nativeCid};
  const program={version:'actql/0.1',id:'native-original-call',stages:[{
    id:'main',inputs:{},steps:[
      {values:{schema:{id:{type:'string',nullable:false}},
        rows:[{id:'b'},{id:'a'}]},as:'input'},
      {assert_rows:{unique_by:['id']},as:'unique'},
      {infer:{contract:corpus.task.task_id,key:'id',input:{state:{if:[
        {eq:[{field:'id'},{literal:'b'}]},
        {typed_literal:{type:'json',value:'null'}},
        {typed_literal:{type:'json',value:'["é\\r\\n",false,0]'}},
      ]}}},as:'answer'},
    ],results:{answer:{from:'answer',fields:['id','outcome','value']}},
  }],results:{answer:{from:{stage:'main',result:'answer'}}}};
  const values=[
    ['native_call_environment',canonicalText(environment)],
    ['native_call_environment_cid',environment.evidence_bundle_cid],
    ['native_call_program',canonicalText(program)],
    ['native_call_execution',canonicalText(execution)],
    ['native_call_execution_cid',execution.self_cid],
    ['native_call_prompt',canonicalText(corpus.prompt)],
    ['native_call_retry',canonicalText(corpus.retry)],
    ['native_call_backoff',canonicalText(corpus.backoff)],
    ['native_call_profile_wire',native.wire],
    ['native_call_profile_cid',native.expected_cid],
  ];
  let source='// Generated from independent Decision/profile admission inputs.\n';
  for(const [name,value] of values)source+=`\n///|\nlet ${name} : String =\n  #|${value}\n`;
  const b=native.body;
  const strings={builder_id:b.adapter.builder_id,builder_revision:b.adapter.builder_revision,
    codec_id:b.adapter.codec_id,codec_revision:b.adapter.codec_revision,
    build_artifact_cid:b.adapter.build_artifact_cid,endpoint:b.operation.endpoint,
    http_method:b.operation.method,validator_id:b.completion.validator_id,
    validator_revision:b.completion.validator_revision,
    validator_artifact_cid:b.completion.validator_artifact_cid,
    completion_basis:b.completion.basis};
  source+=`\n///|\nfn native_call_installation() -> @environment.ModelResponseProfileInstallation {\n{\n`;
  for(const [name,value]of Object.entries(strings))source+=`${name}:${JSON.stringify(value)},\n`;
  const sdk=b.adapter.sdk;
  source+=`streaming:false,sdk:Some({package_name:${JSON.stringify(sdk.package)},version:${JSON.stringify(sdk.version)},interface:${JSON.stringify(sdk.interface)},lock_artifact_cid:${JSON.stringify(sdk.lock_artifact_cid)}}),\n}\n}\n`;
  assert.ok(process.env.MOON_HOME,'Pinned MOON_HOME required');
  return execFileSync(join(process.env.MOON_HOME,'bin/moonfmt'),['-'],{input:source,encoding:'utf8'});
}
export function checkNativeOriginalCallFixture(write=false) {
  const source=nativeOriginalCallFixture();
  if(write)writeFileSync(target,source);
  assert.equal(readFileSync(target,'utf8'),source,'Stale native original-call admission fixture');
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
  checkNativeOriginalCallFixture(process.argv.includes('--write'));
}
