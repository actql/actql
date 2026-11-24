import type * as Public from './cancellation.js';
type Original = Public.OriginalCancellation;
interface ObservationFields {state?:unknown;original?:{cancelRef?:unknown;attemptRef?:unknown};outcome?:unknown}
import {validCancellationRef, validOperationAttemptRef, validCancellationAttempt} from '@actql/client-wire';
const reject:()=>never=()=>{throw Object.assign(new Error('ExplorerInvalidCancellation'),{code:'ExplorerInvalidCancellation'});};
const sameRun=(a:Original['cancelRef'],b:Original['cancelRef'])=>(['namespaceId','authorityScopeCid','runDefinitionCid'] as const).every(key=>a?.[key]===b?.[key]);

// Retain exact Client-owned identities before dispatch. These are references,
// not a cancellation admission, permission, new revision or physical-stop ACK.
export function captureCancellation(cancelRef:unknown, attemptRef:unknown):Original {
  const ref=structuredClone(cancelRef), attempt=structuredClone(attemptRef);
  if (!validCancellationRef(ref) || !validOperationAttemptRef(attempt) ||
      attempt.operation !== 'cancel') reject();
  return Object.freeze({cancelRef:Object.freeze(ref),attemptRef:Object.freeze(attempt as Original['attemptRef'])});
}

// This presentation envelope is not an Owner cancellation-attempt wire.
// Unknown never manufactures an accepted/refused or physical-stop record.
export function validCancellationObservation(value:unknown, original:unknown):value is Public.CancellationObservation {
  if (!value || typeof value!=='object' || Array.isArray(value) ||
      !['observed','unknown'].includes((value as ObservationFields).state as string)) return false;
  const keys=(value as ObservationFields).state==='observed'?['state','original','outcome']:['state','original'];
  if (Object.keys(value).length!==keys.length || !keys.every(key=>Object.hasOwn(value,key))) return false;
  let saved,expected;try{saved=captureCancellation((value as ObservationFields).original?.cancelRef,(value as ObservationFields).original?.attemptRef);
    expected=captureCancellation((original as ObservationFields['original'])?.cancelRef,(original as ObservationFields['original'])?.attemptRef);}catch{return false;}
  const a=saved,b=expected;
  if (!sameRun(a.cancelRef,b.cancelRef) || a.cancelRef.cancelId!==b.cancelRef.cancelId ||
      a.cancelRef.expectedRevision!==b.cancelRef.expectedRevision ||
      a.attemptRef.attemptId!==b.attemptRef.attemptId || a.attemptRef.operation!==b.attemptRef.operation) return false;
  return (value as ObservationFields).state==='unknown'||validCancellationAttempt((value as ObservationFields).outcome,saved.cancelRef,saved.attemptRef);
}
