import {runtimeField} from './compiler-binding.generated.mjs';
import {checked} from './runtime-result.mjs';

type Limits = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
type Contract = Readonly<{name: string; identity: string; identityField: string; wire: string}>;
type EffectArtifact = Readonly<{identity: string}>;
type SourceArtifact = Readonly<{kind: 'captured-effect-source-artifact'}>;
type ResultSnapshot = Readonly<{kind: 'captured-result-snapshot'}>;
type CaptureChain = Readonly<{
  runDefinition: unknown; invocation: unknown; definitions: readonly unknown[]; artifacts: readonly unknown[];
  manifest: unknown; computationReceipt: unknown; capturedRun: unknown;
}>;
type CaptureSource = Readonly<{memberIndex: number; artifact: unknown; result?: unknown}>;
type PayloadBinding = Readonly<{artifact_cid: string; physical_cid: string; byte_count: number}>;
type DependencyEntry = Readonly<{kind: string; cid: string; body: unknown}>;
type CapturedRunWire = Readonly<{
  effect_context?: Readonly<{effect_dependency_inventory?: DependencyEntry[]}>;
}>;

// Actual handles and raw Result variants remain with the generated Common.
type CommonEffectCaptureBindings = Readonly<{
  clientProgramAdmitInstalledEffectCapturedRun(owner: unknown, wire: string): unknown;
  clientProgramAdmitRequestEffectCapturedRun(parent: unknown, input: unknown, request: unknown,
    definition: unknown, wire: string): unknown;
  clientProgramEffectSourceArtifactPreviewBinding(artifact: unknown, invocationCid: string,
    sourceResult: string, storeAuthorityCid: string): unknown;
  clientProgramEffectTableSourceArtifactPreviewBinding(artifact: unknown, invocationCid: string,
    sourceTableInput: string, storeAuthorityCid: string): unknown;
  clientProgramIssueEffectSourceArtifact?(input: unknown, receipt: unknown, invocation: unknown,
    retention: unknown, sourceBindingCid: string, storeAuthorityCid: string, maxWireBytes: number,
    maxNodes: number, maxDepth: number): unknown;
  clientProgramIssueEffectTableSourceArtifact?(input: unknown, receipt: unknown, invocation: unknown,
    retention: unknown, sourceBindingCid: string, storeAuthorityCid: string, maxWireBytes: number,
    maxNodes: number, maxDepth: number): unknown;
  clientProgramLocalEffectResultArtifactJson(value: unknown): string;
  clientProgramLocalEffectResultPayloadBinding(value: unknown, runDefinition: unknown): unknown;
  clientProgramRecoveredEffectCapturedRunChainValid(run: unknown, invocation: unknown,
    definitions: unknown, artifacts: unknown, manifest: unknown, receipt: unknown, captured: unknown,
    prepared: unknown, preview: unknown, maxBytes: number, maxNodes: number, maxDepth: number): boolean;
  clientProgramRecoveredEffectCapturedRunPayloads(value: unknown): readonly string[];
  clientProgramRecoveredEffectCapturedRunSchemas(value: unknown): readonly unknown[];
  clientProgramRecoveredEffectCapturedRunSources(runDefinition: unknown, invocation: unknown,
    definitions: unknown, resultArtifacts: unknown, manifest: unknown, receipt: unknown, captured: unknown,
    prepared: unknown, preview: unknown, memberIndices: unknown, artifacts: unknown,
    storeAuthorityCid: string, maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramReserveRequestEffectCaptureDecoded(parent: unknown, input: unknown, request: unknown,
    definition: unknown, wire: string): unknown;
  clientProgramReserveRequestEffectCaptureEncrypted(parent: unknown, input: unknown, request: unknown,
    definition: unknown, bytes: number, maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramReserveRequestEffectCaptureEnvelope(parent: unknown, input: unknown, request: unknown,
    definition: unknown, wire: string): unknown;
  clientProgramReserveRequestEffectCaptureRecovery?(parent: unknown, input: unknown, request: unknown,
    definition: unknown, encryptedBytes: number, maxWireBytes: number, maxNodes: number, maxDepth: number): unknown;
  strategyAdmitCapturedEffectSourceArtifact(preview: unknown, memberIndex: number, invocation: unknown,
    artifact: unknown, storeAuthorityCid: string): unknown;
  strategyAdmitCapturedEffectSourceFromCapture(preview: unknown, memberIndex: number, invocation: unknown,
    artifact: unknown, captured: unknown, storeAuthorityCid: string, maxWireBytes: number,
    maxNodes: number, maxDepth: number): unknown;
  strategyAdmitCapturedEffectSourceFromResult(preview: unknown, memberIndex: number, invocation: unknown,
    artifact: unknown, result: unknown, storeAuthorityCid: string): unknown;
  strategyAdmitCapturedEffectSourceFromTableInput(preview: unknown, memberIndex: number,
    invocation: unknown, artifact: unknown, input: unknown, storeAuthorityCid: string): unknown;
  strategyAdmitCapturedResultSnapshot(definition: unknown, artifact: unknown, rowsWire: string,
    fields: unknown, maxWireBytes: number, maxNodes: number, maxDepth: number): unknown;
  strategyCapturedEffectSourceArtifactCid(source: unknown): string;
  strategyCapturedEffectSourceHoldingCid(source: unknown): string;
  strategyCapturedEffectSourceInventoryFromArtifactsValid(preview: unknown, memberIndices: unknown,
    artifacts: unknown, relations: unknown): boolean;
  strategyCapturedEffectSourceInventoryFromCaptureValid(preview: unknown, memberIndices: unknown,
    artifacts: unknown, invocation: unknown, captured: unknown, storeAuthorityCid: string,
    maxWireBytes: number, maxNodes: number, maxDepth: number): boolean;
  strategyCapturedEffectSourceInventoryFromResultsValid(preview: unknown, memberIndices: unknown,
    artifacts: unknown, results: unknown): boolean;
  strategyCapturedEffectSourceMatchesPreview(preview: unknown, memberIndex: number, invocation: unknown,
    source: unknown, localEvidence: unknown, storeAuthorityCid: string, maxWireBytes: number,
    maxNodes: number, maxDepth: number): unknown;
  strategyCapturedEffectSourceRecoveryInventoryValid(preview: unknown, memberIndices: unknown,
    artifacts: unknown): boolean;
  strategyCapturedEffectSourceStoreAuthorityCid(source: unknown): string;
  strategyEffectfulComputationEvidenceChainValid(runDefinition: unknown, invocation: unknown,
    definitions: unknown, artifacts: unknown, manifest: unknown, computationReceipt: unknown,
    capturedRun: unknown, preview: unknown, maxWireBytes: number, maxNodes: number, maxDepth: number): boolean;
  strategyPublicationAdmit(name: string, completeWire: string, maxWireBytes: number, maxNodes: number,
    maxDepth: number): unknown;
}>;

type CapturePorts = Readonly<{
  computationPreviewTokens: WeakMap<object, unknown>;
  recoveredEffectCaptures: WeakMap<object, unknown>;
  localEffectArtifactTokens: WeakMap<object, unknown>;
  token: (contract: unknown) => unknown;
  inspect: (contract: unknown, limits?: Limits) => Contract;
  inspectSnapshot: (snapshot: unknown) => ResultSnapshot;
  inspectEffectSource: (source: unknown) => SourceArtifact;
  inspectPreparedEffectCapturedRun: (prepared: unknown) => Contract;
  effectSourceToken: (source: unknown) => unknown;
  localEffectSourceToken: (evidence: unknown) => unknown;
  issuanceLimits: (limits: Limits, label: string) => void;
}>;

export function createEffectCaptureControls(moon: CommonEffectCaptureBindings, {
  computationPreviewTokens, recoveredEffectCaptures, localEffectArtifactTokens,
  token, inspect, inspectSnapshot, inspectEffectSource, inspectPreparedEffectCapturedRun,
  effectSourceToken, localEffectSourceToken, issuanceLimits,
}: CapturePorts) {
  return {
    captureControls: {
      admitCapturedResultSnapshot(definition: unknown, artifact: unknown, rowsWire: string,
        fields: readonly string[], limits: Limits) {
        issuanceLimits(limits, 'Captured Result snapshot');
        if (typeof rowsWire !== 'string' || !Array.isArray(fields) ||
            fields.some(field => typeof field !== 'string')) {
          throw new TypeError('Invalid Captured Result snapshot');
        }
        return inspectSnapshot(checked(
          moon.strategyAdmitCapturedResultSnapshot(
            token(definition),
            token(artifact),
            rowsWire,
            fields,
            limits.maxWireBytes,
            limits.maxNodes,
            limits.maxDepth,
          ),
        ));
      },
      admitCapturedEffectSourceArtifact(preview: unknown, memberIndex: number, invocation: unknown,
        artifact: unknown, storeAuthorityCid: string) {
        const ownedPreview = computationPreviewTokens.get(preview as object);
        if (ownedPreview === undefined ||
            !Number.isSafeInteger(memberIndex) || memberIndex < 0 ||
            typeof storeAuthorityCid !== 'string') {
          throw new TypeError('Invalid captured Effect source artifact');
        }
        return inspectEffectSource(checked(
          moon.strategyAdmitCapturedEffectSourceArtifact(
            ownedPreview, memberIndex, token(invocation), token(artifact),
            storeAuthorityCid,
          ),
        ));
      },
      capturedEffectSourceMatchesPreview(preview: unknown, memberIndex: number, invocation: unknown,
        source: unknown, localEvidence: unknown, storeAuthorityCid: string, limits: Limits) {
        issuanceLimits(limits, 'captured Effect source Preview');
        const ownedPreview = computationPreviewTokens.get(preview as object);
        if (ownedPreview === undefined || !Number.isSafeInteger(memberIndex) ||
            memberIndex < 0 || typeof storeAuthorityCid !== 'string') {
          throw new TypeError('Invalid captured Effect source Preview');
        }
        return checked(moon.strategyCapturedEffectSourceMatchesPreview(ownedPreview,
          memberIndex, token(invocation), effectSourceToken(source),
          localEffectSourceToken(localEvidence), storeAuthorityCid,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth)) as boolean;
      },
      reserveEffectCaptureRecovery(parent: unknown, input: unknown, request: unknown, runDefinition: unknown,
        encryptedBytes: number, limits: Limits) {
        issuanceLimits(limits, 'Effect capture recovery');
        if (!Number.isSafeInteger(encryptedBytes) || encryptedBytes < 0 || encryptedBytes > 2147483647 ||
            typeof moon.clientProgramReserveRequestEffectCaptureRecovery !== 'function') {
          throw new TypeError('Invalid Effect capture recovery Resource');
        }
        return checked(moon.clientProgramReserveRequestEffectCaptureRecovery(
          parent, input, request, token(runDefinition), encryptedBytes,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      },
      reserveEffectCaptureEncrypted(parent: unknown, input: unknown, request: unknown, runDefinition: unknown,
        encryptedBytes: number, limits: Limits) {
        issuanceLimits(limits, 'Effect capture encrypted recovery');
        if (!Number.isSafeInteger(encryptedBytes) || encryptedBytes < 0 || encryptedBytes > 2147483647) throw new TypeError('Invalid Effect capture encrypted Resource');
        return checked(moon.clientProgramReserveRequestEffectCaptureEncrypted(parent, input, request, token(runDefinition), encryptedBytes,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      },
      reserveEffectCaptureEnvelope(parent: unknown, input: unknown, request: unknown, runDefinition: unknown,
        wire: string, limits: Limits) {
        issuanceLimits(limits, 'Effect capture envelope recovery');
        if (typeof wire !== 'string') throw new TypeError('Invalid Effect capture envelope Resource');
        return checked(moon.clientProgramReserveRequestEffectCaptureEnvelope(parent, input, request, token(runDefinition), wire));
      },
      reserveEffectCaptureDecoded(parent: unknown, input: unknown, request: unknown, runDefinition: unknown,
        wire: string, limits: Limits) {
        issuanceLimits(limits, 'Effect capture decoded recovery');
        if (typeof wire !== 'string') throw new TypeError('Invalid Effect capture decoded Resource');
        return checked(moon.clientProgramReserveRequestEffectCaptureDecoded(parent, input, request, token(runDefinition), wire));
      },
      admitRecoveredEffectCapturedRun(parent: unknown, input: unknown, request: unknown,
        runDefinition: unknown, wire: string, limits: Limits) {
        issuanceLimits(limits, 'Effect captured Run recovery');
        if (typeof wire !== 'string') throw new TypeError('Invalid Effect captured Run recovery');
        const prepared = checked(moon.clientProgramAdmitRequestEffectCapturedRun(parent, input, request, token(runDefinition), wire));
        return inspectPreparedEffectCapturedRun(prepared);
      },
      admitLiveEffectCapturedRun(owner: unknown, wire: string) {
        if (typeof wire !== 'string') throw new TypeError('Invalid live Effect captured Run recovery');
        return inspectPreparedEffectCapturedRun(checked(moon.clientProgramAdmitInstalledEffectCapturedRun(owner, wire)));
      },
      retireRecoveredEffectCapturedRun(captured: unknown) {
        const prepared = recoveredEffectCaptures.get(captured as object);
        if (prepared === undefined) throw new TypeError('Foreign recovered Effect captured Run');
        recoveredEffectCaptures.delete(captured as object); recoveredEffectCaptures.delete(prepared as object);
      },
      admitCapturedEffectSourceFromCapture(preview: unknown, memberIndex: number, invocation: unknown,
        artifact: unknown, capturedRun: unknown, storeAuthorityCid: string, limits: Limits) {
        issuanceLimits(limits, 'recovered Effect source');
        const ownedPreview = computationPreviewTokens.get(preview as object);
        if (ownedPreview === undefined || !Number.isSafeInteger(memberIndex) ||
            memberIndex < 0 || typeof storeAuthorityCid !== 'string') {
          throw new TypeError('Invalid recovered Effect source');
        }
        return inspectEffectSource(checked(moon.strategyAdmitCapturedEffectSourceFromCapture(
          ownedPreview, memberIndex, token(invocation), token(artifact),
          token(capturedRun), storeAuthorityCid, limits.maxWireBytes,
          limits.maxNodes, limits.maxDepth)));
      },
      issueEffectSourceArtifactFromExport(input: unknown, receipt: unknown, invocation: unknown,
        retention: unknown, sourceBindingCid: string, storeAuthorityCid: string, limits: Limits) {
        issuanceLimits(limits, 'Effect source Artifact');
        if (typeof moon.clientProgramIssueEffectSourceArtifact !== 'function' ||
            typeof sourceBindingCid !== 'string' ||
            typeof storeAuthorityCid !== 'string') {
          throw new TypeError('Invalid Effect source Artifact export');
        }
        return inspect(checked(moon.clientProgramIssueEffectSourceArtifact(
          input, receipt, token(invocation), token(retention),
          sourceBindingCid, storeAuthorityCid, limits.maxWireBytes,
          limits.maxNodes, limits.maxDepth,
        )));
      },
      issueEffectTableSourceArtifactFromExport(input: unknown, receipt: unknown, invocation: unknown,
        retention: unknown, sourceBindingCid: string, storeAuthorityCid: string, limits: Limits) {
        issuanceLimits(limits, 'private Table source Artifact');
        if (typeof moon.clientProgramIssueEffectTableSourceArtifact !== 'function' ||
            typeof sourceBindingCid !== 'string' || typeof storeAuthorityCid !== 'string') {
          throw new TypeError('Invalid private Table source export');
        }
        return inspect(checked(moon.clientProgramIssueEffectTableSourceArtifact(
          input, receipt, token(invocation), token(retention), sourceBindingCid,
          storeAuthorityCid, limits.maxWireBytes, limits.maxNodes, limits.maxDepth)));
      },
      admitCapturedEffectSourceFromTableInput(preview: unknown, memberIndex: number, invocation: unknown,
        artifact: unknown, input: unknown, storeAuthorityCid: string, limits: Limits) {
        issuanceLimits(limits, 'captured private Table source');
        const ownedPreview = computationPreviewTokens.get(preview as object);
        const ownedInput = localEffectArtifactTokens.get(input as object);
        if (ownedPreview === undefined || ownedInput === undefined ||
            !Number.isSafeInteger(memberIndex) || memberIndex < 0) {
          throw new TypeError('Invalid captured private Table source owner');
        }
        const relation = checked(moon.strategyPublicationAdmit('result_artifact',
          moon.clientProgramLocalEffectResultArtifactJson(ownedInput),
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
        return inspectEffectSource(checked(moon.strategyAdmitCapturedEffectSourceFromTableInput(
          ownedPreview, memberIndex, token(invocation), token(artifact), relation,
          storeAuthorityCid)));
      },
      admitCapturedEffectSourceFromResult(preview: unknown, memberIndex: number, invocation: unknown,
        artifact: unknown, result: unknown, storeAuthorityCid: string, limits: Limits) {
        issuanceLimits(limits, 'captured Table source');
        const ownedPreview = computationPreviewTokens.get(preview as object);
        const ownedResult = localEffectArtifactTokens.get(result as object);
        if (ownedPreview === undefined || ownedResult === undefined ||
            !Number.isSafeInteger(memberIndex) || memberIndex < 0) {
          throw new TypeError('Invalid captured Table source owner');
        }
        const publicationResult = checked(moon.strategyPublicationAdmit('result_artifact',
          moon.clientProgramLocalEffectResultArtifactJson(ownedResult),
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
        return inspectEffectSource(checked(moon.strategyAdmitCapturedEffectSourceFromResult(
          ownedPreview, memberIndex, token(invocation), token(artifact),
          publicationResult, storeAuthorityCid)));
      },
    },
    sourceControls: {
      effectSourceArtifactPreviewBinding(artifact: unknown, invocationCid: string, sourceResult: string,
        storeAuthorityCid: string) {
        return checked(moon.clientProgramEffectSourceArtifactPreviewBinding(
          token(artifact), invocationCid, sourceResult, storeAuthorityCid));
      },
      effectTableSourceArtifactPreviewBinding(artifact: unknown, invocationCid: string,
        sourceTableInput: string, storeAuthorityCid: string) {
        return checked(moon.clientProgramEffectTableSourceArtifactPreviewBinding(
          token(artifact), invocationCid, sourceTableInput, storeAuthorityCid));
      },
      capturedEffectSourceHoldingCid(source: unknown) {
        return moon.strategyCapturedEffectSourceHoldingCid(
          effectSourceToken(source));
      },
      capturedEffectSourceArtifactCid(source: unknown) {
        return moon.strategyCapturedEffectSourceArtifactCid(
          effectSourceToken(source));
      },
      capturedEffectSourceStoreAuthorityCid(source: unknown) {
        return moon.strategyCapturedEffectSourceStoreAuthorityCid(
          effectSourceToken(source));
      },
    },
    inventoryControls: {
      effectfulComputationEvidenceChainValid(chain: CaptureChain, preview: unknown, limits: Limits) {
        issuanceLimits(limits, 'Effectful computation evidence chain');
        const ownedPreview = computationPreviewTokens.get(preview as object);
        if (ownedPreview === undefined || !Array.isArray(chain?.definitions) ||
            !Array.isArray(chain.artifacts)) {
          throw new TypeError('Invalid Effectful computation evidence chain');
        }
        const prepared = recoveredEffectCaptures.get(chain.capturedRun as object);
        if (prepared !== undefined) return moon.clientProgramRecoveredEffectCapturedRunChainValid(
          token(chain.runDefinition), token(chain.invocation), chain.definitions.map(token), chain.artifacts.map(token),
          token(chain.manifest), token(chain.computationReceipt), token(chain.capturedRun), prepared, ownedPreview,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth);
        return moon.strategyEffectfulComputationEvidenceChainValid(
          token(chain.runDefinition), token(chain.invocation),
          chain.definitions.map(token), chain.artifacts.map(token),
          token(chain.manifest), token(chain.computationReceipt),
          token(chain.capturedRun), ownedPreview,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth,
        );
      },
      capturedEffectSourceRecoveryInventoryValid(preview: unknown, sources: readonly CaptureSource[]) {
        const ownedPreview = computationPreviewTokens.get(preview as object);
        if (ownedPreview === undefined || !Array.isArray(sources) ||
            sources.some(value => !Number.isSafeInteger(value?.memberIndex))) {
          throw new TypeError('Invalid recovered Effect source inventory');
        }
        return moon.strategyCapturedEffectSourceRecoveryInventoryValid(
          ownedPreview, sources.map(value => value.memberIndex),
          sources.map(value => token(value.artifact)),
        );
      },
      hasPreparedCapturedEffectRun(capturedRun: unknown) {
        token(capturedRun);
        return recoveredEffectCaptures.has(capturedRun as object);
      },
      prepareCapturedEffectSourceInventory(chain: CaptureChain, preview: unknown,
        sources: readonly CaptureSource[], storeAuthorityCid: string, limits: Limits) {
        token(chain.capturedRun);
        const prepared = recoveredEffectCaptures.get(chain.capturedRun as object);
        if (prepared === undefined) return undefined;
        issuanceLimits(limits, 'prepared recovered Effect source inventory');
        const ownedPreview = computationPreviewTokens.get(preview as object);
        if (ownedPreview === undefined || !Array.isArray(sources) ||
            sources.some(value => !Number.isSafeInteger(value?.memberIndex)) ||
            typeof storeAuthorityCid !== 'string') {
          throw new TypeError('Invalid prepared Effect source inventory');
        }
        // Existing decoded Read backing precedes these transient index vectors
        // and returned original Source handles. No second persistent cache or
        // replacement owner is created; the complete checked context is reused.
        const originals = checked(moon.clientProgramRecoveredEffectCapturedRunSources(
          token(chain.runDefinition), token(chain.invocation), chain.definitions.map(token),
          chain.artifacts.map(token), token(chain.manifest), token(chain.computationReceipt),
          token(chain.capturedRun), prepared, ownedPreview,
          sources.map(value => value.memberIndex), sources.map(value => token(value.artifact)),
          storeAuthorityCid, limits.maxWireBytes, limits.maxNodes, limits.maxDepth)) as readonly unknown[];
        return Object.freeze(originals.map(inspectEffectSource));
      },
      capturedEffectSourceInventoryFromCaptureValid(preview: unknown, sources: readonly CaptureSource[],
        invocation: unknown, capturedRun: unknown, storeAuthorityCid: string, limits: Limits) {
        issuanceLimits(limits, 'recovered Effect source inventory');
        const ownedPreview = computationPreviewTokens.get(preview as object);
        if (ownedPreview === undefined || !Array.isArray(sources) ||
            sources.some(value => !Number.isSafeInteger(value?.memberIndex)) ||
            typeof storeAuthorityCid !== 'string') {
          throw new TypeError('Invalid recovered Effect source inventory');
        }
        return moon.strategyCapturedEffectSourceInventoryFromCaptureValid(
          ownedPreview, sources.map(value => value.memberIndex),
          sources.map(value => token(value.artifact)), token(invocation),
          token(capturedRun), storeAuthorityCid, limits.maxWireBytes,
          limits.maxNodes, limits.maxDepth);
      },
      capturedEffectSourceInventoryFromResultsValid(preview: unknown, sources: readonly CaptureSource[],
        limits: Limits) {
        issuanceLimits(limits, 'captured Table source inventory');
        const ownedPreview = computationPreviewTokens.get(preview as object);
        if (ownedPreview === undefined || !Array.isArray(sources)) {
          throw new TypeError('Invalid captured Table source inventory');
        }
        const results = sources.map(value => {
          const owned = localEffectArtifactTokens.get(value.result as object);
          if (owned === undefined || !Number.isSafeInteger(value.memberIndex)) {
            throw new TypeError('Foreign captured Table source Result');
          }
          return checked(moon.strategyPublicationAdmit('result_artifact',
            moon.clientProgramLocalEffectResultArtifactJson(owned),
            limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
        });
        return moon.strategyCapturedEffectSourceInventoryFromResultsValid(ownedPreview,
          sources.map(value => value.memberIndex),
          sources.map(value => token(value.artifact)), results);
      },
      capturedEffectSourceInventoryFromArtifactsValid(preview: unknown, sources: readonly CaptureSource[],
        limits: Limits) {
        issuanceLimits(limits, 'captured Relation source inventory');
        const ownedPreview = computationPreviewTokens.get(preview as object);
        if (ownedPreview === undefined || !Array.isArray(sources)) {
          throw new TypeError('Invalid captured Relation source inventory');
        }
        const relations = sources.map(value => {
          const owned = localEffectArtifactTokens.get(value.result as object);
          if (owned === undefined || !Number.isSafeInteger(value.memberIndex)) {
            throw new TypeError('Foreign captured Relation source Artifact');
          }
          return checked(moon.strategyPublicationAdmit('result_artifact',
            moon.clientProgramLocalEffectResultArtifactJson(owned),
            limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
        });
        return moon.strategyCapturedEffectSourceInventoryFromArtifactsValid(ownedPreview,
          sources.map(value => value.memberIndex),
          sources.map(value => token(value.artifact)), relations);
      },
      localEffectResultPayloadBinding(artifact: EffectArtifact, runDefinition: unknown) {
        const owned = localEffectArtifactTokens.get(artifact as object);
        if (owned === undefined) {
          throw new TypeError('Foreign local Effect Result artifact');
        }
        const binding = checked(moon.clientProgramLocalEffectResultPayloadBinding(
          owned, token(runDefinition)));
        return Object.freeze({artifactCid: artifact.identity,
          physicalCid: runtimeField(binding, 0) as string, byteCount: runtimeField(binding, 1) as number});
      },
      // Schema material from the authenticated capture, not current configuration.
      capturedEffectDependencySchemas(capturedRun: unknown) {
        const prepared = recoveredEffectCaptures.get(capturedRun as object);
        if (prepared !== undefined) return Object.freeze(moon.clientProgramRecoveredEffectCapturedRunSchemas(prepared)
          .map(pair => Object.freeze({cid:runtimeField(pair,0) as string, wire:runtimeField(pair,1) as string})));
        const captured = inspect(token(capturedRun));
        const inventory = (JSON.parse(captured.wire) as CapturedRunWire).effect_context?.effect_dependency_inventory;
        if (captured.name !== 'captured_run' || !Array.isArray(inventory) || inventory.length > 4096) {
          throw new TypeError('InvalidEffectDependencySchemas');
        }
        // Original canonical bodies admitted by the CapturedRun/dependency Owner,
        // never reconstructed from current Catalogs or observed row values.
        return Object.freeze(inventory.filter(entry => entry.kind === 'relation_schema').map(entry => {
          if (typeof entry.cid !== 'string' || !/^sha256:[0-9a-f]{64}$/u.test(entry.cid) ||
              entry.body === null || typeof entry.body !== 'object' || Array.isArray(entry.body)) {
            throw new TypeError('InvalidEffectDependencySchemas');
          }
          return Object.freeze({cid: entry.cid, wire: JSON.stringify(entry.body)});
        }));
      },
      // Physical custody metadata is not semantic identity or permission.
      // Callers first validate the Captured Run chain; issuance binds receipts.
      capturedEffectDependencyPayloadBindings(capturedRun: unknown, bindings: readonly PayloadBinding[]) {
        const captured = inspect(token(capturedRun));
        const prepared = recoveredEffectCaptures.get(capturedRun as object);
        const inventory = prepared === undefined ? (JSON.parse(captured.wire) as CapturedRunWire).effect_context?.effect_dependency_inventory : undefined;
        if (captured.name !== 'captured_run' || (prepared === undefined && !Array.isArray(inventory)) ||
            !Array.isArray(bindings) || (prepared === undefined && bindings.length > 4096)) {
          throw new TypeError('InvalidEffectDependencyPayloadBindings');
        }
        const required = new Set(prepared === undefined ? inventory!.filter(entry =>
          entry.kind === 'result_artifact' || entry.kind === 'table_input_artifact').map(entry => entry.cid)
          : moon.clientProgramRecoveredEffectCapturedRunPayloads(prepared));
        const seen = new Set();
        const owned = bindings.map(binding => {
          if (binding === null || typeof binding !== 'object' ||
              Object.keys(binding).sort().join(',') !==
                'artifact_cid,byte_count,physical_cid' ||
              !required.has(binding.artifact_cid) ||
              seen.has(binding.artifact_cid) ||
              typeof binding.physical_cid !== 'string' ||
              !/^sha256:[0-9a-f]{64}$/u.test(binding.physical_cid) ||
              !Number.isSafeInteger(binding.byte_count) || binding.byte_count < 0) {
            throw new TypeError('InvalidEffectDependencyPayloadBindings');
          }
          seen.add(binding.artifact_cid);
          return Object.freeze({...binding});
        });
        if (seen.size !== required.size) {
          throw new TypeError('IncompleteEffectDependencyPayloadBindings');
        }
        return Object.freeze(owned);
      },
    },
  };
}
