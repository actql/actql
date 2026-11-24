import {checked} from './runtime-result.mjs';

type BigIntInput = Parameters<typeof BigInt>[0];
type GrantDeclaration = Readonly<{
  issuerAuthority: string;
  principal: string;
  namespaceId: string;
  environment: string;
  siteKey: string;
  siteGeneration: number;
  runtimeBundleCid: string;
  connectorRegistration: string;
  connectorRevision: string;
  resourceOrigin: string;
  operation: string;
  runInvocationCid: string;
  taskAttempt: number;
  dispatchRequestCid: string;
  expiresUnixMilliseconds: BigIntInput;
  maxUses: number;
}>;

type UseAuthorization = Readonly<{
  trustedNowMilliseconds: BigIntInput;
  revoked: boolean;
  scope: GrantDeclaration;
}>;
type UseRequest = UseAuthorization & Readonly<{useId: string; usedCount: number}>;
type SignatureEnvelope = Readonly<{
  version: string;
  keyId: string;
  grantCid: string;
  body: string;
  signature: string;
}>;

// Both existing use calls forward the grant expiry after the scope. The
// Common JS exports consume the preceding scope fields and ignore that tail.
type ScopeFields = [
  principal: string, namespaceId: string, environment: string, siteKey: string,
  siteGeneration: number, runtimeBundleCid: string, connectorRegistration: string,
  connectorRevision: string, resourceOrigin: string, operation: string, runInvocationCid: string,
  taskAttempt: number, dispatchRequestCid: string, expiresUnixMilliseconds: bigint,
];
type GrantFields = [issuerAuthority: string, ...ScopeFields, maxUses: number];

// Common validates all opaque handles and owns the original authentication pair.
type CommonCredentialBindings = {
  strategyRemoteCredentialGrantPrepare(...fields: GrantFields): unknown;
  strategyRemoteCredentialGrantIdentity(grant: unknown): string;
  strategyRemoteCredentialGrantJson(grant: unknown): unknown;
  strategyRemoteCredentialGrantAdmitJson(body: string, claimedGrantCid: string): unknown;
  strategyRemoteCredentialGrantProjection(grant: unknown): readonly string[];
  strategyRemoteCredentialSignaturePreimage(grant: unknown): unknown;
  strategyRemoteCredentialSignatureEnvelopePrepare(grant: unknown, keyId: string, signature: string): unknown;
  strategyRemoteCredentialSignatureEnvelopeAdmit(
    version: string, keyId: string, grantCid: string, body: string, signature: string,
  ): unknown;
  strategyRemoteCredentialSignatureEnvelopeProjection(envelope: unknown): readonly string[];
  strategyRemoteCredentialSignatureEnvelopeGrant(envelope: unknown): unknown;
  strategyRemoteCredentialUsePrepare(grant: unknown, useId: string, trustedNowMilliseconds: bigint,
    usedCount: number, revoked: boolean, ...scope: ScopeFields): unknown;
  strategyRemoteCredentialUseIdentity(use: unknown): string;
  strategyRemoteCredentialUseJson(use: unknown): unknown;
  strategyRemoteCredentialUseAuthorize(
    use: unknown, trustedNowMilliseconds: bigint, revoked: boolean, ...scope: ScopeFields
  ): unknown;
  strategyRemoteCredentialUseProjection(use: unknown): readonly string[];
  strategyCredentialAuthenticationRequest(
    parent: unknown, grant: unknown, material: unknown, httpMethod: string, path: string,
    mediaType: string, body: Uint8Array, maxBodyBytes: number, deadlineUnixMilliseconds: bigint,
  ): unknown;
  strategyCredentialAuthenticationUseBind(
    request: unknown, parent: unknown, credentialUse: unknown, material: unknown,
    httpMethod: string, path: string, mediaType: string, body: Uint8Array, trustedNowMilliseconds: bigint,
  ): unknown;
  strategyCredentialAuthenticationOperationCheck(
    operation: unknown, request: unknown, parent: unknown, credentialUse: unknown, material: unknown,
    httpMethod: string, path: string, mediaType: string, body: Uint8Array, trustedNowMilliseconds: bigint,
  ): unknown;
};

const remoteCredentialControls = new WeakMap<object, ReturnType<typeof createRemoteCredentialControl>>();

