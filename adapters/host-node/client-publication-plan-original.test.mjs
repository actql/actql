import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
import {checkedLocalOutputLimits, acquiredMultiTaskPublicationPlan, acquiredKeyedTaskPublicationPlan, localOutputLimits} from './local-values-plan.mjs';
import {resultOutputLimitFields} from '../host-common/result-output-limits.mjs';

function originalGetter(record) {
 const source=readFileSync(new URL('./embedded-local.mjs',import.meta.url),'utf8');
 const ast=parse(source,{ecmaVersion:'latest',sourceType:'module'});
 let selected;
 function walk(node){if(!node||typeof node!=='object')return;if(node.type==='Property'&&node.key?.name==='managedComputePublicationOriginal')selected=node.value;for(const value of Object.values(node)){if(Array.isArray(value))value.forEach(walk);else if(value&&typeof value==='object')walk(value);}}
 walk(ast);assert(selected);
 const request={};
 return new Function('record','clientOperationError','moon','sourceManaged','computeManaged','originals','originalSourceManagedHostRequest',`return function(runtime,prepared)${source.slice(selected.body.start,selected.body.end)}`)(record,code=>Object.assign(new Error(code),{code}), [...record.computeRuns.values()][0].runtime,undefined,undefined,{},()=>request);
}

test('publication reads the same original before admission and after its move to the live Run',()=>{
 const runtime={},prepared={},original={},live={};
 const proof={};
 const run={runtime,prepared,closed:false,preparedSequences:original,manager:{authoringContextOriginal(actual){assert.strictEqual(actual,prepared);return proof;}}};
 const record={computeRuns:new Map([[prepared,run]])},get=originalGetter(record);
 const before=get(runtime,prepared);assert.equal(before.kind,'preparation');assert.strictEqual(before.value,original);assert.strictEqual(before.authoringContext,proof);
 run.value=live;run.preparedSequences=undefined;
 const after=get(runtime,prepared);assert.equal(after.kind,'installed_run');assert.strictEqual(after.value,live);assert.strictEqual(after.authoringContext,proof);
 assert.equal(record.computeRuns.size,1);assert.equal(run.preparedSequences,undefined);
 run.closed=true;assert.throws(()=>get(runtime,prepared),{code:'NodeManagedRunRuntimeUnavailable'});
 run.closed=false;assert.throws(()=>get({},prepared),{code:'NodeManagedRunRuntimeUnavailable'});
 const read=run.manager.authoringContextOriginal;run.manager.authoringContextOriginal=()=>{run.closed=true;return proof;};
 assert.throws(()=>get(runtime,prepared),{code:'NodeManagedRunRuntimeUnavailable'});
 run.closed=false;run.manager.authoringContextOriginal=read;
 run.value=undefined;assert.throws(()=>get(runtime,prepared),{code:'NodeManagedRunRuntimeUnavailable'});
 assert.equal(get(runtime,{}),undefined); // No original belongs to an unrelated Program.
});

test('publication phase dispatch preserves nominal owners and rejects invalid projection instead of legacy fallback',()=>{
 const prepared={},original={},live={},calls=[];
 const vector=resultOutputLimitFields.map(()=>1);
 const moon={
  clientProgramPreparedLocalPublicationLimits:(...args)=>{calls.push(['preparation',...args]);return vector;},
  clientProgramInstalledManagedPublicationLimits:(...args)=>{calls.push(['installed',...args]);return vector;},
 };
 checkedLocalOutputLimits(moon,prepared,{kind:'preparation',value:original});
 checkedLocalOutputLimits(moon,prepared,{kind:'installed_run',value:live});
 assert.throws(()=>checkedLocalOutputLimits(moon,prepared),/InvalidCheckedLocalPublicationOriginal/);
 assert.strictEqual(calls[0][1],original);assert.strictEqual(calls[0][2],prepared);
 assert.strictEqual(calls[1][1],live);assert.strictEqual(calls[1][2],prepared);
 assert.deepEqual(calls.map(c=>c[0]),['preparation','installed']);
 moon.clientProgramInstalledManagedPublicationLimits=()=>[];
 assert.throws(()=>checkedLocalOutputLimits(moon,prepared,{kind:'installed_run',value:live}),/InvalidCheckedLocalPublicationLimits/);
 assert.equal(calls.length,2);
 assert.throws(()=>checkedLocalOutputLimits(moon,prepared,{kind:'other',value:live}),/InvalidCheckedLocalPublicationOriginal/);
});

