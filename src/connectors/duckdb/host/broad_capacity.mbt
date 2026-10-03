///|
/// Capacity of the selected Broad configuration, including the original
/// Client/Local residual. This does not select or execute another acquisition.
pub fn configured_broad_capacity(
  setup : BroadHostConfiguration,
) -> NativeCapacity? {
  let limits = setup.limits
  let guards = @planning.query_requirement_guards(setup.requirement)
  let query = @planning.query_material_owner(
    @planning.query_requirement_material(setup.requirement),
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
fn broad_capacity(
  l : BroadHostLimits,
  residual : @execution.ExecutionCapacity,
) -> NativeCapacity? {
  let c = l.completion
  let mut retained = @execution.execution_capacity_retained_bytes(residual)
  let mut scratch = @execution.execution_capacity_execution_bytes(residual)
  // The scan and guarded residual completion coexist until the exact source
  // capture closes. Include schema and every retained evidence document too.
  for
    n in [
      l.physical.max_rows,
      l.physical.max_cells,
      l.physical.max_nodes,
      l.retention.max_nodes,
      l.transport.max_columns,
      l.transport.max_columns,
      l.transport.max_columns,
      c.records.max_nodes,
      c.records.max_nodes,
      c.records.max_nodes,
      c.capture.max_nodes,
    ] {
    if n < 0 || n.to_int64() * 256L > 9223372036854775807L - retained {
      return None
    }
    retained += n.to_int64() * 256L
  }
  for
    n in [
      l.physical.max_text_bytes,
      l.retention.max_text_bytes,
      c.retention.retained_wire_bytes,
      c.records.max_bytes,
      c.records.max_bytes,
      c.records.max_bytes,
      c.capture.max_bytes,
    ] {
    if n < 0 || n.to_int64() * 8L > 9223372036854775807L - retained {
      return None
    }
    retained += n.to_int64() * 8L
  }
  for
    n in [
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
    ] {
    if n < 0 || n.to_int64() * 256L > 9223372036854775807L - scratch {
      return None
    }
    scratch += n.to_int64() * 256L
  }
  for
    n in [
      l.transport.max_bytes,
      l.transport.max_text_bytes,
      c.guards.max_bytes,
      c.retention.measurement.max_bytes,
    ] {
    if n < 0 || n.to_int64() * 8L > 9223372036854775807L - scratch {
      return None
    }
    scratch += n.to_int64() * 8L
  }
  Some({ retained_bytes: retained, execution_bytes: scratch, })
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
