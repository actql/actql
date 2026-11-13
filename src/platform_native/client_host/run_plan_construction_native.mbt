///|
// Variable projection construction after separately funded measurement. The
// original Read and fixed constructor basis remain with the caller. Invoke its
// metadata reservation once for this returned view; do not refill on progress.
fn native_static_plan_projection_working(
  geometry : @host.ClientStaticPlanViewConstruction,
  step_key : @local.ClientStaticPlanCodecLayout,
  port_key : @local.ClientStaticPlanCodecLayout,
  map : @local.ClientStaticPlanCodecLayout,
  view : @local.ClientStaticPlanCodecLayout,
  carrier : @local.ClientStaticPlanCodecLayout,
) -> (Int64, Int64, Int64)? {
  guard @local.client_static_plan_projection_layout(
      geometry, step_key, port_key, map, view, carrier,
    )
    is Some(layout) &&
    native_static_plan_variable_raw(
      layout.string_utf16_units,
      layout.builder_utf16_bound,
      layout.wire_bytes,
      layout.reference_array_slots,
      layout.map_bucket_slots,
      layout.scalar_array_items,
    )
    is Some(raw) else {
    return None
  }
  Some((layout.retained_cost, layout.execution_cost, raw))
}

///|
// Pinned Native contiguous constructor endpoints, not a conversion from the
// logical R/E tariff. Fixed object/closure/call controls remain with entry.
fn native_static_plan_variable_raw(
  units : Int64,
  builder_units : Int64,
  wire : Int64,
  references : Int64,
  buckets : Int64,
  scalar_items : Int64,
) -> Int64? {
  for value in [units, builder_units, wire, references, buckets, scalar_items] {
    if value < 0L || value > 2147483647L {
      return None
    }
  }
  let (header, unit, terminator, array_header, pointer) = @bootstrap.native_managed_value_layout()
  if header <= 0L ||
    unit != 2L ||
    terminator != unit ||
    array_header <= 0L ||
    pointer <= 0L {
    return None
  }
  let mut capacity = 1L
  while capacity < builder_units {
    capacity *= 2L
  }
  Some(
    Int64::max(
      header + (units + 1L) * unit,
      Int64::max(
        header + (capacity + 1L) * unit,
        Int64::max(
          header + wire,
          Int64::max(
            array_header + references * pointer,
            Int64::max(
              array_header + buckets * pointer,
              array_header + scalar_items * 4L,
            ),
          ),
        ),
      ),
    ),
  )
}
