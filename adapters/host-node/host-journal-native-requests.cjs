'use strict';

// Request/lifetime arithmetic for the selected private Host/Journal recipe.
// This is deliberately NOT a physical facility, installation admission,
// hard quota or guarantee that an allocation succeeds. The actual prefix
// must bind all native/platform/managed originals and the complete phase
// before use. These partial request vectors cannot populate a disposition.
const {isProxy} = require('node:util').types;
const descriptor = Object.getOwnPropertyDescriptor, own = Object.hasOwn;
const freeze = Object.freeze, NativeError = Error;
const maximum = 9223372036854775807n;
const names = freeze(['databaseBytes', 'pageBytes', 'walFrames', 'preparedStatements',
  'sqlCalls', 'sqlBytes', 'statementCalls', 'resultRows', 'parameterBytes']);
const unavailable = () => {
  const cause = new NativeError('HostJournalEnvelopeUnavailable');
  cause.code = 'HostJournalEnvelopeUnavailable';
  throw cause;
};
const checked = value => {
  if (value < 0n || value > maximum) unavailable();
  return value;
};
const ceil = (value, divisor) => value / divisor + (value % divisor === 0n ? 0n : 1n);
const rounded = (value, quantum) => ceil(value, quantum) * quantum;
const greater = (a, b) => a > b ? a : b;

function hostJournalNativeUsableUpper(request) {
  if (typeof request !== 'bigint' || request < 1n || request > maximum) unavailable();
  // Conditional ordinary arm64 libmalloc792.60.6 xzone/nano/scalable family.
  // Not a live zone observation, region/metadata reservation or selection of
  // custom/debug/guard/interposed allocators. The actual prefix still owns
  // source/runtime/library correspondence and all shared lifetime coverage.
  if (request <= 32768n) {
    let xzone;
    if (request <= 128n) xzone = rounded(request, 16n);
    else {
      let base = 128n;
      while (2n * base < request) base *= 2n;
      xzone = rounded(request, base / 4n);
    }
    const scalable = rounded(request, request <= 1008n ? 16n : 512n);
    return greater(xzone, scalable);
  }
  // Scalable large-cache best fit may retain an entry STRICTLY smaller
  // than twice the rounded request. This is not arbitrary spare capacity.
  return checked(greater(rounded(request, 32768n),
    2n * rounded(request, 16384n) - 1n));
}

const allocation = request => freeze({request,
  heapUsableUpper:hostJournalNativeUsableUpper(request)});
const preservingGrowth = (previousPeak, next) => freeze({
  previousMaximum:allocation(previousPeak), nextMaximum:allocation(next),
  retainedOriginalUpper:greater(hostJournalNativeUsableUpper(previousPeak),
    hostJournalNativeUsableUpper(next)),
  immediateCredit:false,
});

function bitvecTree(size) {
  // LP64 source layout: 512-byte node,496 usable bytes,62 child pointers,
  //3968 bitmap bits. Last child has the SAME divisor size, not a shorter
  // caller-invented allocation. Full population is a conservative upper.
  if (size <= 3968n) return freeze({nodes:1n, depth:1n});
  const divided = ceil(size, 62n);
  const divisor = divided < 3968n ? 3968n : divided;
  const child = bitvecTree(divisor);
  return freeze({nodes:checked(1n + ceil(size, divisor) * child.nodes),
    depth:1n + child.depth});
}

