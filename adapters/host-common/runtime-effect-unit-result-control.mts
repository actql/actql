import {runtimeField, runtimeOptionalField} from './compiler-binding.generated.mjs';
import {checked} from './runtime-result.mjs';

type Limits = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
type Artifact = Readonly<{identity: string; wire: string; derivationWire: string; orderingWire: string}>;
type CapacityOwner = Readonly<{growOriginalPublicationCapacity?: (retained: bigint, execution: bigint) => unknown}>;
type UnitResults = {
  pins?: unknown;
  imports?: unknown[];
  exports: unknown[];
  receipts: unknown[];
  artifacts: Readonly<{name: string; artifact: unknown}>[];
  manifest?: unknown;
  modelScan?: unknown;
  modelReceipt?: unknown;
  modelOriginal?: unknown;
  identityRetainedBytes?: bigint;
  identityExecutionBytes?: bigint;
};
type ResultDependency =
  | Readonly<{kind: 'combined_source'; issued: unknown; unit: number}>
  | Readonly<{kind: 'preconsumer_model'; issued: unknown; original: unknown; unit: number}>;
type PhysicalSource = (task: number | undefined) => Readonly<{
  completed: unknown;
  material: unknown;
  withRows(append: (row: string) => void, signal: AbortSignal | undefined, finish: () => unknown): unknown;
}> | undefined;

