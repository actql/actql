// Both ingress transports use the same preparation and acceptance boundary.
// The handler owns durable admission; this wrapper never retries it.
import {validSubmitReply} from '../../packages/client-wire/index.mjs';
import type {WireClientBodyByOperation} from '../../packages/client-wire/index.js';

type ClientSubmitOptions<Prepared> = Readonly<{
  connection: WireClientBodyByOperation['submit']['connection'];
  requestId: WireClientBodyByOperation['submit']['requestId'];
  prepare?: (() => Prepared) | undefined;
  submit: (prepared: Awaited<Prepared> | undefined) => unknown;
  executionProfile?: WireClientBodyByOperation['submit']['executionProfile'];
}>;

function invalid(code: string): never {
  throw Object.assign(new Error(code), {code});
}

export async function performClientSubmit<Prepared>({connection, requestId, prepare,
  submit, executionProfile}: ClientSubmitOptions<Prepared>) {
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
