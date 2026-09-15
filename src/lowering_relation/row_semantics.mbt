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
/// Defensive copy. Callers charge projection_field_count before requesting it.
pub fn projection_fields(
  view : PreparedProjection,
) -> Array[@relation.ProjectionField] {
  @relation.projection(view.checked)
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
  kernel.owner.prepared.nodes[kernel.step_index].output_schema
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
