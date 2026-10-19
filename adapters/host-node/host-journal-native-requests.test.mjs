import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import requests from './host-journal-native-requests.cjs';

const {hostJournalNativeStructureRequests:calculate, hostJournalNativeUsableUpper:usable} = requests;
const input = (overrides = {}) => ({databaseBytes:4194304n, pageBytes:4096n,
  walFrames:4062n, preparedStatements:10n, sqlCalls:100n, sqlBytes:10000n,
  statementCalls:100n, resultRows:128n, parameterBytes:4096n, ...overrides});
const unavailable = {code:'HostJournalEnvelopeUnavailable'};

test('main cache includes failed page and original hash growth at exact power boundary', () => {
  const value = calculate(input());
  assert.equal(value.cache.admittedPages,1024n);
  assert.equal(value.cache.peakKeys,1025n);
  assert.equal(value.cache.hashSlots,2048n);
  assert.equal(value.cache.hashOldNewRequest,24576n);
  assert.equal(value.cache.individualPageRequest,4368n);
  assert.equal(value.cache.initialBulkRequest,87360n);
  assert.equal(calculate(input({databaseBytes:4190208n})).cache.hashSlots,1024n);
});

test('WAL first-region boundary keeps shared mapping separate from private fallback pages', () => {
  const first = calculate(input());
  const next = calculate(input({walFrames:4063n}));
  assert.equal(first.wal.logicalRegions,1n);
  assert.equal(next.wal.logicalRegions,2n);
  assert.equal(next.wal.sameInodeMappingBytes,65536n);
  assert.equal(next.wal.perConnectionPrivateIndexPages,2n);
  assert.equal(next.wal.privateIndexPageRequest,32768n);
  assert.equal(next.wal.recoveryFrameAndPrivateHashRequest,36888n);
});

test('savepoints and partial subjournal chunks use original attempt lifetime without floating point', () => {
  const value = calculate(input());
  assert.equal(value.savepoint.points,12n);
  assert.equal(value.savepoint.arrayRequest,960n);
  assert.equal(value.savepoint.callerWriteOpportunities,23000n);
  assert.equal(value.savepoint.retriedWriteOpportunities,1173000n);
  assert.equal(value.savepoint.subjournalRecordSlots,1201152000n);
  assert.equal(value.savepoint.subjournalBytes,4924723200000n);
  assert.equal(value.savepoint.subjournalChunks,4847168504n);
  const tree = calculate(input({databaseBytes:67108864n})).savepoint;
  assert.equal(tree.treeNodes,6n);
  assert.equal(tree.rehashDepth,2n);
});

test('incomplete vectors are immutable DATA and never claim complete phase or returned credit', () => {
  const value = calculate(input());
  assert.equal(value.qualification,'partial-native-request-vectors');
  assert.equal(value.completePhase,false);
  assert.equal(value.replenishedOnClose,false);
  assert(Object.isFrozen(value));
  for (const key of ['cache','wal','savepoint','workspaces']) assert(Object.isFrozen(value[key]));
  assert.throws(() => {value.wal.logicalRegions = 0n;},TypeError);
  assert.equal(typeof requests.prepareHostJournalInstallation,'undefined');
});

test('proxy/accessor/inherited input is refused without invoking caller traps or coercion', () => {
  let reads = 0;
  const proxy = new Proxy(input(),{get(){reads++;},ownKeys(){reads++;},getOwnPropertyDescriptor(){reads++;}});
  assert.throws(() => calculate(proxy),unavailable);
  const getter = input();
  Object.defineProperty(getter,'pageBytes',{get(){reads++;return 4096n;}});
  assert.throws(() => calculate(getter),unavailable);
  assert.throws(() => calculate(Object.create(input())),unavailable);
  assert.equal(reads,0);
});

test('unsupported representation and overflowing products refuse rather than truncate or resize', () => {
  for (const overrides of [{pageBytes:4096},{pageBytes:513n},{databaseBytes:1n},
    {walFrames:4294967295n},{preparedStatements:0n},{sqlBytes:-1n},
    {statementCalls:9223372036854775807n},{sqlBytes:9223372036854775807n}]) {
    assert.throws(() => calculate(input(overrides)),unavailable);
  }
  assert.throws(() => calculate(input({walFrames:268431327n})),unavailable);
});