// Generated Common results are opaque until the original result or layout check.
type CommonEffectUnitResultBindings = Readonly<{
  clientProgramAcquiredEffectDependencyBodies(value: unknown): unknown;
  clientProgramAcquiredEffectRequestCid(value: unknown): string;
  clientProgramBeginInstalledEffectModelUnitManagedExport(run: unknown, plan: unknown,
    request: unknown, captured: unknown, inputs: unknown, index: number, output: unknown,
    material: unknown): unknown;
  clientProgramBindInferResultArtifactInput(active: unknown, importIndex: number, artifact: unknown,
    manifest: unknown): unknown;
  clientProgramBindOriginalEffectUnitArtifactRunContext(owner: unknown, inputs: unknown,
    artifact: unknown, admission: unknown, definition: unknown, invocation: unknown,
    observation: unknown): unknown;
  clientProgramCheckOriginalEffectUnitArtifactExport(owner: unknown, inputs: unknown,
    artifact: unknown, exported: unknown, receipt: unknown): unknown;
  clientProgramEffectInputExportCancelPreparation(value: unknown): boolean;
  clientProgramEffectInputExportLogicalCid(receipt: unknown): string;
  clientProgramEffectInputExportReleaseReceipt(receipt: unknown): undefined;
  clientProgramEffectInputExportSchemaCid(receipt: unknown): string;
  clientProgramEffectInputExportSchemaWire(receipt: unknown): string;
  clientProgramEffectLocalResultExportPreparation(value: unknown): unknown;
  clientProgramEffectManagedInputAppend(value: unknown, row: string): unknown;
  clientProgramEffectManagedInputCancel(value: unknown): undefined;
  clientProgramEffectManagedInputFinish(value: unknown): unknown;
  clientProgramEffectModelUnitExportReceipt(exported: unknown): unknown;
  clientProgramEffectModelUnitManagedExportOwner(inputs: unknown, index: number, value: unknown): unknown;
  clientProgramEffectModelUnitResultArtifactIssueKind(result: unknown): string | undefined;
  clientProgramEffectModelUnitResultCount(inputs: unknown): number;
  clientProgramEffectModelUnitResultExportIssueKind(result: unknown): string | undefined;
  clientProgramEffectModelUnitResultName(inputs: unknown, index: number): string | undefined;
  clientProgramEffectModelUnitResultRequiresManagedExport(inputs: unknown, index: number): boolean;
  clientProgramEffectModelUnitResultTask(inputs: unknown, index: number): number | undefined;
  clientProgramInferModelIdentityAdvance(scan: unknown, quantum: number, retained: bigint,
    execution: bigint): unknown;
  clientProgramInferModelIdentityBody(scan: unknown, receipt: unknown): string | undefined;
  clientProgramInferModelIdentityCancel(scan: unknown): boolean;
  clientProgramInferModelIdentityFinish(scan: unknown): unknown;
  clientProgramInferModelIdentityNextCapacity(scan: unknown): readonly [bigint, bigint] | undefined;
  clientProgramInferModelIdentityReceiptCancel(receipt: unknown): undefined;
  clientProgramInferOccurrenceCoordinates(occurrence: unknown): readonly [number, number, number];
  clientProgramLocalEffectResultManifestCid(value: unknown): string;
  clientProgramLocalEffectResultManifestJson(value: unknown): string;
  clientProgramOriginalEffectUnitArtifactDefinition(artifact: unknown): unknown;
  clientProgramOriginalEffectUnitManifestMatches(manifest: unknown, owner: unknown,
    invocation: unknown, artifacts: unknown): boolean;
  clientProgramOriginalModelAcquiredEffectInvocation(value: unknown): unknown;
  clientProgramOriginalModelAcquiredEffectScope(value: unknown): string;
  clientProgramOriginalModelAcquiredEffectSources(value: unknown): unknown;
  clientProgramOriginalModelAcquiredLookupDependencyBodies(value: unknown): unknown;
  clientProgramOriginalModelAcquiredScopeImportBodies(value: unknown): unknown;
  clientProgramPinInstalledEffectModelUnitResults(run: unknown, plan: unknown, request: unknown,
    captured: unknown, unit: number): unknown;
  clientProgramPreconsumerModelUnitAcquiredEvidence(original: unknown): unknown;
  clientProgramPreconsumerModelUnitDependencyBodies(value: unknown): unknown;
  clientProgramPreconsumerModelUnitIdentityStart(held: unknown, compiled: unknown,
    definition: unknown, plan: unknown): unknown;
  clientProgramPreconsumerModelUnitIdentityStartCapacity(held: unknown,
    compiled: unknown, definition: unknown, plan: unknown): readonly [bigint, bigint] | undefined;
  clientProgramPreconsumerModelUnitObservationCapacity(held: unknown,
    compiled: unknown, definition: unknown, plan: unknown,
    receipt: unknown, maxWireBytes: number): readonly [bigint, bigint] | undefined;
  clientProgramPrepareInstalledEffectModelSourceUnitArtifact(run: unknown, plan: unknown,
    request: unknown, inputs: unknown, exported: unknown, combined: unknown, receipt: unknown,
    admission: unknown, definition: unknown, maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramPrepareInstalledEffectModelUnitArtifact(run: unknown, plan: unknown, request: unknown,
    owner: unknown, original: unknown, inputs: unknown, exported: unknown, receipt: unknown,
    admission: unknown, maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramPrepareInstalledEffectModelUnitEvidence(run: unknown, plan: unknown, request: unknown,
    held: unknown, compiled: unknown, definition: unknown, graph: unknown, receipt: unknown,
    retention: unknown, maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramPrepareInstalledEffectModelUnitManifest(run: unknown, plan: unknown, request: unknown,
    invocation: unknown, artifacts: unknown, maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramPrepareInstalledEffectModelUnitResultExport(run: unknown, plan: unknown,
    request: unknown, captured: unknown, inputs: unknown, index: number): unknown;
  clientProgramReleaseEffectModelUnitResults(inputs: unknown): boolean;
}>;

type EffectUnitResultPorts = Readonly<{
  compiledRunTokens: WeakMap<object, unknown>;
  localEffectDependencyTokens: WeakMap<object, unknown>;
  localEffectArtifactTokens: WeakMap<object, unknown>;
  localEffectManifestTokens: WeakMap<object, unknown>;
  issuanceLimits: (limits: Limits, label: string) => Limits;
  token: (value: unknown) => unknown;
  admissionToken: (value: unknown) => unknown;
  inspectLocalEffectArtifact: (value: unknown) => Artifact;
  localEffectContext: (context: unknown) => readonly [unknown, unknown, unknown, unknown];
}>;

export function createEffectUnitResultControls(moon: CommonEffectUnitResultBindings, {
  compiledRunTokens, localEffectDependencyTokens, localEffectArtifactTokens, localEffectManifestTokens,
  issuanceLimits, token, admissionToken, inspectLocalEffectArtifact, localEffectContext,
}: EffectUnitResultPorts) {
  return {
    prepareOriginalEffectModelUnitEvidence(managedRun: unknown, plan: unknown, request: unknown,
      held: unknown, compiled: unknown, definition: unknown, graph: unknown, unit: number,
      retention: unknown, catalogBodies: readonly unknown[], operation: CapacityOwner | undefined,
      limits: Limits, retained: UnitResults, current: () => void, retainedBase: bigint,
      executionBase: bigint, deferCatalogs = false) {
      issuanceLimits(limits, 'Original completed Model Unit');
      const originalCompiled = compiledRunTokens.get(compiled as object);
      if (originalCompiled === undefined || (compiled as Readonly<{kind?: unknown}>).kind !== 'infer' || retained.modelScan !== undefined ||
          typeof current !== 'function' || typeof operation?.growOriginalPublicationCapacity !== 'function' ||
          !Number.isSafeInteger(unit) || unit < 0 || !Array.isArray(catalogBodies)) {
        throw new TypeError('ForeignPreconsumerModelOriginal');
      }
      const extent = (quote: unknown) => {
        const r = runtimeOptionalField(quote, 0), e = runtimeOptionalField(quote, 1);
        if (typeof r !== 'bigint' || typeof e !== 'bigint' || r < 0n || e < 0n) {
          throw new TypeError('PreconsumerModelConstructionCapacityUnavailable');
        }
        return [r, e] as const;
      };
      const rawDefinition = token(definition);
      let [r, e] = extent(moon.clientProgramPreconsumerModelUnitIdentityStartCapacity(
        held, originalCompiled, rawDefinition, graph));
      operation.growOriginalPublicationCapacity(retainedBase + r, executionBase + e);
      current();
      retained.modelScan = checked(moon.clientProgramPreconsumerModelUnitIdentityStart(
        held, originalCompiled, rawDefinition, graph));
      current();
      for (;;) {
        const [nextR, nextE] = extent(moon.clientProgramInferModelIdentityNextCapacity(retained.modelScan));
        r = nextR > r ? nextR : r; e = nextE > e ? nextE : e;
        operation.growOriginalPublicationCapacity(retainedBase + r, executionBase + e);
        current();
        const progress = checked(moon.clientProgramInferModelIdentityAdvance(retained.modelScan, 256, nextR, nextE));
        current();
        if (runtimeField(progress, 0)) break;
      }
      retained.modelReceipt = checked(moon.clientProgramInferModelIdentityFinish(retained.modelScan));
      current();
      const [writerR, writerE] = extent(moon.clientProgramPreconsumerModelUnitObservationCapacity(
        held, originalCompiled, rawDefinition, graph, retained.modelReceipt, limits.maxWireBytes));
      retained.identityRetainedBytes = r + writerR;
      retained.identityExecutionBytes = e + writerE;
      operation.growOriginalPublicationCapacity(retainedBase + retained.identityRetainedBytes,
        executionBase + retained.identityExecutionBytes);
      current();
      retained.modelOriginal = checked(moon.clientProgramPrepareInstalledEffectModelUnitEvidence(
        managedRun, plan, request, held, originalCompiled, rawDefinition, graph, retained.modelReceipt,
        token(retention), limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      current();
      const acquired = checked(moon.clientProgramPreconsumerModelUnitAcquiredEvidence(retained.modelOriginal));
      const originals = (checked(moon.clientProgramPreconsumerModelUnitDependencyBodies(retained.modelOriginal)) as readonly unknown[])
        .map(body => Object.freeze({kind: runtimeField(body, 0), cid: runtimeField(body, 1), wire: runtimeField(body, 2)}));
      const direct = moon.clientProgramOriginalModelAcquiredEffectSources(acquired) as readonly unknown[];
      const lookupBodies = (checked(moon.clientProgramOriginalModelAcquiredLookupDependencyBodies(acquired)) as readonly unknown[])
        .map(body => Object.freeze({kind: runtimeField(body, 0), cid: runtimeField(body, 1), wire: runtimeField(body, 2)}));
      const bodies = [
        ...originals,
        ...direct.flatMap(source => (moon.clientProgramAcquiredEffectDependencyBodies(source) as readonly unknown[])
          .map(pair => Object.freeze({kind: runtimeField(pair, 0), wire: runtimeField(pair, 1),
            ...(runtimeField(pair, 0) === 'request_values' ? {cid: moon.clientProgramAcquiredEffectRequestCid(source)} : {})}))),
        ...lookupBodies,
        ...(moon.clientProgramOriginalModelAcquiredScopeImportBodies(acquired) as readonly unknown[])
          .map(body => Object.freeze({kind: runtimeField(body, 0), cid: runtimeField(body, 1), wire: runtimeField(body, 2)})),
        Object.freeze({kind: 'acquisition_scope', wire: moon.clientProgramOriginalModelAcquiredEffectScope(acquired)}),
        Object.freeze({kind: 'relation_value', cid: moon.clientProgramEffectInputExportLogicalCid(retained.modelReceipt),
          wire: moon.clientProgramInferModelIdentityBody(retained.modelScan, retained.modelReceipt)}),
        Object.freeze({kind: 'relation_schema', cid: moon.clientProgramEffectInputExportSchemaCid(retained.modelReceipt),
          wire: moon.clientProgramEffectInputExportSchemaWire(retained.modelReceipt)}),
      ];
      const value = Object.freeze({invocation: moon.clientProgramOriginalModelAcquiredEffectInvocation(acquired),
        ...(deferCatalogs ? {catalogDeferred: true} : {}),
        bodies: Object.freeze(bodies), catalogBodies: Object.freeze([...catalogBodies,
          ...lookupBodies.filter(body => ['source_contract', 'source_view_contract', 'data_policy',
            'request_schema', 'carrier_schema', 'schema_evidence', 'capability_evidence'].includes(body.kind as string))])});
      localEffectDependencyTokens.set(value, {kind: 'preconsumer_model', issued: acquired,
        original: retained.modelOriginal, unit});
      current();
      return value;
    },
    async prepareOriginalEffectSourceUnitResults(managedRun: unknown, plan: unknown, request: unknown,
      captured: unknown, dependency: unknown, admission: unknown, definition: unknown, limits: Limits,
      retained: UnitResults, current: () => void, prepared: unknown, consumerOccurrence: unknown,
      physicalSource: unknown, signal: AbortSignal | undefined, retainedCurrent: (() => void) | undefined) {
      issuanceLimits(limits, 'Original preconsumer Effect Unit Results');
      const owned = localEffectDependencyTokens.get(dependency as object) as ResultDependency | undefined;
      if (!['combined_source', 'preconsumer_model'].includes(owned?.kind as string) || retained === null || typeof retained !== 'object' ||
          retained.pins !== undefined || !Array.isArray(retained.exports) || retained.exports.length !== 0 ||
          !Array.isArray(retained.receipts) || retained.receipts.length !== 0 ||
          !Array.isArray(retained.artifacts) || retained.artifacts.length !== 0 || typeof current !== 'function') {
        throw new TypeError('ForeignEffectSourceUnitOriginal');
      }
      current();
      retained.pins = checked(moon.clientProgramPinInstalledEffectModelUnitResults(
        managedRun, plan, request, captured,
        owned!.unit));
      current();
      const count = moon.clientProgramEffectModelUnitResultCount(retained.pins);
      for (let index = 0; index < count; index++) {
        let result;
        if (moon.clientProgramEffectModelUnitResultRequiresManagedExport(retained.pins, index)) {
          const task = moon.clientProgramEffectModelUnitResultTask(retained.pins, index);
          const physical = (physicalSource as PhysicalSource | undefined)?.(task);
          if (physical === undefined) throw new Error('OriginalEffectUnitPhysicalSourceUnavailable');
          const importing = checked(moon.clientProgramBeginInstalledEffectModelUnitManagedExport(
            managedRun, plan, request, captured, retained.pins, index, physical.completed, physical.material));
          // Retain the SAME bridge before current/withRows can reenter or await.
          (retained.imports ??= []).push(importing); current();
          if (typeof retainedCurrent !== 'function') throw new TypeError('OriginalEffectUnitRetainedFenceUnavailable');
          await physical.withRows(row => {
            // The physical reader owns its same-material use and signal. A
            // row checks only local retention; full Journal/selection current
            // stays at the existing read/finish and Model dispatch boundaries.
            retainedCurrent();
            checked(moon.clientProgramEffectManagedInputAppend(importing, row));
            retainedCurrent();
          }, signal, () => {
            current();
            const preparation = checked(moon.clientProgramEffectManagedInputFinish(importing));
            current();
            return preparation;
          });
          current();
          result = moon.clientProgramEffectModelUnitManagedExportOwner(retained.pins, index, importing);
        } else result = moon.clientProgramPrepareInstalledEffectModelUnitResultExport(
          managedRun, plan, request, captured, retained.pins, index);
        let exported;
        try { exported = checked(result); }
        catch (cause) {
          try {
            const kind = moon.clientProgramEffectModelUnitResultExportIssueKind?.(result);
            const coordinates = consumerOccurrence === undefined ? undefined
              : moon.clientProgramInferOccurrenceCoordinates(consumerOccurrence);
            const task = runtimeField(coordinates, 0) as number, unit = runtimeField(coordinates, 1) as number,
              step = runtimeField(coordinates, 2) as number;
            if (typeof kind === 'string' && [task, unit, step].every(value =>
                Number.isSafeInteger(value) && value >= 0 && value <= 2147483647)) {
              Object.defineProperty(cause as object, 'primaryDiagnostic', {
                value: Object.freeze({code: 'MoonBitHostFailure',
                  phase: 'original_effect_source_unit_result_export', kind, task, unit, step}),
              });
            }
          } catch { /* Optional DATA cannot replace the original export failure. */ }
          throw cause;
        }
        retained.exports.push(exported); current();
        const receipt = checked(moon.clientProgramEffectModelUnitExportReceipt(exported));
        retained.receipts.push(receipt); current();
        // The Plan retained this original public holder/token. A separate
        // Journal wire admission has the same CID but is not that original.
        const artifactResult = owned!.kind === 'combined_source'
          ? moon.clientProgramPrepareInstalledEffectModelSourceUnitArtifact(
            managedRun, plan, request, retained.pins, exported, owned!.issued, receipt,
            admissionToken(admission), token(definition), limits.maxWireBytes, limits.maxNodes, limits.maxDepth)
          : moon.clientProgramPrepareInstalledEffectModelUnitArtifact(
            managedRun, plan, request, prepared,
            owned!.original, retained.pins, exported, receipt, admissionToken(admission),
            limits.maxWireBytes, limits.maxNodes, limits.maxDepth);
        let issued;
        try {issued = checked(artifactResult);}
        catch (cause) {
          try {
            const kind = moon.clientProgramEffectModelUnitResultArtifactIssueKind?.(artifactResult);
            const coordinates = consumerOccurrence === undefined ? undefined
              : moon.clientProgramInferOccurrenceCoordinates(consumerOccurrence);
            const task = runtimeField(coordinates, 0) as number, unit = runtimeField(coordinates, 1) as number,
              step = runtimeField(coordinates, 2) as number;
            if (typeof kind === 'string' && [task, unit, step].every(value =>
                Number.isSafeInteger(value) && value >= 0 && value <= 2147483647)) {
              Object.defineProperty(cause as object, 'primaryDiagnostic', {
                value: Object.freeze({code: 'MoonBitHostFailure',
                  phase: 'original_effect_source_unit_artifact', kind, task, unit, step}),
              });
            }
          } catch { /* Optional DATA cannot replace the original artifact failure. */ }
          throw cause;
        }
        const artifact = inspectLocalEffectArtifact(issued);
        const name = moon.clientProgramEffectModelUnitResultName(retained.pins, index);
        if (typeof name !== 'string') throw new TypeError('OriginalEffectUnitResultUnavailable');
        retained.artifacts.push(Object.freeze({name, artifact})); current();
      }
      const issued = checked(moon.clientProgramPrepareInstalledEffectModelUnitManifest(
        managedRun, plan, request, (dependency as Readonly<{invocation: unknown}>).invocation,
        retained.artifacts.map(value => localEffectArtifactTokens.get(value.artifact as object)),
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      const manifest = Object.freeze({identity: moon.clientProgramLocalEffectResultManifestCid(issued),
        wire: moon.clientProgramLocalEffectResultManifestJson(issued)});
      localEffectManifestTokens.set(manifest, issued);
      retained.manifest = manifest; current();
      return retained;
    },
    bindOriginalEffectUnitArtifact(owner: unknown, inputs: unknown, artifact: unknown, context: unknown) {
      const original = localEffectArtifactTokens.get(artifact as object);
      if (original === undefined) throw new TypeError('ForeignOriginalEffectUnitArtifact');
      checked(moon.clientProgramBindOriginalEffectUnitArtifactRunContext(
        owner, inputs, original, ...localEffectContext(context)));
    },
    originalEffectUnitArtifactDefinition(artifact: unknown) {
      const original = localEffectArtifactTokens.get(artifact as object);
      if (original === undefined) throw new TypeError('ForeignOriginalEffectUnitArtifact');
      return checked(moon.clientProgramOriginalEffectUnitArtifactDefinition(original));
    },
    reuseOriginalEffectUnitArtifact<Artifact>(owner: unknown, inputs: unknown, artifact: Artifact,
      exported: unknown, receipt: unknown) {
      const original = localEffectArtifactTokens.get(artifact as object);
      if (original === undefined) throw new TypeError('ForeignOriginalEffectUnitArtifact');
      checked(moon.clientProgramCheckOriginalEffectUnitArtifactExport(owner, inputs, original, exported, receipt));
      return artifact;
    },
    reuseOriginalEffectUnitManifest<Manifest>(owner: unknown, invocation: unknown,
      artifacts: readonly unknown[], manifest: Manifest) {
      const original = localEffectManifestTokens.get(manifest as object);
      const retained = artifacts.map(artifact => {
        const value = localEffectArtifactTokens.get(artifact as object);
        if (value === undefined) throw new TypeError('ForeignOriginalEffectUnitArtifact');
        return value;
      });
      if (original === undefined || !moon.clientProgramOriginalEffectUnitManifestMatches(
          original, owner, invocation, retained)) throw new TypeError('ForeignOriginalEffectUnitManifest');
      return manifest;
    },
    bindInferOriginalResultArtifact(active: unknown, index: number, artifact: unknown, manifest: unknown) {
      const result = localEffectArtifactTokens.get(artifact as object), complete = localEffectManifestTokens.get(manifest as object);
      if (result === undefined || complete === undefined) throw new TypeError('ForeignInferResultArtifact');
      checked(moon.clientProgramBindInferResultArtifactInput(active, index, result, complete));
    },
    retireOriginalEffectUnitResults(retained: UnitResults) {
      // The enclosing original Host/consumer must be stopped first. These
      // calls sever only original export/receipt aliases and Unit pins; no
      // physical stop/Store ACK or consumed-work refund is inferred here.
      for (const exported of retained.exports) moon.clientProgramEffectInputExportCancelPreparation(
        moon.clientProgramEffectLocalResultExportPreparation(exported));
      for (const importing of retained.imports ?? []) moon.clientProgramEffectManagedInputCancel(importing);
      if (retained.imports !== undefined) retained.imports.length = 0;
      for (const receipt of retained.receipts) moon.clientProgramEffectInputExportReleaseReceipt(receipt);
      if (retained.modelReceipt !== undefined) moon.clientProgramInferModelIdentityReceiptCancel(retained.modelReceipt);
      if (retained.modelScan !== undefined) moon.clientProgramInferModelIdentityCancel(retained.modelScan);
      if (retained.pins !== undefined) {
        if (moon.clientProgramReleaseEffectModelUnitResults(retained.pins) !== true) return false;
        retained.pins = undefined;
      }
      retained.exports.length = 0; retained.receipts.length = 0;
      retained.artifacts.length = 0; retained.manifest = undefined;
      retained.modelScan = retained.modelReceipt = retained.modelOriginal = undefined;
      return true;
    },
  };
}
