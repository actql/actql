///|
/// The existing protected Local Reviewer and HostAttestation selection
/// addresses. These DATA fields do not admit a key or spend a signing use.
pub struct ClientLocalEffectApprovalSelection {
  registration : @checkpoint.ReviewerAuthority
  reviewer_public_key : String
  host_key_id : String
  host_public_key : String
  private_key_file : String
  signed_resource : String
}

///|
/// Public metadata for explicitly provisioned fresh Local Host attestation.
pub struct ClientLocalEffectAttestationSelection {
  key_id : String
  public_key : String
  private_key_file : String
  resource : String
}

///|
fn client_local_effect_approval_object(
  wire : String,
  role : String,
  names : Array[String],
) -> @decode.ObjectView? {
  let bytes = @utf8.encode(wire)
  guard bytes.length() <= 8192 &&
    @source.parse_json_bytes_preserving(bytes, {
      max_input_bytes: 8192,
      max_nodes: 32,
      max_depth: 4,
    })
    is Ok(source) &&
    @decode.admit(source, {
      max_nodes: 32,
      max_depth: 4,
      max_string_bytes: 4096,
      max_total_string_bytes: 6144,
    })
    is Ok(cursor) &&
    @decode.closed_object(cursor, ["version", "native"]) is Ok(root) &&
    client_checkpoint_text(root, "version") == Some("actql-config/0.1") &&
    @decode.required(root, "native") is Ok(native) &&
    @decode.closed_object(native, [role]) is Ok(selected) &&
    @decode.required(selected, role) is Ok(value) &&
    @decode.closed_object(value, names) is Ok(fields) else {
    return None
  }
  Some(fields)
}

///|
fn client_effect_approval_selection_text(
  fields : @decode.ObjectView,
  name : String,
  bound : Int,
) -> String? {
  guard client_checkpoint_text(fields, name) is Some(value) &&
    !value.is_empty() &&
    !value.contains("\u{0000}") &&
    @scalar.admit_utf8_length(value, bound) is Ok(_) else {
    return None
  }
  Some(value)
}

///|
fn client_local_effect_approval_control(
  fields : @decode.ObjectView,
  principal : String,
  connection : String,
) -> Bool {
  @decode.required(fields, "enabled") is Ok(enabled) &&
  @decode.boolean(enabled) == Ok(true) &&
  client_effect_approval_selection_text(fields, "principal", 512) ==
  Some(principal) &&
  client_effect_approval_selection_text(fields, "connection", 512) ==
  Some(connection)
}

///|
/// Admit the exact independently provisioned attestation subject before
/// Account bootstrap. No protected key or reviewer registration is read here.
pub fn admit_client_local_effect_attestation_selection(
  wire : String,
  principal : String,
  connection : String,
) -> ClientLocalEffectAttestationSelection? {
  guard client_local_effect_approval_object(wire, "signing_key", [
      "enabled", "purpose", "principal", "connection", "resource", "key_id", "private_key_file",
      "public_key_pem", "checkpoint_kinds",
    ])
    is Some(host) &&
    client_local_effect_approval_control(host, principal, connection) &&
    client_checkpoint_text(host, "purpose") == Some("host_attestation") &&
    @decode.required(host, "checkpoint_kinds") is Ok(kinds) &&
    @decode.array_length(kinds) == Some(1) &&
    @decode.element_at(kinds, 0) is Some(kind) &&
    @decode.text(kind) == Ok("effect_set") &&
    client_effect_approval_selection_text(host, "resource", 512)
    is Some(resource) &&
    client_effect_approval_selection_text(host, "key_id", 128) is Some(key_id) &&
    client_effect_approval_selection_text(host, "public_key_pem", 4096)
    is Some(public_key) &&
    client_effect_approval_selection_text(host, "private_key_file", 128)
    is Some(private_key_file) &&
    private_key_file != "." &&
    private_key_file != ".." &&
    !private_key_file.contains("/") &&
    !private_key_file.contains("\\") else {
    return None
  }
  Some({ key_id, public_key, private_key_file, resource, })
}

///|
/// Both protected originals explicitly select the exact current Local
/// principal and disjoint roles. The physical owner then authorizes this
/// resource, confirms its use and compares its actual signing key.
pub fn admit_client_local_effect_approval_selection(
  reviewer_wire : String,
  host_wire : String,
  principal : String,
  connection : String,
) -> ClientLocalEffectApprovalSelection? {
  guard client_local_effect_approval_object(reviewer_wire, "effect_reviewer", [
      "enabled", "principal", "connection", "key_id", "reviewer_id", "public_key_pem",
    ])
    is Some(reviewer) &&
    client_local_effect_approval_control(reviewer, principal, connection) &&
    admit_client_local_effect_attestation_selection(
      host_wire, principal, connection,
    )
    is Some(host) &&
    client_effect_approval_selection_text(reviewer, "key_id", 128)
    is Some(reviewer_key) &&
    client_effect_approval_selection_text(reviewer, "reviewer_id", 128)
    is Some(reviewer_id) &&
    client_effect_approval_selection_text(reviewer, "public_key_pem", 4096)
    is Some(reviewer_public_key) &&
    host.key_id != reviewer_key &&
    host.public_key != reviewer_public_key else {
    return None
  }
  Some({
    registration: { key_id: reviewer_key, reviewer_id, },
    reviewer_public_key,
    host_key_id: host.key_id,
    host_public_key: host.public_key,
    private_key_file: host.private_key_file,
    signed_resource: host.resource,
  })
}
