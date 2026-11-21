import {createHash} from 'node:crypto';
import type {WireRunRef} from '../../packages/client-wire/index.js';
import type {createPublicationContractStore, PublicationContract} from './publication-contract-store.mjs';
import type {IndexReadDemand} from './publication-index-reader.mjs';
import type {createPublicationObjectConsumer} from './publication-object-consumer.mjs';
import type {createPublicationObjectVerifier} from './publication-object-verifier.mjs';
import type {createPublicationResultMetadata} from './publication-result-metadata.mjs';
import type {createPublicationSemanticReader} from './publication-semantic-reader.mjs';
import {indexKey} from './publication-store-inputs.mjs';
import {exactKeys, fail, quantity} from './publication-store-io.mjs';

type DurableResultBinding = Readonly<{
  store_authority_cid: string;
  physical_sha256: string;
  material_generation_cid: string;
  byte_count: number;
  result_schema_cid: string;
  logical_result_cid: string;
  result_fields: readonly string[];
  row_count: number;
}>;

type ReadOriginal<Contract extends PublicationContract> =
  ReturnType<typeof createPublicationSemanticReader<Contract>>['readSemanticOriginal'];
type VerifyPorts<Contract extends PublicationContract> =
  Pick<ReturnType<typeof createPublicationContractStore<Contract>>, 'parseContract'> & Readonly<{
    readSemanticOriginal: ReadOriginal<Contract>;
    cidHex(value: unknown): string;
    verifyObject: ReturnType<typeof createPublicationObjectVerifier>;
  }>;

export function createDurableResultBindingVerifier<Contract extends PublicationContract>(
  configuration: Readonly<{storeAuthorityCid: string}>,
  {parseContract, readSemanticOriginal, cidHex, verifyObject}: VerifyPorts<Contract>,
) {
  const verifyDurableResultBinding = async (
    contract: Contract, readOriginal: ReadOriginal<Contract> = readSemanticOriginal,
    retainedBinding?: DurableResultBinding, readDemand?: IndexReadDemand<Contract>,
  ) => {
    if (contract.name !== 'durable_result_binding') {
      fail('InvalidPublicationCommitEvidence');
    }
    // Only the private selected reader supplies this same already parsed
    // body. Other internal callers still interpret their own contract here.
    const binding = retainedBinding === undefined ? parseContract(contract) as DurableResultBinding : retainedBinding;
    if (binding.store_authority_cid !== configuration.storeAuthorityCid ||
        binding.physical_sha256 !== cidHex(binding.material_generation_cid)) {
      fail('PublicationDurableBindingMismatch');
    }
    const physical = await verifyObject(binding.material_generation_cid, readDemand);
    readDemand?.finish();
    if (physical.bytes !== binding.byte_count) {
      fail('PublicationDurableBindingMismatch');
    }
    const original = await readOriginal(binding.result_schema_cid, false);
    const schemaBytes = original.bytes;
    const schemaCid = original.physicalCid ?? `sha256:${createHash('sha256')
      .update(schemaBytes).digest('hex')}`;
    if (schemaCid !== binding.result_schema_cid) {
      fail('PublicationDurableBindingMismatch');
    }
    const schemaWire = schemaBytes.toString('utf8');
    let schema;
    try { schema = JSON.parse(schemaWire); }
    catch (error) { fail('PublicationDurableBindingMismatch', error); }
    if (schema === null || typeof schema !== 'object' ||
        Array.isArray(schema) || !Array.isArray(binding.result_fields) ||
        binding.result_fields.length !== Object.keys(schema).length ||
        binding.result_fields.some(field =>
          typeof field !== 'string' ||
          !Object.prototype.hasOwnProperty.call(schema, field))) {
      fail('PublicationDurableBindingMismatch');
    }
    if (readDemand !== undefined) {
      let units = schemaWire.length;
      for (const field of binding.result_fields) units += field.length;
      // The temporary JS schema tree is not part of the returned metadata.
      // Its exact wire and the field-name holding survive until use completes.
      readDemand.data(9, 2 + binding.result_fields.length, units);
      readDemand.finish();
    }
    return Object.freeze({
      binding,
      physical,
      schema: Object.freeze({
        cid: schemaCid,
        wire: schemaWire,
      }),
    });
  };

  return verifyDurableResultBinding;
}

type ResultMetadataPorts<Contract extends PublicationContract> =
  ReturnType<typeof createPublicationResultMetadata<Contract>>;
type SelectedBinding<Contract extends PublicationContract> =
  Awaited<ReturnType<ResultMetadataPorts<Contract>['requireCommittedResultBinding']>> &
  Readonly<{value: DurableResultBinding}>;
type ResultReaderPorts<Contract extends PublicationContract> =
  Pick<ResultMetadataPorts<Contract>, 'requireCommittedResultBinding' | 'requireResultNotDeleted'> & Readonly<{
    readSemanticOriginal: ReadOriginal<Contract>;
    active(): unknown;
    cidHex(value: unknown): string;
    consumeObject: ReturnType<typeof createPublicationObjectConsumer>;
    verifyDurableResultBinding: ReturnType<typeof createDurableResultBindingVerifier<Contract>>;
  }>;
