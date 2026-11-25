import type * as Public from './browser-source.js';
import type {WireRunRef, WireSubmissionRef} from '@actql/client-wire';
type BrowserSource = ReturnType<typeof Public.createExplorerBrowserSource>;
type StaticExplanation = Awaited<ReturnType<BrowserSource['staticExplanation']>>;
type SavedExplanation = Awaited<ReturnType<BrowserSource['runContext']>>;
interface Session {csrf:string;scopeEpoch:number;expiresAt:number;cancellation:boolean;checkpointList:boolean;checkpointReview:boolean;runStart:boolean;sample:boolean;debugResume:boolean}
interface SessionReply {capabilities:Record<string,unknown>;csrf:unknown;scopeEpoch:unknown;expiresAt:unknown}

import {checkpointPageModel,captureReviewReference,validReviewObservation} from '@actql/explorer-ui/checkpoint-review';
import {resumeControlOperationRef, validControlOperationLookup, validWireControlCommandShape,
  validWireControlOperationRefShape, snapshotClientRequest, validCancellationLookup, validRunRef, validSubmissionRef, validWireRunExplanationViewShape} from '@actql/client-wire';
import {captureCancellation, validCancellationObservation} from '@actql/explorer-ui/cancellation';
import {createReadEpoch, sampleMatchesPort, validSamplePortSelection} from '@actql/explorer-ui/read-model';

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

function validNarrative(plan: StaticExplanation['plan'] | null | undefined,
  story: StaticExplanation['story'] | undefined, context: StaticExplanation['context'] | undefined, locale: string) {
  return typeof plan?.logicalMapCid === 'string' && plan.logicalMapCid === story?.logicalMapCid &&
    plan.compiledPlanCid === story.compiledPlanCid && plan.programDefinitionCid === story.programDefinitionCid &&
    story.locale === locale && Array.isArray(story.occurrences) && Array.isArray(context) &&
    story.narrative?.version === 'actql-explanation-narrative/0.1' &&
    typeof story.narrative.summary === 'string' && story.narrative.summary.length > 0 &&
    Array.isArray(story.narrative.clauses) && Array.isArray(story.narrative.items) &&
    story.narrative.items.length === context.length + story.occurrences.length &&
    context.every(item => typeof item?.text === 'string' && item.origin != null);
}