test('stock usable upper follows separate small classes and large cached alternatives', () => {
  for (const [request,expected] of [[1n,16n],[80n,80n],[136n,160n],[264n,320n],
    [520n,640n],[1008n,1024n],[1009n,1024n],[1032n,1536n],[2056n,2560n],
    [8192n,8192n],[32768n,32768n],[32769n,98303n],[65536n,131071n],
    [1048576n,2097151n]]) assert.equal(usable(request),expected);
  for (const request of [0n,-1n,1,NaN,9223372036854775807n]) {
    assert.throws(() => usable(request),unavailable);
  }
});

test('bulk and page are mapped individually rather than mapping their request sum', () => {
  const allocations = calculate(input()).allocationBounds;
  assert.equal(allocations.cachePage.heapUsableUpper,5120n);
  assert.equal(allocations.cacheBulk.heapUsableUpper,196607n);
  assert.equal(allocations.cacheBulk.heapUsableUpper + allocations.cachePage.heapUsableUpper,201727n);
  assert.equal(usable(allocations.cacheBulk.request + allocations.cachePage.request),196607n);
  assert.notEqual(allocations.cacheBulk.heapUsableUpper + allocations.cachePage.heapUsableUpper,
    usable(allocations.cacheBulk.request + allocations.cachePage.request));
});

test('reallocation keeps both original alternatives and does not free prior maximum on logical shrink', () => {
  const allocations = calculate(input()).allocationBounds;
  assert.equal(allocations.cacheHashGrowth.previousMaximum.request,8192n);
  assert.equal(allocations.cacheHashGrowth.nextMaximum.request,16384n);
  assert.equal(allocations.cacheHashGrowth.immediateCredit,false);
  const saved = allocations.savedPointArrayGrowth;
  assert.equal(saved.previousMaximum.request,960n);
  assert.equal(saved.nextMaximum.request,960n);
  assert.equal(saved.retainedOriginalUpper,1024n);
  assert.equal(saved.immediateCredit,false);
  for (const value of Object.values(allocations)) {
    if (typeof value === 'object') assert(Object.isFrozen(value));
  }
});

test('retained VM and transferred child keep fixed arrays and P4 beside active work', () => {
  const {statements:s,activeVm:a} = calculate(input());
  assert.equal(s.count,10n);
  assert.equal(s.mainArraysRequest,5088n);
  assert.equal(s.mainOpRequest,618960n);
  assert.equal(s.eachChildOpRequest,148944n);
  assert.equal(s.retainedChildVdbeCopies,0n);
  assert.equal(s.eachChildSubprogramRequest,48n);
  assert.equal(s.eachChildFrameRequest,1300n);
  assert.equal(s.p4SlotsPerStatement,19104n);
  assert.equal(s.eachP4UsableUpper,3584n);
  assert.equal(s.p4UsablePerStatement,68468736n);
  assert.equal(s.metadataTextBlocks,120n);
  assert.equal(a.dataRegisters,82n);
  assert.equal(a.cursorStorageBlocks,8n);
  assert.equal(a.retainedMainAndChildArraysAlreadyCounted,true);
});

test('bindings survive reset and one active bind overlaps retained statements without U of sum', () => {
  const {bindings:b} = calculate(input());
  assert.equal(b.boundStatements,10n);
  assert.equal(b.retainedRequestSumPerStatement,8640n);
  assert.equal(b.retainedHeapUsableSumPerStatement,476032n);
  assert.equal(b.retainedHeapUsableSum,4760320n);
  assert.equal(b.peakRequestSum,90524n);
  assert.equal(b.activeUtf8HeapRequest,12289n);
  assert.equal(b.resetReleasesBindingPayload,false);
  assert.equal(calculate(input({statementCalls:1n})).bindings.boundStatements,1n);
  assert.equal(calculate(input({parameterBytes:341n})).bindings.activeUtf8HeapRequest,0n);
});

