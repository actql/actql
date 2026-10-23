import {runtimeField, runtimeIsError, runtimeIsBoxedNone, runtimeIsOk, runtimeIsBoxedSome} from './compiler-binding.generated.mjs';
import * as owner from './dist/client_values_host_abi.js';

const retainedInputEdges = new WeakMap();
const retainedInputProducers = new WeakMap();
const retainedInputIntents = new WeakMap();
const retainedInputPlans = new WeakMap();
const retainedInputResults = new WeakMap();
const retainedInputCurrentQueries = new WeakMap();
const retainedInputCurrentReplies = new WeakMap();
const retainedTaskInputs = new WeakMap();
import {publicationAction} from './publication-action.mjs';

const environments = new WeakMap();
const preparations = new WeakMap();
const sourcePreparations = new WeakMap();
const compilations = new WeakMap();
const taskCompilations = new WeakMap();
const effectPreparations = new WeakMap();
const effectCompilations = new WeakMap();
const effectAllowedRuns = new WeakMap();
const effectCheckpointBindings = new WeakMap();
const effectMaterialOwners = new WeakMap();
const issuedEffectMaterials = new WeakMap();
const requests = new WeakMap();
const cancellationIdentities = new WeakMap();
const submissionEpochs = new WeakMap();
const submittedIntents = new WeakMap();
const admissions = new WeakMap();
const definitions = new WeakMap();
const publicationContracts = new WeakMap();
const publicationOriginals = new WeakMap();
const runEvidences = new WeakMap();
const originalRunPlans = new WeakMap();
const resultOccurrences = new WeakMap();
const capturedSnapshots = new WeakMap();
const materialHolds = new WeakMap();
const profileKeys = new Set(['textTime', 'veca', 'rela', 'sga', 'tea',
  'calendar', 'textRank']);

function checked(result, code) {
  if (runtimeIsOk(result)) return runtimeField(result, 0);
  if (runtimeIsError(result)) {
    throw Object.assign(new Error(code, {cause: runtimeField(result, 0)}), {code});
  }
  throw Object.assign(new Error('InvalidRunHostOwnerResult'),
    {code: 'InvalidRunHostOwnerResult'});
}

function handle(map, value, kind) {
  const token = Object.freeze({kind});
  map.set(token, value);
  return token;
}

function requireHandle(map, token) {
  const value = map.get(token);
  if (value === undefined) throw new TypeError('ForeignRunHostHandle');
  return value;
}

/** Shared Result-generation hold decisions; physical CAS stays in the Host. */
export function beginResultMaterialHolds(bindingCid, materialGenerationCid) {
  return handle(materialHolds, deliveryResult(
    'clientValuesHostBeginResultMaterialHolds', bindingCid,
    materialGenerationCid), 'result-material-holds');
}

export function admitResultMaterialHolds(wire) {
  if (typeof wire !== 'string') throw new TypeError('InvalidMaterialHoldsWire');
  return handle(materialHolds, deliveryResult(
    'clientValuesHostAdmitResultMaterialHolds', wire),
  'result-material-holds');
}

export function resultMaterialHoldsWire(value) {
  return deliveryResult('clientValuesHostResultMaterialHoldsWire',
    requireHandle(materialHolds, value));
}

export function resultMaterialHoldsFacts(value) {
  const ownerValue = requireHandle(materialHolds, value);
  return Object.freeze({
    bindingCid: owner.clientValuesHostResultMaterialHoldsBinding(ownerValue),
    materialGenerationCid:
      owner.clientValuesHostResultMaterialHoldsGeneration(ownerValue),
    revision: owner.clientValuesHostResultMaterialHoldsRevision(ownerValue),
    reclaimable:
      owner.clientValuesHostResultMaterialHoldsReclaimable(ownerValue),
  });
}

export function prepareResultMaterialHoldsStep(value, operation, identity) {
  if (!['add_consumer', 'release_consumer', 'begin_reader',
    'end_reader', 'stop_readers'].includes(operation) ||
    typeof identity !== 'string') {
    throw new TypeError('InvalidMaterialHoldsStep');
  }
  return handle(materialHolds, deliveryResult(
    'clientValuesHostPrepareResultMaterialHoldsStep',
    requireHandle(materialHolds, value), operation, identity),
  'result-material-holds');
}

function checkedProfileSelection(profiles, error) {
  if (profiles === null || typeof profiles !== 'object' ||
      Array.isArray(profiles)) {
    throw new TypeError(error);
  }
  let numericProfileCid;
  for (const [key, value] of Object.entries(profiles)) {
    if (key === 'numericProfileCid') {
      if (typeof value !== 'string' || !/^sha256:[0-9a-f]{64}$/u.test(value)) {
        throw new TypeError(error);
      }
      numericProfileCid = value;
    } else if (!profileKeys.has(key) || typeof value !== 'boolean') {
      throw new TypeError(error);
    }
  }
  return Object.freeze({
    textTime: profiles.textTime === true,
    veca: profiles.veca === true,
    rela: profiles.rela === true,
    sga: profiles.sga === true,
    tea: profiles.tea === true,
    calendar: profiles.calendar === true,
    textRank: profiles.textRank === true,
    ...(numericProfileCid === undefined ? {} : {numericProfileCid}),
  });
}

/** Admit the existing profile contract and make omitted selections explicit. */
export function admitProfileSelection(profiles) {
  return checkedProfileSelection(profiles, 'InvalidRunHostProfileSelection');
}

export function admitEnvironment(body, evidenceBundleCid, profiles) {
  if (typeof body !== 'string' || typeof evidenceBundleCid !== 'string') {
    throw new TypeError('InvalidRunHostEnvironment');
  }
  const selected = checkedProfileSelection(profiles, 'InvalidRunHostEnvironment');
  const value = owner.clientValuesHostEnvironment(body, evidenceBundleCid,
    selected.textTime, selected.veca, selected.rela, selected.sga,
    selected.tea, selected.calendar, selected.textRank, selected.numericProfileCid);
  if (value === undefined) {
    throw Object.assign(new Error('RunHostEnvironmentRejected'),
      {code: 'RunHostEnvironmentRejected'});
  }
  return handle(environments, value, 'check-environment');
}

export function prepare(document, format, environment, parametersWire) {
  if (typeof document !== 'string' || !['json', 'yaml'].includes(format) ||
      parametersWire !== undefined && typeof parametersWire !== 'string') {
    throw new TypeError('InvalidRunHostPreparation');
  }
  const value = checked(owner.clientValuesHostPrepare(document, format,
    requireHandle(environments, environment), parametersWire),
  'RunHostPreparationRejected');
  return handle(preparations, value, 'prepared-program');
}

/** Select the existing preparation Owner from one ordinary parsed Program. */
export function prepareProgram(document, format, environment, parametersWire) {
  if (typeof document !== 'string' || !['json', 'yaml'].includes(format) ||
      parametersWire !== undefined && typeof parametersWire !== 'string') {
    throw new TypeError('InvalidRunHostPreparation');
  }
  const selected = checked(owner.clientValuesHostPrepareProgram(document, format,
    requireHandle(environments, environment), parametersWire), 'RunHostProgramPreparationRejected');
  const kind = owner.clientValuesHostProgramPreparationKind(selected);
  if (kind === 'effect_free') {
    const value = owner.clientValuesHostProgramPreparationEffectFree(selected);
    if (value === undefined) throw new Error('InvalidRunHostOwnerResult');
    return Object.freeze({kind, prepared: handle(preparations, value, 'prepared-program')});
  }
  if (kind === 'effect') {
    const value = owner.clientValuesHostProgramPreparationEffect(selected);
    if (value === undefined) throw new Error('InvalidRunHostOwnerResult');
    return Object.freeze({kind, prepared: handle(effectPreparations, value, 'prepared-effect-program')});
  }
  throw new Error('InvalidRunHostOwnerResult');
}

/** One original submitted source and trusted installation publication. */
export function prepareSourceProgram(intent, environment, publicationWire) {
  return prepareSourceProgramOriginal(intent, environment, publicationWire, 'public-main');
}

function prepareSourceProgramOriginal(intent, environment, publicationWire, primaryResultRecipe) {
  if (typeof publicationWire !== 'string') throw new TypeError('InvalidRunHostSourcePublication');
  const originalIntent = requireHandle(submittedIntents, intent);
  const originalEnvironment = requireHandle(environments, environment);
  const prepare = primaryResultRecipe === undefined
    ? owner.clientValuesHostPrepareSourceProgram : owner.clientValuesHostPreparePublicSourceProgram;
  const value = checked(Reflect.apply(prepare, owner, [originalIntent,
    originalEnvironment, publicationWire]), 'RunHostSourcePreparationRejected');
  const kind = owner.clientValuesHostSourceProgramKind(value);
  const raw = kind === 'effect_free' ? owner.clientValuesHostSourceProgramPure(value)
    : kind === 'effect' ? owner.clientValuesHostSourceProgramEffect(value) : undefined;
  if (raw === undefined) throw new Error('InvalidRunHostOwnerResult');
  const prepared = handle(kind === 'effect_free' ? preparations : effectPreparations,
    raw, kind === 'effect_free' ? 'prepared-program' : 'prepared-effect-program');
  sourcePreparations.set(prepared, {value, intent, environment, primaryResultRecipe});
  return Object.freeze({kind, prepared, originalIntent: intent});
}

/** Retained original DATA for authenticated Host storage, never authority. */
export function sourceProgramOriginals(prepared) {
  const original = sourcePreparations.get(prepared);
  if (original === undefined) throw new TypeError('ForeignRunHostSourcePreparation');
  const facts = owner.clientValuesHostSourceProgramOriginals(original.value);
  if (!Array.isArray(facts) || facts.length !== 4 || facts.some(x => typeof x !== 'string')) {
    throw new Error('InvalidRunHostOwnerResult');
  }
  return Object.freeze({intentWire: facts[0], intentCid: facts[1],
    environmentCid: facts[2], publicationWire: facts[3],
    ...(original.primaryResultRecipe === undefined ? {} :
      {primaryResultRecipe: original.primaryResultRecipe})});
}

/** Original lowerer projection for the existing JSON Run material codec. */
export function sourceProgramMaterialInput(prepared, environmentWire) {
  const original = sourcePreparations.get(prepared);
  if (original === undefined) throw new TypeError('ForeignRunHostSourcePreparation');
  if (typeof environmentWire !== 'string') throw new TypeError('InvalidRunHostRunMaterialsInput');
  const document = owner.clientValuesHostSourceProgramDocument(original.value);
  const parametersWire = owner.clientValuesHostSourceProgramParameters(original.value);
  if (typeof document !== 'string' || parametersWire !== undefined && typeof parametersWire !== 'string') {
    throw new Error('InvalidRunHostOwnerResult');
  }
  return Object.freeze({format: 'json', document, environment: original.environment,
    environmentWire, ...(parametersWire === undefined ? {} : {parametersWire})});
}

/** Exact authored input projection for saved-source correspondence. */
export function sourceProgramSourceInput(prepared) {
  const original = sourcePreparations.get(prepared);
  if (original === undefined) throw new TypeError('ForeignRunHostSourcePreparation');
  const fields = owner.clientValuesHostSourceProgramInput(original.value);
  const parametersWire = owner.clientValuesHostSourceProgramParameters(original.value);
  const parameterDeclarationsWire = owner.clientValuesHostSourceProgramDeclarations(original.value);
  if (!Array.isArray(fields) || fields.length !== 2 || fields.some(x => typeof x !== 'string') ||
      [parametersWire, parameterDeclarationsWire].some(x => x !== undefined && typeof x !== 'string')) {
    throw new Error('InvalidRunHostOwnerResult');
  }
  return Object.freeze({document: fields[0], format: fields[1],
    ...(parametersWire === undefined ? {} : {parametersWire}),
    ...(parameterDeclarationsWire === undefined ? {} : {parameterDeclarationsWire})});
}

/** Re-admit saved originals; the Host still verifies current custody and Run. */
export function restoreSourceProgram(originals, environment) {
  const keys = ['intentWire', 'intentCid', 'environmentCid', 'publicationWire'];
  const recipe = originals === null || typeof originals !== 'object' ? undefined
    : Object.getOwnPropertyDescriptor(originals, 'primaryResultRecipe');
  if (recipe !== undefined) {
    if (!Object.hasOwn(recipe, 'value') || recipe.value !== 'public-main') {
      throw new TypeError('InvalidRunHostSourceOriginals');
    }
    keys.push('primaryResultRecipe');
  }
  if (originals === null || typeof originals !== 'object' || Array.isArray(originals) ||
      Reflect.ownKeys(originals).length !== keys.length || keys.some(key => {
        const d = Object.getOwnPropertyDescriptor(originals, key);
        return d === undefined || !Object.hasOwn(d, 'value') || typeof d.value !== 'string';
      })) throw new TypeError('InvalidRunHostSourceOriginals');
  const intent = prepareSubmittedIntent(originals.intentWire,
    {maxWireBytes: 1048576, maxNodes: 65536, maxDepth: 64});
  // Absence means the exact historical configured-primary recipe. Never
  // upgrade a saved source preparation merely because new public input uses
  // main. Run restoration independently checks its saved request/materials.
  const selected = prepareSourceProgramOriginal(intent, environment,
    originals.publicationWire, recipe?.value);
  const actual = sourceProgramOriginals(selected.prepared);
  if (keys.some(key => actual[key] !== originals[key])) throw new TypeError('ForeignRunHostSourceOriginals');
  return selected;
}

export function prepareSourceRequest(prepared, intent, authorityScopeCid, requestId) {
  const original = sourcePreparations.get(prepared);
  if (original === undefined || original.intent !== intent) throw new TypeError('ForeignRunHostSourcePreparation');
  if (typeof authorityScopeCid !== 'string' || typeof requestId !== 'string') throw new TypeError('InvalidRunHostRequest');
  return handle(requests, checked(owner.clientValuesHostSourceProgramRequest(original.value,
    requireHandle(submittedIntents, intent), requireHandle(environments, original.environment),
    authorityScopeCid, requestId), 'RunHostRequestRejected'), 'request-identity');
}

/** Restore only a request that belongs to this original source preparation. */
export function admitSourceRequestFields(prepared, intent, fields) {
  const retained = admitRequestFields(fields);
  const current = prepareSourceRequest(prepared, intent, fields.authorityScopeCid, fields.requestId);
  if (requestRelation(current, retained) !== 'same_request') {
    throw Object.assign(new Error('RunHostRequestRecordRejected'), {code: 'RunHostRequestRecordRejected'});
  }
  return retained;
}

export function compileValues(prepared) {
  const value = checked(owner.clientValuesHostCompile(
    requireHandle(preparations, prepared)), 'RunHostCompilationRejected');
  return handle(compilations, {value, prepared}, 'values-compilation');
}

export function compileTasks(prepared) {
  const value = checked(owner.clientValuesHostCompileTasks(
    requireHandle(preparations, prepared)), 'RunHostTaskCompilationRejected');
  return handle(taskCompilations, {value, prepared}, 'task-compilation');
}

/** Static Effect closure; no acquisition, approval or physical apply. */
export function prepareEffect(document, format, environment, parametersWire) {
  if (typeof document !== 'string' || !['json', 'yaml'].includes(format) ||
      parametersWire !== undefined && typeof parametersWire !== 'string') {
    throw new TypeError('InvalidRunHostPreparation');
  }
  return handle(effectPreparations, checked(owner.clientValuesHostPrepareEffect(
    document, format, requireHandle(environments, environment), parametersWire),
  'RunHostEffectPreparationRejected'), 'prepared-effect-program');
}

export function compileEffect(prepared, options = {}) {
  if (options === null || typeof options !== 'object' ||
      options.normalizationProfile !== undefined &&
      options.normalizationProfile !== 'completion-free') {
    throw new TypeError('InvalidRunHostEffectCompilationProfile');
  }
  const value = checked(owner.clientValuesHostCompileEffect(
    requireHandle(effectPreparations, prepared),
    options.normalizationProfile === 'completion-free'), 'RunHostEffectCompilationRejected');
  return handle(effectCompilations, {value, prepared}, 'effect-compilation');
}

function effectCompilationFor(prepared, compilation) {
  const retained = requireHandle(effectCompilations, compilation);
  if (retained.prepared !== prepared) throw new TypeError('ForeignRunHostCompilation');
  return retained.value;
}

/** Checked counts only; this does not select or schedule an executable task. */
export function effectExecutionShape(prepared, compilation) {
  const counts = owner.clientValuesHostEffectShape(effectCompilationFor(prepared, compilation));
  if (!Array.isArray(counts) || counts.length !== 3 ||
      counts.some(value => !Number.isSafeInteger(value) || value < 0)) {
    throw new Error('InvalidRunHostEffectExecutionProjection');
  }
  return Object.freeze({taskCount: counts[0], acquisitionCount: counts[1],
    effectCount: counts[2]});
}

/** Original checked dispatch coordinates, not execution or approval permits. */
export function effectTaskKeys(prepared, compilation) {
  const keys = checked(owner.clientValuesHostEffectTaskKeys(
    effectCompilationFor(prepared, compilation)), 'RunHostTaskKeysRejected');
  if (!Array.isArray(keys) || keys.some(key => typeof key !== 'string') ||
      new Set(keys).size !== keys.length) throw new Error('InvalidRunHostTaskKeyProjection');
  return Object.freeze([...keys]);
}

/** Result inventory owned by the original Effect computation. */
export function effectResultDefinitions(prepared, compilation) {
  const value = effectCompilationFor(prepared, compilation);
  const fields = checked(owner.clientValuesHostEffectResultDefinitions(value),
    'RunHostResultInventoryRejected');
  const names = owner.clientValuesHostEffectResultNames(value);
  if (!Array.isArray(fields) || fields.length !== names.length * 3 ||
      !fields.every(field => typeof field === 'string')) {
    throw new Error('InvalidRunHostResultInventory');
  }
  return Object.freeze(names.map((name, index) => {
    if (fields[index * 3] !== name) throw new Error('InvalidRunHostResultInventory');
    return Object.freeze({name, cid: fields[index * 3 + 1], wire: fields[index * 3 + 2]});
  }));
}

export function effectResultSchema(prepared, compilation, resultName) {
  const value = effectCompilationFor(prepared, compilation);
  if (typeof resultName !== 'string') throw new TypeError('InvalidRunHostResultSelection');
  const result = owner.clientValuesHostEffectResultNames(value).indexOf(resultName);
  if (result < 0) throw new RangeError('UnknownRunHostResult');
  const facts = checked(owner.clientValuesHostEffectResultSchema(value, result),
    'RunHostResultSchemaRejected');
  if (!Array.isArray(facts) || facts.length < 2 ||
      !facts.every(field => typeof field === 'string') ||
      !/^sha256:[0-9a-f]{64}$/u.test(facts[0])) {
    throw new Error('InvalidRunHostResultSchema');
  }
  const fields = Object.freeze(facts.slice(2));
  // JavaScript enumerates integer-like keys numerically; the Owner uses UTF-16.
  const schemaFields = Object.keys(JSON.parse(facts[1])).sort();
  if (schemaFields.length !== fields.length ||
      schemaFields.some((field, index) => field !== fields[index])) {
    throw new Error('InvalidRunHostResultSchema');
  }
  return Object.freeze({cid: facts[0], wire: facts[1], fields});
}

