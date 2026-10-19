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
  assert.equal(value.activeVm.eachTranslatedDataPayloadRequestUpper,8436090n);
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
