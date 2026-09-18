///|
/// Static preservation along actual checked kernels, not evidence that those
/// kernels ran. An installed executor must still establish the row occurrence
/// mapping, demanded expressions, order/failures and exact output material.
struct ManagedViewPlan[T] {
  input : ManagedProducerRead[T]
  target : @pipeline.Target
  columns : Array[Int?]
  rows : ManagedViewRows
}

///|
pub(all) enum ManagedViewRows {
  AllRows
  PermutedRows
  SelectedRows
} derive(Eq, Debug)

///|
pub(all) enum ManagedViewIssue {
  InvalidLimits
  Limit
  ForeignInput
  InvalidPath
  UnsupportedKernel
} derive(Eq, Debug)

///|
priv struct ManagedViewBudget {
  mut work : Int
  mut names : Int
}

///|
fn managed_view_name(
  budget : ManagedViewBudget,
  name : String,
) -> Result[String, ManagedViewIssue] {
  if budget.work == 0 {
    return Err(Limit)
  }
  budget.work -= 1
  match @scalar.admit_utf8_length(name, budget.names) {
    Err(_) => Err(Limit)
    Ok(size) => {
      budget.names -= size
      Ok(name)
    }
  }
}

///|
fn managed_view_copy(
  expr : @lower.Expression,
  source : Map[String, Int?],
  slots : Array[Int?],
  budget : ManagedViewBudget,
) -> Result[Int?, ManagedViewIssue] {
  // expression_body defensively copies variadic/case entries even when the
  // expression is not a copy. Bound that metadata work before accessing it.
  let entries = @lower.expression_view_entries(expr)
  if entries > budget.work {
    return Err(Limit)
  }
  budget.work -= entries
  match @lower.expression_body(expr) {
    Field(_, @relation.InputField(field)) => {
      let name = match
        managed_view_name(budget, @schema.reference_name(field)) {
        Ok(name) => name
        Err(issue) => return Err(issue)
      }
      match source.get(name) {
        Some(origin) => Ok(origin)
        None => Err(InvalidPath)
      }
    }
    Field(_, @relation.PriorSlot(index)) => {
      if budget.work == 0 {
        return Err(Limit)
      }
      budget.work -= 1
      match slots.get(index) {
        Some(origin) => Ok(origin)
        None => Err(InvalidPath)
      }
    }
    _ => Ok(None)
  }
}

