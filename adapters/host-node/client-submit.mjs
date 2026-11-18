// Both ingress transports use the same preparation and acceptance boundary.
// The handler owns durable admission; this wrapper never retries it.
import {validSubmitReply} from '../../packages/client-wire/index.mjs';

function invalid(code) {
  throw Object.assign(new Error(code), {code});
}

export async function performClientSubmit({connection, requestId, prepare,
  submit, executionProfile}) {
  // Legacy submit has no retained original intent before compilation. Only
  // the existing intent entrances may select a first-Plan Debug strategy.
  if (executionProfile === 'debug') invalid('ClientProgramUnsupported');
  const prepared = prepare === undefined ? undefined : await prepare();
  if (prepare !== undefined && prepared === undefined) {
    invalid('InvalidClientHostPreparation');
  }
  const reply = await submit(prepared);
  if (!validSubmitReply(reply, connection, requestId)) {
    invalid('InvalidClientHostAdmission');
  }
  return reply;
}
