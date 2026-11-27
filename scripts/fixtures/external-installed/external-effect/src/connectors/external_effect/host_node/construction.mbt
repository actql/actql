// Native quantities for this fixture's EXISTING JSON constructors. The
// standard Host owns capture, HTTP, controls, claims and retirement.

///|
let external_effect_key_units : Int = 64

///|
let external_effect_note_units : Int = 256

///|
let external_effect_request_bytes : Int = 4096

///|
let external_effect_response_bytes : Int = 4096

///|
let external_effect_response_nodes : Int = 16

///|
let external_effect_response_depth : Int = 3

///|
#export_name("installedStandardCreateHttpLimits")
pub fn installed_standard_create_http_limits() -> Array[Int] {
  [
    external_effect_request_bytes, external_effect_response_bytes, external_effect_response_nodes,
    external_effect_response_depth,
  ]
}

///|
fn external_effect_request_wire_bounds() -> (Int64, Int64) {
  let fixed : Json = { "key": "", "note": "" }
  let wire = fixed.stringify()
  let mut quotes = 0L
  for index in 0..<wire.length() {
    if wire[index] == '"' {
      quotes += 1L
    }
  }
  let units = (external_effect_key_units + external_effect_note_units).to_int64()
  // Six units inside the request; seven after the outer body String escapes
  // the same original backslash. Neither bound is a later HTTP allowance.
  (
    wire.length().to_int64() + 6L * units,
    "{\"body\":\"\"}".length().to_int64() +
    wire.length().to_int64() +
    quotes +
    7L * units,
  )
}

///|
fn external_effect_request_capacity() -> @execution.ExecutionCapacity? {
  // Inner Object+two Strings and outer Object+body String. Conservatively
  // retain the whole closed forest at both existing stringify calls.
  guard @encode.text_writer_construction_inventory(0, 5, 2) is Some(writer) else {
    return None
  }
  let (inner, outer) = external_effect_request_wire_bounds()
  @execution.preparation_execution_capacity({
    retained: {
      record_headers: 2L * writer.record_headers,
      reference_slots: 2L * writer.reference_slots,
      scalar_words: 2L * writer.scalar_words,
      owned_utf16_units: 2L * inner + 2L * outer + 8L,
      owned_wire_bytes: 0L,
    },
    workspace: {
      record_headers: 0L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    retained_nodes: 5L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}

///|
#export_name("installedStandardCreateConstructionProfile")
pub fn installed_standard_create_construction_profile() -> Array[
  (@execution.ExecutionCapacity, @source.ParseLimits?, @source.ParseLimits?),
]? {
  guard external_effect_request_capacity() is Some(request) else { return None }
  let (_, exported) = external_effect_request_wire_bounds()
  let request_export : @source.ParseLimits = {
    max_input_bytes: (3L * exported).to_int(),
    max_nodes: 2,
    max_depth: 1,
  }
  // Exact fixed alternatives plus the sole variable returned id. The actual
  // formatter functions below also emit these original protocol spellings.
  let fixed = Int::max(
    external_effect_success("").stringify().length(),
    Int::max(
      external_effect_failure().stringify().length(),
      external_effect_unknown().stringify().length(),
    ),
  )
  let response : @source.ParseLimits = {
    max_input_bytes: 3 * fixed + 6 * external_effect_key_units,
    max_nodes: 8,
    max_depth: 3,
  }
  guard @encode.text_writer_construction_inventory(
      response.max_input_bytes,
      response.max_nodes,
      response.max_depth,
    )
    is Some(writer) &&
    @execution.preparation_execution_capacity({
      retained: {
        record_headers: writer.record_headers,
        reference_slots: writer.reference_slots,
        scalar_words: writer.scalar_words,
        owned_utf16_units: writer.owned_utf16_units,
        owned_wire_bytes: 0L,
      },
      workspace: {
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      retained_nodes: 8L,
      workspace_nodes: 0L,
      retained_bytes: 0L,
      workspace_bytes: 0L,
    })
    is Some(projected) else {
    return None
  }
  let input : @source.ParseLimits = {
    max_input_bytes: external_effect_response_bytes,
    max_nodes: external_effect_response_nodes,
    max_depth: external_effect_response_depth,
  }
  // The write-only composer does not select subject-read positions. Those
  // compatibility positions borrow the SAME immutable quantities, not a new
  // reader, physical occurrence, capacity grant or fabricated successful read.
  Some([
    (request, None, Some(request_export)),
    (request, None, Some(request_export)),
    (projected, Some(input), Some(response)),
    (projected, Some(input), Some(response)),
  ])
}

///|
#export_name("externalEffectDriverConstructionCapacity")
pub fn external_effect_driver_construction_capacity(
  metadata_units : Int64,
) -> @execution.ExecutionCapacity? {
  if metadata_units < 0L || metadata_units > 2147483647L {
    return None
  }
  // Only this provider's variable footprint DATA. The bound initializer and
  // standard operation composer own their existing shared fixed/control
  // overhead; no JS closure or record census is priced by this provider.
  let fixed : Json = { "origin": "", "namespace": "" }
  let wire = fixed.stringify().length().to_int64() + 6L * metadata_units
  @execution.preparation_execution_capacity({
    retained: {
      record_headers: 0L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: 2L * wire,
      owned_wire_bytes: 3L * wire,
    },
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
