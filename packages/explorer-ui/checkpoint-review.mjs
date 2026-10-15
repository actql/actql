import {ExplorerReadError} from './presentation-limits.mjs';
const refuse=()=>{throw new ExplorerReadError('ExplorerInvalidCheckpointReview');};
export const checkpointReadLimits=Object.freeze({maxItems:32,maxReviewBytes:65536,
 maxWireBytes:65536,maxNodes:10000,maxDepth:64});
const exact=(v,keys)=>v!==null&&typeof v==='object'&&!Array.isArray(v)&&
 Object.keys(v).length===keys.length&&keys.every(k=>Object.hasOwn(v,k));
const cid=value=>typeof value==='string'&&/^sha256:[0-9a-f]{64}$/u.test(value);
const frozen=value=>{if(value!==null&&typeof value==='object'){for(const child of Object.values(value))frozen(child);Object.freeze(value);}return value;};
// A private presentation projection, not the Checkpoint wire reader or an issuer.
// The Gateway admits the original complete metadata with the existing SDK codec.
export function checkpointPageModel(value){
 if(!exact(value,['items','hasNext'])||!Array.isArray(value.items)||value.items.length>checkpointReadLimits.maxItems||
  typeof value.hasNext!=='boolean'||!value.items.every(item=>exact(item,['checkpointId','checkpointCid','reviewProjectionCid','humanSummary','metadataJson'])&&
   typeof item.checkpointId==='string'&&item.checkpointId.length>0&&cid(item.checkpointCid)&&cid(item.reviewProjectionCid)&&
   typeof item.humanSummary==='string'&&typeof item.metadataJson==='string')||
  new Set(value.items.map(item=>item.checkpointCid)).size!==value.items.length||
  new TextEncoder().encode(JSON.stringify(value)).length>checkpointReadLimits.maxWireBytes)refuse();
 return frozen(structuredClone(value));
}
export function captureReviewReference(value){
 const copy=structuredClone(value);if(!exact(copy,['checkpointCid','reviewProjectionCid'])||!cid(copy.checkpointCid)||!cid(copy.reviewProjectionCid))refuse();
 return Object.freeze(copy);
}
export function validReviewObservation(value,input){
 let original;try{original=captureReviewReference(input);}catch{return false;}
 if(!exact(value,['checkpointCid','artifactCid','byteLength','contentBase64'])||value.checkpointCid!==original.checkpointCid||
  value.artifactCid!==original.reviewProjectionCid||!Number.isSafeInteger(value.byteLength)||value.byteLength<0||
  value.byteLength>checkpointReadLimits.maxReviewBytes||typeof value.contentBase64!=='string'||
  value.contentBase64.length>4*Math.ceil(checkpointReadLimits.maxReviewBytes/3)||
  !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/u.test(value.contentBase64))return false;
 const padding=value.contentBase64.endsWith('==')?2:value.contentBase64.endsWith('=')?1:0;
 return value.contentBase64.length/4*3-padding===value.byteLength;
}
export function reviewText(value){
 if(!validReviewObservation(value,{checkpointCid:value?.checkpointCid,reviewProjectionCid:value?.artifactCid}))refuse();
 const bytes=Uint8Array.from(atob(value.contentBase64),c=>c.charCodeAt(0));
 try{return {kind:'utf8',text:new TextDecoder('utf-8',{fatal:true}).decode(bytes)};}
 catch{return {kind:'binary',base64:value.contentBase64};}
}
