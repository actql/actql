// The Local package stages its adapter graph after the TypeScript emit.
// Resolve the corresponding authored adapter types independently of that
// staging directory. The shipped entry points still load the staged JS.
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

// The existing Embedded Local JavaScript Host supplies this public boundary.
// The types come from the same package declarations served to consumers.
declare module '*/adapters/host-node/embedded-local.mjs' {
  export const connectEmbeddedLocal: typeof import('./index.d.ts').connect;
  export const publishInstalledSource: typeof import('./index.d.ts').publishSource;
  export const publishInstalledEffect: typeof import('./index.d.ts').publishEffect;
  export const openInstalledRemoteHttpHost: typeof import('./http-host.d.ts').openInstalledRemoteHttpHost;
}

declare module '*_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js' {
  export function clientRenderStaticExplanationNarrative(wire: string, locale: string): unknown;
}
