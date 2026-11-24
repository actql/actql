import {link, lstat, mkdir, rename, rm} from 'node:fs/promises';
import {resolve} from 'node:path';
import type {WireRunRef} from '../../packages/client-wire/index.js';
import type {ActivePhysicalRecordWriter} from './physical-holding-record-writer.mjs';
import type {createPublicationContractStore, PublicationContract} from './publication-contract-store.mjs';
import type {createPublicationSemanticReader} from './publication-semantic-reader.mjs';
import type {validateConfiguration} from './publication-store-inputs.mjs';
import {cidPattern, exactKeys, fail, readBounded} from './publication-store-io.mjs';

type CodedCause = Readonly<{code?: unknown; cleanupHandle?: Readonly<{status?: unknown; retry?: unknown}>}> | null | undefined;
type CleanupStatus = ReturnType<NonNullable<ActivePhysicalRecordWriter['cleanup']>['status']>;
export type DeliveryAttemptData = Readonly<Record<string, unknown>> & Readonly<{
  delivery_attempt_cid: string;
  run_definition_cid: string;
  result_read_grant_cid: string;
  result_manifest_cid: string;
  result_name: string;
  result_artifact_cid: string;
  attempt_id: string;
}>;
type GrantData = Readonly<{
  namespace_id: string;
  authority_scope_cid: string;
  principal_id: string;
  purpose: string;
  run_definition_cid: string;
  result_manifest_cid: string;
  max_uses: number;
  results: readonly Readonly<{result_name: string; result_artifact_cid: string}>[];
}>;
export type DeliveryRecordData = Readonly<{
  delivery_record_cid: string;
  delivery_attempt_cid: string;
  sequence: number;
  state: string;
  result_delivery_receipt_cid?: string;
}>;
type DeliveryQuery = Readonly<{
  indexKey: WireRunRef;
  principalId: string;
  purpose: string;
  resultName: string;
  attemptId: string;
}>;
type ClaimRow = Readonly<{
  logical_key: string;
  attempt_cid: string;
  grant_cid: string;
  run_cid: string;
  attempt_wire: string;
  grant_wire: string;
}>;
type IndexedClaim = ClaimRow & Readonly<{ready: 0 | 1; initial_wire?: string | null; initial_cid?: string | null}>;
type Admitted<Contract, Data> = Readonly<{contract: Contract; value: Data}>;
type RecoveredClaim<Contract> = Readonly<{
  attemptContract: Contract;
  attempt: DeliveryAttemptData;
  grantContract: Contract;
  grant: GrantData;
  streaming?: Contract;
  streamingRecord?: DeliveryRecordData;
}>;
type DeliveryStart<Contract> = Readonly<{original: unknown; streaming: Contract}>;
export type DeliveryCompletionEntry = Readonly<{
  attempt_cid: string;
  prior_cid: string;
  record_cid: string;
  record_wire: string;
  receipt_cid: string;
  receipt_wire: string;
}>;
export type StoredProgress<Contract> = {
  runCid: string;
  phase: 'preparing' | 'installed' | 'failed';
  recordDirectoryAcknowledged?: boolean;
  completion?: Readonly<{attempt: Contract; receipt: Contract; contract: Contract; entry: DeliveryCompletionEntry}>;
};
type DeliveryClaimIndex = Readonly<{
  lookup(key: string): IndexedClaim | undefined;
  claim(row: ClaimRow, maxUses: number, initialWire?: string, initialCid?: string): Readonly<{created: boolean}>;
  finish(key: string, attemptCid: string): unknown;
}>;
type ReadDeliveryOriginal<Contract> = (original: unknown) => Readonly<{grant: Contract; attempt: Contract}>;
type SemanticRead<Contract extends PublicationContract> = ReturnType<typeof createPublicationSemanticReader<Contract>>;
type DeliveryAttemptPorts<Contract extends PublicationContract> = Pick<ReturnType<typeof createPublicationContractStore<Contract>>,
  'admitContract' | 'parseContract'> & Pick<SemanticRead<Contract>, 'nativeDeliveryContract' | 'readContract' | 'readSemanticBytes'> & Readonly<{
  active(): unknown;
  currentDeliveryIndex(): DeliveryClaimIndex | undefined;
  contractPath(cid: string): string;
  deliveryAttemptPath(cid: string): string;
  exactUtf8WireMatches(bytes: Buffer, wire: string): boolean;
  syncDirectory(path: string): unknown;
  runMetadataDeletionStarted(cid: string): Promise<boolean>;
  putSemanticBatch(supplied: readonly Readonly<{wire: string; semanticCid: string}>[]): Promise<unknown>;
  readLatestDeliveryRecordContract(
    attemptCid: string, original: undefined, retainedBirth?: Contract, retainedBirthValue?: DeliveryRecordData,
  ): Promise<Contract | undefined>;
}>;

