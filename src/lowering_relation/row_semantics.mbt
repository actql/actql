///|
/// Read-only projection semantics. Its checked owner stays private; consumers
/// cannot manufacture a projection or discover frontend construction history.
struct PreparedProjection {
  checked : @relation.CheckedOperation
}

///|
/// Lower an already checked projection without granting execution authority.
pub fn prepare_projection(
  checked : @relation.CheckedOperation,
) -> PreparedProjection? {
  if @relation.operation(checked) == @relation.Select {
    Some({ checked, })
  } else {
    None
  }
}

///|
pub fn projection_output_schema(view : PreparedProjection) -> @schema.Schema {
  @relation.output_schema(view.checked)
}

///|
pub fn projection_field_count(view : PreparedProjection) -> Int {
  @schema.field_count(@relation.output_schema(view.checked))
}

///|
pub fn projection_field_at(
  view : PreparedProjection,
  index : Int,
) -> @relation.ProjectionField? {
  @relation.projection_field_at(view.checked, index)
}

///|
/// Defensive copy. Callers charge projection_field_count before requesting it.
pub fn projection_fields(
  view : PreparedProjection,
) -> Array[@relation.ProjectionField] {
  @relation.projection(view.checked)
}

///|
/// Indexed immutable view for bounded consumers; no projection-array copy.
pub fn projection_field_at(
  view : PreparedProjection,
  index : Int,
) -> @relation.ProjectionField? {
  @relation.projection_field_at(view.checked, index)
}

///|
pub fn preparation_input_projection(
  prepared : Prepared,
  index : Int,
) -> PreparedProjection? {
  @pipeline.input_producer(prepared.owner, index)
  .bind(@pipeline.producer_projection)
  .map(checked => { checked, })
}

///|
pub fn kernel_distinct_projection(
  kernel : PreparedKernel,
) -> PreparedProjection? {
  if kernel.body is DistinctRows &&
    kernel.owner.prepared.nodes[kernel.step_index].projection_id is Some(_) {
    Some({ checked: kernel.checked, })
  } else {
    None
  }
}

///|
/// Allocation-free discriminants of KernelBody, not frontend operation names.
pub fn kernel_is_sort(kernel : PreparedKernel) -> Bool {
  kernel.body is StableSort(_)
}

///|
pub fn kernel_is_dedupe(kernel : PreparedKernel) -> Bool {
  kernel.body is DedupeRows
}

///|
pub fn kernel_is_distinct(kernel : PreparedKernel) -> Bool {
  kernel.body is DistinctRows
}

///|
/// Bound lag navigation view. The complete order remains owned by preparation.
pub fn kernel_lag(
  kernel : PreparedKernel,
) -> (@schema.FieldName, String, Int64)? {
  guard kernel.body is Lag(offset, _) &&
    @relation.lag_navigation(kernel.checked) is Some((field, output, _)) else {
    return None
  }
  Some((field.field, output, offset))
}

///|
/// Bound watermark semantics. Prefix order remains owned by the threshold and
/// cannot be supplied independently by an execution backend.
pub fn kernel_watermark(
  kernel : PreparedKernel,
) -> (@schema.FieldName, Bool, @relation.LatePolicy, PreparedWatermarkThreshold)? {
  match kernel.body {
    Watermark(time, timestamp, policy, threshold) =>
      Some((time, timestamp, policy, threshold))
    _ => None
  }
}

///|
/// The exact checked input sequence used by prefix watermark progression.
pub fn watermark_input_order(
  threshold : PreparedWatermarkThreshold,
) -> @pipeline.LogicalOrder? {
  match threshold {
    PrefixWatermark(_, order) => Some(order)
    FixedWatermark(_) => None
  }
}

///|
/// Fixed threshold or prefix skew in milliseconds.
pub fn watermark_threshold_value(
  threshold : PreparedWatermarkThreshold,
) -> Double {
  match threshold {
    FixedWatermark(value) => value
    PrefixWatermark(value, _) => value.to_double()
  }
}

///|
/// True only for the running-prefix threshold law.
pub fn watermark_is_prefix(threshold : PreparedWatermarkThreshold) -> Bool {
  threshold is PrefixWatermark(_, _)
}

