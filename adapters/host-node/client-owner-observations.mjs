// Read-only composition of admitted Owner views. No events are synthesized,
// persisted, or ordered across Owners, and no execution hook is installed.
import {validRunRef, snapshotClientRequest} from '../../packages/client-wire/index.mjs';
import {createHash} from 'node:crypto';
import {canonicalJson as canonicalValueJson} from '../../packages/sdk/host-port.mjs';

const kinds = new Set(['run','effect','publication','delivery','site']);
const rowStates = new Set(['prepared','dispatching','applied','accepted','failed','unknown']);
const historyProblems = new Set(['retention_expired','history_unrecoverable','cursor_mismatch','cursor_expired','limit_exceeded']);
const cid = value => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);
const count = value => Number.isSafeInteger(value) && value >= 0;
const positive = value => count(value) && value > 0;
const wireBytes = value => Buffer.byteLength(JSON.stringify(value),'utf8');
const snapshotCid = (ref,owner,snapshot) => `sha256:${createHash('sha256')
  .update(canonicalValueJson({version:'actql-owner-snapshot/0.1',ref,owner,snapshot},{dataKeys:true})).digest('hex')}`;
const exact = (value, fields) => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && Object.keys(value).sort().join(',') === [...fields].sort().join(',');
const ownerKey = value => JSON.stringify([value.kind,value.scopeCid,value.streamCid]);
const ownerRef = value => exact(value,['kind','scopeCid','streamCid']) &&
  kinds.has(value.kind) && cid(value.scopeCid) && cid(value.streamCid);
const denied = () => Object.assign(new Error('RunObservationAccessDenied'), {code:'RunObservationAccessDenied'});
const limited = () => Object.assign(new Error('ClientOwnerObservationLimit'),{code:'ClientOwnerObservationLimit'});
const own = value => {
  const copy = snapshotClientRequest(value);
  const freeze = item => {
    if (item !== null && typeof item === 'object') {
      Object.values(item).forEach(freeze); Object.freeze(item);
    }
    return item;
  };
  return freeze(copy);
};

