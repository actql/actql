// Translate the public submit body into the installed MoonBit checker JS bridge.
// The returned prepared handle is in-process only and cannot authorize a Run.
import {validCheckOutcome, validSubmitPreparationError} from
  '../../packages/client-wire/index.mjs';
import {installNodePublicSourcePreparation} from
  './public-source-preparation.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeIsError, runtimeField} from '../host-common/compiler-binding.generated.mjs';

const issueCodes = Object.freeze({
  invalid_format: 'ClientProgramInvalidInput',
  supplied_syntax: 'ClientParametersInvalid',
  supplied_admission: 'ClientParametersInvalid',
  supplied_too_large: 'ClientParametersTooLarge',
  program_syntax: 'ClientProgramInvalidInput',
  effect_not_supported: 'ClientProgramUnsupported',
  values_profile_unsupported: 'ClientProgramUnsupported',
  needs_inputs: 'ClientProgramNeedsInputs',
  check_invalid_input: 'ClientProgramInvalidInput',
  check_invalid_configuration: 'ClientProgramPreparationFailure',
  check_unsupported: 'ClientProgramImplementationLimit',
  check_compile_limit: 'ClientProgramAnalysisLimit',
  check_missing_input: 'ClientProgramNeedsInputs',
  check_unclassified: 'ClientProgramPreparationFailure',
  missing_checked_stage: 'ClientProgramRejected',
  missing_stage_identity: 'ClientProgramRejected',
  lowering_rejected: 'ClientProgramRejected',
  binding_rejected: 'ClientProgramRejected',
  graph_rejected: 'ClientProgramRejected',
  source_invalid_input: 'ClientProgramInvalidInput',
  source_rejected: 'ClientProgramRejected',
  source_unresolved: 'ClientProgramRejected',
  source_unsupported: 'ClientProgramRejected',
  source_missing_input: 'ClientProgramNeedsInputs',
  source_declarations: 'ClientParametersInvalid',
  source_limit: 'ClientProgramRejected',
  source_encoding: 'ClientProgramPreparationFailure',
});
const effectIssueCodes = Object.freeze({
  invalid_format: 'ClientProgramInvalidInput',
  supplied_syntax: 'ClientParametersInvalid',
  supplied_admission: 'ClientParametersInvalid',
  invalid_input_owner: 'ClientParametersInvalid',
  program_syntax: 'ClientProgramInvalidInput',
  effect_candidate_rejected: 'ClientProgramRejected',
  effect_mapping_rejected: 'ClientProgramRejected',
  effect_static_rejected: 'ClientProgramRejected',
  stage_rejected: 'ClientProgramRejected',
  graph_rejected: 'ClientProgramRejected',
});
if ([...Object.values(issueCodes), ...Object.values(effectIssueCodes)]
  .some(code => code !== 'ClientProgramPreparationFailure' &&
    !validSubmitPreparationError({code}))) {
  throw new Error('StaleClientProgramErrorProjection');
}

// Only this projection owns these immutable facts. A copied/mutable error
// property or a lookalike Host exception cannot issue a capacity diagnostic.
const capacityRefusals = new WeakMap();
export function requestProgramCapacityRefusal(error) {
  return error !== null && (typeof error === 'object' || typeof error === 'function')
    ? capacityRefusals.get(error) : undefined;
}
function projectCapacityRefusal(moon, result) {
  const project = moon.clientProgramRequestProgramModuleCapacityRefusal;
  if (typeof project !== 'function') fail('InvalidHostRuntimeResult');
  const value = Reflect.apply(project, moon, [result]);
  if (value === undefined) fail('InvalidHostRuntimeResult');
  const phase = runtimeField(value, 0), dimension = runtimeField(value, 1);
  const amounts = [2, 3, 4, 5].map(index => runtimeField(value, index));
  if (phase !== 'source_free_plan' || !['retention', 'execution'].includes(dimension) ||
      amounts.some(amount => typeof amount !== 'bigint' || amount < 0n || amount > 9223372036854775807n) ||
      (dimension === 'retention' ? amounts[0] <= amounts[2]
        : amounts[0] > amounts[2] || amounts[1] <= amounts[3])) fail('InvalidHostRuntimeResult');
  return Object.freeze({phase, dimension,
    requiredRetentionBytes: amounts[0].toString(), requiredExecutionBytes: amounts[1].toString(),
    availableRetentionBytes: amounts[2].toString(), availableExecutionBytes: amounts[3].toString()});
}

