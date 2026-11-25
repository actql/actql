// Assemble operation families after admitting the original connection profile.
import {createCheckOperation} from './check-observation.mjs';
import {createCheckpointOperations} from './checkpoint-operations.mjs';
import {createClientLifecycle} from './client-lifecycle.mjs';
import {inProcessOptions} from './connection-options.mjs';
import {captureResponse, freezeInput} from './data.mjs';
import {ClientError, fail} from './errors.mjs';
import {createPlan} from './plan.mjs';
import {createResources} from './resources.mjs';
import {createExecutionFactory} from './run-observation.mjs';
import {createSubmissionOperations} from './submission-observation.mjs';
import {createTransport, loadLoopbackTransport} from './transport.mjs';
import {validClientProfile} from '@actql/client-wire';

import type {Client} from '../index.mjs';
import type {RuntimeHostPort} from './transport.mjs';
import type {SelectedConnection} from './connection-options.mjs';

export async function connectSelected(selected: SelectedConnection & {redactCredentialErrors?: boolean},
  port?: RuntimeHostPort): Promise<Client> {
  // Capture the installed provider's original operation once. Its DATA input
  // is not key custody or authority; the provider owns those current checks.
  const answerCheckpoint = port?.answerCheckpoint;
  if (answerCheckpoint !== undefined && typeof answerCheckpoint !== 'function') {
    fail('InvalidLocalHostPort');
  }
  let directLoopback;
  if (selected.directLoopbackHttp) {
    try { ({requestLoopbackClient: directLoopback} = await loadLoopbackTransport()); }
    catch { fail('LoopbackHttpUnavailable'); }
    if (typeof directLoopback !== 'function') fail('LoopbackHttpUnavailable');
  }
  const lifecycle = createClientLifecycle(port);
  const transport = createTransport(selected, port, lifecycle.isClosed, directLoopback);
  const {exchange, responseValue} = transport;
  const profileResponse = await exchange('connect');
  let profile;
  try { profile = await responseValue(profileResponse); }
  catch (cause) { throw new ClientError('InvalidHostProfile', {cause}); }
  try {
    // Capture detaches caller-owned fields once. Validate that owned snapshot;
    // a second clone/admission cannot add facts to this connection boundary.
    profile = captureResponse(profile);
    if (!validClientProfile(profile, selected.wire)) fail('InvalidHostProfile');
  } catch { fail('InvalidHostProfile'); }
  const confirmed = freezeInput(profile);

  const execution = createExecutionFactory(selected, confirmed, transport, lifecycle);
  const submissions = createSubmissionOperations(selected, confirmed, transport, execution, lifecycle);
  return Object.freeze({
    profile: confirmed,
    requestedDurability: selected.wire.durability ?? null,
    startSource: submissions.startSource,
    sql: submissions.sql,
    aql: submissions.aql,
    newSubmission: submissions.newSubmission,
    lookupSubmission: submissions.lookupSubmission,
    check: createCheckOperation(selected.wire, exchange, responseValue),
    ...createPlan(selected.wire, exchange, responseValue,
      submissions.withStaticPreparation, transport.sourcePreparation),
    start: submissions.start,
    attach: submissions.attach,
    lookupRequest: submissions.lookupRequest,
    recoverRequest: submissions.recoverRequest,
    cancelRequest: submissions.cancelRequest,
    ...createResources(selected.wire, exchange, responseValue),
    ...createCheckpointOperations(selected.wire, exchange, responseValue, {
      isClosed: lifecycle.isClosed,
      ...(answerCheckpoint === undefined ? {} : {
        answerOriginal: (summary, decision, signal) =>
          Reflect.apply(answerCheckpoint, port, [summary, decision, signal]),
      }),
    }),
    close: lifecycle.close,
    [Symbol.asyncDispose]: lifecycle.close,
  });
}

// Only an installed Local provider calls this pure Client facade. The port
// returns typed control values and Result frames; it is never a public URL.
export async function connectInProcess(options: unknown, port: RuntimeHostPort): Promise<Client> {
  if (port === null || typeof port !== 'object' ||
      typeof port.perform !== 'function' ||
      port.close !== undefined && typeof port.close !== 'function' ||
      port.seal !== undefined && typeof port.seal !== 'function') fail('InvalidLocalHostPort');
  return connectSelected(inProcessOptions(options), port);
}
