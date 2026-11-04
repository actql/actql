///|
// Same subject-node request forest and TWO stringify calls as the existing
// subject request. Only the fixed, unescaped GraphQL document grows. Keep the
// old whole envelope when it dominates; no constructor runs while quoting.
fn github_comment_confirmation_request_inventory() -> @execution.PreparationRepresentationUnits? {
  guard github_comment_request_construction_inventory(true) is Some(original) else {
    return None
  }
  let delta = Int64::max(
    0L,
    @catalog.comment_confirmation_query.length().to_int64() -
    @catalog.comment_subject_query.length().to_int64(),
  )
  @execution.compose_preparation_representation([
    original,
    {
      record_headers: 0L,
      reference_slots: 0L,
      scalar_words: 0L,
      // Old/new inner and old/new exported String each contain the document.
      owned_utf16_units: 4L * delta,
      owned_wire_bytes: 0L,
    },
  ])
}

///|
fn github_comment_confirmation_request_capacity() -> @execution.ExecutionCapacity? {
  guard github_comment_confirmation_request_inventory() is Some(retained) else {
    return None
  }
  @execution.preparation_execution_capacity({
    retained,
    workspace: {
      record_headers: 0L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}

///|
// Additional semantic work of the checked ORIGINAL marked body. Native byte
// parsing/index admission and returned-JSON construction remain separate tuple
// roles. Reuse actual decoder Owners for maps, cursors and detached issues;
// neither an allowed key count nor success is assumed for malformed input.
fn github_comment_confirmation_semantic_workspace(
  saved_request : Bool,
) -> @execution.PreparationRepresentationUnits? {
  let nodes = github_comment_page_limits.max_nodes
  let depth = github_comment_page_limits.max_depth
  guard @decode.open_object_construction_extent(nodes) is Some(opened) &&
    @decode.closed_object_field_construction_extent(
      Some(nodes),
      2,
      depth.to_int64(),
    )
    is Some(closed) &&
    @decode.issue_construction_extent(depth) is Some(issue) else {
    return None
  }
  let lookup = @decode.indexed_child_construction_extent()
  // Saved wire admits root and variables as CLOSED objects. Read-back adds
  // one Issue object to the existing response/repository decoder. Supplied
  // widths can each reach the original input-node bound on a refusal.
  let object_headers = if saved_request {
    2L * closed.record_headers
  } else {
    opened.record_headers
  }
  let object_refs = if saved_request {
    2L * closed.reference_slots
  } else {
    opened.reference_slots
  }
  let object_words = if saved_request {
    2L * closed.scalar_words
  } else {
    opened.scalar_words
  }
  // Both paths add four lookup operations. Read-back has three required_text
  // calls (field/decoded/returned Result each); saved wire has two and one
  // direct text Result. Co-count three complete wrong-kind issues, including
  // their original detached paths, rather than assuming successful fields.
  let results = if saved_request { 7L } else { 9L }
  // Same literal prefix, exact71-unit CID DATA and suffix as the original
  // marked-body constructor. Input is borrowed; three source concatenation
  // alternatives are co-counted even when JS fuses them into one template.
  let marker_units = "\n\n<!-- actql:effect:".length().to_int64() +
    71L +
    " -->".length().to_int64()
  let text = 2L * @catalog.max_comment_characters.to_int64() + marker_units
  @execution.compose_preparation_representation([
    {
      record_headers: object_headers,
      reference_slots: object_refs,
      scalar_words: object_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    {
      record_headers: 4L * lookup.record_headers + 3L * issue.record_headers,
      reference_slots: 4L * lookup.reference_slots + 3L * issue.reference_slots,
      scalar_words: 4L * lookup.scalar_words + 3L * issue.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    {
      // Two tag checks each own prefix/suffix StringViews (4H4R8W).
      // Three concat String headers and four marked/row Result alternatives
      // add7H4R4W; text Results above each own1H1R1W. These are constructor
      // records, not a new frame fee or an engine heap measurement.
      record_headers: 11L + results,
      reference_slots: 8L + results,
      scalar_words: 12L + results,
      owned_utf16_units: 3L * text,
      owned_wire_bytes: 0L,
    },
  ])
}

///|
fn github_comment_confirmation_projection_capacity(
  original_report : @execution.ExecutionCapacity,
  saved_request : Bool,
) -> @execution.ExecutionCapacity? {
  guard github_comment_confirmation_semantic_workspace(saved_request)
    is Some(workspace) &&
    @execution.preparation_execution_capacity({
      retained: {
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      workspace,
      retained_nodes: 0L,
      workspace_nodes: 0L,
      retained_bytes: 0L,
      workspace_bytes: 0L,
    })
    is Some(semantic) else {
    return None
  }
  // Keep semantic work co-held with the complete existing response envelope.
  // Its8-node/depth3 JSON report bounds both the5-node matched-comment DATA
  // and3-node original-request DATA as well as every existing refusal label.
  @execution.add_execution_capacity(original_report, semantic)
}

///|
/// Seven ACTUAL native roles for a confirmed comment CREATE. The original
/// four-role method remains unchanged for existing callers. A matching Host
/// recipe must explicitly select this whole native value, distinguish logical
/// preparation/finalization and independent initial/cold read occurrences,
/// and add its own JS/grant/secret/transfer/retention overlap before invoking.
/// No JavaScript Option/tuple reconstruction, resource grant or admission.
/// Order: original4; confirmation request; confirmation reply; saved wire.
#export_name("installedStandardCreateConfirmedConstructionProfile")
pub fn installed_standard_create_confirmed_construction_profile() -> Array[
  (@execution.ExecutionCapacity, @source.ParseLimits?, @source.ParseLimits?),
]? {
  guard installed_standard_create_construction_profile() is Some(original) &&
    original.length() == 4 &&
    github_comment_confirmation_request_capacity() is Some(request) else {
    return None
  }
  let (report, response_input, response_output) = original[2]
  guard github_comment_confirmation_projection_capacity(report, false)
    is Some(response) &&
    github_comment_confirmation_projection_capacity(report, true) is Some(saved) else {
    return None
  }
  let (_, old_wire) = github_comment_request_wire_bounds(true)
  let delta = Int64::max(
    0L,
    @catalog.comment_confirmation_query.length().to_int64() -
    @catalog.comment_subject_query.length().to_int64(),
  )
  let request_output : @source.ParseLimits = {
    max_input_bytes: (3L * (old_wire + delta)).to_int(),
    max_nodes: 2,
    max_depth: 1,
  }
  let saved_input : @source.ParseLimits = {
    max_input_bytes: github_comment_http_request_bytes,
    max_nodes: github_comment_page_limits.max_nodes,
    max_depth: github_comment_page_limits.max_depth,
  }
  Some([
    original[0],
    original[1],
    original[2],
    original[3],
    (request, None, Some(request_output)),
    (response, response_input, response_output),
    (saved, Some(saved_input), response_output),
  ])
}
