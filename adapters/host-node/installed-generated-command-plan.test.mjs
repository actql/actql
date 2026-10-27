import {ledgerUsageFields} from './ledger-contract.generated.mjs';
// Required integration regression: an authentic generation barrier must be
// compiled inside the same checked Effect Program, not rewritten to a Source
// supplying an already issued ContentRef. Physical acceptance is separate.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {inspect} from 'node:util';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {canonical} from './fixtures/file-listing-source.fixture.mjs';
import {contentCommandFixture, generatedContentCommandProgram}
  from './fixtures/content-command.fixture.mjs';

const familyRegistry = await readFile(new URL(
  '../../spec/dependencies/aoa-pipeline-registry.json', import.meta.url), 'utf8');
const familyContracts = JSON.parse(await readFile(new URL(
  '../../spec/contracts/actql-aoa.json', import.meta.url), 'utf8')).execution_contracts;
const familyValues = JSON.stringify(familyContracts['REL.values']);
const familyFragment = JSON.stringify(familyContracts['ACTQL.expression_fragment/0.1']);
const familyOrdered = JSON.stringify(familyContracts['REL.derive.ordered']);

test('original generated COMMAND sizes its actual installed Content family before I/O', async () => {
  const fixture = contentCommandFixture({contentMime: 'text/csv', inputMime: 'text/csv'});
  const prepared = moon.clientProgramEffectPreparationReady(
    moon.clientProgramPrepareEffectComputationWithParameters(
      canonical(generatedContentCommandProgram()), 'json', fixture.environment, undefined, []));
  assert.ok(prepared);
  // Independent finite diagnostic ceilings. These are installed port limits,
  // not sampled row/byte counts or synthetic Source completion evidence.
  const exported = moon.clientProgramEffectInputExportLimits(
    16, 10000, 10000, 1000, 2, 1000, 10000, 64, 100000,
    10000, 1000, 64, 16, 10000, 10000, 1000, 64,
    16, 10000, 1000, 64, 128);
  assert.ok(exported);
  const workspace = moon.clientProgramContentStepWorkspace(
    32, 1000, 64, 100, 10000, 16384, 256, 32,
    100000, 10000, 100, exported);
  assert.ok(workspace);
  let opens = 0, stops = 0, closes = 0;
  const provider = moon.clientProgramEffectContentLocalProvider(
    prepared, 1, 2, familyRegistry, familyValues,
    familyFragment, familyOrdered, workspace,
    () => { stops++; return true; }, () => true,
    () => { closes++; return true; }, () => { opens++; return true; });
  assert.ok(provider);
  const budget = moon.clientProgramEffectContentLedgerLimits(prepared,
    familyRegistry, familyValues, familyFragment, familyOrdered, provider);
  assert.ok(budget);
  assert.equal(budget.attempts, 2, 'acquisition and original consumer; no prefix attempt');
  assert.equal(budget.holdings, 2);
  assert.ok(budget.retained_bytes > 0n);
  assert.ok(budget.execution_bytes > 0n);
  assert.deepEqual([opens, stops, closes], [0, 0, 0]);
  const requirement = checked(moon.clientProgramEffectPrepareLocalQueryRequirement(
    prepared, 0, 0, familyRegistry, familyValues, familyFragment, familyOrdered));
  const [queryContract, evidenceContract] = await Promise.all([
    'actql-query-acquisition.json', 'actql-query-process-evidence.json',
  ].map(name => readFile(new URL(`../../spec/contracts/${name}`, import.meta.url), 'utf8')));
  const acquisition = checked(moon.clientProgramRowSourcePrepareAcquisition(
    fixture.declaration, requirement, queryContract, evidenceContract, undefined));
  const captureCapacity = moon.clientProgramInstalledRowCaptureCapacity(acquisition);
  assert.ok(captureCapacity);
  const ledger = moon.clientProgramPrepareContentEffectCaptureLedger(prepared,
    captureCapacity, 1024n, 1024n, familyRegistry, familyValues,
    familyFragment, familyOrdered, provider);
  assert.ok(ledger, 'the original checked acquisition and Content task share a sized ledger');
  // Existing projection: planning, attempts, holdings, transferred, reserved
  // transfer, held, reserved retention, reserved execution, uncertain transfer.
  assert.deepEqual(moon.clientProgramMultiCapturedLedgerUsage(ledger), Array(ledgerUsageFields.length).fill(0n),
    'neither capacity preparation nor ledger creation starts or reserves a task');
  for (const [transfer, scratch] of [[-1n, 1024n], [1024n, -1n],
    [1024n, 9223372036854775807n]]) {
    assert.equal(moon.clientProgramPrepareContentEffectCaptureLedger(prepared,
      captureCapacity, transfer, scratch, familyRegistry, familyValues,
      familyFragment, familyOrdered, provider), undefined,
    'invalid or overflowing physical allowances refuse before Source I/O');
  }
  const foreign = moon.clientProgramEffectPreparationReady(
    moon.clientProgramPrepareEffectComputationWithParameters(
      canonical(generatedContentCommandProgram()), 'json', fixture.environment, undefined, []));
  assert.equal(moon.clientProgramEffectContentLedgerLimits(foreign,
    familyRegistry, familyValues, familyFragment, familyOrdered, provider), undefined,
  'a family of another checked owner cannot size this original task');
  assert.equal(moon.clientProgramEffectContentLocalProvider(prepared, 1, 3,
    familyRegistry, familyValues, familyFragment, familyOrdered,
    workspace, () => true, () => true, () => true, () => true), undefined,
  'the JOIN coordinate is not a generation occurrence');
});