test('generated/intermediate record upper is not silently limited to saved file bytes', () => {
  const value = calculate(input());
  assert.equal(value.activeVm.generatedPayloadRequestUpper,4218044n);
  assert.equal(value.activeVm.eachTranslatedDataPayloadRequestUpper,25308270n);
  assert.equal(value.activeVm.eachRcStringRequestUpper,4218056n);
  assert.equal(value.activeVm.uniqueRcStringBlocks,90n);
  assert.throws(() => calculate(input({parameterBytes:9223372036854775807n})),unavailable);
});

test('fixed schema request catalogue remains bound to the exact supported own DDL', () => {
  const body = readFileSync(new URL('./host-journal-schema-support.cjs', import.meta.url));
  assert.equal(createHash('sha256').update(body).digest('hex'),
    '9677078c8c7df3c264d0b02f6f20e45bb9fa645f8c100cb5ed099a68bc27e44a');
  const s = calculate(input()).fixedSchema;
  assert.equal(s.tables.count,15n);
  assert.equal(s.finalColumnArrays.requestSum,1424n);
  assert.equal(s.columnNames.count,89n);
  assert.equal(s.indexesIncludingNames.count,10n);
  assert.equal(s.indexesIncludingNames.requestSum,2019n);
  assert.equal(s.tables.requestSum + s.tableNames.requestSum +
    s.finalColumnArrays.requestSum + s.columnNames.requestSum +
    s.indexesIncludingNames.requestSum,7050n);
});

test('schema groups apply a per-block sum bound and retain independent lifetime', () => {
  const a = calculate(input({preparedStatements:1n})).fixedSchema;
  const b = calculate(input({preparedStatements:100n})).fixedSchema;
  assert.deepEqual(a,b);
  assert.equal(a.tables.heapUsableSumUpper,495120n);
  assert.equal(a.indexesIncludingNames.heapUsableSumUpper,331718n);
  assert.equal(a.completeSchema,false);
  assert.equal(a.resetRetiresSchema,false);
  assert(Object.isFrozen(a));
  assert(Object.isFrozen(a.checkNodes));
});

test('retained CHECK originals and packed defaults do not collapse into one allocation', () => {
  const s = calculate(input()).fixedSchema;
  assert.equal(s.checkNodes.count,117n);
  assert.equal(s.checkNodes.requestSum,10008n);
  assert.equal(s.checkNames.count,33n);
  assert.equal(s.checkLists.count,13n);
  assert.equal(s.checkInnerLists.count,7n);
  assert.equal(s.defaultTrees.count,7n);
  assert.equal(s.defaultTrees.heapUsableSumUpper,1344n);
  assert.equal(s.defaultLists.requestSum,400n);
  assert.equal(s.activeDefaultParsedNodeRequestUpper,82n);
  assert.equal(s.activeDefaultSpanRequest,2n);
  assert.equal(s.largestActiveCheckCloneNodeRequestSum,640n);
  assert.equal(s.cloneListRequestUsesOriginalUsable,true);
});

test('fixed foreign-key and trigger holdings keep coallocations and transferred VM ownership separate', () => {
  const s = calculate(input()).fixedSchema;
  assert.equal(s.foreignKeys.count,2n);
  assert.equal(s.foreignKeys.eachRequest,115n);
  assert.equal(s.foreignKeys.heapUsableSumUpper,256n);
  assert.equal(s.foreignKeys.generatedActionTriggers,0n);
  assert.equal(s.triggers.count,2n);
  assert.equal(s.triggers.eachStepAndInlineTargetRequestUpper,127n);
  assert.equal(s.triggers.packedExpressionTrees,4n);
  assert.equal(s.triggers.eachSetListCloneRequestUpper,160n);
  assert.equal(s.triggers.resetRetiresTriggers,false);
  assert.equal(s.ownHashElements.count,28n);
  assert.equal(s.ownHashElements.requestSum,1120n);
  assert.equal(calculate(input()).statements.retainedChildVdbeCopies,0n);
  assert(Object.isFrozen(s.foreignKeys));
  assert(Object.isFrozen(s.triggers));
});

