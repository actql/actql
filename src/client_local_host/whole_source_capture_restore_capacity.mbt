///|
/// Actual saved-body and checked-schema demand for the existing Whole Source
/// receiver. Policy remains an admission predicate, never a startup allocation.
fn whole_source_capture_restoration_capacity(
  capacity : ClientInstalledWholeSourceCapacity,
  rows : Array[String],
) -> @execution.ExecutionCapacity? {
  let policy = @row_source_host.row_input_acquisition_limits(
    capacity.acquisition,
  )
  guard @row_source_host.row_input_capture_schema_geometry(capacity.acquisition)
    is Some((columns, schema_bytes, schema_nodes, schema_depth)) &&
    source_capture_restoration_capacity(
      "",
      rows,
      None,
      input_policy=policy,
      input_columns=columns,
    )
    is Some(body) else {
    return None
  }
  let count = rows.length().to_int64()
  let width = columns.to_int64()
  guard @execution.checked_preparation_add_product(0L, count, width)
    is Some(cells) &&
    @execution.checked_preparation_add_product(8L * count, cells, 8L)
    is Some(items) &&
    @execution.checked_preparation_add_product(items, width, 8L) is Some(items) &&
    @execution.preparation_array_representation(4L + 4L * count, items, true)
    is Some(arrays) else {
    return None
  }
  // AdmittedInput/buffer/budget, CapturedRows/usage, SuppliedRead, restored
  // owner, verifier/port and closures/refs/typed carriers. Co-count transient
  // variants under the same fixed constructor packet; values stay in body.
  let controls : @execution.PreparationRepresentationUnits = {
    record_headers: 32L,
    reference_slots: 96L,
    scalar_words: 96L,
    owned_utf16_units: 2L * 71L,
    owned_wire_bytes: 0L,
  }
  // One row's checked-cell wrappers and presence/append variants overlap;
  // width is the actual checked schema, including omitted optional fields.
  let cells_work : @execution.PreparationRepresentationUnits = {
    record_headers: 8L * width,
    reference_slots: 24L * width,
    scalar_words: 8L * width,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  guard @encode.hash_writer_construction_inventory(schema_nodes, schema_depth)
    is Some(hash) &&
    @encode.text_writer_construction_inventory(
      schema_bytes,
      Int::max(1, schema_nodes),
      schema_depth,
    )
    is Some(text) else {
    return None
  }
  // The schema identity's two sinks, canonical field names and observed wire
  // live during readmission. No schema identity is held after capture returns.
  let schema_work : @execution.PreparationRepresentationUnits = {
    record_headers: hash.record_headers + text.record_headers,
    reference_slots: hash.reference_slots + text.reference_slots,
    scalar_words: hash.scalar_words + text.scalar_words,
    owned_utf16_units: hash.owned_utf16_units + text.owned_utf16_units,
    owned_wire_bytes: hash.owned_wire_bytes,
  }
  guard @execution.compose_preparation_representation([controls, arrays])
    is Some(retained) &&
    @execution.compose_preparation_representation([
      controls, cells_work, schema_work,
    ])
    is Some(workspace) &&
    @execution.preparation_execution_capacity({
      retained,
      workspace,
      retained_nodes: 0L,
      workspace_nodes: 0L,
      retained_bytes: 0L,
      workspace_bytes: 0L,
    })
    is Some(input) &&
    @execution.checked_preparation_add_product(
      @execution.execution_capacity_retained_bytes(body),
      @execution.execution_capacity_retained_bytes(input),
      1L,
    )
    is Some(retained) &&
    @execution.checked_preparation_add_product(
      @execution.execution_capacity_execution_bytes(body),
      @execution.execution_capacity_execution_bytes(input),
      1L,
    )
    is Some(execution) else {
    return None
  }
  // Identity/quote controls and reconstruction run sequentially on this Ledger.
  @execution.execution_capacity(
    retained,
    Int64::max(execution, source_capture_restore_quote_bytes),
  )
}
