import {explainOwnerObservations, formatOwnerObservations, type OwnerObservationsExplanation,
  type Execution, type OwnerCursor, type OwnerObservations} from './index.js';

declare const run: Execution;
declare const cursor: OwnerCursor;
const views: OwnerObservations=await run.observeOwners({cursors:[cursor],maxEntries:1,maxWireBytes:65536});
const consistency: 'non_atomic'=views.consistency;
const ordering: 'owner_local'=views.ordering;
void consistency;void ordering;
for(const owner of views.owners){
  if(owner.kind==='observed'){
    if(owner.history.kind==='page')owner.history.cursor?.value;
    if(owner.owner==='run' && 'snapshot' in owner)owner.snapshot.value.control?.revision;
    if(owner.owner==='effect' && 'snapshot' in owner)owner.snapshot.value.state;
  }
}
// @ts-expect-error A composite observation is not a cancellation revision.
views.control.revision;
// @ts-expect-error A cursor is not a Run reference or a read capability.
run.observeOwners({cursors:[run.ref]});

const explained: OwnerObservationsExplanation | undefined = explainOwnerObservations(views);
if (explained) {
  const observation: 'owner_views' = explained.observation;
  void observation;
  explained.requested.cursors[0]?.owner.streamCid;
  for (const view of explained.owners) {
    if (view.kind === 'observed') {
      view.history.summary;
      if ('snapshotProblem' in view) view.snapshotProblem.hint;
      if (view.history.kind === 'page') view.history.entries[0]?.entryCid;
    } else view.hint;
  }
  // @ts-expect-error Observations do not carry write retry permission.
  explained.retryAllowed;
  // @ts-expect-error The composite vector is not a Run control revision.
  explained.controlRevision;
}
const output: string | undefined = formatOwnerObservations(views, {format: 'json'});
void output;
