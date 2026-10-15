import {validCancellationRef, validOperationAttemptRef, validCancellationAttempt} from '@actql/client-wire';
const reject=()=>{throw Object.assign(new Error('ExplorerInvalidCancellation'),{code:'ExplorerInvalidCancellation'});};
const sameRun=(a,b)=>['namespaceId','authorityScopeCid','runDefinitionCid'].every(key=>a?.[key]===b?.[key]);

// Retain exact Client-owned identities before dispatch. These are references,
// not a cancellation admission, permission, new revision or physical-stop ACK.
export function captureCancellation(cancelRef, attemptRef) {
  const ref=structuredClone(cancelRef), attempt=structuredClone(attemptRef);
  if (!validCancellationRef(ref) || !validOperationAttemptRef(attempt) ||
      attempt.operation !== 'cancel') reject();
  return Object.freeze({cancelRef:Object.freeze(ref),attemptRef:Object.freeze(attempt)});
}

// This presentation envelope is not an Owner cancellation-attempt wire.
// Unknown never manufactures an accepted/refused or physical-stop record.
export function validCancellationObservation(value, original) {
  if (!value || typeof value!=='object' || Array.isArray(value) ||
      !['observed','unknown'].includes(value.state)) return false;
  const keys=value.state==='observed'?['state','original','outcome']:['state','original'];
  if (Object.keys(value).length!==keys.length || !keys.every(key=>Object.hasOwn(value,key))) return false;
  let saved,expected;try{saved=captureCancellation(value.original?.cancelRef,value.original?.attemptRef);
    expected=captureCancellation(original?.cancelRef,original?.attemptRef);}catch{return false;}
  const a=saved,b=expected;
  if (!sameRun(a.cancelRef,b.cancelRef) || a.cancelRef.cancelId!==b.cancelRef.cancelId ||
      a.cancelRef.expectedRevision!==b.cancelRef.expectedRevision ||
      a.attemptRef.attemptId!==b.attemptRef.attemptId || a.attemptRef.operation!==b.attemptRef.operation) return false;
  return value.state==='unknown'||validCancellationAttempt(value.outcome,saved.cancelRef,saved.attemptRef);
}