// Read only the original typed Request result. The existing Common projection
// owns categories; JS never decodes an error constructor or checks input again.
// Foreign/current/general capacity/Host failures stay uncertain. Only the exact
// configured source-free Plan refusal below proves pre-admission nonexecution.
export function checkedRequestProgramPreparation(moon, result,
  projectIssue = moon.clientProgramRequestPreparationIssueCode) {
  if (runtimeIsError(result)) {
    const category = projectIssue.call(moon, result);
    if (category === 'source_free_capacity_exceeded') {
      const capacity = projectCapacityRefusal(moon, result);
      // Existing operation_failed refusal: no claim that the Program is
      // semantically invalid or unsupported, and no public wire extension.
      const error = Object.assign(new Error('ClientProgramRejected', {cause: runtimeField(result, 0)}),
        {code: 'ClientProgramRejected', capacity});
      capacityRefusals.set(error, capacity);
      throw error;
    }
    const code = issueCodes[category] ?? effectIssueCodes[category];
    if (code !== undefined) {
      throw Object.assign(new Error(code, {cause: runtimeField(result, 0)}), {code});
    }
  }
  return checked(result);
}

function fail(code, cause) {
  throw Object.assign(new Error(code, {cause}), {code});
}

function serializeProgram({kind, input, parameters}) {
  let document, format, supplied, declarations;
  try {
    if (kind === 'aql') {
      document = input.text;
      format = input.format;
      if (input.parameterDeclarations !== undefined) {
        if (!['aql', 'aql-text', 'sql'].includes(format)) {
          fail('ClientProgramInvalidInput');
        }
        declarations = JSON.stringify(input.parameterDeclarations);
      }
    } else if (kind === 'program') {
      document = JSON.stringify(input);
      format = 'json';
    } else {
      fail('ClientProgramInvalidInput');
    }
    supplied = parameters === null ? undefined :
      JSON.stringify(parameters);
  } catch (cause) {
    if (cause?.code === 'ClientProgramInvalidInput') throw cause;
    fail('ClientProgramInvalidInput', cause);
  }
  return {document, format, supplied, declarations};
}

