import {runtimeField, runtimeIsOk} from './compiler-binding.generated.mjs';
import {createTypeSafeAi} from '@ai-sdk/typesafe-ai';
import {interceptSdkRequest} from './intercepted-request.mjs';
import {isDeepStrictEqual} from 'node:util';
import {createSdkNativeDecisionPreflight} from './model-port.mjs';
import {fixedInferResponseLimits} from './bounded-response.mjs';

type InterceptionOptions = Parameters<typeof interceptSdkRequest>[0];
type DecisionOptions = Pick<Parameters<ReturnType<ReturnType<typeof createTypeSafeAi>['decisionModel']>['doDecide']>[0], 'state' | 'questions'>;
type PhysicalOptions = Parameters<typeof createSdkNativeDecisionPreflight>[0];
type ResponseLimits = Parameters<typeof fixedInferResponseLimits>[0];
interface ProjectionRuntime {
  clientProgramNativeDecisionRequestMatches?(projected: unknown, provider: unknown, request: unknown): unknown;
  clientProgramNativeDecisionRequestBinding?(projected: unknown): unknown;
  clientProgramNativeDecisionRequestWires?(projected: unknown): unknown;
}
interface TransportRuntime {
  clientProgramModelResponseProfileTransportMatches?(profile: unknown, requestBytes: number,
    maxBytes: number, maxChunkBytes: number, maxChunks: number, maxHeaderBytes: number): unknown;
}
type PreparationOptions = Pick<InterceptionOptions,
  'maxRequestBytes' | 'maxHeaderBytes' | 'maxHeaders' | 'signal' | 'notify' | 'verifyRequest'> & {
    modelId: string; baseURL: string; apiKey: string; options: DecisionOptions;
  };
type ProjectionInput = Omit<PreparationOptions, 'options' | 'verifyRequest'> & {
  moon: ProjectionRuntime; projected: unknown; admittedProvider: unknown; request: unknown;
  taskCid: string; promptCid: string; outputSchemaCid: string; modelSelector: string;
};
type ProjectionPreflightInput = Omit<PhysicalOptions, 'moon' | 'notify'> & Omit<ProjectionInput, 'apiKey' | 'notify'> & {
  apiKey: string | undefined; notify: (() => unknown) | undefined;
  moon: ProjectionRuntime & TransportRuntime & PhysicalOptions['moon']; probability: unknown;
};
interface AnswerRuntime extends ProjectionRuntime {
  clientProgramProjectNativeDecisionAnswers?(projected: unknown, provider: unknown,
    request: unknown, response: unknown, maxBytes: number, maxNodes: number,
    maxDepth: number, maxWork: number): unknown;
}

// Consume the existing Common profile predicate, not another support table or
// numerical policy. Callers retain immutable physical declarations through
// their original preparation; matching is neither funding nor send authority.
export function requireTypeSafeOriginalTransportLimits(moon: TransportRuntime, profile: unknown, requestBytes: number, responseLimits: ResponseLimits) {
  if(typeof moon?.clientProgramModelResponseProfileTransportMatches!=='function'||
      profile===undefined||profile===null) {
    throw new TypeError('TypeSafeOriginalTransportLimitsUnavailable');
  }
  if(!Number.isSafeInteger(requestBytes)||requestBytes<1||requestBytes>2147483647||
      moon.clientProgramModelResponseProfileTransportMatches(profile,requestBytes,
        responseLimits.maxBytes,responseLimits.maxChunkBytes,responseLimits.maxChunks,
        responseLimits.maxHeaderBytes)!==true) {
    throw new TypeError('TypeSafeOriginalTransportLimitsMismatch');
  }
}