///|
/// Allocation-free count view for both global and partitioned top-k kernels.
pub fn kernel_top_k_count(kernel : PreparedKernel) -> Int64? {
  match kernel.body {
    TopK(count, _) | PartitionedTopK(count, _) => Some(count)
    _ => None
  }
}

///|
pub fn kernel_is_partitioned_top_k(kernel : PreparedKernel) -> Bool {
  kernel.body is PartitionedTopK(_, _)
}

///|
pub fn kernel_unnest(
  kernel : PreparedKernel,
) -> (@schema.FieldName, String, String?, Bool, Int64?)? {
  match kernel.body {
    Unnest(column, element, index, outer, max_items) =>
      Some((column, element, index, outer, max_items))
    _ => None
  }
}

///|
pub fn kernel_unpivot_column_count(kernel : PreparedKernel) -> Int {
  match kernel.body {
    Unpivot(columns, _, _, _) => columns.length()
    _ => 0
  }
}

///|
pub fn kernel_unpivot_column_at(
  kernel : PreparedKernel,
  index : Int,
) -> @schema.FieldName? {
  match kernel.body {
    Unpivot(columns, _, _, _) => columns.get(index)
    _ => None
  }
}

///|
pub fn kernel_unpivot_keep_count(kernel : PreparedKernel) -> Int {
  match kernel.body {
    Unpivot(_, keep, _, _) => keep.length()
    _ => 0
  }
}

///|
pub fn kernel_unpivot_keep_at(
  kernel : PreparedKernel,
  index : Int,
) -> @schema.FieldName? {
  match kernel.body {
    Unpivot(_, keep, _, _) => keep.get(index)
    _ => None
  }
}

///|
pub fn kernel_unpivot_outputs(kernel : PreparedKernel) -> (String, String)? {
  match kernel.body {
    Unpivot(_, _, name_column, value_column) =>
      Some((name_column, value_column))
    _ => None
  }
}

///|
pub fn kernel_is_projection(kernel : PreparedKernel) -> Bool {
  kernel.body is Select(_)
}

///|
pub fn kernel_input_schema(kernel : PreparedKernel) -> @schema.Schema {
  let node = kernel.owner.prepared.nodes[kernel.step_index]
  preparation_schema_at(kernel.owner.prepared, node.input_targets[0]).unwrap()
}

///|
pub fn kernel_output_schema(kernel : PreparedKernel) -> @schema.Schema {
  kernel.owner.prepared.nodes[kernel.step_index].output_schema.unwrap()
}

///|
pub fn ordered_binding_count(kernel : PreparedKernel) -> Int {
  match kernel.body {
    OrderedBindings(bindings) => bindings.length()
    _ => 0
  }
}

///|
/// Same bounded occurrences used by the canonical dedupe emitter. No key or
/// representative-order array is copied, normalized, or inferred by a backend.
pub fn kernel_dedupe_key_count(kernel : PreparedKernel) -> Int {
  if kernel.body is DedupeRows {
    @relation.dedupe_key_count(kernel.checked)
  } else {
    0
  }
}

///|
pub fn kernel_dedupe_key_at(
  kernel : PreparedKernel,
  index : Int,
) -> @schema.FieldName? {
  if kernel.body is DedupeRows {
    @relation.dedupe_key_at(kernel.checked, index).map(key => key.field)
  } else {
    None
  }
}

///|
pub fn kernel_dedupe_order_count(kernel : PreparedKernel) -> Int {
  if kernel.body is DedupeRows {
    @relation.dedupe_order_count(kernel.checked)
  } else {
    0
  }
}

///|
/// (field, descending, nulls first). Dedupe keeps the first representative and
/// fails on a top tie; these are the existing REL.dedupeRows laws.
pub fn kernel_dedupe_order_at(
  kernel : PreparedKernel,
  index : Int,
) -> (@schema.FieldName, Bool, Bool)? {
  if kernel.body is DedupeRows {
    @relation.dedupe_order_at(kernel.checked, index).map(term => {
      (term.field, term.direction is Desc, term.nulls is First)
    })
  } else {
    None
  }
}
