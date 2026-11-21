import {createHash} from 'node:crypto';
import {lstat, readdir, rm} from 'node:fs/promises';
import {resolve} from 'node:path';
import type {createDeliveryAttemptStore, DeliveryAttemptData, DeliveryCompletionEntry,
  DeliveryRecordData, StoredProgress} from './delivery-attempt-store.mjs';
import type {createPublicationContractStore, PublicationContract} from './publication-contract-store.mjs';
import type {MetadataContractObject} from './publication-metadata-inventory.mjs';
import type {createPublicationObjectVerifier} from './publication-object-verifier.mjs';
import type {createPublicationSemanticReader} from './publication-semantic-reader.mjs';
import {cidPattern, fail, quantity, readBounded} from './publication-store-io.mjs';

type CodedCause = Readonly<{code?: unknown}> | null | undefined;
type PublicationAttempt = Readonly<{run_definition_cid: string; publication_request_cid: string}>;
type RunBoundContract = Readonly<{run_definition_cid: string}>;
type ResultBinding = Readonly<{result_definition_cid: string; material_generation_cid: string; byte_count: unknown}>;
type RetentionExtension = Readonly<{extension_retention_policy_cid: string}>;
type DeliveryPorts<Contract extends PublicationContract> = ReturnType<typeof createDeliveryAttemptStore<Contract>>;
type NativeRunIndex<Contract extends PublicationContract> = Readonly<{
  publicationAttemptsForRun(runCid: string): readonly Readonly<{attempt_cid: string}>[];
  publicationRecords(attemptCid: string): readonly Readonly<{record_cid: string}>[];
  run(runCid: string): readonly Parameters<DeliveryPorts<Contract>['admitDeliveryClaim']>[0][];
  completion(attemptCid: string): DeliveryCompletionEntry | undefined;
  forgetRun(runCid: string): unknown;
}>;
type RunMetadataDirectories = Readonly<{
  attemptsDirectory: string;
  deliveriesDirectory: string;
  manifestReadsDirectory: string;
  retentionExtensionsDirectory: string;
}>;
type RunMetadataPorts<Contract extends PublicationContract> =
  Pick<ReturnType<typeof createPublicationContractStore<Contract>>, 'admitContract' | 'parseContract'> &
  Pick<ReturnType<typeof createPublicationSemanticReader<Contract>>, 'readContract' | 'readSemanticOriginal'> &
  Pick<DeliveryPorts<Contract>, 'readDeliveryAttemptContract' | 'admitDeliveryClaim'> & Readonly<{
    currentDeliveryIndex(): NativeRunIndex<Contract> | undefined;
    publicationAttemptPath(cid: string): string;
    deliveryAttemptPath(cid: string): string;
    contractPath(cid: string): string;
    retentionExtensionDirectory(keyHash: string): string;
    syncDirectory(path: string): unknown;
    verifyObject: ReturnType<typeof createPublicationObjectVerifier>;
  }>;

