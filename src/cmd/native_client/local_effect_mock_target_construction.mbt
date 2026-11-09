///|
// Existing immutable implementation allowances; this is no Root/limit/grant.
fn native_mock_effect_capacity_envelope(
  left : @execution.ExecutionCapacity,
  right : @execution.ExecutionCapacity,
) -> @execution.ExecutionCapacity? {
  @execution.execution_capacity(
    Int64::max(
      @execution.execution_capacity_retained_bytes(left),
      @execution.execution_capacity_retained_bytes(right),
    ),
    Int64::max(
      @execution.execution_capacity_execution_bytes(left),
      @execution.execution_capacity_execution_bytes(right),
    ),
  )
}

///|
// SAME original owned Strings; no provider/document/transport is constructed
// by this pure JSON phase. The live Target has its own original reservation.
fn native_mock_effect_request_json_capacity(
  target : String,
  changes : String,
  before : String,
  binding : String,
  mapping : String,
  version : String,
) -> @execution.ExecutionCapacity? {
  let mut units = 0L
  for text in [target, changes, before, binding, mapping, version] {
    guard @execution.checked_preparation_add_product(
        units,
        text.length().to_int64(),
        1L,
      )
      is Some(next) else {
      return None
    }
    units = next
  }
  guard @canonical_value.nfc_lf_retained_output_units(units) is Some(normalized) &&
    @execution.checked_preparation_add_product(128L + units, normalized, 6L)
    is Some(wire_bound) &&
    @execution.checked_preparation_add_product(128L, units, 4L)
    is Some(raw_bound) else {
    return None
  }
  let bytes = Int64::max(
    raw_bound,
    Int64::min(local_project_mock_relation_wire_bytes.to_int64(), wire_bound),
  )
  if bytes > 2147483647L {
    return None
  }
  let bytes = Int::max(1, bytes.to_int())
  let empty = @execution.execution_capacity(0L, 0L).unwrap()
  // The original Native adapter normalizes through canonical.from_json.
  // Keep its existing normalizing/NFC peak, not the preserving-only quote.
  @local_values.installed_json_effect_response_construction_capacity(
    empty,
    bytes,
    bytes,
    Int::min(bytes, local_project_mock_relation_wire_depth),
  )
}

///|
// check_update borrows the SAME ready Target document/writer allowance; it
// creates no second Reader, receive buffer or document. Its temporary field
// replacements and returned whole-document Bytes are additional. They die
// before the final request JSON phase. Keep original parser/admission guards.
fn native_mock_effect_changes_input_capacity(
  page : @row_host.RowPageLimits,
  writable_fields : Int,
  changes : String,
  before : String,
  version : String,
) -> @execution.ExecutionCapacity? {
  if writable_fields < 1 || writable_fields > page.max_nodes {
    return None
  }
  guard native_mock_effect_request_json_capacity("", changes, "", "", "", "")
    is Some(json) &&
    @execution.execution_capacity_inventory(
      [
        {
          unit: QuotedBytes,
          count: page.max_bytes.to_int64(),
          copies: writable_fields + 1,
        },
      ],
      [],
      RetainedAlongsideExecution,
    )
    is Some(replacements) &&
    @execution.preparation_representation_cost({
      // Original input record H1/R4 + Some H1/R1/W1. The fixed
      // caller slot belongs to the same Plan controls_per_row for its lifetime.
      // Before/version transfer to this same request before Target retirement.
      record_headers: 2L,
      reference_slots: 5L,
      scalar_words: 1L,
      owned_utf16_units: before.length().to_int64() +
      version.length().to_int64(),
      owned_wire_bytes: 0L,
    })
    is Some(input) &&
    @execution.execution_capacity(input, input) is Some(input) &&
    @execution.add_execution_capacity(json, replacements) is Some(phase) else {
    return None
  }
  @execution.add_execution_capacity(phase, input)
}
