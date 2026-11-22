import {sign, verify} from 'node:crypto';
import type {remoteCredentialControl} from '../host-common/remote-credential-control.mjs';
import type {createInstallationPreparationMetadata} from '../host-common/installation-preparation-metadata.mjs';
import type {SynchronousRuntimeData} from '../host-common/runtime-result.mjs';

type RunControl = ReturnType<typeof remoteCredentialControl>;
type MetadataControl = ReturnType<ReturnType<typeof createInstallationPreparationMetadata>['forSubject']>;
type Control = RunControl | MetadataControl;
type Projector = Pick<Control, 'signatureEnvelopeProjection'>;
type Signer = Projector & Pick<Control, 'signaturePreimage' | 'prepareSignatureEnvelope'>;
type Verifier = Projector & Pick<Control, 'admitSignatureEnvelope' | 'signatureEnvelopeGrant' | 'signaturePreimage'>;
type Envelope = Parameters<RunControl['admitSignatureEnvelope']>[0];
type SigningOptions = Readonly<{keyId: string; privateKey: Parameters<typeof sign>[2]}>;
type Authorities = ReadonlyMap<string, ReadonlyMap<string, Parameters<typeof verify>[2]>>;
type Grant = Extract<SynchronousRuntimeData, object>;

const fail: (code: string, cause?: unknown) => never = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};
const text = (value: unknown): value is string => typeof value === 'string' && value.length > 0;

function envelopeObject(value: unknown, control: Projector): Envelope {
  const [version, keyId, grantCid, body, signature] =
    control.signatureEnvelopeProjection(value);
  return Object.freeze({version, keyId, grantCid, body, signature});
}

export function signRemoteCredentialGrant(grant: unknown, control: Signer, {
  keyId,
  privateKey,
}: SigningOptions) {
  if (!text(keyId) || privateKey === undefined ||
      typeof control?.signaturePreimage !== 'function' ||
      typeof control?.prepareSignatureEnvelope !== 'function' ||
      typeof control?.signatureEnvelopeProjection !== 'function') {
    fail('InvalidRemoteCredentialSigner');
  }
  let signature;
  try {
    signature = sign(null, control.signaturePreimage(grant), privateKey)
      .toString('base64url');
  } catch (error) {
    fail('RemoteCredentialSigningFailed', error);
  }
  return envelopeObject(
    control.prepareSignatureEnvelope(grant, keyId, signature),
    control,
  );
}

export function admitSignedRemoteCredentialGrant(envelope: Envelope, authorities: Authorities,
  control: Verifier): Grant {
  if (envelope === null || typeof envelope !== 'object' ||
      !text(envelope.version) ||
      !text(envelope.keyId) || !text(envelope.grantCid) ||
      !text(envelope.body) || !text(envelope.signature) ||
      !(authorities instanceof Map) ||
      typeof control?.admitSignatureEnvelope !== 'function' ||
      typeof control?.signatureEnvelopeProjection !== 'function' ||
      typeof control?.signatureEnvelopeGrant !== 'function' ||
      typeof control?.signaturePreimage !== 'function') {
    fail('InvalidRemoteCredentialEnvelope');
  }
  const admitted = control.admitSignatureEnvelope(envelope);
  const projection = control.signatureEnvelopeProjection(admitted);
  const keys = authorities.get(projection[5]);
  const publicKey = keys instanceof Map ? keys.get(projection[1]) : undefined;
  if (publicKey === undefined) fail('RemoteCredentialAuthorityRejected');
  let accepted;
  try {
    accepted = verify(
      null,
      control.signaturePreimage(control.signatureEnvelopeGrant(admitted)),
      publicKey,
      Buffer.from(projection[4], 'base64url'),
    );
  } catch (error) {
    fail('RemoteCredentialSignatureRejected', error);
  }
  if (!accepted) fail('RemoteCredentialSignatureRejected');
  return control.signatureEnvelopeGrant(admitted) as Grant;
}
