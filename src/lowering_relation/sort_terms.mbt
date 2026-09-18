///|
/// Indexed read of the compiler-selected order, never an independent completion
/// rule. An empty authored sort has no resolution and has zero terms.
pub fn kernel_sort_term_count(kernel : PreparedKernel) -> Int {
  if kernel.body is Limit(_, _, _) {
    return take_completion(kernel.owner.prepared.owner, kernel.step_index)
      .map(@evidence.key_field_count)
      .unwrap_or(0)
  }
  if top_k_order(kernel) is Some(order) {
    return @relation.ranking_term_count(kernel.checked) +
      @pipeline.order_sort_completion(order)
      .map(@pipeline.sort_completion_count)
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
  if top_k_order(kernel) is Some(order) {
    if index < 0 {
      return None
    }
    let authored = @relation.ranking_term_count(kernel.checked)
    if index < authored {
      let term = @relation.ranking_term_at(kernel.checked, index).unwrap()
      return Some((term.field, term.direction is Desc, term.nulls is First))
    }
    return @pipeline.order_sort_completion(order).bind(completion => {
      @pipeline.sort_completion_field(completion, index - authored).map(field => {
        (field, false, false)
      })
    })
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

///|
fn top_k_order(kernel : PreparedKernel) -> @pipeline.LogicalOrder? {
  match kernel.body {
    TopK(_, order) | PartitionedTopK(_, order) => Some(order)
    _ => None
  }
}

///|
/// Authored partition occurrences are retained exactly, including repetition.
pub fn kernel_top_k_partition_count(kernel : PreparedKernel) -> Int {
  if kernel.body is PartitionedTopK(_, _) {
    @relation.top_k_partition_count(kernel.checked)
  } else {
    0
  }
}

///|
pub fn kernel_top_k_partition_at(
  kernel : PreparedKernel,
  index : Int,
) -> @schema.FieldName? {
  if kernel.body is PartitionedTopK(_, _) {
    @relation.top_k_partition_at(kernel.checked, index).map(field => field.field)
  } else {
    None
  }
}
