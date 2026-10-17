///|
/// Original Host installation/catalog-preparation subject DATA, not a Program
/// Run, operational preparation token, issuer, current Allow or read grant.
/// The trusted installation Owner retains the actual request/actor/generation
/// and original declaration behind its separate opaque operational custody.
/// declaration_source_cid names the exact retained declaration source bytes;
/// it is not a semantic Contract CID or a replacement for that original.
pub(all) struct InstallationPreparationSubjectFields {
  account_configuration_cid : String
  account_id : String
  connection : String
  connector_registration : String
  connector_revision : String
  declaration_source_cid : String
  installation_request_id : String
  principal : String
  runtime_bundle_cid : String
  site_generation : Int
  site_key : String
} derive(Eq, Debug)

///|
struct InstallationPreparationSubject {
  fields : InstallationPreparationSubjectFields
  body : String
  identity : String
} derive(Eq, Debug)

///|
fn installation_preparation_text(value : String, bound : Int) -> Bool {
  bounded_text(value, bound) && !value.contains("\u{0}")
}

///|
fn installation_preparation_subject_fields_valid(
  value : InstallationPreparationSubjectFields,
) -> Bool {
  [
    value.account_configuration_cid,
    value.declaration_source_cid,
    value.runtime_bundle_cid,
  ].all(valid_cid) &&
  [
    value.account_id,
    value.connection,
    value.connector_registration,
    value.connector_revision,
    value.principal,
    value.site_key,
  ].all(value => installation_preparation_text(value, 512)) &&
  installation_preparation_text(value.installation_request_id, 256) &&
  value.site_generation >= 0
}

///|
/// Canonical identity only. A caller-provided request ID, copied body/CID or
/// admitted value cannot recreate the actual Host's operational original.
pub fn prepare_installation_preparation_subject(
  fields : InstallationPreparationSubjectFields,
) -> Result[InstallationPreparationSubject, RemoteCredentialIssue] {
  if !installation_preparation_subject_fields_valid(fields) {
    return Err(InvalidCredentialGrant)
  }
  try {
    let writer = @encode.writer(8192, 40, 2)
    @encode.begin_ordered_object(writer)
    for
      (key, value) in [
        ("account_configuration_cid", fields.account_configuration_cid),
        ("account_id", fields.account_id),
        ("connection", fields.connection),
        ("connector_registration", fields.connector_registration),
        ("connector_revision", fields.connector_revision),
        ("declaration_source_cid", fields.declaration_source_cid),
        ("installation_request_id", fields.installation_request_id),
        ("principal", fields.principal),
        ("runtime_bundle_cid", fields.runtime_bundle_cid),
      ] {
      @encode.ordered_key(writer, key)
      @encode.string_value(writer, value)
    }
    @encode.ordered_key(writer, "site_generation")
    @encode.number_value(writer, fields.site_generation.to_double())
    @encode.ordered_key(writer, "site_key")
    @encode.string_value(writer, fields.site_key)
    @encode.ordered_key(writer, "version")
    @encode.string_value(writer, "actql-installation-metadata-preparation/0.1")
    @encode.end_object(writer)
    let body = @encode.finish(writer)
    let digest = match @sha.text_hex(body) {
      Ok(value) => value
      Err(_) => return Err(InvalidCredentialGrant)
    }
    Ok({ fields, body, identity: "sha256:" + digest })
  } catch {
    _ => Err(InvalidCredentialGrant)
  }
}

///|
pub fn InstallationPreparationSubject::original_wire(
  self : InstallationPreparationSubject,
) -> String {
  self.body
}

///|
pub fn InstallationPreparationSubject::cid(
  self : InstallationPreparationSubject,
) -> String {
  self.identity
}

///|
pub fn InstallationPreparationSubject::fields(
  self : InstallationPreparationSubject,
) -> InstallationPreparationSubjectFields {
  self.fields
}

///|
/// Restore exact subject DATA only, without a Host request, current scope,
/// physical metadata funding, issuer, durable claim or rediscovery authority.
pub fn admit_installation_preparation_subject_json(
  body : String,
  expected_cid : String,
) -> Result[InstallationPreparationSubject, RemoteCredentialIssue] {
  try {
    let source = match
      @source.parse_json_bytes_preserving(@utf8.encode(body), {
        max_input_bytes: 8192,
        max_nodes: 40,
        max_depth: 2,
      }) {
      Ok(value) => value
      Err(_) => raise RemoteCredentialDecodeStop
    }
    let cursor = credential_decoded(
      @decode.admit(source, {
        max_nodes: 40,
        max_depth: 2,
        max_string_bytes: 512,
        max_total_string_bytes: 8192,
      }),
    )
    let object = credential_decoded(
      @decode.closed_object(cursor, [
        "account_configuration_cid", "account_id", "connection",
        "connector_registration", "connector_revision", "declaration_source_cid", "installation_request_id",
        "principal", "runtime_bundle_cid", "site_generation", "site_key", "version",
      ]),
    )
    if credential_text(object, "version") !=
      "actql-installation-metadata-preparation/0.1" {
      return Err(InvalidCredentialGrant)
    }
    let value = match
      prepare_installation_preparation_subject({
        account_configuration_cid: credential_text(object, "account_configuration_cid"),
        account_id: credential_text(object, "account_id"),
        connection: credential_text(object, "connection"),
        connector_registration: credential_text(object, "connector_registration"),
        connector_revision: credential_text(object, "connector_revision"),
        declaration_source_cid: credential_text(object, "declaration_source_cid"),
        installation_request_id: credential_text(object, "installation_request_id"),
        principal: credential_text(object, "principal"),
        runtime_bundle_cid: credential_text(object, "runtime_bundle_cid"),
        site_generation: credential_int(object, "site_generation"),
        site_key: credential_text(object, "site_key"),
      }) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if value.body != body {
      Err(InvalidCredentialGrant)
    } else if value.identity != expected_cid {
      Err(CredentialGrantIdentityMismatch)
    } else {
      Ok(value)
    }
  } catch {
    RemoteCredentialDecodeStop => Err(InvalidCredentialGrant)
  }
}
