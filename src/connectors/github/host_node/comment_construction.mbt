///|
// Bound the EXISTING two native stringify calls, not the later HTTP quota.
// The fixed GraphQL documents contain no JSON escape characters. Empty value
// slots below include their quotes; only original subject/body content varies.
// A control character contributes six units to the inner body and seven to
// its outer String export. A non-BMP body scalar contributes two, not twelve:
// the original body limit counts scalars, whereas the subject limit counts
// UTF16 units. Seven remains a bound for either original domain.
fn github_comment_request_wire_bounds(subject_check : Bool) -> (Int64, Int64) {
  let (fixed, query, characters) = if subject_check {
    (
      "{\"query\":\"\",\"variables\":{\"id\":\"\"}}", @catalog.comment_subject_query,
      0L,
    )
  } else {
    (
      "{\"query\":\"\",\"variables\":{\"subjectId\":\"\",\"body\":\"\"}}",
      @catalog.add_comment_mutation,
      @catalog.max_comment_characters.to_int64(),
    )
  }
  let mut quotes = 0L
  for index in 0..<fixed.length() {
    if fixed[index] == '"' {
      quotes += 1L
    }
  }
  let fixed_units = fixed.length().to_int64() + query.length().to_int64()
  let content = @catalog.max_comment_subject_units.to_int64() + characters
  (
    fixed_units + 6L * content,
    "{\"body\":\"\"}".length().to_int64() + fixed_units + quotes + 7L * content,
  )
}

///|
// A pinned JS Json::stringify owns a builder, stack and empty indent cache.
// Each live Object frame has its original Map Iter, closure, two captured
// cells and old/new size-hint Some:7H6R7W including the frame. Its current
// Some(value), Some(entry), entry tuple, builder and old/new/scratch Strings
// add8H5R2W. Co-count the two calls instead of claiming return/GC retirement.
// Literal Map pair arrays/tuples are included even where compilation elides
// them. The common shape owner expands their Array/Map backing, not this file.
fn github_comment_request_construction_inventory(
  subject_check : Bool,
) -> @execution.PreparationRepresentationUnits? {
  let fields = if subject_check { 4L } else { 5L }
  let json_nodes = fields + 2L
  let (iterator_h, iterator_r, iterator_w) = if subject_check {
    (0L, 0L, 0L)
  } else {
    // Original body scalar counter: Iter, closure, captured index and the
    // current Some(Char). The original body String is borrowed, never copied.
    (4L, 4L, 3L)
  }
  // Inner object depth2 plus outer depth1. The original Ok(String) and failed
  // Err carrier are both covered; refusal text is shared module DATA.
  let depth = 2L + 1L
  guard @shape.collection_construction_extent({
      records: json_nodes + 2L + iterator_h + 2L * 8L + 7L * depth + fields,
      record_references: json_nodes +
      1L +
      iterator_r +
      2L * 5L +
      6L * depth +
      2L * fields,
      record_words: json_nodes + 2L + iterator_w + 2L * 2L + 7L * depth,
      reference_arrays: 2L * 2L + 3L,
      reference_items: depth + fields,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 3L,
      map_entries: fields,
    })
    is Some(controls) else {
    return None
  }
  let (inner, outer) = github_comment_request_wire_bounds(subject_check)
  Some({
    record_headers: controls.record_headers,
    reference_slots: controls.reference_slots,
    scalar_words: controls.scalar_words,
    // JS concatenation's old/new value at each builder plus each call's
    // current Char/hex scratch (<=4 units). Input, documents and fixed keys
    // remain at their original owner. Neither call encodes UTF8 Bytes.
    owned_utf16_units: 2L * inner + 2L * outer + 8L,
    owned_wire_bytes: 0L,
  })
}

///|
fn github_comment_request_capacity(
  subject_check : Bool,
) -> @execution.ExecutionCapacity? {
  guard github_comment_request_construction_inventory(subject_check)
    is Some(retained) else {
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
/// Native request/export constructor DATA, held until its output retirement.
/// The Host separately backs quotation, original input, JS decode/map/hash,
/// saved request, HTTP/secret/response/failed-child overlap BEFORE invocation.
/// This neither constructs a request nor issues capacity, attempts or grants.
#export_name("githubAddCommentRequestConstructionCapacity")
pub fn github_add_comment_request_construction_capacity() -> @execution.ExecutionCapacity? {
  github_comment_request_capacity(false)
}

///|
/// Separate original subject-check constructor; same exclusions and lifetime.
#export_name("githubCommentSubjectRequestConstructionCapacity")
pub fn github_comment_subject_request_construction_capacity() -> @execution.ExecutionCapacity? {
  github_comment_request_capacity(true)
}
