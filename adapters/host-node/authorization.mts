// Node Host installation of the execution-authorization gate. The gate shares
// the standard strategy runtime, so an evaluated dispatch decision can grant
// exactly one captured-task activation without a second evaluation.
import {createAuthorizationGate} from '../host-common/authorization-gate.mjs';

type AuthorizationOptions = NonNullable<Parameters<typeof createAuthorizationGate>[0]>;
type AuthorizationRuntime = NonNullable<AuthorizationOptions['runtime']>;

const runtimeUrl = new URL(
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',
  import.meta.url,
);
let runtime: Promise<AuthorizationRuntime> | undefined;

export function loadExecutionAuthorizationRuntime() {
  return runtime ??= import(runtimeUrl.href);
}

// `options` is Host installation: account configuration text and its CID,
// trusted principal/context, optional embedded decision function, optional
// durable Checkpoint deferral and Host-declared protected Sites. Nothing here
// is read from a Program.
export async function createNodeAuthorizationGate(options: Omit<AuthorizationOptions, 'runtime'> = {}) {
  return createAuthorizationGate({
    ...options,
    runtime: await loadExecutionAuthorizationRuntime(),
  });
}