type ResultReadRequest = Readonly<WireRunRef & {resultDefinitionCid: string}>;
type ResultReadIdentity = Readonly<{
  durableResultBindingCid: string;
  logicalResultCid: string;
  resultSchemaCid: string;
}>;
type ResultReadMetadata = ResultReadIdentity & Readonly<{
  resultSchemaWire: string;
  resultFields: readonly string[];
  rowCount: number;
  payloadBytes: number;
}>;
type Authorize = (facts: ResultReadRequest | (ResultReadRequest & ResultReadIdentity)) => unknown;
type ConsumeBytes = (accept: (chunk: Buffer) => unknown) => Promise<Readonly<{cid: string; bytes: number}>>;
type FrameLimits = Readonly<{maxRowBytes: number; maxDepth: number; maxFrameBytes: number}>;
type FramePreparation = FrameLimits & Readonly<{maxBytes: number; maxRows: number}>;
type FrameSummary = Readonly<{bytes: number; rows: number}>;
type FrameControl<Frames> = Readonly<{
  prepareDurableResultRowFrames(limits: FramePreparation): Frames;
  prepareGrowingDurableResultRowFrames?(limits: FramePreparation): Frames;
  durableResultRowFrameGrowth?(frames: Frames, bytes: number): number;
  growDurableResultRowFrameBuffer?(frames: Frames, bytes: number): unknown;
  feedDurableResultRowFrames(frames: Frames, chunk: Uint8Array): Iterable<string>;
  finishDurableResultRowFrames(frames: Frames): FrameSummary;
  cancelDurableResultRowFrames(frames: Frames): unknown;
}>;
type ReadRows = (accept: (row: string, index: number) => unknown,
  beforeBufferGrowth?: (required: number) => number | PromiseLike<number>) => Promise<FrameSummary>;

