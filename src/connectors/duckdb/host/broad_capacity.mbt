///|
/// Capacity of the selected Broad configuration, including the original
/// Client/Local residual. This does not select or execute another acquisition.
pub fn configured_broad_capacity(
  setup : BroadHostConfiguration,
) -> NativeCapacity? {
  prepared_broad_capacity(setup.requirement, setup.limits)
}

///|
/// Size Broad's original bounded residual without selecting or executing it.
/// The checked requirement and the eventual Host configuration share this
/// capacity calculation; a pending read needs no fabricated AcquisitionChoice.
pub fn prepared_broad_capacity(
  requirement : @planning.QueryRequirement,
  limits : BroadHostLimits,
) -> NativeCapacity? {
  let guards = @planning.query_requirement_guards(requirement)
  let query = @planning.query_material_owner(
    @planning.query_requirement_material(requirement),
  )
  let measurement : @execution.FixedInputGuardMeasureLimits = {
    max_work: limits.completion.guards.max_work,
    max_bytes: limits.completion.guards.max_bytes,
    max_nodes: limits.completion.guards.max_nodes,
    max_depth: limits.completion.guards.max_depth,
  }
  let (sequence, measured) = match
    @execution.prepare_fixed_input_guard_roots(
      @query.query_generated_sequence(query),
      guards.max_value_bytes,
      true,
      measurement,
    ) {
    Ok(value) => value
    Err(_) => return None
  }
  guard @execution.generated_sequence_capacity(
      sequence,
      limits.completion.execution,
      measured,
    )
    is Some(residual) else {
    return None
  }
  broad_capacity(limits, residual)
}

///|
/// The same selected Broad attempt has two serial phases. Physical transport
/// retains its admitted scan, but cannot start residual/evidence construction
/// until its exact session owner confirms cleanup. Fund both peaks up front;
/// this quote does not release a resource or establish that confirmation.
pub fn configured_broad_physical_capacity(
  setup : BroadHostConfiguration,
  physical_execution : Int64,
) -> NativeCapacity? {
  guard configured_broad_capacity(setup) is Some(full) else { return None }
  broad_physical_capacity(setup.limits, full, physical_execution)
}

///|
fn broad_physical_capacity(
  limits : BroadHostLimits,
  full : NativeCapacity,
  physical_execution : Int64,
) -> NativeCapacity? {
  guard broad_receiving_retention(limits) is Some(scan) &&
    broad_receiving_scratch(limits) is Some(scratch) &&
    @execution.execution_capacity_inventory_bytes([
      { unit: QuotedBytes, count: physical_execution, copies: 1, },
      { unit: QuotedBytes, count: scan, copies: 1, },
      { unit: QuotedBytes, count: scratch, copies: 1, },
    ])
    is Some(receiving) else {
    return None
  }
  Some({
    retained_bytes: full.retained_bytes,
    execution_bytes: Int64::max(receiving, full.execution_bytes),
  })
}

///|
fn broad_capacity(
  l : BroadHostLimits,
  residual : @execution.ExecutionCapacity,
) -> NativeCapacity? {
  guard broad_receiving_retention(l) is Some(scan) &&
    broad_evidence_retention(l) is Some(evidence) &&
    broad_receiving_scratch(l) is Some(scratch) &&
    @execution.execution_capacity_inventory_bytes([
      {
        unit: QuotedBytes,
        count: @execution.execution_capacity_retained_bytes(residual),
        copies: 1,
      },
      { unit: QuotedBytes, count: scan, copies: 1, },
      { unit: QuotedBytes, count: evidence, copies: 1, },
    ])
    is Some(retained) &&
    @execution.execution_capacity_inventory_bytes([
      {
        unit: QuotedBytes,
        count: @execution.execution_capacity_execution_bytes(residual),
        copies: 1,
      },
      { unit: QuotedBytes, count: scratch, copies: 1, },
    ])
    is Some(execution) else {
    return None
  }
  Some({ retained_bytes: retained, execution_bytes: execution, })
}

