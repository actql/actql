///|
fn bounded_events_flat_rows(rows : @carrier.Knowledge) -> Bool {
  if !@carrier.all_fields_required(rows) {
    return false
  }
  for index in 0..<@carrier.field_count(rows) {
    guard @carrier.field_at(rows, index).bind(field => field.contract)
      is Some(contract) else {
      return false
    }
    match contract.shape {
      @contract.Number | @contract.Boolean | @contract.Text(_) => ()
      _ => return false
    }
  }
  true
}

///|
/// The exact three-step numeric-clock watermark pipeline uses stepped record
/// append and measuring/hash writers. It never constructs the generic full
/// canonical input-measurement body. Preserve every other generic input,
/// output, measurement-node, fragment, metadata, frame and depth allowance.
/// The caller independently adds BOTH actual record-storage generations.
pub fn generated_bounded_events_projection_capacity(
  generated : GeneratedSequence,
  limits : SequenceExecutionLimits,
  measurement : FixedInputGuardMeasureLimits,
) -> ExecutionCapacity? {
  guard generated_sequence_step_count(generated) == 3 &&
    generated_sequence_step_index_at(generated, 0) == Some(0) &&
    generated_sequence_step_index_at(generated, 1) == Some(1) &&
    generated_sequence_step_index_at(generated, 2) == Some(2) &&
    generated_sequence_step_at(generated, 0) is Some(@lower.EventStep(first)) &&
    generated_sequence_step_at(generated, 1) is Some(@lower.EventStep(second)) &&
    generated_sequence_step_at(generated, 2)
    is Some(@lower.CarrierProjectionStep(last)) &&
    @lower.event_output_carrier(first) is @carrier.EventValue(first_events) &&
    @lower.event_output_carrier(second) is @carrier.EventValue(second_events) &&
    @lower.carrier_projection_output_carrier(last) is @carrier.Relation(output) &&
    @carrier.event_clock_encoding(first_events) is @carrier.Milliseconds &&
    @carrier.event_clock_encoding(second_events) is @carrier.Milliseconds &&
    bounded_events_flat_rows(@carrier.event_records(first_events)) &&
    bounded_events_flat_rows(@carrier.event_records(second_events)) &&
    bounded_events_flat_rows(output) else {
    return None
  }
  let prepared = @lower.bound_preparation(generated_sequence_owner(generated))
  guard @lower.node_at(prepared, 0) is Some(input_node) &&
    @lower.operation(input_node) == "BRIDGE.rows.to_events" &&
    @lower.node_input_count(input_node) == 1 &&
    @lower.node_input_target(input_node, 0).bind(target => {
      @lower.preparation_carrier_at(prepared, target)
    })
    is Some(@carrier.Relation(input)) &&
    bounded_events_flat_rows(input) &&
    @lower.node_at(prepared, 1) is Some(watermark) &&
    @lower.operation(watermark) == "TEA.watermark.label" &&
    @lower.node_input_count(watermark) == 1 &&
    @lower.node_input_target(watermark, 0) == Some(@pipeline.Step(0)) &&
    @lower.node_at(prepared, 2) is Some(project) &&
    @lower.operation(project) == "BRIDGE.events.to_rows" &&
    @lower.node_input_count(project) == 1 &&
    @lower.node_input_target(project, 0) == Some(@pipeline.Step(1)) else {
    return None
  }
  guard generated_sequence_capacity_with_roots(
      generated,
      limits,
      measurement,
      limits.rows.retained_entries.to_int64() +
      limits.rows.metadata_entries.to_int64(),
      limits.rows.metadata_entries.to_int64(),
      false,
      bounded_measurement=true,
    )
    is Some(base) &&
    // Only the absent body is removed; keep the old measurement-node packet.
    execution_capacity_inventory_add(
      base.execution_bytes,
      ValueNodeSlots,
      measurement.max_nodes.to_int64(),
      1,
    )
    is Some(execution) else {
    return None
  }
  execution_capacity(
    base.retained_bytes,
    Int64::max(base.retained_bytes, execution),
  )
}
