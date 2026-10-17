///|
pub(all) enum EffectReviewProjectionIssue {
  InvalidLimits
  InvalidPolicy
  ForeignPreview
  InsufficientEvidence(Int, Int)
  Preview(EffectPreviewIdentityIssue)
  Evidence(RunEvidenceValueIssue)
  Encoding
} derive(Eq, Debug)

///|
fn review_text(
  writer : @encode.Writer,
  name : String,
  value : String,
) -> Unit raise @encode.EncodeFailure {
  @encode.key(writer, name)
  @encode.string_value(writer, value)
}

///|
fn review_field(
  writer : @encode.Writer,
  value : @json.CanonicalValue,
  name : String,
) -> Unit raise @encode.EncodeFailure {
  @encode.key(writer, name)
  @json.emit_value(@json.object_field(value, name).unwrap(), writer)
}

///|
fn review_row_state(value : @json.CanonicalValue) -> String? {
  guard @json.object_field(value, "state") is Some(@json.String(state)) else {
    return None
  }
  if state == "present" {
    if @json.object_field_count(value) == Some(2) &&
      @json.object_field(value, "value").bind(@json.object_field_count)
      is Some(_) {
      Some(state)
    } else {
      None
    }
  } else if ["absent", "unavailable", "not_applicable"].contains(state) &&
    @json.object_field_count(value) == Some(1) {
    Some(state)
  } else {
    None
  }
}

///|
// The private row identity already enforces original guard/change and operation
// obligations. A public sealed review additionally cannot claim full_diff with
// an unavailable before/after, or targeted with invented before evidence.
fn review_row_evidence_sufficient(
  effect : @json.CanonicalValue,
  row : @json.CanonicalValue,
) -> Bool {
  guard @json.object_field(effect, "effect_kind") is Some(@json.String(kind)) &&
    @json.object_field(effect, "preview_strength")
    is Some(@json.String(strength)) &&
    @json.object_field(row, "before").bind(review_row_state) is Some(before) &&
    @json.object_field(row, "after").bind(review_row_state) is Some(after) else {
    return false
  }
  if ["update", "delete", "upsert"].contains(kind) {
    if strength == "targeted" {
      if before != "unavailable" {
        return false
      }
    } else if strength == "full_diff" {
      if before != "present" && !(kind == "upsert" && before == "absent") {
        return false
      }
    } else {
      return false
    }
    if kind == "delete" {
      after == "absent"
    } else {
      after == "present"
    }
  } else if kind == "create" {
    after == "present"
  } else {
    // Command/store keep their exact kind-specific payload and row states;
    // this does not invent a before row or infer a stronger Preview.
    kind == "command" || kind == "store"
  }
}

