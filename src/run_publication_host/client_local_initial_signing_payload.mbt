///|
/// Closed DATA from the original installation payload, not adopted material,
/// an issuer, a current key, a grant or a signing use. These immutable Strings
/// do not authenticate their own claims. The existing physical Host must still
/// authenticate the original epoch/HMAC, Store, projection and current fence.
pub(all) struct ClientLocalInitialSigningPayloadFields {
  adoption_cid : String
  initialization_intent_cid : String
  issuer_authority : String
  key_file : String
  key_projection : String
  policy_cid : String
  policy_original : String
  public_key_cid : String
  public_key_original : String
  public_key_pem : String
  purpose : String
  root_role : String
  version : String
} derive(Eq, Debug)

///|
fn client_local_initial_signing_payload_keys() -> Array[String] {
  [
    "adoption_cid", "initialization_intent_cid", "issuer_authority", "key_file",
    "key_projection", "policy_cid", "policy_original", "public_key_cid", "public_key_original",
    "public_key_pem", "purpose", "root_role", "version",
  ]
}

///|
/// Preserve the existing Native installation payload's exact ordered bytes.
/// Only its physical first initializer may capture an original. Encoding DATA
/// neither performs initialization nor admits any operational responsibility.
pub fn client_local_initial_signing_payload_body(
  fields : ClientLocalInitialSigningPayloadFields,
) -> Result[Bytes, ClientLocalOriginalCodecIssue] {
  let values = [
    fields.adoption_cid,
    fields.initialization_intent_cid,
    fields.issuer_authority,
    fields.key_file,
    fields.key_projection,
    fields.policy_cid,
    fields.policy_original,
    fields.public_key_cid,
    fields.public_key_original,
    fields.public_key_pem,
    fields.purpose,
    fields.root_role,
    fields.version,
  ]
  client_local_original_record_body(
    client_local_initial_signing_payload_keys().mapi((index, key) => {
      (key, values[index])
    }),
  )
}

///|
/// Read only the same closed canonical String record under the existing Local
/// original codec's byte/node/depth/String budgets. Policy and public-key
/// admission, PEM decoding, the native projection layout, purpose separation
/// and authenticated current observation remain with their existing Owners.
/// In particular, successful decoding cannot turn a legacy missing original
/// into an initialized signer or establish that a physical key still exists.
pub fn read_client_local_initial_signing_payload(
  body : Bytes,
) -> Result[
  ClientLocalInitialSigningPayloadFields,
  ClientLocalOriginalCodecIssue,
] {
  let fields = match
    client_local_original_record_fields(
      body,
      client_local_initial_signing_payload_keys(),
    ) {
    Ok(fields) => fields
    Err(issue) => return Err(issue)
  }
  Ok({
    adoption_cid: fields[0],
    initialization_intent_cid: fields[1],
    issuer_authority: fields[2],
    key_file: fields[3],
    key_projection: fields[4],
    policy_cid: fields[5],
    policy_original: fields[6],
    public_key_cid: fields[7],
    public_key_original: fields[8],
    public_key_pem: fields[9],
    purpose: fields[10],
    root_role: fields[11],
    version: fields[12],
  })
}
