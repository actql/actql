import {validCancellationLookup} from '@actql/client-wire';
import {captureCancellation, validCancellationObservation} from '@actql/explorer-ui/cancellation';
import {createReadEpoch} from '@actql/explorer-ui/read-model';

const replyBytes = 262144;
const refused = code => {throw Object.assign(new Error(code), {code});};
async function jsonReply(response) {
  const reader = response.body?.getReader();
  if (!reader) refused('ExplorerInvalidReply');
  const chunks = []; let length = 0;
  try {
    while (true) {
      const {done, value} = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > replyBytes) refused('ExplorerReplyLimit');
      chunks.push(value);
    }
  } catch (error) {await reader.cancel().catch(() => {}); throw error;}
  finally {reader.releaseLock();}
  const bytes = new Uint8Array(length); let offset = 0;
  for (const chunk of chunks) {bytes.set(chunk, offset); offset += chunk.length;}
  try {return JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(bytes));}
  catch {refused('ExplorerInvalidReply');}
}

// A browser session holds only Gateway presentation credentials in memory.
// It contains no Host token and conveys no durable execution permission.
export function createExplorerBrowserSource({origin, fetch: send = globalThis.fetch,
  now = Date.now}) {
  const selected = new URL(origin);
  if (selected.protocol !== 'http:' || selected.hostname !== '127.0.0.1' ||
      !selected.port || selected.origin !== origin || typeof send !== 'function' ||
      typeof now !== 'function') {
    refused('ExplorerInvalidOrigin');
  }
  const epoch = createReadEpoch();
  let session;
  const invalidate = () => {epoch.invalidate(); session = undefined;};
  const request = async (path, body, original) => {
    const ticket = epoch.capture();
    ticket.assertCurrent();
    try {
      const response = await send(`${origin}${path}`, {method: 'POST',
        mode: 'same-origin', credentials: 'same-origin', redirect: 'error',
        cache: 'no-store', headers: {'Content-Type': 'application/json',
          ...(original ? {'X-Actql-CSRF': original.csrf} : {})},
        body: JSON.stringify(body)});
      const answer = await jsonReply(response);
      ticket.assertCurrent();
      if (!response.ok) {
        // An old response cannot invalidate a newer session. Error messages
        // and unvalidated response data are never promoted into UI facts.
        if (original === session && [401, 403].includes(response.status)) invalidate();
        refused('ExplorerReadUnavailable');
      }
      return answer;
    } catch (error) {ticket.assertCurrent(); throw error;}
  };
  const read = async (kind, body, group='read') => {
    const original = session;
    if (!original || now() >= original.expiresAt) {
      invalidate(); refused('ExplorerSessionExpired');
    }
    const answer = await request(`/api/${group}/${kind}`, body, original);
    if (original !== session || now() >= original.expiresAt) refused('ExplorerStaleScope');
    if (answer === null || typeof answer !== 'object' || Array.isArray(answer) ||
        Object.keys(answer).length !== 2 || !Object.hasOwn(answer, 'data') ||
        answer.scopeEpoch !== original.scopeEpoch) refused('ExplorerInvalidReply');
    return answer.data;
  };
  return Object.freeze({
    async connect(bootstrap) {
      invalidate();
      const answer = await request('/api/session', {bootstrap});
      const capabilities = answer?.capabilities;
      if (answer === null || typeof answer !== 'object' || Object.keys(answer).length !== 4 ||
          typeof answer?.csrf !== 'string' || !/^[a-zA-Z0-9_-]{43}$/u.test(answer.csrf) ||
          !Number.isSafeInteger(answer.scopeEpoch) || answer.scopeEpoch < 0 ||
          !Number.isSafeInteger(answer.expiresAt) || answer.expiresAt <= now() ||
          answer.expiresAt > now() + 300000 ||
          capabilities === null || typeof capabilities !== 'object' ||
          Object.keys(capabilities).length !== 7 || typeof capabilities.plan !== 'boolean' ||
          capabilities.run !== true || capabilities.resultMetadata !== true ||
          capabilities.resultPayload !== false || capabilities.control !== false ||
          capabilities.sample !== false || typeof capabilities.cancellation !== 'boolean') refused('ExplorerInvalidReply');
      session = Object.freeze({csrf: answer.csrf, scopeEpoch: answer.scopeEpoch,
        expiresAt: answer.expiresAt, cancellation: capabilities.cancellation});
      return answer.capabilities;
    },
    plan(input, options) {return read('plan', {input, ...(options === undefined ? {} : {options})});},
    async launchView() {
      const view = await read('launch', {});
      if (view === null) return null;
      if (view === null || typeof view !== 'object' || Array.isArray(view) ||
          Object.keys(view).length !== 2 || !Object.hasOwn(view, 'kind') ||
          !(view.kind === 'program' && Object.hasOwn(view, 'plan') ||
            view.kind === 'run' && Object.hasOwn(view, 'originalPlan'))) refused('ExplorerInvalidReply');
      return view;
    },
    inspect(ref) {return read('run', {ref});},
    observe(ref) {return read('observation', {ref});},
    runPlan(ref) {return read('run-plan', {ref});},
    describe(ref, name) {return read('result', {ref, name});},
    async cancel(original) {
      const saved=captureCancellation(original.cancelRef,original.attemptRef);
      if (!session?.cancellation) refused('ExplorerCapabilityUnavailable');
      // Keep the same original references even when a Gateway response is lost.
      let answer;
      try {answer=await read('cancel',saved,'control');}
      catch (error) {
        if (error?.code==='ExplorerStaleScope' || error?.code==='ExplorerSessionExpired') throw error;
        return {state:'unknown',original:saved};
      }
      return validCancellationObservation(answer,saved)
        ? answer : {state:'unknown',original:saved};
    },
    async lookupCancellation(cancelRef) {
      const saved=structuredClone(cancelRef);
      if (!session?.cancellation) refused('ExplorerCapabilityUnavailable');
      const answer=await read('lookup-cancellation',{cancelRef:saved},'control');
      if (!validCancellationLookup(answer,saved)) refused('ExplorerInvalidReply');
      return answer;
    },
    close: invalidate,
  });
}
