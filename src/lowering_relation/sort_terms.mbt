///|
/// Indexed read of the compiler-selected order, never an independent completion
/// rule. An empty authored sort has no resolution and has zero terms.
pub fn kernel_sort_term_count(kernel : PreparedKernel) -> Int {
  if kernel.body is Limit(_, _, _) {
    return take_completion(kernel.owner.prepared.owner, kernel.step_index)
      .map(@evidence.key_field_count)
      .unwrap_or(0)
  }
  guard kernel.body is StableSort(resolution) else { return 0 }
  @relation.sort_term_count(kernel.checked) +
  resolution
  .map(order => {
    match @pipeline.sort_order_strategy(order) {
      CandidateKey(c) => @pipeline.sort_completion_count(c)
      ExistingTotal(_) => 0
    }
  })
  .unwrap_or(0)
}

///|
/// (checked field, descending, nulls first). No complete order array is copied.
pub fn kernel_sort_term_at(
  kernel : PreparedKernel,
  index : Int,
) -> (@schema.FieldName, Bool, Bool)? {
  if kernel.body is Limit(_, _, _) {
    return take_completion(kernel.owner.prepared.owner, kernel.step_index).bind(key => {
        @evidence.key_field_at(key, index).map(field => {
          (field.name, false, false)
        })
      },
    )
  }
  guard kernel.body is StableSort(resolution) else { return None }
  if index < 0 {
    return None
  }
  let authored = @relation.sort_term_count(kernel.checked)
  if index < authored {
    let term = @relation.sort_term_at(kernel.checked, index).unwrap()
    return Some((term.field, term.direction is Desc, term.nulls is First))
  }
  resolution.bind(order => {
    match @pipeline.sort_order_strategy(order) {
      CandidateKey(c) =>
        @pipeline.sort_completion_field(c, index - authored).map(field => {
          (field, false, false)
        })
      ExistingTotal(_) => None
    }
  })
}
