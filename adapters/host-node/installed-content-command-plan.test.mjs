// Real checked Source/Catalog/Command compilation. This is not physical
// capture, approval, dispatch, recovery or a public COMMAND acceptance claim.
import assert from 'node:assert/strict';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {inspect} from 'node:util';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../host-common/runtime-result.mjs';
import {rowSourceCheckEnvironment} from './installed-row-source.mjs';
import {createInstalledRowEffect, installedRowEffectDescriptors} from './installed-row-effect.mjs';
import {composeInstalledEffects, installedEffectFor} from './installed-effect-inventory.mjs';
import {canonical, cid} from './fixtures/file-listing-source.fixture.mjs';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {contentCommandFixture} from './fixtures/content-command.fixture.mjs';
import {createInstalledLoaderParent} from './fixtures/installed-loader-parent.fixture.mjs';

const baseWire = await readFile(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8');

test('checked Content COMMAND compiles with its original Catalog and Result root', () => {
  const {program, environment, command} = contentCommandFixture();
  const outcome = moon.clientProgramPrepareEffectComputationWithParameters(
    JSON.stringify(program), 'json', environment, undefined, []);
  const prepared = moon.clientProgramEffectPreparationReady(outcome);
  assert.ok(prepared, inspect(moon.clientProgramEffectPreparationIssue(outcome), {depth: 8}));
  let compilation;
  try { compilation = checked(moon.clientProgramCompileLocalEffects(prepared)); }
  catch (error) { assert.fail(inspect(error.cause, {depth: 8})); }
  const material = JSON.parse(moon.clientProgramEffectCompilationPlanWire(compilation));
  assert.deepEqual(material.execution_material.program.stages[1].effects,
    program.stages[1].effects);
  assert.equal(Object.hasOwn(command, 'minimum_approval'), false);
  assert.deepEqual(moon.clientProgramEffectCompilationResultNames(compilation), ['r']);
  const descriptor = checked(moon.clientProgramEffectMemberDescriptor(prepared, 1, 'upload', 2));
  assert.deepEqual([descriptor._0, descriptor._1, descriptor._2, descriptor._3,
    descriptor._4, descriptor._5, descriptor._6, descriptor._7, descriptor._8],
  [0, 'upload', 'command', 'file', command.command_id, command.contract_cid, 'r', 'halt', undefined]);
  assert.throws(() => checked(moon.clientProgramEffectMemberDescriptor(prepared, 1, 'upload', 1)),
    error => moon.clientProgramEffectMemberDescriptorIssueCode(error.cause) === 'WorkLimit');
  assert.throws(() => checked(moon.clientProgramEffectMemberDescriptor(prepared, 0, 'upload', 16)),
    error => moon.clientProgramEffectMemberDescriptorIssueCode(error.cause) === 'InvalidMember');
  assert.equal(checked(moon.clientProgramEffectPlanCid(prepared, 0, 2, 16, 4096, 128, 12)),
    undefined, 'a Command is not assigned a synthetic Mapping Plan');
  assert.deepEqual(installedRowEffectDescriptors(moon, prepared, compilation), [{
    effectId: 'upload', kind: 'command', target: 'file',
    commandRef: command.command_id, commandCid: command.contract_cid,
  }]);
});

test('structured Content COMMAND check closes only visible valid static Effects', () => {
  const fixture = contentCommandFixture();
  const aliases = fixture.declared.views.map(view => ({name: 'files.transfers',
    sourceRef: view.source_ref, sourceViewContractCid: view.view_cid,
    schemaContractCid: view.carrier_schema_cid}));
  const observe = (program, visible = aliases, environment = fixture.environment) =>
    JSON.parse(moon.clientProgramCheckProgram(canonical(program), environment,
      canonical({environmentCid: moon.clientProgramCheckingEnvironmentCid(environment),
        aliases: visible}), undefined, `ctx:${'1'.repeat(64)}`, `rev:${'2'.repeat(64)}`,
      undefined, `corr:${'3'.repeat(32)}`, 'bound_input', undefined));
  const report = observe(fixture.program);
  assert.equal(report.outcome, 'completed');
  assert.equal(report.report.verdict, 'verified');
  assert.deepEqual(report.report.coverage, {limits: [], unresolved: []});
  for (const fault of ['unknown_command', 'incompatible_input']) {
    const program = structuredClone(fixture.program);
    const command = program.stages[1].effects.upload.command;
    if (fault === 'unknown_command') command.contract = 'command:files.undeclared.v1';
    else command.input.name = 7;
    const refused = observe(program);
    assert.equal(refused.outcome, 'completed');
    assert.notEqual(refused.report.verdict, 'verified', fault);
    assert.ok(refused.report.coverage.limits.length > 0 || refused.report.reasons.length > 0,
      'a failed closure retains the existing refusal instead of claiming verification');
  }
  const hidden = observe(fixture.program, []);
  assert.equal(hidden.report.verdict, 'undetermined');
  assert.deepEqual(hidden.report.coverage.unresolved,
    [{boundary: 'source_resolution', reason: 'unresolved_protected'}]);
  assert.deepEqual(hidden.report.reasons, [], 'protected Effect inputs are not disclosed');
});

test('checked Content COMMAND selects only its published original installation contract', async t => {
  const {program, environment, environmentWire, command} = contentCommandFixture();
  const prepared = moon.clientProgramEffectPreparationReady(
    moon.clientProgramPrepareEffectComputationWithParameters(
      JSON.stringify(program), 'json', environment, undefined, []));
  assert.ok(prepared);
  const compilation = checked(moon.clientProgramCompileLocalEffects(prepared));
  const descriptors = installedRowEffectDescriptors(moon, prepared, compilation);
  const selector = descriptors[0];
  let closes = 0;
  const owner = Object.freeze({environmentWire,
    effectSelectors: Object.freeze([Object.freeze({...selector})]),
    async close() { closes += 1; }});
  // This metadata owner supplies no physical Source or Command acceptance.
  // Its Environment composition still uses the actual initial Resource and
  // the same nominal Source services as an installed Host.
  const root = await mkdtemp(join(tmpdir(), 'actql-command-composition-'));
  const parent = createInstalledLoaderParent({root, moon});
  t.after(async () => {await parent.close(); await rm(root, {recursive: true, force: true});});
  parent.open();
  const options = {moon, baseEnvironmentWire: baseWire.trimEnd()};
  const compose = value => parent.load((paths, captured) =>
    composeInstalledEffects(paths, captured,
      async (_path, _options, retain) => { retain(value); return value; }),
  ['/fixture-command'], options);
  let inventory;
  try { inventory = await compose(owner); }
  catch (error) { assert.fail(inspect(error, {depth: 8})); }
  assert.equal(installedEffectFor(inventory, descriptors), owner);
  for (const fault of [{commandCid: `sha256:${'a'.repeat(64)}`},
    {commandRef: 'command:files.other.v1'}, {target: 'folder'},
    {mappingRef: 'mapping:files.upload.v1', mappingCid: command.contract_cid}]) {
    assert.throws(() => installedEffectFor(inventory, [{...selector, ...fault}]),
      {code: 'InstalledEffectProgramMismatch'});
    const invalid = Object.freeze({...owner,
      effectSelectors: Object.freeze([Object.freeze({...selector, ...fault})])});
    await assert.rejects(compose(invalid),
      error => (error.primaryFailure?.code ?? error.code) === 'InvalidInstalledEffectSelectors');
  }
  await inventory.close();
  assert.equal(closes, 5, 'refused installation and successful inventory retain the same cleanup owners');
});

test('checked Content COMMAND refuses incompatible MIME and foreign target kind before execution', () => {
  for (const options of [{inputMime: 'text/plain'}, {targetKind: 'folder'}]) {
    const {program, environment} = contentCommandFixture(options);
    const outcome = moon.clientProgramPrepareEffectComputationWithParameters(
      JSON.stringify(program), 'json', environment, undefined, []);
    assert.equal(moon.clientProgramEffectPreparationReady(outcome), undefined,
      JSON.stringify(options));
    const issue = inspect(moon.clientProgramEffectPreparationIssue(outcome), {depth: 12});
    assert.match(issue, options.inputMime === undefined
      ? /CommandTargets[\s\S]*TargetKindMismatch/u
      : /CommandInputs[\s\S]*IncompatibleField/u);
  }
});

test('checked Content COMMAND physical factory retains its original contract and requires recovery hooks', async t => {
  const value = contentCommandFixture();
  const scratch = await createOwnedScratch({parent: tmpdir(),
    prefix: 'actql-command-factory-', label: 'Command factory contract'});
  let touched = 0, closed = 0;
  const unexpected = () => { touched++; throw new Error('UnexpectedCommandPhysicalIO'); };
  const driver = {kinds: ['command'], prepareRequest: unexpected,
    requestFacts: unexpected, writeOperation: unexpected, send: unexpected,
    project: unexpected, footprint: unexpected, recheckRequests: unexpected,
    recoveryEntry: unexpected, recoverRequests: unexpected, requestCid: unexpected};
  const options = {moon, commands: [{resource: 'transfers',
    commandRef: value.command.command_id, commandCid: value.command.contract_cid,
    body: canonical(value.command)}], environmentWire: value.environmentWire,
    connectorId: 'content-fixture', connectorRegistration: 'fixture',
    connectorRevision: 'fixture/0.1', connection: 'fixture:files',
    site: {issueEffectGrant: unexpected, issueReadGrant: unexpected,
      close() { closed++; }}, authorization: {authorize: unexpected},
    runtimeBundleCid: cid({runtime: 'command-fixture'}),
    bindingCid: cid({installation: 'command-fixture'}), ledgerRoot: scratch.path, driver};
  const effect = await createInstalledRowEffect(options);
  t.after(() => effect.close());
  assert.deepEqual(effect.mappings, [], 'a Command does not install a synthetic Mapping');
  const prepared = moon.clientProgramEffectPreparationReady(
    moon.clientProgramPrepareEffectComputationWithParameters(
      JSON.stringify(value.program), 'json', value.environment, undefined, []));
  assert.ok(prepared);
  const compilation = checked(moon.clientProgramCompileLocalEffects(prepared));
  assert.deepEqual(effect.effectSelectors,
    installedRowEffectDescriptors(moon, prepared, compilation).map(({effectId: _, ...selector}) => selector));
  for (const hook of ['recheckRequests', 'recoveryEntry', 'recoverRequests', 'requestCid']) {
    const incomplete = {...driver};
    delete incomplete[hook];
    await assert.rejects(createInstalledRowEffect({...options, driver: incomplete}),
      {code: 'InvalidInstalledRowEffectDriver'}, hook);
  }
  for (const change of [{commandCid: `sha256:${'a'.repeat(64)}`},
    {commandRef: 'command:files.other.v1'},
    {body: canonical({...value.command, connector_id: 'other'})}]) {
    await assert.rejects(createInstalledRowEffect({...options,
      commands: [{...options.commands[0], ...change}]}),
      {code: 'InvalidInstalledRowEffectCommand'});
  }
  await assert.rejects(createInstalledRowEffect({...options,
    commands: [...options.commands, ...options.commands]}),
    {code: 'InvalidInstalledRowEffectCommand'});
  assert.equal(touched, 0, 'registration cannot perform request, grant or send I/O');
  // No physical run was started here. Record cleanup before successful scratch
  // disposal; this component test is not an approved Command dispatch claim.
  t.after(() => { assert.equal(closed, 1); scratch.passed(); });
});