export function createCommittedResultReaders<Contract extends PublicationContract>(
  activeResultReaders: Map<string, number>,
  {active, cidHex, consumeObject, readSemanticOriginal, verifyDurableResultBinding,
    requireCommittedResultBinding, requireResultNotDeleted}: ResultReaderPorts<Contract>,
) {
  const withCommittedResult = async <Result,>(
    key: WireRunRef,
    resultDefinitionCid: string,
    authorize: Authorize,
    use: (metadata: ResultReadMetadata, consume: ConsumeBytes) => Result | PromiseLike<Result>,
    readDemand?: IndexReadDemand<Contract>,
  ) => {
    active();
    cidHex(resultDefinitionCid);
    if (typeof authorize !== 'function' || typeof use !== 'function') {
      fail('InvalidPublicationObjectConsumer');
    }
    const request = Object.freeze({...key, resultDefinitionCid});
    if (authorize(request) !== true) fail('PublicationLookupDenied');
    const selected = await requireCommittedResultBinding(
      key, resultDefinitionCid, undefined, readDemand,
    ) as SelectedBinding<Contract>;
    const keyHash = indexKey(key);
    await requireResultNotDeleted(
      keyHash, selected, resultDefinitionCid, readDemand,
    );
    const authorization = Object.freeze({
      ...request,
      durableResultBindingCid: selected.contract.identity,
      logicalResultCid: selected.value.logical_result_cid,
      resultSchemaCid: selected.value.result_schema_cid,
    });
    if (authorize(authorization) !== true) fail('PublicationLookupDenied');
    const materialCid = selected.value.material_generation_cid;
    activeResultReaders.set(
      materialCid, (activeResultReaders.get(materialCid) ?? 0) + 1,
    );
    let scopeActive = true, physicalReadPending = false, readerRetired = false;
    const retireReader = () => {
      if (scopeActive || physicalReadPending || readerRetired) return;
      readerRetired = true;
      const remaining = (activeResultReaders.get(materialCid) ?? 1) - 1;
      if (remaining === 0) activeResultReaders.delete(materialCid);
      else activeResultReaders.set(materialCid, remaining);
    };
    try {
      const verified = await verifyDurableResultBinding(selected.contract,
        (cid, includeNative) => readSemanticOriginal(cid, includeNative, false, undefined, readDemand), selected.value, readDemand);
      await requireResultNotDeleted(
        keyHash, selected, resultDefinitionCid, readDemand,
      );
      const metadata = Object.freeze({
        durableResultBindingCid: selected.contract.identity,
        logicalResultCid: verified.binding.logical_result_cid,
        resultSchemaCid: verified.binding.result_schema_cid,
        resultSchemaWire: verified.schema.wire,
        resultFields: Object.freeze([...verified.binding.result_fields]),
        rowCount: verified.binding.row_count,
        payloadBytes: verified.physical.bytes,
      });
      let scopeOpen = true;
      let consumed = false;
      const consume: ConsumeBytes = async accept => {
        if (!scopeOpen || consumed || typeof accept !== 'function') {
          fail('InvalidPublicationObjectConsumer');
        }
        consumed = true;
        physicalReadPending = true;
        return consumeObject(materialCid, accept, () => {
          // Scope completion alone is not the consuming FD's close ACK.
          // A failed close keeps this same reader until its original cleanup
          // callback acknowledges retirement, without reopening or rereading.
          physicalReadPending = false;
          retireReader();
        });
      };
      try { return await use(metadata, consume); }
      finally { scopeOpen = false; }
    } finally {
      scopeActive = false;
      retireReader();
    }
  };

  const consumeCommittedResult = async (
    key: WireRunRef,
    resultDefinitionCid: string,
    authorize: Authorize,
    accept: Parameters<ConsumeBytes>[0],
  ) => withCommittedResult(
    key,
    resultDefinitionCid,
    authorize,
    async (metadata, consume) => {
      const consumed = await consume(accept);
      return Object.freeze({
        durableResultBindingCid: metadata.durableResultBindingCid,
        logicalResultCid: metadata.logicalResultCid,
        resultSchemaCid: metadata.resultSchemaCid,
        resultSchemaWire: metadata.resultSchemaWire,
        resultFields: metadata.resultFields,
        rowCount: metadata.rowCount,
        bytes: consumed.bytes,
      });
    },
  );

  const withCommittedResultRows = async <Frames, Result,>(
    key: WireRunRef,
    resultDefinitionCid: string,
    authorize: Authorize,
    frameLimits: FrameLimits,
    use: (metadata: ResultReadMetadata, readRows: ReadRows) => Result | PromiseLike<Result>,
    frameControl: FrameControl<Frames>,
    _attemptIdentity?: unknown,
    readDemand?: IndexReadDemand<Contract>,
  ) => {
    if (!exactKeys(frameLimits, [
      'maxRowBytes', 'maxDepth', 'maxFrameBytes',
    ]) || !Object.values(frameLimits).every(quantity) ||
        typeof use !== 'function' || frameControl === null ||
        typeof frameControl !== 'object' ||
        typeof frameControl.prepareDurableResultRowFrames !== 'function' ||
        typeof frameControl.feedDurableResultRowFrames !== 'function' ||
        typeof frameControl.finishDurableResultRowFrames !== 'function' ||
        typeof frameControl.cancelDurableResultRowFrames !== 'function') {
      fail('InvalidPublicationRowConsumer');
    }
    return withCommittedResult(
      key,
      resultDefinitionCid,
      authorize,
      async (metadata, consume) => {
        let scopeOpen = true;
        let rowsConsumed = false;
        const readRows: ReadRows = async (accept, beforeBufferGrowth) => {
          if (!scopeOpen || rowsConsumed || typeof accept !== 'function') {
            fail('InvalidPublicationRowConsumer');
          }
          rowsConsumed = true;
          const growing = readDemand !== undefined;
          if (growing && (typeof beforeBufferGrowth !== 'function' ||
              (['prepareGrowingDurableResultRowFrames', 'durableResultRowFrameGrowth',
                'growDurableResultRowFrameBuffer'] as const).some(name => typeof frameControl[name] !== 'function'))) {
            fail('InvalidPublicationRowConsumer');
          }
          const prepareFrames = growing ? frameControl.prepareGrowingDurableResultRowFrames
            : frameControl.prepareDurableResultRowFrames;
          const frames = Reflect.apply(prepareFrames!, frameControl, [{
            maxBytes: metadata.payloadBytes,
            maxRows: metadata.rowCount,
            maxRowBytes: frameLimits.maxRowBytes,
            maxDepth: frameLimits.maxDepth,
            maxFrameBytes: frameLimits.maxFrameBytes,
          }]);
          let rowIndex = 0, frameCapacity = 0;
          try {
            const physical = await consume(async chunk => {
              if (growing) {
                const needed = frameControl.durableResultRowFrameGrowth!(frames, chunk.byteLength);
                if (needed > frameCapacity) {
                  // The original delivery owner flushes staged output and
                  // grows its SAME READ parent before old/new row backing.
                  const admitted = await beforeBufferGrowth!(needed);
                  if (!Number.isSafeInteger(admitted) || admitted < needed ||
                      admitted > Math.min(frameLimits.maxRowBytes, metadata.payloadBytes)) {
                    fail('InvalidPublicationRowConsumer');
                  }
                  frameControl.growDurableResultRowFrameBuffer!(frames, admitted);
                  frameCapacity = admitted;
                }
              }
              const rows = frameControl.feedDurableResultRowFrames(
                frames, chunk,
              );
              for (const row of rows) {
                await accept(row, rowIndex);
                rowIndex++;
              }
            });
            const summary = frameControl.finishDurableResultRowFrames(frames);
            if (summary.rows !== metadata.rowCount ||
                summary.bytes !== physical.bytes) {
              fail('PublicationDurableBindingMismatch');
            }
            return summary;
          } catch (error) {
            frameControl.cancelDurableResultRowFrames(frames);
            throw error;
          }
        };
        try { return await use(metadata, readRows); }
        finally { scopeOpen = false; }
      },
      readDemand,
    );
  };

  return {withCommittedResult, consumeCommittedResult, withCommittedResultRows};
}
