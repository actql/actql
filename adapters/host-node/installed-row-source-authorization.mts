import {contentCid as cid, createLocalAuthorizationGate} from './local-account-config.mjs';
import {rejectInstalledRowSource as fail} from './installed-row-source-mapping.mjs';

type Gate = Awaited<ReturnType<typeof createLocalAuthorizationGate>>;
type Decision = Awaited<ReturnType<Gate['authorize']>>;
type Context = NonNullable<Gate['context']>;
type GateOptions = NonNullable<Parameters<typeof createLocalAuthorizationGate>[0]> & Readonly<{runtime?: unknown}>;
type Installation = Readonly<{
  accountConfiguration: unknown; principalId: unknown; root: unknown; connectorRegistration: unknown;
  originalContext?: Context; gateOptions?: GateOptions;
}>;
type Authorization = Gate & Readonly<{
  context: Context; accountConfiguration: string; accountConstruction?: GateOptions['accountConstruction'];
  issued(decision: unknown): boolean;
}>;

const text = (value: unknown): value is string => typeof value === 'string' && value.length > 0;
const cidPattern = /^sha256:[0-9a-f]{64}$/u;

// The Host account gate of one installed row source, under its own context.
// A trusted existing installer may retain its original immutable context
// preimage. This is installation DATA, not a decision, grant or current ACK;
// the same Account Owner still admits the configuration and every decision.
export async function installRowSourceAuthorization({accountConfiguration,
  principalId, root, connectorRegistration, originalContext, gateOptions = {}}: Installation): Promise<Authorization> {
  if (!text(accountConfiguration) || !text(principalId) || !text(root) ||
      !text(connectorRegistration) ||
      (originalContext !== undefined &&
        (originalContext === null || typeof originalContext !== 'object' ||
          !Object.isFrozen(originalContext) ||
          Object.getPrototypeOf(originalContext) !== Object.prototype ||
          Object.keys(originalContext).length !== 2 ||
          !Object.hasOwn(originalContext, 'principal') ||
          !Object.hasOwn(originalContext, 'contextCid') ||
          originalContext.principal !== principalId ||
          !cidPattern.test(originalContext.contextCid ?? '')))) {
    fail('InvalidRowSourceAuthorizationInstallation');
  }
  const context = originalContext ?? Object.freeze({principal: principalId,
    contextCid: cid({version: 'actql-installed-row-source-context/0.1',
      root, principalId, connectorRegistration})});
  const gate = await createLocalAuthorizationGate({...gateOptions,
    accountConfiguration, principal: principalId, context});
  const issued = new WeakSet<object>();
  const own = (decision: Decision) => {
    if (decision !== null && typeof decision === 'object') issued.add(decision);
    return decision;
  };
  return Object.freeze({...gate, context, accountConfiguration,
    accountConstruction: gateOptions.accountConstruction,
    issued: (decision: unknown) => issued.has(decision as object),
    authorize: async (...args: Parameters<Gate['authorize']>) => own(await gate.authorize(...args)),
    resume: async (...args: Parameters<Gate['resume']>) => own(await gate.resume(...args))});
}
