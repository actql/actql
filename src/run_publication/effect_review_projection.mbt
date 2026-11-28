///|
pub(all) enum EffectReviewProjectionIssue {
  InvalidLimits
  InvalidPolicy
  ForeignPreview
  InsufficientEvidence(Int, Int)
  Preview(EffectPreviewIdentityIssue)
  Evidence(RunEvidenceValueIssue)
  Encoding
  DisplayLimit
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
// Admit the original member and row evidence independently of the policy
// envelope. The same canonical Preview supplies all displayed values.
fn admit_effect_display_evidence(
  original : EffectPreviewIdentity,
  preview_wire : String,
  preview_bytes : Int,
  preview_nodes : Int,
  preview_depth : Int,
  member_preview_cid? : String,
) -> Result[
  (@json.CanonicalValue, Array[@json.CanonicalValue]),
  EffectReviewProjectionIssue,
] {
  let (checked, preview) = match
    admit_effect_preview_identity_with_original(
      preview_wire,
      original.run_identity_cid,
      original.authoring_context_cid,
      preview_bytes,
      preview_nodes,
      preview_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Preview(issue))
  }
  if checked.semantic_cid != original.semantic_cid {
    return Err(ForeignPreview)
  }
  let members = match @json.object_field(preview, "effects") {
    Some(@json.Array(items)) => @json.array_values(items)
    _ => return Err(ForeignPreview)
  }
  let mut selected = None
  for effect_index, effect in members {
    if member_preview_cid is Some(expected) {
      if original.member_cids.get(effect_index) != Some(expected) ||
        checked.member_cids.get(effect_index) != Some(expected) {
        continue
      }
      selected = Some(effect)
    }
    guard @json.object_field(effect, "changes") is Some(@json.Array(changes)) else {
      return Err(ForeignPreview)
    }
    for row_index, row in @json.array_values(changes) {
      if !review_row_evidence_sufficient(effect, row) {
        return Err(InsufficientEvidence(effect_index, row_index))
      }
    }
  }
  match (member_preview_cid, selected) {
    (Some(_), Some(effect)) => Ok((preview, [effect]))
    (Some(_), None) => Err(ForeignPreview)
    _ => Ok((preview, members))
  }
}

///|
fn emit_effect_display_evidence(
  writer : @encode.Writer,
  members : Array[@json.CanonicalValue],
) -> Result[Unit, EffectReviewProjectionIssue] raise @encode.EncodeFailure {
  @encode.key(writer, "displayed_scope")
  @encode.begin_object(writer)
  @encode.key(writer, "effects")
  @encode.begin_array(writer)
  for effect in members {
    @encode.begin_object(writer)
    review_field(writer, effect, "effect_id")
    @encode.key(writer, "kind")
    @json.emit_value(@json.object_field(effect, "effect_kind").unwrap(), writer)
    review_field(writer, effect, "target")
    review_field(writer, effect, "count")
    @encode.end_object(writer)
  }
  @encode.end_array(writer)
  @encode.end_object(writer)
  emit_effect_display_values(writer, members)
}

