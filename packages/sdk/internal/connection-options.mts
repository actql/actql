// Connection selection and safe diagnostics, before Host I/O.
import {connectionStringCredential, isLoopbackEndpointHostname, parseConnectionString} from '../connection-string.mjs';
import {fail, ownedClientFailure} from './errors.mjs';
import {validClientConnection} from '@actql/client-wire';
import type {WireConnection} from '@actql/client-wire';

// These are unchecked caller fields. The original guards below still decide
// admission; the array hints never replace Array.isArray or member validation.
interface UncheckedOptions {
  [key: string]: unknown;
  consentRefs?: readonly unknown[];
  runners?: readonly unknown[];
}

export interface SelectedConnection {
  readonly wire: WireConnection;
  readonly endpoint: string;
  readonly token?: string | (() => unknown);
  readonly traceContext?: () => unknown;
  readonly directLoopbackHttp?: true;
}

export const connectionObjectExample = "Use connect({mode: 'remote', endpoint: 'https://host.example/', token: getAccessToken}). For embedded Local, use open() from '@actql/node' without a Host or token.";

export const connectionStringExample = "Use connect('actql://host.example/workspace-id', {token: getAccessToken}), or provide a percent-encoded bearer credential in actql://token:<credential>@host.example/workspace-id.";
// Fixed field names and examples only: never include options, URLs or causes.
export const connectionFailure: (code: string, hint: string) => never = (code, hint) => {
  throw ownedClientFailure(code, {hint});
};

export function inProcessOptions(original: unknown): SelectedConnection {
  const options = original as UncheckedOptions;
  if (options === null || typeof options !== 'object' ||
      Array.isArray(options) || options.mode !== 'local' ||
      options.owner !== 'local' || options.endpoint !== undefined ||
      options.token !== undefined ||
      options.runtime !== undefined && options.runtime !== 'embedded' ||
      Object.keys(options).some(key => ![
        'mode', 'owner', 'runtime', 'durability', 'consentRefs',
      ].includes(key)) ||
      options.durability !== undefined &&
        !['volatile', 'durable'].includes(options.durability as string) ||
      !Array.isArray(options.consentRefs ?? []) ||
      (options.consentRefs ?? []).some(value =>
        typeof value !== 'string' || !value) ||
      new Set(options.consentRefs ?? []).size !==
        (options.consentRefs ?? []).length) {
    fail('InvalidConnectionOptions');
  }
  const wire = Object.freeze({mode: 'local', owner: 'local',
    ...(options.durability === undefined ? {} :
      {durability: options.durability}),
    consentRefs: Object.freeze([...(options.consentRefs ?? [])]),
    runners: Object.freeze([])});
  if (!validClientConnection(wire)) fail('InvalidConnectionOptions');
  return Object.freeze({wire, endpoint: 'actql:embedded'});
}

export function connectionStringOptions(input: unknown, original: unknown = {}) {
  const options = original as UncheckedOptions;
  let keys: string[], parsed: ReturnType<typeof parseConnectionString>, hasToken: boolean;
  let token: unknown, durability: unknown, consentRefs: unknown, traceContext: unknown;
  if (options === null || typeof options !== 'object' || Array.isArray(options)) {
    connectionFailure('InvalidConnectionOptions', connectionStringExample);
  }
  try { keys = Object.keys(options); }
  catch { connectionFailure('InvalidConnectionOptions', connectionStringExample); }
  if (keys.some(key => !['token', 'durability', 'consentRefs', 'traceContext'].includes(key))) {
    connectionFailure('InvalidConnectionOptions',
      'Connection-string options accept only token, durability, consentRefs and traceContext. ' + connectionStringExample);
  }
  try { parsed = parseConnectionString(input); }
  catch {
    connectionFailure('InvalidConnectionString',
      'Specify an actql:// Host and one workspace-id. Only ?transport=http is accepted, for an explicit loopback Host. ' + connectionStringExample);
  }
  const embedded = connectionStringCredential(parsed);
  try { hasToken = 'token' in options; }
  catch { connectionFailure('InvalidConnectionOptions', connectionStringExample); }
  if (embedded !== undefined && hasToken) {
    connectionFailure('ConflictingConnectionCredentials',
      'Choose either the connection-string credential or the separate token option, never both.');
  }
  try {
    token = embedded ?? options.token;
    durability = options.durability;
    consentRefs = options.consentRefs;
    traceContext = options.traceContext;
  } catch { connectionFailure('InvalidConnectionOptions', connectionStringExample); }
  return {mode: 'remote', endpoint: parsed.endpoint,
    workspaceId: parsed.workspaceId, token, durability, consentRefs, traceContext};
}

