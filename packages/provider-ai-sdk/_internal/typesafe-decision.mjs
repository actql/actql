import {createTypeSafeAi} from '@ai-sdk/typesafe-ai';
import {interceptSdkRequest} from './intercepted-request.mjs';

// Private physical preparation, not Common Decision admission or a native
// completion/profile issuer. The original caller supplies checked, bounded
// state/questions and funds the SDK representation before invoking this.
// Public exports and installed native execution remain unavailable.
export function prepareTypeSafeDecisionRequest({modelId,baseURL,apiKey,options,
  maxRequestBytes,maxHeaderBytes,maxHeaders,signal,notify,verifyRequest}) {
  if(typeof modelId!=='string'||modelId.length===0||
    typeof baseURL!=='string'||baseURL.endsWith('/')||
    typeof apiKey!=='string'||apiKey.length===0||
    options===null||typeof options!=='object'||Array.isArray(options)||
    Object.keys(options).sort().join(',')!=='questions,state'||
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
