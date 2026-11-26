import {explorerCopy} from './i18n.mjs';
import type {CheckpointPanelProps} from './checkpoint-review.js';
import {reviewText} from '@actql/explorer-ui/checkpoint-review';
export function CheckpointPanel({page,review,pending,canList,canRead,onList,onRead,locale}:CheckpointPanelProps){
 const words=explorerCopy(locale);
 const content=review?reviewText(review):null;
 return <section className="actql-checkpoint-review" aria-label={words.currentHostReviews}>
  <h2>{words.checkpointReview}</h2>
  <p>{words.checkpointScope}</p>
  <button type="button" disabled={pending||!canList} onClick={onList}>{words.listWaitingCheckpoints}</button>
  {!canList&&<p>{words.checkpointListUnavailable}</p>}
  {page&&<><p>{page.items.length===0?words.noWaitingCheckpoints:words.originalWaitingCheckpoint}
   {page.hasNext?words.unreadCheckpointPage:''}{words.checkpointPartialHistory}</p>
   {page.items.map(checkpoint=><article key={checkpoint.checkpointCid} aria-label={words.checkpointId(checkpoint.checkpointId)}>
    <h3>{checkpoint.humanSummary}</h3><p>{checkpoint.checkpointCid}</p>
    <pre aria-label={words.originalCheckpointMetadata}>{checkpoint.metadataJson}</pre>
    <button type="button" disabled={pending||!canRead} onClick={()=>onRead({checkpointCid:checkpoint.checkpointCid,
      reviewProjectionCid:checkpoint.reviewProjectionCid})}>{words.readOriginalReview}</button>
   </article>)}</>}
  {!canRead&&<p>{words.checkpointReadUnavailable}</p>}
  {review&&content&&<section aria-label={words.sealedReviewArtifact}><h3>{words.originalReviewArtifact}</h3>
   <p>{words.reviewInfo(review.artifactCid, review.byteLength, review.checkpointCid)}</p>
   <p>{words.reviewBytesNote}</p>
   {content.kind==='utf8'?<pre aria-label={words.originalReviewText}>{content.text}</pre>:<><p>{words.binaryReviewNote}</p><pre aria-label={words.originalReviewBase64}>{content.base64}</pre></>}
  </section>}
 </section>;
}
