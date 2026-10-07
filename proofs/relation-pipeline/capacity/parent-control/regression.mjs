import assert from 'node:assert/strict';
import {auditParentStartup} from './audit.mjs';
export function rejectParentSubstitutions(report,source,read) {
  auditParentStartup(report,source,read);
  const bad = mutate => {const copy=structuredClone(report);mutate(copy);assert.throws(()=>auditParentStartup(copy,source,read));};
  bad(r=>r.target='js');bad(r=>r.target='wasm');
  bad(r=>r.unconditionalAllocationBytes=true);bad(r=>r.reuseAuthorized=true);
  bad(r=>r.buildIdentity='0'.repeat(64));bad(r=>r.boundary.sourceDigest='0'.repeat(64));
  bad(r=>r.restored=false);bad(r=>r.records[0].environments[0].requestedBytes=72);
  bad(r=>r.artifacts={});bad(r=>r.archives={});
  bad(r=>r.retainedCore.bytes='512');bad(r=>r.model.sourceDigest='0'.repeat(64));
  bad(r=>r.providerConstruction.recipe.bytes=512);bad(r=>delete r.providerConstruction);
  bad(r=>delete r.preparationStorageFacts);
  bad(r=>r.preparationStorageFacts[3].selected.backingBytes=0);
  bad(r=>r.preparationStorageFacts[2].transferredColumns='1');
  return '17 Native parent receipt substitutions rejected; no extra scientific execution';
}
