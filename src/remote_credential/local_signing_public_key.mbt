///|
/// Canonical public-byte identity within the existing Credential Owner. This
/// opaque value owns no key, issuer, role, current authority or permission.
struct LocalSigningPublicKey {
  encoded : String
  body : String
  identity : String
}

///|
pub(all) enum LocalSigningPublicKeyIssue {
  InvalidPublicKey
  PublicKeyEncoding
  PublicKeyIdentityMismatch
} derive(Eq, Debug)

///|
fn local_signing_public_key_body(
  encoded : String,
) -> Result[String, LocalSigningPublicKeyIssue] {
  try {
    let writer = @encode.writer(256, 16, 2)
    @encode.begin_ordered_object(writer)
    @encode.ordered_key(writer, "algorithm")
    @encode.string_value(writer, "ed25519")
    @encode.ordered_key(writer, "public_key")
    @encode.string_value(writer, encoded)
    @encode.ordered_key(writer, "version")
    @encode.string_value(writer, "actql-local-signing-public-key/0.1")
    @encode.end_object(writer)
    Ok(@encode.finish(writer).text)
  } catch {
    _ => Err(PublicKeyEncoding)
  }
}

///|
/// Canonical identity only. Actual key validation/correspondence, authenticated
/// issuer installation, current authority and signing use remain separate.
pub fn prepare_local_signing_public_key(
  public_key : Bytes,
) -> Result[LocalSigningPublicKey, LocalSigningPublicKeyIssue] {
  if public_key.length() != 32 {
    return Err(InvalidPublicKey)
  }
  // Retain immutable encoded bytes, not a caller-owned mutable byte array.
  let encoded = @base64.encode(public_key)
  let body = match local_signing_public_key_body(encoded) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match @sha.text_hex(body) {
    Ok(value) => Ok({ encoded, body, identity: "sha256:" + value, })
    Err(_) => Err(PublicKeyEncoding)
  }
}

///|
pub fn LocalSigningPublicKey::json(self : LocalSigningPublicKey) -> String {
  self.body
}

///|
pub fn LocalSigningPublicKey::cid(self : LocalSigningPublicKey) -> String {
  self.identity
}

///|
/// A fresh copy of admitted public bytes, never a private-key handle or grant.
pub fn LocalSigningPublicKey::raw32(
  self : LocalSigningPublicKey,
) -> Result[Bytes, LocalSigningPublicKeyIssue] {
  try {
    Ok(@base64.decode(self.encoded[:]))
  } catch {
    _ => Err(PublicKeyEncoding)
  }
}

///|
/// Bounded closed reader. Require exact canonical body bytes and the independent
/// expected CID; syntax-valid metadata alone does not establish issuer custody.
pub fn admit_local_signing_public_key_json(
  body : String,
  expected_cid : String,
) -> Result[LocalSigningPublicKey, LocalSigningPublicKeyIssue] {
  if !valid_cid(expected_cid) ||
    body.length() > 256 ||
    @utf8.encode(body).length() > 256 {
    return Err(InvalidPublicKey)
  }
  try {
    let source = credential_decoded(
      @source.parse_json_bytes_preserving(@utf8.encode(body), {
        max_input_bytes: 256,
        max_nodes: 8,
        max_depth: 2,
      }),
    )
    let cursor = credential_decoded(
      @decode.admit(source, {
        max_nodes: 8,
        max_depth: 2,
        max_string_bytes: 128,
        max_total_string_bytes: 256,
      }),
    )
    let object = credential_decoded(
      @decode.closed_object(cursor, ["algorithm", "public_key", "version"]),
    )
    if credential_text(object, "algorithm") != "ed25519" ||
      credential_text(object, "version") != "actql-local-signing-public-key/0.1" {
      return Err(InvalidPublicKey)
    }
    let encoded = credential_text(object, "public_key")
    // Bound decoding before allocation; re-encoding rejects padding variants,
    // nonzero pad bits, URL-safe spelling, whitespace and alternate alphabets.
    if encoded.length() != 44 {
      return Err(InvalidPublicKey)
    }
    let raw = @base64.decode(encoded[:]) catch {
      _ => return Err(InvalidPublicKey)
    }
    if raw.length() != 32 || @base64.encode(raw) != encoded {
      return Err(InvalidPublicKey)
    }
    let value = match prepare_local_signing_public_key(raw) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if value.body != body {
      return Err(InvalidPublicKey)
    }
    if value.identity != expected_cid {
      return Err(PublicKeyIdentityMismatch)
    }
    Ok(value)
  } catch {
    RemoteCredentialDecodeStop => Err(InvalidPublicKey)
  }
}
