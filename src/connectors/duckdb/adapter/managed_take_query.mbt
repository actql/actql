///|
/// Prepared take/projection/exact-copy path over an exact managed input. The installed Host
/// must bind `ordinal` to the input's proven logical occurrence order, with one
/// distinct zero-based ordinal per row. A provider's incidental order or a
/// user-supplied integer column does not satisfy that physical binding.
struct ManagedTakeQuery[T] {
  input : @execution.ManagedProducerRead[T]
  plan : @execution.ManagedViewPlan[T]
  sql : String
  count : Int64
  offset : Int64
  width : Int
  stages : Array[(Int64, Int64)]
  fragment_start : Int
}

///|
pub fn[T] prepare_managed_take_query(
  input : @execution.ManagedProducerRead[T],
  database_schema : String,
  table : String,
  ordinal : String,
  occurrence_alias : String,
  limits : NativeQueryLimits,
) -> Result[ManagedTakeQuery[T], NativeQueryIssue] {
  if limits.max_entries < 0 || limits.max_sql_bytes < 0 {
    return Err(InvalidLimits)
  }
  if !@execution.managed_producer_read_available(input) {
    return Err(InputUnavailable)
  }
  let owner = @execution.managed_producer_read_receiver(input)
  let preparation = @lower.bound_preparation(owner)
  if @execution.managed_producer_read_input_index(input) != 0 ||
    @lower.preparation_input_count(preparation) != 1 ||
    @lower.node_count(preparation) == 0 {
    return Err(UnsupportedShape)
  }
  let steps = @lower.node_count(preparation)
  if steps > limits.max_entries {
    return Err(Limit)
  }
  let kernels = []
  let mut entries = limits.max_entries - steps
  let mut count = 9007199254740991L
  let mut offset = 0L
  let mut has_take = false
  let mut fragment_start = -1
  let stages = []
  for step in 0..<steps {
    let kernel = match
      @lower.prepare_kernel(
        owner,
        step,
        max_bindings=entries,
        max_name_bytes=limits.max_sql_bytes,
        limits.expressions,
      ) {
      Ok(kernel) => kernel
      Err(issue) => return Err(Lowering(issue))
    }
    let used = @lower.kernel_view_entries(kernel)
    if used > entries {
      return Err(Limit)
    }
    entries -= used
    match @lower.kernel_body(kernel) {
      @lower.Limit(next_count, next_offset, order) => {
        // Physical occurrence order cannot replace candidate-key completion.
        if @pipeline.order_key_completion(order) is Some(_) {
          return Err(UnsupportedShape)
        }
        has_take = true
        let skipped = Int64::min(next_offset, count)
        // Both operands are at most the safe-integer bound, so this sum fits
        // Int64. Saturation is beyond the exact input's Int-sized row domain.
        offset = Int64::min(9007199254740991L, offset + skipped)
        count = Int64::min(next_count, count - skipped)
      }
      @lower.Select(_) => ()
      @lower.SnapshotMap(bindings) | @lower.OrderedBindings(bindings) => {
        if fragment_start < 0 {
          fragment_start = step
        }
        // Check every binding, not only surviving output columns: a later
        // projection must not erase a demanded failing computation. Only
        // exact checked field/slot copies have no new expression to execute.
        for (_, expression) in bindings {
          let inspected = @lower.expression_view_entries(expression)
          if inspected > entries {
            return Err(Limit)
          }
          entries -= inspected
          match @lower.expression_body(expression) {
            @lower.Field(_, @relation.InputField(_))
            | @lower.Field(_, @relation.PriorSlot(_)) => ()
            _ => return Err(UnsupportedShape)
          }
        }
      }
      _ => return Err(UnsupportedShape)
    }
    stages.push((count, offset))
    kernels.push(kernel)
  }
  if !has_take {
    return Err(UnsupportedShape)
  }
  let final_schema = @lower.preparation_schema_at(preparation, Step(steps - 1)).unwrap()
  let schema = @execution.managed_producer_read_schema(input)
  if @schema.field_count(schema) > entries {
    return Err(Limit)
  }
  // Bound identifier inspection as well as emitted SQL. Hidden ordinal must
  // not be shadowed by an authored input field.
  let mut names = limits.max_sql_bytes
  for name in [ordinal, occurrence_alias] {
    match @scalar.admit_utf8_length(name, names) {
      Ok(bytes) => names -= bytes
      Err(_) => return Err(Limit)
    }
  }
  for i in 0..<@schema.field_count(schema) {
    let name = @schema.reference_name(@schema.field_at(schema, i).unwrap().name)
    match @scalar.admit_utf8_length(name, names) {
      Ok(bytes) => names -= bytes
      Err(_) => return Err(Limit)
    }
    if physical_column_name_key(name) == physical_column_name_key(ordinal) {
      return Err(UnsupportedField)
    }
  }
  if !physical_column_names_unique(schema) ||
    !physical_column_names_unique(final_schema) {
    return Err(UnsupportedField)
  }
  let plan = match
    @execution.prepare_managed_view_plan(
      input,
      kernels,
      limits.max_entries,
      limits.max_sql_bytes,
      limits.max_entries,
    ) {
    Ok(plan) => plan
    Err(ForeignInput) => return Err(InputUnavailable)
    Err(InvalidPath | UnsupportedKernel) => return Err(UnsupportedShape)
    Err(InvalidLimits) => return Err(InvalidLimits)
    Err(Limit) => return Err(Limit)
  }
  let out = { builder: StringBuilder(), remaining: limits.max_sql_bytes, }
  try {
    sql_text(out, "SELECT ")
    sql_text(out, "\"__actql_input\".")
    sql_identifier(out, ordinal)
    sql_text(out, " AS ")
    sql_identifier(out, occurrence_alias)
    for column in 0..<@schema.field_count(final_schema) {
      guard @execution.managed_view_plan_column(plan, column) is Some(origin) else {
        return Err(UnsupportedShape)
      }
      guard @schema.field_at(schema, origin).unwrap().name
        is @schema.Unqualified(source) &&
        @schema.field_at(final_schema, column).unwrap().name
        is @schema.Unqualified(target) else {
        return Err(UnsupportedField)
      }
      if physical_column_name_key(target) ==
        physical_column_name_key(occurrence_alias) {
        return Err(UnsupportedField)
      }
      sql_text(out, ", ")
      sql_text(out, "\"__actql_input\".")
      sql_identifier(out, source)
      sql_text(out, " AS ")
      sql_identifier(out, target)
    }
    sql_text(out, " FROM ")
    sql_identifier(out, database_schema)
    sql_text(out, ".")
    sql_identifier(out, table)
    sql_text(out, " AS \"__actql_input\" ORDER BY \"__actql_input\".")
    sql_identifier(out, ordinal)
    sql_text(out, " ASC LIMIT ")
    sql_text(out, count.to_string())
    sql_text(out, " OFFSET ")
    sql_text(out, offset.to_string())
  } catch {
    TextLimit => return Err(Limit)
    BadIdentifier => return Err(InvalidIdentifier)
  }
  if !@execution.managed_producer_read_available(input) {
    return Err(InputUnavailable)
  }
  Ok({
    input,
    plan,
    sql: out.builder.to_string(),
    count,
    offset,
    width: @schema.field_count(final_schema),
    stages,
    fragment_start,
  })
}

