import type {RunObservationModel} from './run-observation.js';

const fact = (value: boolean | undefined) => value === undefined ? 'Unavailable' : String(value);

// This component owns presentation only. Its adapter supplies already current,
// scope-checked observations; no Client, credentials or mutation hooks enter it.
export function RunInspector({model}: {model: RunObservationModel}) {
  const run = model.run;
  return <section className="actql-run-inspector" aria-label="Current Run observations">
    <header><p>OWNER OBSERVATIONS · READ-ONLY</p><h2>Current Run</h2>
      <p>Independent reads: {model.consistency}; scope: {model.observationScope}.
        Owner revisions are not one global transaction or logical-step progress.</p></header>
    <dl><dt>Run</dt><dd>{run.id}</dd><dt>State</dt><dd>{run.status}</dd>
      <dt>Control revision</dt><dd>{run.controlRevision}</dd>
      <dt>Observed Run update</dt><dd>{run.updatedAt}</dd>
      <dt>Original namespace</dt><dd>{model.runRef.namespaceId}</dd>
      <dt>Original authority scope</dt><dd>{model.runRef.authorityScopeCid}</dd>
      <dt>Original Run definition</dt><dd>{model.runRef.runDefinitionCid}</dd>
      <dt>Observed Compiled Plan binding</dt><dd>{model.planBinding.compiledPlanCid ?? 'Unavailable'}</dd>
      <dt>Observed Logical Map binding</dt><dd>{model.planBinding.logicalMapCid ?? 'Unavailable'}</dd>
      <dt>Stop reason</dt><dd>{run.stopReason ?? 'Unavailable'}</dd>
      <dt>Cleanup pending</dt><dd>{fact(run.cleanupPending)}</dd>
      <dt>Pause pending</dt><dd>{fact(run.pausePending)}</dd>
      <dt>Expiry pending</dt><dd>{fact(run.expiryPending)}</dd>
      <dt>Cancellation requested</dt><dd>{run.cancellation.state === 'observed'
        ? fact(run.cancellation.requested) : 'Unavailable'}</dd>
      <dt>Physical stop</dt><dd>{run.cancellation.state === 'observed'
        ? run.cancellation.physicalStop : 'Unavailable'}</dd></dl>
    {run.boundary && <aside aria-label="Observed Run boundary"><h3>Observed boundary</h3>
      <p>{run.boundary.kind} · {run.boundary.position} · {run.boundary.step_id ?? 'No step ID observed'}</p>
      <p>This is the Owner’s boundary fact, not a progress overlay on a separately read Plan.</p></aside>}
    <h3>Current components</h3>
    {model.components.length === 0 ? <p>No component observations provided.</p> :
      <table aria-label="Owner component observations"><thead><tr>
        <th>Owner</th><th>State</th><th>Revision</th><th>Provenance</th></tr></thead>
        <tbody>{model.components.map((item, index) => <tr key={index}>
          <td>{item.owner}</td><td>{item.state}</td><td>{item.revision ?? 'Unavailable'}</td>
          <td>{item.provenance_cid ?? 'Unavailable'}</td></tr>)}</tbody></table>}
    <h3>Observed quantities</h3>
    {model.quantities.length === 0 ? <p>No quantities provided; this does not mean zero.</p> :
      <table aria-label="Observed quantities"><thead><tr><th>Evidence</th><th>Value</th>
        <th>Unit</th><th>Original scope and basis</th></tr></thead><tbody>
        {model.quantities.map((item, index) => <tr key={index}>
          <td>{item.kind}</td><td>{item.kind === 'unknown' ? 'Unknown' : item.value}</td>
          <td>{item.unit}</td><td>{item.kind === 'unknown' ? item.reason
            : <>{item.scopeCid}<br/>{item.basisCid}</>}</td></tr>)}
      </tbody></table>}
    <p>Logical-step progress, INFER counts, elapsed time, tokens, cost and sealed Preview:
      unavailable in this projection. Update timestamps are not elapsed measurements.
      Sample: {model.sample.state}{model.sample.reason ? ` (${model.sample.reason})` : ''}; payload not opened here.</p>
    <h3>Result availability</h3>
    {model.resultAvailability.state === 'unavailable' ? <p>Unavailable: not observed.</p> :
      model.resultAvailability.entries.length === 0 ? <p>No per-Result observations provided.</p> :
      <table aria-label="Independent Result availability"><thead><tr><th>Result</th>
        <th>State</th><th>Reason</th><th>Observed at</th></tr></thead><tbody>
        {model.resultAvailability.entries.map(item => <tr key={item.name}>
          <td>{item.name}</td><td>{item.state}</td><td>{item.reason}</td><td>{item.observedAt}</td>
        </tr>)}</tbody></table>}
    <h3>Owner-local history</h3>
    <p>One bounded page per Owner, in its original returned order. No cross-Owner timeline,
      fabricated timestamps or complete-history claim.</p>
    {model.histories.state === 'unavailable' ? <p>Unavailable: {model.histories.reason}.</p> :
      model.histories.owners.map((owner, index) => <article key={index} aria-label={`${owner.owner} Owner history`}>
        <h4>{owner.owner}</h4>{owner.state === 'unavailable' ? <p>Unavailable: {owner.reason}.</p> : <>
          <p>Scope: {owner.ownerRef.scopeCid}<br/>Stream: {owner.ownerRef.streamCid}</p>
          <p>Snapshot: {owner.snapshot.state === 'unavailable' ? `Unavailable (${owner.snapshot.reason})`
            : <>{owner.snapshot.cid} · revision {owner.snapshot.revision ?? 'not provided'}</>}</p>
          {owner.history.state === 'unavailable' ? <p>History unavailable: {owner.history.reason}.</p> : <>
            <p>Head: {owner.history.head === null ? 'No entries observed'
              : <>revision {owner.history.head.revision} · {owner.history.head.entryCid}</>}
              {owner.history.cursorAvailable ? ' · Original cursor present (no further page fetched)' : ''}</p>
            <ol>{owner.history.entries.map(entry => <li key={entry.revision}>
              Revision {entry.revision} · {entry.state} · {entry.entryCid}</li>)}</ol>
          </>}
        </>}</article>)}
  </section>;
}
