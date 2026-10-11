///|
/// Closed original-identity projection only. Neither these fields nor their
/// CID prove durable first start, current permission or Provider entry.
pub(all) struct LocalPreparationFenceFields {
  client_request_intent_cid : String
  client_request_scope_cid : String
  operation_occurrence_cid : String
  run_invocation_cid : String
  unit_definition_cid : String
} derive(Eq, Debug)

///|
// An admitted value identity, not the operational token retained by Native
// Work. Reading a public preimage cannot mint or reconstruct that token.
struct LocalPreparationFenceIdentity {
  fields : LocalPreparationFenceFields
  body : String
  cid : String
} derive(Eq, Debug)

///|
pub fn prepare_local_preparation_fence_identity(
  fields : LocalPreparationFenceFields,
) -> Result[LocalPreparationFenceIdentity, RemoteCredentialIssue] {
  if ![
      fields.client_request_intent_cid,
      fields.client_request_scope_cid,
      fields.operation_occurrence_cid,
      fields.run_invocation_cid,
      fields.unit_definition_cid,
    ].all(valid_cid) {
    return Err(InvalidCredentialGrant)
  }
  try {
    let writer = @encode.writer(4096, 12, 2)
    @encode.begin_object(writer)
    for
      (name, value) in [
        ("client_request_intent_cid", fields.client_request_intent_cid),
        ("client_request_scope_cid", fields.client_request_scope_cid),
        ("operation_occurrence_cid", fields.operation_occurrence_cid),
        ("run_invocation_cid", fields.run_invocation_cid),
        ("unit_definition_cid", fields.unit_definition_cid),
        ("version", "actql-local-preparation-fence/0.1"),
      ] {
      @encode.key(writer, name)
      @encode.string_value(writer, value)
    }
    @encode.end_object(writer)
    let body = @encode.finish(writer)
    let digest = match @sha.text_hex(body) {
      Ok(value) => value
      Err(_) => return Err(InvalidCredentialGrant)
    }
    Ok({ fields, body, cid: "sha256:" + digest, })
  } catch {
    _ => Err(InvalidCredentialGrant)
  }
}

///|
pub fn local_preparation_fence_json(
  value : LocalPreparationFenceIdentity,
) -> String {
  value.body
}

///|
pub fn local_preparation_fence_cid(
  value : LocalPreparationFenceIdentity,
) -> String {
  value.cid
}

///|
pub fn local_preparation_fence_fields(
  value : LocalPreparationFenceIdentity,
) -> LocalPreparationFenceFields {
  value.fields
}

///|
/// Identity admission only. Original Work/journal authority must independently
/// supply its opaque operational first-start token before protected use.
pub fn admit_local_preparation_fence_json(
  body : String,
  claimed_cid : String,
) -> Result[LocalPreparationFenceIdentity, RemoteCredentialIssue] {
  try {
    let source = match
      @source.parse_json_bytes_preserving(@utf8.encode(body), {
        max_input_bytes: 4096,
        max_nodes: 12,
        max_depth: 2,
      }) {
      Ok(value) => value
      Err(_) => raise RemoteCredentialDecodeStop
    }
    let cursor = credential_decoded(
      @decode.admit(source, {
        max_nodes: 12,
        max_depth: 2,
        max_string_bytes: 71,
        max_total_string_bytes: 512,
      }),
    )
    let object = credential_decoded(
      @decode.closed_object(cursor, [
        "client_request_intent_cid", "client_request_scope_cid", "operation_occurrence_cid",
        "run_invocation_cid", "unit_definition_cid", "version",
      ]),
    )
    if credential_text(object, "version") != "actql-local-preparation-fence/0.1" {
      return Err(InvalidCredentialGrant)
    }
    let value = match
      prepare_local_preparation_fence_identity({
        client_request_intent_cid: credential_text(
          object, "client_request_intent_cid",
        ),
        client_request_scope_cid: credential_text(
          object, "client_request_scope_cid",
        ),
        operation_occurrence_cid: credential_text(
          object, "operation_occurrence_cid",
        ),
        run_invocation_cid: credential_text(object, "run_invocation_cid"),
        unit_definition_cid: credential_text(object, "unit_definition_cid"),
      }) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if value.body != body {
      return Err(InvalidCredentialGrant)
    }
    if value.cid != claimed_cid {
      return Err(CredentialGrantIdentityMismatch)
    }
    Ok(value)
  } catch {
    RemoteCredentialDecodeStop => Err(InvalidCredentialGrant)
  }
}
