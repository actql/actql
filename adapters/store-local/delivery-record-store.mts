import {link, mkdir, readdir} from 'node:fs/promises';
import {resolve} from 'node:path';
import type {openDeliveryAttemptIndex} from './delivery-attempt-index.mjs';
import type {createDeliveryAttemptStore, DeliveryAttemptData, DeliveryCompletionEntry,
  DeliveryRecordData, StoredProgress} from './delivery-attempt-store.mjs';
import type {createPublicationContractStore, PublicationContract} from './publication-contract-store.mjs';
import type {createPublicationSemanticReader} from './publication-semantic-reader.mjs';
import type {validateConfiguration} from './publication-store-inputs.mjs';
import {cidPattern, exactKeys, fail, readBounded} from './publication-store-io.mjs';

type CodedCause = Readonly<{code?: unknown}> | null | undefined;
type OriginalRecordRead<Contract> = {contract: Contract; bytes: Buffer | undefined};
type AdmittedCompletion<Contract> = Readonly<{attempt: Contract; receipt: Contract; record: DeliveryRecordData}>;
type DeliveryRecordIndex = Pick<Awaited<ReturnType<typeof openDeliveryAttemptIndex>>,
  'completion' | 'attempt' | 'confirmRecord' | 'complete'>;
type RecordPorts<Contract extends PublicationContract> = Pick<ReturnType<typeof createPublicationContractStore<Contract>>,
  'admitContract' | 'parseContract'> & Pick<ReturnType<typeof createPublicationSemanticReader<Contract>>,
  'readContract' | 'readSemanticBytes'> & Pick<ReturnType<typeof createDeliveryAttemptStore<Contract>>,
  'enqueueDeliveryAdmission' | 'readDeliveryAttemptContract'> & Readonly<{
  active(): unknown;
  currentDeliveryIndex(): DeliveryRecordIndex | undefined;
  contractPath(cid: string): string;
  deliveryAttemptPath(cid: string): string;
  exactUtf8WireMatches(bytes: Buffer, wire: string): boolean;
  syncDirectory(path: string): unknown;
  runMetadataDeletionStarted(cid: string): Promise<boolean>;
  putSemantic(wire: string, semanticCid: string): Promise<unknown>;
  putSemanticBatch(supplied: readonly Readonly<{wire: string; semanticCid: string}>[]): Promise<unknown>;
}>;