///|
/// Project only the already admitted original Preview. The trusted Host owns
/// policy/claim originals and their current authorization; these DATA inputs
/// and the resulting public CID confer no apply, resume or storage authority.
/// Re-admission checks the complete row/member chain, exact Run and Authoring
/// Context before any displayed evidence is emitted.
pub fn project_effect_review_projection(
  original : EffectPreviewIdentity,
  preview_wire : String,
  authority_scope_cid : String,
  approval_claims : Array[String],
  redaction_policy_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[RunEvidenceValue, EffectReviewProjectionIssue] {
  if max_wire_bytes < 1 || max_nodes < 2 || max_depth < 1 {
    return Err(InvalidLimits)
  }
  if !valid_contract_cid(authority_scope_cid) ||
    !valid_contract_cid(redaction_policy_cid) ||
    approval_claims.length() < 1 ||
    approval_claims.length() > 2 {
    return Err(InvalidPolicy)
  }
  for index in 0..<approval_claims.length() {
    let claim = approval_claims[index]
    if claim != "effect_scope_approved" &&
      claim != "partial_application_accepted" {
      return Err(InvalidPolicy)
    }
    for previous in 0..<index {
      if approval_claims[previous] == claim {
        return Err(InvalidPolicy)
      }
    }
  }
  if !approval_claims.contains("effect_scope_approved") {
    return Err(InvalidPolicy)
  }
  let checked = match
    admit_effect_preview_identity(
      preview_wire,
      original.run_identity_cid,
      original.authoring_context_cid,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Preview(issue))
  }
  if checked.semantic_cid != original.semantic_cid {
    return Err(ForeignPreview)
  }
  let preview = match
    parse_effect_preview_shape(
      preview_wire, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Preview(PreviewShape(issue)))
  }
  let members = match @json.object_field(preview, "effects") {
    Some(@json.Array(items)) => @json.array_values(items)
    _ => return Err(ForeignPreview)
  }
  for effect_index, effect in members {
    guard @json.object_field(effect, "changes") is Some(@json.Array(changes)) else {
      return Err(ForeignPreview)
    }
    for row_index, row in @json.array_values(changes) {
      if !review_row_evidence_sufficient(effect, row) {
        return Err(InsufficientEvidence(effect_index, row_index))
      }
    }
  }
  let body_wire = try {
    let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    @encode.begin_object(writer)
    review_text(writer, "version", "actql-review-projection/0.1")
    review_text(writer, "effect_preview_cid", original.semantic_cid)
    review_text(writer, "authority_scope_cid", authority_scope_cid)
    @encode.key(writer, "approval_claims")
    @encode.begin_array(writer)
    for claim in approval_claims {
      @encode.string_value(writer, claim)
    }
    @encode.end_array(writer)
    review_text(writer, "authoring_context_cid", original.authoring_context_cid)
    review_text(writer, "redaction_policy_cid", redaction_policy_cid)
    review_text(writer, "sensitivity", "restricted")
    review_text(writer, "retention_class", "approval-evidence")
    @encode.key(writer, "encryption_required")
    @encode.bool_value(writer, true)
    @encode.key(writer, "displayed_scope")
    @encode.begin_object(writer)
    @encode.key(writer, "effects")
    @encode.begin_array(writer)
    for effect in members {
      @encode.begin_object(writer)
      review_field(writer, effect, "effect_id")
      @encode.key(writer, "kind")
      @json.emit_value(
        @json.object_field(effect, "effect_kind").unwrap(),
        writer,
      )
      review_field(writer, effect, "target")
      review_field(writer, effect, "count")
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.end_object(writer)
    @encode.key(writer, "displayed_permissions")
    @encode.begin_array(writer)
    for effect in members {
      guard @json.object_field(effect, "required_permissions")
        is Some(@json.Array(permissions)) else {
        return Err(ForeignPreview)
      }
      for permission in @json.array_values(permissions) {
        @json.emit_value(permission, writer)
      }
    }
    @encode.end_array(writer)
    @encode.key(writer, "displayed_rows")
    @encode.begin_array(writer)
    for effect in members {
      guard @json.object_field(effect, "changes") is Some(@json.Array(changes)) else {
        return Err(ForeignPreview)
      }
      for row in @json.array_values(changes) {
        @encode.begin_object(writer)
        review_field(writer, effect, "effect_id")
        for
          name in ["row_preview_cid", "target_row_identity", "before", "after"] {
          review_field(writer, row, name)
        }
        // Strength comes from the original member, never from row shape or
        // kind. Guard and intended change retain their exact original states.
        review_field(writer, effect, "preview_strength")
        review_field(writer, row, "target_guard")
        review_field(writer, row, "intended_changes")
        @encode.end_object(writer)
      }
    }
    @encode.end_array(writer)
    @encode.key(writer, "displayed_authoring_context")
    @encode.begin_array(writer)
    @json.emit_value(
      @json.object_field(preview, "authoring_context").unwrap(),
      writer,
    )
    @encode.end_array(writer)
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(Encoding)
  }
  seal_run_evidence_value(
    "review_projection", body_wire, max_wire_bytes, max_nodes, max_depth,
  ).map_err(issue => Evidence(issue))
}

///|
/// Structural legacy compatibility cannot upgrade insufficient evidence. New
/// review/approval admission compares every displayed value with the same
/// original Preview and trusted policy originals, including all three row
/// evidence fields. This returns DATA, not an approval or apply permission.
pub fn admit_effect_review_projection(
  original : EffectPreviewIdentity,
  preview_wire : String,
  review_wire : String,
  authority_scope_cid : String,
  approval_claims : Array[String],
  redaction_policy_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[RunEvidenceValue, EffectReviewProjectionIssue] {
  let expected = match
    project_effect_review_projection(
      original, preview_wire, authority_scope_cid, approval_claims, redaction_policy_cid,
      max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let admitted = match
    admit_run_evidence_value(
      "review_projection", review_wire, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Evidence(issue))
  }
  if admitted.wire != expected.wire {
    return Err(ForeignPreview)
  }
  Ok(admitted)
}
