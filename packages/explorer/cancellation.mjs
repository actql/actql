import {validCancellationRef, validCancellationAttempt, validCancellationLookup} from '@actql/client-wire';
import {captureCancellation} from '@actql/explorer-ui/cancellation';
export {captureCancellation,validCancellationObservation} from '@actql/explorer-ui/cancellation';
const reject=()=>{throw Object.assign(new Error('ExplorerInvalidCancellation'),{code:'ExplorerInvalidCancellation'});};
const sameRun=(a,b)=>['namespaceId','authorityScopeCid','runDefinitionCid'].every(key=>a?.[key]===b?.[key]);

export async function requestExistingCancellation(client, original, ticket) {
  const {cancelRef,attemptRef}=captureCancellation(original.cancelRef,original.attemptRef);
  ticket.assertCurrent();
  const ref=Object.freeze({namespaceId:cancelRef.namespaceId,
    authorityScopeCid:cancelRef.authorityScopeCid,runDefinitionCid:cancelRef.runDefinitionCid});
  const run=await client.attach(ref);ticket.assertCurrent();
  if (typeof run.cancel !== 'function') throw Object.assign(new Error('ExplorerCapabilityUnavailable'),
    {code:'ExplorerCapabilityUnavailable'});
  // Once invoked, a lost/foreign/malformed response stays Unknown. Do not
  // repeat cancel or ask status for another revision to manufacture a retry.
  let answer;
  try {answer=structuredClone(await run.cancel({cancelId:cancelRef.cancelId,
    expectedRevision:cancelRef.expectedRevision,attemptId:attemptRef.attemptId}));}
  catch {ticket.assertCurrent();return {state:'unknown',original:{cancelRef,attemptRef}};}
  ticket.assertCurrent();
  return validCancellationAttempt(answer,cancelRef,attemptRef)
    ? {state:'observed',original:{cancelRef,attemptRef},outcome:answer}
    : {state:'unknown',original:{cancelRef,attemptRef}};
}

export async function lookupExistingCancellation(client, input, ticket) {
  const cancelRef=structuredClone(input);
  if (!validCancellationRef(cancelRef)) reject();
  Object.freeze(cancelRef);ticket.assertCurrent();
  const ref=Object.freeze({namespaceId:cancelRef.namespaceId,
    authorityScopeCid:cancelRef.authorityScopeCid,runDefinitionCid:cancelRef.runDefinitionCid});
  const run=await client.attach(ref);ticket.assertCurrent();
  if (typeof run.lookupCancellation !== 'function') throw Object.assign(new Error('ExplorerCapabilityUnavailable'),
    {code:'ExplorerCapabilityUnavailable'});
  const answer=structuredClone(await run.lookupCancellation(cancelRef));ticket.assertCurrent();
  if (!validCancellationLookup(answer,cancelRef) ||
      answer.kind==='found' && !sameRun(answer.cancellation.ref,ref)) reject();
  return answer;
}
