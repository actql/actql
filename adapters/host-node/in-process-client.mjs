// Installed Local Client Host ingress. It shares public validation and Host
// services with HTTP ingress while keeping control and Result rows in process.
import {ClientError} from '../../packages/sdk/index.mjs';
import {validClientAdmission, validClientBody, validClientProfile,
  validDeliveryAttemptLookup, validRequestLookup, validRunState} from
  '../../packages/client-wire/index.mjs';
import {inspectAuthorizedRunState} from
  '../host-common/run-state-access.mjs';
import {inspectAuthorizedDeliveryAttempt} from './result-access.mjs';
import {authorizedLocalResultFrames} from './in-process-result.mjs';

const fail = code => { throw new ClientError(code); };
const publicCode = /^[A-Za-z][A-Za-z0-9_]{0,79}$/u;

export function createNodeInProcessClientHost({
  authenticate, authorizeConnection, negotiate, prepareSubmit, submit,
  attach, lookupRequest, stateService, resultService, observeRun, wait,
  cancel, reconcile, maxRowBytes,
}) {
  if (typeof authenticate !== 'function' ||
      typeof authorizeConnection !== 'function' ||
      typeof negotiate !== 'function' ||
      !Number.isSafeInteger(maxRowBytes) || maxRowBytes < 1) {
    throw new TypeError('InvalidInProcessClientHostInstallation');
  }
  return Object.freeze({async perform(operation, body, signal) {
    try {
      const validationBody = operation === 'read'
        ? {...body, format: 'jsonl'} : body;
      if (!validClientBody(operation, validationBody)) {
        fail('InvalidClientRequest');
      }
      let principalId;
      try { principalId = await authenticate(); }
      catch { fail('ClientAuthenticationDenied'); }
      if (typeof principalId !== 'string' || !principalId) {
        fail('ClientAuthenticationDenied');
      }
      const connection = body.connection;
      const ref = body.ref;
      let authorized;
      try {
        authorized = await authorizeConnection(Object.freeze({
          principalId, connection, ref, operation,
        }));
      } catch { authorized = false; }
      if (authorized !== true) fail('ClientConnectionDenied');
      const invoke = async (handler, preparedProgram) => {
        if (typeof handler !== 'function') fail('ClientOperationUnavailable');
        return handler(Object.freeze({principalId, connection,
          ...Object.fromEntries(Object.entries(body).filter(([key]) =>
            key !== 'connection')),
          ...(signal === undefined || operation === 'submit'
            ? {} : {signal}),
          ...(preparedProgram === undefined ? {} : {preparedProgram}),
        }));
      };
      if (operation === 'connect') {
        const profile = await invoke(negotiate);
        if (!validClientProfile(profile, connection)) {
          fail('InvalidClientHostProfile');
        }
        return profile;
      }
      if (operation === 'submit') {
        const prepared = prepareSubmit === undefined ? undefined :
          await invoke(prepareSubmit);
        if (prepareSubmit !== undefined && prepared === undefined) {
          fail('InvalidClientHostPreparation');
        }
        const admitted = await invoke(submit, prepared);
        if (!validClientAdmission(admitted, connection)) {
          fail('InvalidClientHostAdmission');
        }
        return admitted;
      }
      if (operation === 'attach') {
        const admitted = await invoke(attach);
        if (!validClientAdmission(admitted, connection) ||
            admitted.ref.tenantId !== ref.tenantId ||
            admitted.ref.authorityScopeCid !== ref.authorityScopeCid ||
            admitted.ref.runDefinitionCid !== ref.runDefinitionCid) {
          fail('InvalidClientHostAdmission');
        }
        return admitted;
      }
      if (operation === 'lookup-request') {
        const found = await invoke(lookupRequest);
        if (!validRequestLookup(found, body.requestId)) {
          fail('InvalidClientHostLookupResponse');
        }
        return found;
      }
      if (operation === 'status' || operation === 'wait') {
        const state = operation === 'status' && observeRun === undefined
          ? await inspectAuthorizedRunState(stateService, {
            indexKey: ref, principalId, purpose: 'inspect',
          }) : await invoke(operation === 'status' ? observeRun : wait);
        if (!validRunState(state)) fail('InvalidClientHostRunState');
        return state;
      }
      if (operation === 'cancel') return invoke(cancel);
      if (operation === 'reconcile') return invoke(reconcile);
      if (operation === 'delivery-attempt') {
        const found = await inspectAuthorizedDeliveryAttempt(resultService, {
          indexKey: ref, principalId, purpose: 'download',
          resultName: body.resultName, attemptId: body.attemptId,
        });
        if (!validDeliveryAttemptLookup(found, {
          attemptId: body.attemptId,
          runDefinitionCid: ref.runDefinitionCid,
          resultName: body.resultName,
        })) fail('InvalidClientHostAttemptLookup');
        return found;
      }
      if (operation === 'read') {
        return authorizedLocalResultFrames(resultService, {
          indexKey: ref, principalId, purpose: 'download',
          resultName: body.resultName, attemptId: body.attemptId,
        }, signal, {maxRowBytes});
      }
      fail('UnknownClientOperation');
    } catch (error) {
      if (error instanceof ClientError) throw error;
      if (typeof error?.code === 'string' &&
          publicCode.test(error.code)) {
        throw new ClientError(error.code, {cause: error});
      }
      throw new ClientError('ClientHostFailure', {cause: error});
    }
  }});
}
