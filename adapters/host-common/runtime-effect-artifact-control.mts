import {checked} from './runtime-result.mjs';

type Limits = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
type CommandLimits = Readonly<{maxFields: number; maxWork: number}>;
type Artifact = Readonly<{identity: string; wire: string; derivationWire: string; orderingWire: string}>;
type EffectContext = Readonly<{
  admission: unknown; runDefinition: unknown; runInvocation: unknown; observation: unknown;
}>;
type RetainedCommandContent = Readonly<{
  view: unknown; owner: unknown; inputs: unknown; memberIndex: number;
  artifact: unknown; row: number; inputName: string;
}>;
type DependencyOwner =
  | Readonly<{kind: 'keyed_source'; issued: unknown; parent: unknown; plan: unknown; request: unknown}>
  | Readonly<{kind: 'model' | 'preconsumer_model'; issued: unknown; original: unknown}>
  | Readonly<{kind: 'acquired' | 'combined_source' | 'source_free' | 'imported'; issued: unknown}>;

// The Generated Common ABI still carries its original opaque result handles.
type CommonEffectArtifactBindings = Readonly<{
  clientProgramAdmitLocalEffectSourceEvidence(owner: unknown, inputs: unknown, memberIndex: number,
    manifest: unknown, invocation: unknown, artifact: unknown, source: unknown, maxWireBytes: number,
    maxNodes: number, maxDepth: number): unknown;
  clientProgramEffectCommandContentBorrow(owner: unknown, inputs: unknown, memberIndex: number,
    artifact: unknown, row: number, inputName: string, maxFields: number, maxWork: number): unknown;
  clientProgramEffectCommandContentMatches(value: unknown, owner: unknown, inputs: unknown,
    memberIndex: number, artifact: unknown, row: number, inputName: string): boolean;
  clientProgramEffectCommandContentMatchesIssued(value: unknown, issued: unknown): boolean;
  clientProgramEffectCommandContentPrepareArtifact(owner: unknown, inputs: unknown,
    memberIndex: number, artifact: unknown, maxFields: number, maxWork: number): unknown;
  clientProgramEffectCommandContentRelease(value: unknown): undefined;
  clientProgramEffectCommandContentReleaseArtifact(artifact: unknown, quantum: number): boolean;
  clientProgramEffectCommandContentWire(value: unknown): unknown;
  clientProgramEffectResultImportObservationJson(value: unknown): string;
  clientProgramImportedEffectInvocation(value: unknown): unknown;
  clientProgramImportedEffectRelationBodies(value: unknown): unknown;
  clientProgramImportedEffectScopeJson(value: unknown): string;
  clientProgramIssueAcquiredEffectLocalResultArtifact(owner: unknown, inputs: unknown,
    exported: unknown, source: unknown, definition: unknown, receipt: unknown, admission: unknown,
    runDefinition: unknown, runInvocation: unknown, observation: unknown, maxBytes: number,
    maxNodes: number, maxDepth: number): unknown;
  clientProgramIssueCombinedSourceEffectLocalResultArtifact(owner: unknown, inputs: unknown,
    exported: unknown, source: unknown, definition: unknown, receipt: unknown, admission: unknown,
    runDefinition: unknown, runInvocation: unknown, observation: unknown, maxBytes: number,
    maxNodes: number, maxDepth: number): unknown;
  clientProgramIssueEffectResultImportObservation(owner: unknown, inputs: unknown, captured: unknown,
    manifest: unknown, artifact: unknown, maxWireBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramIssueImportedEffectEvidence(owner: unknown, inputs: unknown, unit: number,
    observations: unknown, maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramIssueImportedEffectLocalResultArtifact(owner: unknown, inputs: unknown,
    exported: unknown, imported: unknown, definition: unknown, receipt: unknown, retention: unknown,
    admission: unknown, runDefinition: unknown, runInvocation: unknown, observation: unknown,
    maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramIssueImportedLocalEffectTableArtifact(owner: unknown, inputs: unknown,
    memberIndex: number, importing: unknown, definition: unknown, imported: unknown,
    receipt: unknown, retention: unknown, admission: unknown, runDefinition: unknown,
    runInvocation: unknown, observation: unknown, maxWireBytes: number, maxNodes: number,
    maxDepth: number): unknown;
  clientProgramIssueInstalledKeyedSourceEffectLocalResultArtifact(parent: unknown, plan: unknown,
    request: unknown, inputs: unknown, exported: unknown, source: unknown, definition: unknown,
    receipt: unknown, admission: unknown, runDefinition: unknown, invocation: unknown,
    observation: unknown, maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramIssueLocalEffectResultManifest(owner: unknown, invocation: unknown,
    artifacts: unknown, maxWireBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramIssueSourceFreeExportedLocalEffectResultArtifact(owner: unknown, inputs: unknown,
    exported: unknown, invocation: unknown, definition: unknown, receipt: unknown,
    retention: unknown, admission: unknown, runDefinition: unknown, runInvocation: unknown,
    observation: unknown, maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramIssueSourceFreeLocalEffectIdentity(owner: unknown, inputs: unknown,
    memberIndex: number, artifact: unknown, maxWork: number, maxWireBytes: number, maxNodes: number,
    maxDepth: number): unknown;
  clientProgramIssueSourceFreeLocalEffectInvocation(value: unknown, unit: number,
    maxWireBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramIssueSourceFreeLocalEffectResultArtifact(owner: unknown, inputs: unknown,
    memberIndex: number, importing: unknown, definition: unknown, invocation: unknown,
    receipt: unknown, retention: unknown, admission: unknown, runDefinition: unknown,
    runInvocation: unknown, observation: unknown, maxWireBytes: number, maxNodes: number,
    maxDepth: number): unknown;
  clientProgramIssueSourceFreeLocalEffectTableArtifact(owner: unknown, inputs: unknown,
    memberIndex: number, importing: unknown, definition: unknown, invocation: unknown,
    receipt: unknown, retention: unknown, admission: unknown, runDefinition: unknown,
    runInvocation: unknown, observation: unknown, maxWireBytes: number, maxNodes: number,
    maxDepth: number): unknown;
  clientProgramLocalEffectIdentityCid(value: unknown): string;
  clientProgramLocalEffectIdentityJson(value: unknown): string;
  clientProgramLocalEffectResultManifestCid(value: unknown): string;
  clientProgramLocalEffectResultManifestJson(value: unknown): string;
  clientProgramLocalEffectSourceMatches(owner: unknown, inputs: unknown, memberIndex: number,
    manifest: unknown, invocation: unknown, artifact: unknown, source: unknown): boolean;
  clientProgramOriginalModelEffectResultArtifact(value: unknown, owner: unknown, inputs: unknown,
    exported: unknown, acquired: unknown, definition: unknown, receipt: unknown, admission: unknown,
    runDefinition: unknown, invocation: unknown, observation: unknown, maxBytes: number,
    maxNodes: number, maxDepth: number): unknown;
}>;

type EffectArtifactPorts = Readonly<{
  localEffectDependencyTokens: WeakMap<object, unknown>;
  localEffectManifestTokens: WeakMap<object, unknown>;
  localEffectArtifactTokens: WeakMap<object, unknown>;
  localEffectArtifactSources: WeakMap<object, unknown>;
  localEffectImportTokens: WeakMap<object, unknown>;
  localEffectImportSources: WeakMap<object, unknown>;
  localEffectSourceTokens: WeakMap<object, unknown>;
  localEffectIdentityTokens: WeakMap<object, unknown>;
  issuanceLimits: (limits: Limits, label: string) => Limits;
  token: (value: unknown) => unknown;
  admissionToken: (value: unknown) => unknown;
  evidenceToken: (value: unknown) => unknown;
  effectSourceToken: (value: unknown) => unknown;
  inspectLocalEffectArtifact: (value: unknown) => Artifact;
  localEffectContext: (value: unknown) => readonly [unknown, unknown, unknown, unknown];
  currentControl: () => Readonly<{seal(kind: string, body: string, limits: Limits): Readonly<{wire: string}>}>;
}>;

export function createEffectArtifactControls(moon: CommonEffectArtifactBindings, {
  localEffectDependencyTokens, localEffectManifestTokens, localEffectArtifactTokens, localEffectArtifactSources,
  localEffectImportTokens, localEffectImportSources, localEffectSourceTokens, localEffectIdentityTokens,
  issuanceLimits, token, admissionToken, evidenceToken, effectSourceToken, inspectLocalEffectArtifact,
  localEffectContext, currentControl,
}: EffectArtifactPorts) {
  const effectDependencyControls = {
    issueSourceFreeEffectEvidence(owner: unknown, unit: number, limits: Limits) {
      issuanceLimits(limits, 'Source-free Effect dependency');
      const invocation = checked(moon.clientProgramIssueSourceFreeLocalEffectInvocation(
        owner, unit, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      const scope = currentControl().seal('acquisition_scope',
        '{"sources":[],"version":"actql-acquisition-scope/0.1"}', limits);
      const value = Object.freeze({invocation, bodies: Object.freeze([
        Object.freeze({kind: 'acquisition_scope', wire: scope.wire}),
      ])});
      localEffectDependencyTokens.set(value, {kind: 'source_free', issued: invocation});
      return value;
    },
    issueEffectResultImportObservation(owner: unknown, inputs: unknown, captured: unknown, manifest: unknown,
      artifact: unknown, limits: Limits) {
      issuanceLimits(limits, 'Effect Result import observation');
      const ownedManifest = localEffectManifestTokens.get(manifest as object);
      const ownedArtifact = localEffectArtifactTokens.get(artifact as object);
      if (ownedManifest === undefined || ownedArtifact === undefined) {
        throw new TypeError('Foreign Effect Result import evidence');
      }
      const issued = checked(moon.clientProgramIssueEffectResultImportObservation(
        owner, inputs, captured, ownedManifest, ownedArtifact,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      const value = Object.freeze({
        wire: moon.clientProgramEffectResultImportObservationJson(issued),
      });
      localEffectImportTokens.set(value, issued);
      const source = localEffectArtifactSources.get(artifact as object);
      if (source !== undefined) localEffectImportSources.set(value, source);
      return value;
    },
    issueImportedEffectEvidence(owner: unknown, inputs: unknown, unit: number,
      observations: readonly object[], limits: Limits) {
      issuanceLimits(limits, 'Imported Effect evidence');
      if (!Array.isArray(observations)) {
        throw new TypeError('Invalid Effect Result import observations');
      }
      const owned = observations.map(value => {
        const issued = localEffectImportTokens.get(value);
        if (issued === undefined) {
          throw new TypeError('Foreign Effect Result import observation');
        }
        return issued;
      });
      const issued = checked(moon.clientProgramIssueImportedEffectEvidence(
        owner, inputs, unit, owned, limits.maxWireBytes, limits.maxNodes,
        limits.maxDepth));
      const value = Object.freeze({
        invocation: moon.clientProgramImportedEffectInvocation(issued),
        bodies: Object.freeze([
          Object.freeze({kind: 'acquisition_scope',
            wire: moon.clientProgramImportedEffectScopeJson(issued)}),
          ...observations.map(value => Object.freeze({
            kind: 'result_import_observation', wire: (value as Readonly<{wire: string}>).wire})),
          ...(moon.clientProgramImportedEffectRelationBodies(issued) as readonly string[]).map(wire =>
            Object.freeze({kind: 'acquisition_relation', wire})),
        ]),
      });
      const sources = observations.map(value => localEffectImportSources.get(value));
      localEffectDependencyTokens.set(value, {kind: 'imported', issued,
        originalSources: sources.every(source => source !== undefined)
          ? Object.freeze(sources) : undefined});
      return value;
    },
    issueDependentLocalEffectResultArtifact(owner: unknown, inputs: unknown, exported: unknown,
      dependency: unknown, definition: unknown, receipt: unknown, retention: unknown, context: unknown,
      limits: Limits) {
      issuanceLimits(limits, 'Dependent local Effect Result Artifact');
      const owned = localEffectDependencyTokens.get(dependency as object) as DependencyOwner | undefined;
      if (owned === undefined) {
        throw new TypeError('Foreign local Effect dependency evidence');
      }
      const exactContext = localEffectContext(context);
      const result = owned.kind === 'keyed_source'
        ? moon.clientProgramIssueInstalledKeyedSourceEffectLocalResultArtifact(
          owned.parent, owned.plan, owned.request, inputs, exported, owned.issued, definition, receipt,
          ...exactContext, limits.maxWireBytes, limits.maxNodes, limits.maxDepth)
        : owned.kind === 'combined_source'
        ? moon.clientProgramIssueCombinedSourceEffectLocalResultArtifact(
          owner, inputs, exported, owned.issued, definition, receipt,
          ...exactContext, limits.maxWireBytes, limits.maxNodes, limits.maxDepth)
        : owned.kind === 'model'
        ? moon.clientProgramOriginalModelEffectResultArtifact(
          owned.original, owner, inputs, exported, owned.issued, definition, receipt,
          ...exactContext, limits.maxWireBytes, limits.maxNodes, limits.maxDepth)
        : owned.kind === 'source_free'
        ? moon.clientProgramIssueSourceFreeExportedLocalEffectResultArtifact(
          owner, inputs, exported, owned.issued, definition, receipt,
          token(retention), ...exactContext,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth)
        : owned.kind === 'acquired'
        ? moon.clientProgramIssueAcquiredEffectLocalResultArtifact(
          owner, inputs, exported, owned.issued, definition, receipt,
          ...exactContext, limits.maxWireBytes, limits.maxNodes, limits.maxDepth)
        : moon.clientProgramIssueImportedEffectLocalResultArtifact(
          owner, inputs, exported, owned.issued, definition, receipt,
          token(retention), ...exactContext,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth);
      const value = inspectLocalEffectArtifact(checked(result));
      // Retain the same producer's nominal provenance with its existing
      // Artifact. This is an alias, not a new Source read or cleanup owner.
      if (owned.kind === 'acquired') localEffectArtifactSources.set(value, owned.issued);
      return value;
    },
  };
  const effectArtifactControls = {
    issueSourceFreeLocalEffectResultArtifact(owner: unknown, inputs: unknown, memberIndex: number,
      importing: unknown, definition: unknown, localInvocation: unknown, receipt: unknown,
      retention: unknown, context: EffectContext, limits: Limits) {
      issuanceLimits(limits, 'local Effect Result Artifact');
      if (!Number.isSafeInteger(memberIndex) || memberIndex < 0 ||
          context === null || typeof context !== 'object' ||
          !['admission', 'runDefinition', 'runInvocation', 'observation']
            .every(key => context[key as keyof EffectContext] !== undefined)) {
        throw new TypeError('Invalid local Effect Result Artifact');
      }
      const issued = checked(
        moon.clientProgramIssueSourceFreeLocalEffectResultArtifact(
          owner, inputs, memberIndex, importing, definition, localInvocation,
          receipt, token(retention), admissionToken(context.admission),
          token(context.runDefinition), token(context.runInvocation),
          evidenceToken(context.observation),
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      return inspectLocalEffectArtifact(issued);
    },
    issueSourceFreeExportedLocalEffectResultArtifact(owner: unknown, inputs: unknown, exported: unknown,
      definition: unknown, invocation: unknown, receipt: unknown, retention: unknown, context: unknown,
      limits: Limits) {
      issuanceLimits(limits, 'source-free local Manifest Result');
      return inspectLocalEffectArtifact(checked(
        moon.clientProgramIssueSourceFreeExportedLocalEffectResultArtifact(
          owner, inputs, exported, invocation, definition, receipt,
          token(retention), ...localEffectContext(context),
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth)));
    },
    issueSourceFreeLocalEffectTableArtifact(owner: unknown, inputs: unknown, memberIndex: number,
      importing: unknown, definition: unknown, localInvocation: unknown, receipt: unknown,
      retention: unknown, context: unknown, limits: Limits) {
      issuanceLimits(limits, 'private Table semantic Artifact');
      if (!Number.isSafeInteger(memberIndex) || memberIndex < 0) {
        throw new TypeError('Invalid private Table member');
      }
      return inspectLocalEffectArtifact(checked(
        moon.clientProgramIssueSourceFreeLocalEffectTableArtifact(
          owner, inputs, memberIndex, importing, definition, localInvocation,
          receipt, token(retention), ...localEffectContext(context),
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth)));
    },
    issueDependentLocalEffectTableArtifact(owner: unknown, inputs: unknown, memberIndex: number,
      importing: unknown, dependency: unknown, definition: unknown, receipt: unknown, retention: unknown,
      context: unknown, limits: Limits) {
      issuanceLimits(limits, 'dependent private Table semantic Artifact');
      const owned = localEffectDependencyTokens.get(dependency as object) as DependencyOwner | undefined;
      if (owned === undefined || !Number.isSafeInteger(memberIndex) || memberIndex < 0) {
        throw new TypeError('Foreign private Table dependency evidence');
      }
      const exactContext = localEffectContext(context);
      const result = owned.kind === 'source_free'
        ? moon.clientProgramIssueSourceFreeLocalEffectTableArtifact(
          owner, inputs, memberIndex, importing, definition, owned.issued,
          receipt, token(retention), ...exactContext,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth)
        : owned.kind === 'imported'
        ? moon.clientProgramIssueImportedLocalEffectTableArtifact(
          owner, inputs, memberIndex, importing, definition, owned.issued,
          receipt, token(retention), ...exactContext,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth)
        : undefined;
      if (result === undefined) {
        throw new TypeError('UnavailableAcquiredPrivateTableEvidence');
      }
      return inspectLocalEffectArtifact(checked(result));
    },
    issueLocalEffectResultManifest(owner: unknown, invocation: unknown, artifacts: readonly unknown[],
      limits: Limits) {
      issuanceLimits(limits, 'local Effect Result Manifest');
      if (!Array.isArray(artifacts) || artifacts.length === 0) {
        throw new TypeError('Invalid local Effect Result Manifest');
      }
      const owned = artifacts.map(artifact => {
        const token = localEffectArtifactTokens.get(artifact as object);
        if (token === undefined) {
          throw new TypeError('Foreign local Effect Result Artifact');
        }
        return token;
      });
      const issued = checked(moon.clientProgramIssueLocalEffectResultManifest(
        owner, invocation, owned, limits.maxWireBytes, limits.maxNodes,
        limits.maxDepth));
      const value = Object.freeze({
        identity: moon.clientProgramLocalEffectResultManifestCid(issued),
        wire: moon.clientProgramLocalEffectResultManifestJson(issued),
      });
      localEffectManifestTokens.set(value, issued);
      return value;
    },
    localEffectSourceMatches(owner: unknown, inputs: unknown, memberIndex: number, manifest: unknown,
      invocation: unknown, artifact: unknown, source: unknown) {
      const ownedManifest = localEffectManifestTokens.get(manifest as object);
      const ownedArtifact = localEffectArtifactTokens.get(artifact as object);
      if (ownedManifest === undefined || ownedArtifact === undefined ||
          !Number.isSafeInteger(memberIndex) || memberIndex < 0) {
        throw new TypeError('Foreign local Effect source evidence');
      }
      return moon.clientProgramLocalEffectSourceMatches(
        owner, inputs, memberIndex, ownedManifest, invocation,
        ownedArtifact, effectSourceToken(source));
    },
    admitLocalEffectSourceEvidence(owner: unknown, inputs: unknown, memberIndex: number, manifest: unknown,
      invocation: unknown, artifact: unknown, source: unknown, limits: Limits) {
      issuanceLimits(limits, 'local Effect source evidence');
      const ownedManifest = localEffectManifestTokens.get(manifest as object);
      const ownedArtifact = localEffectArtifactTokens.get(artifact as object);
      if (ownedManifest === undefined || ownedArtifact === undefined ||
          !Number.isSafeInteger(memberIndex) || memberIndex < 0) {
        throw new TypeError('Foreign local Effect source evidence');
      }
      const issued = checked(moon.clientProgramAdmitLocalEffectSourceEvidence(
        owner, inputs, memberIndex, ownedManifest, invocation,
        ownedArtifact, effectSourceToken(source), limits.maxWireBytes,
        limits.maxNodes, limits.maxDepth));
      const value = Object.freeze({kind: 'captured-local-effect-source'});
      localEffectSourceTokens.set(value, issued);
      return value;
    },
    issueSourceFreeLocalEffectIdentity(owner: unknown, inputs: unknown, memberIndex: number,
      artifact: unknown, limits: Limits & Readonly<{maxWork: number}>) {
      issuanceLimits(limits, 'local Effect identity');
      const ownedArtifact = localEffectArtifactTokens.get(artifact as object);
      if (ownedArtifact === undefined ||
          !Number.isSafeInteger(memberIndex) || memberIndex < 0 ||
          !Number.isSafeInteger(limits.maxWork) || limits.maxWork < 1) {
        throw new TypeError('Invalid local Effect identity owner');
      }
      const issued = checked(
        moon.clientProgramIssueSourceFreeLocalEffectIdentity(
          owner, inputs, memberIndex, ownedArtifact, limits.maxWork,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      const value = Object.freeze({
        identity: moon.clientProgramLocalEffectIdentityCid(issued),
        wire: moon.clientProgramLocalEffectIdentityJson(issued),
      });
      localEffectIdentityTokens.set(value, issued);
      return value;
    },
    prepareEffectCommandContentArtifact(owner: unknown, inputs: unknown, memberIndex: number,
      artifact: unknown, limits: CommandLimits): undefined {
      const owned = localEffectArtifactTokens.get(artifact as object);
      if (owned === undefined || ![memberIndex, limits?.maxFields, limits?.maxWork]
        .every(value => Number.isSafeInteger(value) && value >= 0)) {
        throw new TypeError('Invalid original Effect Content Artifact');
      }
      checked(moon.clientProgramEffectCommandContentPrepareArtifact(
        owner, inputs, memberIndex, owned, limits.maxFields, limits.maxWork));
    },
    releaseEffectCommandContentArtifact(artifact: unknown, quantum: number) {
      const owned = localEffectArtifactTokens.get(artifact as object);
      if (owned === undefined || !Number.isSafeInteger(quantum) || quantum <= 0) {
        throw new TypeError('Invalid original Effect Content retirement');
      }
      return moon.clientProgramEffectCommandContentReleaseArtifact(owned, quantum);
    },
    borrowEffectCommandContent(owner: unknown, inputs: unknown, memberIndex: number, artifact: unknown,
      row: number, inputName: string, limits: CommandLimits) {
      const ownedArtifact = localEffectArtifactTokens.get(artifact as object);
      if (ownedArtifact === undefined || typeof inputName !== 'string' ||
          ![memberIndex, row, limits?.maxFields, limits?.maxWork].every(
            value => Number.isSafeInteger(value) && value >= 0)) {
        throw new TypeError('Invalid original Effect Content input');
      }
      const view = checked(moon.clientProgramEffectCommandContentBorrow(
        owner, inputs, memberIndex, ownedArtifact, row, inputName,
        limits.maxFields, limits.maxWork));
      let original: RetainedCommandContent | undefined = {view, owner, inputs, memberIndex,
        artifact: ownedArtifact, row, inputName};
      const current = () => original !== undefined &&
        moon.clientProgramEffectCommandContentMatches(original.view,
          original.owner, original.inputs, original.memberIndex,
          original.artifact, original.row, original.inputName);
      // A physical preparation retains this view before awaiting. Its wire is
      // observed DATA, not byte custody, a capacity loan or a read/send grant.
      return Object.freeze({binding: view, current,
        matchesIssued(issued: unknown) {
          const retained = original;
          return retained !== undefined &&
            moon.clientProgramEffectCommandContentMatchesIssued(retained.view, issued) &&
            original === retained;
        },
        wire() {
          if (!current()) throw new TypeError('Original Effect Content unavailable');
          return checked(moon.clientProgramEffectCommandContentWire(original!.view)) as string;
        },
        release() {
          if (original === undefined) return;
          moon.clientProgramEffectCommandContentRelease(original.view);
          original = undefined;
        }});
    },
  };
  return {effectDependencyControls, effectArtifactControls};
}
