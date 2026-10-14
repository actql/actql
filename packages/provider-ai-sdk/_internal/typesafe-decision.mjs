import {createTypeSafeAi} from '@ai-sdk/typesafe-ai';
import {interceptSdkRequest} from './intercepted-request.mjs';
import {isDeepStrictEqual} from 'node:util';
import {createSdkNativeDecisionPreflight} from './model-port.mjs';

// Private physical preparation, not Common Decision admission or a native
// completion/profile issuer. The original caller supplies checked, bounded
// state/questions and funds the SDK representation before invoking this.
// Public exports and installed native execution remain unavailable.
export function prepareTypeSafeDecisionRequest({modelId,baseURL,apiKey,options,
  maxRequestBytes,maxHeaderBytes,maxHeaders,signal,notify,verifyRequest}) {
  // Compare the actual existing enumerable field vector. Joining names can
  // mistake one comma-bearing own field for both required originals and then
  // read their values from the prototype. This neither changes the accepted
  // DATA/accessor/hidden/symbol rules nor issues native Task admission.
  const optionKeys=options!==null&&typeof options==='object'&&!Array.isArray(options)
    ? Object.keys(options).sort():undefined;
  if(typeof modelId!=='string'||modelId.length===0||
    typeof baseURL!=='string'||baseURL.endsWith('/')||
    typeof apiKey!=='string'||apiKey.length===0||
    options===null||typeof options!=='object'||Array.isArray(options)||
    optionKeys.length!==2||optionKeys[0]!=='questions'||optionKeys[1]!=='state'||
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
  modelId,baseURL,apiKey,maxRequestBytes,maxHeaderBytes,maxHeaders,signal,notify}) {
  if (!['clientProgramNativeDecisionRequestMatches',
    'clientProgramNativeDecisionRequestBinding','clientProgramNativeDecisionRequestWires']
    .every(name=>typeof moon?.[name]==='function') ||
      !moon.clientProgramNativeDecisionRequestMatches(projected,admittedProvider,request)) {
    throw new TypeError('TypeSafeOriginalProjectionUnavailable');
  }
  const binding=moon.clientProgramNativeDecisionRequestBinding(projected);
  const wires=moon.clientProgramNativeDecisionRequestWires(projected);
  if (binding===undefined || wires===undefined ||
      binding._0!==taskCid || binding._1!==promptCid ||
      binding._2!==outputSchemaCid || binding._3!==modelSelector ||
      typeof wires._0!=='string' || typeof wires._1!=='string') {
    throw new TypeError('TypeSafeOriginalProjectionBindingMismatch');
  }
  const stateWire=wires._0,questionsWire=wires._1;
  let state,questions;
  try {state=JSON.parse(stateWire);questions=JSON.parse(questionsWire);}
  catch {throw new TypeError('TypeSafeOriginalProjectionWireUnavailable');}
  // These trees/callbacks and the SDK overlap are funded by the original
  // installation before entry. JSON parsing in this external adapter is
  // finite under Common's projection bounds, not cooperatively preemptible.
  return prepareTypeSafeDecisionRequest({modelId,baseURL,apiKey,
    options:{state,questions},maxRequestBytes,maxHeaderBytes,maxHeaders,signal,notify,
    verifyRequest(body) {
      // Compare against immutable original wires, never the mutable tree
      // handed to SDK code. The pinned SDK maps Boolean to its native noul
      // wire discriminator; Common's question and answer contract is unchanged.
      const originalQuestions=Object.fromEntries(Object.entries(JSON.parse(questionsWire))
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
  maxHeaders, signal, notify, ...port}) {
  if (!moon.clientProgramNativeDecisionRequestMatches?.(projected, admittedProvider, request)) {
    throw new TypeError('TypeSafeOriginalProjectionUnavailable');
  }
  let terminal = false;
  const progress = {
    advance() {
      if (terminal || signal?.aborted) { terminal = true; return {kind: 'rejected'}; }
      terminal = true;
      return {kind: 'ready', preparation: prepareProjectedTypeSafeDecisionRequest({
        moon, projected, admittedProvider, request, taskCid, promptCid, outputSchemaCid,
        modelSelector, modelId, baseURL, apiKey, maxRequestBytes, maxHeaderBytes,
        maxHeaders, signal, notify})};
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
  admittedProvider,request,admittedResponse,limits}) {
  if (typeof moon?.clientProgramProjectNativeDecisionAnswers!=='function' ||
      !moon.clientProgramNativeDecisionRequestMatches?.(projected,admittedProvider,request)) {
    throw new TypeError('TypeSafeOriginalProjectionUnavailable');
  }
  const keys=['maxBytes','maxDepth','maxNodes','maxWork'];
  const descriptors=limits===null || typeof limits!=='object' || Array.isArray(limits)
    ? undefined : Object.getOwnPropertyDescriptors(limits);
  const amounts=descriptors===undefined ? undefined : keys.map(name=>descriptors[name]?.value);
  if (limits===null || typeof limits!=='object' || Array.isArray(limits) ||
      Reflect.ownKeys(descriptors).length!==keys.length ||
      keys.some((name,index)=>!Object.hasOwn(descriptors[name] ?? {},'value') ||
        !Number.isSafeInteger(amounts[index]) ||
        amounts[index]<(name==='maxWork'?0:1) || amounts[index]>2_147_483_647)) {
    throw new TypeError('InvalidTypeSafeAnswerProjectionLimits');
  }
  // Validate and pass the same DATA descriptor values, never re-read a getter
  // or Proxy property after checking a different finite amount.
  const result=moon.clientProgramProjectNativeDecisionAnswers(projected,
    admittedProvider,request,admittedResponse,amounts[0],amounts[2],amounts[1],amounts[3]);
  if (result?.$tag!==1) throw new TypeError('TypeSafeOriginalAnswerProjectionRefused');
  return result._0;
}
