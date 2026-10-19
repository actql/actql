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

// An upper for a SUM of independently allocated blocks, not U(sum r).
// The selected stock family above satisfies U(r)<=2r+32768 per block.
// Keep this conservative form where the fixed source inventory records a
// request sum but not every individual size class. This is not region backing.
const allocationGroup = (count, requestSum) => freeze({count, requestSum,
  heapUsableSumUpper:checked(2n * requestSum + 32768n * count)});

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

function includedNativeComponents(value) {
  const a = value.allocationBounds, c = value.cache, w = value.wal;
  const s = value.savepoint, work = value.workspaces;
  const u = hostJournalNativeUsableUpper;
  // Compose distinct original allocations. In particular the retained hash
  // is already the new growth member, and the embedded Pager wrappers are
  // not three more allocations. This remains one selected page geometry.
  const cache = checked(c.peakKeys * a.cachePage.heapUsableUpper +
    a.cacheBulk.heapUsableUpper + a.cacheControl.heapUsableUpper +
    (a.cacheHashGrowth.previousMaximum?.heapUsableUpper ?? 0n) +
    a.cacheHashGrowth.nextMaximum.heapUsableUpper);
  const wal = checked(w.perConnectionPrivateIndexPages * a.privateWalIndexPage.heapUsableUpper +
    u(w.perWalVectorRequest) + u(w.sharedVectorRequest) +
    u(w.checkpointIteratorRequest) + u(w.recoveryFrameAndPrivateHashRequest) +
    u(w.unreliableReadFrameRequest));
  const savepoint = checked(s.treeCount * s.treeNodes * a.bitvecNode.heapUsableUpper +
    a.savedPointArrayGrowth.previousMaximum.heapUsableUpper +
    a.savedPointArrayGrowth.nextMaximum.heapUsableUpper +
    s.rehashDepth * a.bitvecRehash.heapUsableUpper +
    s.subjournalChunks * a.subjournalChunk.heapUsableUpper);
  const workspaces = checked(2n * a.pagerTemporary.heapUsableUpper +
    a.btreeTemporary.heapUsableUpper + a.balanceScratch.heapUsableUpper +
    2n * u(work.btreeTemporaryRequest));
  const pagerControls = checked(a.combinedPager.heapUsableUpper + a.temporaryPath.heapUsableUpper +
    a.btree.heapUsableUpper + a.sharedBtree.heapUsableUpper + a.walAndFile.heapUsableUpper);
  const init = value.connectionInitialization, f3 = init.fts3, f5 = init.fts5;
  const connection = checked(init.sqliteRecord.heapUsableUpper +
    init.recursiveMutex.heapUsableUpper + init.lookaside.heapUsableUpper +
    init.collationBlocks * u(init.eachCollationBlockRequestUpper) +
    init.moduleRegistrations * u(init.eachModuleAndNameRequestUpper) +
    init.functionRegistrationAttempts * u(init.eachFunctionAndNameRequestUpper) +
    init.overloadAttempts * (u(init.eachOverloadDestructorRequest) + u(init.eachOverloadDataNameRequestUpper)) +
    init.registrationHashElements * u(init.eachHashElementRequest) +
    init.growingRegistrationHashes * (init.eachRegistrationHashGrowth.previousMaximum.heapUsableUpper +
      init.eachRegistrationHashGrowth.nextMaximum.heapUsableUpper) +
    u(f3.wrapperRequest) + f3.tokenizerElements * u(f3.eachElementRequest) +
    f3.copiedKeyRequests.reduce((sum, request) => sum + u(request), 0n) + u(f3.initialBucketArrayRequest) +
    u(f5.globalRequest) + f5.auxiliaryRecords * u(f5.eachAuxiliaryAndNameRequestUpper) +
    f5.tokenizerRecords * u(f5.eachTokenizerAndNameRequestUpper));
  const parser = value.preparation.parser;
  const activeParserBackings = checked(parser.activeParsers *
    (parser.eachGrowth.previousMaximum.heapUsableUpper + parser.eachGrowth.nextMaximum.heapUsableUpper));
  const graph = value.preparation.graph;
  const activePrepareGraph = checked([
    graph.expressionContributions, graph.originalLists, graph.oldGrowingLists,
    graph.clonedLists, graph.listEntryNames, graph.sourceLists, graph.sourceCloneNames,
    graph.selectRecords, graph.identifierArrays, graph.identifierNames, graph.cleanupNodes,
  ].reduce((sum, group) => sum + group.heapUsableSumUpper, 0n) +
    graph.labelGrowth.previousMaximum.heapUsableUpper + graph.labelGrowth.nextMaximum.heapUsableUpper +
    graph.tableLockGrowth.previousMaximum.heapUsableUpper + graph.tableLockGrowth.nextMaximum.heapUsableUpper +
    graph.aggregateRequests.reduce((sum, request) => sum + u(request), 0n) +
    u(graph.updateMapRequest) + u(graph.insertIndexMapRequest) +
    value.preparation.planner.heapUsableSubsetUpper);
  const fixed = value.fixedSchema, internal = value.internalSchema;
  // The own-schema and whole-schema hash catalogues are overlapping views.
  // Use the whole30 once, not own28+whole30 or another copy per statement.
  const retainedSchema = checked([
    fixed.tables, fixed.tableNames, fixed.finalColumnArrays, fixed.columnNames,
    fixed.indexesIncludingNames, fixed.checkNodes, fixed.checkNames,
    fixed.checkLists, fixed.checkInnerLists, fixed.defaultLists,
    internal.columnNames, internal.tableAffinities, internal.allSchemaHashElements,
  ].reduce((sum, group) => sum + group.heapUsableSumUpper, 0n) +
    fixed.defaultTrees.heapUsableSumUpper + fixed.foreignKeys.heapUsableSumUpper +
    fixed.triggers.count * (u(fixed.triggers.eachControlRequestUpper) +
      u(fixed.triggers.eachNameRequest) + u(fixed.triggers.eachTableNameRequest) +
      u(fixed.triggers.eachStepAndInlineTargetRequestUpper) +
      u(fixed.triggers.eachSpanRequestUpper) + u(fixed.triggers.eachSetListCloneRequestUpper) +
      u(fixed.triggers.eachSetNameRequest)) +
    fixed.triggers.packedExpressionTrees * u(fixed.triggers.eachPackedTreeRequestUpper) +
    internal.schemas.heapUsableSumUpper + internal.tables.heapUsableSumUpper +
    internal.finalColumnArrays.heapUsableSumUpper + u(internal.mainTableNameRequest) +
    u(internal.tempTableNameRequest) +
    internal.growingHashOriginals * (internal.eachHashGrowth.previousMaximum.heapUsableUpper +
      internal.eachHashGrowth.nextMaximum.heapUsableUpper));
  const statement = value.statements, bind = value.bindings, vm = value.activeVm;
  const eachRetainedStatement = checked(u(statement.vdbeRecordRequest) +
    u(statement.mainArraysRequest) + u(statement.mainOpRequest) +
    statement.childPrograms * (u(statement.eachChildOpRequest) + u(statement.eachChildSubprogramRequest)) +
    statement.p4UsablePerStatement + u(statement.metadataArrayRequest) +
    statement.metadataTextBlocks * u(statement.metadataTextRequest) + u(statement.savedSqlRequest));
  const retainedStatements = checked(statement.count * eachRetainedStatement);
  const retainedBindings = bind.retainedHeapUsableSum;
  const activePrepare = checked(activeParserBackings + activePrepareGraph + eachRetainedStatement +
    u(statement.mainGrowingOldOpRequest) + u(statement.vdbeRecordRequest) +
    u(24n * statement.childEmittedSlots) + u(internal.activeOldColumnArrayRequestUpper) +
    // Node keeps the SQL Utf8Value through native prepare/exec. The copied
    // statement SQL above is a different original, not this temporary.
    u(3n * value.preparation.parser.sqlBytesUpper + 1n));
  const translated = vm.eachTranslatedDataPayloadRequestUpper;
  // Each DATA Mem may retain a previous large payload while scalar/static.
  // At most one currently executing growth/translation adds its old/new
  // overlap. Do not double every Mem, or give cursor-storage Mem DATA payload.
  const activeExecution = checked(vm.dataRegisters * u(translated) + u(translated) +
    vm.uniqueRcStringBlocks * u(vm.eachRcStringRequestUpper) +
    vm.cursorStorageBlocks * (u(vm.eachCursorStorageRequest) + u(vm.eachCursorCacheControlRequest) +
      vm.eachCursorOverflowGrowth.previousMaximum.heapUsableUpper +
      vm.eachCursorOverflowGrowth.nextMaximum.heapUsableUpper + u(vm.eachSavedIndexKeyRequestUpper)) +
    statement.childPrograms * u(statement.eachChildFrameRequest) +
    value.temporaryBtrees.heapUsableSubsetUpper);
  // A positional call clears the old binding set BEFORE constructing its
  // values. At most14 current slots plus one translating copy coexist, then
  // the separate Node Utf8Value. Map each block sum, never U(sum requests).
  const activeBindingCopies = checked((bind.boundStatements - 1n) * bind.retainedHeapUsableSumPerStatement +
    allocationGroup(statement.variableSlots + 1n, bind.activeRequestSumPerStatement).heapUsableSumUpper);
  const activeBinding = checked((activeBindingCopies > retainedBindings
    ? activeBindingCopies - retainedBindings : 0n) +
    (bind.activeUtf8HeapRequest === 0n ? 0n : u(bind.activeUtf8HeapRequest)));
  // The selected synchronous wrapper fences reentry before callbacks and
  // retains unresolved iterators; consume/operands refuse further work until
  // the SAME connection closes. Prepare/reprepare, bind and execution are
  // alternatives for this connection. Different retained connections remain
  // separate co-phase originals; this is not a max across their whole heaps.
  const activeAlternative = greater(activePrepare, greater(activeExecution, activeBinding));
  const node = value.nodeWrappers;
  const nodeWrapperSubset = checked(node.database.heapUsableUpper +
    node.statementAttempts * node.eachStatement.heapUsableUpper +
    node.iteratorAttempts * node.eachIterator.heapUsableUpper +
    node.pointerDataOriginals * node.eachPointerData.heapUsableUpper +
    node.membershipNodes * node.eachMembershipNode.heapUsableUpper +
    node.membershipGrowthAttempts * (node.eachMembershipGrowth.previousMaximum.heapUsableUpper +
      node.eachMembershipGrowth.nextMaximum.heapUsableUpper));
  return freeze({qualification:'included-stock-usable-subtotal-only', completeJournal:false,
    cache, wal, savepoint, workspaces, pagerControls, connection, activeParserBackings, activePrepareGraph,
    retainedSchema, eachRetainedStatement, retainedStatements, retainedBindings,
    activePrepare, activeExecution, activeBinding, activeAlternative, nodeWrapperSubset,
    activePhaseCombination:'maximum-of-same-connection-alternatives',
    heapUsableUpper:checked(cache + wal + savepoint + workspaces + pagerControls +
      connection + retainedSchema + retainedStatements + retainedBindings + activeAlternative +
      nodeWrapperSubset),
    // Same-inode WAL mappings are not heap malloc blocks and are not another
    // per-connection credit. Root must compose each real connection/copy and
    // the shared mapping once, together with all remaining facility terms.
    sameInodeWalMappingBytes:w.sameInodeMappingBytes,
    subjournalUsesCumulativeAttemptUpper:true,
    coversStockRegionAndProcessControls:false,
    returnsCreditOnNativeObjectFree:false});
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
  // A V-byte original may contain malformed UTF8 before semantic admission.
  // Replacement can produce2*V logical UTF16 bytes, then3*V UTF8 bytes. A
  // subsequent UTF16 conversion requests2*n+2 from that logical UTF8 length
  // BEFORE releasing the old backing. The reverse request is at most4*V+1.
  // Do not assume canonical text here, apply2*V+2 to every transition, or use
  // buffer capacity as n. Repeated conversion does not create more characters.
  const translatedPayload = checked(6n * generatedPayload + 6n);
  // Original binary preflight requires usable>=480; the reserved-byte
  // header is one byte. Do not assume usable==pageSize for a saved database.
  const usablePageLower = greater(480n, p - 255n);
  const cursorOverflowRequest = checked(8n * ceil(generatedPayload, usablePageLower - 4n));
  // One-source fixed WHERE shapes under the selected source's default
  // planner20000+1000 budget. This is not a changed public work limit.
  const plannerLoopUsable = hostJournalNativeUsableUpper(208n);
  const plannerTermsUsable = hostJournalNativeUsableUpper(256n);
  // Complete fixed-template forest argument: two parser contexts and their
  // preserved constant/deferred copies, then virtual predicate/CHECK/trigger
  // and aggregate extras. This is not an observed parser high-water mark.
  const forestNodes = 47967n, forestItems = 95934n;
  const forestListRequests = 12663288n;
  const clonedListRequests = checked(2n * forestListRequests + 32768n * forestNodes);
  // Fixed admitted SQL uses only scalar literal IN lists of at most5 items;
  // each ASCII literal is shorter than64 bytes. Cover even the two-item
  // NOOP alternative as a Btree, without relying on planner optimization.
  // A TEXT key has at most128 UTF16 data bytes+3 record-header bytes. With
  // minimum480 usable bytes each key needs at most one overflow page. Five
  // entries occupy at most five leaves/four internal pages, plus schema page1
  // and five overflow pages. Sixteen live pages conservatively cover that
  // population and root transition, plus one failed cache-acquisition key.
  // These are new memory Btree/Pager/cache originals, NOT main Pager aliases.
  const temporaryPage = 65536n, temporaryCursors = 8n;
  const temporaryCache = checked(17n * hostJournalNativeUsableUpper(temporaryPage + 272n) +
    hostJournalNativeUsableUpper(20n * (temporaryPage + 272n)) +
    hostJournalNativeUsableUpper(168n) + hostJournalNativeUsableUpper(2048n));
  const temporaryControls = checked(hostJournalNativeUsableUpper(3751n) +
    hostJournalNativeUsableUpper(1026n) + hostJournalNativeUsableUpper(128n) +
    hostJournalNativeUsableUpper(240n));
  const temporaryWork = checked(2n * hostJournalNativeUsableUpper(temporaryPage + 8n) +
    3n * hostJournalNativeUsableUpper(temporaryPage) +
    hostJournalNativeUsableUpper(7n * temporaryPage));
  // Conditional ordinary LP64 Node/libc++ object-layout uppers, NOT observed
  // sizeof or a selected native allocator extent. BaseObject's vptr, Global,
  // Realm/PointerData pointers and intrusive two-pointer list fit48 bytes.
  // The fixed database fields/string/two empty trees/hash control fit256;
  // statement BaseObject/pointers/flags/optional tree fit128; iterator fits64.
  // No dynamic map, session, backup or user function is admitted by the fixed
  // positional-only Journal receiver. Keep actual ABI/allocator/control and
  // the separate path String backing requirements before operational use.
  const wrapperOriginals = checked(1n + P + X);
  // Default load factor1 and insertion-only pointer membership: growth is
  // requested only when old buckets < next size<=P. Doubling/prime growth
  // stays below8*(P+1) slots; include a full old/new pair for EVERY attempted
  // insertion rather than assuming reset/clear/GC retires native storage.
  const membershipBucketRequest = checked(64n * checked(P + 1n));

  const value = freeze({
    qualification:'partial-native-request-vectors', completePhase:false,
    replenishedOnClose:false,
    nodeWrappers:freeze({
      qualification:'conditional-lp64-node-libcxx-wrapper-subset', completeNativeControl:false,
      database:allocation(256n), statementAttempts:P, eachStatement:allocation(128n),
      iteratorAttempts:X, eachIterator:allocation(64n),
      wrapperOriginals, pointerDataOriginals:wrapperOriginals, eachPointerData:allocation(24n),
      membershipNodes:P, eachMembershipNode:allocation(32n),
      membershipGrowthAttempts:P,
      eachMembershipGrowth:preservingGrowth(membershipBucketRequest, membershipBucketRequest),
      // Strong pointers borrow existing original metadata, not a new control
      // allocation for every db_/stmt_ alias. Conservatively allow one native
      // PointerData allocation for EACH wrapper, including partial attempts.
      newPointerDataPerStrongAlias:false,
      dynamicNamedParameterMaps:0n, backupOrSessionEntries:0n,
      persistentHandleCells:wrapperOriginals,
      // V8 persistent-cell blocks and LocalVector allocators belong to the
      // SAME selected runtime/control domain. They are not supplied by the
      // fixed C++ wrapper requests and must not mint another whole VM heap.
      coversV8HandleBlocks:false, coversResultBacking:false, coversPathBacking:false,
      coversAllocatorRegions:false, nativeCloseRetiresWrappers:false,
      replenishedOnClose:false,
    }),
    connectionInitialization:freeze({
      qualification:'selected-ordinary-builtins-registration-subset', completeConnection:false,
      // Actual selected openDatabase requests808 bytes; aDbStatic and the
      // embedded Hash headers are inside that sqlite3, not extra allocations.
      sqliteRecord:allocation(808n), databaseSlotsInline:2n,
      // LP64 Darwin pthread_mutex_t plus every conditional SQLite debug/
      // armor field fits96. Native pthread/platform bookkeeping is separate.
      recursiveMutex:allocation(96n),
      // Cover both stock one/two-size defaults, not caller/global config.
      // The100-slot branch is the larger original. Small/big slots partition
      // this one backing; do not add another allocation for every slot.
      lookaside:allocation(1200n * 100n), lookasideBackings:1n,
      // BINARY's three encodings share ONE three-CollSeq block. NOCASE and
      // RTRIM each own another such block; each inline name is at most7B.
      collationBlocks:3n, eachCollationBlockRequestUpper:127n,
      // Registration still runs before the first authored SQL, even if no
      // admitted statement ever uses an FTS/RTREE/JSON virtual table.
      moduleRegistrations:12n, eachModuleAndNameRequestUpper:61n,
      // Count all32 registration attempts, including the FTS5 snippet
      // overload already supplied by FTS3. One attempt owns at most one new
      // FuncDef/name. Read-only global builtin FuncDefs are not copied here.
      functionRegistrationAttempts:32n, eachFunctionAndNameRequestUpper:95n,
      overloadAttempts:10n, eachOverloadDestructorRequest:24n,
      eachOverloadDataNameRequestUpper:16n,
      // Function overload chains can share a hash key. Keeping one element
      // per attempt is conservative without allocating another copied name.
      registrationHashElements:47n, eachHashElementRequest:40n,
      growingRegistrationHashes:2n,
      eachRegistrationHashGrowth:preservingGrowth(1024n,1024n),
      fts3:freeze({wrapperRequest:40n, tokenizerElements:3n,
        eachElementRequest:40n, copiedKeyRequests:freeze([7n,7n,10n]),
        initialBucketArrayRequest:128n,
        hashHeadersInline:true, tokenizersInstantiated:false}),
      fts5:freeze({globalRequest:112n, auxiliaryRecords:4n,
        eachAuxiliaryAndNameRequestUpper:64n, tokenizerRecords:4n,
        eachTokenizerAndNameRequestUpper:106n,
        localeRandomBytes:16n, localeHeaderInline:true,
        apiInline:true, tokenizersInstantiated:false}),
      // These are registration objects, not virtual-table/index/tokenizer
      // execution, automatic native extensions or application functions.
      coversVirtualTableExecution:false, coversAutomaticExtensions:false,
      coversNodeWrapperAndPlatform:false,
      customSqliteConfigurationSupported:false,
      sharedModuleRecordsCopied:false, closeReturnsRegionCredit:false,
    }),
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
    pagerControls:freeze({qualification:'selected-non-uri-unix-vfs-subset',
      // Pager+embedded PCache+main/subjournal/journal file wrappers and path
      // suffixes occupy ONE allocation. PCache1/PGroup/hash/pages and actual
      // OS FD/path bookkeeping are distinct, not supplied by this subset.
      combinedPagerRequestUpper:3751n, temporaryPathRequestUpper:1026n,
      btreeRequestUpper:128n, sharedBtreeRequestUpper:240n,
      walAndFileRequestUpper:848n,
      embeddedFileWrapperCount:3n, standaloneEmbeddedFileAllocations:0n,
      physicalFdAndZoneCoverage:false}),
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
    preparation:freeze({completePrepare:false,
      parser:freeze({
        // The fixed current SQL plus rendered nested DDL is bounded1751B.
        // Generated grammar DAG gives live<=29*B+73. yyGrowStack starts
        // inline100, then grows2*old+100:51100 covers50852 live entries.
        sqlBytesUpper:1751n, liveEntriesUpper:50852n,
        nativeCapacityEntriesUpper:51100n, previousNativeEntriesUpper:25500n,
        activeParsers:2n, entryBytes:24n,
        eachGrowth:preservingGrowth(612000n,1226400n),
        // Exact selected RunParser frame2624 includes engine2432/inline100.
        // This is NOT the whole native thread/caller/recursive stack term.
        eachRunParserStackFrameBytes:2624n, engineIncludedInFrame:true,
        parseObjectIncludedInCallerStack:true,
        nativeStackComplete:false,
        growingBackingUsesGlobalAllocator:true,
        fixedSchemaReaderVmCountedSeparately:true,
        nativeFreeReturnsRegionCredit:false,
      }),
      graph:freeze({
        qualification:'closed-fixed-template-active-forest-subset',
        expressionNodes:forestNodes, listItems:forestItems,
        // ROUND8(80 +1751+1), deliberately using the entire supported SQL
        // byte upper instead of assuming a smaller observed token spelling.
        expressionContributions:allocationGroup(forestNodes,1832n * forestNodes),
        // A reduced clone can pack many binary nodes into one allocation.
        // Map the whole SUM with an allocation COUNT upper; U(perNode)*N
        // need not cover a large packed block's cached-size alternative.
        packedCloneTreatedAsOneBlock:true,
        originalLists:allocationGroup(forestNodes,forestListRequests),
        oldGrowingLists:allocationGroup(forestNodes,forestListRequests),
        // ExprListDup requests ORIGINAL usable bytes, not logical nExpr.
        // Compose the stock SUM upper once to bound clone REQUESTS, then
        // map those separate clone allocations through the same upper.
        clonedLists:allocationGroup(forestNodes,clonedListRequests),
        cloneRequestsUseOriginalUsable:true,
        listEntryNames:allocationGroup(forestItems,1752n * forestItems),
        sourceLists:allocationGroup(forestNodes,240n * forestNodes),
        sourceCloneNames:allocationGroup(3n * forestNodes,5256n * forestNodes),
        selectRecords:allocationGroup(forestNodes,160n * forestNodes),
        // Fixed authored INSERT/constraint lists have at most24 entries.
        // Include old/new and cloned IdList arrays, not24 separately
        // allocated records for the inline entries of each original array.
        identifierArrays:allocationGroup(3n * forestNodes,1176n * forestNodes),
        identifierNames:allocationGroup(forestItems,1752n * forestItems),
        // Cover cleanup roots for the six allocated graph families plus
        // emitted main/child P4 bookkeeping, retaining original reset duty.
        cleanupNodes:allocationGroup(6n * forestNodes + p4Slots,
          24n * (6n * forestNodes + p4Slots)),
        labelGrowth:preservingGrowth(103208n,103208n),
        tableLockGrowth:preservingGrowth(928n,928n),
        aggregateRequests:freeze([112n,80n,128n,64n]),
        updateMapRequest:113n, insertIndexMapRequest:20n,
        // Source/Schema pointers borrow retained originals. No whole Table,
        // schema, builtin FuncDef or Vdbe is copied per forest node here.
        wholeSchemaClonesPerNode:0n, wholeVmClonesPerNode:0n,
        copiedSqlAndNodeUtf8Covered:false, backingRetiredByParseReset:false,
      }),
      // Reprepare builds pNew while the old complete VM remains live, then
      // swaps/finalizes it. Fifty sequential retries are work/history, not
      // fifty simultaneous replacement VMs. Schema/bind payloads are not
      // automatically duplicated when the same Mem ownership is transferred.
      reprepare:freeze({retainedPreparedVms:P, activeReplacementVms:1n,
        simultaneousVmOriginals:checked(P + 1n),
        eachReplacementUsesStatementVector:true,
        activeMainGrowingOldOpRequest:24n * mainH,
        duplicatedBindingPayloadSets:0n,
        schemaRetryLimit:50n, retryReturnsBackingCredit:false}),
      planner:freeze({candidateLoops:21000n,
        eachLoopRequest:208n, eachSeparateTermPointerRequest:256n,
        eachLoopUsableUpper:plannerLoopUsable,
        eachTermPointerUsableUpper:plannerTermsUsable,
        activeOldPointerRequestUpper:256n,
        // Inline eight WhereTerms, one level and builder template already
        // reside in the combined WhereInfo. Grown arrays remain linked on
        // pMemToFree, including BOTH16 and32-slot allocations until reset.
        combinedInfoRequestUpper:2080n, solverRequestUpper:176n,
        grown16TermRequest:1680n, grown32TermRequest:3344n,
        retainedGrownTermRequestSum:5024n,
        heapUsableSubsetUpper:checked(21000n * (plannerLoopUsable + plannerTermsUsable) +
          plannerTermsUsable + hostJournalNativeUsableUpper(2080n) +
          hostJournalNativeUsableUpper(176n) + hostJournalNativeUsableUpper(1680n) +
          hostJournalNativeUsableUpper(3344n)),
        secondStat4PassRetainsFirstCandidates:false,
        resetReturnsRegionCredit:false}),
    }),
    bindings:freeze({boundStatements, variableSlots:14n,
      retainedRequestSumPerStatement:retainedBindRequests,
      activeRequestSumPerStatement:activeBindRequests,
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
      usablePageLower,
      // aOverflow uses TWO Pgno arrays, hence8 rather than4 bytes per entry.
      // Logical invalidation/shrink cannot credit the prior larger allocation.
      eachCursorOverflowGrowth:preservingGrowth(cursorOverflowRequest, cursorOverflowRequest),
      eachSavedIndexKeyRequestUpper:checked(generatedPayload + 17n),
      cursorPagesAliasOriginalPager:true,
      aggregateContextCoveredByP4Vector:true,
      aggregateAccumulatorCoveredByDataVector:true,
      retainedMainAndChildArraysAlreadyCounted:true}),
    temporaryBtrees:freeze({
      qualification:'fixed-literal-in-memory-btree-subset', completeTemporaryFacility:false,
      simultaneousOriginals:temporaryCursors, maximumListItems:5n,
      maximumLiteralUtf8Bytes:64n, maximumEncodedKeyBytes:131n,
      maximumOverflowPagesPerKey:1n, usablePageLower:480n,
      livePagesPerOriginal:16n, peakCacheKeysPerOriginal:17n,
      pageBytesUpper:temporaryPage,
      eachCacheSubsetUpper:temporaryCache, eachControlSubsetUpper:temporaryControls,
      eachWorkSubsetUpper:temporaryWork,
      heapUsableSubsetUpper:checked(temporaryCursors *
        (temporaryCache + temporaryControls + temporaryWork)),
      mainPagerAlias:false, separateWalMapping:false,
      // OP_OpenEphemeral selects OMIT_JOURNAL|SINGLE, while the selected
      // TEMP_STORE=MEMORY is checked before schema preparation. No virtual
      // table/subquery/sorter/automatic-join-index execution is imported.
      omittedJournal:true, temporaryStorage:'memory',
      coversSortersOrVirtualTables:false, closeReturnsRegionCredit:false,
    }),
    fixedSchema:freeze({
      qualification:'closed-own-ddl-retained-subset', completeSchema:false,
      // One combined primary/observation catalogue, NOT a copy per prepared
      // statement. Internal main/temp Schema, intrinsic tables, hashes,
      // trigger graphs and parse/copy/growth work remain additional terms.
      tables:allocationGroup(15n, 1800n),
      tableNames:allocationGroup(15n, 427n),
      finalColumnArrays:allocationGroup(15n, 1424n),
      columnNames:allocationGroup(89n, 1380n),
      // Index name bytes are INLINE in the same allocation as the Index,
      // pointer/column/sort arrays. Do not charge a second name allocation.
      indexesIncludingNames:allocationGroup(10n, 2019n),
      fixedRecordRequestSum:7050n,
      // Retained CHECK originals are not all reduced packed clones. Inner
      // ExprLists and original CHECK names have their own allocations.
      checkNodes:allocationGroup(117n, 10008n),
      checkNames:allocationGroup(33n, 779n),
      checkLists:allocationGroup(13n, 1896n),
      checkInnerLists:allocationGroup(7n, 1080n),
      // Each numeric-zero default packs TK_SPAN plus its child into ONE
      // reduced-tree allocation. Its temporary parsed node/span overlap it.
      defaultTrees:freeze({count:7n, eachRequestUpper:176n,
        heapUsableSumUpper:7n * hostJournalNativeUsableUpper(176n)}),
      defaultLists:allocationGroup(2n, 400n),
      activeDefaultParsedNodeRequestUpper:82n,
      activeDefaultSpanRequest:2n,
      // The two NO ACTION references each allocate FKey+one column mapping+
      // both terminated names together:64+16+16+19. The parent Table/key
      // aliases are not another copy, nor an automatic action-trigger VM.
      foreignKeys:freeze({count:2n, eachRequest:115n,
        heapUsableSumUpper:2n * hostJournalNativeUsableUpper(115n),
        generatedActionTriggers:0n}),
      // Fixed AFTER INSERT/DELETE triggers each retain one UPDATE step.
      // These records survive execution/reset; their programs are the
      // transferred child programs already counted under statements.
      triggers:freeze({count:2n, eachControlRequestUpper:96n,
        eachNameRequest:36n, eachTableNameRequest:24n,
        eachStepAndInlineTargetRequestUpper:127n,
        eachSpanRequestUpper:128n,
        packedExpressionTrees:4n, eachPackedTreeRequestUpper:264n,
        // ExprListDup uses original xSize(136), not136 itself. The schema
        // CREATE path disables lookaside; the selected stock upper is160.
        eachSetListCloneRequestUpper:160n, eachSetNameRequest:15n,
        resetRetiresTriggers:false}),
      // Hash keys alias these owned names. Do not allocate a name for every
      // HashElem. Fixed own records alone have28 entries; intrinsic schema
      // entries and any in-progress/error-path insertions remain additional.
      ownHashElements:allocationGroup(28n, 1120n),
      // A transient DML CHECK clone is beside the retained Schema and VM;
      // list clones request the original usable size, not the logical count.
      largestActiveCheckCloneNodeRequestSum:640n,
      cloneListRequestUsesOriginalUsable:true,
      resetRetiresSchema:false,
    }),
    internalSchema:freeze({
      qualification:'per-connection-main-and-temp-schema-subset', completeSchema:false,
      // sqlite3SchemaGet allocates main and TEMP independently. The four
      // Hash headers are inline in each120-byte LP64 Schema, not four more
      // allocation originals. TEMP exists even without a temp Btree.
      schemas:freeze({count:2n, eachRequest:120n,
        heapUsableSumUpper:2n * hostJournalNativeUsableUpper(120n)}),
      // sqlite3InitOne parses its fixed CREATE TABLE x(type text,name text,
      // tbl_name text,rootpage int,sql text) into each internal Table. These
      // two tables are additional to the15 admitted application tables.
      tables:freeze({count:2n, eachRequest:120n,
        heapUsableSumUpper:2n * hostJournalNativeUsableUpper(120n)}),
      mainTableNameRequest:14n, tempTableNameRequest:19n,
      // TEXT and INT use the standard type enum, without copied type text.
      finalColumnArrays:freeze({count:2n, eachRequest:80n,
        heapUsableSumUpper:2n * hostJournalNativeUsableUpper(80n)}),
      columnNames:allocationGroup(10n,64n),
      activeOldColumnArrayRequestUpper:64n,
      // Account the lazy affinity strings separately from Column and name
      // storage, whether or not this execution actually requests them.
      tableAffinities:allocationGroup(17n,116n),
      //28 own-DDL hash elements plus main/TEMP internal table entries.
      // Hash keys borrow the original owning names; no copied key per entry.
      additionalHashElements:allocationGroup(2n,80n),
      // This whole-schema view includes fixedSchema.ownHashElements: do not
      // add both views to a co-phase sum as independent allocations.
      allSchemaHashElements:allocationGroup(30n,1200n),
      // Only main table/index hashes reach5 entries for this exact schema.
      // rehash clamps each bucket request to SQLITE_MALLOC_SOFT_LIMIT1024.
      // Keep old/new alternatives beside both originals, without credit on
      // schema reset. Element records are accounted separately above.
      growingHashOriginals:2n,
      eachHashGrowth:preservingGrowth(1024n,1024n),
      hashHeadersInline:true, hashKeysAliasOwnedNames:true,
      schemasSharedAcrossConnections:false,
      applicationTableCopiesIncluded:false,
      schemaParseAndReaderCovered:false,
      resetReturnsRegionCredit:false,
    }),
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
      combinedPager:allocation(3751n), temporaryPath:allocation(1026n),
      btree:allocation(128n), sharedBtree:allocation(240n), walAndFile:allocation(848n),
    }),
  });
  return freeze({...value, includedNativeComponents:includedNativeComponents(value)});
}

module.exports = freeze({hostJournalNativeStructureRequests, hostJournalNativeUsableUpper});
