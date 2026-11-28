// The Local package stages its adapter graph after the TypeScript emit.
// Resolve the corresponding authored adapter types independently of that
// staging directory. The shipped entry points still load the staged JS.
declare module '*/adapters/host-node/model-http/normal-http-chat.mjs' {
  export const createHttpChatProvider: typeof import('../provider-http/_internal/normal-http-chat.mjs').createHttpChatProvider;
}

declare module '*/adapters/host-node/installed-connectors.mjs' {
  export const createInstalledConnectorTable: typeof import('../../adapters/host-node/installed-connectors.mjs').createInstalledConnectorTable;
}

declare module '*/adapters/host-node/installed-row-source.mjs' {
  export const createInstalledRowSource: typeof import('../../adapters/host-node/installed-row-source.mjs').createInstalledRowSource;
  export const rowSourceCheckEnvironment: typeof import('../../adapters/host-node/installed-row-source.mjs').rowSourceCheckEnvironment;
  export const rowSourceMapping: typeof import('../../adapters/host-node/installed-row-source.mjs').rowSourceMapping;
  export const installRowSourceAuthorization: typeof import('../../adapters/host-node/installed-row-source.mjs').installRowSourceAuthorization;
  export const openRowSourceCredentialSite: typeof import('../../adapters/host-node/installed-row-source.mjs').openRowSourceCredentialSite;
}

declare module '*/adapters/host-node/installed-row-effect.mjs' {
  export const createInstalledRowEffect: typeof import('../../adapters/host-node/installed-row-effect.mjs').createInstalledRowEffect;
}

declare module '*/adapters/host-node/installed-rest-source.mjs' {
  export const createInstalledRestSource: typeof import('../../adapters/host-node/installed-rest-source.mjs').createInstalledRestSource;
}

declare module '*/adapters/host-node/installed-host-cleanup.mjs' {
  export const retainInstalledHostInitializationFailure: typeof import('../../adapters/host-node/installed-host-cleanup.mjs').retainInstalledHostInitializationFailure;
}

declare module '*/adapters/host-common/runtime-result.mjs' {
  export const checked: typeof import('../../adapters/host-common/runtime-result.mjs').checked;
}

declare module '*/adapters/host-common/owned-invocation-context.mjs' {
  export const invokeScopedCredentialOperation: typeof import('../../adapters/host-common/owned-invocation-context.mjs').invokeScopedCredentialOperation;
}

declare module '*/adapters/host-common/observation.mjs' {
  export const createHostObservationConnection: typeof import('../../adapters/host-common/observation.mjs').createHostObservationConnection;
  export const observationLimits: typeof import('../../adapters/host-common/observation.mjs').observationLimits;
  export const installHostObservation: typeof import('../../adapters/host-common/observation.mjs').installHostObservation;
}

declare module '*/adapters/host-common/http-exchange.mjs' {
  export const exchangeLimits: typeof import('../../adapters/host-common/http-exchange.mjs').exchangeLimits;
}

declare module '*/adapters/host-common/compiler-binding.generated.mjs' {
  export const runtimeField: typeof import('../../adapters/host-common/compiler-binding.generated.mjs').runtimeField;
  export const runtimeIsError: typeof import('../../adapters/host-common/compiler-binding.generated.mjs').runtimeIsError;
  export const runtimeIsOk: typeof import('../../adapters/host-common/compiler-binding.generated.mjs').runtimeIsOk;
  export const runtimeIsBoxedSome: typeof import('../../adapters/host-common/compiler-binding.generated.mjs').runtimeIsBoxedSome;
}

// The staged runtime path resolves to the authoritative Embedded Local
// producer's types during compile, before the copied runtime graph exists.
declare module '*/adapters/host-node/embedded-local.mjs' {
  export const connectEmbeddedLocal: typeof import('../../adapters/host-node/embedded-local.mjs').connectEmbeddedLocal;
  export const publishInstalledSource: typeof import('../../adapters/host-node/embedded-local.mjs').publishInstalledSource;
  export const publishInstalledEffect: typeof import('../../adapters/host-node/embedded-local.mjs').publishInstalledEffect;
  export const openInstalledRemoteHttpHost: typeof import('../../adapters/host-node/embedded-local.mjs').openInstalledRemoteHttpHost;
}