export function connectionOptions(original: unknown, parsedConnectionString = false): SelectedConnection {
  const options = original as UncheckedOptions;
  if (options === null || typeof options !== 'object' ||
      Array.isArray(options)) connectionFailure('InvalidConnectionOptions', connectionObjectExample);
  const {mode, owner, endpoint, token, durability, consentRefs, runners, workspaceId,
    movementPolicyRef, cloudConnectionRef, traceContext} = options;
  if (endpoint === undefined && (mode === 'local' ||
      mode === 'hybrid' && owner === 'local')) {
    throw ownedClientFailure('LocalProviderNotInstalled', {
      hint: "For embedded Local, install @actql/node and use open() without a Host or token. This SDK connects only to an existing Host with endpoint and token.",
    });
  }
  if (!(mode === 'remote' && owner === undefined ||
        mode === 'local' && owner === 'local' ||
        mode === 'hybrid' && ['local', 'cloud'].includes(owner as string)) ||
      typeof endpoint !== 'string' ||
      typeof token !== 'string' && typeof token !== 'function' ||
      traceContext !== undefined && typeof traceContext !== 'function' ||
      durability !== undefined && !['volatile', 'durable'].includes(durability as string) ||
      !Array.isArray(consentRefs ?? []) ||
      (consentRefs ?? []).some(value => typeof value !== 'string' || !value) ||
      new Set(consentRefs ?? []).size !== (consentRefs ?? []).length ||
      !Array.isArray(runners ?? []) ||
      (runners ?? []).some(value => typeof value !== 'string' || !value) ||
      new Set(runners ?? []).size !== (runners ?? []).length ||
      movementPolicyRef !== undefined &&
        (typeof movementPolicyRef !== 'string' || !movementPolicyRef) ||
      cloudConnectionRef !== undefined &&
        (typeof cloudConnectionRef !== 'string' || !cloudConnectionRef)) {
    const missing = [['mode', mode], ['endpoint', endpoint], ['token', token]]
      .filter(([, value]) => value === undefined).map(([name]) => name);
    if ((mode === 'local' || mode === 'hybrid') && owner === undefined) missing.push('owner');
    connectionFailure('InvalidConnectionOptions',
      (missing.length ? `Missing connection options: ${missing.join(', ')}. ` :
        'Check mode/owner, endpoint, token and the optional connection fields. ') +
      (parsedConnectionString ? connectionStringExample : connectionObjectExample));
  }
  if (mode !== 'hybrid' && (runners !== undefined ||
      movementPolicyRef !== undefined || cloudConnectionRef !== undefined) ||
      mode === 'hybrid' && (movementPolicyRef === undefined ||
        owner === 'local' && cloudConnectionRef === undefined ||
        owner === 'cloud' && (cloudConnectionRef !== undefined ||
          runners === undefined || runners.length === 0))) {
    connectionFailure('InvalidHybridConnection',
      'Hybrid needs movementPolicyRef; a Local owner also needs cloudConnectionRef, and a Cloud owner needs nonempty runners. Other modes omit these fields.');
  }
  let url;
  try { url = new URL(endpoint); }
  catch {
    connectionFailure('InvalidConnectionEndpoint',
      'Set endpoint to an HTTPS origin, such as https://host.example/, without userinfo, path, query or fragment.');
  }
  const loopback = url.protocol === 'http:' &&
    (mode === 'local' && ['127.0.0.1', '[::1]'].includes(url.hostname) ||
      parsedConnectionString && mode === 'remote' && isLoopbackEndpointHostname(url.hostname));
  if (!(url.protocol === 'https:' || loopback) ||
      url.username || url.password ||
      url.search || url.hash || url.pathname !== '/') {
    connectionFailure('InvalidConnectionEndpoint',
      'Set endpoint to an HTTPS origin without userinfo, path, query or fragment. Connected Local also accepts explicit numeric loopback HTTP.');
  }
  const wire = Object.freeze({
    mode, owner: owner ?? 'remote',
    ...(workspaceId === undefined ? {} : {workspaceId}),
    ...(durability === undefined ? {} : {durability}),
    consentRefs: Object.freeze([...(consentRefs ?? [])]),
    runners: Object.freeze([...(runners ?? [])]),
    ...(movementPolicyRef === undefined ? {} : {movementPolicyRef}),
    ...(cloudConnectionRef === undefined ? {} : {cloudConnectionRef}),
  });
  if (!validClientConnection(wire)) {
    connectionFailure('InvalidConnectionOptions',
      'Check workspaceId and the selected connection profile. ' +
      (parsedConnectionString ? connectionStringExample : connectionObjectExample));
  }
  return Object.freeze({endpoint: url.href, token: token as string | (() => unknown), wire,
    ...(traceContext === undefined ? {} : {traceContext: traceContext as () => unknown}),
    ...(parsedConnectionString && loopback ? {directLoopbackHttp: true} : {})});
}
