import type {Client} from '@actql/sdk';
import type {ReadTicket} from '@actql/explorer-ui/read-model';
import {validCheckpointPage,withinResultDescriptionLimits} from '@actql/client-wire';
import {checkpointPageModel,captureReviewReference,validReviewObservation,checkpointReadLimits} from '@actql/explorer-ui/checkpoint-review';
const unavailable:()=>never=()=>{throw Object.assign(new Error('ExplorerCapabilityUnavailable'),{code:'ExplorerCapabilityUnavailable'});};
const refuse:()=>never=()=>{throw Object.assign(new Error('ExplorerInvalidCheckpointReview'),{code:'ExplorerInvalidCheckpointReview'});};
const exact=(v:unknown,keys:readonly string[]):v is Record<string,unknown>=>v!==null&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).length===keys.length&&keys.every(k=>Object.hasOwn(v,k));
async function currentRead<T>(ticket:ReadTicket,read:()=>T|Promise<T>):Promise<T>{ticket.assertCurrent();try{const value=await read();ticket.assertCurrent();return value;}
 catch(error){ticket.assertCurrent();throw error;}}
// Validate complete original Owner metadata before the smaller browser projection.
// The page is Host-scoped, not a guessed Run join, history or resolve permission.
export async function readWaitingCheckpoints(client:Partial<Pick<Client,'checkpoints'>>,ticket:ReadTicket){
 if(typeof client.checkpoints!=='function')unavailable();
 const page=await currentRead(ticket,()=>client.checkpoints!({limit:checkpointReadLimits.maxItems}));
 if(!withinResultDescriptionLimits(page,checkpointReadLimits)||!validCheckpointPage(page,checkpointReadLimits.maxItems))refuse();
 return checkpointPageModel({items:page.items.map(item=>({checkpointId:item.checkpointId,checkpointCid:item.checkpointCid,
  reviewProjectionCid:item.reviewProjectionCid,humanSummary:item.humanSummary,metadataJson:JSON.stringify(item)})),hasNext:page.next!==undefined});
}
// The existing SDK independently authorizes this read and verifies artifact bytes.
// The captured two-CID selector is a reference only; metadata/permission is not rebuilt.
export async function readCheckpointReview(client:Partial<Pick<Client,'reviewCheckpoint'>>,input:unknown,ticket:ReadTicket){
 const original=captureReviewReference(input);
 if(typeof client.reviewCheckpoint!=='function')unavailable();
 const value=await currentRead(ticket,()=>client.reviewCheckpoint!(original.checkpointCid,{maxBytes:checkpointReadLimits.maxReviewBytes}));
 if(!exact(value,['checkpointCid','artifactCid','bytes'])||value.checkpointCid!==original.checkpointCid||
  value.artifactCid!==original.reviewProjectionCid||!(value.bytes instanceof Uint8Array)||value.bytes.byteLength>checkpointReadLimits.maxReviewBytes)refuse();
 const bytes=new Uint8Array(value.bytes);let binary='';for(const byte of bytes)binary+=String.fromCharCode(byte);
 const result={checkpointCid:original.checkpointCid,artifactCid:value.artifactCid,byteLength:bytes.length,contentBase64:btoa(binary)};
 if(!validReviewObservation(result,original))refuse();ticket.assertCurrent();return Object.freeze(result);
}
