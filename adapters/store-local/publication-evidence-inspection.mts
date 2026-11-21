import {constructEffectfulPublication} from '../host-common/run-publication.mjs';
import type {createPhysicalHoldingReaders} from './physical-holding-record-reader.mjs';
import type {createPhysicalHoldingLifecycle} from './physical-holding-record-writer.mjs';
import type {createPublicationContractStore, PublicationContract} from './publication-contract-store.mjs';
import type {createPublicationIndexReader, PublicationIndexEntry} from './publication-index-reader.mjs';
import type {createPublicationMetadataInventory} from './publication-metadata-inventory.mjs';
import type {createDurableResultBindingVerifier} from './publication-result-reader.mjs';
import type {SemanticReader} from './publication-object-verifier.mjs';
import type {createPublicationSemanticReader} from './publication-semantic-reader.mjs';
import type {createPrivatePublicationEvidence} from './publication-store-private-evidence.mjs';
import {cidPattern, exactKeys, fail, quantity} from './publication-store-io.mjs';

type EvidenceContracts<Contract> = Readonly<{
  runDefinition: Contract;
  invocation: Contract;
  definitions: readonly Contract[];
  artifacts: readonly Contract[];
  derivations: readonly Contract[];
  orderings: readonly Contract[];
  retentions: readonly Contract[];
  durableBindings: readonly Contract[];
  manifest: Contract;
  capturedRun: Contract;
}>;
type Evidence<Contract> = EvidenceContracts<Contract> & Readonly<{receipt: Contract}>;
type EffectChain<Contract> = EvidenceContracts<Contract> & Readonly<{computationReceipt: Contract}>;
type Receipts = Readonly<{setWire: string; memberWires: readonly string[]; finalWire: string}>;
type PrivateBinding = Readonly<{name: string; semanticCid: string; holdingCid: string; wire: string}>;
type EvidenceIndexEntry = PublicationIndexEntry & Readonly<{publication_request_cid: string; publication_attempt_cid: string}>;
type RetainedIndex<Contract> = Readonly<{contract: Contract; entry: EvidenceIndexEntry}>;
type EffectInspection<Contract> = Readonly<{
  index: Contract;
  chain: EffectChain<Contract>;
  preview: unknown;
  receipts: Receipts;
  privateBinding: PrivateBinding;
  effectSources: readonly unknown[];
  recoveryResources?: Parameters<typeof constructEffectfulPublication>[0];
}>;
type ContractLimits = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
type ContentBinding = Readonly<{
  holdingCid: string; manifestCid: string; contentCid: string; byteCount: bigint; bindings: readonly PrivateBinding[];
}>;
type CaptureRecord = Readonly<{
  captured_run: unknown; run_definition: unknown; store_authority_cid: unknown; effect_dependency_payloads: unknown;
}>;
type EffectContext = Readonly<{effect_source_holding_cids?: Readonly<Record<string, unknown>>}>;
type EvidenceControl<Contract> = Readonly<{
  capturedContentGenerationCount?(captured: Contract): unknown;
  capturedContentGenerationStorage?(captured: Contract, definition: Contract, storeAuthorityCid: string, index: number): ContentBinding;
  effectFreeStoredCommitValid(
    runDefinition: Contract, invocation: Contract, definitions: readonly Contract[], artifacts: readonly Contract[],
    derivations: readonly Contract[], orderings: readonly Contract[], retentions: readonly Contract[],
    durableBindings: readonly Contract[], manifest: Contract, receipt: Contract, capturedRun: Contract,
    request: Contract, attempt: Contract, admitted: Contract, active: () => unknown,
  ): unknown;
  effectfulCommitValid?(chain: EffectChain<Contract>, preview: unknown, receipts: Receipts, request: Contract,
    attempt: Contract, index: Contract, limits: ContractLimits): boolean;
  effectPrivateEvidenceBinding?(preview: unknown, storeAuthorityCid: string): PrivateBinding;
  capturedEffectSourceHoldingCid?(source: unknown): string;
  capturedEffectSourceArtifactCid?(source: unknown): string;
  capturedEffectSourceStoreAuthorityCid?(source: unknown): string;
  effectComputationCaptureHoldingCid?(definition: Contract, storeAuthorityCid: string): string;
  effectComputationRecordHoldingCid?(definition: Contract, storeAuthorityCid: string): string;
  capturedEffectDependencyPayloadBindings(captured: Contract, payloads: unknown):
    readonly Readonly<{physical_cid: string; byte_count: number}>[];
}>;
type SemanticReaderPorts<Contract extends PublicationContract> = ReturnType<typeof createPublicationSemanticReader<Contract>>;
type ReadSemanticOriginal<Contract extends PublicationContract> = SemanticReaderPorts<Contract>['readSemanticOriginal'];
type NativeSelection<Contract extends PublicationContract> = NonNullable<Parameters<ReadSemanticOriginal<Contract>>[1]>;
type EvidenceRead<Contract extends PublicationContract> =
  (cid: string, includeNative: NativeSelection<Contract>, retained?: Contract) =>
    ReturnType<ReadSemanticOriginal<Contract>> | Awaited<ReturnType<ReadSemanticOriginal<Contract>>>;