///|
/// Kernels must form the exact receiving path, not merely have compatible
/// schemas. Work/name/column ceilings bound metadata composition independently
/// of row count. There is no equivalence search or evaluation of expressions.
pub fn[T] prepare_managed_view_plan(
  input : ManagedProducerRead[T],
  kernels : Array[@lower.PreparedKernel],
  max_work : Int,
  max_name_bytes : Int,
  max_columns : Int,
) -> Result[ManagedViewPlan[T], ManagedViewIssue] {
  if max_work < 0 || max_name_bytes < 0 || max_columns < 0 {
    return Err(InvalidLimits)
  }
  if !managed_producer_read_available(input) {
    return Err(ForeignInput)
  }
  if kernels.length() > max_work || input.columns.length() > max_columns {
    return Err(Limit)
  }
  let budget = { work: max_work - kernels.length(), names: max_name_bytes, }
  let mut columns = Array::makei(input.columns.length(), index => Some(index))
  let mut schema = input.schema
  let mut target : @pipeline.Target = Input(input.input_index)
  let mut rows = AllRows
  for kernel in kernels {
    if !physical_equal(@lower.kernel_owner(kernel), input.receiver) {
      return Err(InvalidPath)
    }
    guard @lower.node_at(
        @lower.bound_preparation(input.receiver),
        @lower.kernel_step(kernel),
      )
      is Some(node) &&
      @lower.node_input_count(node) == 1 &&
      @lower.node_input_target(node, 0) == Some(target) else {
      return Err(InvalidPath)
    }
    let output_schema = @lower.kernel_output_schema(kernel)
    if @schema.field_count(output_schema) > max_columns ||
      @lower.kernel_view_entries(kernel) > budget.work {
      return Err(Limit)
    }
    budget.work -= @lower.kernel_view_entries(kernel)
    let source : Map[String, Int?] = Map([])
    for index in 0..<columns.length() {
      let name = match
        managed_view_name(
          budget,
          @schema.reference_name(@schema.field_at(schema, index).unwrap().name),
        ) {
        Ok(name) => name
        Err(issue) => return Err(issue)
      }
      source[name] = columns[index]
    }
    let output = source.copy()
    match @lower.kernel_body(kernel) {
      Select(fields) => {
        output.clear()
        for field in fields {
          let from = match
            managed_view_name(budget, @schema.reference_name(field.input)) {
            Ok(name) => name
            Err(issue) => return Err(issue)
          }
          let into = match
            managed_view_name(budget, @schema.reference_name(field.output)) {
            Ok(name) => name
            Err(issue) => return Err(issue)
          }
          guard source.get(from) is Some(origin) else {
            return Err(InvalidPath)
          }
          output[into] = origin
        }
      }
      SnapshotMap(bindings) | OrderedBindings(bindings) => {
        let slots : Array[Int?] = []
        for (name, expr) in bindings {
          let name = match managed_view_name(budget, name) {
            Ok(name) => name
            Err(issue) => return Err(issue)
          }
          let origin = match managed_view_copy(expr, source, slots, budget) {
            Ok(origin) => origin
            Err(issue) => return Err(issue)
          }
          slots.push(origin)
          output[name] = origin
        }
      }
      Filter(_) | Limit(_, _, _) | TopK(_, _) | PartitionedTopK(_, _) =>
        rows = SelectedRows
      StableSort(order) =>
        if order is Some(_) && rows == AllRows {
          rows = PermutedRows
        }
      _ => return Err(UnsupportedKernel)
    }
    columns = []
    for index in 0..<@schema.field_count(output_schema) {
      let name = match
        managed_view_name(
          budget,
          @schema.reference_name(
            @schema.field_at(output_schema, index).unwrap().name,
          ),
        ) {
        Ok(name) => name
        Err(issue) => return Err(issue)
      }
      guard output.get(name) is Some(origin) else { return Err(InvalidPath) }
      columns.push(origin)
    }
    schema = output_schema
    target = Step(@lower.kernel_step(kernel))
  }
  if !managed_producer_read_available(input) {
    return Err(ForeignInput)
  }
  Ok({ input, target, columns, rows, })
}

///|
pub fn[T] managed_view_plan_matches(
  plan : ManagedViewPlan[T],
  input : ManagedProducerRead[T],
  target : @pipeline.Target,
) -> Bool {
  managed_producer_read_same_binding(plan.input, input) &&
  plan.target == target &&
  managed_producer_read_available(input)
}

///|
pub fn[T] managed_view_plan_rows(plan : ManagedViewPlan[T]) -> ManagedViewRows {
  plan.rows
}

///|
/// Original receiving-column index for an unchanged/exactly copied value.
/// None includes computed values and invalid/revoked lookups, not a failure.
pub fn[T] managed_view_plan_column(
  plan : ManagedViewPlan[T],
  column : Int,
) -> Int? {
  if !managed_producer_read_available(plan.input) {
    return None
  }
  plan.columns.get(column).bind(origin => origin)
}

///|
/// Universal bounds survive selection; exact totals do not. These are facts
/// conditional on the executor establishing the checked plan's preservation.
/// They are not an output receipt or a replacement for actual row mapping.
pub(all) struct ManagedViewColumnFacts {
  source_column : Int
  max_value_bytes_bound : Int
  null_free : Bool
  exact_measurement : ManagedColumnMeasurement?
} derive(Eq, Debug)

///|
pub fn[T] managed_view_plan_column_facts(
  plan : ManagedViewPlan[T],
  column : Int,
) -> ManagedViewColumnFacts? {
  guard managed_view_plan_column(plan, column) is Some(source_column) &&
    managed_producer_read_column_measurement(plan.input, source_column)
    is Some(measurement) else {
    return None
  }
  Some({
    source_column,
    max_value_bytes_bound: measurement.max_value_bytes,
    null_free: measurement.null_rows == 0,
    exact_measurement: if plan.rows == SelectedRows {
      None
    } else {
      Some(measurement)
    },
  })
}