test('reprepare retains one replacement beside existing VMs without multiplying bindings or retry credit', () => {
  const p = calculate(input()).preparation;
  assert.equal(p.completePrepare,false);
  assert.equal(p.reprepare.retainedPreparedVms,10n);
  assert.equal(p.reprepare.activeReplacementVms,1n);
  assert.equal(p.reprepare.simultaneousVmOriginals,11n);
  assert.equal(p.reprepare.activeMainGrowingOldOpRequest,309504n);
  assert.equal(p.reprepare.duplicatedBindingPayloadSets,0n);
  assert.equal(p.reprepare.schemaRetryLimit,50n);
  assert.equal(p.reprepare.retryReturnsBackingCredit,false);
  assert.throws(() => calculate(input({preparedStatements:9223372036854775807n})),unavailable);
});

test('planner keeps all linked grown arrays and only one active old pointer resize', () => {
  const p = calculate(input()).preparation.planner;
  assert.equal(p.candidateLoops,21000n);
  assert.equal(p.eachLoopUsableUpper,224n);
  assert.equal(p.eachTermPointerUsableUpper,256n);
  assert.equal(p.activeOldPointerRequestUpper,256n);
  assert.equal(p.grown16TermRequest,1680n);
  assert.equal(p.grown32TermRequest,3344n);
  assert.equal(p.retainedGrownTermRequestSum,5024n);
  assert.equal(p.heapUsableSubsetUpper,10088640n);
  assert.equal(p.secondStat4PassRetainsFirstCandidates,false);
  assert.equal(p.resetReturnsRegionCredit,false);
  assert(Object.isFrozen(p));
});

test('Pager file wrappers stay coallocated while pathname and Btree originals overlap separately', () => {
  const {pagerControls:p,allocationBounds:a} = calculate(input());
  assert.equal(p.combinedPagerRequestUpper,3751n);
  assert.equal(p.temporaryPathRequestUpper,1026n);
  assert.equal(p.embeddedFileWrapperCount,3n);
  assert.equal(p.standaloneEmbeddedFileAllocations,0n);
  assert.equal(a.combinedPager.heapUsableUpper,4096n);
  assert.equal(a.temporaryPath.heapUsableUpper,1536n);
  assert.equal(a.btree.heapUsableUpper,128n);
  assert.equal(a.sharedBtree.heapUsableUpper,256n);
  assert.equal(a.walAndFile.heapUsableUpper,896n);
});

test('cursor overflow accounts for reserved bytes and both original Pgno arrays', () => {
  const a = calculate(input()).activeVm;
  assert.equal(a.usablePageLower,3841n);
  assert.equal(a.eachCursorOverflowGrowth.nextMaximum.request,8800n);
  assert.equal(a.eachCursorOverflowGrowth.previousMaximum.request,8800n);
  assert.equal(a.eachCursorOverflowGrowth.immediateCredit,false);
  assert.equal(a.eachSavedIndexKeyRequestUpper,4218061n);
  const small = calculate(input({pageBytes:512n})).activeVm;
  assert.equal(small.usablePageLower,480n);
  assert.equal(small.eachCursorOverflowGrowth.nextMaximum.request,70896n);
});

test('cursor page aliases and aggregate ownership do not multiply native originals', () => {
  const a = calculate(input()).activeVm;
  assert.equal(a.cursorPagesAliasOriginalPager,true);
  assert.equal(a.aggregateContextCoveredByP4Vector,true);
  assert.equal(a.aggregateAccumulatorCoveredByDataVector,true);
  assert.equal(a.retainedMainAndChildArraysAlreadyCounted,true);
  assert.equal(calculate(input()).completePhase,false);
});

