import {runtimeField} from './compiler-binding.generated.mjs';
import {publicationAction} from './publication-action.mjs';
import {validOutputLimits, validResultOutputLimits} from './result-output-limits.mjs';
import {checked} from './runtime-result.mjs';
import type {SynchronousRuntimeData} from './runtime-result.mjs';

type CommonObject = Extract<SynchronousRuntimeData, object>;
type ResultProgress = (preparation: unknown, quantum: number) => boolean;
type EvidenceContext = Readonly<{
  computationContractCid: string;
  inputRelationCids: readonly string[];
  scopeCid: string;
  effectiveDataPolicyCid: string;
  authorityScopeCid: string;
}>;
type EvidenceLimits = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
type ExportMeasurement = Readonly<{
  row_count: number;
  admission_nodes: number;
  admission_text_bytes: number;
  admission_work: number;
  column_rows: readonly number[];
  column_bytes: readonly number[];
  column_nodes: readonly number[];
  column_max_value_bytes: readonly number[];
  column_null_rows: readonly number[];
  column_admitted_depths: readonly number[];
}>;
type PublicationBindings = Readonly<{
  admit(kind: 'derivation_evidence' | 'ordering_evidence', wire: string, limits: EvidenceLimits): CommonObject;
  publicationCleanupOwnerAction(
    currentIndex: number, ownerCount: number, statusChecked: boolean, pending: boolean,
    retryAvailable: boolean, retryAttempted: boolean,
  ): ReturnType<typeof publicationAction<'cleanupOwner'>>;
}>;

// The original Common JS bindings supply opaque handles and raw Result values.
type CommonOutputExportBindings = {
  strategyDurablePayloadFailureAction(
    writerExists: boolean, writerSealed: boolean, writerCancelAttempted: boolean,
    preparedPending: boolean, preparedReleaseAttempted: boolean, exportExists: boolean,
    exportReleased: boolean, exportCancelAttempted: boolean,
  ): number;
  strategyHostManagedResultImportAppend(
    value: unknown, row: string, maxBytes: number, maxNodes: number, maxDepth: number,
    maxTextBytes: number,
  ): unknown;
  strategyHostManagedResultImportBegin(
    host: unknown, result: number, output: unknown, material: unknown, maxResultFields: number,
    maxResultMappingWork: number, maxResultOrderWork: number, maxResultWorkspaceEntries: number,
    maxRows: number, maxValueNodes: number, maxValueTextBytes: number, maxValueDepth: number,
    maxValueWork: number, maxWireBytes: number, maxWireNodes: number, maxWireDepth: number,
    maxColumns: number, maxOrderWork: number, maxLogicalWireBytes: number,
    maxLogicalWireNodes: number, maxLogicalWireDepth: number, maxSchemaFields: number,
    maxSchemaBytes: number, maxSchemaNodes: number, maxSchemaDepth: number, maxBatchBytes: number,
  ): unknown;
  strategyHostManagedResultImportCancel(value: unknown): void;
  strategyHostManagedResultTransformationBegin(value: unknown, selection: unknown): unknown;
  strategyHostOutputExportAdvance(value: unknown, quantum: number): unknown;
  strategyHostOutputExportBegin(
    output: unknown, maxRows: number, maxValueNodes: number, maxValueTextBytes: number,
    maxValueDepth: number, maxValueWork: number, maxWireBytes: number, maxWireNodes: number,
    maxWireDepth: number, maxColumns: number, maxOrderWork: number, maxLogicalWireBytes: number,
    maxLogicalWireNodes: number, maxLogicalWireDepth: number, maxSchemaFields: number,
    maxSchemaBytes: number, maxSchemaNodes: number, maxSchemaDepth: number, maxBatchBytes: number,
  ): unknown;
  strategyHostOutputExportBytes(value: unknown): unknown;
  strategyHostOutputExportCancel(value: unknown): void;
  strategyHostOutputExportCid(value: unknown): unknown;
  strategyHostOutputExportCodecContractCid(value: unknown): unknown;
  strategyHostOutputExportDerivationEvidenceJson(value: unknown): unknown;
  strategyHostOutputExportFinish(value: unknown): unknown;
  strategyHostOutputExportIssueResultEvidence(
    value: unknown, computationContractCid: string, inputRelationCids: readonly string[], scopeCid: string,
    effectiveDataPolicyCid: string, authorityScopeCid: string, maxWireBytes: number,
    maxNodes: number, maxDepth: number,
  ): unknown;
  strategyHostOutputExportLogicalRelationCid(value: unknown): unknown;
  strategyHostOutputExportMeasurement(value: unknown): unknown;
  strategyHostOutputExportNext(value: unknown): unknown;
  strategyHostOutputExportNodes(value: unknown): unknown;
  strategyHostOutputExportOrderingEvidenceJson(value: unknown): unknown;
  strategyHostOutputExportResultFields(value: unknown): unknown;
  strategyHostOutputExportResultSchemaCid(value: unknown): unknown;
  strategyHostOutputExportResultSchemaWire(value: unknown): unknown;
  strategyHostOutputExportRows(value: unknown): unknown;
  strategyHostOutputExportRowsComplete(value: unknown): unknown;
  strategyHostOutputExportSchemaBytes(value: unknown): unknown;
  strategyHostOutputExportSchemaFields(value: unknown): unknown;
  strategyHostOutputExportSchemaNodes(value: unknown): unknown;
  strategyHostResultTransformationAdvance(value: unknown, quantum: number): unknown;
  strategyHostResultTransformationBegin(
    host: unknown, result: number, maxResultFields: number, maxResultMappingWork: number,
    maxResultOrderWork: number, maxResultWorkspaceEntries: number, maxRows: number,
    maxValueNodes: number, maxValueTextBytes: number, maxValueDepth: number, maxValueWork: number,
    maxWireBytes: number, maxWireNodes: number, maxWireDepth: number, maxColumns: number,
    maxOrderWork: number, maxLogicalWireBytes: number, maxLogicalWireNodes: number,
    maxLogicalWireDepth: number, maxSchemaFields: number, maxSchemaBytes: number,
    maxSchemaNodes: number, maxSchemaDepth: number, maxBatchBytes: number,
    convertedOutput: unknown, selection: unknown,
  ): unknown;
  strategyHostResultTransformationCancel(value: unknown): void;
  strategyHostResultTransformationFinish(value: unknown): unknown;
};

