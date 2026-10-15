import type {CheckpointPanelProps} from './checkpoint-review.js';
import {reviewText} from '@actql/explorer-ui/checkpoint-review';
export function CheckpointPanel({page,review,pending,canList,canRead,onList,onRead}:CheckpointPanelProps){
 const content=review?reviewText(review):null;
 return <section className="actql-checkpoint-review" aria-label="Current Host Checkpoint reviews">
  <h2>Checkpoint review</h2>
  <p>One current authorized Host page, independent of the selected Run. Listing, review reading and answering need separate permissions.
   This viewer does not answer a Checkpoint, create a Run or resume execution.</p>
  <button type="button" disabled={pending||!canList} onClick={onList}>List waiting Checkpoints</button>
  {!canList&&<p>Checkpoint listing is unavailable in this Client.</p>}
  {page&&<><p>{page.items.length===0?'No waiting Checkpoints in this authorized page.':'Original waiting Checkpoint metadata.'}
   {page.hasNext?' A further page exists; it has not been read.':''} This is not complete history.</p>
   {page.items.map(checkpoint=><article key={checkpoint.checkpointCid} aria-label={`Checkpoint ${checkpoint.checkpointId}`}>
    <h3>{checkpoint.humanSummary}</h3><p>{checkpoint.checkpointCid}</p>
    <pre aria-label="Original Checkpoint metadata">{checkpoint.metadataJson}</pre>
    <button type="button" disabled={pending||!canRead} onClick={()=>onRead({checkpointCid:checkpoint.checkpointCid,
      reviewProjectionCid:checkpoint.reviewProjectionCid})}>Read original review</button>
   </article>)}</>}
  {!canRead&&<p>Review reading is unavailable in this Client.</p>}
  {review&&content&&<section aria-label="Original sealed review artifact"><h3>Original review artifact</h3>
   <p>{review.artifactCid} · {review.byteLength} bytes · Checkpoint {review.checkpointCid}</p>
   <p>Exact bytes returned by the existing SDK review read. This content does not establish current permission, an accepted answer or a resumed Run.</p>
   {content.kind==='utf8'?<pre aria-label="Original review text">{content.text}</pre>:<><p>Binary artifact; no text or Effect diff is inferred.</p><pre aria-label="Original binary review base64">{content.base64}</pre></>}
  </section>}
 </section>;
}