///|
// Physical conversion and the owned scan coexist. Row containers and admitted
// immutable cell backing survive transport settlement; neither output aliasing
// nor a completed Promise permits omitting this original retained inventory.
fn broad_receiving_retention(l : BroadHostLimits) -> Int64? {
  broad_inventory_bytes(
    [
      l.physical.max_rows,
      l.physical.max_cells,
      l.physical.max_nodes,
      l.retention.max_nodes,
      l.transport.max_columns,
      l.transport.max_columns,
      l.transport.max_columns,
    ],
    [l.physical.max_text_bytes, l.retention.max_text_bytes],
  )
}

///|
// These documents and residual outputs are constructed only after the physical
// session settles. Their full retained allowance is still reserved at entry.
fn broad_evidence_retention(l : BroadHostLimits) -> Int64? {
  let c = l.completion
  broad_inventory_bytes(
    [
      c.records.max_nodes,
      c.records.max_nodes,
      c.records.max_nodes,
      c.capture.max_nodes,
    ],
    [
      c.retention.retained_wire_bytes,
      c.records.max_bytes,
      c.records.max_bytes,
      c.records.max_bytes,
      c.capture.max_bytes,
    ],
  )
}

///|
// Preserve every existing non-residual scratch term in BOTH phase peaks. Some
// are needed only later; retaining them here avoids an unproved early credit.
fn broad_receiving_scratch(l : BroadHostLimits) -> Int64? {
  let c = l.completion
  broad_inventory_bytes(
    [
      l.transport.max_nodes,
      l.transport.max_rows,
      l.transport.max_columns,
      c.guards.max_nodes,
      c.guards.max_depth,
      c.retention.measurement.max_nodes,
      c.retention.measurement.max_depth,
      c.retention.measurement.max_columns,
      c.records.max_depth,
      c.records.max_fields,
      c.records.max_parameters,
      c.capture.max_depth,
      l.retention.max_depth,
    ],
    [
      l.transport.max_bytes,
      l.transport.max_text_bytes,
      c.guards.max_bytes,
      c.retention.measurement.max_bytes,
    ],
  )
}

///|
// Domain occurrences stay here; conversions and checked arithmetic stay with
// the existing shared capacity owner. No local memory tariff or grant is added.
fn broad_inventory_bytes(nodes : Array[Int], text : Array[Int]) -> Int64? {
  let mut total = 0L
  for count in nodes {
    guard @execution.execution_capacity_inventory_add(
        total,
        ValueNodeSlots,
        count.to_int64(),
        1,
      )
      is Some(next) else {
      return None
    }
    total = next
  }
  for count in text {
    guard @execution.execution_capacity_inventory_add(
        total,
        DecodedTextBytes,
        count.to_int64(),
        1,
      )
      is Some(next) else {
      return None
    }
    total = next
  }
  Some(total)
}

///|
enum CaptureConfigurationOwner {
  Native(NativeHostConfiguration)
  Broad(BroadHostConfiguration)
}

///|
/// Retain the actual selected preparation for plural Host capacity admission.
/// Neither a numeric estimate nor an adapter-supplied capacity is an owner.
pub struct CaptureConfiguration {
  owner : CaptureConfigurationOwner
}

///|
pub fn native_capture_configuration(
  setup : NativeHostConfiguration,
) -> CaptureConfiguration {
  { owner: Native(setup), }
}

///|
pub fn broad_capture_configuration(
  setup : BroadHostConfiguration,
) -> CaptureConfiguration {
  { owner: Broad(setup), }
}

///|
pub fn configured_capture_capacity(
  setup : CaptureConfiguration,
) -> NativeCapacity? {
  match setup.owner {
    Native(value) => configured_native_capacity(value)
    Broad(value) => configured_broad_capacity(value)
  }
}

///|
/// Exact checked requirement retained by the selected configuration.
pub fn configured_capture_requirement(
  setup : CaptureConfiguration,
) -> @planning.QueryRequirement {
  match setup.owner {
    Native(value) => value.requirement
    Broad(value) => value.requirement
  }
}
