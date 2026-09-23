///|
pub(all) enum EffectPreviewIdentityIssue {
  PreviewShape(PublicationContractIssue)
  InvalidMember
  MemberIdentityMismatch(Int)
  PreviewIdentityMismatch
  RunBindingMismatch
  AuthoringBindingMismatch
  AuthoringIdentityMismatch
  Encoding
} derive(Eq, Debug)

///|
pub struct EffectPreviewIdentity {
  semantic_cid : String
  member_cids : Array[String]
  row_keys : Array[Array[String]]
  run_identity_cid : String
  authoring_context_cid : String
}

///|
fn emit_effect_change_semantics(
  value : @json.CanonicalValue,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let fields = @json.object_fields(value).unwrap()
  @encode.begin_object(writer)
  for (name, child) in fields {
    if name != "row_idempotency_key" {
      @encode.key(writer, name)
      @json.emit_value(child, writer)
    }
  }
  @encode.end_object(writer)
}

///|
fn emit_effect_member_semantics(
  value : @json.CanonicalValue,
  writer : @encode.Writer,
  identity_override : String?,
) -> Unit raise @encode.EncodeFailure {
  let fields = @json.object_fields(value).unwrap()
  @encode.begin_object(writer)
  for (name, child) in fields {
    if name == "effect_member_preview_cid" && identity_override is None {
      continue
    }
    @encode.key(writer, name)
    if name == "effect_member_preview_cid" {
      @encode.string_value(writer, identity_override.unwrap())
    } else if name == "changes" {
      let changes = match child {
        @json.Array(items) => @json.array_values(items)
        _ => abort("Effect Preview shape admission required")
      }
      @encode.begin_array(writer)
      for change in changes {
        emit_effect_change_semantics(change, writer)
      }
      @encode.end_array(writer)
    } else {
      @json.emit_value(child, writer)
    }
  }
  @encode.end_object(writer)
}

///|
fn effect_member_semantic_cid(
  effect : @json.CanonicalValue,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, EffectPreviewIdentityIssue] {
  let writer = @encode.hashing_writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  let digest = try {
    @encode.begin_object(writer)
    @encode.key(writer, "member")
    emit_effect_member_semantics(effect, writer, None)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-effect-member-preview/0.1")
    @encode.end_object(writer)
    @encode.finish_hash(writer)
  } catch {
    _ => return Err(Encoding)
  }
  Ok("sha256:" + digest)
}

///|
fn effect_preview_semantic_cid(
  preview : @json.CanonicalValue,
  member_cids : Array[String],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, EffectPreviewIdentityIssue] {
  let writer = @encode.hashing_writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  let digest = try {
    @encode.begin_object(writer)
    for (name, child) in @json.object_fields(preview).unwrap() {
      if name == "effect_preview_cid" ||
        name == "run_identity_cid" ||
        name == "authoring_context" {
        continue
      }
      @encode.key(writer, name)
      if name == "effects" {
        let members = match child {
          @json.Array(items) => @json.array_values(items)
          _ => abort("Effect Preview shape admission required")
        }
        @encode.begin_array(writer)
        for index in 0..<members.length() {
          emit_effect_member_semantics(
            members[index],
            writer,
            Some(member_cids[index]),
          )
        }
        @encode.end_array(writer)
      } else {
        @json.emit_value(child, writer)
      }
    }
    @encode.end_object(writer)
    @encode.finish_hash(writer)
  } catch {
    _ => return Err(Encoding)
  }
  Ok("sha256:" + digest)
}