type EvidencePorts<Contract extends PublicationContract> =
  Pick<ReturnType<typeof createPublicationContractStore<Contract>>, 'admitContract' | 'parseContract'> &
  Pick<SemanticReaderPorts<Contract>, 'readContract' | 'readSemanticOriginal'> &
  Pick<ReturnType<typeof createPublicationIndexReader<Contract>>, 'confirmCommittedIndex'> &
  Pick<ReturnType<typeof createPhysicalHoldingReaders>, 'inspectPhysicalHolding'> &
  Pick<ReturnType<typeof createPhysicalHoldingLifecycle>, 'commitPhysicalHolding'> &
  Pick<ReturnType<typeof createPrivatePublicationEvidence>, 'confirmPrivateEvidence' | 'readPrivateEvidence'> &
  Pick<ReturnType<typeof createPublicationMetadataInventory>, 'readCommittedMetadataInventory'> & Readonly<{
    active(): unknown;
    nativeContractRead(name: string): NativeSelection<Contract>;
    verifyDurableResultBinding: ReturnType<typeof createDurableResultBindingVerifier<Contract>>;
  }>;

export function createPublicationEvidence<Contract extends PublicationContract>(
  configuration: Readonly<{storeAuthorityCid: string}>,
  contractControl: EvidenceControl<Contract>,
  contractLimits: ContractLimits,
  activeSemanticReaders: Set<SemanticReader>,
  {active, admitContract, parseContract, readContract, readSemanticOriginal, nativeContractRead,
    verifyDurableResultBinding, confirmCommittedIndex, readCommittedMetadataInventory,
    inspectPhysicalHolding, commitPhysicalHolding, confirmPrivateEvidence, readPrivateEvidence}: EvidencePorts<Contract>,
) {
  const confirmCapturedContentHoldings = async (captured: Contract, definition: Contract) => {
    active();
    const context = parseContract(captured).effect_context as object;
    if (!Object.hasOwn(context, 'content_generations')) return Object.freeze([]);
    if (typeof contractControl.capturedContentGenerationCount !== 'function' ||
        typeof contractControl.capturedContentGenerationStorage !== 'function') {
      fail('PublicationContentInventoryUnsupported');
    }
    const count = contractControl.capturedContentGenerationCount(captured);
    if (!quantity(count) || count < 1) fail('PublicationContentInventoryInvalid');
    const cids = [];
    for (let index = 0; index < count; index++) {
      const binding = contractControl.capturedContentGenerationStorage(captured,
        definition, configuration.storeAuthorityCid, index);
      const holding = await inspectPhysicalHolding(binding.holdingCid);
      if (holding?.namespace !== 'content' ||
          holding.manifest_cid !== binding.manifestCid || holding.objects.length !== 1 ||
          holding.objects[0].cid !== binding.contentCid ||
          BigInt(holding.objects[0].byte_count) !== binding.byteCount) {
        fail('PublicationContentHoldingUnavailable');
      }
      await commitPhysicalHolding(holding, []);
      cids.push(binding.holdingCid);
      for (const proof of binding.bindings) {
        if (await confirmPrivateEvidence(proof) === undefined) {
          fail('PublicationContentEvidenceUnavailable');
        }
        cids.push(proof.holdingCid);
      }
    }
    if (new Set(cids).size !== cids.length) fail('PublicationContentInventoryInvalid');
    return Object.freeze(cids.sort());
  };

  const verifyCommitEvidence = async (
    admitted: Contract,
    entry: EvidenceIndexEntry,
    suppliedEvidence: Evidence<Contract>,
    required: ReadonlySet<string> | undefined,
    readOriginal: EvidenceRead<Contract> = (cid, includeNative) => readSemanticOriginal(cid, includeNative),
  ) => {
    if (!exactKeys(suppliedEvidence, [
      'runDefinition',
      'invocation',
      'definitions',
      'artifacts',
      'derivations',
      'orderings',
      'retentions',
      'durableBindings',
      'manifest',
      'receipt',
      'capturedRun',
    ]) || !Array.isArray(suppliedEvidence.definitions) ||
        suppliedEvidence.definitions.length === 0 ||
        !Array.isArray(suppliedEvidence.artifacts) ||
        suppliedEvidence.artifacts.length === 0 ||
        !Array.isArray(suppliedEvidence.derivations) ||
        !Array.isArray(suppliedEvidence.orderings) ||
        !Array.isArray(suppliedEvidence.retentions) ||
        !Array.isArray(suppliedEvidence.durableBindings) ||
        suppliedEvidence.durableBindings.length === 0) {
      fail('InvalidPublicationCommitEvidence');
    }
    const evidenceContracts: Contract[] = [
      suppliedEvidence.runDefinition,
      suppliedEvidence.invocation,
      ...suppliedEvidence.definitions,
      ...suppliedEvidence.artifacts,
      ...suppliedEvidence.derivations,
      ...suppliedEvidence.orderings,
      ...suppliedEvidence.retentions,
      ...suppliedEvidence.durableBindings,
      suppliedEvidence.manifest,
      suppliedEvidence.receipt,
      suppliedEvidence.capturedRun,
    ];
    for (const contract of evidenceContracts) {
      if (!exactKeys(contract, ['name', 'identityField', 'identity', 'wire']) ||
          typeof contract.name !== 'string' ||
          typeof contract.identityField !== 'string' ||
          !cidPattern.test(contract.identity) ||
          typeof contract.wire !== 'string' ||
          required !== undefined && !required.has(contract.identity)) {
        fail('InvalidPublicationCommitEvidence');
      }
      const persisted = (await readOriginal(contract.identity,
        nativeContractRead(contract.name), contract)).bytes;
      if (!persisted.equals(Buffer.from(contract.wire, 'utf8'))) {
        fail('PublicationCommitEvidenceMismatch');
      }
    }
    const verifiedBindings = [];
    for (const contract of suppliedEvidence.durableBindings) {
      verifiedBindings.push(await verifyDurableResultBinding(contract, readOriginal));
    }
    const attemptStored = await readContract(
      entry.publication_attempt_cid, 'publication_attempt', readOriginal,
    );
    const attempt = attemptStored.value as Readonly<{publication_request_cid: unknown; run_definition_cid: unknown}>;
    const requestStored = await readContract(
      entry.publication_request_cid, 'publication_request', readOriginal,
    );
    if (attempt.publication_request_cid !== entry.publication_request_cid ||
        attempt.run_definition_cid !== entry.run_definition_cid) {
      fail('PublicationAttemptMismatch');
    }
    let chainValid: unknown = false;
    // Same semantic-read custody as native inspection: close cannot release
    // this Store while its owned checker is suspended between quanta.
    const validationReader = {cleanup: undefined};
    activeSemanticReaders.add(validationReader);
    try {
      active();
      chainValid = await contractControl.effectFreeStoredCommitValid(
        suppliedEvidence.runDefinition,
        suppliedEvidence.invocation,
        suppliedEvidence.definitions,
        suppliedEvidence.artifacts,
        suppliedEvidence.derivations,
        suppliedEvidence.orderings,
        suppliedEvidence.retentions,
        suppliedEvidence.durableBindings,
        suppliedEvidence.manifest,
        suppliedEvidence.receipt,
        suppliedEvidence.capturedRun,
        requestStored.contract!,
        attemptStored.contract!,
        admitted,
        active,
      );
    } catch (error) {
      fail('InvalidPublicationCommitChain', error);
    } finally {
      // The fixed control cancels its exact checker before this promise unwinds.
      activeSemanticReaders.delete(validationReader);
    }
    if (chainValid !== true) fail('InvalidPublicationCommitChain');
    return Object.freeze(verifiedBindings);
  };

  const validateCommittedEvidence = async (
    suppliedIndex: unknown,
    suppliedEvidence: Evidence<Contract>,
  ) => {
    active();
    if (!exactKeys(suppliedIndex, [
      'name', 'identityField', 'identity', 'wire',
    ]) || suppliedIndex.name !== 'public_index_entry') {
      fail('InvalidCommittedPublicationIndex');
    }
    const admitted = admitContract('public_index_entry', suppliedIndex.wire);
    if (admitted.identity !== suppliedIndex.identity) {
      fail('InvalidCommittedPublicationIndex');
    }
    const entry = parseContract(admitted) as EvidenceIndexEntry;
    const key = {
      namespaceId: entry.namespace_id,
      authorityScopeCid: entry.authority_scope_cid,
      runDefinitionCid: entry.run_definition_cid,
    };
    const committed = await confirmCommittedIndex(key);
    if (committed?.public_index_entry_cid !== admitted.identity) {
      fail('InvalidCommittedPublicationIndex');
    }
    const verifiedBindings = await verifyCommitEvidence(
      admitted, entry, suppliedEvidence, undefined,
    );
    const expectedContent = await confirmCapturedContentHoldings(
      suppliedEvidence.capturedRun, suppliedEvidence.runDefinition);
    const inventory = await readCommittedMetadataInventory(committed);
    if (inventory?.physical_holding_cids.join('\0') !== expectedContent.join('\0')) {
      fail('InvalidPublicationMetadataInventoryStore');
    }
    return true;
  };

  // This is stored-evidence inspection, not physical row-outcome admission
  // or publication commit. The portable control admits the final reference
  // chain; the Store confirms its public bodies and private physical holdings.
  // A caller cannot use this result as an apply or commit permit.
  const inspectEffectfulStoredEvidence = async ({index, chain, preview,
    receipts, privateBinding, effectSources, recoveryResources}: EffectInspection<Contract>,
    readOriginal: EvidenceRead<Contract> = (cid, includeNative) => readSemanticOriginal(cid, includeNative),
    retainedIndex?: RetainedIndex<Contract>) => {
    active();
    if (typeof contractControl.effectfulCommitValid !== 'function' ||
        typeof contractControl.effectPrivateEvidenceBinding !== 'function' ||
        typeof contractControl.capturedEffectSourceHoldingCid !== 'function' ||
        typeof contractControl.capturedEffectSourceArtifactCid !== 'function' ||
        typeof contractControl.capturedEffectSourceStoreAuthorityCid !==
          'function' ||
        !exactKeys(chain, [
          'runDefinition', 'invocation', 'definitions', 'artifacts',
          'derivations', 'orderings', 'retentions', 'durableBindings',
          'manifest', 'computationReceipt', 'capturedRun',
        ]) || !(['definitions', 'artifacts', 'derivations', 'orderings',
          'retentions', 'durableBindings'] as const).every(name =>
          Array.isArray(chain[name])) ||
        !exactKeys(receipts, ['setWire', 'memberWires', 'finalWire']) ||
        typeof receipts.setWire !== 'string' ||
        typeof receipts.finalWire !== 'string' ||
        !Array.isArray(receipts.memberWires) ||
        receipts.memberWires.some(wire => typeof wire !== 'string') ||
        !Array.isArray(effectSources) ||
        !exactKeys(privateBinding, [
          'name', 'semanticCid', 'holdingCid', 'wire',
        ])) {
      fail('InvalidEffectfulStoredEvidence');
    }
    if (retainedIndex !== undefined && retainedIndex.contract !== index) {
      fail('InvalidEffectfulStoredEvidence');
    }
    const admittedIndex = retainedIndex === undefined
      ? admitContract('public_index_entry', index?.wire) : retainedIndex.contract;
    if (admittedIndex.identity !== index?.identity) {
      fail('InvalidEffectfulStoredEvidence');
    }
    const entry = retainedIndex === undefined ? parseContract(admittedIndex) as EvidenceIndexEntry : retainedIndex.entry;
    const request = (await readContract(
      entry.publication_request_cid, 'publication_request', readOriginal,
    )).contract!;
    const attempt = (await readContract(
      entry.publication_attempt_cid, 'publication_attempt', readOriginal,
    )).contract!;
    const finalReceipt = admitContract('run_receipt', receipts.finalWire);
    const setReceipt = admitContract(
      'effect_set_apply_receipt', receipts.setWire,
    );
    const memberReceipts = receipts.memberWires.map(wire =>
      admitContract('effect_apply_receipt', wire));
    const publicContracts: Contract[] = [chain.runDefinition, chain.invocation,
      ...chain.definitions, ...chain.artifacts, ...chain.derivations,
      ...chain.orderings, ...chain.retentions, ...chain.durableBindings,
      chain.manifest, chain.computationReceipt, chain.capturedRun,
      finalReceipt, setReceipt, ...memberReceipts];
    for (const contract of publicContracts) {
      if (!exactKeys(contract, [
        'name', 'identityField', 'identity', 'wire',
      ]) || !cidPattern.test(contract.identity) ||
          !(await readOriginal(contract.identity,
            nativeContractRead(contract.name), contract)).bytes.equals(
            Buffer.from(contract.wire, 'utf8'))) {
        fail('EffectfulCommitEvidenceMismatch');
      }
    }
    const validCommit = recoveryResources === undefined
      ? contractControl.effectfulCommitValid(chain, preview, receipts, request, attempt, admittedIndex, contractLimits)
      : constructEffectfulPublication(recoveryResources, chain.capturedRun, contractControl,
        contractControl.effectfulCommitValid, [chain, preview, receipts, request, attempt, admittedIndex, contractLimits]);
    if (validCommit !== true) {
      fail('InvalidEffectfulCommitChain');
    }
    const expectedPrivate = contractControl.effectPrivateEvidenceBinding(
      preview, configuration.storeAuthorityCid,
    );
    if (Object.keys(privateBinding).some(key =>
      privateBinding[key as keyof PrivateBinding] !== expectedPrivate[key as keyof PrivateBinding]) ||
        await confirmPrivateEvidence(privateBinding) === undefined) {
      fail('EffectfulPrivateEvidenceUnavailable');
    }
    const context = parseContract(chain.capturedRun).effect_context as EffectContext | undefined;
    const expectedHoldings = Object.values(
      context?.effect_source_holding_cids ?? {},
    );
    if (new Set(expectedHoldings).size !== expectedHoldings.length ||
        effectSources.length !== expectedHoldings.length) {
      fail('InvalidEffectfulSourceInventory');
    }
    const seen = new Set<string>();
    const sourceArtifactCids = [];
    const sourceSchemaCids = [];
    for (const source of effectSources) {
      const holdingCid = contractControl.capturedEffectSourceHoldingCid(source);
      const artifactCid = contractControl.capturedEffectSourceArtifactCid(source);
      if (seen.has(holdingCid) || !expectedHoldings.includes(holdingCid) ||
          contractControl.capturedEffectSourceStoreAuthorityCid(source) !==
            configuration.storeAuthorityCid) {
        fail('InvalidEffectfulSourceInventory');
      }
      seen.add(holdingCid);
      const holding = await inspectPhysicalHolding(holdingCid);
      if (holding?.namespace !== 'effect-source' ||
          holding.manifest_cid !== artifactCid) {
        fail('EffectfulSourceHoldingUnavailable');
      }
      const artifact = (await readContract(
        artifactCid, 'effect_source_artifact', readOriginal,
      )).value as Readonly<{result_schema_cid: string}>;
      await readOriginal(artifact.result_schema_cid, false);
      sourceArtifactCids.push(artifactCid);
      sourceSchemaCids.push(artifact.result_schema_cid);
      await commitPhysicalHolding(holding, []);
    }
    const verifiedBindings = [];
    for (const binding of chain.durableBindings) {
      verifiedBindings.push(await verifyDurableResultBinding(binding, readOriginal));
    }
    let captureHoldingCid;
    let captureRecordHoldingCid;
    let captureRecord: CaptureRecord | undefined;
    if (typeof contractControl.effectComputationCaptureHoldingCid ===
        'function') {
      const candidate = contractControl.effectComputationCaptureHoldingCid(
        chain.runDefinition, configuration.storeAuthorityCid,
      );
      const holding = await inspectPhysicalHolding(candidate);
      if (holding !== undefined) {
        const recordCid = contractControl.effectComputationRecordHoldingCid!(
          chain.runDefinition, configuration.storeAuthorityCid);
        try {
          captureRecord = await readPrivateEvidence(
            'effect_capture', chain.capturedRun.identity, recordCid,
            (_plaintext, read) => JSON.parse(read.releaseBytes()) as CaptureRecord,
          ) as CaptureRecord;
        } catch (error) {
          fail('InvalidEffectfulCaptureRecord', error);
        }
        if (captureRecord?.captured_run !== chain.capturedRun.wire ||
            captureRecord?.run_definition !== chain.runDefinition.wire ||
            captureRecord?.store_authority_cid !== configuration.storeAuthorityCid) {
          fail('InvalidEffectfulCaptureRecord');
        }
        const expected = new Map();
        for (const binding of chain.durableBindings) {
          const body = parseContract(binding);
          const prior = expected.get(body.material_generation_cid);
          if (prior !== undefined && prior !== body.byte_count) {
            fail('InvalidEffectfulCaptureHolding');
          }
          expected.set(body.material_generation_cid, body.byte_count);
        }
        for (const binding of contractControl.capturedEffectDependencyPayloadBindings(
          chain.capturedRun, captureRecord.effect_dependency_payloads)) {
          const previous = expected.get(binding.physical_cid);
          if (previous !== undefined && previous !== binding.byte_count) {
            fail('InvalidEffectfulCaptureHolding');
          }
          expected.set(binding.physical_cid, binding.byte_count);
        }
        if (holding.namespace !== 'effect-capture' ||
            holding.manifest_cid !== chain.capturedRun.identity ||
            holding.objects.length !== expected.size ||
            holding.objects.some(object =>
              expected.get(object.cid) !== object.byte_count)) {
          fail('InvalidEffectfulCaptureHolding');
        }
        await commitPhysicalHolding(holding, []);
        captureHoldingCid = candidate;
      }
    }
    if (typeof contractControl.effectComputationRecordHoldingCid ===
        'function') {
      const candidate = contractControl.effectComputationRecordHoldingCid(
        chain.runDefinition, configuration.storeAuthorityCid,
      );
      const holding = await inspectPhysicalHolding(candidate);
      if (holding !== undefined) {
        if (holding.namespace !== 'publication-private' ||
            holding.manifest_cid !== chain.capturedRun.identity ||
            holding.objects.length !== 1) {
          fail('InvalidEffectfulCaptureRecord');
        }
        let record;
        try {
          record = captureRecord ?? await readPrivateEvidence(
            'effect_capture', chain.capturedRun.identity, candidate,
            (_plaintext, read) => JSON.parse(read.releaseBytes()) as CaptureRecord,
          ) as CaptureRecord;
        } catch (error) {
          fail('InvalidEffectfulCaptureRecord', error);
        }
        if (record?.captured_run !== chain.capturedRun.wire ||
            record?.run_definition !== chain.runDefinition.wire ||
            record?.store_authority_cid !== configuration.storeAuthorityCid) {
          fail('InvalidEffectfulCaptureRecord');
        }
        captureRecordHoldingCid = candidate;
      }
    }
    return Object.freeze({index: admittedIndex, finalReceipt,
      verifiedBindings: Object.freeze(verifiedBindings),
      privateHoldingCid: privateBinding.holdingCid,
      captureHoldingCid, captureRecordHoldingCid,
      effectSourceHoldingCids: Object.freeze([...seen]),
      publicContractCids: Object.freeze(publicContracts.map(contract =>
        contract.identity)),
      sourceArtifactCids: Object.freeze(sourceArtifactCids),
      sourceSchemaCids: Object.freeze(sourceSchemaCids)});
  };

  return {confirmCapturedContentHoldings, verifyCommitEvidence, validateCommittedEvidence, inspectEffectfulStoredEvidence};
}