export function installNodeClientProgramPreparation({moon, environment,
  allowEffects = false, effectEvidence = [], sourcePublication, valuesMaxRows, check,
  verifyRequestValuePolicy, restoreEffectOriginal, restoreInferOriginal,
  getPreparedSourceEnvironment, getFundedPreparation}) {
  const funded = getFundedPreparation !== undefined;
  if (!moon || (!funded && (typeof moon.clientProgramPrepareEffectFreeWithParameters !==
      'function' || typeof moon.clientProgramPreparationReady !== 'function' ||
      typeof moon.clientProgramPreparationIssue !== 'function' ||
      typeof moon.clientProgramPreparationIssueCode !== 'function')) ||
      environment === undefined || typeof allowEffects !== 'boolean' ||
      !Array.isArray(effectEvidence) || effectEvidence.length > 1024 ||
      (restoreEffectOriginal !== undefined && typeof restoreEffectOriginal !== 'function') ||
      (restoreInferOriginal !== undefined && typeof restoreInferOriginal !== 'function') ||
      (check !== undefined && typeof check !== 'function') ||
      (getPreparedSourceEnvironment !== undefined && typeof getPreparedSourceEnvironment !== 'function') ||
      (getFundedPreparation !== undefined && typeof getFundedPreparation !== 'function') ||
      (verifyRequestValuePolicy !== undefined &&
        (!funded || typeof verifyRequestValuePolicy !== 'function')) ||
      (!funded && allowEffects &&
        (typeof moon.clientProgramPrepareEffectComputationWithParameters !==
          'function'))) {
    throw new TypeError('InvalidClientProgramPreparationInstallation');
  }
  if (valuesMaxRows !== undefined && (!Number.isSafeInteger(valuesMaxRows) ||
      valuesMaxRows < 1 || valuesMaxRows > 10000 ||
      (funded ? typeof moon.clientProgramValuesMaxRows !== 'function'
        : typeof moon.clientProgramWithValuesRowLimit !== 'function') || allowEffects)) {
    throw new TypeError('InvalidLocalValuesRowLimit');
  }
  const owned = new WeakMap();
  const retiredOriginals = new WeakSet();
  const effectOwned = new WeakSet();
  const sourceCheckFailures = new WeakSet();
  const fundedFailures = new WeakSet();
  let installedEvidence = Object.freeze([...effectEvidence]);
  effectEvidence = undefined;
  let retired = false;
  let sourcePreparation;
  const publicSourcePreparation = selectedEnvironment => selectedEnvironment === environment
    ? (sourcePreparation ??= installNodePublicSourcePreparation({moon,
      environment, publication: sourcePublication, allowEffects,
      effectEvidence: installedEvidence, getPreparedSourceEnvironment}))
    : installNodePublicSourcePreparation({moon,
      environment: selectedEnvironment, publication: sourcePublication, allowEffects,
      effectEvidence: installedEvidence});
  const preparePublishedEffect = (request, selectedEnvironment) => {
    const {document, format, supplied} = serializeProgram(request);
    return effectPreparation(moon, publicSourcePreparation(selectedEnvironment)
      .prepareEffect({document, format, supplied}));
  };
  if (!funded && allowEffects && sourcePublication !== undefined) {
    // The Source and JSON Effect frontends borrow the same admitted
    // publication, not two independently reconstructed catalogs.
    publicSourcePreparation(environment);
  }
  let prepareEffect = funded || !allowEffects ? undefined : sourcePublication === undefined
    ? installNodeClientEffectProgramPreparation({moon,
      environment, evidence: installedEvidence})
    : request => preparePublishedEffect(request, environment);
  const prepareFunded = async (request, selectedEnvironment) => {
    try {
      const signal = request.signal;
      const original = await getFundedPreparation(request, selectedEnvironment,
        verifyRequestValuePolicy, signal);
      if (retired) fail('ClientProgramPreparationFailure');
      signal?.throwIfAborted();
      if (original === undefined || original === null ||
          !['effect_free', 'effectful'].includes(original.kind) ||
          original.prepared === null || typeof original.prepared !== 'object' ||
          original.originalInputs?.environment !== selectedEnvironment ||
          original.originalInputs.parameters !== undefined &&
            typeof original.originalInputs.parameters !== 'string') {
        fail('ClientProgramPreparationFailure');
      }
      const prepared = original.prepared;
      if (original.kind === 'effectful') {
        if (!allowEffects) fail('ClientProgramUnsupported');
        effectOwned.add(prepared);
      } else {
        if (valuesMaxRows !== undefined &&
            moon.clientProgramValuesMaxRows(prepared) !== valuesMaxRows) {
          fail('ClientProgramPreparationFailure');
        }
        // This is original DATA from the same fixed Request owner. It neither
        // certifies a Run nor supplies a second preparation/cleanup authority.
        owned.set(prepared, Object.freeze({...original.originalInputs}));
      }
      return prepared;
    } catch (error) {
      // A foreign constructor can throw any JS value. Keep that exact cause
      // in this attempt's failure carrier so even undefined/null cannot fall
      // through to a second public check or old preparation path.
      const failure = error !== null && (typeof error === 'object' || typeof error === 'function')
        ? error : Object.assign(new Error('ClientProgramPreparationFailure', {cause: error}),
          {code: 'ClientProgramPreparationFailure'});
      fundedFailures.add(failure);
      throw failure;
    }
  };
  const prepare = (request, selectedEnvironment = environment) => {
    if (retired) fail('ClientProgramPreparationFailure');
    // Fixed Local owner may already have parsed/checked this exact pending
    // original under its same preparation reservation. Ask BEFORE serializing
    // so the funded route never makes an unquoted second document/AST copy.
    // The installed row ceiling was selected by that same Request before its
    // compiler/Plan. Never clone a Prepared here or divert into the serializer.
    if (funded) {
      // Selection is mandatory. A missing/failed owner cannot silently choose
      // the old serializer or return a Promise as if it were a Prepared token.
      return prepareFunded(request, selectedEnvironment);
    }
    const {document, format, supplied, declarations} =
      serializeProgram(request);
    let outcome;
    const sourceFormat = ['aql', 'aql-text', 'sql'].includes(format);
    if (sourceFormat) {
      const currentSourcePreparation = publicSourcePreparation(selectedEnvironment);
      const source = currentSourcePreparation.prepare({document, format, declarations,
        supplied});
      if (source.kind === 'effectful') {
        const effect = effectPreparation(moon, source.outcome);
        effectOwned.add(effect);
        return effect;
      }
      outcome = source.outcome;
    } else {
      outcome = moon.clientProgramPrepareEffectFreeWithParameters(
        document, format, selectedEnvironment, supplied);
    }
    let prepared = moon.clientProgramPreparationReady(outcome);
    if (prepared !== undefined) {
      if (valuesMaxRows !== undefined) {
        prepared = moon.clientProgramWithValuesRowLimit(prepared, valuesMaxRows);
        if (prepared === undefined) fail('ClientProgramUnsupported');
      }
      // Retain the actual normalized Environment and the original serialized
      // Parameter Values used by this preparation, not current Host defaults.
      owned.set(prepared, Object.freeze({environment: selectedEnvironment, parameters: supplied}));
      return prepared;
    }
    const issue = moon.clientProgramPreparationIssue(outcome);
    const category = moon.clientProgramPreparationIssueCode(outcome);
    if (!sourceFormat && category === 'effect_not_supported' && prepareEffect !== undefined) {
      const effect = selectedEnvironment === environment ? prepareEffect(request)
        : sourcePublication === undefined
          ? installNodeClientEffectProgramPreparation({moon,
            environment: selectedEnvironment, evidence: installedEvidence})(request)
          : preparePublishedEffect(request, selectedEnvironment);
      effectOwned.add(effect);
      return effect;
    }
    // Raw Source compilation budgets may depend on protected publication.
    // Only the audience-filtered check below may expose that budget.
    const sourceCheck = sourceFormat && ['source_invalid_input', 'source_unresolved',
      'source_unsupported', 'check_invalid_input', 'check_unsupported', 'check_compile_limit'].includes(category);
    const code = sourceCheck && ['check_compile_limit', 'check_unsupported'].includes(category)
      ? 'ClientProgramRejected' : issueCodes[category];
    if (issue === undefined || code === undefined) {
      fail('ClientProgramPreparationFailure');
    }
    const error = Object.assign(new Error(code, {cause: issue}), {code});
    if (sourceCheck) {
      sourceCheckFailures.add(error);
    }
    throw error;
  };
  // The Local planner accepts only this installation's checked owner. This
  // keeps the exact runtime and environment binding without parsing it again.
  const disclosed = check === undefined ? prepare : async request => {
    try { return await prepare(request); }
    catch (error) {
      // The selected owner already performed its check. Keep its exact failure;
      // nominal audience-bound observation is a separate existing projection.
      if (fundedFailures.has(error)) throw error;
      if ((error?.code !== 'ClientProgramRejected' && !sourceCheckFailures.has(error)) || request.kind !== 'aql' ||
          !['aql', 'aql-text', 'sql'].includes(request.input.format)) throw error;
      // Preparation already refused. The same public check Owner may disclose
      // an independent input violation; it cannot admit or execute this input.
      // Its audience-visible publication hides absent and inaccessible Sources.
      let outcome;
      try { outcome = await check({...request, kind: 'text', scope: 'bound_input'}); }
      catch (cause) {
        if (request.signal?.aborted) throw cause;
        fail('ClientProgramRejected', error);
      }
      if (validCheckOutcome(outcome)) {
        const report = outcome.report ?? outcome.partial_report;
        if (report?.scope.kind === 'bound_input' && report.verdict === 'invalid') {
          fail('ClientProgramInvalidInput', error);
        }
        if (report?.scope.kind === 'bound_input' &&
            report.coverage.limits.some(limit => limit.code === 'analysis_budget_exhausted')) {
          fail('ClientProgramAnalysisLimit', error);
        }
        if (report?.scope.kind === 'bound_input' &&
            report.coverage.limits.some(limit => limit.code === 'implementation_limit')) {
          fail('ClientProgramImplementationLimit', error);
        }
      }
      fail('ClientProgramRejected', error);
    }
  };
  // Trusted policy verification belongs to the funded Request before compile.
  // No completed-input reprepare or externally substituted Environment remains.
  return Object.freeze(Object.assign(disclosed, {
    retireReferences() {
      if (retired) return;
      retired = true;
      sourcePreparation?.retireSourceEnvironment();
      prepareEffect?.retireSourceEnvironment?.();
      sourcePreparation = prepareEffect = undefined;
      environment = sourcePublication = installedEvidence = getPreparedSourceEnvironment = getFundedPreparation = undefined;
      // Installation callbacks may themselves retain the same Environment.
      check = verifyRequestValuePolicy = restoreEffectOriginal = restoreInferOriginal = undefined;
    },
    // Private installing Local cleanup owner only. This releases the exact
    // Pure preparation metadata, not the shared Environment or another Run.
    // Call only after all original borrowers have confirmed cleanup.
    retireOriginal(prepared) {
      if (retiredOriginals.has(prepared)) return;
      const original = owned.get(prepared);
      if (original === undefined || original.inferRun !== undefined) {
        throw new TypeError('Foreign Pure Client preparation');
      }
      owned.delete(prepared);
      retiredOriginals.add(prepared);
    },
    originalInputs(prepared) {
      const original = owned.get(prepared);
      if (original === undefined || original.inferRun !== undefined) {
        fail('ClientProgramPreparationFailure');
      }
      return original;
    },
    originalInferRun(prepared) {return owned.get(prepared)?.inferRun;},
    restoreInferOriginal(original, definition, request, evidence) {
      if (restoreInferOriginal === undefined) fail('ClientProgramUnsupported');
      const restored = restoreInferOriginal(original, definition, request, evidence);
      if (typeof restored?.then === 'function') {
        void Promise.resolve(restored).catch(() => {});
        fail('ClientProgramPreparationFailure');
      }
      if (restored?.prepared === undefined || restored?.compiled === undefined ||
          restored?.graph === undefined || restored?.runDefinition !== definition) {
        fail('ClientProgramPreparationFailure');
      }
      // This trusted callback uses the existing Common saved-material reader.
      // One entry retains its exact nominal pair; no copied public preparation
      // is admitted by adding an identity or a caller-provided ownership flag.
      owned.set(restored.prepared, Object.freeze({inferRun: restored}));
      return restored.prepared;
    },
    // Only the installed Host passes an original from its existing verified
    // Checkpoint custody. Public submit objects never enter this method.
    restoreOriginal(original) {
      if (!allowEffects || restoreEffectOriginal === undefined) fail('ClientProgramUnsupported');
      const restored = restoreEffectOriginal(original);
      if (restored?.prepared === undefined || restored?.compilation === undefined) {
        fail('ClientProgramPreparationFailure');
      }
      effectOwned.add(restored.prepared);
      return restored.prepared;
    },
    sourceCheckFailure(error) {return sourceCheckFailures.has(error);},
    // Only the same installation's prepared owner reaches this boundary. The
    // submitted intent is the opaque original retained by the request journal;
    // no emitted row, final-stage inspection or Account decision stands in for
    // its complete Common Effect inventory.
    assertSubmittedIntent(prepared, intent) {
      if (!owned.has(prepared) && !effectOwned.has(prepared)) {
        throw new TypeError('Foreign Client preparation');
      }
      if (effectOwned.has(prepared) &&
          !moon.clientSubmittedIntentEffectCompatible(intent, prepared)) {
        fail('ClientProgramRejected');
      }
    },
    assertOwned(prepared) {
      if (!owned.has(prepared) && !effectOwned.has(prepared)) {
        throw new TypeError('Foreign Client preparation');
      }
    },
    kindOf(prepared) {
      if (owned.has(prepared)) return 'effect_free';
      if (effectOwned.has(prepared)) return 'effectful';
      throw new TypeError('Foreign Client preparation');
    },
  }));
}

