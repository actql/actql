import {connectSelected} from './internal/client.mjs';
import {connectionFailure, connectionObjectExample, connectionOptions, connectionStringExample,
  connectionStringOptions, inProcessOptions} from './internal/connection-options.mjs';
import {fail, isOwnedClientFailure} from './internal/errors.mjs';
import {explainDeliveryAttempt, explainReadFailure} from './internal/result-read.mjs';
import {explainCancellation, explainEffectUncertainty, explainOwnerObservations,
  explainRunObservationFailure} from './internal/run-observation.mjs';
import {explainRequestCancellation, explainRequestLookup, explainSubmission} from './internal/submission-observation.mjs';
import {formatOperationExplanation} from './operation-formats.mjs';

export {getCheckReasonCatalogInfo, getCheckReasonCatalogEntry} from './check-reason-catalog.generated.js';
export {getCheckPresentationInfo} from './check-presentation.mjs';
export {getOperationPresentationInfo} from './operation-presentation.mjs';
export {explainCheckOutcome, explainCheckReason} from './check-presentation.mjs';
export {ClientError} from './internal/errors.mjs';
export {getCheckFailureInput, explainCheckFailure, getCheckInput, getCheckFixes,
  getCheckParameterAdmission, getCheckContextRequirements, getCheckRequirementFrontier,
  equalCheckRequirementFrontiers, createCheckSupplementationSession, resolveCheckLocation,
  resolveCheckTextRange, resolveCheckTextRangeEncoding, createCheckDocumentSession,
  formatCheckOutcome} from './internal/check-observation.mjs';
export {getSubmissionCheckObservation, getSubmissionInput, getSubmissionOutcome,
  getSubmissionAttempt, explainSubmission, explainRequestLookup, explainRequestCancellation,
  RequestHeld} from './internal/submission-observation.mjs';
export {explainRunObservationFailure, explainOwnerObservations, explainEffectUncertainty,
  explainCancellation} from './internal/run-observation.mjs';
export {explainReadFailure, explainDeliveryAttempt} from './internal/result-read.mjs';
export async function connect(options, stringOptions) {
  const connectionString = typeof options === 'string';
  if (!connectionString && stringOptions !== undefined) {
    connectionFailure('InvalidConnectionOptions',
      'Object connections take one options argument. ' + connectionObjectExample);
  }
  let selected;
  try {
    selected = connectionOptions(connectionString
      ? connectionStringOptions(options, stringOptions) : options, connectionString);
  } catch (error) {
    if (!isOwnedClientFailure(error)) {
      connectionFailure('InvalidConnectionOptions',
        'Connection options could not be read safely. ' +
        (connectionString ? connectionStringExample : connectionObjectExample));
    }
    throw error;
  }
  return connectSelected(connectionString
    ? Object.freeze({...selected, redactCredentialErrors: true}) : selected);
}

// Only an installed Local provider calls this pure Client facade. The port
// returns typed control values and Result frames; it is never a public URL.
export async function connectInProcess(options, port) {
  if (port === null || typeof port !== 'object' ||
      typeof port.perform !== 'function' ||
      port.close !== undefined && typeof port.close !== 'function' ||
      port.seal !== undefined && typeof port.seal !== 'function') fail('InvalidLocalHostPort');
  return connectSelected(inProcessOptions(options), port);
}
/** Display retained operation facts without lookup, retry or execution authority. */
export function formatSubmission(result, options) {
  return formatOperationExplanation(explainSubmission(result), 'submission', options);
}
export function formatRequestLookup(result, options) {
  return formatOperationExplanation(explainRequestLookup(result), 'request', options);
}
export function formatRequestCancellation(result, options) {
  return formatOperationExplanation(explainRequestCancellation(result), 'requestCancellation', options);
}
export function formatCancellation(result, options) {
  return formatOperationExplanation(explainCancellation(result), 'cancellation', options);
}
export function formatReadFailure(result, options) {
  return formatOperationExplanation(explainReadFailure(result), 'read', options);
}
export function formatDeliveryAttempt(result, options) {
  return formatOperationExplanation(explainDeliveryAttempt(result), 'delivery', options);
}
export function formatEffectUncertainty(result, options) {
  return formatOperationExplanation(explainEffectUncertainty(result), 'effect', options);
}

export function formatRunObservationFailure(error, options) {
  return formatOperationExplanation(explainRunObservationFailure(error), 'observation', options);
}

export function formatOwnerObservations(result, options) {
  return formatOperationExplanation(explainOwnerObservations(result), 'ownerObservations', options);
}
