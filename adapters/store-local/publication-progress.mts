import {link, lstat, mkdir, readdir} from 'node:fs/promises';
import {resolve} from 'node:path';
import type {createPublicationContractStore, PublicationContract} from './publication-contract-store.mjs';
import type {createPublicationSemanticReader} from './publication-semantic-reader.mjs';
import type {validateConfiguration} from './publication-store-inputs.mjs';
import {exactKeys, fail, PublicationStoreError, readBounded} from './publication-store-io.mjs';

type CodedCause = Readonly<{code?: unknown; outcome?: unknown}>;
type PublicationAttemptData = Readonly<{publication_attempt_cid: string; run_definition_cid: string}>;
type PublicationProgressData = Readonly<{
  publication_attempt_cid: string;
  publication_record_cid: string;
  sequence: number;
  state: string;
}>;
type AdmittedAttempt<Contract> = Readonly<{contract: Contract; value: PublicationAttemptData}>;
type AdmittedProgressRecord<Contract> = Readonly<{contract: Contract; value: PublicationProgressData}>;
type PublicationProgressIndex = Readonly<{
  publicationAttempt(cid: string): unknown;
  latestPublicationRecord(cid: string): Readonly<{record_cid: string; sequence: number}> | undefined;
}>;
type ContractPorts<Contract extends PublicationContract> = ReturnType<typeof createPublicationContractStore<Contract>>;
type PublicationProgressPorts<Contract extends PublicationContract> = Pick<ContractPorts<Contract>,
  'admitContract' | 'parseContract' | 'admitPublicationContracts' | 'putAdmittedPublicationContract' |
  'putAdmittedPublicationContracts' | 'putNativePublicationContracts'> & Readonly<{
  active(): unknown;
  currentDeliveryIndex(): PublicationProgressIndex | undefined;
  runMetadataDeletionStarted(cid: string): Promise<boolean>;
  publicationAttemptPath(cid: string): string;
  contractPath(cid: string): string;
  syncDirectory(path: string): unknown;
  nativePublicationContract(name: string): boolean;
  readContract: ReturnType<typeof createPublicationSemanticReader<Contract>>['readContract'];
}>;