test('generated SERIALIZE Content COMMAND compiles its original checked producer and destination dependencies', () => {
  const fixture = contentCommandFixture({contentMime: 'text/csv', inputMime: 'text/csv'});
  const program = generatedContentCommandProgram();
  const preparedOutcome = moon.clientProgramPrepareEffectComputationWithParameters(
    canonical(program), 'json', fixture.environment, undefined, []);
  const prepared = moon.clientProgramEffectPreparationReady(preparedOutcome);
  assert.ok(prepared, inspect(moon.clientProgramEffectPreparationIssue(preparedOutcome), {depth: 16}));
  assert.deepEqual(moon.clientProgramEffectSerializationOccurrences(prepared), [{_0: 1, _1: 2}]);
  let compilation;
  try { compilation = checked(moon.clientProgramCompileLocalEffects(prepared)); }
  catch (error) { assert.fail(inspect(error.cause, {depth: 16})); }
  const plan = JSON.parse(moon.clientProgramEffectCompilationPlanWire(compilation));
  assert.deepEqual(plan.execution_material.program, program,
    'the same Program retains SERIALIZE and COMMAND; no preissued-Ref substitute');
  assert.deepEqual(moon.clientProgramEffectCompilationResultNames(compilation), ['r']);
  assert.deepEqual(plan.nodes.filter(node => node.node_id.startsWith('task_'))
    .map(node => [node.node_id, node.kind]), [
    ['task_0', 'aoa_fragment'],
    ['task_1_before_serialize_2', 'aoa_fragment'],
    ['task_1_serialize_2', 'content_barrier'],
    ['task_1_after_serialize_3', 'aoa_fragment'],
  ]);
  assert.deepEqual(plan.data_edges.filter(edge => edge.to.node_id.startsWith('task_'))
    .map(edge => [edge.from.node_id, edge.from.port, edge.to.node_id, edge.to.port]), [
    ['task_0', 'select_1', 'task_1_before_serialize_2', 'transfers'],
    ['task_0', 'select_1', 'task_1_after_serialize_3', 'input_1'],
    // The prefix exports the barrier's checked input schema at its selected
    // coordinate. Its port is serialize_2; it contains no serializer execution.
    ['task_1_before_serialize_2', 'serialize_2', 'task_1_serialize_2', 'input_0'],
    ['task_1_serialize_2', 'serialize_2', 'task_1_after_serialize_3', 'input_0'],
  ], 'the authentic original destination and generated Content reach distinct JOIN ports');
  assert.deepEqual(plan.root_refs.filter(root => root.role === 'effect_result'), [{
    name: 'upload', role: 'effect_result',
    ref: {node_id: 'task_1_after_serialize_3', port: 'join_3'},
  }]);
  assert.deepEqual(plan.required_profiles.map(profile => profile.profile_id), ['actql-content/0.1']);
  const barrier = plan.nodes.find(node => node.kind === 'content_barrier').barrier;
  assert.deepEqual(barrier.serialization.bounds, {max_bytes: 32, max_rows: 1});
  assert.ok(!JSON.stringify(plan.nodes).includes('REL.serialize'),
    'generation is not recast as a pure Relation operator');
});

