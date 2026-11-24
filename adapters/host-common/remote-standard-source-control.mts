// The original Common port owns Factory and Session admission. The adapter
// forwards its existing configuration slots and physical cleanup callbacks.
type StandardSourceConfiguration = Readonly<{
  schemaContractCid: string;
  viewContractCid: string;
  codecContractCid: string;
  sequence: unknown;
  program: unknown;
  bindingLimits?: Readonly<{
    maxBindingBytes?: number;
    maxChunks?: number;
    maxManifestBytes?: number;
    maxReferencedBytes?: bigint;
  }> | null;
  sourceLimits?: Readonly<{
    maxRows?: number;
    maxWireBytes?: number;
    maxReadBytes?: number;
    maxEntries?: number;
    maxNameBytes?: number;
    values?: Readonly<{
      maxNodes?: number;
      maxTextBytes?: number;
      maxDepth?: number;
      maxWork?: number;
    }> | null;
    wire?: Readonly<{
      maxBytes?: number;
      maxNodes?: number;
      maxDepth?: number;
      maxTextBytes?: number;
    }> | null;
  }> | null;
}>;

type Claim = Readonly<{request: unknown; destinationReceipt: unknown}>;
type PhysicalObservation = () => boolean;
type OptionalCount = number | undefined;
type CommonStandardSourceBindings = {
  strategyRemoteStandardSourceFactoryRegister(
    schemaContractCid: string, viewContractCid: string, codecContractCid: string,
    sequence: unknown, program: unknown, maxBindingBytes: OptionalCount, maxChunks: OptionalCount,
    maxManifestBytes: OptionalCount, maxReferencedBytes: bigint | undefined, maxRows: OptionalCount,
    maxWireBytes: OptionalCount, maxReadBytes: OptionalCount, maxEntries: OptionalCount,
    maxNameBytes: OptionalCount, maxValueNodes: OptionalCount, maxValueTextBytes: OptionalCount,
    maxValueDepth: OptionalCount, maxValueWork: OptionalCount, maxRowBytes: OptionalCount,
    maxRowNodes: OptionalCount, maxRowDepth: OptionalCount, maxRowTextBytes: OptionalCount,
  ): unknown;
  strategyRemoteStandardSourceFactoryRequestCid(factory: unknown, binding: unknown): unknown;
  strategyRemoteStandardSourceSessionStart(factory: unknown, dispatch: unknown, binding: unknown,
    request: unknown, receipt: unknown, available: PhysicalObservation, release: PhysicalObservation): unknown;
  strategyRemoteStandardSourceSessionAuthorizes(session: unknown, request: unknown, receipt: unknown): boolean;
  strategyRemoteStandardSourceSessionFeed(session: unknown, index: number, bytes: Uint8Array): boolean;
  strategyRemoteStandardSourceSessionFinish(session: unknown): unknown;
  strategyRemoteStandardSourceSessionCancel(session: unknown): unknown;
  strategyRemoteStandardSourceCaptured(source: unknown): unknown;
  strategyRemoteStandardSourceRelease(source: unknown): boolean;
  strategyRemoteStandardInputFailureCode(failure: unknown): string;
  strategyRemoteStandardInputFailureCleanupPending(failure: unknown): boolean;
  strategyRemoteStandardInputFailureCleanupRetry(failure: unknown): boolean;
};

const remoteStandardSourceControls = new WeakMap<object, ReturnType<typeof createRemoteStandardSourceControl>>();

export function remoteStandardSourceControl(moon: CommonStandardSourceBindings) {
  let control = remoteStandardSourceControls.get(moon);
  if (control !== undefined) return control;
  control = createRemoteStandardSourceControl(moon);
  remoteStandardSourceControls.set(moon, control);
  return control;
}

function createRemoteStandardSourceControl(moon: CommonStandardSourceBindings) {
  return Object.freeze({
    register(configuration: StandardSourceConfiguration) {
      if (configuration === null || typeof configuration !== 'object') {
        throw new TypeError('Invalid remote standard source configuration');
      }
      const binding = configuration.bindingLimits;
      const source = configuration.sourceLimits;
      const values = source?.values;
      const wire = source?.wire;
      return moon.strategyRemoteStandardSourceFactoryRegister(
        configuration.schemaContractCid,
        configuration.viewContractCid,
        configuration.codecContractCid,
        configuration.sequence,
        configuration.program,
        binding?.maxBindingBytes,
        binding?.maxChunks,
        binding?.maxManifestBytes,
        binding?.maxReferencedBytes,
        source?.maxRows,
        source?.maxWireBytes,
        source?.maxReadBytes,
        source?.maxEntries,
        source?.maxNameBytes,
        values?.maxNodes,
        values?.maxTextBytes,
        values?.maxDepth,
        values?.maxWork,
        wire?.maxBytes,
        wire?.maxNodes,
        wire?.maxDepth,
        wire?.maxTextBytes,
      );
    },
    requestCid: moon.strategyRemoteStandardSourceFactoryRequestCid,
    start: (factory: unknown, dispatch: unknown, binding: unknown, claim: Claim,
      available: PhysicalObservation, release: PhysicalObservation) =>
      moon.strategyRemoteStandardSourceSessionStart(
        factory,
        dispatch,
        binding,
        claim.request,
        claim.destinationReceipt,
        available,
        release,
      ),
    authorize: (session: unknown, claim: Claim) =>
      moon.strategyRemoteStandardSourceSessionAuthorizes(
        session,
        claim.request,
        claim.destinationReceipt,
      ),
    feed: moon.strategyRemoteStandardSourceSessionFeed,
    finish: moon.strategyRemoteStandardSourceSessionFinish,
    cancel: moon.strategyRemoteStandardSourceSessionCancel,
    captured: moon.strategyRemoteStandardSourceCaptured,
    release: moon.strategyRemoteStandardSourceRelease,
    failureCode: moon.strategyRemoteStandardInputFailureCode,
    failureCleanupPending:
      moon.strategyRemoteStandardInputFailureCleanupPending,
    retryFailureCleanup:
      moon.strategyRemoteStandardInputFailureCleanupRetry,
  });
}
