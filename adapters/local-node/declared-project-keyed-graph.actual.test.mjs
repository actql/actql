import assert from 'node:assert/strict';
import {mkdtemp, mkdir, open, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {dirname, join, resolve} from 'node:path';
import test from 'node:test';
import {inspect} from 'node:util';
import {pathToFileURL} from 'node:url';
import {projectTemplateFiles} from '../../packages/native-cli/lib/project-template.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField, runtimeIsOk} from '../host-common/compiler-binding.generated.mjs';
import {rowSourceCheckEnvironment} from '../host-node/installed-row-source.mjs';
import {composeInstalledCheckEnvironment} from '../host-node/installed-check-environment.mjs';
import {sourceAliasPublication} from '../host-node/source-alias-publication.mjs';
import {inspectDeclaredProjectCatalog} from './declared-project-catalog.mjs';
import {LOCAL_FILES_DEFAULT_LIMITS} from '../connectors/local/host/installed-project-files.mjs';
import {localFilesLookupExecutionPolicy, localResourceLookupExecutionPolicy,
  selectInstalledLocalMaterializationEnvironment} from '../host-node/installed-host-policy.mjs';

assert.ok(process.env.ACTQL_TEST_PROJECT_PROFILE_RUNTIME,
  'Select the actual matching builtin Common runtime');
const moon = await import(pathToFileURL(process.env.ACTQL_TEST_PROJECT_PROFILE_RUNTIME));
// Match the existing public Mock Task construction-component tests. The
// handling reader charges both declared body-emission bounds before work.
const bounds = [65536, 4096, 64, 256, 4096, 64, 65536, 2097152];
const tuple = (value, count) => Array.from({length: count}, (_, index) => runtimeField(value, index));

// Construction-component diagnostic only. The public declaration loader and
// compiler see the unchanged scaffold. No sample rows, answer file, physical
// Source, Model call, Request, Run or operational Resource owner is opened.
test('actual declared deal-review compiler locates original keyed and Model tasks without serialization', async t => {
  const files = projectTemplateFiles('deal-review-mock');
  const configuration = JSON.parse(files['actql.config.json']);
  const directory = await mkdtemp(join(tmpdir(), 'actql-declared-keyed-graph-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const catalogPath = resolve(directory, configuration.mock.catalog);
  await mkdir(dirname(catalogPath), {recursive: true});
  await writeFile(catalogPath, files['mock/catalog.json']);
  const connections = checked(moon.clientProjectConnectionsAdmit(files['connectors.json']));
  const opens = [];
  const catalog = await inspectDeclaredProjectCatalog(moon, {
    directory, catalogFile: configuration.mock.catalog, dataFile: configuration.mock.data,
    connections, assertCurrent() {},
    openFile(path, ...args) {
      opens.push(path);
      assert.equal(path, catalogPath, 'only declared catalog metadata may be opened');
      return open(path, ...args);
    },
  });
  assert.deepEqual(opens, [catalogPath]);

  const originalBaseWire = (await readFile(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8')).trimEnd();
  // Match the selected ordinary Local installation's explicit service policy.
  // No sample count or compiler estimate participates in these ceilings.
  const lookupPolicy = localResourceLookupExecutionPolicy(moon, moon.clientLocalResourcePolicyOriginal(),
    localFilesLookupExecutionPolicy([LOCAL_FILES_DEFAULT_LIMITS]));
  const baseWire = selectInstalledLocalMaterializationEnvironment(moon, originalBaseWire, undefined, lookupPolicy);
  const sourceWires = catalog.sources.map(source => rowSourceCheckEnvironment(baseWire,
    JSON.parse(source.wire), source.writes.map(write => write.mappingWire)).wire);
  assert.equal(sourceWires.length, 2);
  const sourceWire = composeInstalledCheckEnvironment(moon, baseWire, ...sourceWires);

  // Normalize the original public Task through Common, without admitting any
  // answer or installing an executable Mock Provider.
  const profileResult = moon.clientProgramInstallMockProfile(...bounds);
  assert.ok(runtimeIsOk(profileResult), 'Common Mock profile admission: ' +
    inspect(runtimeField(profileResult, 0)?.kind, {depth: 2}));
  const profile = checked(profileResult);
  t.after(() => assert.equal(moon.clientProgramRetireMockProfile(profile), true));
  const task = checked(moon.clientProgramReadPublicModelTask(
    files['model-tasks/deal-review.v1.yaml'], 'yaml', ...bounds));
  const normalized = checked(moon.clientProgramNormalizeMockTask(task, profile, ...bounds));
  const projected = checked(moon.clientProgramProjectPublicModelTaskEnvironment(
    sourceWire, JSON.parse(sourceWire).evidence_bundle_cid, [normalized], ...bounds));
  const environmentWire = runtimeField(projected, 0);
  const environment = moon.clientProgramCheckEnvironment(environmentWire, runtimeField(projected, 1),
    false, false, true, false, false, false, false);
  assert.ok(environment, 'the exact original declaration and Task environment must admit');

  const aliases = catalog.sources.flatMap(source => {
    const declared = JSON.parse(source.wire);
    return source.catalogue.queryAliases.map(alias => {
      const view = declared.views.find(value => value.resource === alias.resource);
      assert.ok(view);
      return {name: alias.name, sourceRef: view.source_ref,
        sourceViewContractCid: view.view_cid, schemaContractCid: view.carrier_schema_cid,
        ...(Object.hasOwn(alias, 'request') ? {request: alias.request} : {})};
    });
  });
  // These publication identifiers are explicit diagnostic DATA, not a live
  // installation binding or an Effect grant. Common checks the target Mapping.
  const updateTargets = catalog.sources.flatMap(source => source.catalogue.updateAliases.map(alias => ({
    name: alias.name, targetRef: 'connector://' + source.catalogue.connectorId + '/' + alias.resource,
    installationBindingCid: 'sha256:' + 'd'.repeat(64),
    installationOwnerCid: 'sha256:' + 'e'.repeat(64),
  })));
  for (const [name, wire] of [
    ...sourceWires.map((wire, index) => [catalog.sources[index].catalogue.connection, wire]),
    ['combined-before-Model', sourceWire],
  ]) {
    const original = moon.clientProgramCheckEnvironment(wire, JSON.parse(wire).evidence_bundle_cid,
      false, false, true, false, false, false, false);
    assert.ok(original);
    const sourceRefs = new Set(JSON.parse(wire).contract_registry
      .filter(contract => contract.kind === 'data_policy').map(contract => contract.body.source_ref));
    const originalAliases = aliases.filter(alias => sourceRefs.has(alias.sourceRef));
    try {
      sourceAliasPublication(moon, original, originalAliases);
      t.diagnostic('original pre-Model publication ' + name + ': admitted');
    } catch (error) {
      t.diagnostic('original pre-Model publication ' + name + ': ' + error.message);
    }
  }
  for (const alias of aliases) {
    try { sourceAliasPublication(moon, environment, [alias]); }
    catch (error) { t.diagnostic('original Source publication ' + alias.name + ': ' + error.message); }
  }
  try { sourceAliasPublication(moon, environment, [], [], {updateTargets}); }
  catch (error) { t.diagnostic('original UPDATE Mapping publication: ' + error.message); }
  // Submit the exact complete publication through the ordinary typed native
  // preparation. The Host wrapper otherwise hides its typed refusal as None.
  const publication = {environmentCid: moon.clientProgramCheckingEnvironmentCid(environment),
    aliases, updateTargets};
  if (process.env.ACTQL_TEST_KEYED_GRAPH_DIAGNOSTIC_PATH) {
    await writeFile(process.env.ACTQL_TEST_KEYED_GRAPH_DIAGNOSTIC_PATH, JSON.stringify({
      sourceWires, sourceWire, environmentWire, publication, source: files['deal-review.aql'],
    }));
  }
  const outcome = moon.clientProgramPreparePublicSourceComputationWithParameters(
    files['deal-review.aql'], 'sql', environment, JSON.stringify(publication),
    undefined, undefined, true, []);
  const rejectedPure = moon.clientProgramSourceComputationPure(outcome);
  assert.equal(rejectedPure, undefined,
    rejectedPure === undefined ? undefined : inspect(moon.clientProgramPreparationIssue(rejectedPure),
      {depth: 6, maxArrayLength: 6, maxStringLength: 400}));
  const effect = moon.clientProgramSourceComputationEffect(outcome);
  assert.ok(effect, 'the unchanged README query must retain an Effect preparation');
  const prepared = moon.clientProgramEffectPreparationReady(effect);
  assert.ok(prepared, inspect(moon.clientProgramEffectPreparationIssue(effect),
    {depth: 6, maxArrayLength: 6, maxStringLength: 400}));
  assert.deepEqual(sourceAliasPublication(moon, environment, aliases, [], {updateTargets}), publication);
  const capturedTaskPrefix = moon.clientProgramEffectAcquisitionCount(prepared);
  assert.equal(capturedTaskPrefix, 2, 'downstream keyed lookup preserves both checked initial Direct tasks');
  t.diagnostic(JSON.stringify({capturedTaskPrefix}));
  assert.deepEqual(moon.clientProgramEffectSerializationOccurrences(prepared), []);
  const occurrence = moon.clientProgramEffectInferOccurrence(prepared);
  assert.ok(occurrence, 'the original Effect must select exactly one Model occurrence');
  const infer = tuple(moon.clientProgramInferOccurrenceCoordinates(occurrence), 3);
  assert.ok(infer.every(Number.isSafeInteger));
  assert.ok(infer[1] >= 0 && infer[1] < 16, 'bound this diagnostic to the declared README graph');

  // Enumerate a bounded set of coordinates through the actual checked-owner
  // APIs. A failed coordinate contributes no synthetic acquisition. Task IDs
  // come only from the keyed projection, not from authored Stage arithmetic.
  const direct = [], keyed = [];
  for (let stage = 0; stage <= infer[1]; stage++) {
    for (let input = 0; input < aliases.length; input++) {
      const candidate = moon.clientProgramEffectPrepareQueryAcquisition(prepared, stage, input);
      if (runtimeIsOk(candidate)) {
        const acquisition = checked(candidate);
        assert.equal(moon.clientProgramQueryAcquisitionSourceIndex(acquisition), input);
        direct.push({stage, input});
      }
      const lookup = moon.clientProgramEffectPrepareKeyedAcquisition(prepared, stage, input, undefined);
      if (runtimeIsOk(lookup)) {
        const acquisition = checked(lookup);
        assert.equal(moon.clientProgramKeyedAcquisitionMatchesEffectProgram(acquisition, prepared), true);
        const selectedCoordinates = moon.clientProgramKeyedAcquisitionInputCoordinates(acquisition);
        const coordinates = runtimeIsOk(selectedCoordinates) ? runtimeField(selectedCoordinates, 0) : undefined;
        assert.ok(coordinates !== undefined && coordinates.length === 4 &&
          coordinates.every(value => Number.isSafeInteger(value) && value >= 0));
        keyed.push(Array.from(coordinates));
      }
    }
  }
  t.diagnostic(JSON.stringify({observedDirect: direct, observedKeyed: keyed, observedInfer: infer}));
  assert.deepEqual(direct, [{stage: 0, input: 0}, {stage: 1, input: 0}],
    'every Direct occurrence must be selected from this exact Effect');
  assert.equal(keyed.length, 1, 'the same Effect must retain exactly one keyed acquisition');
  const originalKeyed = checked(moon.clientProgramEffectPrepareKeyedAcquisition(
    prepared, keyed[0][0], keyed[0][1], keyed[0][3]));
  const equalOutcome = moon.clientProgramPreparePublicSourceComputationWithParameters(
    files['deal-review.aql'], 'sql', environment, JSON.stringify(publication),
    undefined, undefined, true, []);
  const equalEffect = moon.clientProgramSourceComputationEffect(equalOutcome);
  const equalPrepared = moon.clientProgramEffectPreparationReady(equalEffect);
  assert.ok(equalPrepared, 'the equal-wire second compilation must be a real separate original');
  assert.notEqual(equalPrepared, prepared);
  assert.equal(moon.clientProgramKeyedAcquisitionMatchesEffectProgram(originalKeyed, equalPrepared), false);
  assert.equal(runtimeIsOk(moon.clientProgramEffectPrepareKeyedAcquisition(
    prepared, keyed[0][0], keyed[0][1] + 1, keyed[0][3])), false,
    'another input port cannot reuse the keyed occurrence');
  assert.equal(runtimeIsOk(moon.clientProgramEffectPrepareQueryAcquisition(
    prepared, keyed[0][0], keyed[0][1])), false,
    'downstream keyed lookup is never relabeled as an independent Direct capture');

  // A third alias with the same Source/request may share an acquisition.
  // This fixture does not establish a third-independent-Direct rejection or
  // mutate private checked subjects to exercise the graph identity guard.
  assert.deepEqual(keyed[0], [2, 0, 2, 1]);
  assert.deepEqual(infer, [2, 2, 5]);
  assert.equal(keyed[0][2], infer[0], 'keyed Content and Model retain the same original task');
  assert.ok(keyed[0][3] < infer[2], 'the keyed operation must precede the checked Model step');
  t.diagnostic(JSON.stringify({kind: 'construction-component-graph', capturedTaskPrefix,
    directStageInputs: direct, keyedStageInputTaskStep: keyed[0], inferTaskStageStep: infer,
    keyedAndInferShareTask: keyed[0][2] === infer[0], serialization: []}));
});