export function createRunMetadataInventory<Contract extends PublicationContract>(
  configuration: Readonly<{maxObjectBytes: number}>,
  {attemptsDirectory, deliveriesDirectory, manifestReadsDirectory, retentionExtensionsDirectory}: RunMetadataDirectories,
  recordNamePattern: RegExp,
  deliveryStarts: Map<string, StoredProgress<Contract>>,
  contractControl: Readonly<{deliverySuccessValid(attempt: Contract, receipt: Contract, record: Contract): unknown}>,
  {currentDeliveryIndex, publicationAttemptPath, deliveryAttemptPath, contractPath, retentionExtensionDirectory,
    syncDirectory, verifyObject, admitContract, parseContract, readContract, readSemanticOriginal,
    readDeliveryAttemptContract, admitDeliveryClaim}: RunMetadataPorts<Contract>,
) {
  const collectRunMetadataContracts = async (
    runDefinitionCid: string,
    keyHash: string,
    initial: readonly string[],
  ) => {
    const collected = new Set(initial);
    for (const row of currentDeliveryIndex()!.publicationAttemptsForRun(runDefinitionCid)) {
      const attempt = (await readContract(row.attempt_cid,'publication_attempt')).value as PublicationAttempt;
      if (attempt.run_definition_cid !== runDefinitionCid) fail('PublicationAttemptMismatch');
      collected.add(row.attempt_cid);
      collected.add(attempt.publication_request_cid);
      for (const record of currentDeliveryIndex()!.publicationRecords(row.attempt_cid)) {
        const admitted = (await readContract(record.record_cid,'publication_record')).contract!;
        if (parseContract(admitted).publication_attempt_cid !== row.attempt_cid) fail('PublicationAttemptMismatch');
        collected.add(admitted.identity);
      }
    }
    // Native originals retire in the SAME indexed Run deletion transaction.
    // Identify their exact bodies without allocating temporary shadow files
    // or requiring spare object-file quota merely to delete native metadata.
    for (const row of currentDeliveryIndex()?.run(runDefinitionCid) ?? []) {
      if (row.initial_cid == null) continue;
      const {attemptContract,grantContract,streaming}=admitDeliveryClaim(row);
      for(const contract of [grantContract,attemptContract,streaming!]) collected.add(contract.identity);
      const completed=currentDeliveryIndex()!.completion(row.attempt_cid);
      if(completed!==undefined) {
        const record=admitContract('delivery_record',completed.record_wire);
        const receipt=admitContract('result_delivery_receipt',completed.receipt_wire);
        if(record.identity!==completed.record_cid || receipt.identity!==completed.receipt_cid ||
            contractControl.deliverySuccessValid(attemptContract,receipt,record)!==true) fail('InvalidDeliveryAttemptIndex');
        collected.add(record.identity);collected.add(receipt.identity);
      }
    }
    for (const name of await readdir(attemptsDirectory)) {
      if (!/^[0-9a-f]{64}$/u.test(name)) {
        fail('InvalidPublicationAttemptStore');
      }
      const attemptCid = `sha256:${name}`;
      const attempt = await readContract(attemptCid, 'publication_attempt') as Readonly<{value: PublicationAttempt}>;
      if (attempt.value.run_definition_cid !== runDefinitionCid) continue;
      collected.add(attemptCid);
      collected.add(attempt.value.publication_request_cid);
      const directory = publicationAttemptPath(attemptCid);
      for (const recordName of await readdir(directory)) {
        if (recordName === 'attempt.json') continue;
        if (!recordNamePattern.test(recordName)) {
          fail('InvalidPublicationRecord');
        }
        const record = admitContract(
          'publication_record',
          (await readBounded(
            resolve(directory, recordName), configuration.maxObjectBytes,
          )).toString('utf8'),
        );
        collected.add(record.identity);
      }
    }
    for (const name of await readdir(deliveriesDirectory)) {
      if (!/^[0-9a-f]{64}$/u.test(name)) {
        fail('InvalidDeliveryAttemptStore');
      }
      const attemptCid = `sha256:${name}`;
      const attempt = await readDeliveryAttemptContract(attemptCid);
      const value = parseContract(attempt) as DeliveryAttemptData;
      if (value.run_definition_cid !== runDefinitionCid) continue;
      collected.add(attemptCid);
      collected.add(value.result_read_grant_cid);
      const directory = deliveryAttemptPath(attemptCid);
      for (const recordName of await readdir(directory)) {
        if (recordName === 'attempt.json') continue;
        if (!recordNamePattern.test(recordName)) {
          fail('InvalidDeliveryRecord');
        }
        const record = admitContract(
          'delivery_record',
          (await readBounded(
            resolve(directory, recordName), configuration.maxObjectBytes,
          )).toString('utf8'),
        );
        const recordValue = parseContract(record) as DeliveryRecordData;
        collected.add(record.identity);
        if (recordValue.result_delivery_receipt_cid !== undefined) {
          collected.add(recordValue.result_delivery_receipt_cid);
        }
      }
    }
    for (const name of await readdir(manifestReadsDirectory)) {
      if (!/^[0-9a-f]{64}$/u.test(name)) {
        fail('InvalidManifestReadStore');
      }
      const grantCid = `sha256:${name}`;
      const grant = await readContract(grantCid, 'manifest_read_grant');
      if ((grant.value as RunBoundContract).run_definition_cid === runDefinitionCid) {
        collected.add(grantCid);
      }
    }
    const extensionRoot = retentionExtensionDirectory(keyHash);
    let resultDirectories: string[] = [];
    try { resultDirectories = await readdir(extensionRoot); }
    catch (error) {
      if ((error as CodedCause)?.code !== 'ENOENT') throw error;
    }
    for (const resultName of resultDirectories) {
      if (!/^[0-9a-f]{64}$/u.test(resultName)) {
        fail('InvalidPublicationRetentionExtensionStore');
      }
      const directory = resolve(extensionRoot, resultName);
      for (const recordName of await readdir(directory)) {
        if (!recordNamePattern.test(recordName)) {
          fail('InvalidPublicationRetentionExtensionStore');
        }
        let record: RetentionExtension;
        try {
          record = JSON.parse((await readBounded(
            resolve(directory, recordName), configuration.maxObjectBytes,
          )).toString('utf8'));
        } catch (error) {
          fail('InvalidPublicationRetentionExtensionStore', error);
        }
        if (!cidPattern.test(record?.extension_retention_policy_cid)) {
          fail('InvalidPublicationRetentionExtensionStore');
        }
        collected.add(record.extension_retention_policy_cid);
      }
    }
    return Object.freeze([...collected].sort());
  };

  type ReadOriginal = ReturnType<ReturnType<typeof createPublicationSemanticReader<Contract>>['readSemanticOriginal']>;
  const bindMetadataContractObjects = async (
    contractCids: readonly string[], readOriginal: (cid: string) => ReadOriginal | Awaited<ReadOriginal> = readSemanticOriginal,
  ) => {
    const objects: (MetadataContractObject & Readonly<{semantic_cid: string}>)[] = [];
    for (const semanticCid of contractCids) {
      const original = await readOriginal(semanticCid);
      if (original.publication === true) {
        objects.push(Object.freeze({semantic_cid:semanticCid,native:'sqlite',
          body_sha256:`sha256:${createHash('sha256').update(original.bytes).digest('hex')}`,
          byte_count:original.bytes.byteLength}));
        continue;
      }
      if(original.native !== undefined) {
        try {await lstat(contractPath(semanticCid));}
        catch(error) {if((error as CodedCause)?.code==='ENOENT') continue; throw error;}
        // Only an independently present real file enters the physical-file
        // inventory. Native body identity is never a fabricated file/ACK.
      }
      const bytes = original.bytes;
      const physicalCid = original.physicalCid ?? `sha256:${createHash('sha256')
        .update(bytes).digest('hex')}`;
      const physical = original.physicalCid === undefined
        ? await verifyObject(physicalCid) : {cid: physicalCid, bytes: bytes.byteLength};
      if (physical.bytes !== bytes.byteLength) {
        fail('PublicationContractCorrupt');
      }
      objects.push(Object.freeze({
        semantic_cid: semanticCid,
        physical_cid: physicalCid,
        byte_count: physical.bytes,
      }));
    }
    return Object.freeze(objects);
  };

  const metadataResultBindings = async (entry: Readonly<{durable_result_binding_cids: readonly string[]}>) => {
    const results = [];
    for (const bindingCid of entry.durable_result_binding_cids) {
      const binding = parseContract((await readContract(
        bindingCid, 'durable_result_binding',
      )).contract!) as ResultBinding;
      if (!quantity(binding.byte_count)) {
        fail('InvalidPublicationDurableBinding');
      }
      results.push(Object.freeze({
        result_definition_cid: binding.result_definition_cid,
        material_generation_cid: binding.material_generation_cid,
        byte_count: binding.byte_count,
      }));
    }
    return Object.freeze(results.sort((left, right) =>
      left.result_definition_cid.localeCompare(right.result_definition_cid)));
  };

  const removeRunMetadataDirectories = async (
    runDefinitionCid: string,
    keyHash: string,
  ) => {
    for (const name of await readdir(attemptsDirectory)) {
      if (!/^[0-9a-f]{64}$/u.test(name)) {
        fail('InvalidPublicationAttemptStore');
      }
      const attempt = await readContract(
        `sha256:${name}`, 'publication_attempt',
      );
      if ((attempt.value as RunBoundContract).run_definition_cid === runDefinitionCid) {
        await rm(resolve(attemptsDirectory, name), {
          recursive: true, force: false,
        });
      }
    }
    await syncDirectory(attemptsDirectory);
    for (const name of await readdir(deliveriesDirectory)) {
      if (!/^[0-9a-f]{64}$/u.test(name)) {
        fail('InvalidDeliveryAttemptStore');
      }
      const attempt = await readDeliveryAttemptContract(`sha256:${name}`);
      if (parseContract(attempt).run_definition_cid === runDefinitionCid) {
        await rm(resolve(deliveriesDirectory, name), {
          recursive: true, force: false,
        });
      }
    }
    await syncDirectory(deliveriesDirectory);
    currentDeliveryIndex()?.forgetRun(runDefinitionCid);
    for (const [attemptCid,progress] of deliveryStarts) {
      if (progress.runCid === runDefinitionCid) deliveryStarts.delete(attemptCid);
    }
    for (const name of await readdir(manifestReadsDirectory)) {
      if (!/^[0-9a-f]{64}$/u.test(name)) {
        fail('InvalidManifestReadStore');
      }
      const grant = await readContract(
        `sha256:${name}`, 'manifest_read_grant',
      );
      if ((grant.value as RunBoundContract).run_definition_cid === runDefinitionCid) {
        await rm(resolve(manifestReadsDirectory, name), {
          recursive: true, force: false,
        });
      }
    }
    await syncDirectory(manifestReadsDirectory);
    try {
      await rm(retentionExtensionDirectory(keyHash), {
        recursive: true, force: false,
      });
      await syncDirectory(retentionExtensionsDirectory);
    } catch (error) {
      if ((error as CodedCause)?.code !== 'ENOENT') throw error;
    }
  };

  return {collectRunMetadataContracts, bindMetadataContractObjects, metadataResultBindings, removeRunMetadataDirectories};
}