export function installClientOwnerObservations({authorizeRun, sourcesFor, codec,
  maxEntries:installedMaxEntries, maxWireBytes:installedMaxWireBytes}) {
  if (typeof authorizeRun !== 'function' || typeof sourcesFor !== 'function' ||
      codec !== undefined && (typeof codec.issue !== 'function' || typeof codec.read !== 'function') ||
      !positive(installedMaxEntries) || installedMaxEntries > 1000 ||
      !positive(installedMaxWireBytes) || installedMaxWireBytes < 1024 || installedMaxWireBytes > 65536) {
    throw new TypeError('InvalidClientOwnerObservationInstallation');
  }
  return async request => {
    if (!validRunRef(request?.ref) || request.cursors !== undefined &&
        (!Array.isArray(request.cursors) || request.cursors.length > 5 ||
          request.cursors.some(cursor => !exact(cursor,['owner','value']) ||
            !ownerRef(cursor.owner) || typeof cursor.value !== 'string' || cursor.value.length > 8192))) {
      throw new TypeError('InvalidClientOwnerObservationRequest');
    }
    const {signal,...data}=request;
    const selected = Object.freeze({...own(data),...(signal === undefined ? {} : {signal})});
    const maxEntries=Math.min(installedMaxEntries,selected.maxEntries ?? installedMaxEntries);
    const maxWireBytes=Math.min(installedMaxWireBytes,selected.maxWireBytes ?? installedMaxWireBytes);
    if (!positive(maxEntries) || !positive(maxWireBytes) || maxWireBytes < 1024) {
      throw new TypeError('InvalidClientOwnerObservationRequest');
    }
    if (await authorizeRun(selected) !== true) throw denied();
    const supplied = await sourcesFor(selected);
    // Installation hooks and identities are one admission snapshot. Their
    // authorization functions still consult live authority on every call.
    const sources = Array.isArray(supplied) ? supplied.map(source =>
      Object.freeze({...source,...(source.kind === 'problem' ? {} : {owner:own(source.owner)})})) : supplied;
    if (!Array.isArray(sources) || sources.length > 5 || sources.some(source =>
      source.kind === 'problem' ? !kinds.has(source.ownerKind) || typeof source.authorize !== 'function' ||
        !['acquisition_failed','limit_exceeded','history_unrecoverable','cursor_mismatch'].includes(source.problem) :
      !ownerRef(source.owner) || typeof source.authorize !== 'function' ||
      typeof source.readSnapshot !== 'function' || !['formal','not_provided'].includes(source.history) ||
      source.history === 'formal' && (typeof source.readPage !== 'function' || codec === undefined)) ||
      new Set(sources.filter(source=>source.kind !== 'problem').map(source => ownerKey(source.owner))).size !==
        sources.filter(source=>source.kind !== 'problem').length) {
      throw new TypeError('InvalidClientOwnerObservationSources');
    }
    if (await authorizeRun(selected) !== true) throw denied();
    const owners = [], revisionVector = [];
    // An unmatched caller-supplied scope is not proof of history absence.
    // Only identify the request position; omit private Owner identities and
    // use the same unavailable result for absent and undisclosable scopes.
    // Reserve the largest unavailable-request list up front. Only currently
    // disclosed Owner bindings may remove positions from it after the reads.
    const unmatchedCursors=(selected.cursors ?? []).map((cursor,index)=>({index,kind:'unavailable'}));
    const envelope = {ref:selected.ref,consistency:'non_atomic',ordering:'owner_local',owners,revisionVector,
      ...(unmatchedCursors.length ? {unmatchedCursors} : {})};
    // Reserve finite acquisition independently of private stream count: at
    // most five reads, each bounded by this request's wire limit. Composite
    // projection is budgeted again after the current disclosure checks.
    const acquisitionBytes=maxWireBytes-wireBytes(envelope)-2*5;
    if(acquisitionBytes < 256)throw limited();
    const collected=[];
    const unavailable=kind=>{
      // Denied streams expose neither their identities nor their count.
      if(!owners.some(view=>view.owner===kind && view.kind==='unavailable' && view.problem===undefined)){
        owners.push({owner:kind,kind:'unavailable'});
      }
    };
    for (const source of sources) {
      const permitted = async () => await authorizeRun(selected) === true &&
        await source.authorize(selected) === true;
      if (source.kind === 'problem') {
        if(await permitted()){
          const view={owner:source.ownerKind,kind:'unavailable',problem:{kind:source.problem}};
          owners.push(view);collected.push({source,view});
        }
        else unavailable(source.ownerKind);
        continue;
      }
      const owner = own(source.owner);
      if (!await permitted()) {unavailable(owner.kind); continue;}
      let snapshot, snapshotProblem;
      try {
        const value = await source.readSnapshot({...selected,maxWireBytes:acquisitionBytes});
        if (!(exact(value,['value']) || exact(value,['revision','value']) && count(value.revision))) {
          throw new Error('InvalidOwnerSnapshot');
        }
        if (wireBytes(value) > acquisitionBytes) snapshotProblem = {kind:'limit_exceeded'};
        else snapshot = own(value);
      } catch {snapshotProblem = {kind:'acquisition_failed'};}
      if (!await permitted()) {unavailable(owner.kind); continue;}
      const matching = (selected.cursors ?? []).filter(cursor => ownerKey(cursor.owner) === ownerKey(owner));
      let history = {kind:matching.length && source.history === 'not_provided'
        ? 'cursor_mismatch' : 'not_provided'};
      let historyHead;
      if (source.history === 'formal') {
        let after = null;
        if (matching.length > 1) history = {kind:'cursor_mismatch'};
        else if (matching.length === 1) {
          const decoded = codec.read(matching[0].value, {ref:selected.ref,owner});
          if (decoded.kind !== 'matched') history = {kind:decoded.kind === 'cursor_expired' ? 'cursor_expired' : 'cursor_mismatch'};
          else after = decoded.position;
        }
        if (!['cursor_mismatch','cursor_expired'].includes(history.kind)) {
          try {
            const page = await source.readPage({...selected,after,maxEntries,maxWireBytes:acquisitionBytes});
            if (historyProblems.has(page?.kind)) history = {kind:page.kind};
            else if (wireBytes(page) > acquisitionBytes) history = {kind:'limit_exceeded'};
            else {
              if (page?.kind !== 'page' || !Array.isArray(page.entries) ||
                  page.entries.length > maxEntries ||
                  page.head !== null && (!cid(page.generation) || !positive(page.head?.revision) ||
                    !cid(page.head.entryCid) || !exact(page.head,['revision','entryCid'])) ||
                  page.head === null && (page.generation !== null || page.entries.length || after !== null)) {
                throw new Error('InvalidOwnerHistoryPage');
              }
              if (after !== null && (page.generation !== after.generation ||
                  page.previous?.revision !== after.revision || page.previous.entryCid !== after.entryCid)) {
                throw new Error('InvalidOwnerHistoryAnchor');
              }
              const entries = page.entries.map((row,index) => {
                if (row.revision !== (after?.revision ?? 0)+index+1 || !cid(row.entryCid) ||
                    row.revision > page.head.revision || row.revision === page.head.revision &&
                    row.entryCid !== page.head.entryCid || row.revision === 1 &&
                    row.entryCid !== page.generation) throw new Error('InvalidOwnerHistoryPosition');
                const entry = JSON.parse(row.entryJson);
                if (!rowStates.has(entry.state)) throw new Error('InvalidOwnerHistoryProjection');
                return {revision:row.revision,entryCid:row.entryCid,state:entry.state};
              });
              const last = page.entries.at(-1);
              if (page.head !== null && last === undefined &&
                  page.head.revision !== after?.revision) throw new Error('InvalidOwnerHistoryPrefix');
              const position = last === undefined ? after : {generation:page.generation,
                revision:last.revision,entryCid:last.entryCid};
              history = {kind:'page',entries,...(position === null ? {} :
                {cursor:{owner,value:codec.issue({ref:selected.ref,owner,position})}})};
              historyHead = page.head === null ? null : {generation:page.generation,...page.head};
            }
          } catch {history = {kind:'acquisition_failed'};}
        }
      }
      // Authorization may have changed during either asynchronous Owner read.
      // Discard all buffered details instead of revealing a protected gap.
      if (!await permitted()) {unavailable(owner.kind); continue;}
      const view = {owner:owner.kind,ownerRef:owner,kind:'observed',...(snapshot === undefined
        ? {snapshotProblem} : {snapshot}),history};
      // A current-only view has no semantic replay revision. Bind its exact
      // content separately; Run control.revision remains inside its own fact
      // and is the only revision used by the cancellation operation.
      const vector = {owner,...(snapshot === undefined ? {} : {snapshotCid:snapshotCid(selected.ref,owner,snapshot)}),
        ...(historyHead === undefined ? {} : {historyHead})};
      owners.push(view); revisionVector.push(vector);
      collected.push({source,view,vector});
    }
    if (await authorizeRun(selected) !== true) throw denied();
    // Later Owner awaits can revoke an earlier projection. Recheck each
    // buffered component before deciding the disclosed response budget.
    for(const {source,view,vector} of collected){
      if(await authorizeRun(selected) !== true)throw denied();
      if(await source.authorize(selected) !== true){
        owners.splice(owners.indexOf(view),1);
        if(vector !== undefined)revisionVector.splice(revisionVector.indexOf(vector),1);
        unavailable(view.owner);
      }
    }
    const disclosedKeys=new Set(owners.filter(view=>view.kind==='observed').map(view=>ownerKey(view.ownerRef)));
    const undisclosed=(selected.cursors ?? []).flatMap((cursor,index)=>
      disclosedKeys.has(ownerKey(cursor.owner)) ? [] : [{index,kind:'unavailable'}]);
    if(undisclosed.length)envelope.unmatchedCursors=undisclosed;
    else delete envelope.unmatchedCursors;
    // Only disclosable components and generic unavailable kinds enter this
    // division. A hidden stream cannot evict another Owner's snapshot/page.
    const baseBytes=wireBytes({...envelope,owners:[],revisionVector:[]});
    const slotBytes=Math.floor((maxWireBytes-baseBytes-2*owners.length)/Math.max(1,owners.length));
    for(const {view,vector} of collected){
      if(!owners.includes(view) || view.kind !== 'observed')continue;
      if(wireBytes(view)+wireBytes(vector)>slotBytes && view.history.kind==='page'){
        view.history={kind:'limit_exceeded'};delete vector.historyHead;
      }
      if(wireBytes(view)+wireBytes(vector)>slotBytes && view.snapshot !== undefined){
        delete view.snapshot;view.snapshotProblem={kind:'limit_exceeded'};delete vector.snapshotCid;
      }
      if(wireBytes(view)+wireBytes(vector)>slotBytes)throw limited();
    }
    if(await authorizeRun(selected) !== true)throw denied();
    if (wireBytes(envelope) > maxWireBytes) throw limited();
    return own(envelope);
  };
}