///|
/// Composed (limit, offset) after a checked step, not its actual row count.
/// Bounds may extend beyond the input. These are conditional slice facts, not
/// discharge of per-step guards, accounting or execution obligations.
pub fn[T] managed_take_query_stage_range(
  query : ManagedTakeQuery[T],
  step : Int,
) -> (Int64, Int64)? {
  query.stages.get(step)
}

///|
pub fn[T] managed_take_query_sql(query : ManagedTakeQuery[T]) -> String {
  query.sql
}

///|
/// Exact-copy derive changes no value bytes, but its checked fragment remains
/// an adopted completion obligation and cannot be omitted from preparation.
fn[T] managed_take_query_fragment_start(query : ManagedTakeQuery[T]) -> Int {
  query.fragment_start
}

///|
pub fn[T] managed_take_query_matches(
  query : ManagedTakeQuery[T],
  input : @execution.ManagedProducerRead[T],
) -> Bool {
  @execution.managed_producer_read_same_binding(query.input, input) &&
  @execution.managed_producer_read_available(query.input)
}

///|
/// Bounded expected occurrence metadata, not evidence that SQL executed.
pub fn[T] prepare_managed_take_selection(
  query : ManagedTakeQuery[T],
  max_cells : Int,
  max_work : Int,
) -> Result[
  @execution.ManagedViewSelection[T],
  @execution.ManagedSelectionMeasureIssue,
] {
  if max_cells < 0 || max_work < 0 {
    return Err(InvalidLimits)
  }
  if !managed_take_query_matches(query, query.input) {
    return Err(ForeignInput)
  }
  let available = @execution.managed_producer_read_row_count(query.input)
  let offset = if query.offset >= available.to_int64() {
    available
  } else {
    query.offset.to_int()
  }
  let remaining = available - offset
  let count = if query.count >= remaining.to_int64() {
    remaining
  } else {
    query.count.to_int()
  }
  if count > max_work {
    return Err(Limit)
  }
  if query.width > 0 && count > max_cells / query.width {
    return Err(Limit)
  }
  @execution.prepare_managed_view_slice(
    query.plan,
    offset,
    count,
    max_cells,
    max_work,
  )
}