// Private physical preparation, not Common Decision admission or a native
// completion/profile issuer. The original caller supplies checked, bounded
// state/questions and funds the SDK representation before invoking this.
// Public exports and installed native execution remain unavailable.
export function prepareTypeSafeDecisionRequest({modelId,baseURL,apiKey,options,
  maxRequestBytes,maxHeaderBytes,maxHeaders,signal,notify,verifyRequest}: PreparationOptions) {
  if(typeof modelId!=='string'||modelId.length===0||
    typeof baseURL!=='string'||baseURL.endsWith('/')||
    typeof apiKey!=='string'||apiKey.length===0||
    options===null||typeof options!=='object'||Array.isArray(options)) {
    throw new TypeError('InvalidTypeSafeSdkPreparation');
  }
  // Preserve the original validation order: invalid scalar/receiver inputs
  // refuse before invoking any option inspection callback.
  // Joining names can mistake one comma-bearing own field for both required
  // originals and then read their values from the prototype. Compare the
  // actual enumerable field vector without changing hidden/symbol rules.
  const optionKeys=Object.keys(options).sort();
  if(optionKeys.length!==2||optionKeys[0]!=='questions'||optionKeys[1]!=='state'||
    Object.values(Object.getOwnPropertyDescriptors(options)).some(d=>!('value' in d))||
    options.questions===null||typeof options.questions!=='object'||Array.isArray(options.questions)) {
    throw new TypeError('InvalidTypeSafeSdkPreparation');
  }
  // Low-level doDecide is the verified native v4 operation. It has no
  // high-level retry/default-provider/tool/workflow loop. Inject the same
  // interceptor used by generation at its actual final HTTP boundary.
  return interceptSdkRequest({endpoint:`${baseURL}/systemone`,
    maxRequestBytes,maxHeaderBytes,maxHeaders,signal,notify,verifyRequest,
    runSdk:(fetch,abortSignal)=>createTypeSafeAi({baseURL,apiKey,fetch})
      .decisionModel(modelId).doDecide({...options,abortSignal})});
}

// Consume the existing Common-issued immutable projection. This private
// adapter implements the verified SDK representation only, not Decision
// semantics, precision, response completion, funding or dispatch authority.
// The original caller retains the projection view through answer mapping;
// retiring its emitter does not retire that separate borrowed view.
export function prepareProjectedTypeSafeDecisionRequest({moon,projected,
  admittedProvider,request,taskCid,promptCid,outputSchemaCid,modelSelector,
  modelId,baseURL,apiKey,maxRequestBytes,maxHeaderBytes,maxHeaders,signal,notify}: ProjectionInput) {
  if (!(['clientProgramNativeDecisionRequestMatches',
    'clientProgramNativeDecisionRequestBinding','clientProgramNativeDecisionRequestWires'] as const)
    .every(name=>typeof moon?.[name]==='function') ||
      !moon.clientProgramNativeDecisionRequestMatches!(projected,admittedProvider,request)) {
    throw new TypeError('TypeSafeOriginalProjectionUnavailable');
  }
  const binding=moon.clientProgramNativeDecisionRequestBinding!(projected);
  const wires=moon.clientProgramNativeDecisionRequestWires!(projected);
  if (binding===undefined || wires===undefined ||
      runtimeField(binding, 0)!==taskCid || runtimeField(binding, 1)!==promptCid ||
      runtimeField(binding, 2)!==outputSchemaCid || runtimeField(binding, 3)!==modelSelector ||
      typeof runtimeField(wires, 0)!=='string' || typeof runtimeField(wires, 1)!=='string') {
    throw new TypeError('TypeSafeOriginalProjectionBindingMismatch');
  }
  const stateWire=runtimeField(wires, 0) as string,questionsWire=runtimeField(wires, 1) as string;
  let state: unknown, questions: unknown;
  try {state=JSON.parse(stateWire);questions=JSON.parse(questionsWire);}
  catch {throw new TypeError('TypeSafeOriginalProjectionWireUnavailable');}
  // These trees/callbacks and the SDK overlap are funded by the original
  // installation before entry. JSON parsing in this external adapter is
  // finite under Common's projection bounds, not cooperatively preemptible.
  return prepareTypeSafeDecisionRequest({modelId,baseURL,apiKey,
    options:{state,questions} as DecisionOptions,maxRequestBytes,maxHeaderBytes,maxHeaders,signal,notify,
    verifyRequest(body) {
      // Compare against immutable original wires, never the mutable tree
      // handed to SDK code. The pinned SDK maps Boolean to its native noul
      // wire discriminator; Common's question and answer contract is unchanged.
      const originalQuestions=Object.fromEntries(Object.entries(JSON.parse(questionsWire) as Record<string, {type?: unknown}>)
        .map(([id,question])=>[id,question.type==='boolean'
          ? {...question,type:'noul'}:question]));
      return isDeepStrictEqual(JSON.parse(body),{
        model:modelId,state:JSON.parse(stateWire),questions:originalQuestions});
    },
  });
}