test('included native sum keeps old/new originals without adding the retained hash twice', () => {
  const n = calculate(input()).includedNativeComponents;
  assert.equal(n.cache,5469375n);
  assert.equal(n.wal,156703n);
  assert.equal(n.savepoint,4963500558336n);
  assert.equal(n.workspaces,51200n);
  assert.equal(n.pagerControls,6912n);
  assert.equal(n.connection,275375n);
  assert.equal(n.activeParserBackings,7405564n);
  assert.equal(n.activePrepareGraph,39978849038n);
  assert.equal(n.retainedSchema,12276562n);
  assert.equal(n.eachRetainedStatement,70814109n);
  assert.equal(n.retainedStatements,708141090n);
  assert.equal(n.retainedBindings,4760320n);
  assert.equal(n.activePrepare,40057861669n);
  assert.equal(n.heapUsableUpper,5004289557542n);
  assert.equal(n.sameInodeWalMappingBytes,32768n);
});

test('a native subset is not a whole facility or allocator-release acknowledgement', () => {
  const n = calculate(input()).includedNativeComponents;
  assert.equal(n.completeJournal,false);
  assert.equal(n.coversStockRegionAndProcessControls,false);
  assert.equal(n.subjournalUsesCumulativeAttemptUpper,true);
  assert.equal(n.returnsCreditOnNativeObjectFree,false);
  assert(Object.isFrozen(n));
  assert.equal(calculate(input({databaseBytes:512n,pageBytes:512n})).cache.hashSlots,256n);
  assert.equal(calculate(input({databaseBytes:512n,pageBytes:512n}))
    .includedNativeComponents.cache,20416n);
});

test('main and TEMP internal schemas are distinct from admitted own tables and inline hashes', () => {
  const {internalSchema:s,fixedSchema:own} = calculate(input());
  assert.equal(s.schemas.count,2n);
  assert.equal(s.schemas.eachRequest,120n);
  assert.equal(s.schemas.heapUsableSumUpper,256n);
  assert.equal(s.tables.count,2n);
  assert.equal(s.mainTableNameRequest,14n);
  assert.equal(s.tempTableNameRequest,19n);
  assert.equal(s.finalColumnArrays.eachRequest,80n);
  assert.equal(s.columnNames.count,10n);
  assert.equal(s.columnNames.requestSum,64n);
  assert.equal(s.activeOldColumnArrayRequestUpper,64n);
  assert.equal(own.tables.count,15n);
  assert.equal(s.hashHeadersInline,true);
  assert.equal(s.schemasSharedAcrossConnections,false);
  assert.equal(s.applicationTableCopiesIncluded,false);
  assert(Object.isFrozen(s));
});

test('whole-schema hashes and affinities retain borrowed names and original growth alternatives', () => {
  const s = calculate(input()).internalSchema;
  assert.equal(s.tableAffinities.count,17n);
  assert.equal(s.tableAffinities.requestSum,116n);
  assert.equal(s.allSchemaHashElements.count,30n);
  assert.equal(s.allSchemaHashElements.requestSum,1200n);
  assert.equal(s.additionalHashElements.count,2n);
  assert.equal(s.additionalHashElements.requestSum,80n);
  assert.equal(s.allSchemaHashElements.requestSum,
    calculate(input()).fixedSchema.ownHashElements.requestSum + s.additionalHashElements.requestSum);
  assert.equal(s.growingHashOriginals,2n);
  assert.equal(s.eachHashGrowth.previousMaximum.request,1024n);
  assert.equal(s.eachHashGrowth.nextMaximum.request,1024n);
  assert.equal(s.eachHashGrowth.immediateCredit,false);
  assert.equal(s.hashKeysAliasOwnedNames,true);
  assert.equal(s.schemaParseAndReaderCovered,false);
  assert.equal(s.completeSchema,false);
  assert.equal(s.resetReturnsRegionCredit,false);
});

test('connection registration includes selected compiled-in modules even without virtual-table execution', () => {
  const c = calculate(input()).connectionInitialization;
  assert.equal(c.sqliteRecord.request,808n);
  assert.equal(c.databaseSlotsInline,2n);
  assert.equal(c.recursiveMutex.request,96n);
  assert.equal(c.lookaside.request,120000n);
  assert.equal(c.lookasideBackings,1n);
  assert.equal(c.collationBlocks,3n);
  assert.equal(c.eachCollationBlockRequestUpper,127n);
  assert.equal(c.moduleRegistrations,12n);
  assert.equal(c.functionRegistrationAttempts,32n);
  assert.equal(c.overloadAttempts,10n);
  assert.equal(c.registrationHashElements,47n);
  assert.equal(c.coversAutomaticExtensions,false);
  assert.equal(c.coversVirtualTableExecution,false);
  assert.equal(c.sharedModuleRecordsCopied,false);
  assert.equal(c.closeReturnsRegionCredit,false);
  assert(Object.isFrozen(c));
});

