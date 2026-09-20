import {sign, verify} from 'node:crypto';

const fail = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};
const text = value => typeof value === 'string' && value.length > 0;

function envelopeObject(value, control) {
  const [version, keyId, runtimeBundleCid, body, signature] =
    control.signatureEnvelopeProjection(value);
  return Object.freeze({version, keyId, runtimeBundleCid, body, signature});
}

export function signRemoteRuntimeBundle(manifest, control, {
  keyId,
  privateKey,
}) {
  if (!text(keyId) || privateKey === undefined ||
      typeof control?.identity !== 'function' ||
      typeof control?.signaturePreimage !== 'function' ||
      typeof control?.prepareSignatureEnvelope !== 'function') {
    fail('InvalidRemoteBundleSigner');
  }
  let signature;
  try {
    signature = sign(null, control.signaturePreimage(manifest), privateKey)
      .toString('base64url');
  } catch (error) {
    fail('RemoteBundleSigningFailed', error);
  }
  return envelopeObject(
    control.prepareSignatureEnvelope(manifest, keyId, signature),
    control,
  );
}

export function admitSignedRemoteRuntimeBundle(envelope, authorities,
  control) {
  if (envelope === null || typeof envelope !== 'object' ||
      !text(envelope.version) || !text(envelope.keyId) ||
      !text(envelope.runtimeBundleCid) ||
      !text(envelope.body) || !text(envelope.signature) ||
      !(authorities instanceof Map) ||
      typeof control?.admitSignatureEnvelope !== 'function' ||
      typeof control?.signatureEnvelopeProjection !== 'function' ||
      typeof control?.signatureEnvelopeManifest !== 'function') {
    fail('InvalidRemoteBundleEnvelope');
  }
  const admitted = control.admitSignatureEnvelope(envelope);
  const projection = control.signatureEnvelopeProjection(admitted);
  const keys = authorities.get(projection[5]);
  const publicKey = keys instanceof Map ? keys.get(projection[1]) : undefined;
  if (publicKey === undefined) fail('RemoteBundleAuthorityRejected');
  let accepted;
  try {
    accepted = verify(
      null,
      control.signaturePreimage(
        control.signatureEnvelopeManifest(admitted),
      ),
      publicKey,
      Buffer.from(projection[4], 'base64url'),
    );
  } catch (error) {
    fail('RemoteBundleSignatureRejected', error);
  }
  if (!accepted) fail('RemoteBundleSignatureRejected');
  return control.signatureEnvelopeManifest(admitted);
}
