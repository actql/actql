'use strict';

// Selected Source recipe DATA, not a startup/Source issuer or an external
// allocator. The actual early startup retains the SAME control declaration
// and adopts this additional scope before any SDK snapshot/preparation.
const freeze = Object.freeze, integer = Number.isSafeInteger;
const NativeError = Error;
const MiB = 1024 * 1024;
const unavailable = () => {throw Object.assign(new NativeError('SourceManagedEnvelopeUnavailable'),
  {code:'SourceManagedEnvelopeUnavailable'});};
const inputLimits = freeze({maxProperties: 40, maxNodes: 40, maxDepth: 4,
  maxStringCodeUnits: 65536, maxTotalStringCodeUnits: 65536 + 4096,
  maxArrayItems: 0, maxOpaqueAliases: 0, maxWork: 2 * 1024 * 1024});
const limits = freeze({installations: 1, requests: 1, sourceOccurrences: 2,
  sourceBytes: 65536, sourceNodes: 4096, sourceDepth: 64,
  sourceWork: 2 * 1024 * 1024, rows: 4096, columns: 128,
  responseBytes: MiB, responses: 128, responsesPerOccurrence: 64, decodedWireBytes: MiB,
  // Explicit separate external representations: original SDK input/body and
  // transport clone, serializations, UTF8/hash preimages, response/row decode
  // workspace and captured output representations. Actual external suppliers
  // must cover these BEFORE use; this calculation supplies no Buffer/FD/TLS.
  simultaneousExternalRepresentations: 16,
  requestControlRecords: 256, perResponseControlRecords: 64});

function declareSourceManagedPhaseEnvelope(controlDeclaration) {
  if (controlDeclaration === null || typeof controlDeclaration !== 'object' ||
      !integer(controlDeclaration.heapCeilingBytes) || controlDeclaration.heapCeilingBytes <= 0 ||
      !integer(controlDeclaration.bytes) || controlDeclaration.bytes < controlDeclaration.heapCeilingBytes) unavailable();
  // One shared VM/compiled-module/native domain, NOT a second whole heap or
  // spendable initial-control credit. The complete existing control total and
  // all escaped control/native/module holdings coexist with this Source.
  const responseBackingBytes = limits.responses * limits.responseBytes;
  const externalWorkspaceBytes = limits.simultaneousExternalRepresentations * limits.decodedWireBytes;
  const externalBytes = responseBackingBytes + externalWorkspaceBytes;
  const simultaneousBytes = controlDeclaration.bytes + externalBytes;
  if (!integer(simultaneousBytes)) unavailable();
  return freeze({limits,inputLimits,controlDeclaration,
    // The README JOIN has two distinct original acquisitions. Both consume
    // partitions of this SAME request total, never two full parent allowances.
    occurrencePartitions:freeze([0,1].map(ordinal=>freeze({ordinal,
      responseStart:ordinal*limits.responsesPerOccurrence,
      responses:limits.responsesPerOccurrence,
      responseBackingBytes:limits.responsesPerOccurrence*limits.responseBytes}))),
    sharedManagedHeapBytes:controlDeclaration.heapCeilingBytes,
    additionalManagedHeapBytes:0,additionalWholeNativeDomainBytes:0,
    responseBackingBytes,externalWorkspaceBytes,externalBytes,simultaneousBytes,
    managedOverlap:freeze(['SDK original input/options and descriptor/path traversal',
      'frozen submission body, request identity and transport clone',
      'intent preimage/hash Promise and pending/context records',
      'Host original request, preparation and original Environment',
      'same pending Host request and at most sixteen original derived-pointer aliases',
      'selected Buffer allocator/operation descriptors and native distinct-backing range originals',
      'Common parse/check/compile graph, contracts and acquisition',
      'RowRun, captured row/value cursors and bounded canonical output',
      'callbacks/receivers, first/latest failures, partial cleanup and escaped aliases']),
    externalRequired:freeze(['original response ArrayBuffer allocations',
      'input/output encoding, hashing and decode workspace',
      'FD/socket/TLS and incoming transport chunks',
      'Store/Journal physical copies, commit and close uncertainty']),
    lifetime:'same-original-process-and-escaped-Source-lifetime',
    replenishedOnSourceClose:false});
}

