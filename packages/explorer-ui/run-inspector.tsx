import {explorerCopy, type ExplorerLocale} from './i18n.mjs';
import type {RunObservationModel} from './run-observation.js';

// This component owns presentation only. Its adapter supplies already current,
// scope-checked observations; no Client, credentials or mutation hooks enter it.
export function RunInspector({model, locale}: {model: RunObservationModel; locale?: ExplorerLocale}) {
  const words = explorerCopy(locale);
  const fact = (value: boolean | undefined) => value === undefined ? words.unavailable : String(value);
  const run = model.run;
  return <section className="actql-run-inspector" aria-label={words.currentRunObservations}>
    <header><p>{words.ownerObservations}</p><h2>{words.currentRun}</h2>
      <p>{words.independentReads(model.consistency, model.observationScope)} {words.separateReadsNote}</p></header>
    <dl><dt>{words.run}</dt><dd>{run.id}</dd><dt>{words.state}</dt><dd>{run.status}</dd>
      <dt>{words.runControlRevision}</dt><dd>{run.controlRevision}</dd>
      <dt>{words.observedRunUpdate}</dt><dd>{run.updatedAt}</dd>
      <dt>{words.originalNamespace}</dt><dd>{model.runRef.namespaceId}</dd>
      <dt>{words.originalAuthority}</dt><dd>{model.runRef.authorityScopeCid}</dd>
      <dt>{words.originalDefinition}</dt><dd>{model.runRef.runDefinitionCid}</dd>
      <dt>{words.observedCompiledPlan}</dt><dd>{model.planBinding.compiledPlanCid ?? words.unavailable}</dd>
      <dt>{words.observedLogicalMap}</dt><dd>{model.planBinding.logicalMapCid ?? words.unavailable}</dd>
      <dt>{words.stopReason}</dt><dd>{run.stopReason ?? words.unavailable}</dd>
      <dt>{words.cleanupPending}</dt><dd>{fact(run.cleanupPending)}</dd>
      <dt>{words.pausePending}</dt><dd>{fact(run.pausePending)}</dd>
      <dt>{words.expiryPending}</dt><dd>{fact(run.expiryPending)}</dd>
      <dt>{words.cancellationRequested}</dt><dd>{run.cancellation.state === 'observed'
        ? fact(run.cancellation.requested) : words.unavailable}</dd>
      <dt>{words.physicalStop}</dt><dd>{run.cancellation.state === 'observed'
        ? run.cancellation.physicalStop : words.unavailable}</dd></dl>
    {run.boundary && <aside aria-label={words.runBoundary}><h3>{words.observedBoundary}</h3>
      <p>{run.boundary.kind} · {run.boundary.position} · {run.boundary.step_id ?? words.noStepId}</p>
      <p>{words.boundaryNote}</p></aside>}
    <h3>{words.components}</h3>
    {model.components.length === 0 ? <p>{words.noComponents}</p> :
      <table aria-label={words.ownerComponents}><thead><tr>
        <th>{words.owner}</th><th>{words.state}</th><th>{words.revision}</th><th>{words.provenance}</th></tr></thead>
        <tbody>{model.components.map((item, index) => <tr key={index}>
          <td>{item.owner}</td><td>{item.state}</td><td>{item.revision ?? words.unavailable}</td>
          <td>{item.provenance_cid ?? words.unavailable}</td></tr>)}</tbody></table>}
    <h3>{words.observedQuantities}</h3>
    {model.quantities.length === 0 ? <p>{words.noQuantities}</p> :
      <table aria-label={words.observedQuantities}><thead><tr><th>{words.evidence}</th><th>{words.value}</th>
        <th>{words.unit}</th><th>{words.originalBasis}</th></tr></thead><tbody>
        {model.quantities.map((item, index) => <tr key={index}>
          <td>{item.kind}</td><td>{item.kind === 'unknown' ? words.stepState.Unknown : item.value}</td>
          <td>{item.unit}</td><td>{item.kind === 'unknown' ? item.reason
            : <>{item.scopeCid}<br/>{item.basisCid}</>}</td></tr>)}
      </tbody></table>}
    <p>{words.inspectionQuantitiesLimit} {words.sampleStatePrefix} {model.sample.state}{model.sample.reason ? ` (${model.sample.reason})` : ''}{words.samplePayloadNotRead}</p>
    <h3>{words.resultAvailability}</h3>
    {model.resultAvailability.state === 'unavailable' ? <p>{words.notObserved}</p> :
      model.resultAvailability.entries.length === 0 ? <p>{words.noResultObservations}</p> :
      <table aria-label={words.independentResultAvailability}><thead><tr><th>{words.result}</th>
        <th>{words.state}</th><th>{words.reason}</th><th>{words.observedAtHeader}</th></tr></thead><tbody>
        {model.resultAvailability.entries.map(item => <tr key={item.name}>
          <td>{item.name}</td><td>{item.state}</td><td>{item.reason}</td><td>{item.observedAt}</td>
        </tr>)}</tbody></table>}
    <h3>{words.ownerHistory}</h3>
    <p>{words.partialOwnerHistory}</p>
    {model.histories.state === 'unavailable' ? <p>{words.unavailable}: {model.histories.reason}.</p> :
      model.histories.owners.map((owner, index) => <article key={index} aria-label={words.ownerHistoryName(owner.owner)}>
        <h4>{owner.owner}</h4>{owner.state === 'unavailable' ? <p>{words.unavailable}: {owner.reason}.</p> : <>
          <p>{words.scopeLabel} {owner.ownerRef.scopeCid}<br/>{words.streamLabel} {owner.ownerRef.streamCid}</p>
          <p>{words.snapshotLabel} {owner.snapshot.state === 'unavailable' ? words.unavailable + " (" + owner.snapshot.reason + ")"
            : <>{owner.snapshot.cid} · {words.revisionInline} {owner.snapshot.revision ?? words.notProvided}</>}</p>
          {owner.history.state === 'unavailable' ? <p>{words.historyUnavailable} {owner.history.reason}.</p> : <>
            <p>{words.headLabel} {owner.history.head === null ? words.noEntries
              : <>{words.revisionInline} {owner.history.head.revision} · {owner.history.head.entryCid}</>}
              {owner.history.cursorAvailable ? words.cursorPresent : ''}</p>
            <ol>{owner.history.entries.map(entry => <li key={entry.revision}>
              {words.revision} {entry.revision} · {entry.state} · {entry.entryCid}</li>)}</ol>
          </>}
        </>}</article>)}
  </section>;
}