/** Exact original Catalog evidence, never a read grant or Effect approval. */
export function effectSourceEvidenceFacts(prepared, compilation, stage, sourceIndex) {
  const value = effectCompilationFor(prepared, compilation);
  if (![stage, sourceIndex].every(index => Number.isSafeInteger(index) &&
      index >= 0 && index <= 2147483647)) {
    throw new TypeError('InvalidRunHostSourceSelection');
  }
  const option = owner.clientValuesHostEffectSourceEvidenceFacts(value, stage, sourceIndex);
  if (runtimeIsBoxedNone(option)) return undefined;
  if (!runtimeIsBoxedSome(option)) throw new Error('InvalidRunHostSourceEvidenceProjection');
  const facts = runtimeField(option, 0);
  if (!Array.isArray(facts) || facts.length !== 6 ||
      facts.some(field => typeof field !== 'string')) {
    throw new Error('InvalidRunHostSourceEvidenceProjection');
  }
  return Object.freeze({sourceRef: facts[0], sourceContractCid: facts[1],
    carrierSchemaContractCid: facts[2], sourceDataPolicyCid: facts[3],
    dataClassification: facts[4], sourceViewContractCid: facts[5]});
}

export function privateEffectCompilationWires(compilation) {
  const {value} = requireHandle(effectCompilations, compilation);
  return Object.freeze({boundTemplate: owner.clientValuesHostEffectTemplateWire(value),
    compiledPlan: owner.clientValuesHostEffectCompiledPlanWire(value)});
}

/** Current Host authorization precedes this call; Effect approval is separate. */
export function issueAllowedEffectRun(prepared, compilation, {
  executionContextCid, hostPolicyCid, expiresAt,
}) {
  if ([executionContextCid, hostPolicyCid, expiresAt]
    .some(value => typeof value !== 'string')) throw new TypeError('InvalidRunHostEvidence');
  const value = checked(owner.clientValuesHostIssueAllowedEffectRun(
    effectCompilationFor(prepared, compilation), executionContextCid,
    hostPolicyCid, expiresAt), 'RunHostEffectAdmissionRejected');
  return handle(effectAllowedRuns, {value, prepared, compilation}, 'allowed-effect-run');
}

export function privateEffectRunEvidence(allowed) {
  const {value} = requireHandle(effectAllowedRuns, allowed);
  return Object.freeze({preparedInvocationWire: owner.clientValuesHostAllowedEffectPreparedWire(value),
    authorizationWire: owner.clientValuesHostAllowedEffectAuthorizationWire(value)});
}

export function issueEffectRunDefinition(allowed, scopeId, runId, createdAt, validUntil) {
  if ([scopeId, runId, createdAt, validUntil].some(value => typeof value !== 'string')) {
    throw new TypeError('InvalidRunHostDefinition');
  }
  const {value} = requireHandle(effectAllowedRuns, allowed);
  return handle(definitions, checked(owner.clientValuesHostIssueEffectRunDefinition(
    value, scopeId, runId, createdAt, validUntil), 'RunHostEffectDefinitionRejected'), 'run-definition');
}

/** Project the original Effect materials using the existing bounded codec. */
export function issueEffectRunMaterials(allowed, definition, retained, request) {
  validateRunMaterialsInput(retained);
  const {value} = requireHandle(effectAllowedRuns, allowed);
  return checked(owner.clientValuesHostIssueEffectRunMaterials(value,
    requireHandle(definitions, definition), requireHandle(environments, retained.environment),
    retained.environmentWire, retained.document, retained.parametersWire,
    request === undefined ? undefined : requireHandle(requests, request)), 'RunHostEffectRunMaterialsRejected');
}

/** Issue original materials and checked normalization without replacement inputs.
 * This finite profile refuses actual completions and unsupported operations. */
export function issuePreparedEffectRunMaterials(allowed, definition, request) {
  const {value, prepared} = requireHandle(effectAllowedRuns, allowed);
  const issued = checked(owner.clientValuesHostIssuePreparedEffectRunMaterials(
    requireHandle(effectPreparations, prepared), value,
    requireHandle(definitions, definition),
    request === undefined ? undefined : requireHandle(requests, request)),
  'RunHostEffectOriginalMaterialsRejected');
  const material = Object.freeze({wire: owner.clientValuesHostIssuedEffectRunMaterialsWire(issued)});
  issuedEffectMaterials.set(material, issued);
  return material;
}

/** Bind the same live issuer originals; no preparation, compilation or approval.
 * The existing Common Owner verifies the Run, request and normalization custody. */
export function bindPreparedEffectRunMaterials(allowed, definition, issued, request) {
  const original = requireHandle(effectAllowedRuns, allowed);
  const bound = checked(owner.clientValuesHostBindPreparedEffectRunMaterials(
    original.value, requireHandle(definitions, definition),
    requireHandle(issuedEffectMaterials, issued), requireHandle(requests, request)),
  'RunHostEffectOriginalMaterialsRejected');
  const materials = Object.freeze({prepared: original.prepared,
    compilation: original.compilation, allowed, definition, request});
  effectMaterialOwners.set(materials, bound);
  return materials;
}

/** Restore saved journal bytes from this exact material admission; no approval. */
export function restoreEffectRunNormalization(materials) {
  return runEvidence(checked(owner.clientValuesHostRestoreEffectRunNormalization(
    requireHandle(effectMaterialOwners, materials)), 'RunHostEffectNormalizationRejected'));
}

/** Saved evidence is re-admitted, not reissued with a fresh policy or lifetime. */
export function admitEffectRunMaterials(wire, definitionCid, profiles, original, expectedRequest, sourcePrepared) {
  if (typeof wire !== 'string' || typeof definitionCid !== 'string') {
    throw new TypeError('InvalidRunHostRunMaterialsInput');
  }
  const selected = checkedProfileSelection(profiles, 'InvalidRunHostProfiles');
  const source = sourcePrepared === undefined ? undefined : sourcePreparations.get(sourcePrepared);
  if (sourcePrepared !== undefined && (source === undefined || !effectPreparations.has(sourcePrepared))) {
    throw new TypeError('ForeignRunHostSourcePreparation');
  }
  const restored = checked(owner.clientValuesHostAdmitEffectRunMaterials(wire,
    definitionCid, selected.textTime, selected.veca, selected.rela, selected.sga,
    selected.tea, selected.calendar, selected.textRank,
    original === undefined ? undefined : requireHandle(issuedEffectMaterials, original),
    expectedRequest === undefined ? undefined : requireHandle(requests, expectedRequest),
    source?.value, selected.numericProfileCid), 'RunHostEffectRestorationRejected');
  const prepared = handle(effectPreparations, owner.clientValuesHostRestoredEffectPrepared(restored), 'prepared-effect-program');
  if (source !== undefined) sourcePreparations.set(prepared, source);
  const originalRequest = owner.clientValuesHostRestoredEffectRequest(restored);
  if (!Array.isArray(originalRequest) || originalRequest.length > 1) throw new Error('InvalidRunHostOriginalRequest');
  const request = originalRequest.length === 1 ? handle(requests, originalRequest[0], 'request-identity') : undefined;
  const compilation = handle(effectCompilations,
    {value: owner.clientValuesHostRestoredEffectCompilation(restored), prepared}, 'effect-compilation');
  const materials = Object.freeze({prepared, ...(request === undefined ? {} : {request}), compilation,
    allowed: handle(effectAllowedRuns,
      {value: owner.clientValuesHostRestoredEffectAllowed(restored), prepared, compilation}, 'allowed-effect-run'),
    definition: handle(definitions, owner.clientValuesHostRestoredEffectDefinition(restored), 'run-definition')});
  effectMaterialOwners.set(materials, restored);
  return materials;
}

/** Original policy/Run expiry check only; current Host authority is independent. */
export function effectRunStartCurrent(allowed, definition, at) {
  if (typeof at !== 'string') throw new TypeError('InvalidRunHostCurrentTime');
  const {value} = requireHandle(effectAllowedRuns, allowed);
  return owner.clientValuesHostEffectStartCurrent(value, requireHandle(definitions, definition), at);
}

/** Original Run/unit/window binding only. Native custody, current authority,
 * waiting commit and Effect approval must be confirmed independently. */
export function effectReviewCheckpointBinding(allowed, definition, wire) {
  if (typeof wire !== 'string') throw new TypeError('InvalidRunHostCheckpointWire');
  const {value} = requireHandle(effectAllowedRuns, allowed);
  const original = checked(owner.clientValuesHostAdmitEffectCheckpointBinding(value,
    requireHandle(definitions, definition), wire), 'RunHostEffectCheckpointBindingRejected');
  const fields = checked(owner.clientValuesHostEffectCheckpointBindingFields(original),
    'RunHostEffectCheckpointBindingRejected');
  if (!Array.isArray(fields) || fields.length !== 8 ||
      fields.some(field => typeof field !== 'string') ||
      [0, 4, 5, 6, 7].some(index => !/^sha256:[0-9a-f]{64}$/u.test(fields[index]))) {
    throw new Error('InvalidRunHostCheckpointBinding');
  }
  const binding = Object.freeze({checkpointCid: fields[0], checkpointWire: fields[1],
    runId: fields[2], unitId: fields[3], runDefinitionCid: fields[4],
    previewCid: fields[5], reviewProjectionCid: fields[6], continuationCid: fields[7]});
  // Only this returned binding retains its nominal Checkpoint and exact
  // original roots. It is neither a persistence receipt nor current authority.
  effectCheckpointBindings.set(binding, {original, allowed, definition});
  return binding;
}

/** Pure same-original facts; helpers and awaits do not re-admit the wire.
 * Restored operations must obtain their own original binding. */
export function effectReviewCheckpointBindingFacts(binding, allowed, definition) {
  const original = effectCheckpointBindings.get(binding);
  if (original === undefined || original.allowed !== allowed ||
      original.definition !== definition) throw new TypeError('ForeignRunHostCheckpointBinding');
  return binding;
}

/** Same original plus actual stored bytes, through the existing waiting writer.
 * Physical read/revision/current gates remain with the restoration operation. */
export function effectReviewCheckpointWaitingState(binding, allowed, definition,
  storedWire, updatedAt, declaredResults) {
  effectReviewCheckpointBindingFacts(binding, allowed, definition);
  const {original} = effectCheckpointBindings.get(binding);
  if (typeof storedWire !== 'string' || typeof updatedAt !== 'string') {
    throw new TypeError('InvalidRunHostCheckpointWaitingInput');
  }
  const results = effectProjectionArray(declaredResults, 65536);
  let textUnits = 0;
  for (const name of results) {
    if (typeof name !== 'string') throw new TypeError('InvalidRunHostCheckpointWaitingInput');
    textUnits += name.length;
    // A necessary lower bound only; Common meters the complete emitted wire.
    if (textUnits > 1048576) throw new TypeError('InvalidRunHostCheckpointWaitingInput');
  }
  return checked(owner.clientValuesHostEffectCheckpointWaitingState(original,
    storedWire, updatedAt, results), 'RunHostEffectCheckpointWaitingRejected');
}

/** Original checked member IDs, not Source grants or Effect authority. */
export function effectReviewCheckpointMembers(allowed, definition, wire) {
  if (typeof wire !== 'string' || wire.length > 65536 || new TextEncoder().encode(wire).length > 65536) {
    throw new TypeError('InvalidRunHostCheckpointWire');
  }
  const {value} = requireHandle(effectAllowedRuns, allowed);
  const members = checked(owner.clientValuesHostEffectCheckpointMembers(value,
    requireHandle(definitions, definition), wire), 'RunHostEffectCheckpointMembersRejected');
  if (!Array.isArray(members) || members.length === 0 || members.length > 64 ||
      members.some(value => typeof value !== 'string' || value.length === 0) ||
      new Set(members).size !== members.length) throw new Error('InvalidRunHostCheckpointMembers');
  return Object.freeze([...members]);
}

/** Original Effect caller; capture is not a newly submitted input Artifact. */
export function prepareEffectRequest(prepared, compilation, authorityScopeCid, requestId) {
  effectCompilationFor(prepared, compilation);
  const source = sourcePreparations.get(prepared);
  if (source !== undefined) return prepareSourceRequest(prepared, source.intent, authorityScopeCid, requestId);
  if (typeof authorityScopeCid !== 'string' || typeof requestId !== 'string') {
    throw new TypeError('InvalidRunHostRequest');
  }
  const value = checked(owner.clientValuesHostEffectRequestIdentity(
    requireHandle(effectPreparations, prepared), authorityScopeCid, requestId),
  'RunHostRequestRejected');
  return handle(requests, value, 'request-identity');
}

/** Logical Source binding from the original checked Effect graph, no I/O. */
export function effectSourceInputBinding(compilation, request) {
  const {value} = requireHandle(effectCompilations, compilation);
  return checked(owner.clientValuesHostEffectSourceInputBinding(value,
    request === undefined ? undefined : requireHandle(requests, request)),
    'RunHostEffectSourceBindingRejected');
}

function effectSiteSelection(selection) {
  if (selection === null || typeof selection !== 'object' || Array.isArray(selection) ||
      Object.keys(selection).sort().join('\0') !== [...siteSelectionKeys].sort().join('\0')) {
    throw new TypeError('InvalidRunHostSiteSelection');
  }
  // Capture once: validation and the ABI must consume exactly the same values.
  const args = siteSelectionKeys.map(key => selection[key]);
  const [taskAttempt, , , siteGeneration] = args;
  if (!Number.isSafeInteger(taskAttempt) || taskAttempt <= 0 ||
      taskAttempt > 2147483647 ||
      !Number.isSafeInteger(siteGeneration) || siteGeneration < 0 ||
      siteGeneration > 2147483647 ||
      args.some((value, index) => index !== 0 && index !== 3 && typeof value !== 'string')) {
    throw new TypeError('InvalidRunHostSiteSelection');
  }
  return args;
}

/** The Host saves the original envelope before the existing Coordinator sends. */
export function issueEffectSourceDispatch(allowed, definition, request, selection) {
  const args = effectSiteSelection(selection);
  const {value} = requireHandle(effectAllowedRuns, allowed);
  const dispatch = checked(owner.clientValuesHostPrepareEffectSourceDispatch(
    value, requireHandle(definitions, definition), requireHandle(requests, request),
    ...args), 'RunHostEffectSourceDispatchRejected');
  return Object.freeze({cid: owner.clientValuesHostDispatchCid(dispatch),
    wire: checked(owner.clientValuesHostDispatchWire(dispatch),
      'RunHostEffectSourceDispatchRejected')});
}

/** Checked topology only; use existing producer/Transfer/current custody owners. */
export function prepareEffectRetainedTaskInputEdge(allowed, definition) {
  const {value} = requireHandle(effectAllowedRuns, allowed);
  return handle(retainedInputEdges, checked(owner.clientValuesHostEffectRetainedInputEdge(
    value, requireHandle(definitions, definition)), 'RunHostEffectRetainedInputEdgeRejected'),
  'retained-input-edge');
}

/** Exact original consumer; current input and destination are read again. */
export function issueEffectRetainedTaskDispatch(allowed, definition, request, selection, input) {
  const args = effectSiteSelection(selection);
  const {value} = requireHandle(effectAllowedRuns, allowed);
  const dispatch = checked(owner.clientValuesHostPrepareEffectRetainedTaskDispatch(
    value, requireHandle(definitions, definition), requireHandle(requests, request),
    ...args, requireHandle(retainedTaskInputs, input)), 'RunHostEffectRetainedTaskDispatchRejected');
  return Object.freeze({cid: owner.clientValuesHostDispatchCid(dispatch),
    wire: checked(owner.clientValuesHostDispatchWire(dispatch),
      'RunHostEffectRetainedTaskDispatchRejected')});
}

export function privateTaskCompilationWires(compilation) {
  const {value} = requireHandle(taskCompilations, compilation);
  return Object.freeze({
    executablePlan: owner.clientValuesHostTaskPlanWire(value),
    factManifest: owner.clientValuesHostTaskFactManifestWire(value),
    boundTemplate: owner.clientValuesHostTaskTemplateWire(value),
    compiledPlan: owner.clientValuesHostTaskCompiledPlanWire(value),
  });
}

export function taskResultNames(compilation) {
  const {value} = requireHandle(taskCompilations, compilation);
  return Object.freeze([...owner.clientValuesHostTaskResultNames(value)]);
}

export function taskExecutionShape(prepared, compilation) {
  const compiled = requireHandle(taskCompilations, compilation);
  if (compiled.prepared !== prepared) throw new TypeError('ForeignRunHostCompilation');
  const counts = owner.clientValuesHostTaskExecutionShape(requireHandle(preparations, prepared));
  if (!Array.isArray(counts) || counts.length !== 2 ||
      counts.some(value => !Number.isSafeInteger(value) || value < 0)) {
    throw new Error('InvalidRunHostTaskExecutionProjection');
  }
  return Object.freeze({taskCount: counts[0], acquisitionCount: counts[1]});
}

/** Dispatch keys from checked task fragments, excluding Result transforms. */
export function taskKeys(prepared, compilation) {
  const compiled = requireHandle(taskCompilations, compilation);
  if (compiled.prepared !== prepared) throw new TypeError('ForeignRunHostCompilation');
  const keys = checked(owner.clientValuesHostTaskKeys(requireHandle(preparations, prepared)),
    'RunHostTaskKeysRejected');
  if (!Array.isArray(keys) || keys.some(key => typeof key !== 'string') ||
      new Set(keys).size !== keys.length) throw new Error('InvalidRunHostTaskKeyProjection');
  return Object.freeze([...keys]);
}

export function privateCompilationWires(compilation) {
  const {value} = requireHandle(compilations, compilation);
  return Object.freeze({
    executablePlan: owner.clientValuesHostPlanWire(value),
    factManifest: owner.clientValuesHostFactManifestWire(value),
    boundTemplate: owner.clientValuesHostTemplateWire(value),
    compiledPlan: owner.clientValuesHostCompiledPlanWire(value),
  });
}

export function compiledPlanCid(compilation) {
  const {value} = requireHandle(compilations, compilation);
  return owner.clientValuesHostCompiledPlanCid(value);
}

export function executionShape(compilation) {
  const {value} = requireHandle(compilations, compilation);
  return Object.freeze({
    planNodeId: owner.clientValuesHostPlanNodeId(value),
    outputContractCid: owner.clientValuesHostOutputContractCid(value),
    resultNames: Object.freeze([...owner.clientValuesHostResultNames(value)]),
  });
}

