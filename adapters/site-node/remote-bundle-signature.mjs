import {sign, verify} from 'node:crypto';

const fail = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};
const text = value => typeof value === 'string' && value.length > 0;

function preimage(runtimeBundleCid, body) {
  return Buffer.from(
    `actql-remote-runtime-bundle-signature/0.1\0${runtimeBundleCid}\0${body}`,
    'utf8',
  );
}

export function signRemoteRuntimeBundle(manifest, control, {
  keyId,
  privateKey,
}) {
  if (!text(keyId) || privateKey === undefined ||
      typeof control?.identity !== 'function' ||
      typeof control?.json !== 'function') {
    fail('InvalidRemoteBundleSigner');
  }
  const runtimeBundleCid = control.identity(manifest);
  const body = control.json(manifest);
  let signature;
  try {
    signature = sign(null, preimage(runtimeBundleCid, body), privateKey)
      .toString('base64url');
  } catch (error) {
    fail('RemoteBundleSigningFailed', error);
  }
  return Object.freeze({
    version: 'actql-remote-runtime-bundle-signature/0.1',
    keyId,
    runtimeBundleCid,
    body,
    signature,
  });
}

export function admitSignedRemoteRuntimeBundle(envelope, authorities,
  control) {
  if (envelope === null || typeof envelope !== 'object' ||
      envelope.version !== 'actql-remote-runtime-bundle-signature/0.1' ||
      !text(envelope.keyId) || !text(envelope.runtimeBundleCid) ||
      !text(envelope.body) || !text(envelope.signature) ||
      !(authorities instanceof Map) ||
      typeof control?.admitJson !== 'function' ||
      typeof control?.projection !== 'function') {
    fail('InvalidRemoteBundleEnvelope');
  }
  const manifest = control.admitJson(
    envelope.body,
    envelope.runtimeBundleCid,
  );
  const projection = control.projection(manifest);
  const keys = authorities.get(projection[1]);
  const publicKey = keys instanceof Map ? keys.get(envelope.keyId) : undefined;
  if (publicKey === undefined) fail('RemoteBundleAuthorityRejected');
  let signature;
  try {
    signature = Buffer.from(envelope.signature, 'base64url');
  } catch (error) {
    fail('InvalidRemoteBundleEnvelope', error);
  }
  if (signature.length === 0 ||
      signature.toString('base64url') !== envelope.signature) {
    fail('InvalidRemoteBundleEnvelope');
  }
  let accepted;
  try {
    accepted = verify(
      null,
      preimage(envelope.runtimeBundleCid, envelope.body),
      publicKey,
      signature,
    );
  } catch (error) {
    fail('RemoteBundleSignatureRejected', error);
  }
  if (!accepted) fail('RemoteBundleSignatureRejected');
  return manifest;
}
