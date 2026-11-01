///|
/// A view of one exact checked content barrier and its bound invocation.
/// This is not a completed input, Store lease, issuance authority or dispatch.
struct PreparedSerialization {
  owner : BoundPrepared
  step : Int
  checked : @pipeline.CheckedSerialization
  order : @pipeline.SerializationOrder
  row_guard : Int64?
  byte_guard : Int64?
  work : Int
}

///|
pub(all) enum SerializationPreparationIssueKind {
  InvalidLimits
  BudgetExceeded
  NotSerialization
  UnprovedInputOrder
  InvalidCountGuard(String)
} derive(Eq, Debug)

///|
pub struct SerializationPreparationIssue {
  kind : SerializationPreparationIssueKind
  source : @decode.Cursor
}

///|
/// Resolve author guards from the existing bound Parameter owner. Host policy
/// must still supply finite physical ceilings before generation starts.
pub fn prepare_serialization(
  owner : BoundPrepared,
  step : Int,
  max_work~ : Int,
) -> Result[PreparedSerialization, SerializationPreparationIssue] {
  let source = @pipeline.source(owner.prepared.owner)
  if max_work < 0 {
    return Err({ kind: InvalidLimits, source, })
  }
  if max_work == 0 {
    return Err({ kind: BudgetExceeded, source, })
  }
  guard owner.prepared.nodes.get(step) is Some(node) &&
    node.payload is Serialize(checked) else {
    return Err({ kind: NotSerialization, source, })
  }
  guard @pipeline.serialization_order(owner.prepared.owner, step) is Some(order) else {
    return Err({ kind: UnprovedInputOrder, source: node.source, })
  }
  let mut work = 1
  let resolved : Array[Int64?] = []
  for
    guard_value in [
      @pipeline.serialization_max_rows(checked),
      @pipeline.serialization_max_bytes(checked),
    ] {
    if work == max_work {
      return Err({ kind: BudgetExceeded, source: node.source, })
    }
    work += 1
    match guard_value {
      None => resolved.push(None)
      Some(guard_value) => {
        let guard_source = @relation.count_value_source(guard_value)
        match @relation.count_value(guard_value) {
          Literal(value) => resolved.push(Some(value))
          Parameter(name) => {
            if name.length() > max_work - work {
              return Err({ kind: BudgetExceeded, source: guard_source, })
            }
            work += name.length()
            // BoundValues already belongs to this exact declaration owner.
            // Number is a fixed-size admitted scalar, not rescanned JSON text.
            guard owner.by_name.get(name) is Some(value) &&
              value.value is @value.Number(number) else {
              return Err({
                kind: InvalidCountGuard(name),
                source: guard_source,
              })
            }
            if work == max_work {
              return Err({ kind: BudgetExceeded, source: guard_source, })
            }
            work += 1
            guard @scalar.read_safe_integer(number) is Some(count) && count > 0L else {
              return Err({
                kind: InvalidCountGuard(name),
                source: guard_source,
              })
            }
            resolved.push(Some(count))
          }
        }
      }
    }
  }
  Ok({
    owner,
    step,
    checked,
    order,
    row_guard: resolved[0],
    byte_guard: resolved[1],
    work,
  })
}

///|
pub fn serialization_owner(value : PreparedSerialization) -> BoundPrepared {
  value.owner
}

///|
pub fn serialization_step(value : PreparedSerialization) -> Int {
  value.step
}

///|
/// Exact prepared occurrence, not equal fields or an independently prepared
/// barrier. This read-only predicate grants no acquisition or completion.
pub fn serialization_matches_node(
  value : PreparedSerialization,
  node : PreparedNode,
) -> Bool {
  value.owner.prepared.nodes.get(value.step) is Some(original) &&
  physical_equal(original, node) &&
  node.payload is Serialize(checked) &&
  physical_equal(value.checked, checked)
}

///|
/// The original checked ORDER BY requires the shared internal sort. Runtime
/// consumers do not need the checked operation to inspect this distinction.
pub fn serialization_requires_sort(value : PreparedSerialization) -> Bool {
  @pipeline.serialization_sort(value.checked) is Some(_)
}

///|
pub fn serialization_checked(
  value : PreparedSerialization,
) -> @pipeline.CheckedSerialization {
  value.checked
}

///|
pub fn serialization_order(
  value : PreparedSerialization,
) -> @pipeline.SerializationOrder {
  value.order
}

///|
pub fn serialization_author_guards(
  value : PreparedSerialization,
) -> (Int64?, Int64?) {
  (value.row_guard, value.byte_guard)
}

///|
pub fn serialization_preparation_work(value : PreparedSerialization) -> Int {
  value.work
}

///|
/// Prepare the checked internal ORDER BY as the ordinary bounded stable-sort
/// kernel. The original invocation and input remain owned by this barrier;
/// preparation does not authorize byte generation or issue a completed input.
pub fn prepare_serialization_sort_kernel(
  value : PreparedSerialization,
  max_bindings~ : Int,
  max_name_bytes~ : Int,
  max_work~ : Int,
) -> Result[PreparedKernel, KernelIssue] {
  if max_bindings < 0 || max_name_bytes < 0 || max_work < 0 {
    return Err(InvalidKernelLimits)
  }
  guard @pipeline.serialization_sort(value.checked) is Some(checked) &&
    @pipeline.serialization_sort_strategy(value.order) is Some(strategy) else {
    return Err(PendingSortOrder)
  }
  let authored = @relation.sort_term_count(checked)
  let completion = match strategy {
    CandidateKey(completion) => Some(completion)
    ExistingTotal(_) => None
  }
  let appended = completion.map(@pipeline.sort_completion_count).unwrap_or(0)
  if authored > max_bindings ||
    appended > max_bindings - authored ||
    authored > max_work ||
    appended > max_work - authored {
    return Err(KernelBudgetExceeded)
  }
  let mut names = max_name_bytes
  for index in 0..<(authored + appended) {
    let field = if index < authored {
      @relation.sort_term_at(checked, index).unwrap().field
    } else {
      @pipeline.sort_completion_field(completion.unwrap(), index - authored).unwrap()
    }
    let name = @schema.reference_name(field)
    if name.length() > names {
      return Err(KernelBudgetExceeded)
    }
    let size = @utf8.encode(name).length()
    if size > names {
      return Err(KernelBudgetExceeded)
    }
    names -= size
  }
  guard value.owner.prepared.nodes.get(value.step) is Some(node) &&
    node.inputs.length() == 1 else {
    return Err(InvalidKernelWiring)
  }
  Ok({
    owner: value.owner,
    step_index: value.step,
    input_id: node.inputs[0],
    checked,
    body: StableSort(Some(strategy)),
    ordered_reference_material: None,
  })
}