export function resultDefinitions(prepared, compilation) {
  const compiled = requireHandle(compilations, compilation);
  if (compiled.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const fields = checked(owner.clientValuesHostResultDefinitions(
    requireHandle(preparations, prepared), compiled.value),
  'RunHostResultInventoryRejected');
  const names = owner.clientValuesHostResultNames(compiled.value);
  if (!Array.isArray(fields) || fields.length !== names.length * 3 ||
      !fields.every(value => typeof value === 'string')) {
    throw new Error('InvalidRunHostResultInventory');
  }
  return Object.freeze(names.map((name, index) => {
    if (fields[index * 3] !== name) {
      throw new Error('InvalidRunHostResultInventory');
    }
    return Object.freeze({name, cid: fields[index * 3 + 1],
      wire: fields[index * 3 + 2]});
  }));
}

export function taskResultDefinitions(prepared, compilation) {
  const compiled = requireHandle(taskCompilations, compilation);
  if (compiled.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const fields = checked(owner.clientValuesHostTaskResultDefinitions(
    requireHandle(preparations, prepared), compiled.value),
  'RunHostResultInventoryRejected');
  const names = owner.clientValuesHostTaskResultNames(compiled.value);
  if (!Array.isArray(fields) || fields.length !== names.length * 3 ||
      !fields.every(value => typeof value === 'string')) {
    throw new Error('InvalidRunHostResultInventory');
  }
  return Object.freeze(names.map((name, index) => {
    if (fields[index * 3] !== name) {
      throw new Error('InvalidRunHostResultInventory');
    }
    return Object.freeze({name, cid: fields[index * 3 + 1],
      wire: fields[index * 3 + 2]});
  }));
}

export function resultSchema(prepared, compilation) {
  const compiled = requireHandle(compilations, compilation);
  if (compiled.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const facts = checked(owner.clientValuesHostResultSchema(
    requireHandle(preparations, prepared)),
  'RunHostResultSchemaRejected');
  if (!Array.isArray(facts) || facts.length < 2 ||
      !facts.every(value => typeof value === 'string') ||
      !/^sha256:[0-9a-f]{64}$/u.test(facts[0])) {
    throw new Error('InvalidRunHostResultSchema');
  }
  const fields = Object.freeze(facts.slice(2));
  // JavaScript enumerates integer-like keys numerically; the Owner uses UTF-16.
  const schemaFields = Object.keys(JSON.parse(facts[1])).sort();
  if (schemaFields.length !== fields.length ||
      schemaFields.some((field, index) => field !== fields[index])) {
    throw new Error('InvalidRunHostResultSchema');
  }
  return Object.freeze({cid: facts[0], wire: facts[1], fields});
}

export function taskResultSchema(prepared, compilation, resultName) {
  const compiled = requireHandle(taskCompilations, compilation);
  if (compiled.prepared !== prepared || typeof resultName !== 'string') {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const names = owner.clientValuesHostTaskResultNames(compiled.value);
  const result = names.indexOf(resultName);
  if (result < 0) throw new RangeError('UnknownRunHostResult');
  const facts = checked(owner.clientValuesHostTaskResultSchema(
    requireHandle(preparations, prepared), result),
  'RunHostResultSchemaRejected');
  if (!Array.isArray(facts) || facts.length < 2 ||
      !facts.every(value => typeof value === 'string') ||
      !/^sha256:[0-9a-f]{64}$/u.test(facts[0])) {
    throw new Error('InvalidRunHostResultSchema');
  }
  const fields = Object.freeze(facts.slice(2));
  // JavaScript enumerates integer-like keys numerically; the Owner uses UTF-16.
  const schemaFields = Object.keys(JSON.parse(facts[1])).sort();
  if (schemaFields.length !== fields.length ||
      schemaFields.some((field, index) => field !== fields[index])) {
    throw new Error('InvalidRunHostResultSchema');
  }
  return Object.freeze({cid: facts[0], wire: facts[1], fields});
}

// The Host must establish scope and admitted input intent before calling this
// pure identity operation. The returned handle is not a Run or a grant.
export function prepareRequest(prepared, authorityScopeCid, requestId,
  admittedInputIntentCid) {
  if ([authorityScopeCid, requestId, admittedInputIntentCid]
    .some(value => typeof value !== 'string')) {
    throw new TypeError('InvalidRunHostRequest');
  }
  const source = sourcePreparations.get(prepared);
  if (source !== undefined) {
    if (sourceProgramOriginals(prepared).intentCid !== admittedInputIntentCid) throw new TypeError('ForeignRunHostSourceIntent');
    return prepareSourceRequest(prepared, source.intent, authorityScopeCid, requestId);
  }
  const value = checked(owner.clientValuesHostRequestIdentity(
    requireHandle(preparations, prepared), authorityScopeCid, requestId,
    admittedInputIntentCid), 'RunHostRequestRejected');
  return handle(requests, value, 'request-identity');
}

export function prepareSourceFreeRequest(prepared, compilation,
  authorityScopeCid, requestId) {
  if (typeof authorityScopeCid !== 'string' || typeof requestId !== 'string') {
    throw new TypeError('InvalidRunHostRequest');
  }
  const {prepared: compiledFrom} = requireHandle(compilations, compilation);
  if (compiledFrom !== prepared) throw new TypeError('ForeignRunHostCompilation');
  const source = sourcePreparations.get(prepared);
  if (source !== undefined) return prepareSourceRequest(prepared, source.intent, authorityScopeCid, requestId);
  const value = checked(owner.clientValuesHostSourceFreeRequestIdentity(
    requireHandle(preparations, prepared), authorityScopeCid, requestId),
  'RunHostRequestRejected');
  return handle(requests, value, 'request-identity');
}

// A later provider capture is not a caller-supplied Run-start Artifact.
export function prepareTaskRequest(prepared, compilation,
  authorityScopeCid, requestId) {
  if (typeof authorityScopeCid !== 'string' || typeof requestId !== 'string') {
    throw new TypeError('InvalidRunHostRequest');
  }
  const compiled = requireHandle(taskCompilations, compilation);
  if (compiled.prepared !== prepared) throw new TypeError('ForeignRunHostCompilation');
  const source = sourcePreparations.get(prepared);
  if (source !== undefined) return prepareSourceRequest(prepared, source.intent, authorityScopeCid, requestId);
  const value = checked(owner.clientValuesHostSourceFreeRequestIdentity(
    requireHandle(preparations, prepared), authorityScopeCid, requestId),
  'RunHostRequestRejected');
  return handle(requests, value, 'request-identity');
}

export function sourceEvidenceFacts(prepared, stage, sourceIndex) {
  if (![stage, sourceIndex].every(value => Number.isSafeInteger(value) &&
      value >= 0 && value <= 2147483647)) {
    throw new TypeError('InvalidRunHostSourceSelection');
  }
  const option = owner.clientValuesHostSourceEvidenceFacts(
    requireHandle(preparations, prepared), stage, sourceIndex);
  if (runtimeIsBoxedNone(option)) return undefined;
  if (!runtimeIsBoxedSome(option)) throw new Error('InvalidRunHostSourceEvidenceProjection');
  const facts = runtimeField(option, 0);
  if (!Array.isArray(facts) || facts.length !== 6 ||
      facts.some(value => typeof value !== 'string')) {
    throw new Error('InvalidRunHostSourceEvidenceProjection');
  }
  return Object.freeze({sourceRef: facts[0], sourceContractCid: facts[1],
    carrierSchemaContractCid: facts[2], sourceDataPolicyCid: facts[3],
    dataClassification: facts[4], sourceViewContractCid: facts[5]});
}

export function taskInputBinding(prepared, task) {
  if (!Number.isSafeInteger(task) || task < 0 || task > 2147483647) {
    throw new TypeError('InvalidRunHostTaskSelection');
  }
  return checked(owner.clientValuesHostTaskInputBinding(
    requireHandle(preparations, prepared), task), 'RunHostTaskBindingRejected');
}

export function requestFields(request) {
  const value = requireHandle(requests, request);
  return Object.freeze({
    authorityScopeCid: owner.clientValuesHostRequestAuthorityScopeCid(value),
    requestId: owner.clientValuesHostRequestCallerId(value),
    logicalRequestScopeCid: owner.clientValuesHostRequestScopeCid(value),
    intentFingerprintCid: owner.clientValuesHostRequestIntentCid(value),
    programDefinitionCid: owner.clientValuesHostRequestProgramCid(value),
    parameterValuesCid: owner.clientValuesHostRequestParametersCid(value),
    callerInputIntentCid: owner.clientValuesHostRequestInputCid(value),
  });
}

const requestKeys = ['authorityScopeCid', 'requestId',
  'logicalRequestScopeCid', 'intentFingerprintCid', 'programDefinitionCid',
  'parameterValuesCid', 'callerInputIntentCid'];

export function admitRequestFields(fields) {
  if (fields === null || typeof fields !== 'object' || Array.isArray(fields) ||
      Object.keys(fields).sort().join('\0') !==
        [...requestKeys].sort().join('\0') ||
      requestKeys.some(key => typeof fields[key] !== 'string')) {
    throw new TypeError('InvalidRunHostRequestRecord');
  }
  const value = checked(owner.clientValuesHostAdmitRequestIdentity(
    fields.authorityScopeCid, fields.requestId,
    fields.programDefinitionCid, fields.parameterValuesCid,
    fields.callerInputIntentCid, fields.logicalRequestScopeCid,
    fields.intentFingerprintCid), 'RunHostRequestRecordRejected');
  return handle(requests, value, 'request-identity');
}

export function admitSourceFreeRequestFields(prepared, compilation, fields) {
  if (fields === null || typeof fields !== 'object' || Array.isArray(fields) ||
      Object.keys(fields).sort().join('\0') !==
        [...requestKeys].sort().join('\0') ||
      requestKeys.some(key => typeof fields[key] !== 'string')) {
    throw new TypeError('InvalidRunHostRequestRecord');
  }
  const source = sourcePreparations.get(prepared);
  if (source !== undefined) {
    const compiled = requireHandle(compilations, compilation);
    if (compiled.prepared !== prepared) throw new TypeError('ForeignRunHostCompilation');
    return admitSourceRequestFields(prepared, source.intent, fields);
  }
  const value = checked(owner.clientValuesHostAdmitSourceFreeRequestIdentity(
    fields.authorityScopeCid, fields.requestId,
    fields.programDefinitionCid, fields.parameterValuesCid,
    fields.callerInputIntentCid, fields.logicalRequestScopeCid,
    fields.intentFingerprintCid), 'RunHostRequestRecordRejected');
  const current = prepareSourceFreeRequest(prepared, compilation,
    fields.authorityScopeCid, fields.requestId);
  if (owner.clientValuesHostRequestRelation(
    requireHandle(requests, current), value) !== 1) {
    throw Object.assign(new Error('RunHostRequestRecordRejected'),
      {code: 'RunHostRequestRecordRejected'});
  }
  return handle(requests, value, 'request-identity');
}

export function requestRelation(requested, retained) {
  const relation = owner.clientValuesHostRequestRelation(
    requireHandle(requests, requested), requireHandle(requests, retained));
  switch (relation) {
    case 0: return 'different_request';
    case 1: return 'same_request';
    case 2: return 'changed_intent';
    default: throw new Error('InvalidRunHostRequestRelation');
  }
}

export function admitRun(prepared, compilation, preparedInvocationWire,
  authorizationWire) {
  if (typeof preparedInvocationWire !== 'string' ||
      typeof authorizationWire !== 'string') {
    throw new TypeError('InvalidRunHostEvidence');
  }
  const compiled = requireHandle(compilations, compilation);
  if (compiled.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const value = checked(owner.clientValuesHostAdmitRun(
    requireHandle(preparations, prepared),
    compiled.value,
    preparedInvocationWire, authorizationWire),
  'RunHostAdmissionRejected');
  return handle(admissions, {value, prepared}, 'run-admission');
}

// Host authorization must precede this call. These owner-issued wires bind
// the selected policy context to the exact checked Values compilation.
export function issueAllowedRun(prepared, compilation, {
  executionContextCid, hostPolicyCid, expiresAt,
}) {
  if ([executionContextCid, hostPolicyCid, expiresAt]
    .some(value => typeof value !== 'string')) {
    throw new TypeError('InvalidRunHostEvidence');
  }
  const compiled = requireHandle(compilations, compilation);
  if (compiled.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const issued = checked(owner.clientValuesHostIssueAllowedRun(
    requireHandle(preparations, prepared), compiled.value,
    executionContextCid, hostPolicyCid, expiresAt),
  'RunHostAdmissionRejected');
  return Object.freeze({
    admission: handle(admissions, {
      value: owner.clientValuesHostAllowedRunAdmission(issued), prepared,
    }, 'run-admission'),
    preparedInvocationWire:
      owner.clientValuesHostAllowedRunPreparedWire(issued),
    authorizationWire:
      owner.clientValuesHostAllowedRunAuthorizationWire(issued),
  });
}

export function issueAllowedTaskRun(prepared, compilation, {
  executionContextCid, hostPolicyCid, expiresAt,
}) {
  if ([executionContextCid, hostPolicyCid, expiresAt]
    .some(value => typeof value !== 'string')) {
    throw new TypeError('InvalidRunHostEvidence');
  }
  const compiled = requireHandle(taskCompilations, compilation);
  if (compiled.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const issued = checked(owner.clientValuesHostIssueAllowedTaskRun(
    requireHandle(preparations, prepared), compiled.value,
    executionContextCid, hostPolicyCid, expiresAt),
  'RunHostAdmissionRejected');
  return Object.freeze({
    admission: handle(admissions, {
      value: owner.clientValuesHostAllowedRunAdmission(issued), prepared,
    }, 'run-admission'),
    preparedInvocationWire:
      owner.clientValuesHostAllowedRunPreparedWire(issued),
    authorizationWire:
      owner.clientValuesHostAllowedRunAuthorizationWire(issued),
  });
}

export function admitTaskRun(prepared, compilation,
  preparedInvocationWire, authorizationWire) {
  if ([preparedInvocationWire, authorizationWire]
    .some(value => typeof value !== 'string')) {
    throw new TypeError('InvalidRunHostEvidence');
  }
  const compiled = requireHandle(taskCompilations, compilation);
  if (compiled.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const value = checked(owner.clientValuesHostAdmitTaskRun(
    requireHandle(preparations, prepared), compiled.value,
    preparedInvocationWire, authorizationWire),
  'RunHostAdmissionRejected');
  return handle(admissions, {value, prepared}, 'run-admission');
}

export function issueRunDefinition(admission, scopeId, runId,
  inputArtifactSetCid, createdAt, validUntil) {
  if ([scopeId, runId, inputArtifactSetCid, createdAt, validUntil]
    .some(value => typeof value !== 'string')) {
    throw new TypeError('InvalidRunHostDefinition');
  }
  const value = checked(owner.clientValuesHostIssueRunDefinition(
    requireHandle(admissions, admission).value, scopeId, runId,
    inputArtifactSetCid, createdAt, validUntil),
  'RunHostDefinitionRejected');
  return handle(definitions, value, 'run-definition');
}

export function issueSourceFreeRunDefinition(prepared, compilation,
  admission, scopeId, runId, createdAt, validUntil) {
  const compiled = requireHandle(compilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  if ([scopeId, runId, createdAt, validUntil]
    .some(value => typeof value !== 'string')) {
    throw new TypeError('InvalidRunHostDefinition');
  }
  const value = checked(owner.clientValuesHostIssueSourceFreeRunDefinition(
    requireHandle(preparations, prepared), compiled.value, admitted.value,
    scopeId, runId, createdAt, validUntil),
  'RunHostSourceFreeDefinitionRejected');
  return handle(definitions, value, 'run-definition');
}

export function issueTaskRunDefinition(prepared, compilation,
  admission, scopeId, runId, createdAt, validUntil) {
  const compiled = requireHandle(taskCompilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  if ([scopeId, runId, createdAt, validUntil]
    .some(value => typeof value !== 'string')) {
    throw new TypeError('InvalidRunHostDefinition');
  }
  const value = checked(owner.clientValuesHostIssueTaskRunDefinition(
    requireHandle(preparations, prepared), compiled.value, admitted.value,
    scopeId, runId, createdAt, validUntil),
  'RunHostTaskDefinitionRejected');
  return handle(definitions, value, 'run-definition');
}

export function admitTaskRunDefinition(prepared, compilation, admission,
  wire) {
  if (typeof wire !== 'string') throw new TypeError('InvalidRunHostDefinition');
  const compiled = requireHandle(taskCompilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const value = checked(owner.clientValuesHostAdmitTaskRunDefinition(
    requireHandle(preparations, prepared), compiled.value, admitted.value,
    wire), 'RunHostTaskDefinitionRejected');
  return handle(definitions, value, 'run-definition');
}

export function privateRunDefinition(definition) {
  const value = requireHandle(definitions, definition);
  return Object.freeze({
    wire: owner.clientValuesHostRunDefinitionWire(value),
    cid: owner.clientValuesHostRunDefinitionCid(value),
  });
}

/** Capture once from the same checked compilation/admission used by the Host.
 * The Host persists the two original wires in its first admission transaction. */
export function captureOriginalRunPlan(prepared, compilation, admission, definition, limits) {
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  const task = taskCompilations.has(compilation);
  const compiled = requireHandle(task ? taskCompilations : compilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const fields = checked((task
    ? owner.clientValuesHostCaptureOriginalTaskRunPlan
    : owner.clientValuesHostCaptureOriginalValuesRunPlan)(
    requireHandle(preparations, prepared), compiled.value, admitted.value,
    requireHandle(definitions, definition), maxWireBytes, maxNodes, maxDepth),
  'RunHostOriginalPlanRejected');
  if (!Array.isArray(fields) || fields.length !== 5 ||
      fields.some(value => typeof value !== 'string')) {
    throw new Error('InvalidRunHostOriginalPlanProjection');
  }
  const original = Object.freeze({compiledPlanWire: fields[0], planViewWire: fields[1]});
  readStoredRunPlanOriginal(original, definition, fields[2], limits);
  return handle(originalRunPlans, Object.freeze({original,
    definitionCid: privateRunDefinition(definition).cid,
    programCid: fields[2], prepared: fields[3], authorization: fields[4]}),
  'original-run-plan');
}

/** Only a genuine first-capture token can supply admission evidence. */
export function originalRunPlanAdmissionEvidence(selection, definition, programCid, evidence) {
  const retained = requireHandle(originalRunPlans, selection);
  if (retained.definitionCid !== privateRunDefinition(definition).cid ||
      retained.programCid !== programCid || retained.prepared !== evidence?.prepared ||
      retained.authorization !== evidence?.authorization) {
    throw new TypeError('ForeignRunHostOriginalPlanAdmission');
  }
  return retained.original;
}

/** Validate authenticated saved metadata without preparation, recompilation or
 * reissuing capture custody. The Host separately checks current RunRead and its
 * original Run/request/context join before and after durable lookup. */
export function readStoredRunPlanOriginal(original, definition, programCid, limits) {
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  const run = privateRunDefinition(definition);
  if (original === undefined) {
    throw Object.assign(new Error('RunHostOriginalPlanUnavailable'),
      {code: 'RunHostOriginalPlanUnavailable'});
  }
  if (original === null || typeof original !== 'object' || Array.isArray(original)) {
    throw new TypeError('InvalidRunHostOriginalPlan');
  }
  const names = Reflect.ownKeys(original);
  const expected = ['compiledPlanWire', 'planViewWire'];
  if (names.length !== expected.length || names.some(name => typeof name !== 'string') ||
      names.sort().some((name, index) => name !== expected[index])) {
    throw new TypeError('InvalidRunHostOriginalPlan');
  }
  // Snapshot data fields once; accessors cannot replace bytes between checks.
  const descriptors = Object.getOwnPropertyDescriptors(original);
  if (Reflect.ownKeys(descriptors).length !== expected.length ||
      expected.some(name => !descriptors[name]?.enumerable ||
        !Object.hasOwn(descriptors[name], 'value'))) {
    throw new TypeError('InvalidRunHostOriginalPlan');
  }
  const compiledPlanWire = descriptors.compiledPlanWire.value;
  const planViewWire = descriptors.planViewWire.value;
  if (typeof programCid !== 'string' ||
      [compiledPlanWire, planViewWire].some(wire => typeof wire !== 'string' ||
        wire.length > maxWireBytes)) {
    throw new TypeError('InvalidRunHostOriginalPlan');
  }
  const plan = admitPublicationContract('compiled_plan', compiledPlanWire, limits);
  if (plan.wire !== compiledPlanWire) {
    throw new TypeError('InvalidRunHostOriginalPlan');
  }
  checked(owner.clientValuesHostCheckStoredPlanView(planViewWire,
    maxWireBytes, maxNodes, maxDepth), 'RunHostOriginalPlanRejected');
  const view = JSON.parse(planViewWire);
  if (JSON.parse(run.wire).compiled_plan_cid !== plan.cid ||
      view.compiled_plan_cid !== plan.cid ||
      JSON.parse(plan.wire).program_definition_cid !== programCid) {
    throw new TypeError('ForeignRunHostOriginalPlan');
  }
  const map = admitRunEvidenceValue('logical_map', JSON.stringify(view.logical_map), limits);
  checked(owner.clientValuesHostCheckLogicalMapBinding(
    requireHandle(runEvidences, map.token), publicationToken(plan),
    maxWireBytes, maxNodes, maxDepth), 'RunHostOriginalMapRejected');
  return planViewWire;
}

// The caller must retain the checked admission and the current physical
// observation. A state wire is a projection, never Run or read authority.
export function issueUnpublishedRunStateWire(prepared, compilation,
  admission, definition, observedAt, observation) {
  const task = taskCompilations.has(compilation);
  const compiled = requireHandle(task ? taskCompilations : compilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const {dispatchReserved, preDispatchFailureConfirmed,
    cancelledBeforeStart = false, executionUnknown = false} =
    observation ?? {};
  if (typeof observedAt !== 'string' ||
      observation === null || typeof observation !== 'object' ||
      Array.isArray(observation) ||
      typeof dispatchReserved !== 'boolean' ||
      typeof preDispatchFailureConfirmed !== 'boolean' ||
      typeof cancelledBeforeStart !== 'boolean' ||
      typeof executionUnknown !== 'boolean') {
    throw new TypeError('InvalidRunHostStateObservation');
  }
  checkRunBinding(prepared, admission, definition);
  const issue = task ? owner.clientValuesHostIssueTaskUnpublishedRunStateWire
    : owner.clientValuesHostIssueUnpublishedRunStateWire;
  const wire = issue(
    requireHandle(definitions, definition), compiled.value, observedAt,
    dispatchReserved, preDispatchFailureConfirmed, cancelledBeforeStart,
    executionUnknown);
  if (typeof wire !== 'string') {
    throw Object.assign(new Error('RunHostStateProjectionRejected'),
      {code: 'RunHostStateProjectionRejected'});
  }
  return wire;
}

export function issueSucceededRunStateWire(prepared, compilation,
  admission, definition, observedAt, observations) {
  const task = taskCompilations.has(compilation);
  const compiled = requireHandle(task ? taskCompilations : compilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  if (typeof observedAt !== 'string' || !Array.isArray(observations) ||
      !observations.every(value => value !== null &&
        typeof value === 'object' &&
        ['name', 'state', 'reason', 'observedAt'].every(key =>
          typeof value[key] === 'string'))) {
    throw new TypeError('InvalidRunHostStateObservation');
  }
  checkRunBinding(prepared, admission, definition);
  const issue = task ? owner.clientValuesHostIssueTaskSucceededRunStateWire
    : owner.clientValuesHostIssueSucceededRunStateWire;
  const wire = issue(
    requireHandle(definitions, definition), compiled.value, observedAt,
    observations.map(value => value.name),
    observations.map(value => value.state),
    observations.map(value => value.reason),
    observations.map(value => value.observedAt));
  if (typeof wire !== 'string') {
    throw Object.assign(new Error('RunHostStateProjectionRejected'),
      {code: 'RunHostStateProjectionRejected'});
  }
  return wire;
}

export function resultReadAvailability(manifest, resultName, retention,
  observedAt) {
  if (typeof resultName !== 'string' || typeof observedAt !== 'string') {
    throw new TypeError('InvalidRunHostAvailabilityObservation');
  }
  return checked(owner.clientValuesHostResultReadAvailability(
    publicationToken(manifest), resultName, publicationToken(retention),
    observedAt), 'RunHostAvailabilityRejected');
}

// The common publication owner selects and checks every listed binding.
// CIDs returned here identify physical custody; they grant no read access.
export function projectCommittedResultRead(index, manifest, resultName,
  bindings) {
  if (typeof resultName !== 'string' || !Array.isArray(bindings)) {
    throw new TypeError('InvalidRunHostResultSelection');
  }
  const wire = owner.clientValuesHostProjectCommittedResultReadWire(
    publicationToken(index), publicationToken(manifest), resultName,
    publicationItems(bindings));
  if (typeof wire !== 'string') {
    throw Object.assign(new Error('RunHostResultSelectionRejected'),
      {code: 'RunHostResultSelectionRejected'});
  }
  const value = JSON.parse(wire);
  const cid = value => typeof value === 'string' &&
    /^sha256:[0-9a-f]{64}$/u.test(value);
  if (value === null || typeof value !== 'object' ||
      !['codec_contract_cid', 'durable_result_binding_cid',
        'effective_retention_policy_cid', 'logical_result_cid',
        'material_generation_cid', 'ordering_evidence_cid',
        'result_artifact_cid', 'result_definition_cid',
        'result_schema_cid', 'store_authority_cid'].every(key =>
        cid(value[key])) ||
      typeof value.physical_sha256 !== 'string' ||
      !/^[0-9a-f]{64}$/u.test(value.physical_sha256) ||
      value.result_name !== resultName ||
      !Array.isArray(value.result_fields) ||
      !value.result_fields.every(field => typeof field === 'string') ||
      !Number.isSafeInteger(value.row_count) || value.row_count < 0 ||
      !Number.isSafeInteger(value.byte_count) || value.byte_count < 0) {
    throw new Error('RunHostResultSelectionInvalid');
  }
  return Object.freeze({resultName: value.result_name,
    resultArtifactCid: value.result_artifact_cid,
    resultDefinitionCid: value.result_definition_cid,
    logicalResultCid: value.logical_result_cid,
    resultSchemaCid: value.result_schema_cid,
    orderingEvidenceCid: value.ordering_evidence_cid,
    effectiveRetentionPolicyCid: value.effective_retention_policy_cid,
    durableResultBindingCid: value.durable_result_binding_cid,
    materialGenerationCid: value.material_generation_cid,
    storeAuthorityCid: value.store_authority_cid,
    codecContractCid: value.codec_contract_cid,
    resultFields: Object.freeze([...value.result_fields]),
    rowCount: value.row_count, byteCount: value.byte_count,
    physicalSha256: value.physical_sha256});
}

export function describeCommittedResult(index, manifest, resultName,
  bindings, definition, schemaWire, format, limits) {
  const bounds = publicationLimits(limits);
  const wire = owner.clientValuesHostDescribeCommittedResult(
    publicationToken(index), publicationToken(manifest), resultName,
    publicationItems(bindings), publicationToken(definition), schemaWire,
    format, bounds.maxWireBytes, bounds.maxNodes, bounds.maxDepth);
  if (typeof wire !== 'string') {
    throw Object.assign(new Error('RunHostResultDescriptionRejected'),
      {code: 'RunHostResultDescriptionRejected'});
  }
  return JSON.parse(wire);
}

export function admitRunDefinition(wire) {
  if (typeof wire !== 'string') throw new TypeError('InvalidRunHostDefinition');
  const value = checked(owner.clientValuesHostAdmitRunDefinition(wire),
    'RunHostDefinitionRejected');
  return handle(definitions, value, 'run-definition');
}

export function admitSourceFreeRunDefinition(prepared, compilation,
  admission, wire) {
  const compiled = requireHandle(compilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  if (typeof wire !== 'string') throw new TypeError('InvalidRunHostDefinition');
  const value = checked(owner.clientValuesHostAdmitSourceFreeRunDefinition(
    requireHandle(preparations, prepared), compiled.value, admitted.value,
    wire), 'RunHostSourceFreeAdmissionRejected');
  return handle(definitions, value, 'run-definition');
}

/** Project the original Run; this does not compile or issue authorization. */
export function issueSourceFreeRunMaterials(prepared, compilation, admission,
  definition, retained) {
  const compiled = requireHandle(compilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  validateRunMaterialsInput(retained);
  return checked(owner.clientValuesHostIssueSourceFreeRunMaterials(
    requireHandle(preparations, prepared), compiled.value, admitted.value,
    requireHandle(definitions, definition),
    requireHandle(environments, retained.environment),
    retained.environmentWire, retained.document, retained.parametersWire),
  'RunHostRunMaterialsRejected');
}

/** Project the original checked task Run; Source bindings stay at the Site. */
export function issueTaskRunMaterials(prepared, compilation, admission,
  definition, retained) {
  const compiled = requireHandle(taskCompilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  validateRunMaterialsInput(retained);
  return checked(owner.clientValuesHostIssueTaskRunMaterials(
    requireHandle(preparations, prepared), compiled.value, admitted.value,
    requireHandle(definitions, definition),
    requireHandle(environments, retained.environment),
    retained.environmentWire, retained.document, retained.parametersWire),
  'RunHostRunMaterialsRejected');
}

function validateRunMaterialsInput(retained) {
  if (retained === null || typeof retained !== 'object' ||
      Array.isArray(retained) || retained.format !== 'json' ||
      typeof retained.document !== 'string' ||
      typeof retained.environmentWire !== 'string' ||
      retained.parametersWire !== undefined &&
        typeof retained.parametersWire !== 'string' ||
      Object.keys(retained).some(key => !['format', 'document',
        'environment', 'environmentWire', 'parametersWire'].includes(key))) {
    throw new TypeError('InvalidRunHostRunMaterialsInput');
  }
}

export function prepareRunStart(requested, retained, definition,
  retainedRunDefinitionCid, dispatchReserved, currentAuthorization) {
  if (typeof retainedRunDefinitionCid !== 'string' ||
      typeof dispatchReserved !== 'boolean' ||
      typeof currentAuthorization !== 'boolean') {
    throw new TypeError('InvalidRunHostStart');
  }
  const action = checked(owner.clientValuesHostPrepareRunStart(
    requireHandle(requests, requested), requireHandle(requests, retained),
    requireHandle(definitions, definition), retainedRunDefinitionCid,
    dispatchReserved, currentAuthorization), 'RunHostStartRejected');
  switch (action) {
    case 0: return 'reserve_dispatch';
    case 1: return 'reconcile_reserved_dispatch';
    default: throw new Error('InvalidRunHostStartAction');
  }
}

export function checkRunBinding(prepared, admission, definition) {
  const admitted = requireHandle(admissions, admission);
  if (admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostAdmission');
  }
  checked(owner.clientValuesHostCheckRunBinding(
    requireHandle(preparations, prepared), admitted.value,
    requireHandle(definitions, definition)), 'RunHostBindingRejected');
}

export function issueSourceFreeInvocation(prepared, compilation, admission,
  definition, dataPolicyCid, limits) {
  if (typeof dataPolicyCid !== 'string') {
    throw new TypeError('InvalidRunHostDataPolicy');
  }
  const compiled = requireHandle(compilations, compilation);
  if (compiled.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  checkRunBinding(prepared, admission, definition);
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  const facts = checked(owner.clientValuesHostIssueSourceFreeInvocation(
    compiled.value, dataPolicyCid, maxWireBytes, maxNodes, maxDepth),
  'RunHostInvocationRejected');
  if (!Array.isArray(facts) || facts.length !== 4 ||
      !facts.every(value => typeof value === 'string')) {
    throw new Error('InvalidRunHostInvocationProjection');
  }
  const observation = admitRunEvidenceValue('observation_set', facts[1],
    limits);
  const invocation = admitPublicationContract('run_invocation', facts[3],
    limits);
  if (observation.cid !== facts[0] || invocation.cid !== facts[2]) {
    throw new Error('InvalidRunHostInvocationProjection');
  }
  return Object.freeze({observation, invocation});
}

export function issueSourceFreeTaskInvocation(prepared, compilation,
  admission, definition, dataPolicyCid, limits) {
  if (typeof dataPolicyCid !== 'string') {
    throw new TypeError('InvalidRunHostDataPolicy');
  }
  const compiled = requireHandle(taskCompilations, compilation);
  if (compiled.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  checkRunBinding(prepared, admission, definition);
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  const facts = checked(owner.clientValuesHostIssueSourceFreeTaskInvocation(
    compiled.value, dataPolicyCid, maxWireBytes, maxNodes, maxDepth),
  'RunHostTaskInvocationRejected');
  if (!Array.isArray(facts) || facts.length !== 4 ||
      !facts.every(value => typeof value === 'string')) {
    throw new Error('InvalidRunHostTaskInvocationProjection');
  }
  const observation = admitRunEvidenceValue('observation_set', facts[1],
    limits);
  const invocation = admitPublicationContract('run_invocation', facts[3],
    limits);
  if (observation.cid !== facts[0] || invocation.cid !== facts[2]) {
    throw new Error('InvalidRunHostTaskInvocationProjection');
  }
  return Object.freeze({observation, invocation});
}

// Source Evidence may enter an acquired task Run only when the admitted
// logical input, checked source, and current Host scope agree. The Host still
// owns authorization and the live capture; this identity grants neither.
export function admitCompletedSourceObservation({sourceEvidenceWire,
  inputLogicalWire, sourceRef, sourceContractCid, authorityScopeCid,
  effectiveDataPolicyCid,
  limits}) {
  if ([sourceEvidenceWire, inputLogicalWire, sourceRef,
    sourceContractCid, authorityScopeCid, effectiveDataPolicyCid].some(value =>
    typeof value !== 'string')) {
    throw new TypeError('InvalidRunHostSourceObservation');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return checked(owner.clientValuesHostAdmitCompletedSourceObservation(
    sourceEvidenceWire, inputLogicalWire, sourceRef, sourceContractCid,
    authorityScopeCid, effectiveDataPolicyCid, maxWireBytes, maxNodes,
    maxDepth),
  'RunHostSourceObservationRejected');
}

export function issueTaskInvocation(prepared, compilation, admission,
  definition, {sourceEvidenceWire, inputLogicalWire, sourceRef,
    sourceContractCid, authorityScopeCid, dataPolicyCid,
    captureStartedAt, captureCompletedAt}, limits) {
  const compiled = requireHandle(taskCompilations, compilation);
  if (compiled.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  checkRunBinding(prepared, admission, definition);
  if ([sourceEvidenceWire, inputLogicalWire, sourceRef, sourceContractCid,
    authorityScopeCid, dataPolicyCid, captureStartedAt, captureCompletedAt]
    .some(value => typeof value !== 'string') ||
    ![captureStartedAt, captureCompletedAt].every(value =>
      /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/u.test(value) &&
      Number.isFinite(Date.parse(value)) &&
      new Date(value).toISOString() === value) ||
    captureStartedAt > captureCompletedAt) {
    throw new TypeError('InvalidRunHostTaskObservation');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  const facts = checked(owner.clientValuesHostIssueTaskInvocation(
    requireHandle(preparations, prepared), compiled.value,
    requireHandle(admissions, admission).value,
    requireHandle(definitions, definition), sourceEvidenceWire,
    inputLogicalWire, sourceRef,
    sourceContractCid, authorityScopeCid, dataPolicyCid,
    captureStartedAt, captureCompletedAt, maxWireBytes, maxNodes,
    maxDepth), 'RunHostTaskInvocationRejected');
  if (!Array.isArray(facts) || facts.length !== 4 ||
      !facts.every(value => typeof value === 'string')) {
    throw new Error('InvalidRunHostTaskInvocationProjection');
  }
  const observation = admitRunEvidenceValue('observation_set', facts[1],
    limits);
  const invocation = admitPublicationContract('run_invocation', facts[3],
    limits);
  if (observation.cid !== facts[0] || invocation.cid !== facts[2]) {
    throw new Error('InvalidRunHostTaskInvocationProjection');
  }
  return Object.freeze({observation, invocation});
}

const siteSelectionKeys = ['taskAttempt', 'dispatchId', 'siteKey',
  'siteGeneration', 'runtimeBundleCid', 'connectorRegistration',
  'connectorRevision', 'strategyRevision', 'obligationsCid', 'budgetCid',
  'evidenceIssuerCapabilityCid', 'grantCid'];

/** Checked topology only: no producer completion, holding or start authority. */
export function prepareRetainedTaskInputEdge(prepared, compilation, admission,
  definition, consumerTask, inputIndex) {
  if (![consumerTask, inputIndex].every(value => Number.isSafeInteger(value) &&
      value >= 0 && value <= 2147483647)) {
    throw new TypeError('InvalidRunHostRetainedInputEdge');
  }
  const compiled = requireHandle(taskCompilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const edge = checked(owner.clientValuesHostRetainedInputEdge(
    requireHandle(preparations, prepared), compiled.value, admitted.value,
    requireHandle(definitions, definition), consumerTask, inputIndex),
  'RunHostRetainedInputEdgeRejected');
  return handle(retainedInputEdges, edge, 'retained-input-edge');
}

/** Carrier port identity and physical schema identity remain distinct. */
export function retainedTaskInputEdgeFacts(edge) {
  const values = owner.clientValuesHostRetainedInputEdgeFacts(
    requireHandle(retainedInputEdges, edge));
  if (!Array.isArray(values) || values.length !== 9 ||
      !values.every(value => typeof value === 'string')) {
    throw new Error('InvalidRunHostRetainedInputEdgeProjection');
  }
  const [runDefinitionCid, producerTaskKey, producerOutputPort,
    producerLogicalCid, carrierContractCid, consumerTaskKey,
    consumerLogicalCid, consumerInputPort, physicalSchemaCid] = values;
  return Object.freeze({runDefinitionCid, producerTaskKey, producerOutputPort,
    producerLogicalCid, carrierContractCid, consumerTaskKey,
    consumerLogicalCid, consumerInputPort, physicalSchemaCid});
}

/** The trusted Host must read its current durable Coordinator owner here. */
export function prepareRetainedInputProducer(edge, readCurrent) {
  const ownedEdge = requireHandle(retainedInputEdges, edge);
  if (typeof readCurrent !== 'function') {
    throw new TypeError('InvalidRunHostRetainedProducerCurrent');
  }
  const current = () => {
    const value = readCurrent();
    if (value === null || typeof value !== 'object' || Array.isArray(value) ||
        Object.keys(value).sort().join('\0') !== 'authority\0durableRecordWire' ||
        typeof value.authority !== 'string' ||
        typeof value.durableRecordWire !== 'string') {
      throw new TypeError('InvalidRunHostRetainedProducerCurrent');
    }
    return [value.authority, value.durableRecordWire];
  };
  const producer = checked(owner.clientValuesHostRetainedInputProducer(
    ownedEdge, current), 'RunHostRetainedProducerRejected');
  return handle(retainedInputProducers, producer, 'retained-input-producer');
}

export function retainedInputProducerAvailable(producer) {
  return owner.clientValuesHostRetainedInputProducerAvailable(
    requireHandle(retainedInputProducers, producer));
}

/** Historical canonical evidence; it grants no read, borrow or dispatch. */
export function retainedInputProducerFacts(producer) {
  const values = checked(owner.clientValuesHostRetainedInputProducerFacts(
    requireHandle(retainedInputProducers, producer)),
  'RunHostRetainedProducerRejected');
  if (!Array.isArray(values) || values.length !== 6 ||
      !values.every(value => typeof value === 'string')) {
    throw new Error('InvalidRunHostRetainedProducerProjection');
  }
  const [dispatchCid, dispatchWire, evidenceCid, evidenceWire,
    subjectCid, subjectWire] = values;
  return Object.freeze({dispatch: Object.freeze({cid: dispatchCid, wire: dispatchWire}),
    evidence: Object.freeze({cid: evidenceCid, wire: evidenceWire}),
    subject: Object.freeze({cid: subjectCid, wire: subjectWire})});
}

const retainedPlanPolicyKeys = ['destinationGrantCid', 'routeCapabilityCid',
  'sourceGrantCid', 'transferAttempt', 'transferExpiresUnixMs', 'transferMaxBytes'];
const retainedPlanCurrentKeys = ['siteBindingCurrent', 'authority', 'nowUnixMs', 'authorized'];
const retainedPlanLimitKeys = ['maxChunks', 'maxManifestBytes', 'maxReferencedBytes'];
const retainedInt64Maximum = 9223372036854775807n;
const exactRetainedFields = (value, keys) => value !== null &&
  typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');
const retainedWire = value => exactRetainedFields(value, ['cid', 'wire']) &&
  typeof value.cid === 'string' && typeof value.wire === 'string';

/** The checked producer supplies every edge and completion field. */
export function prepareRetainedInputIntent(producer, policy) {
  const owned = requireHandle(retainedInputProducers, producer);
  if (!exactRetainedFields(policy, retainedPlanPolicyKeys) ||
      retainedPlanPolicyKeys.slice(0, 4).some(key => typeof policy[key] !== 'string') ||
      ['transferExpiresUnixMs', 'transferMaxBytes'].some(key =>
        typeof policy[key] !== 'bigint' || policy[key] < 1n ||
        policy[key] > retainedInt64Maximum)) {
    throw new TypeError('InvalidRunHostRetainedInputPolicy');
  }
  const value = checked(owner.clientValuesHostPrepareRetainedInputIntent(owned,
    policy.destinationGrantCid, policy.routeCapabilityCid, policy.sourceGrantCid,
    policy.transferAttempt, policy.transferExpiresUnixMs, policy.transferMaxBytes),
  'RunHostRetainedInputIntentRejected');
  return handle(retainedInputIntents, {producer: owned, value}, 'retained-input-intent');
}

/** Restore original saved bytes, not another intent or refreshed lifetime. */
export function admitRetainedInputIntent(producer, saved) {
  const owned = requireHandle(retainedInputProducers, producer);
  if (!retainedWire(saved)) throw new TypeError('InvalidRunHostRetainedInputIntentWire');
  const value = checked(owner.clientValuesHostAdmitRetainedInputIntent(
    owned, saved.wire, saved.cid), 'RunHostRetainedInputIntentRejected');
  return handle(retainedInputIntents, {producer: owned, value}, 'retained-input-intent');
}

/** Historical projection only; it is not current delivery permission. */
export function retainedInputIntentFacts(intent) {
  const values = owner.clientValuesHostRetainedInputIntentFacts(
    requireHandle(retainedInputIntents, intent).value);
  if (!Array.isArray(values) || values.length !== 2 ||
      !values.every(value => typeof value === 'string')) {
    throw new Error('InvalidRunHostRetainedInputIntentProjection');
  }
  return Object.freeze({cid: values[0], wire: values[1]});
}

/** Checked original poll envelope, before the Native physical manifest exists. */
export function retainedInputPlanEnvelope(intent) {
  const owned = requireHandle(retainedInputIntents, intent);
  return checked(owner.clientValuesHostRetainedInputPlanEnvelope(
    owned.producer, owned.value), 'RunHostRetainedInputIntentRejected');
}

/** Current trusted scope is required even when restoring a saved Native plan. */
export function admitRetainedInputPlan(intent, saved, current, limits) {
  const owned = requireHandle(retainedInputIntents, intent);
  if (!retainedWire(saved)) throw new TypeError('InvalidRunHostRetainedInputPlanWire');
  if (!exactRetainedFields(current, retainedPlanCurrentKeys) ||
      retainedPlanCurrentKeys.some(key => typeof current[key] !== 'function')) {
    throw new TypeError('InvalidRunHostRetainedPlanCurrent');
  }
  if (!exactRetainedFields(limits, retainedPlanLimitKeys) ||
      ['maxChunks', 'maxManifestBytes'].some(key =>
        !Number.isSafeInteger(limits[key]) || limits[key] < 1 || limits[key] > 2147483647) ||
      typeof limits.maxReferencedBytes !== 'bigint' || limits.maxReferencedBytes < 1n ||
      limits.maxReferencedBytes > retainedInt64Maximum) {
    throw new TypeError('InvalidRunHostRetainedPlanLimits');
  }
  // Capture ports, not their first successful answers. Every validation reads
  // current trusted state; changing an object's properties cannot swap ports.
  const {siteBindingCurrent, authority, nowUnixMs, authorized} = current;
  const booleanResult = (value, code) => {
    if (typeof value !== 'boolean') throw new TypeError(code);
    return value;
  };
  const value = checked(owner.clientValuesHostAdmitRetainedInputPlan(
    owned.producer, owned.value, saved.wire, saved.cid,
    (key, generation, bundle) => booleanResult(
      siteBindingCurrent(key, Number(generation), bundle), 'InvalidRunHostRetainedSiteCurrent'),
    () => {
      const value = authority();
      if (typeof value !== 'string') throw new TypeError('InvalidRunHostRetainedAuthority');
      return value;
    },
    () => {
      const value = nowUnixMs();
      if (typeof value !== 'bigint' || value < 0n || value > retainedInt64Maximum) {
        throw new TypeError('InvalidRunHostRetainedClock');
      }
      return value;
    },
    (dispatchCid, requestWire) => booleanResult(authorized(dispatchCid, requestWire),
      'InvalidRunHostRetainedAuthorization'),
    limits.maxChunks, limits.maxManifestBytes, limits.maxReferencedBytes),
  'RunHostRetainedInputPlanRejected');
  return handle(retainedInputPlans, value, 'retained-input-plan');
}

/** Revalidate after persistence and immediately before delivery. */
export function validateRetainedInputPlan(plan) {
  checked(owner.clientValuesHostValidateRetainedInputPlan(
    requireHandle(retainedInputPlans, plan)), 'RunHostRetainedInputPlanRejected');
}

/** Immutable originals only; no reservation, borrow, payload or start claim. */
export function retainedInputPlanFacts(plan) {
  const values = checked(owner.clientValuesHostRetainedInputPlanFacts(
    requireHandle(retainedInputPlans, plan)), 'RunHostRetainedInputPlanRejected');
  if (!Array.isArray(values) || values.length !== 6 ||
      !values.every(value => typeof value === 'string')) {
    throw new Error('InvalidRunHostRetainedInputPlanProjection');
  }
  return Object.freeze({cid: values[0], wire: values[1],
    transfer: Object.freeze({cid: values[2], wire: values[3]}),
    manifest: Object.freeze({cid: values[4], wire: values[5]})});
}

/** Revalidate the original checked plan against live Owners before delivery. */
export function retainedInputTransferEnvelope(plan) {
  return checked(owner.clientValuesHostRetainedInputTransferEnvelope(
    requireHandle(retainedInputPlans, plan)), 'RunHostRetainedInputPlanRejected');
}

/** Historical committed receipt, never current custody or consumer authority. */
export function admitRetainedInputResult(plan, saved) {
  const owned = requireHandle(retainedInputPlans, plan);
  if (!retainedWire(saved)) throw new TypeError('InvalidRunHostRetainedInputResultWire');
  const value = checked(owner.clientValuesHostAdmitRetainedInputResult(
    owned, saved.wire, saved.cid), 'RunHostRetainedInputResultRejected');
  return handle(retainedInputResults, value, 'retained-input-result');
}

/** These immutable facts must be persisted and joined to current trusted Owners. */
export function retainedInputResultFacts(result) {
  const values = checked(owner.clientValuesHostRetainedInputResultFacts(
    requireHandle(retainedInputResults, result)), 'RunHostRetainedInputResultRejected');
  if (!Array.isArray(values) || values.length !== 7 ||
      !values.every(value => typeof value === 'string')) {
    throw new Error('InvalidRunHostRetainedInputResultProjection');
  }
  return Object.freeze({cid: values[0], wire: values[1], planCid: values[2],
    transferReply: Object.freeze({requestCid: values[3], wire: values[4]}),
    receipt: Object.freeze({cid: values[5], wire: values[6]})});
}

/** The caller uses a new challenge for each authenticated live receiver query. */
export function prepareRetainedInputCurrentQuery(plan, queryId) {
  if (typeof queryId !== 'string') throw new TypeError('InvalidRunHostRetainedInputQuery');
  const value = checked(owner.clientValuesHostPrepareRetainedInputCurrentQuery(
    requireHandle(retainedInputPlans, plan), queryId), 'RunHostRetainedInputCurrentRejected');
  return handle(retainedInputCurrentQueries, value, 'retained-input-current-query');
}

/** Revalidate current plan authority before offering the same exact query. */
export function retainedInputCurrentEnvelope(query) {
  return checked(owner.clientValuesHostRetainedInputCurrentEnvelope(
    requireHandle(retainedInputCurrentQueries, query)), 'RunHostRetainedInputCurrentRejected');
}

/** Admit an exact live response; a stored reply never becomes current authority. */
export function admitRetainedInputCurrentReply(query, saved, limits) {
  const owned = requireHandle(retainedInputCurrentQueries, query);
  if (!retainedWire(saved)) throw new TypeError('InvalidRunHostRetainedInputCurrentWire');
  if (!exactRetainedFields(limits, retainedPlanLimitKeys) ||
      ['maxChunks', 'maxManifestBytes'].some(key =>
        !Number.isSafeInteger(limits[key]) || limits[key] < 1 || limits[key] > 2147483647) ||
      typeof limits.maxReferencedBytes !== 'bigint' || limits.maxReferencedBytes < 1n ||
      limits.maxReferencedBytes > retainedInt64Maximum) {
    throw new TypeError('InvalidRunHostRetainedInputCurrentLimits');
  }
  const value = checked(owner.clientValuesHostAdmitRetainedInputCurrentReply(
    owned, saved.wire, saved.cid, limits.maxChunks, limits.maxManifestBytes,
    limits.maxReferencedBytes), 'RunHostRetainedInputCurrentRejected');
  return handle(retainedInputCurrentReplies, value, 'retained-input-current-reply');
}

/** Immutable snapshot, not permission to borrow, reserve, start or replay. */
export function retainedInputCurrentReplyFacts(reply) {
  const values = checked(owner.clientValuesHostRetainedInputCurrentReplyFacts(
    requireHandle(retainedInputCurrentReplies, reply)), 'RunHostRetainedInputCurrentRejected');
  if (!Array.isArray(values) || values.length !== 5 ||
      !values.every(value => typeof value === 'string')) {
    throw new Error('InvalidRunHostRetainedInputCurrentProjection');
  }
  return Object.freeze({cid: values[0], wire: values[1], transferRecordWire: values[2],
    receipt: Object.freeze({cid: values[3], wire: values[4]})});
}

const retainedCurrentKeys = ['readTransfer', 'siteBindingCurrent', 'authority',
  'nowUnixMs', 'authorized'];

/** Ports must query existing current owners, never the saved binding itself. */
export function prepareRetainedTaskInput(producer, receipt, destinationUseId,
  current, limits) {
  const owned = requireHandle(retainedInputProducers, producer);
  if (receipt === null || typeof receipt !== 'object' || Array.isArray(receipt) ||
      Object.keys(receipt).sort().join('\0') !== 'cid\0wire' ||
      typeof receipt.cid !== 'string' || typeof receipt.wire !== 'string' ||
      typeof destinationUseId !== 'string' || !destinationUseId ||
      current === null || typeof current !== 'object' || Array.isArray(current) ||
      Object.keys(current).sort().join('\0') !== [...retainedCurrentKeys].sort().join('\0') ||
      retainedCurrentKeys.some(key => typeof current[key] !== 'function')) {
    throw new TypeError('InvalidRunHostRetainedInputCurrent');
  }
  if (limits === null || typeof limits !== 'object' || Array.isArray(limits) ||
      Object.keys(limits).sort().join('\0') !==
        'maxBindingBytes\0maxChunks\0maxManifestBytes\0maxReferencedBytes' ||
      ['maxBindingBytes', 'maxChunks', 'maxManifestBytes'].some(key =>
        !Number.isSafeInteger(limits[key]) || limits[key] < 1 || limits[key] > 2147483647) ||
      typeof limits.maxReferencedBytes !== 'bigint' || limits.maxReferencedBytes < 1n ||
      limits.maxReferencedBytes > 9223372036854775807n) {
    throw new TypeError('InvalidRunHostRetainedInputLimits');
  }
  // Capture the installed functions so replacing properties cannot replace an
  // Owner port; each invocation still reads that Owner's current live state.
  const {readTransfer, siteBindingCurrent, authority, nowUnixMs, authorized} = current;
  const stringResult = (read, code) => () => {
    const value = read();
    if (typeof value !== 'string') throw new TypeError(code);
    return value;
  };
  const booleanResult = (value, code) => {
    if (typeof value !== 'boolean') throw new TypeError(code);
    return value;
  };
  const input = checked(owner.clientValuesHostPrepareRetainedTaskInput(owned,
    stringResult(readTransfer, 'InvalidRunHostRetainedTransferCurrent'),
    receipt.wire, receipt.cid, destinationUseId,
    (key, generation, bundle) => booleanResult(
      siteBindingCurrent(key, Number(generation), bundle),
      'InvalidRunHostRetainedSiteCurrent'),
    stringResult(authority, 'InvalidRunHostRetainedAuthority'),
    () => {
      const value = nowUnixMs();
      if (typeof value !== 'bigint' || value < 0n || value > 9223372036854775807n) {
        throw new TypeError('InvalidRunHostRetainedClock');
      }
      return value;
    },
    (dispatchCid, transferRequestWire) => booleanResult(
      authorized(dispatchCid, transferRequestWire),
      'InvalidRunHostRetainedAuthorization'),
    limits.maxChunks, limits.maxManifestBytes, limits.maxReferencedBytes,
    limits.maxBindingBytes), 'RunHostRetainedTaskInputRejected');
  return handle(retainedTaskInputs, input, 'retained-task-input');
}

/** Restore the exact saved binding against newly installed current owners. */
export function admitRetainedTaskInput(producer, saved, receipt,
  destinationUseId, current, limits) {
  if (saved === null || typeof saved !== 'object' || Array.isArray(saved) ||
      Object.keys(saved).sort().join('\0') !== 'cid\0wire' ||
      typeof saved.cid !== 'string' || typeof saved.wire !== 'string') {
    throw new TypeError('InvalidRunHostRetainedTaskInputWire');
  }
  const restored = prepareRetainedTaskInput(producer, receipt, destinationUseId,
    current, limits);
  const value = checked(owner.clientValuesHostAdmitRetainedTaskInput(
    requireHandle(retainedTaskInputs, restored), saved.wire, saved.cid),
  'RunHostRetainedTaskInputRejected');
  return handle(retainedTaskInputs, value, 'retained-task-input');
}

export function validateRetainedTaskInput(input) {
  checked(owner.clientValuesHostValidateRetainedTaskInput(
    requireHandle(retainedTaskInputs, input)), 'RunHostRetainedTaskInputRejected');
}

/** Historical wire grants no physical material access or start claim. */
export function retainedTaskInputFacts(input) {
  const values = owner.clientValuesHostRetainedTaskInputFacts(
    requireHandle(retainedTaskInputs, input));
  if (!Array.isArray(values) || values.length !== 2 ||
      !values.every(value => typeof value === 'string')) {
    throw new Error('InvalidRunHostRetainedTaskInputProjection');
  }
  return Object.freeze({cid: values[0], wire: values[1]});
}

export function issueRetainedTaskDispatch(prepared, compilation, admission,
  definition, request, task, selection, input) {
  if (!Number.isSafeInteger(task) || task < 0 || task > 2147483647 ||
      selection === null || typeof selection !== 'object' || Array.isArray(selection) ||
      Object.keys(selection).sort().join('\0') !== [...siteSelectionKeys].sort().join('\0') ||
      !Number.isSafeInteger(selection.taskAttempt) ||
      !Number.isSafeInteger(selection.siteGeneration) ||
      siteSelectionKeys.slice(1).filter(key => key !== 'siteGeneration')
        .some(key => typeof selection[key] !== 'string')) {
    throw new TypeError('InvalidRunHostSiteSelection');
  }
  const compiled = requireHandle(taskCompilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const source = sourcePreparations.get(prepared);
  const args = [
    requireHandle(preparations, prepared), compiled.value, admitted.value,
    requireHandle(definitions, definition), requireHandle(requests, request),
    task, selection.taskAttempt, selection.dispatchId, selection.siteKey,
    selection.siteGeneration, selection.runtimeBundleCid,
    selection.connectorRegistration, selection.connectorRevision,
    selection.strategyRevision, selection.obligationsCid, selection.budgetCid,
    selection.evidenceIssuerCapabilityCid, selection.grantCid,
    requireHandle(retainedTaskInputs, input)];
  const dispatch = checked(source === undefined
    ? owner.clientValuesHostPrepareRetainedTaskDispatch(...args)
    : owner.clientValuesHostPrepareRetainedTaskDispatchWithSource(...args, source.value), 'RunHostRetainedTaskDispatchRejected');
  return Object.freeze({cid: owner.clientValuesHostDispatchCid(dispatch),
    wire: checked(owner.clientValuesHostDispatchWire(dispatch),
      'RunHostRetainedTaskDispatchRejected')});
}

export function issueTaskDispatch(prepared, compilation, admission,
  definition, request, task, selection) {
  if (!Number.isSafeInteger(task) || task < 0 || task > 2147483647 ||
      selection === null || typeof selection !== 'object' ||
      Array.isArray(selection) ||
      Object.keys(selection).sort().join('\0') !==
        [...siteSelectionKeys].sort().join('\0') ||
      !Number.isSafeInteger(selection.taskAttempt) ||
      !Number.isSafeInteger(selection.siteGeneration) ||
      siteSelectionKeys.slice(1).filter(key => key !== 'siteGeneration')
        .some(key => typeof selection[key] !== 'string')) {
    throw new TypeError('InvalidRunHostSiteSelection');
  }
  const compiled = requireHandle(taskCompilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const source = sourcePreparations.get(prepared);
  const args = [
    requireHandle(preparations, prepared), compiled.value, admitted.value,
    requireHandle(definitions, definition), requireHandle(requests, request),
    task, selection.taskAttempt, selection.dispatchId, selection.siteKey,
    selection.siteGeneration, selection.runtimeBundleCid,
    selection.connectorRegistration, selection.connectorRevision,
    selection.strategyRevision, selection.obligationsCid,
    selection.budgetCid, selection.evidenceIssuerCapabilityCid,
    selection.grantCid];
  const dispatch = checked(source === undefined
    ? owner.clientValuesHostPrepareTaskDispatch(...args)
    : owner.clientValuesHostPrepareTaskDispatchWithSource(...args, source.value), 'RunHostDispatchRejected');
  return Object.freeze({cid: owner.clientValuesHostDispatchCid(dispatch),
    wire: checked(owner.clientValuesHostDispatchWire(dispatch),
      'RunHostDispatchRejected')});
}

// The current Host authorization and Site policy decision precede issuance.
// The returned canonical wire is identity material, not a Site credential.
export function issueSourceFreeDispatch(prepared, compilation, admission,
  definition, request, selection) {
  if (selection === null || typeof selection !== 'object' ||
      Array.isArray(selection) ||
      Object.keys(selection).sort().join('\0') !==
        [...siteSelectionKeys].sort().join('\0') ||
      !Number.isSafeInteger(selection.taskAttempt) ||
      !Number.isSafeInteger(selection.siteGeneration) ||
      siteSelectionKeys.slice(1).filter(key => key !== 'siteGeneration')
        .some(key => typeof selection[key] !== 'string')) {
    throw new TypeError('InvalidRunHostSiteSelection');
  }
  const compiled = requireHandle(compilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const dispatch = checked(owner.clientValuesHostPrepareDispatch(
    requireHandle(preparations, prepared), compiled.value, admitted.value,
    requireHandle(definitions, definition), requireHandle(requests, request),
    selection.taskAttempt, selection.dispatchId, selection.siteKey,
    selection.siteGeneration, selection.runtimeBundleCid,
    selection.connectorRegistration, selection.connectorRevision,
    selection.strategyRevision, selection.obligationsCid,
    selection.budgetCid, selection.evidenceIssuerCapabilityCid,
    selection.grantCid), 'RunHostDispatchRejected');
  return Object.freeze({cid: owner.clientValuesHostDispatchCid(dispatch),
    wire: checked(owner.clientValuesHostDispatchWire(dispatch),
      'RunHostDispatchRejected')});
}

function publicationLimits(limits) {
  if (limits === null || typeof limits !== 'object' ||
      !['maxWireBytes', 'maxNodes', 'maxDepth'].every(key =>
        Number.isSafeInteger(limits[key]) && limits[key] > 0 &&
        limits[key] <= 2147483647)) {
    throw new TypeError('InvalidRunHostPublicationLimits');
  }
  return limits;
}

function publicationContract(value) {
  const token = handle(publicationContracts, value, 'publication-contract');
  const contract = Object.freeze({token,
    cid: owner.clientValuesHostPublicationContractIdentity(value),
    wire: owner.clientValuesHostPublicationContractWire(value)});
  publicationOriginals.set(contract, Object.freeze({value,
    cid: contract.cid, wire: contract.wire}));
  return contract;
}

function runEvidence(value) {
  const token = handle(runEvidences, value, 'run-evidence');
  return Object.freeze({token,
    cid: owner.clientValuesHostRunEvidenceValueIdentity(value),
    wire: owner.clientValuesHostRunEvidenceValueWire(value)});
}

export function admitRunEvidenceValue(name, wire, limits) {
  if (typeof name !== 'string' || typeof wire !== 'string') {
    throw new TypeError('InvalidRunHostEvidence');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return runEvidence(checked(owner.clientValuesHostAdmitRunEvidenceValue(
    name, wire, maxWireBytes, maxNodes, maxDepth),
  'RunHostEvidenceRejected'));
}

export function sealRunEvidenceValue(name, bodyWire, limits) {
  if (typeof name !== 'string' || typeof bodyWire !== 'string') {
    throw new TypeError('InvalidRunHostEvidence');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return runEvidence(checked(owner.clientValuesHostSealRunEvidenceValue(
    name, bodyWire, maxWireBytes, maxNodes, maxDepth),
  'RunHostEvidenceRejected'));
}

// Canonical admission and chain decisions belong to the portable owner.
// A contract handle is in-process only and conveys no publication authority.
export function admitPublicationContract(name, wire, limits) {
  if (typeof name !== 'string' || typeof wire !== 'string') {
    throw new TypeError('InvalidRunHostPublicationContract');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  const value = checked(owner.clientValuesHostAdmitPublicationContract(
    name, wire, maxWireBytes, maxNodes, maxDepth),
  'RunHostPublicationContractRejected');
  return publicationContract(value);
}

function publicationToken(contract) {
  return requireHandle(publicationContracts, contract?.token);
}

export function projectPublicationSnapshot(record, index) {
  if (index === null || typeof index !== 'object' ||
      Array.isArray(index) ||
      !['absent', 'unknown', 'committed'].includes(index.kind) ||
      Object.keys(index).sort().join('\0') !==
        (index.kind === 'committed' ? 'entry\0kind' : 'kind')) {
    throw new TypeError('InvalidRunHostIndexObservation');
  }
  const mode = index.kind === 'absent' ? 0 :
    index.kind === 'unknown' ? 1 : 2;
  const facts = checked(owner.clientValuesHostProjectPublicationSnapshot(
    record === undefined ? undefined : publicationToken(record), mode,
    mode === 2 ? publicationToken(index.entry) : undefined),
  'RunHostPublicationSnapshotRejected');
  if (!Array.isArray(facts) || facts.length !== 2 ||
      !facts.every(value => typeof value === 'string')) {
    throw new Error('InvalidRunHostPublicationSnapshot');
  }
  return Object.freeze({state: facts[0],
    evidenceCid: facts[1] || undefined});
}

export function publicationIndexScopeKey(ref, limits) {
  if (ref === null || typeof ref !== 'object' || Array.isArray(ref) ||
      Object.keys(ref).sort().join('\0') !==
        'authorityScopeCid\0namespaceId\0runDefinitionCid' ||
      !['namespaceId', 'authorityScopeCid', 'runDefinitionCid']
        .every(key => typeof ref[key] === 'string')) {
    throw new TypeError('InvalidRunHostPublicationIndexScope');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return checked(owner.clientValuesHostPublicationIndexScopeKey(
    ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid,
    maxWireBytes, maxNodes, maxDepth),
  'RunHostPublicationIndexScopeRejected');
}

function nonnegativeCount(value) {
  if (!Number.isSafeInteger(value) || value < 0 || value > 2147483647) {
    throw new TypeError('InvalidRunHostPublicationCount');
  }
  return value;
}

export function issueResultOccurrenceEvidence(definition, facts, limits) {
  if (facts === null || typeof facts !== 'object' ||
      !['logicalValueCid', 'resultSchemaCid', 'computationContractCid',
        'scopeCid', 'effectiveDataPolicyCid', 'issuerId',
        'authorityScopeCid'].every(key => typeof facts[key] === 'string') ||
      !Array.isArray(facts.inputRelationCids) ||
      !facts.inputRelationCids.every(value => typeof value === 'string')) {
    throw new TypeError('InvalidRunHostResultEvidence');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  const value = checked(owner.clientValuesHostIssueResultOccurrenceEvidence(
    publicationToken(definition), facts.logicalValueCid,
    facts.resultSchemaCid, facts.computationContractCid,
    facts.inputRelationCids, facts.scopeCid,
    facts.effectiveDataPolicyCid, facts.issuerId,
    facts.authorityScopeCid, maxWireBytes, maxNodes, maxDepth),
  'RunHostResultEvidenceRejected');
  return resultOccurrence(value);
}

function resultOccurrence(value) {
  const token = handle(resultOccurrences, value, 'result-occurrence');
  return Object.freeze({token,
    derivation: publicationContract(
      owner.clientValuesHostResultOccurrenceDerivation(value)),
    ordering: publicationContract(
      owner.clientValuesHostResultOccurrenceOrdering(value))});
}

export function issueCheckedValuesResultOccurrenceEvidence(prepared,
  compilation, definition, facts, limits) {
  if (facts === null || typeof facts !== 'object' ||
      Object.keys(facts).sort().join('\0') !==
        ['logicalValueCid', 'resultSchemaCid', 'scopeCid',
          'effectiveDataPolicyCid', 'issuerId', 'authorityScopeCid']
          .sort().join('\0') ||
      Object.values(facts).some(value => typeof value !== 'string')) {
    throw new TypeError('InvalidRunHostCheckedResultEvidence');
  }
  const compiled = requireHandle(compilations, compilation);
  if (compiled.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  const value = checked(
    owner.clientValuesHostIssueCheckedValuesResultOccurrenceEvidence(
      requireHandle(preparations, prepared), compiled.value,
      publicationToken(definition), facts.logicalValueCid,
      facts.resultSchemaCid, facts.scopeCid,
      facts.effectiveDataPolicyCid, facts.issuerId,
      facts.authorityScopeCid, maxWireBytes, maxNodes, maxDepth),
    'RunHostCheckedResultEvidenceRejected');
  return resultOccurrence(value);
}

export function issueCompleteResultArtifact(definition, invocation,
  evidence, retention, actualRowCount, limits) {
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return publicationContract(checked(
    owner.clientValuesHostIssueCompleteResultArtifact(
      publicationToken(definition), publicationToken(invocation),
      requireHandle(resultOccurrences, evidence?.token),
      publicationToken(retention), nonnegativeCount(actualRowCount),
      maxWireBytes, maxNodes, maxDepth),
    'RunHostResultArtifactRejected'));
}

export function issueDurableResultBinding(runDefinition, definition,
  invocation, artifact, ordering, retention, physical, limits) {
  if (physical === null || typeof physical !== 'object' ||
      !['codecContractCid', 'resultSchemaWire', 'materialGenerationCid',
        'storeAuthorityCid', 'physicalSha256'].every(key =>
        typeof physical[key] === 'string') ||
      !Array.isArray(physical.resultFields) ||
      !physical.resultFields.every(value => typeof value === 'string')) {
    throw new TypeError('InvalidRunHostDurableBinding');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return publicationContract(checked(
    owner.clientValuesHostIssueDurableResultBinding(
      publicationToken(runDefinition), publicationToken(definition),
      publicationToken(invocation), publicationToken(artifact),
      publicationToken(ordering), publicationToken(retention),
      physical.codecContractCid, physical.resultFields,
      physical.resultSchemaWire, physical.materialGenerationCid,
      physical.storeAuthorityCid, nonnegativeCount(physical.rowCount),
      nonnegativeCount(physical.byteCount), physical.physicalSha256,
      maxWireBytes, maxNodes, maxDepth),
    'RunHostDurableBindingRejected'));
}

export function inspectCanonicalResultRows(rowsWire, fields, limits) {
  if (typeof rowsWire !== 'string' || !Array.isArray(fields) ||
      !fields.every(value => typeof value === 'string')) {
    throw new TypeError('InvalidRunHostResultRows');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  const result = checked(owner.clientValuesHostInspectCanonicalResultRows(
    rowsWire, fields, maxWireBytes, maxNodes, maxDepth),
  'RunHostResultRowsRejected');
  if (!Array.isArray(result) || result.length !== 2 ||
      typeof result[0] !== 'string' ||
      !/^sha256:[0-9a-f]{64}$/u.test(result[0]) ||
      typeof result[1] !== 'string' ||
      !/^(0|[1-9][0-9]*)$/u.test(result[1])) {
    throw new Error('InvalidRunHostResultRowsProjection');
  }
  const rowCount = Number(result[1]);
  if (!Number.isSafeInteger(rowCount)) {
    throw new Error('InvalidRunHostResultRowsProjection');
  }
  return Object.freeze({logicalRelationCid: result[0], rowCount});
}

export function issueResultManifest(runDefinition, invocation,
  definitions, artifacts, limits) {
  if (!Array.isArray(definitions) || !Array.isArray(artifacts)) {
    throw new TypeError('InvalidRunHostPublicationChain');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return publicationContract(checked(owner.clientValuesHostIssueResultManifest(
    publicationToken(runDefinition), publicationToken(invocation),
    definitions.map(publicationToken), artifacts.map(publicationToken),
    maxWireBytes, maxNodes, maxDepth), 'RunHostResultManifestRejected'));
}

export function validatePublicationChain(runDefinition, invocation,
  definitions, artifacts, manifest, limits) {
  if (!Array.isArray(definitions) || !Array.isArray(artifacts)) {
    throw new TypeError('InvalidRunHostPublicationChain');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  checked(owner.clientValuesHostValidatePublicationChain(
    publicationToken(runDefinition), publicationToken(invocation),
    definitions.map(publicationToken), artifacts.map(publicationToken),
    publicationToken(manifest), maxWireBytes, maxNodes, maxDepth),
  'RunHostPublicationChainRejected');
}

export function validatePublicationRecordTransition(previous, next,
  uncommittedConfirmed) {
  if (typeof uncommittedConfirmed !== 'boolean') {
    throw new TypeError('InvalidRunHostPublicationTransition');
  }
  checked(owner.clientValuesHostValidatePublicationRecordTransition(
    previous === undefined ? undefined : publicationToken(previous),
    publicationToken(next), uncommittedConfirmed),
  'RunHostPublicationTransitionRejected');
}

function publicationItems(values) {
  if (!Array.isArray(values)) throw new TypeError('InvalidRunHostInventory');
  return values.map(publicationToken);
}

export function issuePublicationRequest(runDefinition, definitions, facts,
  limits) {
  if (facts === null || typeof facts !== 'object' ||
      ['namespaceId', 'authorityScopeCid', 'publicationPolicyCid',
        'publicationTargetCid', 'requestedAt'].some(key =>
        typeof facts[key] !== 'string')) {
    throw new TypeError('InvalidRunHostPublicationRequest');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return publicationContract(checked(
    owner.clientValuesHostIssuePublicationRequest(
      publicationToken(runDefinition), publicationItems(definitions),
      facts.namespaceId, facts.authorityScopeCid,
      facts.publicationPolicyCid, facts.publicationTargetCid,
      facts.requestedAt, maxWireBytes, maxNodes, maxDepth),
    'RunHostPublicationRequestRejected'));
}

export function issuePublicationAttempt(request, runDefinition, facts,
  limits) {
  if (facts === null || typeof facts !== 'object' ||
      ['attemptId', 'fenceCid', 'startedAt'].some(key =>
        typeof facts[key] !== 'string') ||
      facts.externalIdempotencyKey !== undefined &&
        typeof facts.externalIdempotencyKey !== 'string') {
    throw new TypeError('InvalidRunHostPublicationAttempt');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return publicationContract(checked(
    owner.clientValuesHostIssuePublicationAttempt(
      publicationToken(request), publicationToken(runDefinition),
      facts.attemptId, facts.fenceCid, facts.externalIdempotencyKey,
      facts.startedAt, maxWireBytes, maxNodes, maxDepth),
    'RunHostPublicationAttemptRejected'));
}

export function issuePublicIndexEntry(runDefinition, invocation, manifest,
  receipt, capturedRun, durableBindings, request, attempt, committedAt,
  limits) {
  if (typeof committedAt !== 'string') {
    throw new TypeError('InvalidRunHostPublicIndexEntry');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return publicationContract(checked(owner.clientValuesHostIssuePublicIndexEntry(
    publicationToken(runDefinition), publicationToken(invocation),
    publicationToken(manifest), publicationToken(receipt),
    publicationToken(capturedRun), publicationItems(durableBindings),
    publicationToken(request), publicationToken(attempt), committedAt,
    maxWireBytes, maxNodes, maxDepth), 'RunHostPublicIndexEntryRejected'));
}

export function validateEffectFreePublicationCommit(evidence, request,
  attempt, indexEntry, limits) {
  if (evidence === null || typeof evidence !== 'object' ||
      !Array.isArray(evidence.definitions) ||
      !Array.isArray(evidence.artifacts) ||
      !Array.isArray(evidence.derivations) ||
      !Array.isArray(evidence.orderings) ||
      !Array.isArray(evidence.retentions) ||
      !Array.isArray(evidence.durableBindings)) {
    throw new TypeError('InvalidRunHostPublicationCommit');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  checked(owner.clientValuesHostValidateEffectFreePublicationCommit(
    publicationToken(evidence.runDefinition),
    publicationToken(evidence.invocation),
    publicationItems(evidence.definitions),
    publicationItems(evidence.artifacts),
    publicationItems(evidence.derivations),
    publicationItems(evidence.orderings),
    publicationItems(evidence.retentions),
    publicationItems(evidence.durableBindings),
    publicationToken(evidence.manifest),
    publicationToken(evidence.receipt),
    publicationToken(evidence.capturedRun),
    publicationToken(request), publicationToken(attempt),
    publicationToken(indexEntry), maxWireBytes, maxNodes, maxDepth),
  'RunHostPublicationCommitRejected');
}

export function issuePublicationRecord(attempt, previous, facts, limits) {
  if (facts === null || typeof facts !== 'object' ||
      typeof facts.state !== 'string' ||
      typeof facts.observedAt !== 'string' ||
      facts.failureCid !== undefined &&
        typeof facts.failureCid !== 'string' ||
      !Array.isArray(facts.cleanupOwnerCids) ||
      !facts.cleanupOwnerCids.every(value => typeof value === 'string') ||
      typeof facts.uncommittedConfirmed !== 'boolean') {
    throw new TypeError('InvalidRunHostPublicationRecord');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return publicationContract(checked(owner.clientValuesHostIssuePublicationRecord(
    publicationToken(attempt), previous === undefined ? undefined :
      publicationToken(previous), facts.state, facts.observedAt,
    facts.publicIndexEntry === undefined ? undefined :
      publicationToken(facts.publicIndexEntry), facts.failureCid,
    facts.cleanupOwnerCids, facts.uncommittedConfirmed,
    maxWireBytes, maxNodes, maxDepth), 'RunHostPublicationRecordRejected'));
}

function evidenceItems(values) {
  if (!Array.isArray(values)) {
    throw new TypeError('InvalidRunHostEvidenceInventory');
  }
  return values.map(value => requireHandle(runEvidences, value?.token));
}

export function issueEffectFreeRunReceipt(admission, runDefinition,
  invocation, observation, definitions, artifacts, manifest,
  normalizationJournal, facts, limits) {
  if (facts === null || typeof facts !== 'object' ||
      !Array.isArray(facts.bindingNames) ||
      !facts.bindingNames.every(value => typeof value === 'string') ||
      !Array.isArray(facts.bindingDigests) ||
      !facts.bindingDigests.every(value => typeof value === 'string') ||
      !Array.isArray(facts.barrierAttemptReceiptCids) ||
      !facts.barrierAttemptReceiptCids.every(value =>
        typeof value === 'string')) {
    throw new TypeError('InvalidRunHostReceiptFacts');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return publicationContract(checked(
    owner.clientValuesHostIssueEffectFreeRunReceipt(
      requireHandle(admissions, admission).value,
      publicationToken(runDefinition), publicationToken(invocation),
      requireHandle(runEvidences, observation?.token),
      publicationItems(definitions), publicationItems(artifacts),
      publicationToken(manifest),
      requireHandle(runEvidences, normalizationJournal?.token),
      facts.bindingNames, facts.bindingDigests,
      evidenceItems(facts.sourceEvidence),
      evidenceItems(facts.modelEvidence),
      facts.barrierAttemptReceiptCids,
      maxWireBytes, maxNodes, maxDepth),
    'RunHostReceiptRejected'));
}

export function admitCapturedResultSnapshot(definition, artifact, rowsWire,
  fields, limits) {
  if (typeof rowsWire !== 'string' || !Array.isArray(fields) ||
      !fields.every(value => typeof value === 'string')) {
    throw new TypeError('InvalidRunHostCapturedRows');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  const snapshot = checked(owner.clientValuesHostAdmitCapturedResultSnapshot(
    publicationToken(definition), publicationToken(artifact), rowsWire,
    fields, maxWireBytes, maxNodes, maxDepth),
  'RunHostCapturedRowsRejected');
  return handle(capturedSnapshots, snapshot, 'captured-result-snapshot');
}

export function issueSourceFreeCapturedRun(runDefinition, invocation,
  definitions, artifacts, manifest, receipt, snapshots, authoring, models,
  limits) {
  return issueReadOnlyCapturedRun(runDefinition, invocation, definitions,
    artifacts, manifest, receipt, snapshots, authoring, models, limits);
}

// Read-only Sources, like Values, have no pending source-state advances.
// The same receipt and captured-computation owner validates the full chain.
export function issueReadOnlyCapturedRun(runDefinition, invocation,
  definitions, artifacts, manifest, receipt, snapshots, authoring, models,
  limits) {
  if (!Array.isArray(snapshots)) {
    throw new TypeError('InvalidRunHostCapturedInventory');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return publicationContract(checked(
    owner.clientValuesHostIssueSourceFreeCapturedRun(
      publicationToken(runDefinition), publicationToken(invocation),
      publicationItems(definitions), publicationItems(artifacts),
      publicationToken(manifest), publicationToken(receipt),
      snapshots.map(value => requireHandle(capturedSnapshots, value)),
      requireHandle(runEvidences, authoring?.token), evidenceItems(models),
      maxWireBytes, maxNodes, maxDepth),
    'RunHostCapturedRunRejected'));
}

// The portable publication service consumes this shape. Each view keeps its
// MoonBit handle in this instance; wire bytes and CIDs alone grant no access.
const deliveryViews = new WeakMap();
const accessProgress = new WeakMap();
const deliverySerializers = new WeakMap();
const durableRowFrames = new WeakMap();

function deliveryCall(method, ...args) {
  try { return owner[method](...args); }
  catch (cause) {
    throw Object.assign(new Error('RunHostDeliveryRejected', {cause}),
      {code: 'RunHostDeliveryRejected'});
  }
}

function deliveryResult(method, ...args) {
  return checked(deliveryCall(method, ...args), 'RunHostDeliveryRejected');
}

function deliveryView(contract, original) {
  const value = original === undefined
    ? publicationToken(contract) : original.value;
  const view = Object.freeze({
    name: owner.clientValuesHostPublicationContractName(value),
    identityField:
      owner.clientValuesHostPublicationContractIdentityField(value),
    identity: original === undefined ? contract.cid : original.cid,
    wire: original === undefined ? contract.wire : original.wire,
  });
  deliveryViews.set(view, contract);
  return view;
}

function deliveryToken(view) {
  return publicationToken(deliveryContract(view));
}

function deliveryContract(view) {
  const contract = deliveryViews.get(view);
  if (contract === undefined) throw new TypeError('ForeignRunHostDelivery');
  return contract;
}

function issuedDelivery(method, ...args) {
  return deliveryView(publicationContract(deliveryResult(method, ...args)));
}

// This is a semantic port for the existing common Result access service.
// The Host still supplies current authorization, trusted time, Store and sink.
export function openResultDeliveryControl() {
  const issuedGrantBounds = new WeakMap();
  const issuedAttempts = new WeakMap();
  const originalAttempts = new WeakMap();
  const sameBounds = (first, second) => first.length === second.length &&
    first.every((value, index) => value === second[index]);
  const limitsOf = limits => {
    const value = publicationLimits(limits);
    return [value.maxWireBytes, value.maxNodes, value.maxDepth];
  };
  const progressToken = progress => requireHandle(accessProgress, progress);
  const mark = (method, progress, value) =>
    deliveryCall(method, progressToken(progress), value);
  return Object.freeze({
    describeCommittedResult(index, manifest, resultName, bindings,
      definition, schemaWire, format, limits) {
      return describeCommittedResult(deliveryContract(index),
        deliveryContract(manifest), resultName,
        bindings.map(deliveryContract), deliveryContract(definition),
        schemaWire, format, limits);
    },
    resultMetadataRetentionState(retention, observedAt) {
      const value = owner.clientValuesHostResultMetadataRetentionState(
        deliveryToken(retention), observedAt);
      if (!['retained', 'delete_due'].includes(value)) {
        throw new Error('RunHostMetadataRetentionRejected');
      }
      return value;
    },
    issueManifestReadGrant(index, manifest, grant, limits) {
      return issuedDelivery('clientValuesHostIssueManifestReadGrant',
        deliveryToken(index), deliveryToken(manifest),
        grant.principalId, grant.purpose, grant.dataCeilingCid,
        grant.maxBytes, grant.maxUses, grant.expiresAt,
        grant.authorizationContextCid, ...limitsOf(limits));
    },
    manifestReadGrantValidAt(grant, at) {
      return deliveryCall('clientValuesHostManifestReadGrantValidAt',
        deliveryToken(grant), at);
    },
    manifestReadGrantAllowsBytes(grant, bytes) {
      return deliveryCall('clientValuesHostManifestReadGrantAllowsBytes',
        deliveryToken(grant), bytes);
    },
    admit(name, wire, limits) {
      return deliveryView(admitPublicationContract(name, wire, limits));
    },
    fromPublication(contract, expectedName) {
      const original = publicationOriginals.get(contract);
      if (original === undefined) {
        throw new TypeError('ForeignRunHostPublication');
      }
      const view = deliveryView(contract, original);
      if (expectedName !== undefined && view.name !== expectedName) {
        throw new TypeError('RunHostPublicationKindMismatch');
      }
      return view;
    },
    beginResultAccessProgress() {
      return handle(accessProgress,
        owner.clientValuesHostBeginResultAccessProgress(),
        'result-access-progress');
    },
    resultAccessProgressAction(progress) {
      return publicationAction('resultAccess',
        owner.clientValuesHostResultAccessProgressAction(progressToken(progress)));
    },
    recordResultAccessRequestAuthorization(progress, value) {
      return mark('clientValuesHostRecordResultAccessRequestAuthorization',
        progress, value);
    },
    recordResultAccessResolution(progress, value) {
      return mark('clientValuesHostRecordResultAccessResolution',
        progress, value);
    },
    recordResultAccessInitialAvailability(progress, value) {
      return mark('clientValuesHostRecordResultAccessInitialAvailability',
        progress, value);
    },
    recordResultAccessReadAdmission(progress, value) {
      return mark('clientValuesHostRecordResultAccessReadAdmission',
        progress, value);
    },
    recordResultAccessGrant(progress, value) {
      return mark('clientValuesHostRecordResultAccessGrant', progress, value);
    },
    resultReadRetentionPolicyCid(manifest, resultName) {
      return deliveryResult('clientValuesHostResultReadRetentionPolicyCid',
        deliveryToken(manifest), resultName);
    },
    resultReadDefinitionCid(manifest, resultName) {
      return deliveryResult('clientValuesHostResultReadDefinitionCid',
        deliveryToken(manifest), resultName);
    },
    resultReadAvailability(manifest, resultName, retention, observedAt) {
      return resultReadAvailability(deliveryContract(manifest), resultName,
        deliveryContract(retention), observedAt);
    },
    resultReadExtendedAvailability(manifest, resultName, retention,
      extension, observedAt) {
      return deliveryResult('clientValuesHostResultReadExtendedAvailability',
        deliveryToken(manifest), resultName, deliveryToken(retention),
        deliveryToken(extension), observedAt);
    },
    resultRetentionClockContractCid(retention) {
      return deliveryResult('clientValuesHostResultRetentionClockContractCid',
        deliveryToken(retention));
    },
    issueResultReadGrant(index, manifest, grant, limits) {
      const bounds = limitsOf(limits);
      const result = issuedDelivery('clientValuesHostIssueResultReadGrant',
        deliveryToken(index), deliveryToken(manifest),
        grant.resultNames, grant.formats, grant.principalId, grant.purpose,
        grant.dataCeilingCid, grant.maxBytes, grant.maxUses,
        grant.expiresAt, grant.authorizationContextCid,
        grant.egressAdmissionCid, ...bounds);
      issuedGrantBounds.set(result, Object.freeze(bounds));
      return result;
    },
    resultReadGrantValidAt(grant, observedAt) {
      return owner.clientValuesHostResultReadGrantValidAt(
        deliveryToken(grant), observedAt);
    },
    resultReadGrantAllowsBytes(grant, count) {
      return owner.clientValuesHostResultReadGrantAllowsBytes(
        deliveryToken(grant), count);
    },
    issueDeliveryAttempt(index, manifest, grant, attempt, limits) {
      const request = Object.freeze({resultName: attempt.resultName,
        format: attempt.format, attemptId: attempt.attemptId,
        requestedAt: attempt.requestedAt});
      const bounds = Object.freeze(limitsOf(limits));
      const result = issuedDelivery('clientValuesHostIssueDeliveryAttempt',
        deliveryToken(index), deliveryToken(manifest), deliveryToken(grant),
        request.resultName, request.format, request.attemptId,
        request.requestedAt, ...bounds);
      const original = Object.freeze({kind: 'issued-delivery-attempt'});
      const facts = Object.freeze({index, manifest, grant, attempt: result,
        request, limits: Object.freeze({maxWireBytes: bounds[0],
          maxNodes: bounds[1], maxDepth: bounds[2]})});
      issuedAttempts.set(result, {index: deliveryContract(index),
        manifest: deliveryContract(manifest), grant: deliveryContract(grant),
        bounds, original});
      originalAttempts.set(original, facts);
      return result;
    },
    captureIssuedDeliveryAttempt(attempt, index, manifest, grant, limits) {
      // Nominal lookups precede any view-field access. A valid raw admission
      // remains compatible, but cannot claim this issuer's captured inputs.
      deliveryContract(attempt);
      const actualIndex = deliveryContract(index);
      const actualManifest = deliveryContract(manifest);
      const actualGrant = deliveryContract(grant);
      const captured = issuedAttempts.get(attempt);
      if (captured === undefined) return undefined;
      if (captured.index !== actualIndex || captured.manifest !== actualManifest ||
          captured.grant !== actualGrant) {
        throw new TypeError('RunHostDeliveryOriginalMismatch');
      }
      const bounds = limitsOf(limits);
      const grantBounds = issuedGrantBounds.get(grant);
      if (grantBounds === undefined || !sameBounds(bounds, grantBounds) ||
          !sameBounds(bounds, captured.bounds)) return undefined;
      return captured.original;
    },
    readIssuedDeliveryAttempt(original) {
      const facts = originalAttempts.get(original);
      if (facts === undefined) throw new TypeError('ForeignRunHostDeliveryOriginal');
      return facts;
    },
    deliveryResultDefinitionCid(manifest, attempt) {
      return deliveryResult('clientValuesHostDeliveryResultDefinitionCid',
        deliveryToken(manifest), deliveryToken(attempt));
    },
    issueResultDeliveryReceipt(index, manifest, grant, attempt,
      delivered, limits) {
      return issuedDelivery('clientValuesHostIssueResultDeliveryReceipt',
        deliveryToken(index), deliveryToken(manifest), deliveryToken(grant),
        deliveryToken(attempt), delivered.byteCount, delivered.sha256,
        ...limitsOf(limits));
    },
    issueDeliveryRecord(attempt, previous, update, limits) {
      return issuedDelivery('clientValuesHostIssueDeliveryRecord',
        deliveryToken(attempt), previous === undefined ? undefined :
          deliveryToken(previous), update.state,
        update.confirmedByteCount, update.exposure,
        update.possibleUnconfirmedMaxBytes, update.deliveredSha256,
        update.receipt === undefined ? undefined :
          deliveryToken(update.receipt), update.failureCid,
        update.observedAt, update.cleanupOwnerCids, ...limitsOf(limits));
    },
    existingDeliveryAttemptAction(record) {
      return publicationAction('existingDelivery',
        owner.clientValuesHostExistingDeliveryAttemptAction(
          record === undefined ? undefined : deliveryToken(record)));
    },
    deliveryFailureTerminalAction(observed) {
      return publicationAction('failureTerminal',
        owner.clientValuesHostDeliveryFailureTerminalAction(observed));
    },
    deliveryRecordRetryAction(next, count) {
      return publicationAction('recordRetry',
        owner.clientValuesHostDeliveryRecordRetryAction(next, count));
    },
    deliveryTransition(previous, next) {
      return owner.clientValuesHostDeliveryRecordTransition(
        previous === undefined ? undefined : deliveryToken(previous),
        deliveryToken(next));
    },
    deliverySuccessValid(attempt, receipt, record) {
      return owner.clientValuesHostDeliverySuccessValid(
        deliveryToken(attempt), deliveryToken(receipt),
        deliveryToken(record));
    },
    trustedClockNotBefore(previous, observedAt) {
      return owner.clientValuesHostTrustedClockNotBefore(previous, observedAt);
    },
    prepareDeliveryGrantUsageClaim(grant, existingWire, attempt, limits) {
      const claim = deliveryResult(
        'clientValuesHostPrepareDeliveryGrantUsageClaim',
        deliveryToken(grant), existingWire, deliveryToken(attempt),
        ...limitsOf(limits));
      return Object.freeze({
        wire: owner.clientValuesHostDeliveryGrantUsageClaimWire(claim),
        newlyClaimed:
          owner.clientValuesHostDeliveryGrantUsageClaimIsNew(claim),
      });
    },
    prepareDurableResultRowFrames(bounds) {
      const frames = deliveryResult(
        'clientValuesHostPrepareDurableResultRowFrames',
        bounds.maxBytes, bounds.maxRows, bounds.maxRowBytes,
        bounds.maxDepth, bounds.maxFrameBytes);
      return handle(durableRowFrames, frames, 'durable-row-frames');
    },
    feedDurableResultRowFrames(frames, chunk) {
      return deliveryResult('clientValuesHostFeedDurableResultRowFrames',
        requireHandle(durableRowFrames, frames), chunk);
    },
    finishDurableResultRowFrames(frames) {
      const values = deliveryResult('clientValuesHostFinishDurableResultRowFrames',
        requireHandle(durableRowFrames, frames));
      return Object.freeze({bytes: values[0], rows: values[1]});
    },
    cancelDurableResultRowFrames(frames) {
      return deliveryCall('clientValuesHostCancelDurableResultRowFrames',
        requireHandle(durableRowFrames, frames));
    },
    prepareResultDeliverySerializer(format, schemaWire, fields, limits) {
      const serializer = deliveryResult(
        'clientValuesHostPrepareResultDeliverySerializer',
        format, schemaWire, fields, ...limitsOf(limits));
      return handle(deliverySerializers, serializer, 'result-serializer');
    },
    beginResultDelivery(serializer) {
      return deliveryResult('clientValuesHostBeginResultDelivery',
        requireHandle(deliverySerializers, serializer));
    },
    nextResultDeliveryRow(serializer, rowWire) {
      return deliveryResult('clientValuesHostNextResultDeliveryRow',
        requireHandle(deliverySerializers, serializer), rowWire);
    },
    finishResultDelivery(serializer) {
      return deliveryResult('clientValuesHostFinishResultDelivery',
        requireHandle(deliverySerializers, serializer));
    },
  });
}

function admittedTaskProgress(prepared, compilation, admission, definition,
  authority, durableWires) {
  const compiled = requireHandle(taskCompilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  if (typeof authority !== 'string' || !Array.isArray(durableWires) ||
      durableWires.some(wire => typeof wire !== 'string')) {
    throw new TypeError('InvalidRunHostTaskProgress');
  }
  checkRunBinding(prepared, admission, definition);
  return checked(owner.clientValuesHostInspectTaskProgress(
    requireHandle(preparations, prepared), compiled.value, admitted.value,
    requireHandle(definitions, definition), authority, durableWires),
  'RunHostTaskProgressRejected');
}

function taskProgressSnapshot(value) {
  const scopes = owner.clientValuesHostTaskProgressScopes(value);
  const next = owner.clientValuesHostTaskProgressNext(value);
  return Object.freeze({
    nextTask: next < 0 ? undefined : next,
    executionComplete: owner.clientValuesHostTaskProgressExecutionComplete(value),
    cleanupComplete: owner.clientValuesHostTaskProgressCleanupComplete(value),
    resultTasks: Object.freeze(owner.clientValuesHostTaskProgressResultTasks(value)),
    tasks: Object.freeze(owner.clientValuesHostTaskProgressFields(value).map((row, index) =>
      Object.freeze({ordinal: Number(row[0]), taskKey: row[1], execution: row[2],
        cleanup: row[3], revision: Number(row[4]), dispatchCid: row[5] || undefined,
        executionScope: Object.freeze(scopes[index])}))),
  });
}

/** Inspect checked task readiness. A snapshot grants no start or input custody. */
export function inspectTaskProgress(prepared, compilation, admission, definition,
  authority, durableWires) {
  return taskProgressSnapshot(admittedTaskProgress(prepared, compilation,
    admission, definition, authority, durableWires));
}

function validateTaskPhysicalStartClaim(claim) {
  const keys = ['taskKey', 'dispatchCid', 'definitionCid', 'reserved',
    'unstarted', 'authorized', 'cancelled', 'failed'];
  if (claim === null || typeof claim !== 'object' || Array.isArray(claim) ||
      Object.keys(claim).sort().join('\0') !== keys.sort().join('\0') ||
      [claim.taskKey, claim.dispatchCid, claim.definitionCid].some(value => typeof value !== 'string') ||
      [claim.reserved, claim.unstarted, claim.authorized, claim.cancelled, claim.failed]
        .some(value => typeof value !== 'boolean')) {
    throw new TypeError('InvalidRunHostTaskStart');
  }
}

/** Prepare a checked task claim. The Host must commit it before any send. */
export function prepareTaskPhysicalStart(prepared, compilation, admission, definition,
  authority, durableWires, requested, retained, claim) {
  validateTaskPhysicalStartClaim(claim);
  const progress = admittedTaskProgress(prepared, compilation, admission, definition,
    authority, durableWires);
  return checked(owner.clientValuesHostPrepareRemoteTaskPhysicalStart(
    progress, claim.taskKey, claim.dispatchCid, requireHandle(requests, requested),
    requireHandle(requests, retained), claim.definitionCid, claim.reserved,
    claim.unstarted, claim.authorized, claim.cancelled, claim.failed),
  'RunHostTaskStartRejected');
}

function admittedEffectTaskProgress(allowed, definition, authority, durableWires) {
  const {value} = requireHandle(effectAllowedRuns, allowed);
  if (typeof authority !== 'string' || !Array.isArray(durableWires) ||
      durableWires.some(wire => typeof wire !== 'string')) {
    throw new TypeError('InvalidRunHostTaskProgress');
  }
  return checked(owner.clientValuesHostInspectEffectTaskProgress(value,
    requireHandle(definitions, definition), authority, durableWires),
  'RunHostEffectTaskProgressRejected');
}

/** Computation/output facts only: this is not Effect or Run completion. */
export function inspectEffectTaskProgress(allowed, definition, authority, durableWires) {
  return effectTaskProgressSnapshot(admittedEffectTaskProgress(allowed, definition, authority, durableWires));
}

function effectTaskProgressSnapshot(value) {
  const scopes = owner.clientValuesHostEffectTaskProgressScopes(value);
  const next = owner.clientValuesHostEffectTaskProgressNext(value);
  return Object.freeze({
    nextTask: next < 0 ? undefined : next,
    computationComplete: owner.clientValuesHostEffectTaskProgressComputationComplete(value),
    taskCleanupComplete: owner.clientValuesHostEffectTaskProgressTaskCleanupComplete(value),
    resultTasks: Object.freeze(owner.clientValuesHostEffectTaskProgressResultTasks(value)),
    tasks: Object.freeze(owner.clientValuesHostEffectTaskProgressFields(value).map((row, index) =>
      Object.freeze({ordinal: Number(row[0]), taskKey: row[1], execution: row[2],
        cleanup: row[3], revision: Number(row[4]), dispatchCid: row[5] || undefined,
        executionScope: Object.freeze(scopes[index])}))),
  });
}

// Read each native Array element once. Caller-owned iteration, some and slice
// methods are not the supplier of the captured durable/claim facts.
function effectProjectionArray(value, maximum) {
  if (!Array.isArray(value)) throw new TypeError('InvalidRunHostEffectRunProjection');
  const length = value.length;
  if (!Number.isSafeInteger(length) || length < 0 || length > maximum) {
    throw new TypeError('InvalidRunHostEffectRunProjection');
  }
  const snapshot = [];
  for (let index = 0; index < length; index++) snapshot.push(value[index]);
  return snapshot;
}

/** Unpublished same-Run computation observation. Task cleanup and cancellation
 * are not a whole Effect/producer/Transfer stop, publication or release ACK. */
export function projectEffectSiteRun(allowed, definition, authority, durableWires,
  observedAt, cancellationRequested, savedClaims) {
  // The original checked graph bounds both complete claims and the at-most
  // one durable Coordinator record for each task, before reading elements.
  const {prepared, compilation} = requireHandle(effectAllowedRuns, allowed);
  const count = effectExecutionShape(prepared, compilation).taskCount;
  const wires = effectProjectionArray(durableWires, count);
  const claims = effectProjectionArray(savedClaims, count);
  if (typeof observedAt !== 'string' || typeof cancellationRequested !== 'boolean') {
    throw new TypeError('InvalidRunHostEffectRunProjection');
  }
  const keys = [], dispatches = [], reserved = [], physicallyClaimed = [];
  for (let index = 0; index < claims.length; index++) {
    const claim = claims[index];
    if (!claim || typeof claim !== 'object') throw new TypeError('InvalidRunHostEffectRunProjection');
    const key = claim.taskKey, dispatch = claim.dispatchCid;
    const reservation = claim.dispatchReserved, physical = claim.physicalStartClaimed;
    if (typeof key !== 'string' || (dispatch !== null && (typeof dispatch !== 'string' || dispatch.length === 0)) ||
        typeof reservation !== 'boolean' || typeof physical !== 'boolean') {
      throw new TypeError('InvalidRunHostEffectRunProjection');
    }
    keys.push(key); dispatches.push(dispatch === null ? '' : dispatch);
    reserved.push(reservation); physicallyClaimed.push(physical);
  }
  const value = admittedEffectTaskProgress(allowed, definition, authority, wires);
  const projected = checked(owner.clientValuesHostProjectEffectTaskRun(value,
    observedAt, cancellationRequested, keys, dispatches, reserved, physicallyClaimed),
  'RunHostEffectTaskRunProjectionRejected');
  const fields = owner.clientValuesHostEffectTaskRunFields(projected);
  const work = owner.clientValuesHostEffectTaskRunWork(projected);
  if (fields[3] !== '0' || fields[4] !== '0') throw new Error('InvalidRunHostEffectRunProjection');
  const progress = effectTaskProgressSnapshot(value), next = Number(fields[2]);
  return Object.freeze({...progress, stateWire: fields[0], execution: fields[1],
    nextTask: next < 0 ? undefined : next, publicationReady: false,
    tasks: Object.freeze(progress.tasks.map((task, index) =>
      Object.freeze({...task, nextWork: work[index]}))),
  });
}

/** Prepare the existing saved task claim; no Effect approval or physical apply. */
export function prepareEffectTaskPhysicalStart(allowed, definition, authority, durableWires,
  requested, retained, claim) {
  validateTaskPhysicalStartClaim(claim);
  const value = admittedEffectTaskProgress(allowed, definition, authority, durableWires);
  return checked(owner.clientValuesHostPrepareEffectTaskPhysicalStart(value,
    claim.taskKey, claim.dispatchCid, requireHandle(requests, requested),
    requireHandle(requests, retained), claim.definitionCid, claim.reserved,
    claim.unstarted, claim.authorized, claim.cancelled, claim.failed),
  'RunHostEffectTaskStartRejected');
}

/** Project the unpublished whole Run without committing, starting or releasing it. */
export function projectTaskSiteRun(prepared, compilation, admission, definition,
  authority, durableWires, observedAt, cancellationRequested = false,
  claimedTaskKeys = []) {
  if (typeof observedAt !== 'string' || typeof cancellationRequested !== 'boolean' ||
      !Array.isArray(claimedTaskKeys) ||
      claimedTaskKeys.some(key => typeof key !== 'string')) {
    throw new TypeError('InvalidRunHostTaskRunProjection');
  }
  const value = admittedTaskProgress(prepared, compilation, admission,
    definition, authority, durableWires);
  const projected = checked(owner.clientValuesHostProjectRemoteTaskRun(
    value, observedAt, cancellationRequested, claimedTaskKeys),
  'RunHostTaskRunProjectionRejected');
  const fields = owner.clientValuesHostRemoteTaskRunFields(projected);
  const work = owner.clientValuesHostRemoteTaskRunWork(projected);
  const progress = taskProgressSnapshot(value);
  const next = Number(fields[2]);
  return Object.freeze({...progress, stateWire: fields[0], execution: fields[1],
    nextTask: next < 0 ? undefined : next, publicationReady: fields[3] === '1',
    cleanupComplete: fields[4] === '1',
    tasks: Object.freeze(progress.tasks.map((task, index) =>
      Object.freeze({...task, nextWork: work[index]}))),
  });
}

/** Project an admitted durable Site record bound to this checked Run. */
export function projectSiteRun(prepared, compilation, admission, definition,
  authority, durableWire, observedAt, cancellationRequested = false,
  physicalStartClaimed = false) {
  const task = taskCompilations.has(compilation);
  const compiled = requireHandle(task ? taskCompilations : compilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  if ([authority, durableWire, observedAt].some(value =>
      typeof value !== 'string') || typeof cancellationRequested !== 'boolean' ||
      typeof physicalStartClaimed !== 'boolean') {
    throw new TypeError('InvalidSiteObservation');
  }
  checkRunBinding(prepared, admission, definition);
  const fields = checked(task ? owner.clientValuesHostProjectTaskSiteRun(
    requireHandle(preparations, prepared), compiled.value, admitted.value,
    requireHandle(definitions, definition), authority, durableWire, observedAt,
    cancellationRequested, physicalStartClaimed)
    : owner.clientValuesHostProjectSiteRun(
      requireHandle(definitions, definition), compiled.value,
      authority, durableWire, observedAt, cancellationRequested,
      physicalStartClaimed),
  'RunHostSiteProjectionRejected');
  if (fields === undefined) {
    throw Object.assign(new Error('RunHostSiteProjectionRejected'),
      {code: 'RunHostSiteProjectionRejected'});
  }
  return Object.freeze({stateWire: fields[0], execution: fields[1],
    cleanup: fields[2], revision: Number(fields[3]), nextWork: fields[4]});
}

export function prepareRunPhysicalStart(requested, retained, definition,
  definitionCid, reserved, unstarted, authorized, cancelled, failed = false) {
  if (typeof definitionCid !== 'string' ||
      [reserved, unstarted, authorized, cancelled, failed].some(value =>
        typeof value !== 'boolean')) throw new TypeError('InvalidRunHostStart');
  return checked(owner.clientValuesHostPreparePhysicalStart(
    requireHandle(requests, requested), requireHandle(requests, retained),
    requireHandle(definitions, definition), definitionCid, reserved,
    unstarted, authorized, cancelled, failed), 'RunHostStartRejected');
}

export function prepareRunPreStartFailure(requested, retained, definition,
  definitionCid, reserved, unstarted, admissionDenied, cancelled) {
  if (typeof definitionCid !== 'string' ||
      [reserved, unstarted, admissionDenied, cancelled].some(value =>
        typeof value !== 'boolean')) throw new TypeError('InvalidRunHostStart');
  return checked(owner.clientValuesHostPreparePreStartFailure(
    requireHandle(requests, requested), requireHandle(requests, retained),
    requireHandle(definitions, definition), definitionCid, reserved,
    unstarted, admissionDenied, cancelled), 'RunHostStartRejected');
}

export function prepareRunCancellation(definition, definitionCid,
  authorized, terminal, requested) {
  if (typeof definitionCid !== 'string' ||
      [authorized, terminal, requested].some(value =>
        typeof value !== 'boolean')) throw new TypeError('InvalidRunCancellation');
  return checked(owner.clientValuesHostPrepareCancellation(
    requireHandle(definitions, definition), definitionCid, authorized,
    terminal, requested), 'RunHostCancellationRejected');
}

/** Identity only; this does not request physical stop or return capacity. */
export function prepareRunCancellationIdentity(definition, scope) {
  const {namespaceId, authorityScopeCid, cancelId, expectedRevision} = scope ?? {};
  if ([namespaceId, authorityScopeCid, cancelId].some(value => typeof value !== 'string') ||
      !Number.isSafeInteger(expectedRevision) || expectedRevision < 0 ||
      expectedRevision > 2147483647) {
    throw new TypeError('InvalidRunCancellationIdentity');
  }
  return handle(cancellationIdentities, checked(
    owner.clientValuesHostPrepareCancellationIdentity(namespaceId,
      authorityScopeCid, cancelId, requireHandle(definitions, definition),
      expectedRevision), 'RunHostCancellationIdentityRejected'),
  'cancellation-identity');
}

/** Stored identity checksum; never storage provenance or execution authority. */
export function runCancellationIntentCid(identity) {
  return owner.clientValuesHostCancellationIntentCid(
    requireHandle(cancellationIdentities, identity));
}

/** Replay requires the saved immutable outcome, rather than today's Run flags. */
export function prepareRunCancellationOperation(definition, requested, facts) {
  const {retained, currentRevision, currentAuthorization,
    terminalObserved, cancellationRequested} = facts ?? {};
  if (!Number.isSafeInteger(currentRevision) || currentRevision < 0 ||
      currentRevision > 2147483647 ||
      [currentAuthorization, terminalObserved, cancellationRequested].some(value =>
        typeof value !== 'boolean')) {
    throw new TypeError('InvalidRunCancellationOperation');
  }
  const result = owner.clientValuesHostPrepareCancellationOperation(
    requireHandle(cancellationIdentities, requested), retained === undefined ?
      undefined : requireHandle(cancellationIdentities, retained),
    requireHandle(definitions, definition), currentRevision,
    currentAuthorization, terminalObserved, cancellationRequested);
  if (runtimeIsError(result) && ['ClientCancellationIntentConflict',
    'ClientCancellationOperationMismatch', 'ClientCancellationRevisionConflict',
    'ClientCancellationDenied', 'ClientCancellationRunMismatch'].includes(runtimeField(result, 0))) {
    throw Object.assign(new Error(runtimeField(result, 0)), {code: runtimeField(result, 0)});
  }
  const action = checked(result, 'RunHostCancellationOperationRejected');
  if (!['accepted', 'already_requested', 'already_terminal', 'replay_original'].includes(action)) {
    throw new Error('InvalidRunHostCancellationOperation');
  }
  return action;
}

export function issueRunControlObservation(revision, observation) {
  const {requested, unstarted, stopped} = observation ?? {};
  if (!Number.isSafeInteger(revision) || revision < 0 || revision > 2147483647 ||
      observation === null || typeof observation !== 'object' ||
      Array.isArray(observation) ||
      [requested, unstarted, stopped].some(value => typeof value !== 'boolean')) {
    throw new TypeError('InvalidRunControlObservation');
  }
  return JSON.parse(checked(owner.clientValuesHostRunControlObservation(
    revision, requested, unstarted, stopped), 'RunHostControlRejected'));
}


// The common identity Owner does not authenticate an epoch or retain its
// validation material. A physical Host must establish those facts separately.
export function prepareSubmissionEpoch(scope) {
  const {authorityScopeCid, epochNonce, notBefore, expiresAt} = scope ?? {};
  if (typeof authorityScopeCid !== 'string' || typeof epochNonce !== 'string' ||
      !Number.isSafeInteger(notBefore) || !Number.isSafeInteger(expiresAt)) {
    throw new TypeError('InvalidSubmissionEpoch');
  }
  const value = owner.clientValuesHostSubmissionEpoch(authorityScopeCid,
    epochNonce, notBefore, expiresAt);
  if (value === undefined) throw new Error('SubmissionEpochRejected');
  return handle(submissionEpochs, value, 'submission-epoch');
}

export function submissionEpochFacts(epoch) {
  const value = requireHandle(submissionEpochs, epoch);
  return Object.freeze({wire: owner.clientValuesHostSubmissionEpochWire(value),
    cid: owner.clientValuesHostSubmissionEpochCid(value)});
}

export function submissionEpochValidity(epoch, now) {
  if (!Number.isSafeInteger(now)) throw new TypeError('InvalidSubmissionClock');
  const value = owner.clientValuesHostSubmissionEpochValidity(
    requireHandle(submissionEpochs, epoch), now);
  if (value === undefined) throw new Error('SubmissionClockRejected');
  if (!['admissible', 'not_yet_valid', 'expired'].includes(value)) {
    throw new Error('InvalidSubmissionOwnerReply');
  }
  return value;
}

export function submissionRequestId(epoch, nonce) {
  if (typeof nonce !== 'string') throw new TypeError('InvalidSubmissionNonce');
  const value = owner.clientValuesHostSubmissionRequestId(
    requireHandle(submissionEpochs, epoch), nonce);
  if (value === undefined) throw new Error('SubmissionNonceRejected');
  return value;
}

export function prepareSubmittedIntent(wire, limits) {
  const {maxWireBytes, maxNodes, maxDepth} = limits ?? {};
  if (typeof wire !== 'string' ||
      !Number.isInteger(maxWireBytes) || maxWireBytes < 1 || maxWireBytes > 1048576 ||
      !Number.isInteger(maxNodes) || maxNodes < 1 || maxNodes > 65536 ||
      !Number.isInteger(maxDepth) || maxDepth < 1 || maxDepth > 64) {
    throw new TypeError('InvalidSubmittedIntent');
  }
  const value = owner.clientValuesHostSubmittedIntent(wire, maxWireBytes, maxNodes, maxDepth);
  if (value === undefined) throw new Error('SubmittedIntentRejected');
  return handle(submittedIntents, value, 'submitted-intent');
}

export function submittedIntentFacts(intent) {
  const value = requireHandle(submittedIntents, intent);
  return Object.freeze({wire: owner.clientValuesHostSubmittedIntentWire(value),
    cid: owner.clientValuesHostSubmittedIntentCid(value)});
}

export function submittedIntentTransition(before, after) {
  if (typeof before !== 'string' || typeof after !== 'string') {
    throw new TypeError('InvalidSubmittedIntentPhase');
  }
  return owner.clientValuesHostSubmittedIntentTransition(before, after);
}