///|
// Only the selected Member contributes row values and permissions to a Debug
// read. The independent policy review can still project its admitted scope.
fn emit_effect_display_values(
  writer : @encode.Writer,
  members : Array[@json.CanonicalValue],
) -> Result[Unit, EffectReviewProjectionIssue] raise @encode.EncodeFailure {
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
      for name in ["row_preview_cid", "target_row_identity", "before", "after"] {
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
  Ok(())
}

///|
fn emit_debug_effect_set(
  writer : @encode.Writer,
  original : EffectPreviewIdentity,
  preview : @json.CanonicalValue,
  unit_id : String,
  member_preview_cid : String,
) -> Result[Unit, EffectReviewProjectionIssue] raise @encode.EncodeFailure {
  guard @json.object_field(preview, "effects") is Some(@json.Array(effects)) else {
    return Err(ForeignPreview)
  }
  @encode.key(writer, "effect_set")
  @encode.begin_object(writer)
  review_text(writer, "kind", "unordered")
  review_text(writer, "unit_id", unit_id)
  review_text(writer, "active_member_preview_cid", member_preview_cid)
  @encode.key(writer, "members")
  @encode.begin_array(writer)
  for index, effect in @json.array_values(effects) {
    guard effect_preview_member_identity(original, index) is Some(member_cid) else {
      return Err(ForeignPreview)
    }
    @encode.begin_object(writer)
    review_field(writer, effect, "effect_id")
    review_text(writer, "member_preview_cid", member_cid)
    @encode.key(writer, "kind")
    @json.emit_value(@json.object_field(effect, "effect_kind").unwrap(), writer)
    review_field(writer, effect, "target")
    @encode.key(writer, "input")
    @encode.begin_object(writer)
    match effect_preview_member_relation_source(original, index) {
      Some(source) => {
        guard effect_preview_member_result_artifact_cid(original, index)
          is Some(artifact_cid) else {
          return Err(ForeignPreview)
        }
        let (kind, name) = match source {
          Result(name) => ("result", name)
          TableInput(name) => ("table_input", name)
        }
        review_text(writer, "kind", kind)
        review_text(writer, "name", name)
        review_text(writer, "artifact_cid", artifact_cid)
      }
      None => review_text(writer, "kind", "none")
    }
    @encode.end_object(writer)
    @encode.end_object(writer)
  }
  @encode.end_array(writer)
  @encode.end_object(writer)
  Ok(())
}

///|
/// Project the unordered inventory of the original sealed Preview and display
/// data for its one active Member. The caller supplies the checked Unit from
/// the same captured Effect owner and owns the live park/read permission.
pub fn project_effect_preview_changes(
  original : EffectPreviewIdentity,
  preview_wire : String,
  preview_limits : (Int, Int, Int),
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  unit_id : String,
  member_preview_cid : String,
) -> Result[String, EffectReviewProjectionIssue] {
  let (preview_bytes, preview_nodes, preview_depth) = preview_limits
  if preview_bytes < 1 ||
    preview_nodes < 2 ||
    preview_depth < 1 ||
    max_wire_bytes < 1 ||
    max_nodes < 2 ||
    max_depth < 1 {
    return Err(InvalidLimits)
  }
  let (preview, members) = match
    admit_effect_display_evidence(
      original,
      preview_wire,
      preview_bytes,
      preview_nodes,
      preview_depth,
      member_preview_cid~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  try {
    let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    @encode.begin_object(writer)
    review_text(writer, "effect_preview_cid", original.semantic_cid)
    match
      emit_debug_effect_set(
        writer, original, preview, unit_id, member_preview_cid,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    match emit_effect_display_values(writer, members) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    @encode.OutputLimit => Err(DisplayLimit)
    _ => Err(Encoding)
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
  preview_limits? : (Int, Int, Int)? = None,
  before_emission? : ((@encode.EncodingConstructionGeometry) -> Bool)? = None,
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
  // The private Preview and its public review have independent codec policies.
  // Keeping the output small must not reinterpret an already admitted input.
  let (preview_bytes, preview_nodes, preview_depth) = preview_limits.unwrap_or(
    (max_wire_bytes, max_nodes, max_depth),
  )
  if preview_bytes < 1 || preview_nodes < 2 || preview_depth < 1 {
    return Err(InvalidLimits)
  }
  let (preview, members) = match
    admit_effect_display_evidence(
      original, preview_wire, preview_bytes, preview_nodes, preview_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let emit = fn(
    writer : @encode.Writer,
  ) -> Result[Unit, EffectReviewProjectionIssue] raise @encode.EncodeFailure {
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
    match emit_effect_display_evidence(writer, members) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    @encode.key(writer, "displayed_authoring_context")
    @encode.begin_array(writer)
    @json.emit_value(
      @json.object_field(preview, "authoring_context").unwrap(),
      writer,
    )
    @encode.end_array(writer)
    @encode.end_object(writer)
    Ok(())
  }
  let body_wire = try {
    if before_emission is Some(reserve) {
      let meter = @encode.construction_measuring_writer(
        max_wire_bytes, max_nodes, max_depth,
      )
      match emit(meter) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      let geometry = @encode.finish_construction_measurement(meter)
      if !reserve(geometry) {
        return Err(Encoding)
      }
    }
    let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    match emit(writer) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
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
  preview_limits? : (Int, Int, Int)? = None,
) -> Result[RunEvidenceValue, EffectReviewProjectionIssue] {
  let expected = match
    project_effect_review_projection(
      original,
      preview_wire,
      authority_scope_cid,
      approval_claims,
      redaction_policy_cid,
      max_wire_bytes,
      max_nodes,
      max_depth,
      preview_limits~,
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

///|
/// Size the SAME immutable Preview wire before its review constructor. The
/// caller first funds the existing fixed preflight controls, then reserves
/// this returned peak beside all retained Run/Preview owners. Geometry does
/// not admit the wire or confer authority; projection still checks its shape,
/// complete identities and exact original semantic CID.
pub fn effect_review_projection_construction_inventory(
  preview_wire : String,
  preview_bytes : Int,
  preview_nodes : Int,
  preview_depth : Int,
  review_bytes : Int,
  review_nodes : Int,
  review_depth : Int,
) -> (
  EffectPreviewIdentityConstructionInventory,
  EffectPreviewIdentityConstructionInventory,
)? {
  if preview_bytes < 1 ||
    preview_nodes < 2 ||
    preview_depth < 1 ||
    review_bytes < 1 ||
    review_nodes < 2 ||
    review_depth < 1 {
    return None
  }
  guard capture_plan_construction_extent(
      preview_wire,
      preview_bytes,
      preview_nodes,
      preview_depth,
      _ => true,
    )
    is Some((bytes, nodes, depth)) else {
    return None
  }
  let nodes = Int::min(nodes, preview_nodes)
  let depth = Int::min(depth, preview_depth)
  // Projection emits each selected input subtree once, plus row/member
  // wrappers, effect IDs, policy and fixed envelope fields. Four nodes per
  // input node plus64 bounds those additions even for a one-node refused
  // prefix. Writer limits independently stop larger output before allocation.
  let output_nodes = Int64::min(
    review_nodes.to_int64(),
    Int64::min(review_bytes.to_int64(), 4L * nodes.to_int64() + 64L),
  ).to_int()
  let output_depth = Int64::min(review_depth.to_int64(), depth.to_int64() + 4L).to_int()
  guard effect_preview_identity_construction_inventory(bytes, nodes, depth)
    is Some(input) &&
    protocol_wire_codec_construction_inventory(
      review_bytes, output_nodes, output_depth,
    )
    is Some(output) else {
    return None
  }
  // The one Preview identity admission retains its checked canonical tree
  // for rendering. The Review body writer, its generic sealing parser/forest,
  // complete self-CID wrapper and final encoder coexist with that input;
  // two output inventories cover these returned and refused prefixes. No
  // parser frame, writer buffer or returned review is treated as released here.
  review_construction_inventory_parts(
    input, output, review_bytes, output_nodes, output_depth,
  )
}

///|
fn review_construction_inventory_parts(
  input : EffectPreviewIdentityConstructionInventory,
  output : EffectPreviewIdentityConstructionInventory,
  review_bytes : Int,
  output_nodes : Int,
  output_depth : Int,
  geometry? : @encode.EncodingConstructionGeometry? = None,
) -> (
  EffectPreviewIdentityConstructionInventory,
  EffectPreviewIdentityConstructionInventory,
)? {
  let n = output_nodes.to_int64()
  let d = output_depth.to_int64()
  // Two Common RunEvidence values (issued and Checkpoint-admitted), the
  // Checkpoint's detached JSON body, both complete wire Strings, Host token
  // views/arrays and the response bytes may coexist through evidence.hold.
  // Keep these returned DATA on the SAME Run control until retirement.
  let canonical = match geometry {
    None =>
      @shape.collection_construction_extent({
        records: 2L * (3L * n + 3L * d + 1L) + 24L,
        record_references: 2L * (4L * n + 6L * d) + 64L,
        record_words: 2L * (2L * n + 4L * d + 3L) + 24L,
        reference_arrays: 4L * n + 8L,
        reference_items: 6L * n + 24L,
        scalar_arrays: 0L,
        scalar_items: 0L,
        maps: 2L * n,
        map_entries: 2L * n,
      })
    Some(value) =>
      @json.source_conversion_construction_extent(
        output_nodes,
        value.fields,
        value.objects,
        value.arrays,
        output_depth,
        0,
      ).map(value => {
        record_headers: 2L * value.retained.record_headers + 24L,
        reference_slots: 2L * value.retained.reference_slots + 64L,
        scalar_words: 2L * value.retained.scalar_words + 24L,
      })
  }
  guard canonical is Some(canonical) &&
    @source.json_tree_retained_construction_extent(
      output_nodes,
      geometry.map(value => value.fields).unwrap_or(output_nodes - 1),
      geometry.map(value => value.objects).unwrap_or(output_nodes),
      geometry.map(value => value.arrays).unwrap_or(0),
      review_bytes.to_int64(),
      keep_spans=false,
    )
    is Some(host) else {
    return None
  }
  let returned : EffectPreviewIdentityConstructionInventory = {
    // originalReview performs its strict admission AFTER the first synchronous
    // projection returns. Keep that later parser/hash/writer envelope here;
    // completion cannot return it before the Checkpoint caller has adopted it.
    record_headers: canonical.record_headers +
    host.record_headers +
    output.record_headers,
    reference_slots: canonical.reference_slots +
    host.reference_slots +
    output.reference_slots,
    scalar_words: canonical.scalar_words +
    host.scalar_words +
    output.scalar_words,
    // Two canonical forests, the Host forest and two independently encoded
    // complete wires. Original Preview/policy strings remain on prior owners.
    owned_utf16_units: 5L * review_bytes.to_int64() + output.owned_utf16_units,
    owned_wire_bytes: 4L * review_bytes.to_int64() + output.owned_wire_bytes,
  }
  let temporary : EffectPreviewIdentityConstructionInventory = {
    // The admission returns one pair holding the identity and the tree.
    record_headers: input.record_headers + 2L * output.record_headers + 9L,
    reference_slots: input.reference_slots + 2L * output.reference_slots + 26L,
    scalar_words: input.scalar_words + 2L * output.scalar_words + 17L,
    owned_utf16_units: input.owned_utf16_units + 2L * output.owned_utf16_units,
    owned_wire_bytes: input.owned_wire_bytes + 2L * output.owned_wire_bytes,
  }
  Some((returned, temporary))
}
