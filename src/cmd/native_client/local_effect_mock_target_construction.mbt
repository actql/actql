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
// SAME already-owned selector/changes/before and installation Strings. The
// Canonical Owner supplies the NFC expansion bound; six bytes per output unit
// cover escaping. Keep raw inputs beside the bounded original writer too.
// These are construction bounds only; all old parser/writer guards remain.
fn native_mock_effect_request_input_capacity(
  provider : @row_file.NativeRelationFilePreparedProvider,
  page : @row_host.RowPageLimits,
  writable_fields : Int,
  received : Int,
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
  guard @local_values.installed_json_effect_request_construction_capacity(
      empty,
      bytes,
      bytes,
      Int::min(
        bytes,
        Int::max(local_project_mock_relation_wire_depth, page.max_depth),
      ),
    )
    is Some(json) &&
    @row_file.native_relation_file_target_read_io_capacity(
      provider,
      writable_fields,
      response_bytes=Some(received),
    )
    is Some(document) &&
    // check_update can retain each field's replacement plus the final whole
    // original document. Its independent old page guard bounds every copy.
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
    @execution.add_execution_capacity(json, document) is Some(complete) else {
    return None
  }
  @execution.add_execution_capacity(complete, replacements)
}