// Separately adopted Common managed-Compute scope. These are the existing
// bounded Local provider ceilings, not extra initial-control/Source credits.
// A fixed actual installer adopts the whole disposition before SDK intake;
// this DATA function alone cannot issue an admission or a Run Ledger.
function declareSourceComputePhaseEnvelope(sourceDeclaration) {
  if (sourceDeclaration?.limits !== limits) unavailable();
  const compute = freeze({tasks:32, inputPorts:1024, rows:100, columns:100,
    valueNodes:20000, textBytes:500000, depth:100, work:20000000, frames:100,
    metadataEntries:10000, retainedEntries:10000, operationEntries:10000,
    wireBytes:1000000, retainedBytes:536870912, executionBytes:536870912});
  // Both original capture holdings remain beside all managed outputs. The
  // standard Direct capture settles its execution reservation before the next
  // serial acquisition or DAG start. Provider/extended capture is not this
  // selected recipe and cannot use this max-over-serial-execution argument.
  const originalRetained = 2000000*8 + 100000*64 + 4096;
  const sourceRetained = 4000000 + originalRetained;
  const sourceExecution = 4000000+4000000+2*1000000+1000000+
    originalRetained+4*2000000;
  const transferBytes = compute.inputPorts*compute.wireBytes+
    limits.sourceOccurrences*limits.responseBytes;
  const retainedBytes = limits.sourceOccurrences*sourceRetained+compute.retainedBytes;
  const executionBytes = compute.executionBytes;
  if (![transferBytes,retainedBytes,executionBytes].every(integer) ||
      sourceExecution > executionBytes) unavailable();
  return freeze({sourceDeclaration,compute,
    limits:freeze({planningWork:100000,attempts:compute.tasks,holdings:compute.tasks,
      transferBytes,retainedBytes,executionBytes}),
    sourceRetained,sourceExecution,
    // Shared selected heap/compiler/module/native domains are counted once in
    // sourceDeclaration.controlDeclaration, through their process/alias life.
    // Logical reservations restrict this admission; they do not add a second
    // copy of that whole domain, reserve an OS heap or release it on Run stop.
    sharedManagedHeapBytes:sourceDeclaration.sharedManagedHeapBytes,
    additionalManagedHeapBytes:0,additionalWholeNativeDomainBytes:0,
    overlap:freeze(['Source/Compute preparation, requirements, graph and generated sequences',
      'two original Source buffers, decoded/captured inputs and their retained allocations',
      'all task provider/import/export/output reservations and predecessor ports',
      'bounded values, schema/key comparison frames and callback/receiver aliases',
      'original SDK packet, intent, pending Promise, returned result and failure/cleanup aliases']),
    executionOrder:'standard-source-0-capture-then-source-1-capture-then-managed-dag',
    lifetime:'same-original-process-and-all-escaped-run-aliases',replenishedOnClose:false});
}

// The source-free purpose reuses the SAME fixed Local implementation and
// shared runtime original, not its Source buffers, child capacity or credit.
// Its actual installation must retain this selection before SDK acquisition.
function declareSourceFreeManagedComputePhaseEnvelope(controlDeclaration) {
  const joint = declareSourceComputePhaseEnvelope(
    declareSourceManagedPhaseEnvelope(controlDeclaration));
  const compute = joint.compute;
  return freeze({controlDeclaration, inputLimits, compute,
    sourceOccurrences: 0, requests: 1,
    limits: freeze({planningWork: 100000, attempts: compute.tasks, holdings: compute.tasks,
      transferBytes: compute.inputPorts * compute.wireBytes,
      retainedBytes: compute.retainedBytes, executionBytes: compute.executionBytes}),
    sharedManagedHeapBytes: controlDeclaration.heapCeilingBytes,
    additionalManagedHeapBytes: 0, additionalWholeNativeDomainBytes: 0,
    overlap: freeze(['one original SDK packet, frozen body, intent and pending request lineage',
      'checked Program/graph, generated sequences, planning and all receiving input ports',
      'same-Run Local values, keys, imports, retained outputs and result aliases',
      'current callbacks, first/latest failures and partial admission/stop custody']),
    lifetime: 'same-original-process-and-all-escaped-run-aliases',
    replenishedOnClose: false});
}

module.exports={declareSourceManagedPhaseEnvelope,declareSourceComputePhaseEnvelope,
  declareSourceFreeManagedComputePhaseEnvelope};
freeze(module.exports);
