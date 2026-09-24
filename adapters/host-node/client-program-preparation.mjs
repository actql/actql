// Translate the public submit body into the installed MoonBit checker ABI.
// The returned prepared handle is in-process only and cannot authorize a Run.
import {validSubmitPreparationError} from
  '../../packages/client-wire/index.mjs';

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
});
if (Object.values(issueCodes).some(code =>
  code !== 'ClientProgramPreparationFailure' &&
  !validSubmitPreparationError({code}))) {
  throw new Error('StaleClientProgramErrorProjection');
}

function fail(code, cause) {
  throw Object.assign(new Error(code, {cause}), {code});
}

export function installNodeClientProgramPreparation({moon, environment}) {
  if (!moon || typeof moon.clientProgramPrepareEffectFreeWithParameters !==
      'function' || typeof moon.clientProgramPreparationReady !== 'function' ||
      typeof moon.clientProgramPreparationIssue !== 'function' ||
      typeof moon.clientProgramPreparationIssueCode !== 'function' ||
      environment === undefined) {
    throw new TypeError('InvalidClientProgramPreparationInstallation');
  }
  return Object.freeze(({kind, input, parameters}) => {
    let document, format, supplied;
    try {
      if (kind === 'aql') {
        document = input.text;
        format = input.format;
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
    const outcome = moon.clientProgramPrepareEffectFreeWithParameters(
      document, format, environment, supplied);
    const prepared = moon.clientProgramPreparationReady(outcome);
    if (prepared !== undefined) return prepared;
    const issue = moon.clientProgramPreparationIssue(outcome);
    const category = moon.clientProgramPreparationIssueCode(outcome);
    const code = issueCodes[category];
    if (issue === undefined || code === undefined) {
      fail('ClientProgramPreparationFailure');
    }
    fail(code, issue);
  });
}