function readStartObservation(value: unknown, submissionRef: WireSubmissionRef): Public.ExplorerStartObservation {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) refused('ExplorerInvalidReply');
  const {state, ref} = value as {state?: unknown; ref?: unknown};
  if (state === 'ready' && Object.keys(value).length === 2 && validRunRef(ref) &&
      ref.authorityScopeCid === submissionRef.epoch.authorityScopeCid) return {state, ref};
  if (Object.keys(value).length === 1 &&
      (state === 'held' || state === 'preparing' || state === 'not_accepted' || state === 'preparation_failed' ||
        state === 'unresolvable' || state === 'reply_unknown')) return {state};
  refused('ExplorerInvalidReply');
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
        const failure = answer as {error?: unknown} | null | undefined;
        const scopeRefused = response.status === 401 ||
          response.status === 403 && failure?.error !== 'ExplorerReadRefused';
        if (original === session && scopeRefused) invalidate();
        if (path === '/api/read/run-sample' && response.status === 403 && failure?.error === 'ExplorerReadRefused') {
          refused('ExplorerSampleAccessDenied');
        }
        if (path === '/api/control/resume') {
          if (response.status === 409 && failure?.error === 'ExplorerControlRevisionConflict') {
            refused('ExplorerControlRevisionConflict');
          }
          if (response.status === 400 && failure?.error === 'ExplorerResumeUnsupported') refused('ExplorerResumeUnsupported');
        }
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
  const readRunProjection = async <Projection extends Readonly<{runRef: WireRunRef}>>(
    kind: 'observation' | 'run-plan', ref: WireRunRef) => {
    const original = Object.freeze({...ref});
    if (!validRunRef(original)) refused('ExplorerInvalidReply');
    const value = await read<Projection>(kind, {ref: original});
    const response = value?.runRef;
    if (!validRunRef(response) || response.namespaceId !== original.namespaceId ||
        response.authorityScopeCid !== original.authorityScopeCid ||
        response.runDefinitionCid !== original.runDefinitionCid) refused('ExplorerInvalidReply');
    return value;
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
          Object.keys(capabilities).length !== 9 + Number(capabilities.runStart === true) + Number(capabilities.debugResume === true) ||
          (Object.hasOwn(capabilities, 'debugResume') && capabilities.debugResume !== true) ||
          (Object.hasOwn(capabilities, 'runStart') && capabilities.runStart !== true) ||
          typeof capabilities.plan !== 'boolean' ||
          capabilities.run !== true || capabilities.resultMetadata !== true ||
          capabilities.resultPayload !== false || capabilities.control !== false ||
          typeof capabilities.sample !== 'boolean' || typeof capabilities.cancellation !== 'boolean'||typeof capabilities.checkpointList!=='boolean'||typeof capabilities.checkpointReview!=='boolean') refused('ExplorerInvalidReply');
      session = Object.freeze({csrf: answer.csrf as string, scopeEpoch: answer.scopeEpoch as number,
        expiresAt: answer.expiresAt as number, cancellation: capabilities.cancellation as boolean,checkpointList:capabilities.checkpointList as boolean,checkpointReview:capabilities.checkpointReview as boolean,
        runStart: capabilities.runStart === true, sample: capabilities.sample === true,
        debugResume: capabilities.debugResume === true});
      return answer.capabilities as Public.ExplorerCapabilities;
    },
    async prepareStart() {
      if (!session?.runStart) refused('ExplorerCapabilityUnavailable');
      const ref = await read('prepare-start', {});
      if (!validSubmissionRef(ref)) refused('ExplorerInvalidReply');
      return ref;
    },
    async startRun(selection) {
      if (!session?.runStart) refused('ExplorerCapabilityUnavailable');
      const input = snapshotClientRequest(selection) as Partial<Public.ExplorerStartSelection>;
      const debug = input?.executionProfile === 'debug' && typeof input.programDefinitionCid === 'string' &&
        /^sha256:[0-9a-f]{64}$/u.test(input.programDefinitionCid);
      if (!validSubmissionRef(input?.ref) || (debug ? Object.keys(input).length !== 5
        : Object.keys(input).length !== 3 || input.executionProfile !== undefined ||
          input.programDefinitionCid !== undefined) ||
          typeof input.text !== 'string' || !input.text.isWellFormed() || !input.text.trim() ||
          input.format === undefined || !['sql', 'aql', 'aql-text', 'program'].includes(input.format)) refused('ExplorerInvalidReply');
      const original = session;
      try {return readStartObservation(await read('start-run', input, 'control'), input.ref);}
      catch (error) {
        if (session === original && now() < original.expiresAt) return {state: 'reply_unknown'};
        throw error;
      }
    },
    async lookupStart(ref) {
      if (!session?.runStart) refused('ExplorerCapabilityUnavailable');
      const original = snapshotClientRequest(ref);
      if (!validSubmissionRef(original)) refused('ExplorerInvalidReply');
      return readStartObservation(await read('lookup-start', {ref: original}), original);
    },
    plan(input, options) {return read<Awaited<ReturnType<BrowserSource['plan']>>>('plan', {input, ...(options === undefined ? {} : {options})});},
    async staticExplanation(input, options, locale = 'en') {
      if (locale !== 'en' && locale !== 'ja') refused('ExplorerInvalidReply');
      const value = await read<StaticExplanation>('static-explanation', {input, locale, ...(options === undefined ? {} : {options})});
      const {plan, story, context} = value ?? {} as Partial<StaticExplanation>;
      if (!validNarrative(plan, story, context, locale)) refused('ExplorerInvalidReply');
      return value;
    },
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
    observe(ref) {return readRunProjection<Awaited<ReturnType<BrowserSource['observe']>>>('observation', ref);},
    runPlan(ref) {return readRunProjection<Awaited<ReturnType<BrowserSource['runPlan']>>>('run-plan', ref);},
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
    async runContext(ref, locale = 'en') {
      const original = Object.freeze({...ref});
      if (!validRunRef(original) || (locale !== 'en' && locale !== 'ja')) refused('ExplorerInvalidReply');
      const value = await read<SavedExplanation>('run-explanation-context', {ref: original, locale});
      if (!validRunRef(value?.runRef) || Object.keys(value).length !== 3 ||
          value.runRef.namespaceId !== original.namespaceId ||
          value.runRef.authorityScopeCid !== original.authorityScopeCid ||
          value.runRef.runDefinitionCid !== original.runDefinitionCid) refused('ExplorerInvalidReply');
      const {plan, explanation} = value;
      if (explanation?.state === 'projected') {
        if (Object.keys(explanation).length !== 3 ||
            !validNarrative(plan, explanation.story, explanation.context, locale)) refused('ExplorerInvalidReply');
      } else if (plan !== null || explanation?.state !== 'not_projected' ||
          explanation.reason !== 'not_retained' || Object.keys(explanation).length !== 2) {
        refused('ExplorerInvalidReply');
      }
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
      const {plan, explanation} = value;
      if (explanation?.state === 'projected') {
        if (!validNarrative(plan, explanation.story, [], locale)) refused('ExplorerInvalidReply');
      } else if (plan !== null || explanation?.state !== 'not_projected' ||
          !['not_retained', 'profile_not_supported'].includes(explanation.reason)) {
        refused('ExplorerInvalidReply');
      }
      return value;
    },
    async prepareResume(ref, {operationId, expectedRevision, until}) {
      if (!session?.debugResume) refused('ExplorerCapabilityUnavailable');
      const original = Object.freeze(snapshotClientRequest(ref));
      if (!validRunRef(original)) refused('ExplorerInvalidReply');
      const command = await read('prepare-resume', {ref: original, operationId, expectedRevision, until});
      if (!validWireControlCommandShape(command) || command.operation !== 'resume' ||
          command.run_ref.namespaceId !== original.namespaceId ||
          command.run_ref.authorityScopeCid !== original.authorityScopeCid ||
          command.run_ref.runDefinitionCid !== original.runDefinitionCid ||
          command.operation_id !== operationId || command.expected_control_revision !== expectedRevision ||
          command.interval?.until !== until || command.interval.guards !== null) refused('ExplorerInvalidReply');
      return command;
    },
    async resume(command) {
      if (!session?.debugResume) refused('ExplorerCapabilityUnavailable');
      const selected = session, captured = snapshotClientRequest(command);
      if (!validWireControlCommandShape(captured) || captured.operation !== 'resume') refused('ExplorerInvalidReply');
      const operationRef = resumeControlOperationRef(captured);
      let answer: unknown;
      try {answer = await read('resume', {command: captured}, 'control');}
      catch (error) {
        const code = (error as {code?: string} | null)?.code;
        if (selected !== session || now() >= selected.expiresAt ||
            code === 'ExplorerControlRevisionConflict' || code === 'ExplorerResumeUnsupported') throw error;
      }
      return validControlOperationLookup(answer, operationRef) ? answer : {state: 'reply_unknown', operationRef};
    },
    async lookupControlOperation(operationRef) {
      if (!session?.debugResume) refused('ExplorerCapabilityUnavailable');
      const original = snapshotClientRequest(operationRef);
      if (!validWireControlOperationRefShape(original)) refused('ExplorerInvalidReply');
      const answer = await read('lookup-control-operation', {operationRef: original});
      if (!validControlOperationLookup(answer, original)) refused('ExplorerInvalidReply');
      return answer;
    },
    async runSample(ref, port) {
      if (!session?.sample) refused('ExplorerCapabilityUnavailable');
      const original = Object.freeze(snapshotClientRequest(ref));
      const selected = Object.freeze(snapshotClientRequest(port));
      if (!validRunRef(original) || !validSamplePortSelection(selected)) refused('ExplorerInvalidReply');
      try {
        const value = await read('run-sample', {ref: original, port: selected});
        if (!sampleMatchesPort(value, original, selected)) refused('ExplorerInvalidReply');
        return value;
      } catch (error) {
        if ((error as {code?: string} | null)?.code === 'ExplorerSampleAccessDenied') return {state: 'forbidden'};
        throw error;
      }
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
