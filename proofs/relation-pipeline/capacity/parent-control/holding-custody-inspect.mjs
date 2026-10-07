import assert from 'node:assert/strict';
export const custodyPhases = ['acquired', 'parent-port-closed', 'consumer-completed', 'owner-cleaned', 'last-consumer-closed', 'duplicate-parent-close'];
const flags = ['ownerMatches','available','resourcePresent','sameToken','slotMatches','portLive','runningConsumer','outputAvailable'];
const naturals = ['task','serial','reservationSerial','bytes','pins','children','schedulerGeneration','heldBytes'];
export function inspectHoldingCustody(log) {
  const cases = [];
  let current;
  for (const line of log.split('\n')) {
    if (line.startsWith('ACTQL_DRIVER_CASE:')) {
      assert(!current,'Overlapping holding cases');
      current={variant:line.slice(18),records:[]};
      assert.equal(current.variant,['current_filter','current_edge_filter'][cases.length]);
    } else if (line.startsWith('ACTQL_HOLDING_CUSTODY:')) {
      assert(current,'Holding outside actual Host case');
      const r=JSON.parse(line.slice('ACTQL_HOLDING_CUSTODY:'.length));
      assert.equal(r.phase,custodyPhases[current.records.length],'Missing/reordered holding boundary');
      for (const f of flags) assert.equal(typeof r[f],'boolean','Missing actual flag '+f);
      for (const f of naturals) assert(Number.isSafeInteger(r[f]) && r[f]>=0,'Invalid holding observation '+f);
      assert(Number.isSafeInteger(r.outputBytes) && r.outputBytes>=-1);
      assert.equal(r.task,4);
      current.records.push(r);
    } else if (line.startsWith('ACTQL_DRIVER_CASE_DONE:')) {
      assert(current && current.variant===line.slice(23),'Missing holding case completion');
      cases.push(current); current=undefined;
    }
  }
  assert(!current && cases.length===2,'Missing completed holding cases');
  return {scope:'two Native Host MATCH outputs at task 4; exact committed token through dependent consumer retirement',
    physicalGCDestruction:false,wholePhysicalLifetimeUpper:false,
    cases:cases.map(c=>{
      assert.equal(c.records.length,custodyPhases.length,'Missing holding observations');
      const [acquired,closed,completed,cleaned,released,repeated]=c.records;
      assert(acquired.bytes>0 && acquired.outputBytes===acquired.bytes,'Output allocation bytes do not correspond');
      assert(acquired.slotMatches && acquired.portLive,'Missing exact completion attachment');
      for (const r of c.records) {
        for (const f of ['serial','reservationSerial','bytes']) assert.equal(r[f],acquired[f],'Replaced original holding '+f);
        assert(r.ownerMatches,'Foreign Ledger holding');
        assert.equal(r.pins,0,'Different retention path from unpinned child dependency');
      }
      for (const r of [acquired,closed,completed,cleaned]) {
        assert(r.available && r.resourcePresent && r.sameToken,'Early release or substitution of acquired holding');
      }
      for (const r of [acquired,closed,completed]) {
        assert(r.outputAvailable,'Acquired input unavailable before consumer commit');
        assert.equal(r.outputBytes,acquired.bytes,'Changed retained output storage');
      }
      // The Host fixture closes its read predicate before the last child closes.
      // Loss of read permission cannot retire the still-dependent allocation.
      assert(!cleaned.outputAvailable && cleaned.outputBytes===-1,'Missing closed Host read predicate');
      for (const r of [closed,completed,cleaned,released,repeated]) assert(!r.portLive && !r.slotMatches,'Revoked public slot reopened');
      assert(closed.runningConsumer,'Missing actual in-flight consumer dependency');
      assert(completed.children>0 && cleaned.children>0,'Missing retained completed child dependency');
      assert(!completed.runningConsumer && !cleaned.runningConsumer,'Consumer completion not observed');
      assert.equal(closed.heldBytes,acquired.heldBytes,'Producer close returned holding early');
      assert.equal(cleaned.heldBytes,completed.heldBytes,'Provider cleanup returned dependent allocation');
      // This is scheduling progress, not an allocation generation identifier.
      assert(completed.schedulerGeneration>closed.schedulerGeneration,'Missing real consumer commit');
      for (const r of [released,repeated]) {
        assert(!r.available && !r.resourcePresent && !r.sameToken && !r.outputAvailable,'Last consumer did not retire original allocation');
        assert.equal(r.children,0); assert(!r.runningConsumer);
      }
      assert(cleaned.heldBytes-released.heldBytes>=acquired.bytes,'Missing original holding credit');
      assert.equal(repeated.heldBytes,released.heldBytes,'Duplicate parent close returned credit again');
      return {variant:c.variant,holdingSerial:acquired.serial,reservationSerial:acquired.reservationSerial,
        outputBytes:acquired.bytes,phases:custodyPhases.length,releasedOnce:true};
    })};
}
