import {sign, verify} from 'node:crypto';

const fail = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};
const text = value => typeof value === 'string' && value.length > 0;

function envelopeObject(value, control) {
  const [version, keyId, grantCid, body, signature] =
    control.signatureEnvelopeProjection(value);
  return Object.freeze({version, keyId, grantCid, body, signature});
}

export function signRemoteCredentialGrant(grant, control, {
  keyId,
  privateKey,
}) {
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

export function admitSignedRemoteCredentialGrant(envelope, authorities,
  control) {
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
  return control.signatureEnvelopeGrant(admitted);
}