for (const preserveOrder of [false, true]) {
test(`additional intermediate SERIALIZE Result retains one generation and its checked public roots (${preserveOrder ? 'PRESERVE ORDER' : 'ORDER BY'})`, () => {
  const fixture = contentCommandFixture({contentMime: 'text/csv', inputMime: 'text/csv'});
  const program = generatedContentCommandProgram({preserveOrder});
  const task = preserveOrder ? 4 : 3;
  const step = preserveOrder ? 3 : 2;
  program.stages[1].results.attachment = {from: 'attachment',
    fields: ['name', 'content', 'media_type', 'size_bytes', 'row_count']};
  program.results.attachment = {from: {stage: 'save', result: 'attachment'}};
  const preparedOutcome = moon.clientProgramPrepareEffectComputationWithParameters(
    canonical(program), 'json', fixture.environment, undefined, []);
  const prepared = moon.clientProgramEffectPreparationReady(preparedOutcome);
  assert.ok(prepared, inspect(moon.clientProgramEffectPreparationIssue(preparedOutcome), {depth: 16}));
  assert.deepEqual(moon.clientProgramEffectSerializationOccurrences(prepared), [{_0: task, _1: step}],
    'the retained intermediate has one generation task; acquisition remains one');
  const outcome = moon.clientProgramCompileLocalEffects(prepared);
  assert.equal(outcome.$tag, 1, inspect(outcome, {depth: 12}));
  const compilation = checked(outcome);
  const plan = JSON.parse(moon.clientProgramEffectCompilationPlanWire(compilation));
  assert.equal(plan.nodes.filter(node => node.kind === 'content_barrier').length, 1);
  assert.deepEqual([...moon.clientProgramEffectCompilationResultNames(compilation)].sort(),
    ['attachment', 'r']);
  const attachment = plan.root_refs.find(root =>
    root.role === 'requested_result' && root.name === 'attachment');
  assert.ok(attachment);
  assert.deepEqual(attachment.ref,
    {node_id: `task_${task}_serialize_${step}`, port: `serialize_${step}`},
    'the full five-field Result exposes the exact retained generation, not its sort or terminal JOIN');
  assert.equal(plan.nodes.find(node => node.node_id === attachment.ref.node_id).kind,
    'content_barrier');
  assert.deepEqual(plan.root_refs.filter(root => root.role === 'effect_result'), [{
    name: 'upload', role: 'effect_result',
    ref: {node_id: `task_${task + 1}`, port: `join_${step + 1}`},
  }], 'the COMMAND still consumes its original destination-bound terminal');
  const exported = moon.clientProgramEffectInputExportLimits(
    16, 10000, 10000, 1000, 2, 1000, 10000, 64, 100000,
    10000, 1000, 64, 16, 10000, 10000, 1000, 64,
    16, 10000, 1000, 64, 128);
  const workspace = moon.clientProgramContentStepWorkspace(
    32, 1000, 64, 100, 10000, 16384, 256, 32,
    100000, 10000, 100, exported);
  assert.ok(workspace);
  const provider = moon.clientProgramEffectContentLocalProvider(
    prepared, task, step, familyRegistry, familyValues, familyFragment,
    familyOrdered, workspace, () => true, () => true, () => true, () => true);
  assert.ok(provider, 'the retained generation has its exact installed provider');
  const budget = moon.clientProgramEffectContentLedgerLimits(prepared,
    familyRegistry, familyValues, familyFragment, familyOrdered, provider);
  assert.ok(budget, 'every selected task and retained input is admitted before Source I/O');
  assert.equal(budget.attempts, task + 2);
  assert.equal(budget.holdings, task + 2);
});
}