declare module '*_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js' {
  // The clean TypeScript prepare runs before MoonBit emits this module. Use
  // the same narrow runtime ports as the installed adapters and their tests.
  type Representation = Parameters<typeof import('../../adapters/store-local/managed-physical-representation.mjs').managedPhysicalRepresentation>[5];
  type FailureProgress = Parameters<typeof import('../../adapters/host-common/managed-failure.mjs').beginManagedFailureProgress>[0];
  type CheckEnvironment = Parameters<typeof import('../../adapters/host-node/installed-check-environment.mjs').composeInstalledCheckEnvironment>[0];
  type Initialization = Parameters<typeof import('../../adapters/local-node/request-preparation-adapter.mjs').openHostInitializationPreparation>[1];
  type Account = Parameters<typeof import('../../adapters/host-node/account-construction.mjs').createAccountConstruction>[0];

  export const physicalManifestAdmit: Representation['physicalManifestAdmit'];
  export const physicalRepresentationContracts: Representation['physicalRepresentationContracts'];
  export const strategyHostBeginManagedFailureProgress: FailureProgress['strategyHostBeginManagedFailureProgress'];
  export const strategyHostManagedFailureAction: FailureProgress['strategyHostManagedFailureAction'];
  export const strategyHostRecordManagedFailureAdditionalClosed: FailureProgress['strategyHostRecordManagedFailureAdditionalClosed'];
  export const strategyHostRecordManagedFailureOperationsCloseAttempted: FailureProgress['strategyHostRecordManagedFailureOperationsCloseAttempted'];
  export const strategyHostRecordManagedFailureOperationsClosed: FailureProgress['strategyHostRecordManagedFailureOperationsClosed'];
  export const strategyHostRecordManagedFailureCleanupStopped: FailureProgress['strategyHostRecordManagedFailureCleanupStopped'];
  export const strategyHostRecordManagedFailureExecutionSettled: FailureProgress['strategyHostRecordManagedFailureExecutionSettled'];
  export const strategyHostRecordManagedFailureCleanupRefreshed: FailureProgress['strategyHostRecordManagedFailureCleanupRefreshed'];
  export const clientProgramCheckEnvironment: CheckEnvironment['clientProgramCheckEnvironment'];

  export const clientLocalResourcePolicyOriginal: Initialization['clientLocalResourcePolicyOriginal'];
  export const clientLocalPreparationResourceLimits: Initialization['clientLocalPreparationResourceLimits'];
  export const clientProgramPrepareLocalPreparationAdmission: Initialization['clientProgramPrepareLocalPreparationAdmission'];
  export const clientProgramCleanupLocalPreparationAdmission: Initialization['clientProgramCleanupLocalPreparationAdmission'];
  export const clientProgramBeginHostInitializationPreparation: Initialization['clientProgramBeginHostInitializationPreparation'];
  export const clientProgramCloseHostInitializationPreparation: Initialization['clientProgramCloseHostInitializationPreparation'];
  export const clientProgramAccountReadControlBytes: Account['moon']['clientProgramAccountReadControlBytes'];
  export const clientProgramCloseAccountRead: Account['moon']['clientProgramCloseAccountRead'];
  export const clientProgramPrepareAccountReadConstruction: Account['moon']['clientProgramPrepareAccountReadConstruction'];
  export const clientProgramCompleteAccountReadConstruction: Account['moon']['clientProgramCompleteAccountReadConstruction'];
  export const executionAuthorizationAdmitPrepared: Account['moon']['executionAuthorizationAdmitPrepared'];
  export function clientProgramPrepareHostAccountRead(parent: unknown): ReturnType<Account['prepareRead']>;

  export function clientRenderStaticExplanationNarrative(wire: string, locale: string): unknown;
}