export function createDeliveryRecordStore<Contract extends PublicationContract>(
  configuration: Pick<ReturnType<typeof validateConfiguration>, 'maxObjectBytes'>,
  deliveriesDirectory: string,
  recordNamePattern: RegExp,
  contractControl: Readonly<{
    deliveryTransition(previous: Contract | undefined, current: Contract): unknown;
    deliverySuccessValid(attempt: Contract, receipt: Contract | undefined, record: Contract): unknown;
  }>,
  deliveryStarts: Map<string, StoredProgress<Contract>>,
  {active, currentDeliveryIndex, contractPath, deliveryAttemptPath, exactUtf8WireMatches, syncDirectory,
    runMetadataDeletionStarted, putSemantic, putSemanticBatch, admitContract, parseContract, enqueueDeliveryAdmission,
    readDeliveryAttemptContract, readContract, readSemanticBytes}: RecordPorts<Contract>,
) {
  // One bounded durability observation, not another admission.
  let lastConfirmedDeliveryRecord: string | undefined;

  const readLatestDeliveryRecordContract = async (
    attemptCid: string, original?: OriginalRecordRead<Contract>, retainedBirth?: Contract, retainedBirthValue?: DeliveryRecordData,
  ) => {
    active();
    const completed=currentDeliveryIndex()?.completion(attemptCid);
    if(completed!==undefined) {
      const retained=original?.contract;
      const contract=retained?.identity===completed.record_cid && retained.wire===completed.record_wire
        ? retained : admitContract('delivery_record',completed.record_wire);
      const record=parseContract(contract) as DeliveryRecordData;
      if(contract.identity!==completed.record_cid || record.delivery_attempt_cid!==attemptCid ||
          record.sequence!==1 || record.state!=='succeeded' || record.result_delivery_receipt_cid!==completed.receipt_cid) {
        fail('InvalidDeliveryAttemptIndex');
      }
      return contract;
    }
    const directory = deliveryAttemptPath(attemptCid);
    const row = currentDeliveryIndex()?.attempt(attemptCid);
    let initial;
    if (row?.initial_cid != null) {
      initial = retainedBirth ?? admitContract('delivery_record',row.initial_wire);
      const record = retainedBirthValue ?? parseContract(initial) as DeliveryRecordData;
      if (initial.identity !== row.initial_cid || initial.wire !== row.initial_wire ||
          record.delivery_attempt_cid !== attemptCid || record.sequence !== 0 || record.state !== 'streaming') {
        fail('InvalidDeliveryAttemptIndex');
      }
    }
    let entries: string[];
    try {entries = await readdir(directory);}
    catch(error) {if((error as CodedCause)?.code !== 'ENOENT' || initial === undefined) throw error; entries=[];}
    if (entries.some(name => name !== 'attempt.json' &&
        !recordNamePattern.test(name))) {
      fail('InvalidDeliveryRecord');
    }
    const names = entries
      .filter(name => recordNamePattern.test(name))
      .map(name => ({name, sequence: Number(name.slice(0, -5))}))
      .filter(value => Number.isSafeInteger(value.sequence))
      .sort((left, right) => left.sequence - right.sequence);
    if (names.length === 0) return initial;
    for (let index = 0; index < names.length; index++) {
      if (names[index].sequence !== index + (initial === undefined ? 0 : 1)) fail('DeliveryRecordGap');
    }
    const bytes = await readBounded(
      resolve(directory, names.at(-1)!.name), configuration.maxObjectBytes,
    );
    const retained = original?.contract;
    if (original !== undefined) original.bytes = bytes;
    // An append already admitted its immutable input. Equal canonical bytes
    // are the same fact in this operation, not a second contract admission.
    if (retained !== undefined && exactUtf8WireMatches(bytes, retained.wire)) {
      return retained;
    }
    try {
      return admitContract('delivery_record', bytes.toString('utf8'));
    } catch (error) {
      fail('InvalidDeliveryRecord', error);
    }
  };

  const latestDeliveryRecordContract = (attemptCid: string) =>
    readLatestDeliveryRecordContract(attemptCid);

  const latestDeliveryRecord = async (attemptCid: string) => {
    const contract = await latestDeliveryRecordContract(attemptCid);
    return contract === undefined ? undefined : parseContract(contract) as DeliveryRecordData;
  };

  const confirmDeliveryRecord = async (suppliedWire: unknown) => {
    active();
    const contract = admitContract('delivery_record', suppliedWire);
    const record = parseContract(contract) as DeliveryRecordData;
    return confirmAdmittedDeliveryRecord(contract, record, false);
  };

  const confirmAdmittedDeliveryRecord = async (contract: Contract, record: DeliveryRecordData, observed: boolean | Buffer | undefined) => {
    if(currentDeliveryIndex()?.confirmRecord(record.delivery_attempt_cid,contract.identity,contract.wire)===true) return record;
    const directory = deliveryAttemptPath(record.delivery_attempt_cid);
    const target = resolve(directory, `${record.sequence}.json`);
    let previousBytes = Buffer.isBuffer(observed) ? observed : undefined;
    const matches = (bytes: Buffer) => {
      if (exactUtf8WireMatches(bytes, contract.wire)) return true;
      // Preserve existing admission of another valid wire spelling. Only a
      // distinct acquired wire needs this fallback; identical rereads reuse it.
      const admitted = admitContract('delivery_record', bytes.toString('utf8'));
      return admitted.identity === contract.identity && admitted.wire === contract.wire;
    };
    if (observed === false) {
      let bytes;
      try { bytes = await readBounded(target, configuration.maxObjectBytes); }
      catch (error) {
        if ((error as CodedCause)?.code === 'ENOENT') fail('DeliveryRecordMissing', error);
        throw error;
      }
      if (!matches(bytes)) fail('DeliveryRecordConflict');
      previousBytes = bytes;
    }
    if (previousBytes !== undefined &&
        lastConfirmedDeliveryRecord === contract.identity) return record;
    // A directory entry may be visible before its containing directory is
    // durable. Unless this Store already confirmed this immutable record,
    // sync its directory and check the same original before acknowledging it.
    await syncDirectory(directory);
    const confirmed = await readBounded(
      target, configuration.maxObjectBytes,
    );
    // The input was admitted once. Trusted I/O and its directory ACK do not
    // require parsing/hashing identical bytes again; changed bytes still fail.
    if (!(previousBytes !== undefined && confirmed.equals(previousBytes)) &&
        !matches(confirmed)) {
      fail('DeliveryRecordDurabilityMismatch');
    }
    lastConfirmedDeliveryRecord = contract.identity;
    return record;
  };

  const appendDeliveryRecord = async (suppliedWire: unknown) => {
    active();
    const contract = admitContract('delivery_record', suppliedWire);
    return enqueueDeliveryAdmission(()=>appendAdmittedDeliveryRecord(contract));
  };

  const appendDeliveryCompletion = async (attempt: Contract, receipt: Contract, contract: Contract) => {
    active();
    for (const [original, name, identityField] of [
      [attempt, 'delivery_attempt', 'delivery_attempt_cid'],
      [receipt, 'result_delivery_receipt', 'result_delivery_receipt_cid'],
      [contract, 'delivery_record', 'delivery_record_cid'],
    ] as const) {
      if (!exactKeys(original, ['name', 'identityField', 'identity', 'wire']) ||
          !Object.isFrozen(original) || original.name !== name ||
          original.identityField !== identityField || !cidPattern.test(original.identity) ||
          typeof original.wire !== 'string' ||
          Buffer.byteLength(original.wire, 'utf8') > configuration.maxObjectBytes) {
        fail('InvalidDeliverySuccessEvidence');
      }
    }
    let valid = false;
    try { valid = contractControl.deliverySuccessValid(attempt, receipt, contract) === true; }
    catch (error) { fail('InvalidDeliverySuccessEvidence', error); }
    if (!valid) fail('InvalidDeliverySuccessEvidence');
    const record = parseContract(contract) as DeliveryRecordData;
    if (record.state !== 'succeeded') fail('InvalidDeliverySuccessEvidence');
    return enqueueDeliveryAdmission(()=>{
      const progress=deliveryStarts.get(attempt.identity), pending=progress?.completion;
      if(pending!==undefined) {
        if(pending.attempt!==attempt || pending.receipt!==receipt || pending.contract!==contract) {
          fail('ResultDeliveryAttemptUnresolved');
        }
        currentDeliveryIndex()!.complete(pending.entry);
        progress!.completion=undefined;
        return record;
      }
      return appendAdmittedDeliveryRecord(contract, {attempt, receipt, record});
    });
  };

  const appendAdmittedDeliveryRecord = async (contract: Contract, completion?: AdmittedCompletion<Contract>) => {
    const suppliedReceipt = completion?.receipt;
    const record = completion?.record ?? parseContract(contract) as DeliveryRecordData;
    const directory = deliveryAttemptPath(record.delivery_attempt_cid);
    const attemptContract = await readDeliveryAttemptContract(
      record.delivery_attempt_cid, completion?.attempt,
    );
    const attempt = parseContract(attemptContract) as DeliveryAttemptData;
    if (await runMetadataDeletionStarted(attempt.run_definition_cid)) {
      fail('PublicationMetadataDeleted');
    }
    const original: OriginalRecordRead<Contract> = {contract, bytes: undefined};
    const previous = await readLatestDeliveryRecordContract(
      record.delivery_attempt_cid, original,
    );
    if (completion !== undefined && attemptContract !== completion.attempt) {
      let valid = false;
      try {
        valid = record.state === 'succeeded' &&
          contractControl.deliverySuccessValid(attemptContract, suppliedReceipt, contract) === true;
      } catch (error) { fail('InvalidDeliverySuccessEvidence', error); }
      if (!valid) fail('InvalidDeliverySuccessEvidence');
    }
    if (previous?.identity === contract.identity) {
      if (suppliedReceipt !== undefined && !exactUtf8WireMatches(
        await readSemanticBytes(suppliedReceipt.identity), suppliedReceipt.wire,
      )) fail('InvalidDeliverySuccessEvidence');
      return confirmAdmittedDeliveryRecord(contract, record, original.bytes);
    }
    if (contractControl.deliveryTransition(previous, contract) !== true) {
      fail('InvalidDeliveryRecordTransition');
    }
    if (attempt.delivery_attempt_cid !== record.delivery_attempt_cid) {
      fail('DeliveryAttemptMismatch');
    }
    if (record.state === 'succeeded' && suppliedReceipt === undefined) {
      const receipt = (await readContract(
        record.result_delivery_receipt_cid!,
        'result_delivery_receipt',
      )).contract;
      if (contractControl.deliverySuccessValid(
        attemptContract, receipt, contract,
      ) !== true) {
        fail('InvalidDeliverySuccessEvidence');
      }
    }
    const native=currentDeliveryIndex()?.attempt(record.delivery_attempt_cid);
    if(completion!==undefined && record.sequence===1 && native?.initial_cid===previous?.identity) {
      const progress: StoredProgress<Contract>=deliveryStarts.get(record.delivery_attempt_cid) ?? {runCid:attempt.run_definition_cid,phase:'installed'};
      deliveryStarts.set(record.delivery_attempt_cid,progress);
      const entry=Object.freeze({attempt_cid:record.delivery_attempt_cid,prior_cid:previous!.identity,
        record_cid:contract.identity,record_wire:contract.wire,
        receipt_cid:suppliedReceipt!.identity,receipt_wire:suppliedReceipt!.wire});
      try {currentDeliveryIndex()!.complete(entry);}
      catch(error) {
        // Retain these SAME nominal inputs for storage-only finalization.
        // A retry cannot send again, reissue a receipt or replace this duty.
        progress.completion=Object.freeze({attempt:completion.attempt,receipt:suppliedReceipt!,contract,entry});
        throw error;
      }
      return record;
    }
    if (suppliedReceipt === undefined) await putSemantic(contract.wire, contract.identity);
    else await putSemanticBatch([suppliedReceipt, contract].map(value => ({
      wire: value.wire, semanticCid: value.identity,
    })));
    const target = resolve(directory, `${record.sequence}.json`);
    // Native START has no alias directory. Its first later record owns this
    // directory ACK; a failed ACK remains pending even when mkdir is visible.
    const start=deliveryStarts.get(record.delivery_attempt_cid);
    if(currentDeliveryIndex()?.attempt(record.delivery_attempt_cid)?.initial_cid != null &&
        start?.recordDirectoryAcknowledged !== true) {
      try {await mkdir(directory,{mode:0o700});}
      catch(error) {if((error as CodedCause)?.code!=='EEXIST') throw error;}
      await syncDirectory(deliveriesDirectory);
      const progress: StoredProgress<Contract>=start ?? {runCid:attempt.run_definition_cid,phase:'installed'};
      progress.recordDirectoryAcknowledged=true;
      deliveryStarts.set(record.delivery_attempt_cid,progress);
    }
    try { await link(contractPath(record.delivery_record_cid), target); }
    catch (error) {
      if ((error as CodedCause)?.code === 'EEXIST') fail('DeliveryRecordConflict');
      throw error;
    }
    return confirmAdmittedDeliveryRecord(contract, record, true);
  };

  return {readLatestDeliveryRecordContract, latestDeliveryRecordContract, latestDeliveryRecord,
    confirmDeliveryRecord, appendDeliveryRecord, appendDeliveryCompletion};
}