test('generated COMMAND Content borrows the original allowed Effect admission without issuing another Run', () => {
  const fixture = contentCommandFixture({contentMime: 'text/csv', inputMime: 'text/csv'});
  const prepared = moon.clientProgramEffectPreparationReady(
    moon.clientProgramPrepareEffectComputationWithParameters(
      canonical(generatedContentCommandProgram()), 'json', fixture.environment, undefined, []));
  assert.ok(prepared);
  const compilation = checked(moon.clientProgramCompileLocalEffects(prepared));
  const allowed = checked(moon.clientProgramIssueAllowedEffectRun(compilation,
    `sha256:${'a'.repeat(64)}`, `sha256:${'b'.repeat(64)}`, '2026-10-11T00:00:00.000Z'));
  const definition = checked(moon.clientProgramIssueEffectRunDefinition(allowed,
    'content-command-scope', 'original-generated-command',
    '2026-10-10T00:00:00.000Z', '2026-10-11T00:00:00.000Z'));
  const compiled = checked(moon.clientProgramEffectAllowedSerializationRun(allowed));
  assert.equal(moon.clientProgramCompiledRunPrepared(compiled),
    moon.clientProgramAllowedEffectRunPrepared(allowed));
  assert.equal(moon.clientProgramCompiledRunAuthorization(compiled),
    moon.clientProgramAllowedEffectRunAuthorization(allowed));
  assert.equal(moon.clientProgramCompiledRunAdmission(compiled),
    moon.clientProgramAllowedEffectRunAdmission(allowed));
  assert.equal(moon.clientProgramCheckCompiledRunDefinition(compiled, definition), true);
  const control = runtimeCore(moon).publicationControl;
  const limits = {maxWireBytes: 1000000, maxNodes: 100000, maxDepth: 100};
  const admittedDefinition = control.admit('run_definition',
    moon.strategyPublicationContractJson(definition), limits);
  const installed = control.adoptCheckedClientEffectSerializationRun(allowed, admittedDefinition);
  assert.equal(installed.kind, 'serialization');
  assert.equal(installed.preparedEvidence.identity,
    moon.strategyRunEvidenceIdentity(moon.clientProgramAllowedEffectRunPrepared(allowed)));
  assert.equal(installed.authorization.identity,
    moon.strategyRunEvidenceIdentity(moon.clientProgramAllowedEffectRunAuthorization(allowed)));
  const selected = control.compiledSerializationGraph(installed);
  assert.deepEqual({task: selected.task, step: selected.step}, {task: 1, step: 2});
  assert.equal(selected.wire, moon.clientProgramSerializationPlanGraphWire(
    moon.clientProgramCompiledRunSerializationGraph(compiled)));
  assert.throws(() => control.compiledSerializationGraph({...installed}),
    {name: 'TypeError', message: 'Foreign Client compiled Content Run'});
  assert.equal(moon.clientProgramCompiledRunHasSerialization(compiled), true);
  const component = moon.clientProgramCompiledRunSerializationGraph(compiled);
  assert.ok(component);
  const graph = JSON.parse(moon.clientProgramSerializationPlanGraphWire(component));
  const barrier = graph.nodes.find(node => node.kind === 'content_barrier').barrier;
  assert.equal(moon.clientProgramSerializationPolicyBody(compiled)._1,
    barrier.effective_output_data_policy_cid);
  const store = `sha256:${'c'.repeat(64)}`;
  const holding = checked(moon.clientProgramSerializationByteHoldingCid(compiled, definition, store));
  assert.match(holding, /^sha256:[0-9a-f]{64}$/u);
  assert.equal(checked(moon.clientProgramSerializationByteHoldingCid(compiled, definition, store)), holding);
  const foreignDefinition = checked(moon.clientProgramIssueEffectRunDefinition(allowed,
    'content-command-scope', 'another-generated-command',
    '2026-10-10T00:00:00.000Z', '2026-10-11T00:00:00.000Z'));
  // A compilation can instantiate distinct Runs; each byte custody identity
  // stays bound to its own Definition rather than just the Content Plan.
  assert.notEqual(checked(moon.clientProgramSerializationByteHoldingCid(compiled, foreignDefinition, store)), holding);
  assert.throws(() => checked(moon.clientProgramEffectAllowedInferRun(allowed)),
    'a Content component does not invent a Model consumer');

  const plainPrepared = moon.clientProgramEffectPreparationReady(
    moon.clientProgramPrepareEffectComputationWithParameters(
      canonical(fixture.program), 'json', fixture.environment, undefined, []));
  const plainAllowed = checked(moon.clientProgramIssueAllowedEffectRun(
    checked(moon.clientProgramCompileLocalEffects(plainPrepared)),
    `sha256:${'a'.repeat(64)}`, `sha256:${'b'.repeat(64)}`, '2026-10-11T00:00:00.000Z'));
  assert.deepEqual(moon.clientProgramEffectSerializationOccurrences(plainPrepared), []);
  assert.throws(() => checked(moon.clientProgramEffectAllowedSerializationRun(plainAllowed)),
    'a Source-issued Ref is not a generated Content component');
  const plainDefinition = checked(moon.clientProgramIssueEffectRunDefinition(plainAllowed,
    'content-command-scope', 'plain-command',
    '2026-10-10T00:00:00.000Z', '2026-10-11T00:00:00.000Z'));
  const plainAdmittedDefinition = control.admit('run_definition',
    moon.strategyPublicationContractJson(plainDefinition), limits);
  assert.throws(() => control.adoptCheckedClientEffectSerializationRun(allowed,
    plainAdmittedDefinition),
  {name: 'TypeError', message: 'Effect Content Run Definition differs from admission'});
});

