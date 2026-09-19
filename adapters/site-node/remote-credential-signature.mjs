import {sign, verify} from 'node:crypto';

const fail = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};
const text = value => typeof value === 'string' && value.length > 0;

function signaturePreimage(grantCid, body) {
  return Buffer.from(
    `actql-remote-credential-grant-signature/0.1\0${grantCid}\0${body}`,
    'utf8',
  );
}

export function signRemoteCredentialGrant(grant, control, {
  keyId,
  privateKey,
}) {
  if (!text(keyId) || privateKey === undefined ||
      typeof control?.identity !== 'function' ||
      typeof control?.json !== 'function') {
    fail('InvalidRemoteCredentialSigner');
  }
  const grantCid = control.identity(grant);
  const body = control.json(grant);
  let signature;
  try {
    signature = sign(null, signaturePreimage(grantCid, body), privateKey)
      .toString('base64url');
  } catch (error) {
    fail('RemoteCredentialSigningFailed', error);
  }
  return Object.freeze({
    version: 'actql-remote-credential-signature/0.1',
    keyId,
    grantCid,
    body,
    signature,
  });
}

export function admitSignedRemoteCredentialGrant(envelope, authorities,
  control) {
  if (envelope === null || typeof envelope !== 'object' ||
      envelope.version !== 'actql-remote-credential-signature/0.1' ||
      !text(envelope.keyId) || !text(envelope.grantCid) ||
      !text(envelope.body) || !text(envelope.signature) ||
      !(authorities instanceof Map) ||
      typeof control?.admitJson !== 'function' ||
      typeof control?.projection !== 'function') {
    fail('InvalidRemoteCredentialEnvelope');
  }
  let signature;
  try {
    signature = Buffer.from(envelope.signature, 'base64url');
  } catch (error) {
    fail('InvalidRemoteCredentialEnvelope', error);
  }
  if (signature.length === 0 ||
      signature.toString('base64url') !== envelope.signature) {
    fail('InvalidRemoteCredentialEnvelope');
  }
  const grant = control.admitJson(envelope.body, envelope.grantCid);
  const projection = control.projection(grant);
  const keys = authorities.get(projection[1]);
  const publicKey = keys instanceof Map ? keys.get(envelope.keyId) : undefined;
  if (publicKey === undefined) fail('RemoteCredentialAuthorityRejected');
  let accepted;
  try {
    accepted = verify(
      null,
      signaturePreimage(envelope.grantCid, envelope.body),
      publicKey,
      signature,
    );
  } catch (error) {
    fail('RemoteCredentialSignatureRejected', error);
  }
  if (!accepted) fail('RemoteCredentialSignatureRejected');
  return grant;
}