function effectPreparation(moon, outcome) {
  const prepared = moon.clientProgramEffectPreparationReady(outcome);
  if (prepared !== undefined) return prepared;
  const issue = moon.clientProgramEffectPreparationIssue(outcome);
  const category = moon.clientProgramEffectPreparationIssueCode(outcome);
  const code = effectIssueCodes[category];
  if (issue === undefined || code === undefined) {
    fail('ClientProgramPreparationFailure');
  }
  fail(code, issue);
}

// Effect preparation shares Client serialization and checked Program
// admission. The installed Effectful submit supplies the separate durable
// Run-start claim; this prepared handle is not a send permit.
export function installNodeClientEffectProgramPreparation({moon, environment,
  evidence = [], publication}) {
  if (!moon ||
      typeof moon.clientProgramPrepareEffectComputationWithParameters !==
        'function' ||
      typeof moon.clientProgramEffectPreparationReady !== 'function' ||
      typeof moon.clientProgramEffectPreparationIssue !== 'function' ||
      typeof moon.clientProgramEffectPreparationIssueCode !== 'function' ||
      environment === undefined || !Array.isArray(evidence) ||
      evidence.length > 1024) {
    throw new TypeError('InvalidClientEffectPreparationInstallation');
  }
  let ownedEvidence = Object.freeze([...evidence]);
  let published = publication === undefined ? undefined :
    installNodePublicSourcePreparation({moon, environment, publication,
      allowEffects: true, effectEvidence: ownedEvidence});
  publication = evidence = undefined;
  let retired = false;
  const prepare = request => {
    if (retired) fail('ClientProgramPreparationFailure');
    const {document, format, supplied} = serializeProgram(request);
    const outcome = published === undefined
      ? moon.clientProgramPrepareEffectComputationWithParameters(
        document, format, environment, supplied, ownedEvidence)
      : published.prepareEffect({document, format, supplied});
    return effectPreparation(moon, outcome);
  };
  return Object.freeze(Object.assign(prepare, {
    retireSourceEnvironment() {
      if (retired) return;
      retired = true;
      published?.retireSourceEnvironment();
      published = environment = ownedEvidence = undefined;
    },
  }));
}
