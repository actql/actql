///|
// Bounded installation syntax only. This selection owns no key, permission,
// grant or claim; trusted Host assembly must select its adopted original file.
struct NativeLocalSigningKeySelection {
  enabled : Bool
  purpose : @credential.LocalSigningPurpose
  principal : String
  connection : String
  resource : String
  key_id : String
  private_key_file : String
  public_key_pem : String
  kinds : Array[@checkpoint.CheckpointKind]
}

///|
pub(all) enum NativeLocalSigningKeySelectionIssue {
  InvalidSigningKeySelection
  SigningKeySelectionLimitExceeded
}

///|
priv suberror LocalSigningSelectionStop {
  LocalSigningSelectionStop(NativeLocalSigningKeySelectionIssue)
}

///|
fn[T] signing_selection_decoded(
  value : Result[T, @decode.Issue],
) -> T raise LocalSigningSelectionStop {
  match value {
    Ok(value) => value
    Err(_) => raise LocalSigningSelectionStop(InvalidSigningKeySelection)
  }
}

///|
fn signing_selection_text(
  fields : @decode.ObjectView,
  name : String,
  bound : Int,
) -> String raise LocalSigningSelectionStop {
  let value = signing_selection_decoded(
    @decode.text(signing_selection_decoded(@decode.required(fields, name))),
  )
  if value.is_empty() || value.contains("\u{0}") {
    raise LocalSigningSelectionStop(InvalidSigningKeySelection)
  }
  if @utf8.encode(value).length() > bound {
    raise LocalSigningSelectionStop(SigningKeySelectionLimitExceeded)
  }
  value
}

///|
/// Admission never discovers a file or validates a public/private key pair.
/// Role-specific current Account checks and authenticated original projection
/// custody remain separate. Copied metadata cannot install an opaque key.
pub fn admit_native_local_signing_key_selection(
  wire : String,
) -> Result[NativeLocalSigningKeySelection, NativeLocalSigningKeySelectionIssue] {
  if @utf8.encode(wire).length() > 8192 {
    return Err(SigningKeySelectionLimitExceeded)
  }
  let source = match
    @source.parse_json_bytes_preserving(@utf8.encode(wire), {
      max_input_bytes: 8192,
      max_nodes: 32,
      max_depth: 4,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidSigningKeySelection)
  }
  try {
    let cursor = signing_selection_decoded(
      @decode.admit(source, {
        max_nodes: 32,
        max_depth: 4,
        max_string_bytes: 4096,
        max_total_string_bytes: 6144,
      }),
    )
    let root = signing_selection_decoded(
      @decode.closed_object(cursor, ["version", "native"]),
    )
    if signing_selection_text(root, "version", 32) != "actql-config/0.1" {
      return Err(InvalidSigningKeySelection)
    }
    let native = signing_selection_decoded(
      @decode.closed_object(
        signing_selection_decoded(@decode.required(root, "native")),
        ["signing_key"],
      ),
    )
    let fields = signing_selection_decoded(
      @decode.closed_object(
        signing_selection_decoded(@decode.required(native, "signing_key")),
        [
          "enabled", "purpose", "principal", "connection", "resource", "key_id",
          "private_key_file", "public_key_pem", "checkpoint_kinds",
        ],
      ),
    )
    let purpose = match signing_selection_text(fields, "purpose", 32) {
      "reviewer_proof" => @credential.ReviewerProof
      "host_attestation" => @credential.HostAttestation
      _ => return Err(InvalidSigningKeySelection)
    }
    let private_key_file = signing_selection_text(
      fields, "private_key_file", 128,
    )
    if private_key_file == "." ||
      private_key_file == ".." ||
      private_key_file.contains("/") ||
      private_key_file.contains("\\") {
      return Err(InvalidSigningKeySelection)
    }
    let kinds_cursor = signing_selection_decoded(
      @decode.required(fields, "checkpoint_kinds"),
    )
    guard @decode.array_length(kinds_cursor) is Some(length) &&
      length > 0 &&
      length <= 6 else {
      return Err(InvalidSigningKeySelection)
    }
    let kinds : Array[@checkpoint.CheckpointKind] = []
    for index in 0..<length {
      guard @decode.element_at(kinds_cursor, index) is Some(item) else {
        return Err(InvalidSigningKeySelection)
      }
      let token = signing_selection_decoded(@decode.text(item))
      guard @checkpoint.parse_checkpoint_kind(token) is Some(kind) &&
        !kinds.contains(kind) else {
        return Err(InvalidSigningKeySelection)
      }
      kinds.push(kind)
    }
    Ok({
      enabled: signing_selection_decoded(
        @decode.boolean(
          signing_selection_decoded(@decode.required(fields, "enabled")),
        ),
      ),
      purpose,
      principal: signing_selection_text(fields, "principal", 512),
      connection: signing_selection_text(fields, "connection", 512),
      resource: signing_selection_text(fields, "resource", 512),
      key_id: signing_selection_text(fields, "key_id", 128),
      private_key_file,
      public_key_pem: signing_selection_text(fields, "public_key_pem", 4096),
      kinds,
    })
  } catch {
    LocalSigningSelectionStop(issue) => Err(issue)
  }
}

///|
/// Finite metadata projection. No mutable kind array or key body is disclosed.
pub fn native_local_signing_key_selection_projection(
  selection : NativeLocalSigningKeySelection,
) -> (
  Bool,
  @credential.LocalSigningPurpose,
  String,
  String,
  String,
  String,
  String,
  String,
) {
  (
    selection.enabled,
    selection.purpose,
    selection.principal,
    selection.connection,
    selection.resource,
    selection.key_id,
    selection.private_key_file,
    selection.public_key_pem,
  )
}

///|
pub fn native_local_signing_key_selection_allows_kind(
  selection : NativeLocalSigningKeySelection,
  kind : @checkpoint.CheckpointKind,
) -> Bool {
  selection.kinds.contains(kind)
}
