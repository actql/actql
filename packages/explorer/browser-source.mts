import type * as Public from './browser-source.js';
type BrowserSource = ReturnType<typeof Public.createExplorerBrowserSource>;
interface Session {csrf:string;scopeEpoch:number;expiresAt:number;cancellation:boolean;checkpointList:boolean;checkpointReview:boolean}
interface SessionReply {capabilities:Record<string,unknown>;csrf:unknown;scopeEpoch:unknown;expiresAt:unknown}

import {checkpointPageModel,captureReviewReference,validReviewObservation} from '@actql/explorer-ui/checkpoint-review';
import {validCancellationLookup, validRunRef, validWireRunExplanationViewShape} from '@actql/client-wire';
import {captureCancellation, validCancellationObservation} from '@actql/explorer-ui/cancellation';
import {createReadEpoch} from '@actql/explorer-ui/read-model';

const replyBytes = 262144;
const refused:(code:string)=>never = code => {throw Object.assign(new Error(code), {code});};
async function jsonReply(response:Response):Promise<unknown> {
  const reader = response.body?.getReader();
  if (!reader) refused('ExplorerInvalidReply');
  const chunks:Uint8Array[] = []; let length = 0;
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
  now = Date.now}:Parameters<typeof Public.createExplorerBrowserSource>[0]):BrowserSource {
  const selected = new URL(origin);
  if (selected.protocol !== 'http:' || selected.hostname !== '127.0.0.1' ||
      !selected.port || selected.origin !== origin || typeof send !== 'function' ||
      typeof now !== 'function') {
    refused('ExplorerInvalidOrigin');
  }
  const epoch = createReadEpoch();
  let session:Session|undefined;
  const invalidate = () => {epoch.invalidate(); session = undefined;};
  const request = async (path:string, body:unknown, original?:Session) => {
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
  const read = async <T=unknown,>(kind:string, body:unknown, group='read'):Promise<T> => {
    const original = session;
    if (!original || now() >= original.expiresAt) {
      invalidate(); refused('ExplorerSessionExpired');
    }
    const answer = await request(`/api/${group}/${kind}`, body, original) as {scopeEpoch:unknown;data:T};
    if (original !== session || now() >= original.expiresAt) refused('ExplorerStaleScope');
    if (answer === null || typeof answer !== 'object' || Array.isArray(answer) ||
        Object.keys(answer).length !== 2 || !Object.hasOwn(answer, 'data') ||
        answer.scopeEpoch !== original.scopeEpoch) refused('ExplorerInvalidReply');
    return answer.data;
  };
  return Object.freeze<BrowserSource>({
    async connect(bootstrap) {
      invalidate();
      const answer = await request('/api/session', {bootstrap}) as SessionReply;
      const capabilities = answer?.capabilities;
      if (answer === null || typeof answer !== 'object' || Object.keys(answer).length !== 4 ||
          typeof answer?.csrf !== 'string' || !/^[a-zA-Z0-9_-]{43}$/u.test(answer.csrf) ||
          !Number.isSafeInteger(answer.scopeEpoch) || (answer.scopeEpoch as number) < 0 ||
          !Number.isSafeInteger(answer.expiresAt) || (answer.expiresAt as number) <= now() ||
          (answer.expiresAt as number) > now() + 300000 ||
          capabilities === null || typeof capabilities !== 'object' ||
          Object.keys(capabilities).length !== 9 || typeof capabilities.plan !== 'boolean' ||
          capabilities.run !== true || capabilities.resultMetadata !== true ||
          capabilities.resultPayload !== false || capabilities.control !== false ||
          capabilities.sample !== false || typeof capabilities.cancellation !== 'boolean'||typeof capabilities.checkpointList!=='boolean'||typeof capabilities.checkpointReview!=='boolean') refused('ExplorerInvalidReply');
      session = Object.freeze({csrf: answer.csrf as string, scopeEpoch: answer.scopeEpoch as number,
        expiresAt: answer.expiresAt as number, cancellation: capabilities.cancellation as boolean,checkpointList:capabilities.checkpointList as boolean,checkpointReview:capabilities.checkpointReview as boolean});
      return answer.capabilities as Public.ExplorerCapabilities;
    },
    plan(input, options) {return read<Awaited<ReturnType<BrowserSource['plan']>>>('plan', {input, ...(options === undefined ? {} : {options})});},
    async launchView() {
      const view = await read<Awaited<ReturnType<BrowserSource['launchView']>>>('launch', {});
      if (view === null) return null;
      if (view === null || typeof view !== 'object' || Array.isArray(view) ||
          Object.keys(view).length !== 2 || !Object.hasOwn(view, 'kind') ||
          !(view.kind === 'program' && Object.hasOwn(view, 'plan') ||
            view.kind === 'run' && Object.hasOwn(view, 'originalPlan'))) refused('ExplorerInvalidReply');
      return view;
    },
    inspect(ref) {return read<Awaited<ReturnType<BrowserSource['inspect']>>>('run', {ref});},
    observe(ref) {return read<Awaited<ReturnType<BrowserSource['observe']>>>('observation', {ref});},
    runPlan(ref) {return read<Awaited<ReturnType<BrowserSource['runPlan']>>>('run-plan', {ref});},
    async explain(ref) {
      const original = Object.freeze({...ref});
      if (!validRunRef(original)) refused('ExplorerInvalidReply');
      const value = await read('run-explanation', {ref: original});
      if (!validWireRunExplanationViewShape(value) ||
          value.run_ref.namespaceId !== original.namespaceId ||
          value.run_ref.authorityScopeCid !== original.authorityScopeCid ||
          value.run_ref.runDefinitionCid !== original.runDefinitionCid) refused('ExplorerInvalidReply');
      return value;
    },
    async runPresentation(ref, options) {
      const original = Object.freeze({...ref});
      if (!validRunRef(original)) refused('ExplorerInvalidReply');
      let locale = 'en';
      if (options !== undefined) {
        if (options === null || typeof options !== 'object' || Array.isArray(options) ||
            ![Object.prototype, null].includes(Object.getPrototypeOf(options))) refused('ExplorerInvalidReply');
        const keys = Reflect.ownKeys(options);
        if (keys.length > 1 || keys.length === 1 && keys[0] !== 'locale') refused('ExplorerInvalidReply');
        const selected = Object.getOwnPropertyDescriptor(options, 'locale');
        if (selected && !Object.hasOwn(selected, 'value')) refused('ExplorerInvalidReply');
        if (selected?.value !== undefined) locale = selected.value;
        if (locale !== 'en' && locale !== 'ja') refused('ExplorerInvalidReply');
      }
      const value = await read<Awaited<ReturnType<BrowserSource['runPresentation']>>>('run-presentation', {ref: original, locale});
      if (!validRunRef(value?.runRef) ||
          value.runRef.namespaceId !== original.namespaceId ||
          value.runRef.authorityScopeCid !== original.authorityScopeCid ||
          value.runRef.runDefinitionCid !== original.runDefinitionCid) refused('ExplorerInvalidReply');
      return value;
    },
    describe(ref, name) {return read<Awaited<ReturnType<BrowserSource['describe']>>>('result', {ref, name});},
    async cancel(original) {
      const saved=captureCancellation(original.cancelRef,original.attemptRef);
      if (!session?.cancellation) refused('ExplorerCapabilityUnavailable');
      // Keep the same original references even when a Gateway response is lost.
      let answer;
      try {answer=await read('cancel',saved,'control');}
      catch (error) {
        if ((error as {code?:unknown}|null)?.code==='ExplorerStaleScope' || (error as {code?:unknown}|null)?.code==='ExplorerSessionExpired') throw error;
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
    async checkpoints(){if(!session?.checkpointList)refused('ExplorerCapabilityUnavailable');return checkpointPageModel(await read('checkpoints',{}));},
    async reviewCheckpoint(input){const checkpoint=captureReviewReference(input);if(!session?.checkpointReview)refused('ExplorerCapabilityUnavailable');
      const value=await read('checkpoint-review',{checkpoint});if(!validReviewObservation(value,checkpoint))refused('ExplorerInvalidReply');return value;},
    close: invalidate,
  });
}