export function createPublicationProgress<Contract extends PublicationContract>(
  configuration: Pick<ReturnType<typeof validateConfiguration>, 'maxObjectBytes' | 'maxObjects'>,
  attemptsDirectory: string,
  recordNamePattern: RegExp,
  contractControl: Readonly<{recordTransition(previous: Contract | undefined, current: Contract, uncommittedConfirmed: boolean): unknown}>,
  {admitContract, parseContract, admitPublicationContracts, putAdmittedPublicationContract, putAdmittedPublicationContracts,
    putNativePublicationContracts, active, currentDeliveryIndex, runMetadataDeletionStarted, publicationAttemptPath, contractPath,
    syncDirectory, nativePublicationContract, readContract}: PublicationProgressPorts<Contract>,
) {
  const createAdmittedAttempt = async (admitted: Contract, retainedAttempt?: PublicationAttemptData) => {
    const attempt = retainedAttempt ?? parseContract(admitted) as PublicationAttemptData;
    if (await runMetadataDeletionStarted(attempt.run_definition_cid)) {
      fail('PublicationMetadataDeleted');
    }
    // An independently adopted file original keeps its legacy link protocol.
    // New attempts need no second physical copy or directory locator: their
    // exact CID is the existing native metadata primary key.
    let fileOriginal = false;
    try { await lstat(contractPath(admitted.identity)); fileOriginal = true; }
    catch (error) { if ((error as CodedCause | null | undefined)?.code !== 'ENOENT') throw error; }
    if (!fileOriginal) {
      const stored = (await putNativePublicationContracts([Object.freeze({contract:admitted,value:attempt})],
        Object.freeze({kind:'attempt',attemptCid:admitted.identity,runCid:attempt.run_definition_cid})))[0];
      return Object.freeze({attempt,created:stored.progressCreated});
    }
    const stored = await putAdmittedPublicationContract(admitted, attempt);
    const directory = publicationAttemptPath(
      attempt.publication_attempt_cid,
    );
    await mkdir(directory, {recursive: true, mode: 0o700});
    try {
      await link(contractPath(stored.semanticCid), resolve(directory, 'attempt.json'));
      await syncDirectory(directory);
      await syncDirectory(attemptsDirectory);
      return Object.freeze({attempt, created: true});
    } catch (error) {
      if ((error as CodedCause | null | undefined)?.code !== 'EEXIST') throw error;
      const existing = await readBounded(
        resolve(directory, 'attempt.json'), configuration.maxObjectBytes,
      );
      if (existing.toString('utf8') !== admitted.wire) {
        fail('PublicationAttemptConflict');
      }
      return Object.freeze({attempt, created: false});
    }
  };

  const createAttempt = async (suppliedWire: unknown) => {
    active();
    return createAdmittedAttempt(admitContract('publication_attempt', suppliedWire));
  };

  const beginPublicationAttempt = async (supplied: unknown, attemptOriginal: Contract, initialRecords?: unknown) => {
    if (!Array.isArray(supplied)) fail('InvalidPublicationContractWire');
    if (initialRecords !== undefined && (!Array.isArray(initialRecords) || initialRecords.length !== 2)) {
      fail('InvalidPublicationRecord');
    }
    if (supplied.length >= configuration.maxObjects) fail('PublicationStoreObjectLimit');
    const admitted = admitPublicationContracts([...supplied, attemptOriginal], true);
    const selected = admitted.find(({contract}) => contract.identity === attemptOriginal.identity &&
      contract.name === 'publication_attempt') as AdmittedAttempt<Contract> | undefined;
    if (selected === undefined) fail('InvalidPublicationContract');
    let records: readonly AdmittedProgressRecord<Contract>[] | undefined;
    if (initialRecords !== undefined) {
      records = admitPublicationContracts(initialRecords,true) as readonly AdmittedProgressRecord<Contract>[];
      if (records.length !== 2 || records.some(({contract}) => contract.name !== 'publication_record')) fail('InvalidPublicationRecord');
      const [first, second] = records;
      if (first.value.publication_attempt_cid !== selected.contract.identity ||
          second.value.publication_attempt_cid !== selected.contract.identity) fail('PublicationAttemptMismatch');
      if (first.value.sequence !== 0 || first.value.state !== 'preparing' ||
          second.value.sequence !== 1 || !['committing','cancelled'].includes(second.value.state) ||
          contractControl.recordTransition(undefined,first.contract,false) !== true ||
          contractControl.recordTransition(first.contract,second.contract,false) !== true) {
        fail('InvalidPublicationRecordTransition');
      }
      for (const record of records) {
        const prior=admitted.find(({contract})=>contract.identity===record.contract.identity);
        if (prior!==undefined && (prior.contract.name!==record.contract.name || prior.contract.wire!==record.contract.wire)) {
          fail('PublicationSemanticIdentityConflict');
        }
      }
    }
    if (await runMetadataDeletionStarted(selected.value.run_definition_cid)) fail('PublicationMetadataDeleted');
    let fileAttempt = false;
    try { await lstat(contractPath(selected.contract.identity)); fileAttempt = true; }
    catch (error) { if ((error as CodedCause | null | undefined)?.code !== 'ENOENT') throw error; }
    // Independently adopted file attempts keep their original file progress.
    // Only an all-native setup joins the bodies and attempt locator in one
    // existing transaction; either path returns after its actual acknowledgements.
    if (fileAttempt || admitted.some(({contract}) => !nativePublicationContract(contract.name))) {
      // Do not preinstall progress bodies as native metadata for a file-backed
      // attempt: its original append path must still create and ACK the files
      // that its sequence links select.
      try {
        await putAdmittedPublicationContracts(admitted, true);
      } catch (error) {
        // This original mutation contains setup only, not the proposed pair.
        // Its caller must confirm exactly that group after a lost reply.
        if (records !== undefined && error instanceof PublicationStoreError &&
            error.code === 'PublicationMetadataCommitOutcomeUnknown' && (error as PublicationStoreError & CodedCause).outcome === 'unknown') {
          Object.defineProperty(error,'publicationStartKind',{value:'setup'});
        }
        throw error;
      }
      const created = await createAdmittedAttempt(selected.contract, selected.value);
      if (records !== undefined && !(await readdir(publicationAttemptPath(selected.contract.identity)))
        .some(name => recordNamePattern.test(name))) await appendInitialPublicationRecords(initialRecords);
      return created;
    }
    const existingProgress = records !== undefined &&
      currentDeliveryIndex()!.publicationAttempt(selected.contract.identity) !== undefined &&
      currentDeliveryIndex()!.latestPublicationRecord(selected.contract.identity) !== undefined;
    const initial = existingProgress ? undefined : records;
    const combined = initial === undefined ? admitted : [...admitted,
      ...initial.filter(value => !admitted.some(({contract})=>contract.identity===value.contract.identity))];
    if (combined.length > configuration.maxObjects) fail('PublicationStoreObjectLimit');
    let stored;
    try {
      stored = await putAdmittedPublicationContracts(combined, true,
      Object.freeze({kind: initial === undefined ? 'attempt' : 'initial-attempt',
        attemptCid: selected.contract.identity, runCid: selected.value.run_definition_cid,
        ...(initial === undefined ? {} : {records:Object.freeze(initial.map(({contract,value},sequence)=>
          Object.freeze({previousCid:sequence === 0 ? null : records![0].contract.identity,
            recordCid:contract.identity,sequence:value.sequence})))})}));
    } catch (error) {
      if (existingProgress && error instanceof PublicationStoreError &&
          error.code === 'PublicationMetadataCommitOutcomeUnknown' && (error as PublicationStoreError & CodedCause).outcome === 'unknown') {
        Object.defineProperty(error,'publicationStartKind',{value:'setup'});
      }
      throw error;
    }
    return Object.freeze({attempt: selected.value,
      created: stored.find(value => value.semanticCid === selected.contract.identity)!.progressCreated});
  };

  const beginPublicationAttemptWithRecords = (supplied: unknown, attemptOriginal: Contract, records: unknown) => {
    if (!Array.isArray(records) || records.length !== 2) fail('InvalidPublicationRecord');
    return beginPublicationAttempt(supplied, attemptOriginal, records);
  };

  const latestRecordContract = async (attemptCid: string) => {
    active();
    if (currentDeliveryIndex()!.publicationAttempt(attemptCid) !== undefined) {
      const row = currentDeliveryIndex()!.latestPublicationRecord(attemptCid);
      if (row === undefined) return undefined;
      const selected = await readContract(row.record_cid,'publication_record') as AdmittedProgressRecord<Contract>;
      if (selected.value.publication_attempt_cid !== attemptCid || selected.value.sequence !== row.sequence) {
        fail('InvalidPublicationRecord');
      }
      return selected.contract;
    }
    const directory = publicationAttemptPath(attemptCid);
    const entries = await readdir(directory);
    if (entries.some(name => name !== 'attempt.json' &&
        !recordNamePattern.test(name))) {
      fail('InvalidPublicationRecord');
    }
    const names = entries
      .filter(name => recordNamePattern.test(name))
      .map(name => ({name, sequence: Number(name.slice(0, -5))}))
      .filter(value => Number.isSafeInteger(value.sequence))
      .sort((left, right) => left.sequence - right.sequence);
    if (names.length === 0) return undefined;
    for (let index = 0; index < names.length; index++) {
      if (names[index].sequence !== index) fail('PublicationRecordGap');
    }
    const bytes = await readBounded(
      resolve(directory, names.at(-1)!.name), configuration.maxObjectBytes,
    );
    try {
      return admitContract('publication_record', bytes.toString('utf8'));
    } catch (error) {
      fail('InvalidPublicationRecord', error);
    }
  };

  const latestRecord = async (attemptCid: string) => {
    const contract = await latestRecordContract(attemptCid);
    return contract === undefined ? undefined : parseContract(contract) as PublicationProgressData;
  };

  const appendRecord = async (suppliedWire: unknown, options: unknown = {}) => {
    active();
    if (!exactKeys(options, ['uncommittedConfirmed']) ||
        typeof options.uncommittedConfirmed !== 'boolean') {
      fail('InvalidPublicationRecordOptions');
    }
    const contract = admitContract('publication_record', suppliedWire);
    const record = parseContract(contract) as PublicationProgressData;
    const directory = publicationAttemptPath(
      record.publication_attempt_cid,
    );
    const attempt = (await readContract(
      record.publication_attempt_cid, 'publication_attempt',
    )).value as PublicationAttemptData;
    if (await runMetadataDeletionStarted(attempt.run_definition_cid)) {
      fail('PublicationMetadataDeleted');
    }
    const previous = await latestRecordContract(
      record.publication_attempt_cid,
    );
    if (contractControl.recordTransition(
      previous,
      contract,
      options.uncommittedConfirmed,
    ) !== true) {
      fail('InvalidPublicationRecordTransition');
    }
    if (attempt.publication_attempt_cid !== record.publication_attempt_cid) {
      fail('PublicationAttemptMismatch');
    }
    if (currentDeliveryIndex()!.publicationAttempt(record.publication_attempt_cid) !== undefined) {
      await putNativePublicationContracts([Object.freeze({contract,value:record})],Object.freeze({
        kind:'record',attemptCid:record.publication_attempt_cid,previousCid:previous?.identity ?? null,
        recordCid:contract.identity,sequence:record.sequence,
      }));
      return record;
    }
    await putAdmittedPublicationContract(contract, record);
    const target = resolve(directory, `${record.sequence}.json`);
    try { await link(contractPath(record.publication_record_cid), target); }
    catch (error) {
      if ((error as CodedCause | null | undefined)?.code === 'EEXIST') fail('PublicationRecordConflict');
      throw error;
    }
    await syncDirectory(directory);
    return record;
  };

  const appendInitialPublicationRecords = async (supplied: unknown) => {
    if (!Array.isArray(supplied) || supplied.length !== 2) fail('InvalidPublicationRecord');
    const admitted = admitPublicationContracts(supplied, true) as readonly AdmittedProgressRecord<Contract>[];
    if (admitted.length !== 2 || admitted.some(({contract})=>contract.name !== 'publication_record')) {
      fail('InvalidPublicationRecord');
    }
    const [first, second] = admitted;
    const attemptCid = first.value.publication_attempt_cid;
    if (second.value.publication_attempt_cid !== attemptCid) fail('PublicationAttemptMismatch');
    if (first.value.sequence !== 0 || first.value.state !== 'preparing' || second.value.sequence !== 1 ||
        !['committing','cancelled'].includes(second.value.state)) fail('InvalidPublicationRecord');
    const attempt = (await readContract(attemptCid, 'publication_attempt')).value as PublicationAttemptData;
    if (await runMetadataDeletionStarted(attempt.run_definition_cid)) fail('PublicationMetadataDeleted');
    const previous = await latestRecordContract(attemptCid);
    if (previous !== undefined || contractControl.recordTransition(undefined, first.contract, false) !== true ||
        contractControl.recordTransition(first.contract, second.contract, false) !== true) {
      fail('InvalidPublicationRecordTransition');
    }
    if (currentDeliveryIndex()!.publicationAttempt(attemptCid) === undefined) {
      // File-backed attempts keep their existing independently durable protocol.
      for (const {contract} of admitted) await appendRecord(contract.wire, {uncommittedConfirmed:false});
    } else {
      await putNativePublicationContracts(admitted, Object.freeze({kind:'initial-records',attemptCid,
        records:Object.freeze(admitted.map(({contract,value},sequence)=>Object.freeze({
          previousCid:sequence === 0 ? null : first.contract.identity,
          recordCid:contract.identity,sequence:value.sequence,
        })))}));
    }
    return second.value;
  };

  return {createAttempt, beginPublicationAttempt, beginPublicationAttemptWithRecords, latestRecordContract,
    latestRecord, appendRecord, appendInitialPublicationRecords};
}