export function outputExportControl(moon: CommonOutputExportBindings, publications: PublicationBindings) {
  async function finishTransformation(
    preparation: unknown, signal?: AbortSignal, resultProgress?: ResultProgress,
  ) {
    let finished = false;
    try {
      while (true) {
        signal?.throwIfAborted();
        const ready = resultProgress === undefined
          ? checked(moon.strategyHostResultTransformationAdvance(preparation, 256))
          : resultProgress(preparation, 256);
        if (typeof ready !== 'boolean') throw new TypeError('Invalid Result transformation progress');
        if (ready) break;
        await new Promise(resolve => setTimeout(resolve, 0));
      }
      signal?.throwIfAborted();
      const exported = checked(
        moon.strategyHostResultTransformationFinish(preparation));
      finished = true;
      return exported as CommonObject;
    } finally {
      if (!finished) moon.strategyHostResultTransformationCancel(preparation);
    }
  }
  const evidenceFields = [
    'computationContractCid',
    'inputRelationCids',
    'scopeCid',
    'effectiveDataPolicyCid',
    'authorityScopeCid',
  ];
  const cidPattern = /^sha256:[0-9a-f]{64}$/u;
  const evidenceLimitFields = ['maxWireBytes', 'maxNodes', 'maxDepth'] as const;
  const validEvidenceLimits = (limits: EvidenceLimits) =>
    limits !== null && typeof limits === 'object' &&
    !Array.isArray(limits) &&
    Object.keys(limits).sort().join('\0') ===
      [...evidenceLimitFields].sort().join('\0') &&
    evidenceLimitFields.every(name =>
      Number.isSafeInteger(limits[name]) && limits[name] >= 0);
  const validEvidenceContext = (value: EvidenceContext) =>
    value !== null && typeof value === 'object' &&
    Object.keys(value).sort().join('\0') ===
      [...evidenceFields].sort().join('\0') &&
    ['computationContractCid', 'scopeCid', 'effectiveDataPolicyCid',
      'authorityScopeCid'].every(name =>
        cidPattern.test(value[name as Exclude<keyof EvidenceContext, 'inputRelationCids'>])) &&
    Array.isArray(value.inputRelationCids) &&
    value.inputRelationCids.every(cid => cidPattern.test(cid));
  return Object.freeze({
    begin(output: unknown, limits: unknown) {
      if (!validOutputLimits(limits)) {
        throw new TypeError('Invalid output export limits');
      }
      return checked(moon.strategyHostOutputExportBegin(
        output,
        limits.maxRows,
        limits.maxValueNodes,
        limits.maxValueTextBytes,
        limits.maxValueDepth,
        limits.maxValueWork,
        limits.maxWireBytes,
        limits.maxWireNodes,
        limits.maxWireDepth,
        limits.maxColumns,
        limits.maxOrderWork,
        limits.maxLogicalWireBytes,
        limits.maxLogicalWireNodes,
        limits.maxLogicalWireDepth,
        limits.maxSchemaFields,
        limits.maxSchemaBytes,
        limits.maxSchemaNodes,
        limits.maxSchemaDepth,
        limits.maxBatchBytes,
      )) as CommonObject;
    },
    beginResult(
      host: object, result: number, limits: unknown, convertedOutput?: unknown, selection?: unknown,
      signal?: AbortSignal, resultProgress?: ResultProgress,
    ) {
      if (!Number.isSafeInteger(result) || result < 0 ||
          !validResultOutputLimits(limits)) {
        throw new TypeError('Invalid Result output export request');
      }
      signal?.throwIfAborted();
      const value = checked(moon.strategyHostResultTransformationBegin(
        host,
        result,
        limits.maxResultFields,
        limits.maxResultMappingWork,
        limits.maxResultOrderWork,
        limits.maxResultWorkspaceEntries,
        limits.maxRows,
        limits.maxValueNodes,
        limits.maxValueTextBytes,
        limits.maxValueDepth,
        limits.maxValueWork,
        limits.maxWireBytes,
        limits.maxWireNodes,
        limits.maxWireDepth,
        limits.maxColumns,
        limits.maxOrderWork,
        limits.maxLogicalWireBytes,
        limits.maxLogicalWireNodes,
        limits.maxLogicalWireDepth,
        limits.maxSchemaFields,
        limits.maxSchemaBytes,
        limits.maxSchemaNodes,
        limits.maxSchemaDepth,
        limits.maxBatchBytes,
        convertedOutput,
        selection,
      ));
      return finishTransformation(value, signal, resultProgress);
    },
    beginManagedResultImport(host: object, result: number, output: unknown, material: unknown, limits: unknown) {
      if (!Number.isSafeInteger(result) || result < 0 || output == null ||
          material == null || !validResultOutputLimits(limits)) {
        throw new TypeError('Invalid managed Result import request');
      }
      return checked(moon.strategyHostManagedResultImportBegin(
        host,
        result,
        output,
        material,
        limits.maxResultFields,
        limits.maxResultMappingWork,
        limits.maxResultOrderWork,
        limits.maxResultWorkspaceEntries,
        limits.maxRows,
        limits.maxValueNodes,
        limits.maxValueTextBytes,
        limits.maxValueDepth,
        limits.maxValueWork,
        limits.maxWireBytes,
        limits.maxWireNodes,
        limits.maxWireDepth,
        limits.maxColumns,
        limits.maxOrderWork,
        limits.maxLogicalWireBytes,
        limits.maxLogicalWireNodes,
        limits.maxLogicalWireDepth,
        limits.maxSchemaFields,
        limits.maxSchemaBytes,
        limits.maxSchemaNodes,
        limits.maxSchemaDepth,
        limits.maxBatchBytes,
      )) as CommonObject;
    },
    appendManagedResultImport(value: unknown, row: string, limits: unknown) {
      if (typeof row !== 'string' || !validResultOutputLimits(limits)) {
        throw new TypeError('Invalid managed Result import row');
      }
      checked(moon.strategyHostManagedResultImportAppend(
        value,
        row,
        limits.maxWireBytes,
        limits.maxWireNodes,
        limits.maxWireDepth,
        limits.maxValueTextBytes,
      ));
    },
    finishManagedResultImport(value: unknown, signal?: AbortSignal, resultProgress?: ResultProgress) {
      signal?.throwIfAborted();
      const preparation = checked(
        moon.strategyHostManagedResultTransformationBegin(value, undefined));
      return finishTransformation(preparation, signal, resultProgress);
    },
    async transformManagedResultImport(
      value: unknown, selection: unknown, signal?: AbortSignal, resultProgress?: ResultProgress,
    ) {
      signal?.throwIfAborted();
      const preparation = checked(
        moon.strategyHostManagedResultTransformationBegin(value, selection));
      return finishTransformation(preparation, signal, resultProgress);
    },
    cancelManagedResultImport: moon.strategyHostManagedResultImportCancel,
    next: (value: unknown) => checked(moon.strategyHostOutputExportNext(value)) as string | undefined,
    rowsComplete: (value: unknown) => checked(moon.strategyHostOutputExportRowsComplete(value)) as boolean,
    advance(value: unknown, quantum: number) {
      if (!Number.isInteger(quantum) || quantum < 1 || quantum > 64) {
        throw new TypeError('Invalid output export quantum');
      }
      const progress = moon.strategyHostOutputExportAdvance(value, quantum);
      return Object.freeze({batch: runtimeField(progress, 0) as string | undefined,
        complete: runtimeField(progress, 1) as boolean,
        work: runtimeField(progress, 2) as number, issue: runtimeField(progress, 3)});
    },
    finish: (value: unknown) => checked(moon.strategyHostOutputExportFinish(value)) as string,
    measurement(value: unknown) {
      const measured = checked(moon.strategyHostOutputExportMeasurement(value)) as ExportMeasurement;
      return Object.freeze({rowCount: measured.row_count,
        admissionNodes: measured.admission_nodes,
        admissionTextBytes: measured.admission_text_bytes,
        admissionWork: measured.admission_work,
        columnRows: Object.freeze([...measured.column_rows]),
        columnBytes: Object.freeze([...measured.column_bytes]),
        columnNodes: Object.freeze([...measured.column_nodes]),
        columnMaxValueBytes: Object.freeze([...measured.column_max_value_bytes]),
        columnNullRows: Object.freeze([...measured.column_null_rows]),
        columnAdmittedDepths: Object.freeze([...measured.column_admitted_depths])});
    },
    identity(value: unknown) {
      return Object.freeze({
        orderedRowsCid: checked(moon.strategyHostOutputExportCid(value)) as string,
        logicalRelationCid:
          checked(moon.strategyHostOutputExportLogicalRelationCid(value)) as string,
        resultSchemaCid:
          checked(moon.strategyHostOutputExportResultSchemaCid(value)) as string,
        resultSchemaWire:
          checked(moon.strategyHostOutputExportResultSchemaWire(value)) as string,
        resultFields:
          checked(moon.strategyHostOutputExportResultFields(value)) as readonly string[],
        codecContractCid:
          checked(moon.strategyHostOutputExportCodecContractCid(value)) as string,
        bytes: checked(moon.strategyHostOutputExportBytes(value)) as number,
        nodes: checked(moon.strategyHostOutputExportNodes(value)) as number,
        rows: checked(moon.strategyHostOutputExportRows(value)) as number,
        schemaBytes: checked(
          moon.strategyHostOutputExportSchemaBytes(value),
        ) as number,
        schemaNodes: checked(
          moon.strategyHostOutputExportSchemaNodes(value),
        ) as number,
        schemaFields: checked(
          moon.strategyHostOutputExportSchemaFields(value),
        ) as number,
      });
    },
    issueResultEvidence(value: unknown, context: EvidenceContext, limits: EvidenceLimits) {
      if (!validEvidenceContext(context) ||
          !validEvidenceLimits(limits)) {
        throw new TypeError('Invalid Result evidence issuance request');
      }
      checked(moon.strategyHostOutputExportIssueResultEvidence(
        value,
        context.computationContractCid,
        context.inputRelationCids,
        context.scopeCid,
        context.effectiveDataPolicyCid,
        context.authorityScopeCid,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      ));
      return Object.freeze({
        derivation: publications.admit(
          'derivation_evidence',
          checked(moon.strategyHostOutputExportDerivationEvidenceJson(value)) as string,
          limits,
        ),
        ordering: publications.admit(
          'ordering_evidence',
          checked(moon.strategyHostOutputExportOrderingEvidenceJson(value)) as string,
          limits,
        ),
      });
    },
    cancel: moon.strategyHostOutputExportCancel,
    payloadFailureAction(
      writerExists: boolean,
      writerSealed: boolean,
      writerCancelAttempted: boolean,
      preparedPending: boolean,
      preparedReleaseAttempted: boolean,
      exportExists: boolean,
      exportReleased: boolean,
      exportCancelAttempted: boolean,
    ) {
      return publicationAction('durablePayloadFailure',
        moon.strategyDurablePayloadFailureAction(
          writerExists,
          writerSealed,
          writerCancelAttempted,
          preparedPending,
          preparedReleaseAttempted,
          exportExists,
          exportReleased,
          exportCancelAttempted,
        ));
    },
    cleanupOwnerAction:
      publications.publicationCleanupOwnerAction,
  });
}