test('generated COMMAND resolves omitted author bounds from admitted Host policy and only tightens them', async () => {
  const hostCeilings = {max_artifact_rows: 3, max_artifact_bytes: 24};
  const base = JSON.parse(await readFile(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8'));
  base.host_policy_profile.capacity = {...base.host_policy_profile.capacity, ...hostCeilings};
  // The fixture issues a new environment identity from this independent Host
  // configuration, not from an observed compiler result.
  const fixture = contentCommandFixture({contentMime: 'text/csv', inputMime: 'text/csv',
    baseEnvironmentWire: canonical(base)});
  for (const [author, expected] of [
    [undefined, {max_rows: 3, max_bytes: 24}],
    [{max_rows: 1, max_bytes: 12}, {max_rows: 1, max_bytes: 12}],
    [{max_rows: 9, max_bytes: 32}, {max_rows: 3, max_bytes: 24}],
  ]) {
    const program = generatedContentCommandProgram();
    const options = program.stages[1].steps.find(step => step.serialize).serialize;
    if (author === undefined) delete options.bounds;
    else options.bounds = author;
    const outcome = moon.clientProgramPrepareEffectComputationWithParameters(
      canonical(program), 'json', fixture.environment, undefined, []);
    const prepared = moon.clientProgramEffectPreparationReady(outcome);
    assert.ok(prepared, inspect(moon.clientProgramEffectPreparationIssue(outcome), {depth: 12}));
    const compilation = checked(moon.clientProgramCompileLocalEffects(prepared));
    const plan = JSON.parse(moon.clientProgramEffectCompilationPlanWire(compilation));
    assert.deepEqual(plan.nodes.find(node => node.kind === 'content_barrier')
      .barrier.serialization.bounds, expected);
  }
});
