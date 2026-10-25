import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {parse} from 'acorn';
import test from 'node:test';
const source=await readFile(new URL('./local-values-plan.mjs',import.meta.url),'utf8');
const ast=parse(source,{ecmaVersion:'latest',sourceType:'module'});
const node=ast.body.find(item=>item.type==='ExportNamedDeclaration' && item.declaration?.id?.name==='sourceFreeValuesPlan').declaration;
const digest=value=>'sha256:'+createHash('sha256').update(JSON.stringify(value)).digest('hex');
function fixture(rows){
  const prepared={},publicationOriginal={},calls=[],admissions=new WeakMap();
  const globals={
    prepareQueryInvocation:()=>undefined,instant:value=>new Date(value).toISOString(),
    randomUUID:()=> 'original-run-id',
    policyCid:name=>digest({version:'actql-installed-local-policy/0.1',name}),
    valuesExecutionContextCid:scope=>digest({version:'actql-installed-local-context/0.1',authority_scope_cid:scope}),
    // Old source calls this and demonstrably refuses the large original.
    valuesHostPolicyOriginal:maxRows=>{if(maxRows>10000)throw new TypeError('InvalidLocalValuesRowLimit');return undefined;},
    bindQueryInvocation:()=>({}),limits:{},
    checkedLocalOutputLimits:(moon,actual,original)=>{assert.equal(actual,prepared);assert.equal(original,publicationOriginal);return {maxRows:rows};},
    localPublicationPlan:options=>Object.freeze(options),valuesAdmissions:admissions,
    retainOriginalPlan:plan=>plan,
  };
  const make=Function(...Object.keys(globals),`return (${source.slice(node.start,node.end)});`)(...Object.values(globals));
  const options={preparedProgram:prepared,publicationOriginal,authorityScopeCid:'scope',namespaceId:'namespace',storeAuthorityCid:'store',now:()=> '2026-10-24T00:00:00Z',
    moon:{clientProgramValuesMaxRows:()=>rows,clientProgramDefinitionCid:()=> 'definition',clientProgramResultCount:()=>1},
    control:{
      prepareCheckedClientCompiledRun(actual,kind,policy){assert.equal(actual,prepared);calls.push(policy);return {admission:{},compiledPlan:{identity:'plan'},preparedEvidence:{wire:'prepared'},authorization:{wire:'authorization'}};},
      defineCheckedClientCompiledRun(compiled,options){return {wire:options.retainedDefinitionWire ?? JSON.stringify({created_at:options.createdAt,valid_until:options.validUntil})};},
      issueCheckedClientCompiledInvocation:()=>({observation:{},invocation:{}}),
    }};
  return {make,options,calls,admissions};
}
test('large original Values demand uses the existing policy identity across retained definition replay',()=>{
  const f=fixture(100000),first=f.make(f.options);
  const second=f.make({...f.options,retainedDefinitionWire:first.runDefinition.wire});
  const expectedPolicy=digest({version:'actql-installed-local-policy/0.1',name:'source-free-values'});
  assert.equal(f.calls.length,2);
  assert.equal(f.calls[0].hostPolicyCid,expectedPolicy);
  assert.deepEqual(f.calls[1],f.calls[0]);
  assert.equal(second.runDefinition.wire,first.runDefinition.wire);
  assert.equal(first.outputLimits.maxRows,100000);
  assert.equal(Object.hasOwn(f.admissions.get(first),'valuesHostPolicyOriginal'),false);
});
test('original publication owner remains required, independent of row count',()=>{
  const f=fixture(121);
  assert.throws(()=>f.make({...f.options,publicationOriginal:{}}),assert.AssertionError);
  const plan=f.make(f.options);
  assert.equal(plan.outputLimits.maxRows,121);
});