// Lazy original-view consumer of the same SDK/Entry/raw port as generation.
// The caller owns the escaped immutable view through raw answer mapping; this
// preparation borrows it and cannot retire the caller's separate lifetime.
// Complete native raw validation and normal funding remain separate required
// installation boundaries, not grants derived from this prepared Plan.
export function createProjectedTypeSafeDecisionPreflight({moon, projected,
  admittedProvider, request, probability, taskCid, promptCid, outputSchemaCid,
  modelSelector, modelId, baseURL, apiKey, maxRequestBytes, maxHeaderBytes,
  maxHeaders, signal, notify, ...port}: ProjectionPreflightInput): ReturnType<typeof createSdkNativeDecisionPreflight> {
  if (!moon.clientProgramNativeDecisionRequestMatches?.(projected, admittedProvider, request)) {
    throw new TypeError('TypeSafeOriginalProjectionUnavailable');
  }
  // Direct private callers do not bypass the installed profile check. Retain
  // the same snapshotted reader limits that were compared, not mutable inputs
  // that may change before later SDK preparation or physical acquisition.
  port.responseLimits=fixedInferResponseLimits(port.responseLimits!);
  requireTypeSafeOriginalTransportLimits(moon,port.profile,maxRequestBytes,port.responseLimits);
  let terminal = false;
  const progress = {
    advance() {
      if (terminal || signal?.aborted) { terminal = true; return {kind: 'rejected'}; }
      terminal = true;
      return {kind: 'ready', preparation: prepareProjectedTypeSafeDecisionRequest({
        moon, projected, admittedProvider, request, taskCid, promptCid, outputSchemaCid,
        modelSelector, modelId, baseURL, apiKey, maxRequestBytes, maxHeaderBytes,
        maxHeaders, signal, notify} as ProjectionInput)};
    },
    cleanup() {
      terminal = true;
      projected = admittedProvider = request = probability = undefined;
      signal = notify = apiKey = undefined;
      return true;
    },
  };
  return createSdkNativeDecisionPreflight({...port, moon, request, notify,
    preparationProgress: progress}, projected, admittedProvider, probability);
}

// Common owns the answer alias mapping. This private consumer accepts only an
// existing admitted response cursor; it never parses SDK-decoded objects into
// authority or treats a mapped wire as saved/complete/validated output. The
// original raw Store/EOF/status/profile and Decision validator remain separate.
export function projectProjectedTypeSafeDecisionAnswers({moon,projected,
  admittedProvider,request,admittedResponse,limits}: {moon: AnswerRuntime; projected: unknown; admittedProvider: unknown; request: unknown; admittedResponse: unknown; limits: unknown}) {
  if (typeof moon?.clientProgramProjectNativeDecisionAnswers!=='function' ||
      !moon.clientProgramNativeDecisionRequestMatches?.(projected,admittedProvider,request)) {
    throw new TypeError('TypeSafeOriginalProjectionUnavailable');
  }
  const keys=['maxBytes','maxDepth','maxNodes','maxWork'];
  const descriptors=limits===null || typeof limits!=='object' || Array.isArray(limits)
    ? undefined : Object.getOwnPropertyDescriptors(limits);
  const amounts: unknown[] | undefined=descriptors===undefined ? undefined : keys.map(name=>descriptors[name]?.value);
  if (limits===null || typeof limits!=='object' || Array.isArray(limits) ||
      Reflect.ownKeys(descriptors!).length!==keys.length ||
      keys.some((name,index)=>!Object.hasOwn(descriptors![name] ?? {},'value') ||
        !Number.isSafeInteger(amounts![index]) ||
        (amounts![index] as number)<(name==='maxWork'?0:1) || (amounts![index] as number)>2_147_483_647)) {
    throw new TypeError('InvalidTypeSafeAnswerProjectionLimits');
  }
  // Validate and pass the same DATA descriptor values, never re-read a getter
  // or Proxy property after checking a different finite amount.
  const result=moon.clientProgramProjectNativeDecisionAnswers!(projected,
    admittedProvider,request,admittedResponse,amounts![0] as number,amounts![2] as number,amounts![1] as number,amounts![3] as number);
  if (!runtimeIsOk(result)) throw new TypeError('TypeSafeOriginalAnswerProjectionRefused');
  return runtimeField(result, 0);
}