export function createDeliveryAttemptStore<Contract extends PublicationContract>(
  configuration: Pick<ReturnType<typeof validateConfiguration>, 'maxObjectBytes'>,
  deliveriesDirectory: string,
  recordNamePattern: RegExp,
  contractControl: object,
  readDeliveryOriginal: ReadDeliveryOriginal<Contract> | undefined,
  deliveryStartTransition: (previous: undefined, current: Contract) => unknown,
  deliveryStarts: Map<string, StoredProgress<Contract>>,
  activePhysicalRecordWriters: Set<ActivePhysicalRecordWriter>,
  {active, currentDeliveryIndex, contractPath, deliveryAttemptPath, exactUtf8WireMatches, syncDirectory,
    runMetadataDeletionStarted, putSemanticBatch, admitContract, parseContract, nativeDeliveryContract, readContract,
    readSemanticBytes, readLatestDeliveryRecordContract}: DeliveryAttemptPorts<Contract>,
) {
  let deliveryAdmissionBusy: Promise<unknown> = Promise.resolve();

  const putDeliveryContracts = async (grant: Contract, attempt: Contract, streaming?: Contract) => {
    await putSemanticBatch([grant, attempt, ...(streaming === undefined ? [] : [streaming])].map(contract => ({
      wire: contract.wire, semanticCid: contract.identity,
    })));
  };

  const readFileDeliveryAttemptContract = async (attemptCid: string, retained?: Contract) => {
    const bytes = await readBounded(
      resolve(deliveryAttemptPath(attemptCid), 'attempt.json'),
      configuration.maxObjectBytes,
    );
    try {
      const contract = retained !== undefined && exactUtf8WireMatches(bytes, retained.wire)
        ? retained : admitContract('delivery_attempt', bytes.toString('utf8'));
      if (contract.identity !== attemptCid) fail('InvalidDeliveryAttempt');
      return contract;
    } catch (error) {
      fail('InvalidDeliveryAttempt', error);
    }
  };

  const readDeliveryAttemptContract = async (attemptCid: string, retained?: Contract) =>
    nativeDeliveryContract(attemptCid,'delivery_attempt',retained) ??
      readFileDeliveryAttemptContract(attemptCid,retained);

  const deliveryLogicalKey = (query: DeliveryQuery) => JSON.stringify([
    query.indexKey.namespaceId, query.indexKey.authorityScopeCid,
    query.indexKey.runDefinitionCid, query.principalId, query.purpose,
    query.resultName, query.attemptId,
  ]);
  const deliveryQuery = (attempt: DeliveryAttemptData, grant: GrantData) => ({
    indexKey: {namespaceId: grant.namespace_id, authorityScopeCid: grant.authority_scope_cid,
      runDefinitionCid: attempt.run_definition_cid},
    principalId: grant.principal_id, purpose: grant.purpose,
    resultName: attempt.result_name, attemptId: attempt.attempt_id,
  });
  const deliveryIndexRow = (
    attempt: DeliveryAttemptData, grant: GrantData, attemptContract: Contract, grantContract: Contract,
  ): ClaimRow => ({
    logical_key: deliveryLogicalKey(deliveryQuery(attempt, grant)),
    attempt_cid: attemptContract.identity, grant_cid: grantContract.identity,
    run_cid: attempt.run_definition_cid,
    attempt_wire: attemptContract.wire, grant_wire: grantContract.wire,
  });
  const installDeliveryAttempt = async (admitted: Contract, streaming?: Contract) => {
    const writer: ActivePhysicalRecordWriter = {cleanup: undefined, failed: false};
    activePhysicalRecordWriters.add(writer);
    let retainedChild = false;
    try {
      const target = deliveryAttemptPath(admitted.identity);
      const linkInitialRecord = async (directory: string) => {
        if (streaming === undefined) return;
        const path = resolve(directory, '0.json');
        try {await link(contractPath(streaming.identity), path);}
        catch (error) {
          if ((error as CodedCause)?.code !== 'EEXIST') throw error;
          if (!exactUtf8WireMatches(await readBounded(path, configuration.maxObjectBytes), streaming.wire)) {
            fail('DeliveryRecordConflict');
          }
        }
      };
      try {
        const retained = await readDeliveryAttemptContract(admitted.identity, admitted);
        if (retained.wire !== admitted.wire) fail('DeliveryAttemptConflict');
        await linkInitialRecord(target);
        await syncDirectory(target);
        await syncDirectory(deliveriesDirectory);
        return;
      } catch (error) { if ((error as CodedCause)?.code !== 'ENOENT') throw error; }
      // A pending claim determines its one original staging alias. Recovery can
      // revisit that alias without scanning unrelated directories on every open.
      const staging = resolve(deliveriesDirectory, `.staging-${admitted.identity.slice(7)}`);
      try { await mkdir(staging, {mode: 0o700}); }
      catch (error) {
        if ((error as CodedCause)?.code !== 'EEXIST') throw error;
        if (!(await lstat(staging)).isDirectory()) fail('InvalidDeliveryAttemptStore');
      }
      try {
        try { await link(contractPath(admitted.identity), resolve(staging, 'attempt.json')); }
        catch (error) {
          if ((error as CodedCause)?.code !== 'EEXIST') throw error;
          const bytes = await readBounded(resolve(staging,'attempt.json'),configuration.maxObjectBytes);
          if (!exactUtf8WireMatches(bytes,admitted.wire)) fail('DeliveryAttemptConflict');
        }
        await linkInitialRecord(staging);
        await syncDirectory(staging);
        await rename(staging, target);
        await syncDirectory(deliveriesDirectory);
      } catch (primary) {
        if ((primary as CodedCause)?.code !== 'EEXIST') throw primary;
        await rm(staging, {recursive: true, force: false});
        const retained = await readDeliveryAttemptContract(admitted.identity, admitted);
        if (retained.wire !== admitted.wire) fail('DeliveryAttemptConflict');
        await linkInitialRecord(target);
        await syncDirectory(target);
        await syncDirectory(deliveriesDirectory);
      }
    } catch (primary) {
      const child = (primary as CodedCause)?.cleanupHandle;
      if (child !== undefined) {
        const statusOriginal = child.status, retryOriginal = child.retry;
        let pending = true;
        let flight: Promise<CleanupStatus> | undefined;
        const status = () => Object.freeze({pending});
        writer.failed = retainedChild = true;
        writer.cleanup = Object.freeze({status,retry() {
          if (flight !== undefined) return flight;
          flight = Promise.resolve().then(async () => {
            if (!pending) return status();
            if (typeof statusOriginal !== 'function' || typeof retryOriginal !== 'function') {
              fail('PublicationStoreCleanupPending');
            }
            await Reflect.apply(retryOriginal,child,[]);
            const observation = await Reflect.apply(statusOriginal,child,[]);
            const descriptor = observation !== null && typeof observation === 'object'
              ? Object.getOwnPropertyDescriptor(observation,'pending') : undefined;
            if (descriptor?.value !== false) fail('PublicationStoreCleanupPending');
            pending = false;
            activePhysicalRecordWriters.delete(writer);
            return status();
          }).finally(() => { flight = undefined; });
          return flight;
        }});
      }
      throw primary;
    } finally {
      if (!retainedChild) activePhysicalRecordWriters.delete(writer);
    }
  };
  const admitDeliveryClaim = (
    row: IndexedClaim, suppliedAttempt?: Admitted<Contract, DeliveryAttemptData>, suppliedGrant?: Admitted<Contract, GrantData>,
  ) => {
    const attemptContract = suppliedAttempt?.contract.identity === row.attempt_cid && suppliedAttempt.contract.wire === row.attempt_wire
      ? suppliedAttempt.contract : admitContract('delivery_attempt', row.attempt_wire);
    const grantContract = suppliedGrant?.contract.identity === row.grant_cid && suppliedGrant.contract.wire === row.grant_wire
      ? suppliedGrant.contract : admitContract('result_read_grant', row.grant_wire);
    const attempt = attemptContract === suppliedAttempt?.contract ? suppliedAttempt!.value : parseContract(attemptContract) as DeliveryAttemptData;
    const grant = grantContract === suppliedGrant?.contract ? suppliedGrant!.value : parseContract(grantContract) as GrantData;
    const expected = deliveryIndexRow(attempt,grant,attemptContract,grantContract);
    if (Object.keys(expected).some(name => expected[name as keyof ClaimRow] !== row[name as keyof ClaimRow]) ||
        attempt.result_read_grant_cid !== grantContract.identity ||
        attempt.run_definition_cid !== grant.run_definition_cid ||
        attempt.result_manifest_cid !== grant.result_manifest_cid ||
        !grant.results.some(result => result.result_name === attempt.result_name &&
          result.result_artifact_cid === attempt.result_artifact_cid)) fail('InvalidDeliveryAttemptIndex');
    let streaming: Contract | undefined;
    let streamingRecord: DeliveryRecordData | undefined;
    if (row.initial_wire != null) {
      streaming = admitContract('delivery_record',row.initial_wire);
      const record = streamingRecord = parseContract(streaming) as DeliveryRecordData;
      if (row.initial_cid != null && streaming.identity !== row.initial_cid ||
          record.delivery_attempt_cid !== attemptContract.identity ||
          record.sequence !== 0 || record.state !== 'streaming' ||
          Reflect.apply(deliveryStartTransition,contractControl,[undefined,streaming]) !== true) {
        fail('InvalidDeliveryAttemptIndex');
      }
    }
    return {attemptContract,attempt,grantContract,grant,streaming,streamingRecord};
  };
  const restoreDeliveryClaim = async (row: IndexedClaim) => {
    const {attemptContract,attempt,grantContract,grant,streaming} = admitDeliveryClaim(row);
    await putDeliveryContracts(grantContract,attemptContract,streaming);
    await installDeliveryAttempt(attemptContract,streaming);
    if (row.ready === 0) currentDeliveryIndex()!.finish(row.logical_key,attemptContract.identity);
    return {attemptContract,attempt,grantContract,grant};
  };

  const enqueueDeliveryAdmission = <Result,>(action: () => Result | PromiseLike<Result>) => {
    active();
    const operation = deliveryAdmissionBusy.then(action);
    deliveryAdmissionBusy = operation.catch(() => {});
    return operation;
  };
  const createAdmittedDeliveryAttempt = async (admitted: Contract, grantContract: Contract, initial?: DeliveryStart<Contract>) => {
    const attempt = parseContract(admitted) as DeliveryAttemptData;
    const grant = parseContract(grantContract) as GrantData;
    if (await runMetadataDeletionStarted(attempt.run_definition_cid)) {
      fail('PublicationMetadataDeleted');
    }
    if (attempt.result_read_grant_cid !== grantContract.identity ||
        attempt.run_definition_cid !== grant.run_definition_cid ||
        attempt.result_manifest_cid !== grant.result_manifest_cid ||
        !grant.results.some(result => result.result_name === attempt.result_name &&
          result.result_artifact_cid === attempt.result_artifact_cid)) {
      fail('DeliveryGrantMismatch');
    }
    const {match: retained} = await selectDeliveryAttempt(
      deliveryQuery(attempt,grant), {contract: admitted, value: attempt},
      {contract: grantContract, value: grant}, false);
    if (retained !== undefined) {
      // Both originals were admitted. Compare every scalar field, restoring
      // only the selected birth/identity, rather than hash the same body again.
      const keys = Object.keys(attempt);
      if (keys.length !== Object.keys(retained.attempt).length ||
          keys.some(name => name !== 'requested_at' && name !== 'delivery_attempt_cid' &&
            attempt[name] !== retained.attempt[name])) fail('DeliveryAttemptConflict');
      return Object.freeze({attempt: retained.attempt, created: false});
    }
    if (currentDeliveryIndex() === undefined) fail('DeliveryAttemptIndexUnavailable');
    const row = deliveryIndexRow(attempt,grant,admitted,grantContract);
    const progress: StoredProgress<Contract> | undefined = initial === undefined ? undefined :
      {runCid:attempt.run_definition_cid,phase:'preparing'};
    if (progress !== undefined) deliveryStarts.set(admitted.identity,progress);
    try {
      const selected = currentDeliveryIndex()!.claim(row,grant.max_uses,initial?.streaming.wire,initial?.streaming.identity);
      if (!selected.created) fail('DeliveryAttemptConflict');
      // This SAME transaction owns uniqueness, use quota and the original
      // initial state. Its native COMMIT is the durable metadata original;
      // no duplicate contract file or alias ACK is required for joint START.
      // Legacy callers retain their original physical representation.
      if (initial === undefined) {
        await putDeliveryContracts(grantContract,admitted);
        await installDeliveryAttempt(admitted);
        currentDeliveryIndex()!.finish(row.logical_key,admitted.identity);
      } else progress!.phase = 'installed';
    } catch (error) {
      if (progress !== undefined) progress.phase = 'failed';
      throw error;
    }
    return Object.freeze(initial === undefined ? {attempt, created: true} :
      {original: initial.original, created: true});
  };
  const createDeliveryAttempt = (suppliedWire: unknown, suppliedGrantWire: unknown) => enqueueDeliveryAdmission(() =>
    createAdmittedDeliveryAttempt(admitContract('delivery_attempt', suppliedWire),
      admitContract('result_read_grant', suppliedGrantWire)));
  const beginDeliveryAttempt = (original: unknown, streaming: Contract) => {
    active();
    let facts;
    try {
      facts = Reflect.apply(readDeliveryOriginal!, contractControl, [original]);
      if (Reflect.apply(deliveryStartTransition, contractControl, [undefined, streaming]) !== true) {
        fail('InvalidDeliveryStartEvidence');
      }
    } catch (cause) {fail('InvalidDeliveryStartEvidence', cause);}
    for (const contract of [facts.grant, facts.attempt, streaming]) {
      if (!exactKeys(contract, ['name', 'identityField', 'identity', 'wire']) ||
          !Object.isFrozen(contract) || typeof contract.wire !== 'string' ||
          Buffer.byteLength(contract.wire, 'utf8') > configuration.maxObjectBytes) {
        fail('InvalidDeliveryStartEvidence');
      }
    }
    const record = parseContract(streaming) as DeliveryRecordData;
    if (streaming.name !== 'delivery_record' || record.delivery_attempt_cid !== facts.attempt.identity ||
        record.sequence !== 0 || record.state !== 'streaming') fail('InvalidDeliveryStartEvidence');
    return enqueueDeliveryAdmission(() => createAdmittedDeliveryAttempt(facts.attempt, facts.grant,
      {original, streaming}));
  };

  const lookupDeliveryAttempt = async (query: unknown) => {
    active();
    if (!exactKeys(query, [
      'indexKey', 'principalId', 'purpose', 'resultName', 'attemptId',
    ]) || !exactKeys(query.indexKey, [
      'namespaceId', 'authorityScopeCid', 'runDefinitionCid',
    ]) || typeof query.indexKey.namespaceId !== 'string' ||
        query.indexKey.namespaceId.length === 0 ||
        !cidPattern.test(query.indexKey.authorityScopeCid as string) ||
        !cidPattern.test(query.indexKey.runDefinitionCid as string) ||
        typeof query.principalId !== 'string' || !query.principalId ||
        typeof query.purpose !== 'string' || !query.purpose ||
        typeof query.resultName !== 'string' || !query.resultName ||
        typeof query.attemptId !== 'string' || !query.attemptId ||
        query.attemptId.length > 256) {
      fail('InvalidDeliveryAttemptLookup');
    }
    return (await selectDeliveryAttempt(query as DeliveryQuery)).match;
  };

  // The native index is complete before this Store escapes. Each public
  // selection reads only its exact target and referenced grant, never unrelated
  // attempt history. The same admission queue owns transactional claim changes.
  const selectDeliveryAttempt = async (
    query: DeliveryQuery, suppliedAttempt?: Admitted<Contract, DeliveryAttemptData>,
    suppliedGrant?: Admitted<Contract, GrantData>, includeProgress = true,
  ) => {
    if (currentDeliveryIndex() === undefined) fail('DeliveryAttemptIndexUnavailable');
    const key = deliveryLogicalKey(query);
    const row = currentDeliveryIndex()!.lookup(key);
    if (row === undefined) return {match: undefined};
    if (row.ready !== 1) fail('ResultDeliveryAttemptUnresolved');
    let recovered: RecoveredClaim<Contract> | undefined;
    if (row.initial_cid != null) {
      const progress = deliveryStarts.get(row.attempt_cid);
      if (progress !== undefined && progress.phase !== 'installed') fail('ResultDeliveryAttemptUnresolved');
      recovered = admitDeliveryClaim(row,suppliedAttempt,suppliedGrant);
    } else if (row.initial_wire != null) {
      let progress = deliveryStarts.get(row.attempt_cid);
      if (progress === undefined) {
        // Recovery is target-specific, not an O(history) ordinary-open pass.
        // Latch before any await/reentry and retain failure for this lifetime.
        progress = {runCid:row.run_cid,phase:'preparing'};
        deliveryStarts.set(row.attempt_cid,progress);
        try {
          if (await runMetadataDeletionStarted(row.run_cid)) fail('PublicationMetadataDeleted');
          recovered = await restoreDeliveryClaim(row);
          progress.phase = 'installed';
        } catch (error) { progress.phase = 'failed'; throw error; }
      } else if (progress.phase !== 'installed') fail('ResultDeliveryAttemptUnresolved');
    }
    const attemptContract = recovered?.attemptContract ?? await readDeliveryAttemptContract(
      row.attempt_cid, suppliedAttempt?.contract);
    const attempt = recovered?.attempt ?? (attemptContract === suppliedAttempt?.contract
      ? suppliedAttempt!.value : parseContract(attemptContract) as DeliveryAttemptData);
    let grantContract: Contract;
    let grant: GrantData;
    if (recovered !== undefined) {
      grantContract = recovered.grantContract;
      grant = recovered.grant;
    } else if (suppliedGrant?.contract.identity === row.grant_cid) {
      const bytes = await readSemanticBytes(row.grant_cid);
      grantContract = exactUtf8WireMatches(bytes,suppliedGrant.contract.wire)
        ? suppliedGrant.contract : admitContract('result_read_grant',bytes.toString('utf8'));
      grant = grantContract === suppliedGrant.contract ? suppliedGrant!.value : parseContract(grantContract) as GrantData;
    } else {
      const original = await readContract(row.grant_cid,'result_read_grant');
      grantContract = original.contract!;
      grant = original.value as GrantData;
    }
    const expected = deliveryIndexRow(attempt,grant,attemptContract,grantContract);
    if (Object.keys(expected).some(name => expected[name as keyof ClaimRow] !== row[name as keyof ClaimRow]) ||
        attempt.result_read_grant_cid !== row.grant_cid ||
        grant.run_definition_cid !== attempt.run_definition_cid ||
        grant.result_manifest_cid !== attempt.result_manifest_cid) {
      fail('InvalidDeliveryAttemptIndex');
    }
    const recordContract = includeProgress ? await readLatestDeliveryRecordContract(
      attemptContract.identity,undefined,row.initial_cid == null ? undefined : recovered!.streaming,
      row.initial_cid == null ? undefined : recovered!.streamingRecord) : undefined;
    const record = recordContract === undefined ? undefined : recordContract === recovered?.streaming
      ? recovered!.streamingRecord : parseContract(recordContract) as DeliveryRecordData;
    const hostReleaseReceipt = record?.result_delivery_receipt_cid === undefined
      ? undefined : (await readContract(record.result_delivery_receipt_cid,
        'result_delivery_receipt')).value;
    return {match: Object.freeze({attempt,record,hostReleaseReceipt})};
  };

  return {readFileDeliveryAttemptContract, readDeliveryAttemptContract, deliveryIndexRow, admitDeliveryClaim, restoreDeliveryClaim,
    enqueueDeliveryAdmission, createDeliveryAttempt, beginDeliveryAttempt, lookupDeliveryAttempt, selectDeliveryAttempt};
}