///|
/// Return independently derived identities after complete 0.1 shape
/// admission. Derived row keys are excluded from both semantic preimages,
/// but remain required transport fields and must be checked at apply.
pub fn derive_effect_preview_identities(
  wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[(String, Array[String]), EffectPreviewIdentityIssue] {
  let preview = match
    parse_effect_preview_shape(wire, max_wire_bytes, max_nodes, max_depth) {
    Ok(value) => value
    Err(issue) => return Err(PreviewShape(issue))
  }
  let members = match @json.object_field(preview, "effects") {
    Some(@json.Array(items)) => @json.array_values(items)
    _ => return Err(InvalidMember)
  }
  let cids = []
  for effect in members {
    let cid = match
      effect_member_semantic_cid(effect, max_wire_bytes, max_nodes, max_depth) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    cids.push(cid)
  }
  let cid = match
    effect_preview_semantic_cid(
      preview, cids, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok((cid, cids))
}

///|
/// Identity admission does not confer apply authority. Exact Run and
/// Authoring Context bindings are checked separately from the semantic CID.
pub fn admit_effect_preview_identity(
  wire : String,
  expected_run_identity_cid : String,
  expected_authoring_context_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[EffectPreviewIdentity, EffectPreviewIdentityIssue] {
  let preview = match
    parse_effect_preview_shape(wire, max_wire_bytes, max_nodes, max_depth) {
    Ok(value) => value
    Err(issue) => return Err(PreviewShape(issue))
  }
  let members = match @json.object_field(preview, "effects") {
    Some(@json.Array(items)) => @json.array_values(items)
    _ => return Err(InvalidMember)
  }
  let cids = []
  let row_keys : Array[Array[String]] = []
  for index in 0..<members.length() {
    let effect = members[index]
    let changes = match @json.object_field(effect, "changes") {
      Some(@json.Array(items)) => @json.array_values(items)
      _ => return Err(InvalidMember)
    }
    let member_keys : Array[String] = []
    for change in changes {
      match @json.object_field(change, "row_idempotency_key") {
        Some(@json.String(value)) => member_keys.push(value)
        _ => return Err(InvalidMember)
      }
    }
    row_keys.push(member_keys)
    let cid = match
      effect_member_semantic_cid(effect, max_wire_bytes, max_nodes, max_depth) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let supplied = match
      @json.object_field(effect, "effect_member_preview_cid") {
      Some(@json.String(value)) => value
      _ => return Err(MemberIdentityMismatch(index))
    }
    if supplied != cid {
      return Err(MemberIdentityMismatch(index))
    }
    cids.push(cid)
  }
  let cid = match
    effect_preview_semantic_cid(
      preview, cids, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let supplied = match @json.object_field(preview, "effect_preview_cid") {
    Some(@json.String(value)) => value
    _ => return Err(PreviewIdentityMismatch)
  }
  if supplied != cid {
    return Err(PreviewIdentityMismatch)
  }
  let run = match @json.object_field(preview, "run_identity_cid") {
    Some(@json.String(value)) => value
    _ => return Err(RunBindingMismatch)
  }
  if run != expected_run_identity_cid {
    return Err(RunBindingMismatch)
  }
  let (authoring, authoring_value) = match
    @json.object_field(preview, "authoring_context") {
    Some(value) =>
      match @json.object_field(value, "authoring_context_cid") {
        Some(@json.String(cid)) => (cid, value)
        _ => return Err(AuthoringBindingMismatch)
      }
    _ => return Err(AuthoringBindingMismatch)
  }
  if authoring != expected_authoring_context_cid {
    return Err(AuthoringBindingMismatch)
  }
  if !evidence_identity_valid(
      authoring_value, "authoring_context_cid", max_wire_bytes, max_nodes, max_depth,
    ) ||
    optional_string(
      @json.object_field(authoring_value, "program_definition_cid"),
    ) !=
    optional_string(@json.object_field(preview, "program_definition_cid")) {
    return Err(AuthoringIdentityMismatch)
  }
  Ok({
    semantic_cid: cid,
    member_cids: cids,
    row_keys,
    run_identity_cid: run,
    authoring_context_cid: authoring,
  })
}

///|
pub fn effect_preview_semantic_identity(
  value : EffectPreviewIdentity,
) -> String {
  value.semantic_cid
}

///|
pub fn effect_preview_member_identity(
  value : EffectPreviewIdentity,
  index : Int,
) -> String? {
  value.member_cids.get(index)
}

///|
pub fn effect_preview_member_count(value : EffectPreviewIdentity) -> Int {
  value.member_cids.length()
}

///|
pub fn effect_preview_row_count(
  value : EffectPreviewIdentity,
  member_index : Int,
) -> Int? {
  match value.row_keys.get(member_index) {
    Some(keys) => Some(keys.length())
    None => None
  }
}

///|
pub fn effect_preview_row_key(
  value : EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
) -> String? {
  match value.row_keys.get(member_index) {
    Some(keys) => keys.get(row_index)
    None => None
  }
}
