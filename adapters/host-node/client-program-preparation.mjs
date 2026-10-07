// Translate the public submit body into the installed MoonBit checker JS bridge.
// The returned prepared handle is in-process only and cannot authorize a Run.
import {validSubmitPreparationError} from
  '../../packages/client-wire/index.mjs';
import {installNodePublicSourcePreparation} from
  './public-source-preparation.mjs';

const issueCodes = Object.freeze({
  invalid_format: 'ClientProgramInvalidInput',
  supplied_syntax: 'ClientParametersInvalid',
  supplied_admission: 'ClientParametersInvalid',
  supplied_too_large: 'ClientParametersTooLarge',
  program_syntax: 'ClientProgramInvalidInput',
  effect_not_supported: 'ClientProgramUnsupported',
  needs_inputs: 'ClientProgramNeedsInputs',
  check_invalid_input: 'ClientProgramRejected',
  check_invalid_configuration: 'ClientProgramPreparationFailure',
  check_unsupported: 'ClientProgramUnsupported',
  check_compile_limit: 'ClientProgramRejected',
  check_missing_input: 'ClientProgramNeedsInputs',
  check_unclassified: 'ClientProgramPreparationFailure',
  missing_checked_stage: 'ClientProgramRejected',
  missing_stage_identity: 'ClientProgramRejected',
  lowering_rejected: 'ClientProgramRejected',
  binding_rejected: 'ClientProgramRejected',
  graph_rejected: 'ClientProgramRejected',
  source_invalid_input: 'ClientProgramInvalidInput',
  source_rejected: 'ClientProgramRejected',
  source_unsupported: 'ClientProgramUnsupported',
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
        if (!['aql-text', 'sql'].includes(format)) {
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
  allowEffects = false, effectEvidence = [], sourcePublication, valuesMaxRows}) {
  if (!moon || typeof moon.clientProgramPrepareEffectFreeWithParameters !==
      'function' || typeof moon.clientProgramPreparationReady !== 'function' ||
      typeof moon.clientProgramPreparationIssue !== 'function' ||
      typeof moon.clientProgramPreparationIssueCode !== 'function' ||
      environment === undefined || typeof allowEffects !== 'boolean' ||
      !Array.isArray(effectEvidence) || effectEvidence.length > 1024 ||
      (allowEffects &&
        (typeof moon.clientProgramPrepareEffectComputationWithParameters !==
          'function'))) {
    throw new TypeError('InvalidClientProgramPreparationInstallation');
  }
  if (valuesMaxRows !== undefined && (!Number.isSafeInteger(valuesMaxRows) ||
      valuesMaxRows < 1 || valuesMaxRows > 10000 ||
      typeof moon.clientProgramWithValuesRowLimit !== 'function' || allowEffects)) {
    throw new TypeError('InvalidLocalValuesRowLimit');
  }
  const owned = new WeakSet();
  const effectOwned = new WeakSet();
  const installedEvidence = Object.freeze([...effectEvidence]);
  const prepareEffect = !allowEffects ? undefined :
    installNodeClientEffectProgramPreparation({moon,
      environment, evidence: installedEvidence});
  let sourcePreparation;
  const prepare = request => {
    const {document, format, supplied, declarations} =
      serializeProgram(request);
    let outcome;
    const sourceFormat = ['aql-text', 'sql'].includes(format);
    if (sourceFormat) {
      sourcePreparation ??= installNodePublicSourcePreparation({moon,
        environment, publication: sourcePublication, allowEffects,
        effectEvidence: installedEvidence});
      const source = sourcePreparation.prepare({document, format, declarations,
        supplied});
      if (source.kind === 'effectful') {
        const effect = effectPreparation(moon, source.outcome);
        effectOwned.add(effect);
        return effect;
      }
      outcome = source.outcome;
    } else {
      outcome = moon.clientProgramPrepareEffectFreeWithParameters(
        document, format, environment, supplied);
    }
    let prepared = moon.clientProgramPreparationReady(outcome);
    if (prepared !== undefined) {
      if (valuesMaxRows !== undefined) {
        prepared = moon.clientProgramWithValuesRowLimit(prepared, valuesMaxRows);
        if (prepared === undefined) fail('ClientProgramUnsupported');
      }
      owned.add(prepared);
      return prepared;
    }
    const issue = moon.clientProgramPreparationIssue(outcome);
    const category = moon.clientProgramPreparationIssueCode(outcome);
    if (!sourceFormat && category === 'effect_not_supported' && prepareEffect !== undefined) {
      const effect = prepareEffect(request);
      effectOwned.add(effect);
      return effect;
    }
    const code = issueCodes[category];
    if (issue === undefined || code === undefined) {
      fail('ClientProgramPreparationFailure');
    }
    fail(code, issue);
  };
  // The Local planner accepts only this installation's checked owner. This
  // keeps the exact runtime and environment binding without parsing it again.
  return Object.freeze(Object.assign(prepare, {
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
  evidence = []}) {
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
  const ownedEvidence = Object.freeze([...evidence]);
  return Object.freeze(request => {
    const {document, format, supplied} = serializeProgram(request);
    const outcome = moon.clientProgramPrepareEffectComputationWithParameters(
      document, format, environment, supplied, ownedEvidence);
    return effectPreparation(moon, outcome);
  });
}