export function remoteCredentialControl(moon: CommonCredentialBindings) {
  let control = remoteCredentialControls.get(moon);
  if (control !== undefined) return control;
  control = createRemoteCredentialControl(moon);
  remoteCredentialControls.set(moon, control);
  return control;
}

function createRemoteCredentialControl(moon: CommonCredentialBindings) {
  const grantFields = (grant: GrantDeclaration): GrantFields => {
    if (grant === null || typeof grant !== 'object') {
      throw new TypeError('Invalid Remote Credential grant');
    }
    return [
      grant.issuerAuthority,
      grant.principal,
      grant.namespaceId,
      grant.environment,
      grant.siteKey,
      grant.siteGeneration,
      grant.runtimeBundleCid,
      grant.connectorRegistration,
      grant.connectorRevision,
      grant.resourceOrigin,
      grant.operation,
      grant.runInvocationCid,
      grant.taskAttempt,
      grant.dispatchRequestCid,
      BigInt(grant.expiresUnixMilliseconds),
      grant.maxUses,
    ];
  };
  return Object.freeze({
    prepare: (grant: GrantDeclaration) => checked(
      moon.strategyRemoteCredentialGrantPrepare(...grantFields(grant)),
    ),
    identity: moon.strategyRemoteCredentialGrantIdentity,
    json: (grant: unknown) => checked(moon.strategyRemoteCredentialGrantJson(grant)) as string,
    admitJson: (body: string, claimedGrantCid: string) => checked(
      moon.strategyRemoteCredentialGrantAdmitJson(body, claimedGrantCid),
    ),
    projection: moon.strategyRemoteCredentialGrantProjection,
    signaturePreimage: (grant: unknown) => checked(
      moon.strategyRemoteCredentialSignaturePreimage(grant),
    ) as Uint8Array,
    prepareSignatureEnvelope: (grant: unknown, keyId: string, signature: string) => checked(
      moon.strategyRemoteCredentialSignatureEnvelopePrepare(
        grant,
        keyId,
        signature,
      ),
    ),
    admitSignatureEnvelope: (envelope: SignatureEnvelope) => checked(
      moon.strategyRemoteCredentialSignatureEnvelopeAdmit(
        envelope.version,
        envelope.keyId,
        envelope.grantCid,
        envelope.body,
        envelope.signature,
      ),
    ),
    signatureEnvelopeProjection:
      moon.strategyRemoteCredentialSignatureEnvelopeProjection,
    signatureEnvelopeGrant:
      moon.strategyRemoteCredentialSignatureEnvelopeGrant,
    prepareUse(grant: unknown, request: UseRequest) {
      if (request === null || typeof request !== 'object') {
        throw new TypeError('Invalid Remote Credential use');
      }
      const scope = grantFields(request.scope);
      return checked(moon.strategyRemoteCredentialUsePrepare(
        grant,
        request.useId,
        BigInt(request.trustedNowMilliseconds),
        request.usedCount,
        request.revoked,
        ...scope.slice(1, 15) as ScopeFields,
      ));
    },
    useIdentity: moon.strategyRemoteCredentialUseIdentity,
    useJson: (value: unknown) => checked(moon.strategyRemoteCredentialUseJson(value)) as string,
    authorizeUse(value: unknown, request: UseAuthorization) {
      if (request === null || typeof request !== 'object') {
        throw new TypeError('Invalid Remote Credential authorization');
      }
      const scope = grantFields(request.scope);
      checked(moon.strategyRemoteCredentialUseAuthorize(
        value,
        BigInt(request.trustedNowMilliseconds),
        request.revoked,
        ...scope.slice(1, 15) as ScopeFields,
      ));
    },
    useProjection: moon.strategyRemoteCredentialUseProjection,
    prepareAuthenticationRequest: (...args: Parameters<CommonCredentialBindings['strategyCredentialAuthenticationRequest']>) => checked(
      moon.strategyCredentialAuthenticationRequest(...args),
    ),
    bindAuthenticationUse: (...args: Parameters<CommonCredentialBindings['strategyCredentialAuthenticationUseBind']>) => checked(
      moon.strategyCredentialAuthenticationUseBind(...args),
    ),
    checkAuthenticationOperation: (...args: Parameters<CommonCredentialBindings['strategyCredentialAuthenticationOperationCheck']>) => checked(
      moon.strategyCredentialAuthenticationOperationCheck(...args),
    ),
  });
}
