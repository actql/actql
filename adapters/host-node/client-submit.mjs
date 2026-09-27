// Both ingress transports use the same preparation and acceptance boundary.
// The handler owns durable admission; this wrapper never retries it.
import {validSubmitReply} from '../../packages/client-wire/index.mjs';

function invalid(code) {
  throw Object.assign(new Error(code), {code});
}

export async function performClientSubmit({connection, requestId, prepare,
  submit}) {
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
