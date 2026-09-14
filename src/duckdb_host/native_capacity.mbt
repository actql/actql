///|
pub struct NativeCapacity {
  retained_bytes : Int64
  execution_bytes : Int64
}

///|
/// Declared bounded receiver/receipt capacity, not allocator usage or RSS.
/// Both validation and native batches remain represented after source cleanup.
pub fn configured_native_capacity(
  setup : NativeHostConfiguration,
) -> NativeCapacity? {
  native_capacity(setup.limits)
}

///|
fn native_capacity(l : NativeHostLimits) -> NativeCapacity? {
  let c = l.completion
  let mut retained = 0L
  let mut scratch = 0L
  for
    n in [
      l.physical.max_rows,
      l.physical.max_cells,
      l.physical.max_nodes,
      l.physical.max_rows,
      l.physical.max_cells,
      l.physical.max_nodes,
      l.retention.max_nodes,
      l.output_rows,
      l.output_entries,
      c.records.max_nodes,
      c.records.max_nodes,
      c.records.max_nodes,
      c.capture.max_nodes,
    ] {
    if n < 0 {
      return None
    }
    retained += 256L * n.to_int64()
  }
  for
    n in [
      l.physical.max_text_bytes,
      l.physical.max_text_bytes,
      l.retention.max_text_bytes,
      l.output_name_bytes,
      c.max_retained_wire_bytes,
      c.records.max_bytes,
      c.records.max_bytes,
      c.records.max_bytes,
      c.capture.max_bytes,
    ] {
    if n < 0 {
      return None
    }
    retained += 8L * n.to_int64()
  }
  for
    n in [
      l.transport.max_nodes,
      l.transport.max_rows,
      l.transport.max_columns,
      l.measurement.max_nodes,
      l.measurement.max_depth,
      c.demand.max_nodes,
      c.demand.max_depth,
      c.receipts.max_nodes,
      c.receipts.max_depth,
      c.receipts.max_columns,
      c.records.max_depth,
      c.records.max_fields,
      c.records.max_parameters,
      c.capture.max_depth,
      l.retention.max_depth,
    ] {
    if n < 0 {
      return None
    }
    scratch += 256L * n.to_int64()
  }
  for
    n in [
      l.transport.max_bytes,
      l.transport.max_text_bytes,
      l.measurement.max_bytes,
      c.demand.max_bytes,
      c.receipts.max_bytes,
    ] {
    if n < 0 {
      return None
    }
    scratch += 8L * n.to_int64()
  }
  Some({ retained_bytes: retained, execution_bytes: scratch, })
}