test('FTS registration keeps inline API and locale header separate from real table/tokenizer execution', () => {
  const {fts3:f3,fts5:f5} = calculate(input()).connectionInitialization;
  assert.equal(f3.wrapperRequest,40n);
  assert.equal(f3.tokenizerElements,3n);
  assert.deepEqual(f3.copiedKeyRequests,[7n,7n,10n]);
  assert.equal(f3.initialBucketArrayRequest,128n);
  assert.equal(f3.tokenizersInstantiated,false);
  assert.equal(f5.globalRequest,112n);
  assert.equal(f5.auxiliaryRecords,4n);
  assert.equal(f5.tokenizerRecords,4n);
  assert.equal(f5.apiInline,true);
  assert.equal(f5.localeRandomBytes,16n);
  assert.equal(f5.localeHeaderInline,true);
  assert.equal(f5.tokenizersInstantiated,false);
  assert(Object.isFrozen(f3.copiedKeyRequests));
});

test('selected parser growth retains old plus new separately from its inline engine and caller stack', () => {
  const p = calculate(input()).preparation.parser;
  assert.equal(p.sqlBytesUpper,1751n);
  assert.equal(p.liveEntriesUpper,29n * 1751n + 73n);
  assert.equal(p.nativeCapacityEntriesUpper,51100n);
  assert.equal(p.previousNativeEntriesUpper,25500n);
  assert.equal(p.eachGrowth.previousMaximum.request,612000n);
  assert.equal(p.eachGrowth.nextMaximum.request,1226400n);
  assert.equal(p.eachGrowth.immediateCredit,false);
  assert.equal(p.eachRunParserStackFrameBytes,2624n);
  assert.equal(p.engineIncludedInFrame,true);
  assert.equal(p.parseObjectIncludedInCallerStack,true);
  assert.equal(p.nativeStackComplete,false);
  assert.equal(p.fixedSchemaReaderVmCountedSeparately,true);
  assert.equal(p.nativeFreeReturnsRegionCredit,false);
});

test('active prepare forest maps packed expression contributions by allocation count and summed requests', () => {
  const g = calculate(input()).preparation.graph;
  assert.equal(g.expressionNodes,47967n);
  assert.equal(g.listItems,95934n);
  assert.equal(g.expressionContributions.count,47967n);
  assert.equal(g.expressionContributions.requestSum,1832n * 47967n);
  assert.equal(g.expressionContributions.heapUsableSumUpper,1747533744n);
  assert.equal(g.packedCloneTreatedAsOneBlock,true);
  assert.equal(g.wholeSchemaClonesPerNode,0n);
  assert.equal(g.wholeVmClonesPerNode,0n);
  assert.equal(g.backingRetiredByParseReset,false);
  assert(Object.isFrozen(g));
});

test('ExprList clone requests preserve original usable size and old growing arrays', () => {
  const g = calculate(input()).preparation.graph;
  assert.equal(g.originalLists.requestSum,12663288n);
  assert.equal(g.oldGrowingLists.requestSum,12663288n);
  assert.equal(g.clonedLists.requestSum,1597109232n);
  assert.equal(g.clonedLists.heapUsableSumUpper,4766001120n);
  assert.equal(g.cloneRequestsUseOriginalUsable,true);
  assert.equal(g.identifierArrays.count,3n * 47967n);
  assert.equal(g.identifierArrays.requestSum,1176n * 47967n);
  assert.equal(g.sourceLists.requestSum,240n * 47967n);
  assert.equal(g.selectRecords.requestSum,160n * 47967n);
  assert.equal(g.copiedSqlAndNodeUtf8Covered,false);
});