function hostJournalNativeStructureRequests(input) {
  // Only fixed already-covered recipe DATA is projected here. This neither
  // enumerates/adopts a raw public packet nor changes its unknown-field or
  // consent semantics. Opaque aliases and callback backing remain elsewhere.
  if (input === null || typeof input !== 'object' || isProxy(input)) unavailable();
  const selected = {};
  for (const name of names) {
    const property = descriptor(input, name);
    if (property === undefined || !own(property, 'value') ||
        typeof property.value !== 'bigint') unavailable();
    selected[name] = checked(property.value);
  }
  const {databaseBytes:D, pageBytes:p, walFrames:F, preparedStatements:P,
    sqlCalls:C, sqlBytes:T, statementCalls:X, resultRows:L, parameterBytes:B} = selected;
  if (p < 512n || p > 65536n || (p & (p - 1n)) !== 0n || D < p ||
      P < 1n || C < 1n || T < 1n || X < 1n || L < 1n || B < 1n) unavailable();
  const N = D / p;
  if (N > 4294967294n || F + 33n > 4294967295n) unavailable();

  // Failed acquisition is cached BEFORE Pager's max-page error and Drop.
  // Hash growth also precedes insertion. N alone misses the power-of-two
  // boundary and the original temporary page on that failure path.
  let H = 256n;
  while (H < N + 1n) H *= 2n;
  const R = 1n + ceil(F > 4062n ? F - 4062n : 0n, 4096n);
  // Conditional selected Darwin ARM page ABI has4096..16384 pages, hence
  // original Unix VFS q=1. This source condition still needs actual runtime/
  // native ABI correspondence; neither a label nor this function proves it.
  if (R > 65535n || 32768n * R > 2147483647n) unavailable();
  const tree = bitvecTree(N);
  const S = checked(P + 2n);
  const callerSteps = checked(C + T + checked(X * (L + 1n)));
  const retriedSteps = checked(51n * callerSteps);
  const recordSlots = checked(N * retriedSteps);
  const subjournalBytes = checked((p + 4n) * recordSlots);
  const chunks = ceil(subjournalBytes, 1016n);
  // Closed own-DDL/current SQL source templates, not observed final EXPLAIN
  // maxima:70 data registers,6 cursor slots,14 aVar slots; H includes attempted
  // emission. Componentwise maxima conservatively give5088 MakeReady bytes.
  // A transferred trigger child keeps Op/P4/SubProgram, not a second full VM.
  const mainH = 12896n, childH = 3104n, childPrograms = 2n;
  const mainOpRequest = 48n * (mainH - 1n);
  const childOpRequest = 48n * (childH - 1n);
  const vmArrays = 56n * (70n + 6n) + 56n * 14n + 8n * 6n;
  const p4Slots = mainH + childPrograms * childH;
  // Each opcode owns at most ONE P4 kind. The largest selected kind is one
  // bounded generated text allocation; do not add every kind to each opcode.
  const metadataTextRequest = 3377n;
  const p4UsableEach = hostJournalNativeUsableUpper(metadataTextRequest);
  const boundStatements = P < X ? P : X;
  const retainedBindRequests = checked(2n * B + 32n * 14n);
  const activeBindRequests = checked(3n * B + 34n * 14n);
  // U(r)<=2r+32768 for each selected stock allocation. Apply the resulting
  // SUM inequality to at most14 distinct payload blocks, never U(sum r).
  const retainedBindUsable = checked(2n * retainedBindRequests + 32768n * 14n);
  const bindBeforeActive = checked((boundStatements - 1n) * retainedBindRequests);
  const generatedPayload = checked(D + B + 19644n);
  const translatedPayload = checked(2n * generatedPayload + 2n);

  return freeze({
    qualification:'partial-native-request-vectors', completePhase:false,
    replenishedOnClose:false,
    cache:freeze({admittedPages:N, peakKeys:N + 1n,
      individualPageRequest:p + 272n,
      initialBulkRequest:checked(20n * (p + 272n)),
      cacheControlRequest:168n,
      hashSlots:H, hashRetainedRequest:8n * H,
      hashOldNewRequest:H === 256n ? 2048n : 12n * H}),
    wal:freeze({logicalRegions:R,
      sameInodeMappingBytes:32768n * R,
      perConnectionPrivateIndexPages:R, privateIndexPageRequest:32768n,
      perWalVectorRequest:8n * R, sharedVectorRequest:8n * R,
      checkpointIteratorRequest:checked(256n * R + 2n * F + 2n * (F < 4096n ? F : 4096n)),
      recoveryFrameAndPrivateHashRequest:p + 24n + 32768n,
      unreliableReadFrameRequest:p + 24n}),
    savepoint:freeze({points:S, arrayRequest:checked(80n * S),
      treeNodes:tree.nodes, nodeRequest:512n, treeCount:checked(S + 3n),
      rehashDepth:tree.depth, eachRehashRequest:496n,
      callerWriteOpportunities:callerSteps, retriedWriteOpportunities:retriedSteps,
      subjournalRecordSlots:recordSlots, subjournalBytes,
      subjournalChunks:chunks, eachChunkRequest:1024n}),
    workspaces:freeze({pagerTemporaryRequest:p + 8n,
      btreeTemporaryRequest:p, balanceScratchRequest:7n * p,
      balanceOldNewPageRequests:2n * p}),
    statements:freeze({count:P, vdbeRecordRequest:304n,
      mainDataRegisters:70n, mainCursors:6n, variableSlots:14n,
      mainArraysRequest:vmArrays, mainEmittedSlots:mainH,
      mainOpRequest, mainGrowingOldOpRequest:24n * mainH,
      childPrograms, childEmittedSlots:childH,
      eachChildOpRequest:childOpRequest, eachChildSubprogramRequest:48n,
      retainedChildVdbeCopies:0n,
      eachChildFrameRequest:912n + ceil(childH, 8n),
      p4SlotsPerStatement:p4Slots, eachP4UsableUpper:p4UsableEach,
      p4UsablePerStatement:checked(p4Slots * p4UsableEach),
      metadataArrayRequest:6720n, metadataTextBlocks:120n, metadataTextRequest,
      savedSqlRequest:1625n}),
    bindings:freeze({boundStatements, variableSlots:14n,
      retainedRequestSumPerStatement:retainedBindRequests,
      retainedHeapUsableSumPerStatement:retainedBindUsable,
      retainedHeapUsableSum:checked(boundStatements * retainedBindUsable),
      peakRequestSum:greater(checked(boundStatements * retainedBindRequests),
        checked(bindBeforeActive + activeBindRequests)),
      // Inline1048-byte Utf8Value/control remains in native stack coverage.
      activeUtf8HeapRequest:B <= 341n ? 0n : checked(3n * B + 1n),
      resetReleasesBindingPayload:false}),
    activeVm:freeze({dataRegisters:82n, cursorStorageBlocks:8n,
      eachCursorStorageRequest:816n, eachCursorCacheControlRequest:32n,
      generatedPayloadRequestUpper:generatedPayload,
      eachTranslatedDataPayloadRequestUpper:translatedPayload,
      uniqueRcStringBlocks:90n, eachRcStringRequestUpper:checked(generatedPayload + 12n),
      retainedMainAndChildArraysAlreadyCounted:true}),
    allocationBounds:freeze({
      qualification:'conditional-stock-usable-not-region',
      cachePage:allocation(p + 272n),
      cacheBulk:allocation(20n * (p + 272n)),
      cacheControl:allocation(168n),
      cacheHashGrowth:H === 256n
        ? freeze({previousMaximum:undefined, nextMaximum:allocation(2048n), immediateCredit:false})
        : preservingGrowth(4n * H, 8n * H),
      // Actual prior array capacity can remain after nSavepoint decreases.
      // Use the SAME lifetime maximum S, not an invented current(S-1) size.
      savedPointArrayGrowth:preservingGrowth(80n * S, 80n * S),
      bitvecNode:allocation(512n), bitvecRehash:allocation(496n),
      privateWalIndexPage:allocation(32768n),
      subjournalChunk:allocation(1024n),
      pagerTemporary:allocation(p + 8n), btreeTemporary:allocation(p),
      balanceScratch:allocation(7n * p),
    }),
  });
}

module.exports = freeze({hostJournalNativeStructureRequests, hostJournalNativeUsableUpper});
