///|
pub(all) enum EffectReviewProjectionIssue {
  InvalidLimits
  InvalidPolicy
  ForeignPreview
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
    for member in members {
      @encode.begin_object(writer)
      review_field(writer, member, "effect_id")
      @encode.key(writer, "kind")
      @json.emit_value(
        @json.object_field(member, "effect_kind").unwrap(),
        writer,
      )
      review_field(writer, member, "target")
      review_field(writer, member, "count")
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.end_object(writer)
    @encode.key(writer, "displayed_permissions")
    @encode.begin_array(writer)
    for member in members {
      guard @json.object_field(member, "required_permissions")
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
    for member in members {
      guard @json.object_field(member, "changes") is Some(@json.Array(changes)) else {
        return Err(ForeignPreview)
      }
      for row in @json.array_values(changes) {
        @encode.begin_object(writer)
        review_field(writer, member, "effect_id")
        for
          name in ["row_preview_cid", "target_row_identity", "before", "after"] {
          review_field(writer, row, name)
        }
        // Strength comes from the original member, never from row shape or
        // kind. Guard and intended change retain their exact original states.
        review_field(writer, member, "preview_strength")
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
