import {checked} from './runtime-result.mjs';

type Limits = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
type CommandContentRequest = Readonly<{
  prepared: unknown; definition: unknown; captured: unknown; preview: unknown; invocation: unknown;
  source: unknown; storeAuthorityCid: string; memberIndex: number; row: number; inputName: string;
  candidate: unknown; issued: unknown; limits: Limits & Readonly<{maxFields: number; maxWork: number}>;
}>;
type GeneratedContentRequest = CommandContentRequest & Readonly<{compiled: unknown; generationIndex: number}>;
type SourceContentRequest = CommandContentRequest & Readonly<{sourceOriginal: unknown; request: unknown}>;
type Claim = Readonly<{scope: unknown; locator: unknown; key: unknown}>;
type TableLedgerBinding = Readonly<{
  preview: unknown; memberIndex: number; rowPreviewCid: string | undefined; operationWire: string;
}>;

// Generated Common bindings expose Result and nominal owner handles opaquely.
type CommonEffectRecoveryBindings = Readonly<{
  clientProgramAdmitLocalTableStorageMapping(wire: string, maxBytes: number, maxNodes: number,
    maxDepth: number): unknown;
  clientProgramBindRecoveredTablePreview(preview: unknown, memberIndex: number, invocation: unknown,
    source: unknown, captured: unknown, scope: unknown, mappingWire: string,
    storeAuthorityCid: string, maxBytes: number, maxNodes: number, maxDepth: number,
    tableMaxBytes: number, tableMaxNodes: number, tableMaxDepth: number): unknown;
  clientProgramBindTableInput(owner: unknown, inputs: unknown, memberIndex: number,
    artifact: unknown, identity: unknown, scope: unknown, operationWire: string, mappingWire: string,
    maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramBindTablePreview(input: unknown, preview: unknown, memberIndex: number): unknown;
  clientProgramCheckRecoveredTableSchemaWire(value: unknown, wire: string, maxBytes: number,
    maxNodes: number, maxDepth: number): unknown;
  clientProgramCheckSourceFreeLocalEffectPreviewIdentities(owner: unknown, inputs: unknown,
    previewWire: string, runIdentityCid: string, authoringContextCid: string, identities: unknown,
    maxWireBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramLocalEffectTableStorageMapping(artifact: unknown, maxBytes: number, maxNodes: number,
    maxDepth: number): unknown;
  clientProgramLocalTableCommitResponse(responseWire: string, statusCode: number, maxBytes: number,
    maxNodes: number, maxDepth: number): unknown;
  clientProgramLocalTableStorageMappingCid(value: unknown): string;
  clientProgramLocalTableStorageMappingJson(value: unknown): string;
  clientProgramRecoverEffectCommandContent(run: unknown, owner: unknown, definition: unknown,
    captured: unknown, preview: unknown, invocation: unknown, source: unknown,
    storeAuthorityCid: string, generationIndex: number, memberIndex: number, row: number,
    inputName: string, candidate: unknown, content: unknown, maxFields: number, maxWork: number,
    maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramRecoverSourceEffectCommandContent(original: unknown, owner: unknown, request: unknown,
    definition: unknown, captured: unknown, preview: unknown, invocation: unknown, source: unknown,
    storeAuthorityCid: string, memberIndex: number, row: number, inputName: string,
    candidate: unknown, content: unknown, maxFields: number, maxWork: number, maxBytes: number,
    maxNodes: number, maxDepth: number): unknown;
  clientProgramRecoveredEffectCommandContentMatches(value: unknown, run: unknown, owner: unknown,
    definition: unknown, captured: unknown, preview: unknown, memberIndex: number, row: number,
    inputName: string): boolean;
  clientProgramRecoveredEffectCommandContentMatchesIssued(value: unknown, content: unknown): boolean;
  clientProgramRecoveredEffectCommandContentRelease(value: unknown): undefined;
  clientProgramRecoveredEffectCommandContentWire(value: unknown): unknown;
  clientProgramRecoveredSourceEffectCommandContentMatches(value: unknown, original: unknown,
    owner: unknown, request: unknown, definition: unknown, captured: unknown, preview: unknown,
    memberIndex: number, row: number, inputName: string): boolean;
  clientProgramRecoveredSourceEffectCommandContentMatchesIssued(value: unknown, content: unknown): boolean;
  clientProgramRecoveredSourceEffectCommandContentRelease(value: unknown): undefined;
  clientProgramRecoveredSourceEffectCommandContentWire(value: unknown): unknown;
  clientProgramRecoveredTablePreviewCommitOutcome(value: unknown, responseWire: string,
    statusCode: number, maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramRecoveredTablePreviewLedgerIdentity(value: unknown): unknown;
  clientProgramRecoveredTablePreviewMappingJson(value: unknown): string;
  clientProgramRecoveredTablePreviewMatchesSource(value: unknown, source: unknown): boolean;
  clientProgramRecoveredTablePreviewMemberIndex(value: unknown): number;
  clientProgramRecoveredTablePreviewOperationJson(value: unknown): string;
  clientProgramRecoveredTablePreviewSubjectCid(value: unknown): string;
  clientProgramTableInputMatchesSource(value: unknown, artifact: unknown, identity: unknown): boolean;
  clientProgramTableInputOperationJson(value: unknown): string;
  clientProgramTableInputSchemaWire(value: unknown): string;
  clientProgramTableInputStorageMappingJson(value: unknown): string;
  clientProgramTablePreviewCommitOutcome(value: unknown, responseWire: string, statusCode: number,
    maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramTablePreviewInputAvailable(value: unknown): boolean;
  clientProgramTablePreviewLedgerIdentity(value: unknown): unknown;
  clientProgramTablePreviewMemberIndex(value: unknown): number;
  clientProgramTablePreviewOperationJson(value: unknown): string;
  clientProgramTablePreviewSubjectCid(value: unknown): string;
  strategyEffectMemberRowAdmit(preview: unknown, memberIndex: number, rowIndex: number,
    effectKind: string, scope: unknown, rowCid: string, locator: unknown, key: unknown): unknown;
  strategyEffectPreviewOrderedRowCid(preview: unknown, memberIndex: number,
    rowIndex: number): string | undefined;
}>;

type EffectRecoveryPorts = Readonly<{
  computationPreviewTokens: WeakMap<object, unknown>;
  localEffectArtifactTokens: WeakMap<object, unknown>;
  localEffectIdentityTokens: WeakMap<object, unknown>;
  tableInputTokens: WeakMap<object, unknown>;
  tablePreviewTokens: WeakMap<object, unknown>;
  recoveredTablePreviewTokens: WeakMap<object, unknown>;
  compiledContent: (value: unknown) => unknown;
  issuanceLimits: (limits: Limits, label: string) => Limits;
  token: (value: unknown) => unknown;
  effectSourceToken: (value: unknown) => unknown;
  currentControl: () => Readonly<{tablePreviewLedgerBinding(preview: unknown): TableLedgerBinding}>;
}>;

export function createEffectRecoveryControls(moon: CommonEffectRecoveryBindings, {
  computationPreviewTokens, localEffectArtifactTokens, localEffectIdentityTokens,
  tableInputTokens, tablePreviewTokens, recoveredTablePreviewTokens,
  compiledContent, issuanceLimits, token, effectSourceToken, currentControl,
}: EffectRecoveryPorts) {
  return {
    recoverEffectCommandContent({compiled, prepared, definition, captured, preview,
      invocation, source, storeAuthorityCid, generationIndex, memberIndex, row,
      inputName, candidate, issued, limits}: GeneratedContentRequest) {
      issuanceLimits(limits, 'Recovered Effect Content');
      const run = compiledContent(compiled);
      const admittedPreview = computationPreviewTokens.get(preview as object);
      if (admittedPreview === undefined || typeof inputName !== 'string' ||
          ![generationIndex, memberIndex, row, limits.maxFields, limits.maxWork]
            .every(value => Number.isSafeInteger(value) && value >= 0)) {
        throw new TypeError('Invalid recovered Effect Content input');
      }
      const original = {run, prepared, definition: token(definition), captured: token(captured),
        preview: admittedPreview, memberIndex, row, inputName};
      const view = checked(moon.clientProgramRecoverEffectCommandContent(run, prepared,
        original.definition, original.captured, admittedPreview, token(invocation), effectSourceToken(source),
        storeAuthorityCid, generationIndex, memberIndex, row, inputName, candidate, issued,
        limits.maxFields, limits.maxWork, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      let retained: typeof original | undefined = original;
      const current = () => retained !== undefined &&
        moon.clientProgramRecoveredEffectCommandContentMatches(view, original.run,
          original.prepared, original.definition, original.captured, original.preview,
          original.memberIndex, original.row, original.inputName) && retained === original;
      return Object.freeze({binding: view, current,
        matchesIssued(value: unknown) {
          return retained !== undefined &&
            moon.clientProgramRecoveredEffectCommandContentMatchesIssued(view, value) &&
            retained === original;
        },
        wire() {
          if (!current()) throw new TypeError('Recovered Effect Content unavailable');
          return checked(moon.clientProgramRecoveredEffectCommandContentWire(view)) as string;
        },
        release() {
          if (retained === undefined) return;
          moon.clientProgramRecoveredEffectCommandContentRelease(view);
          retained = undefined;
        }});
    },
    recoverSourceEffectCommandContent({sourceOriginal, prepared, request, definition,
      captured, preview, invocation, source, storeAuthorityCid, memberIndex, row,
      inputName, candidate, issued, limits}: SourceContentRequest) {
      issuanceLimits(limits, 'Recovered Source Effect Content');
      const admittedPreview = computationPreviewTokens.get(preview as object);
      if (admittedPreview === undefined || typeof inputName !== 'string' ||
          ![memberIndex, row, limits.maxFields, limits.maxWork]
            .every(value => Number.isSafeInteger(value) && value >= 0)) {
        throw new TypeError('Invalid recovered Source Effect Content input');
      }
      const original = {sourceOriginal, prepared, request, definition: token(definition),
        captured: token(captured), preview: admittedPreview, memberIndex, row, inputName};
      const view = checked(moon.clientProgramRecoverSourceEffectCommandContent(sourceOriginal,
        prepared, request, original.definition, original.captured, admittedPreview,
        token(invocation), effectSourceToken(source), storeAuthorityCid, memberIndex,
        row, inputName, candidate, issued, limits.maxFields, limits.maxWork,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      let retained: typeof original | undefined = original;
      const current = () => retained !== undefined &&
        moon.clientProgramRecoveredSourceEffectCommandContentMatches(view,
          original.sourceOriginal, original.prepared, original.request, original.definition,
          original.captured, original.preview, original.memberIndex, original.row,
          original.inputName) && retained === original;
      return Object.freeze({binding: view, current,
        matchesIssued(value: unknown) {
          return retained !== undefined &&
            moon.clientProgramRecoveredSourceEffectCommandContentMatchesIssued(view, value) &&
            retained === original;
        },
        wire() {
          if (!current()) throw new TypeError('Recovered Source Effect Content unavailable');
          return checked(moon.clientProgramRecoveredSourceEffectCommandContentWire(view)) as string;
        },
        release() {
          if (retained === undefined) return;
          moon.clientProgramRecoveredSourceEffectCommandContentRelease(view);
          retained = undefined;
        }});
    },
    localEffectTableStorageMapping(artifact: unknown, limits: Limits) {
      issuanceLimits(limits, 'Table storage mapping');
      const owned = localEffectArtifactTokens.get(artifact as object);
      if (owned === undefined) throw new TypeError('Foreign Table input Artifact');
      const issued = checked(moon.clientProgramLocalEffectTableStorageMapping(
        owned, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      return Object.freeze({
        identity: moon.clientProgramLocalTableStorageMappingCid(issued),
        wire: moon.clientProgramLocalTableStorageMappingJson(issued),
      });
    },
    admitLocalTableStorageMapping(wire: string, limits: Limits) {
      issuanceLimits(limits, 'Local Table storage mapping');
      if (typeof wire !== 'string') throw new TypeError('Invalid Local Table mapping');
      const admitted = checked(moon.clientProgramAdmitLocalTableStorageMapping(
        wire, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      return Object.freeze({
        identity: moon.clientProgramLocalTableStorageMappingCid(admitted),
        wire: moon.clientProgramLocalTableStorageMappingJson(admitted),
      });
    },
    bindTableInput(owner: unknown, inputs: unknown, memberIndex: number, artifact: unknown,
      identity: unknown, scope: unknown, operationWire: string, mappingWire: string, limits: Limits) {
      issuanceLimits(limits, 'Table input');
      const ownedArtifact = localEffectArtifactTokens.get(artifact as object);
      const ownedIdentity = localEffectIdentityTokens.get(identity as object);
      if (ownedArtifact === undefined || ownedIdentity === undefined ||
          !Number.isSafeInteger(memberIndex) || memberIndex < 0 ||
          typeof operationWire !== 'string' || typeof mappingWire !== 'string') {
        throw new TypeError('Invalid Table input owner');
      }
      const issued = checked(moon.clientProgramBindTableInput(
        owner, inputs, memberIndex, ownedArtifact, ownedIdentity, scope,
        operationWire, mappingWire, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      // Content/owner binding only. Nothing stages or dispatches a Table write.
      const value = Object.freeze({
        wire: moon.clientProgramTableInputOperationJson(issued),
      });
      tableInputTokens.set(value, issued);
      return value;
    },
    tableInputMatchesSource(input: unknown, artifact: unknown, identity: unknown) {
      const ownedInput = tableInputTokens.get(input as object);
      const ownedArtifact = localEffectArtifactTokens.get(artifact as object);
      const ownedIdentity = localEffectIdentityTokens.get(identity as object);
      if (ownedInput === undefined || ownedArtifact === undefined ||
          ownedIdentity === undefined) {
        throw new TypeError('Foreign Table input source');
      }
      return moon.clientProgramTableInputMatchesSource(ownedInput,
        ownedArtifact, ownedIdentity);
    },
    tableInputStorageMappingWire(input: unknown) {
      const owned = tableInputTokens.get(input as object);
      if (owned === undefined) throw new TypeError('Foreign Table input');
      return moon.clientProgramTableInputStorageMappingJson(owned);
    },
    tableInputSchemaWire(input: unknown) {
      const owned = tableInputTokens.get(input as object);
      if (owned === undefined) throw new TypeError('Foreign Table input');
      return moon.clientProgramTableInputSchemaWire(owned);
    },
    checkRecoveredTableSchemaWire(preview: unknown, wire: string, limits: Limits) {
      issuanceLimits(limits, 'recovered Table schema');
      const owned = recoveredTablePreviewTokens.get(preview as object);
      if (owned === undefined || typeof wire !== 'string') {
        throw new TypeError('Foreign recovered Table schema');
      }
      checked(moon.clientProgramCheckRecoveredTableSchemaWire(owned, wire,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      return wire;
    },
    bindRecoveredTablePreview(preview: unknown, memberIndex: number, invocation: unknown, source: unknown,
      capturedRun: unknown, scope: unknown, mappingWire: string, storeAuthorityCid: string, limits: Limits,
      tableLimits: Limits) {
      issuanceLimits(limits, 'recovered Table Preview');
      issuanceLimits(tableLimits, 'recovered Table material');
      const ownedPreview = computationPreviewTokens.get(preview as object);
      if (ownedPreview === undefined || !Number.isSafeInteger(memberIndex) ||
          memberIndex < 0 || typeof mappingWire !== 'string' ||
          typeof storeAuthorityCid !== 'string') {
        throw new TypeError('Invalid recovered Table Preview');
      }
      const issued = checked(moon.clientProgramBindRecoveredTablePreview(
        ownedPreview, memberIndex, token(invocation), effectSourceToken(source),
        token(capturedRun), scope, mappingWire, storeAuthorityCid,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth,
        tableLimits.maxWireBytes, tableLimits.maxNodes, tableLimits.maxDepth));
      const value = Object.freeze({
        subjectCid: moon.clientProgramRecoveredTablePreviewSubjectCid(issued),
        operationWire: moon.clientProgramRecoveredTablePreviewOperationJson(issued),
        mappingWire: moon.clientProgramRecoveredTablePreviewMappingJson(issued),
      });
      recoveredTablePreviewTokens.set(value, issued);
      return value;
    },
    recoveredTablePreviewMatchesSource(preview: unknown, source: unknown) {
      const owned = recoveredTablePreviewTokens.get(preview as object);
      if (owned === undefined) throw new TypeError('Foreign recovered Table Preview');
      return moon.clientProgramRecoveredTablePreviewMatchesSource(owned,
        effectSourceToken(source));
    },
    bindTablePreview(input: unknown, capturedPreview: unknown, memberIndex: number) {
      const ownedInput = tableInputTokens.get(input as object);
      if (ownedInput === undefined || !Number.isSafeInteger(memberIndex) ||
          memberIndex < 0) throw new TypeError('Invalid Table Preview input');
      const issued = checked(moon.clientProgramBindTablePreview(ownedInput,
        capturedPreview, memberIndex));
      const value = Object.freeze({
        subjectCid: moon.clientProgramTablePreviewSubjectCid(issued),
        operationWire: moon.clientProgramTablePreviewOperationJson(issued),
      });
      tablePreviewTokens.set(value, issued);
      return value;
    },
    tablePreviewInputAvailable(preview: unknown) {
      const owned = tablePreviewTokens.get(preview as object);
      if (owned === undefined) throw new TypeError('Foreign Table Preview');
      return moon.clientProgramTablePreviewInputAvailable(owned);
    },
    localTableCommitResponse(responseWire: unknown, statusCode: number, limits: Limits) {
      issuanceLimits(limits, 'Local Table physical response');
      if (typeof responseWire !== 'string' || !Number.isSafeInteger(statusCode)) {
        throw new TypeError('Invalid Local Table physical response');
      }
      return checked(moon.clientProgramLocalTableCommitResponse(responseWire,
        statusCode, limits.maxWireBytes, limits.maxNodes, limits.maxDepth)) as string;
    },
    tablePreviewCommitOutcome(preview: unknown, responseWire: unknown, statusCode: number, limits: Limits) {
      issuanceLimits(limits, 'Table commit outcome');
      const owned = tablePreviewTokens.get(preview as object);
      const recovered = recoveredTablePreviewTokens.get(preview as object);
      if (recovered !== undefined && typeof responseWire === 'string' &&
          Number.isSafeInteger(statusCode)) {
        return checked(moon.clientProgramRecoveredTablePreviewCommitOutcome(
          recovered, responseWire, statusCode, limits.maxWireBytes,
          limits.maxNodes, limits.maxDepth)) as string;
      }
      if (owned === undefined || typeof responseWire !== 'string' ||
          !Number.isSafeInteger(statusCode)) {
        throw new TypeError('Invalid Table commit response owner');
      }
      return checked(moon.clientProgramTablePreviewCommitOutcome(owned,
        responseWire, statusCode, limits.maxWireBytes, limits.maxNodes,
        limits.maxDepth)) as string;
    },
    tablePreviewLedgerBinding(preview: unknown) {
      const owned = tablePreviewTokens.get(preview as object);
      const recovered = recoveredTablePreviewTokens.get(preview as object);
      if (recovered !== undefined) {
        const identity = moon.clientProgramRecoveredTablePreviewLedgerIdentity(recovered);
        const memberIndex = moon.clientProgramRecoveredTablePreviewMemberIndex(recovered);
        return Object.freeze({preview: identity, memberIndex,
          rowPreviewCid: moon.strategyEffectPreviewOrderedRowCid(identity, memberIndex, 0),
          operationWire: moon.clientProgramRecoveredTablePreviewOperationJson(recovered)});
      }
      if (owned === undefined) throw new TypeError('Foreign Table Preview');
      const identity = moon.clientProgramTablePreviewLedgerIdentity(owned);
      const memberIndex = moon.clientProgramTablePreviewMemberIndex(owned);
      return Object.freeze({
        preview: identity, memberIndex,
        rowPreviewCid: moon.strategyEffectPreviewOrderedRowCid(identity, memberIndex, 0),
        operationWire: moon.clientProgramTablePreviewOperationJson(owned),
      });
    },
    admitTablePreviewClaim(preview: unknown, claim: Claim) {
      const binding = currentControl().tablePreviewLedgerBinding(preview);
      // The Common claim validates the selected ledger member and row as before.
      // The generated accessor exposes an option even for this admitted Table row.
      return checked(moon.strategyEffectMemberRowAdmit(binding.preview,
        binding.memberIndex, 0, 'store', claim.scope, binding.rowPreviewCid as string,
        claim.locator, claim.key));
    },
    checkSourceFreeLocalEffectPreviewIdentities(owner: unknown, inputs: unknown, wire: string,
      runIdentityCid: string, authoringContextCid: string, identities: readonly unknown[], limits: Limits) {
      issuanceLimits(limits, 'local Effect Preview identities');
      if (typeof wire !== 'string' ||
          typeof runIdentityCid !== 'string' ||
          typeof authoringContextCid !== 'string' ||
          !Array.isArray(identities)) {
        throw new TypeError('Invalid local Effect Preview identities');
      }
      const owned = identities.map(identity => {
        const token = localEffectIdentityTokens.get(identity as object);
        if (token === undefined) {
          throw new TypeError('Foreign local Effect identity');
        }
        return token;
      });
      return checked(
        moon.clientProgramCheckSourceFreeLocalEffectPreviewIdentities(
          owner, inputs, wire, runIdentityCid, authoringContextCid, owned,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
    },
  };
}
