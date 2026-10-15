import {validCheckpointPage,validCheckpointReview,withinResultDescriptionLimits} from '@actql/client-wire';
import {ExplorerReadError} from './presentation-limits.mjs';
const refuse=()=>{throw new ExplorerReadError('ExplorerInvalidCheckpointReview');};
export const checkpointReadLimits=Object.freeze({maxItems:32,maxReviewBytes:65536,
  maxWireBytes:65536,maxNodes:10000,maxDepth:64});
const frozen=value=>{if(value!==null&&typeof value==='object'){for(const child of Object.values(value))frozen(child);Object.freeze(value);}return value;};
const exact=(v,keys)=>v!==null&&typeof v==='object'&&!Array.isArray(v)&&
 Object.keys(v).length===keys.length&&keys.every(k=>Object.hasOwn(v,k));
export function checkpointPageModel(value){
 if(!withinResultDescriptionLimits(value,checkpointReadLimits)||!validCheckpointPage(value,checkpointReadLimits.maxItems))refuse();
 return frozen(structuredClone(value));
}
export function captureCheckpoint(value){
 const copy=structuredClone(value);if(!withinResultDescriptionLimits(copy,checkpointReadLimits)||!validCheckpointPage({items:[copy]},1))refuse();
 return frozen(copy);
}
const sameJSON=(a,b)=>a===b||a!==null&&b!==null&&typeof a==='object'&&typeof b==='object'&&
 Array.isArray(a)===Array.isArray(b)&&Object.keys(a).length===Object.keys(b).length&&
 Object.keys(a).every(key=>Object.hasOwn(b,key)&&sameJSON(a[key],b[key]));
export function validReviewObservation(value,checkpoint){
 if(!exact(value,['checkpoint','artifactCid','byteLength','contentBase64']))return false;
 let selected;try{selected=captureCheckpoint(value.checkpoint);checkpoint=captureCheckpoint(checkpoint);}catch{return false;}
 if(!sameJSON(selected,checkpoint))return false;
 return value.artifactCid===checkpoint.reviewProjectionCid&&validCheckpointReview({kind:'review',checkpointCid:checkpoint.checkpointCid,
  artifactCid:value.artifactCid,byteLength:value.byteLength,contentBase64:value.contentBase64},
  {checkpointCid:checkpoint.checkpointCid,maxBytes:checkpointReadLimits.maxReviewBytes});
}
async function currentRead(ticket,read){ticket.assertCurrent();try{const value=await read();ticket.assertCurrent();return value;}
 catch(error){ticket.assertCurrent();throw error;}}
// A Host-authorized waiting page is not a Run join, complete history or resolve permission.
export async function readWaitingCheckpoints(client,ticket){
 if(typeof client.checkpoints!=='function')throw new ExplorerReadError('ExplorerCapabilityUnavailable');
 const page=await currentRead(ticket,()=>client.checkpoints({limit:checkpointReadLimits.maxItems}));
 return checkpointPageModel(page);
}
// The existing public SDK verifies review bytes against the original artifact CID.
// This adapter copies that admitted read; it does not issue a seal, identity or authority.
export async function readCheckpointReview(client,input,ticket){
 const checkpoint=captureCheckpoint(input);
 if(typeof client.reviewCheckpoint!=='function')throw new ExplorerReadError('ExplorerCapabilityUnavailable');
 const value=await currentRead(ticket,()=>client.reviewCheckpoint(checkpoint,{maxBytes:checkpointReadLimits.maxReviewBytes}));
 if(!exact(value,['checkpointCid','artifactCid','bytes'])||value.checkpointCid!==checkpoint.checkpointCid||
  value.artifactCid!==checkpoint.reviewProjectionCid||!(value.bytes instanceof Uint8Array)||
  value.bytes.byteLength>checkpointReadLimits.maxReviewBytes)refuse();
 // Capture the response once before any subsequent callback or await.
 const bytes=new Uint8Array(value.bytes);let binary='';for(const byte of bytes)binary+=String.fromCharCode(byte);
 const result={checkpoint,artifactCid:value.artifactCid,byteLength:bytes.length,contentBase64:btoa(binary)};
 if(!validReviewObservation(result,checkpoint))refuse();ticket.assertCurrent();return frozen(result);
}
export function reviewText(value){
 if(!validReviewObservation(value,value?.checkpoint))refuse();
 const bytes=Uint8Array.from(atob(value.contentBase64),c=>c.charCodeAt(0));
 try{return {kind:'utf8',text:new TextDecoder('utf-8',{fatal:true}).decode(bytes)};}
 catch{return {kind:'binary',base64:value.contentBase64};}
}
