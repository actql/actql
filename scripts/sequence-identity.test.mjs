import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {sequenceIdentityOracle,retainedSequenceIdentityOracle} from './sequence-identity-oracle.mjs';
import {signatureRoleCid} from './sga-signature-role-identity-oracle.mjs';
const read=path=>JSON.parse(readFileSync(path,'utf8'));
test('Original sequence source keeps its full historical grammar-bound Run',()=>{
 const before=read('scripts/fixtures/pre-sequence-values-identities.json');
 assert.equal(before.source_revision,'7648dfc099f24e819ccaf49376cec57a45c5ea12');
 const after=retainedSequenceIdentityOracle();
 assert.deepEqual(after,read('scripts/fixtures/submitted-sequence-values-identities.json'));
 for(const v of [before,after]) for(const [name,field] of [['template','bound_invocation_template_cid'],['executable','executable_plan_cid'],['compiled','compiled_plan_cid'],['run','run_definition_cid']]) {
  const {[field]:pin,...body}=v.run_preimages[name];assert.equal(signatureRoleCid(body),pin);
 }
 assert.deepEqual(after.values_dependencies,before.values_dependencies);
 assert.deepEqual(after.program_identity,before.program_identity);
});
test('Merged current contracts retain independent expression and query grammar inputs and containing Run preimages',()=>{
 const before=read('scripts/fixtures/pre-current-sequence-values-identities.json');
 assert.equal(before.source_revision,'d879fb93ae19a314c44f5fb8e1fea1461bc3d0d5');
 // This complete authored predecessor stays immutable when current contracts
 // change. Rebuilding it with today's expression contract would reidentify it.
 assert.equal(createHash('sha256').update(readFileSync('scripts/fixtures/pre-current-sequence-values-identities.json')).digest('hex'),
  '120db01f5d88d8e94b6e5d6462e3bf36de72d1816a8f9204172ccad81190909d');
 for(const [part,field] of [['template','bound_invocation_template_cid'],['executable','executable_plan_cid'],['compiled','compiled_plan_cid'],['run','run_definition_cid']]) {
  const {[field]:pin,...body}=before.run_preimages[part];assert.equal(signatureRoleCid(body),pin);
 }
 const current=sequenceIdentityOracle();assert.deepEqual(current,read('scripts/fixtures/current-sequence-values-identities.json'));
 assert.deepEqual(current.grammar,read('spec/manifests/actql-grammar-0.1.json'));
 // This recorded two-contract transition remains bound to its actual Source;
 // later current normative dependencies are checked separately above.
 const source='c6aa9761c5fb941ef98279b8aa483cf4e8ca43b0';
 const historical=path=>JSON.parse(execFileSync('git',['show',`${source}:${path}`],{encoding:'utf8',maxBuffer:4*1024*1024}));
 const after=historical('scripts/fixtures/current-sequence-values-identities.json');
 assert.deepEqual(after.grammar,historical('spec/manifests/actql-grammar-0.1.json'));
 const mutable=new Set(['source_grammar_cid','structural_text_grammar_sha256','structural_text_rules_sha256',
  'expression_contract_cid','expression_text_grammar_sha256',
  'expression_text_rules_sha256','query_text_grammar_sha256','query_text_rules_sha256','grammar_manifest_cid']);
 // Each current normative input is independently selected, not an arbitrary
 // mutable field accepted from the candidate manifest.
 const protocol=historical('spec/contracts/actql-protocol-schemas.json');
 assert.equal(after.grammar.source_grammar_cid,signatureRoleCid(protocol.artifact_schemas.executable_plan.properties.execution_material.properties.program));
 assert.equal(after.grammar.structural_text_grammar_sha256,createHash('sha256').update(execFileSync('git',['show',`${source}:spec/grammar/actql-text-0.1.ebnf`])).digest('hex'));
 assert.equal(after.grammar.structural_text_rules_sha256,createHash('sha256').update(execFileSync('git',['show',`${source}:docs/spec/structural-text.md`])).digest('hex'));
 const retained=grammar=>Object.fromEntries(Object.entries(grammar).filter(([key])=>!mutable.has(key)));
 assert.deepEqual(retained(after.grammar),retained(before.grammar));
 const oldExpression=before.grammar.expression_contract_cid;
 const oldEnvironment='sha256:ebc358ceb6d9c9042afeb1b713f1cd26b6d40e87ec785bdaf9ffc4ff03449935';
 const replaced=new Set([oldExpression,oldEnvironment]);
 assert.deepEqual(after.values_dependencies.contracts,[
  ...before.values_dependencies.contracts.filter(cid=>!replaced.has(cid)),
  signatureRoleCid(historical('spec/contracts/actql-expressions.json')),
  signatureRoleCid(historical('spec/contracts/actql-check-environment.json'))].sort());
 const {expression_contract_cid:oldLocalExpression,...oldLocal}=before.values_dependencies.local;
 const {expression_contract_cid:newLocalExpression,...newLocal}=after.values_dependencies.local;
 assert.equal(oldLocalExpression,oldExpression);
 assert.equal(newLocalExpression,after.grammar.expression_contract_cid);
 assert.deepEqual(newLocal,oldLocal);
 const oldSemantics=structuredClone(before.program_identity.semantics);
 oldSemantics.expression_contract_cid=newLocalExpression;
 oldSemantics.program_template.stages[0].stage_semantics_cid=signatureRoleCid(after.values_dependencies.local);
 assert.deepEqual(after.program_identity.semantics,oldSemantics);
 assert.equal(after.program_identity.semanticsCid,signatureRoleCid(oldSemantics));
 assert.deepEqual(after.program_identity.definition,{...before.program_identity.definition,
  program_semantics_cid:after.program_identity.semanticsCid});
 assert.equal(after.program_identity.programCid,signatureRoleCid(after.program_identity.definition));
 const limits=before.run_preimages.executable.resolved_limits.map(limit=>{
  const {resolved_limit_cid:oldLimitCid,...body}=limit;
  assert.equal(signatureRoleCid(body),oldLimitCid);
  const candidates=body.candidates.map(candidate=>{
   if(candidate.role==='host_ceiling')return candidate;
   assert.equal(candidate.role,'proven_upper_bound');
   const {witness_cid:oldWitness,...witness}=candidate;assert.equal(signatureRoleCid(witness),oldWitness);
   const updated={...witness,dependencies:[after.values_dependencies.proof],source:{...witness.source,
    proof_cid:after.values_dependencies.proof,semantic_ref:`unit:${after.values_dependencies.unit}#/steps/0`}};
   return {...updated,witness_cid:signatureRoleCid(updated)};
  }).sort((a,b)=>a.witness_cid<b.witness_cid?-1:a.witness_cid>b.witness_cid?1:0);
  const updated={...body,candidates,subject_ref:body.subject_ref.replace(before.values_dependencies.unit,after.values_dependencies.unit)};
  return {...updated,resolved_limit_cid:signatureRoleCid(updated)};
 });
 assert.deepEqual(after.run_preimages.executable.resolved_limits,limits);
 assert.notEqual(after.run_preimages.run.run_definition_cid,before.run_preimages.run.run_definition_cid);
});