// Execute the actual dispatch arguments and plan-builder bodies. Core, Source
// and invocation ports are explicit; no physical publication is claimed here.
function capturedPublicationFixture(kind, mode = 'managed') {
  const prepared = {}, live = {}, compiled = {}, definition = {}, evidence = [{}, {}];
  const request = {};
  const acquired = {compiled, runDefinition: definition, compiledPlan: {identity: 'compiled'}, createdAt: 'start',
    requestIdentity: request, publicationPreparation: mode === 'legacy' ? undefined : live};
  const captures = [0, 1].map(index => ({logicalInput: {}, identity: {}, requirement: {},
    checkedSource: {}, capture: {source: () => index}}));
  const vector = resultOutputLimitFields.map((name, index) => index + 128);
  const seen = {limits: 0, publication: 0};
  const foreign = Error('OriginalPublicationOwnerRefusal');
  const moon = {
    clientProgramPublicationDataPolicyCid: original => {assert.equal(original, prepared); return 'policy';},
    clientProgramCapturedSourceMatches: original => original === prepared,
    clientProgramCapturedTaskSourceMatches: original => original === prepared,
    clientProgramCapturedSourceLogicalCid: identity => captures.findIndex(value => value.identity === identity),
    clientProgramDefinitionCid: original => {assert.equal(original, prepared); return 'program';},
    clientProgramResultCount: original => {assert.equal(original, prepared); return 0;},
    clientProgramInstalledManagedPublicationLimits(original, program) {
      seen.limits++;
      assert.equal(original, live); assert.equal(program, prepared);
      if (mode === 'foreign') throw foreign;
      return mode === 'malformed' ? [] : vector;
    },
  };
  const control = {
    issueProgramInitialRetention(owner, program, actualRequest) {
      assert.strictEqual(owner, live); assert.strictEqual(program, prepared);
      assert.strictEqual(actualRequest, request); return {};
    },
    seal: () => ({}), // Existing complete standalone path, not managed admission.
    preparedClientNormalizationEvidence() { seen.publication++; return {}; },
    preparedClientAuthoringContextEvidence: () => ({}),
    checkClientCompiledRunOwner(original, program) {assert.equal(original, compiled); assert.equal(program, prepared);},
    issueCheckedClientCompiledInvocation(original, run, fields, _limits, _owner, program) {
      assert.equal(original, compiled); assert.equal(run, definition); assert.equal(program, prepared);
      assert.equal(fields.dataPolicyCid, 'policy'); return {observation: {}, invocation: {}};
    },
    keyedLookupPublicationEvidence(original) {assert.equal(original, evidence[1]); return {logicalRelationCid: 'right', source: evidence[1]};},
  };
  const name = kind === 'multi' ? 'acquiredMultiTaskPublicationPlan' : 'acquiredKeyedTaskPublicationPlan';
  const build = kind === 'multi' ? acquiredMultiTaskPublicationPlan : acquiredKeyedTaskPublicationPlan;

  const dispatch = readFileSync(new URL('./client-dispatch-owner.mjs', import.meta.url), 'utf8');
  const calls = [];
  function walk(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'CallExpression' && node.callee.type === 'Identifier' && node.callee.name === name) calls.push(node);
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(walk); else if (value && typeof value === 'object') walk(value);
    }
  }
  walk(parse(dispatch, {ecmaVersion: 'latest', sourceType: 'module'})); assert.equal(calls.length, 1);
  const managedRun = mode === 'legacy' ? undefined : live;
  const context = {moon, control, acquired, preparedProgram: prepared, managedRun,
    held: {plan: acquired, managedRun}, sources: captures.map((captured, index) => ({captured, sourceEvidence: evidence[index]})),
    captured: captures[0], sourceEvidence: evidence[0], keyedObservation: {observation: evidence[1]},
    authorityScopeCid: 'authority', effectiveDataPolicyCid: 'policy', captureStartedAt: 'start', captureCompletedAt: 'end',
    namespaceId: 'namespace', storeAuthorityCid: 'store', now: () => 'end', [name]: build};
  // Source wiring only: the caller's installed-run value must be the SAME
  // expression tested for absence. Runtime behavior below uses actual imports.
  const original = calls[0].arguments[0].properties.find(p => p.key?.name === 'publicationOriginal')?.value;
  assert.equal(original?.type, 'ConditionalExpression');
  const selected = original.alternate.properties.find(p => p.key?.name === 'value')?.value;
  assert.equal(dispatch.slice(selected.start, selected.end), dispatch.slice(original.test.left.start, original.test.left.end));
  return {run: () => build({...context,
    publicationOriginal: managedRun === undefined ? undefined : {kind: 'installed_run', value: managedRun},
    now: () => '2026-11-19T00:00:00.000Z'}), seen, vector, foreign};
}

for (const kind of ['multi', 'keyed']) {
  test(`${kind} Source dispatch preserves checked same-Run output limits and rejects invalid originals`, () => {
    const original = capturedPublicationFixture(kind);
    const plan = original.run();
    assert.deepEqual(plan.outputLimits, Object.fromEntries(resultOutputLimitFields.map((name, index) => [name, original.vector[index]])));
    assert.deepEqual(original.seen, {limits: 1, publication: 1});
    const malformed = capturedPublicationFixture(kind, 'malformed');
    assert.throws(malformed.run, /InvalidCheckedLocalPublicationLimits/);
    assert.deepEqual(malformed.seen, {limits: 1, publication: 0});
    const foreign = capturedPublicationFixture(kind, 'foreign');
    assert.throws(foreign.run, error => error === foreign.foreign);
    assert.deepEqual(foreign.seen, {limits: 1, publication: 0});
    const legacy = capturedPublicationFixture(kind, 'legacy');
    assert.deepEqual(legacy.run().outputLimits, localOutputLimits);
    assert.deepEqual(legacy.seen, {limits: 0, publication: 1});
  });
}
