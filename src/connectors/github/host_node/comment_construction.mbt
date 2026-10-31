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
// The native constructor owns a closed literal forest: three Objects and
// three subject-check/four mutation String nodes, at maximum object depth2.
// Use the EXISTING common fixed-control envelope for each of the TWO actual
// stringify calls. This conservatively co-counts the whole retained forest at
// both calls; it is not a new per-provider Iter/closure/slot price table.
fn github_comment_request_construction_inventory(
  subject_check : Bool,
) -> @execution.PreparationRepresentationUnits? {
  let json_nodes = if subject_check { 6 } else { 7 }
  guard @encode.text_writer_construction_inventory(0, json_nodes, 2)
    is Some(controls) else {
    return None
  }
  let stringify_calls = 2L
  let (inner, outer) = github_comment_request_wire_bounds(subject_check)
  Some({
    record_headers: stringify_calls * controls.record_headers,
    reference_slots: stringify_calls * controls.reference_slots,
    scalar_words: stringify_calls * controls.scalar_words,
    // Actual pinned JS String domains remain Provider facts: old/new value
    // of each builder and its current Char/hex scratch (<=4 units). Inputs,
    // fixed documents and keys are borrowed. Neither call encodes UTF8 Bytes.
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
