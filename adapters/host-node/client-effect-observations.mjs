// Reads only the existing admitted Ledger. No provider, apply, recovery or
// publication hook is supplied; failed physical closes keep their exact owner.
import {existsSync} from 'node:fs';
import {join} from 'node:path';
import {openEffectLedger} from './effect-ledger.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';

export function installClientEffectObservations({moon,root,authorize,maxPending=4}) {
  if (typeof authorize !== 'function' || !Number.isSafeInteger(maxPending) || maxPending < 1 || maxPending > 4) {
    throw new TypeError('InvalidClientEffectObservations');
  }
  const pending=new Set(),control=runtimeCore(moon).effectApplicationControl;
  const withLedger=(identity,read)=>{
    if (pending.size >= maxPending) throw new Error('EffectObservationCleanupPending');
    let ledger;
    try {
      ledger=openEffectLedger({moon,root,authorityScopeCid:moon.clientRequestAuthorityScopeCid(identity),
        callerRequestId:moon.clientRequestCallerId(identity)});
      return read(ledger);
    } catch (failure) {
      if (ledger === undefined && failure.cleanupPending === true &&
          typeof failure.cleanupHandle?.retry === 'function' && typeof failure.cleanupHandle?.status === 'function') {
        pending.add({close:async()=>{await failure.cleanupHandle.retry();
          if(failure.cleanupHandle.status().pending !== false)throw failure;}});
      }
      throw failure;
    } finally {
      if (ledger !== undefined) {
        try {ledger.close();}
        catch (failure) {pending.add(ledger);throw failure;}
      }
    }
  };
  return Object.freeze({
    sources(identity,request) {
      const problem=kind=>({kind:'problem',ownerKind:'effect',problem:kind,authorize});
      if (!existsSync(join(root,'effect-ledger.sqlite3'))) {
        // A caller's unadmitted token cannot certify that this stream ever
        // existed or that history was lost. The collector reports its request
        // position as unavailable, without inventing a retention/absence fact.
        return [];
      }
      const scope=control.logicalRequestScope(moon.clientRequestAuthorityScopeCid(identity),
        moon.clientRequestCallerId(identity),256);
      const scopeCid=control.logicalRequestScopeCid(scope);
      let page;
      try {page=withLedger(identity,ledger=>ledger.currentScopePage({maxItems:3,maxWireBytes:request.maxWireBytes}));}
      catch {return [problem('acquisition_failed')];}
      if (page.kind !== 'page') return [problem(page.kind)];
      const result=page.entries.map(row=>{
        const streamCid=row.logicalItemLocatorCid;
        return {owner:{kind:'effect',scopeCid,streamCid},history:'formal',authorize,
          readSnapshot:()=>withLedger(identity,ledger=>{
            const current=ledger.current(streamCid);
            if (current === undefined)throw new Error('EffectObservationHistoryUnrecoverable');
            return {revision:current.revision,value:{state:JSON.parse(current.entryJson).state}};
          }),
          readPage:options=>withLedger(identity,ledger=>ledger.historyPage(streamCid,options))};
      });
      if (page.hasMore)result.push(problem('limit_exceeded'));
      return result;
    },
    async close() {
      let failure;
      for (const owner of pending) {
        try {await owner.close();pending.delete(owner);}
        catch (error) {failure ??= error;}
      }
      if (failure !== undefined)throw failure;
    },
  });
}
