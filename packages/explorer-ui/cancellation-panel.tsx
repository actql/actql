export type {OriginalCancellation, CancellationObservation, CancellationPanelProps} from './cancellation-types.js';
import type {CancellationPanelProps} from './cancellation-types.js';

// The adapter keeps the original Client references and supplies explicit actions.
// This component owns no SDK, credentials, controller, permission or retry loop.
export function CancellationPanel({original,observation,history,pending,
  canPrepare,canRequest,canLookup,onPrepare,onRequest,onLookup}:CancellationPanelProps) {
  const outcome=observation?.state==='observed'?observation.outcome:null;
  const download=() => {
    if (!original) return;
    const url=URL.createObjectURL(new Blob([JSON.stringify(original,null,2)+'\n'],{type:'application/json'}));
    try {const link=document.createElement('a');link.href=url;link.download='actql-original-cancellation.json';link.click();}
    finally{URL.revokeObjectURL(url);}
  };
  return <section className="actql-cancellation" aria-label="Original Run cancellation">
    <h3>Original Run cancellation</h3>
    <p>Only explicit requests use the existing Host cancellation Owner. Current permission is checked there.
      Acceptance does not confirm physical stop, cleanup or Result release.</p>
    <button type="button" disabled={pending||!canPrepare} onClick={onPrepare}>Prepare cancellation reference</button>
    {original && <>
      <p>This original reference names its Run and observed control revision. Save it before requesting;
        after an uncertain response use lookup only. Closing this view does not resolve the operation.</p>
      <pre aria-label="Saved cancellation reference">{JSON.stringify(original,null,2)}</pre>
      <button type="button" onClick={download}>Save original cancellation reference</button>
      <button type="button" disabled={pending||!canRequest} onClick={onRequest}>Request original cancellation</button>
      <button type="button" disabled={pending||!canLookup} onClick={onLookup}>Look up original cancellation</button>
    </>}
    <p role="status">{observation?.state==='unknown'
      ? 'Cancellation outcome Unknown. Do not resend or create another attempt; look up this original reference.'
      : outcome ? `Owner invocation outcome: ${outcome.kind}. No physical-stop acknowledgement is inferred.`
        : 'No cancellation outcome observed.'}</p>
    {history && <p>{history.kind==='found'
      ? `Original Owner record: ${history.cancellation.kind}; control revision ${history.cancellation.revision}.`
      : 'Original cancellation history Unknown; absence is not permission to resend.'}</p>}
    <p>Pause, step and resume remain unavailable in this client.</p>
  </section>;
}