test('prepare cleanup and control allocations remain alongside forests until original reset', () => {
  const g = calculate(input()).preparation.graph;
  assert.equal(g.cleanupNodes.count,306906n);
  assert.equal(g.cleanupNodes.requestSum,7365744n);
  assert.equal(g.labelGrowth.previousMaximum.request,103208n);
  assert.equal(g.labelGrowth.nextMaximum.request,103208n);
  assert.equal(g.tableLockGrowth.previousMaximum.request,928n);
  assert.equal(g.tableLockGrowth.nextMaximum.request,928n);
  assert.deepEqual(g.aggregateRequests,[112n,80n,128n,64n]);
  assert.equal(g.updateMapRequest,113n);
  assert.equal(g.insertIndexMapRequest,20n);
  assert.equal(calculate(input()).includedNativeComponents.completeJournal,false);
});

test('retained schema is one per connection and whole hashes do not duplicate the own hash view', () => {
  const first = calculate(input({preparedStatements:1n}));
  const many = calculate(input({preparedStatements:100n}));
  assert.equal(first.includedNativeComponents.retainedSchema,many.includedNativeComponents.retainedSchema);
  assert.equal(first.includedNativeComponents.retainedSchema,12276562n);
  assert.equal(first.internalSchema.allSchemaHashElements.count,30n);
  assert.equal(first.fixedSchema.ownHashElements.count,28n);
  assert.equal(first.includedNativeComponents.retainedStatements,
    first.includedNativeComponents.eachRetainedStatement);
  assert.equal(many.includedNativeComponents.retainedStatements,
    100n * first.includedNativeComponents.eachRetainedStatement);
});

test('same-connection active phases are alternatives beside retained VMs, schema and bindings', () => {
  const value = calculate(input()), n = value.includedNativeComponents;
  assert.equal(n.activePhaseCombination,'maximum-of-same-connection-alternatives');
  assert.equal(n.activeAlternative,[n.activePrepare,n.activeExecution,n.activeBinding]
    .reduce((high,value) => high > value ? high : value));
  assert.equal(n.heapUsableUpper,n.cache+n.wal+n.savepoint+n.workspaces+n.pagerControls+
    n.connection+n.retainedSchema+n.retainedStatements+n.retainedBindings+n.activeAlternative);
  assert(n.activeAlternative < n.activePrepare+n.activeExecution+n.activeBinding);
  // Includes one full replacement VM plus one active old/new opcode pair,
  // not fifty retained copies for sequential schema retries.
  assert(n.activePrepare > n.eachRetainedStatement+n.activeParserBackings+n.activePrepareGraph);
  assert.equal(value.preparation.reprepare.activeReplacementVms,1n);
});

test('UTF16 round-trip allocation uses logical encoded length and only one active growth overlap', () => {
  const value = calculate(input()), vm = value.activeVm, n = value.includedNativeComponents;
  const maximumLogicalUtf16 = 2n * vm.generatedPayloadRequestUpper;
  assert(vm.eachTranslatedDataPayloadRequestUpper >= 2n * maximumLogicalUtf16 + 1n);
  const replacementUtf8 = 3n * vm.generatedPayloadRequestUpper;
  assert(vm.eachTranslatedDataPayloadRequestUpper >= 2n * replacementUtf8 + 2n);
  const u = usable, s = value.statements;
  const cursor = vm.cursorStorageBlocks * (u(vm.eachCursorStorageRequest)+u(vm.eachCursorCacheControlRequest)+
    vm.eachCursorOverflowGrowth.previousMaximum.heapUsableUpper+
    vm.eachCursorOverflowGrowth.nextMaximum.heapUsableUpper+u(vm.eachSavedIndexKeyRequestUpper));
  assert.equal(n.activeExecution,(vm.dataRegisters+1n)*u(vm.eachTranslatedDataPayloadRequestUpper)+
    vm.uniqueRcStringBlocks*u(vm.eachRcStringRequestUpper)+cursor+
    s.childPrograms*u(s.eachChildFrameRequest));
  assert.equal(value.bindings.activeRequestSumPerStatement,12764n);
  assert.equal(n.activeBinding,55352n);
  assert.equal(n.completeJournal,false);
});
