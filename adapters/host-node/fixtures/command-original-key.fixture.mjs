// Actual Common/managed Result and Host export fixture. Policy evidence below
// isolates capture correspondence; it is not an installed issuer, normal
// numerical supplier, authenticated Preview or physical Effect permission.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {canonicalText} from '../../../scripts/check-canonical-json.mjs';
import * as moon from '../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../../host-common/runtime-result.mjs';
import {runCapturedEffectComputation} from '../entry.mjs';

export {moon};
const cid = digit => `sha256:${digit.repeat(64)}`;

function publicationEvidence(prepared) {
  const bounds = [100000,10000,64];
  const evidence = (kind, body) => checked(moon.strategyRunEvidenceSeal(
    kind, JSON.stringify(body), ...bounds));
  const program = moon.clientProgramEffectDefinitionCid(prepared);
  const parameters = moon.clientRequestParametersCid(
    moon.clientProgramEffectRequestIdentity(prepared,cid('a'),'key-fixture',cid('b')));
  const template = evidence('bound_invocation_template',{
    version:'actql-bound-invocation-template/0.1',program_definition_cid:program,
    parameter_values_cid:parameters,
    invocation_bindings_cid:'sha256:5400e202cc7c63c3b757399f3a694b413f7b717ce58aa887cc156c6a39aab67f',
    check_environment_cid:moon.clientProgramEffectEnvironmentCid(prepared),
    grammar_manifest_cid:cid('5'),required_profile_contracts:[],
    barrier_contract_manifest_cid:cid('6'),source_evidence:'unbound',
  });
  const plan = checked(moon.strategyPublicationSeal('compiled_plan',JSON.stringify({
    version:'actql-compiled-plan/0.1',compiler_version:'compiler-test-0.1',
    aoa_ir_version:'aoa-ir-test-0.1',executable_plan_cid:cid('7'),
    program_definition_cid:program,program_semantics_cid:moon.clientProgramEffectSemanticsCid(prepared),
    aoa_contract_cid:cid('8'),aoa_logical_cid:cid('9'),
  }),...bounds));
  const invocation = evidence('prepared_invocation',{
    version:'actql-prepared-invocation/0.1',invocation_template_cid:moon.strategyRunEvidenceIdentity(template),
    compiled_plan_cid:moon.strategyPublicationContractIdentity(plan),execution_context_cid:cid('a'),
    host_policy_cid:cid('b'),policy_decision:'allow',expires_at:'2099-01-01T00:00:00.000Z',
  });
  const authorization = evidence('run_authorization',{
    version:'actql-run-authorization/0.1',prepared_invocation_cid:moon.strategyRunEvidenceIdentity(invocation),
    execution_context_cid:cid('a'),host_policy_cid:cid('b'),decision:'allowed',
  });
  return [template,invocation,authorization,plan];
}

export async function originalCommandKeyFixture({rows = [{id:'one',value:'original'}], inputKey = true} = {}) {
  // Reuse the original independently authored Common Catalog and Program
  // vector, not a rendering of the product's checked output.
  const source = await readFile(new URL('../../../src/query_integration/published_store_capture_wbtest.mbt',import.meta.url),'utf8');
  const literals = [...source.matchAll(/^\s*#\|(.+)$/gmu)].map(match=>JSON.parse(match[1]));
  const environmentBody = literals.find(value=>Array.isArray(value.command_contracts));
  const program = literals.find(value=>value.id==='published-store-capture');
  assert(environmentBody && program);
  const base=JSON.parse(await readFile(new URL('../../../spec/local-check-environment.json',import.meta.url),'utf8'));
  environmentBody.host_policy_profile=base.host_policy_profile;
  delete environmentBody.evidence_bundle_cid;
  environmentBody.evidence_bundle_cid=`sha256:${createHash('sha256').update(canonicalText(environmentBody)).digest('hex')}`;
  program.stages[0].steps[0].values.rows = rows;
  if(inputKey) program.stages[0].effects.save.command.input_key='id';
  const environment = moon.clientProgramCheckEnvironment(canonicalText(environmentBody),
    environmentBody.evidence_bundle_cid,false,false,true,false,false,false,false);
  assert(environment,'original Common environment admitted');
  const outcome = moon.clientProgramPrepareEffectComputationWithParameters(
    JSON.stringify(program),'json',environment,undefined,[]);
  const prepared = moon.clientProgramEffectPreparationReady(outcome);
  assert(prepared,moon.clientProgramEffectPreparationIssueCode(outcome));
  const evidence = publicationEvidence(prepared);
  const admission = moon.clientProgramAdmitEffectPublication(prepared,...evidence);
  assert(admission);
  const definition = checked(moon.strategyIssueRunDefinition(admission,'key-fixture-scope',
    'key-fixture',cid('c'),'2026-09-24T00:00:00.000Z','2027-01-01T00:00:00.000Z',100000,10000,64));
  const bound = moon.clientProgramBindEffectRun(prepared,admission,definition);
  assert(bound);
  const [registry,contracts] = await Promise.all([
    readFile(new URL('../../../spec/dependencies/aoa-pipeline-registry.json',import.meta.url),'utf8'),
    readFile(new URL('../../../spec/contracts/actql-aoa.json',import.meta.url),'utf8'),
  ]);
  const values = JSON.stringify(JSON.parse(contracts).execution_contracts['REL.values']);
  const owned = moon.clientProgramOpenSourceFreeLocalEffectHost(bound,registry,values,1n,0n,0n,0n);
  assert(owned);
  const execution = await runCapturedEffectComputation(owned);
  let inputs;
  try {
    assert.equal(execution.status,'host-tasks-completed');
    inputs=checked(moon.clientProgramPinEffectSources(owned,2));
    const limits=moon.clientProgramEffectInputExportLimits(
      10,1000,10000,100,100,10000,100000,64,100000,
      100000,10000,64,10,10000,100000,10003,66,10,100000,10000,64,4096);
    assert(limits);
    return {prepared,owned,execution,inputs,limits,
      async close(){moon.clientProgramReleaseEffectInputs(inputs);await execution.close();assert.equal(execution.cleanupPending(),false);}};
  } catch(error) {
    if(inputs!==undefined)moon.clientProgramReleaseEffectInputs(inputs);
    await execution.close();throw error;
  }
}
