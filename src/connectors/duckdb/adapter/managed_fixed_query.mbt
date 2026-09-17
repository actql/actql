///|
/// A single-input native realization bound to an exact managed receiving use.
/// No legacy CID-bearing input is manufactured. This is preparation only:
/// dispatch still needs input obligations, a physical representation matching
/// the checked view, a live pin, current authority and resource admission.
struct ManagedFixedQuery[T] {
  input : @execution.ManagedProducerRead[T]
  query : FixedQuery
  create_sql : String
}

///|
/// Compile from the common managed request rather than manufacturing a legacy
/// request. This adapter currently supports one input; multi-input realization
/// remains an explicit connector capability rather than silently dropping
/// ports.
pub fn[T] prepare_managed_fixed_request_query(
  request : @connector.ManagedFixedComputeRequest[T],
  table : String,
  limits : NativeQueryLimits,
) -> Result[ManagedFixedQuery[T], NativeQueryIssue] {
  guard @connector.managed_fixed_compute_request_input_count(request) == 1 &&
    @connector.managed_fixed_compute_request_input(request, 0) is Some(input) else {
    return Err(UnsupportedShape)
  }
  prepare_managed_fixed_query(input, table, limits)
}

///|
pub fn[T] prepare_managed_fixed_query(
  input : @execution.ManagedProducerRead[T],
  table : String,
  limits : NativeQueryLimits,
) -> Result[ManagedFixedQuery[T], NativeQueryIssue] {
  if !@execution.managed_producer_read_available(input) {
    return Err(InputUnavailable)
  }
  if limits.max_entries < 0 || limits.max_sql_bytes < 0 {
    return Err(InvalidLimits)
  }
  let owner = @execution.managed_producer_read_receiver(input)
  if @execution.managed_producer_read_input_index(input) != 0 ||
    @lower.preparation_input_count(@lower.bound_preparation(owner)) != 1 {
    return Err(UnsupportedShape)
  }
  let (create_sql, _, _) = match
    compile_fixed_import_schema(
      @execution.managed_producer_read_schema(input),
      table,
      limits.max_entries,
      limits.max_sql_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let query = match compile_fixed_query(owner, "main", table, limits) {
    Ok(query) => query
    Err(issue) => return Err(issue)
  }
  if !@execution.managed_producer_read_available(input) {
    return Err(InputUnavailable)
  }
  Ok({ input, query, create_sql, })
}

///|
/// A second preparation of the same completed material is still a different
/// consumer use. Schema/content equality is insufficient for this match.
pub fn[T] managed_fixed_query_matches(
  value : ManagedFixedQuery[T],
  input : @execution.ManagedProducerRead[T],
) -> Bool {
  @execution.managed_producer_read_same_binding(value.input, input) &&
  @execution.managed_producer_read_available(value.input)
}

///|
pub fn[T] managed_fixed_query_query(value : ManagedFixedQuery[T]) -> FixedQuery {
  value.query
}

///|
pub fn[T] managed_fixed_query_input(
  value : ManagedFixedQuery[T],
) -> @execution.ManagedProducerRead[T] {
  value.input
}

///|
pub fn[T] managed_fixed_query_create_sql(
  value : ManagedFixedQuery[T],
) -> String {
  value.create_sql
}

///|
/// Finite installed physical codec for one numeric column. The file contains
/// newline-delimited objects whose `native_columns` member is one DOUBLE list.
/// This compiles only the import; exact Store generation, integrity, use
/// authority and the subsequent typed managed completion remain mandatory.
pub fn[T] managed_fixed_query_numeric_file_sql(
  value : ManagedFixedQuery[T],
  max_sql_bytes : Int,
) -> String? {
  let schema = @execution.managed_producer_read_schema(value.input)
  guard max_sql_bytes > 0 &&
    @schema.field_count(schema) == 1 &&
    @schema.field_at(schema, 0) is Some(field) &&
    field.contract.shape is @contract.Number &&
    fixed_query_input_table(value.query, 0) is Some(table) else {
    return None
  }
  let output = { builder: StringBuilder(), remaining: max_sql_bytes, }
  try {
    sql_text(output, "INSERT INTO ")
    sql_identifier(output, table)
    sql_text(
      output, " SELECT unnest(native_columns[1]) FROM read_json(?, format='newline_delimited', auto_detect=false, columns={native_columns:'DOUBLE[][]'}, ignore_errors=false)",
    )
    Some(output.builder.to_string())
  } catch {
    _ => None
  }
}

///|
/// Compile the finite preservation path for the already accepted native
/// filter/select realization. Group creates new values and needs its separate
/// validation issuer; compilation is not execution evidence.
pub fn[T] prepare_managed_fixed_view_plan(
  query : ManagedFixedQuery[T],
  limits : NativeQueryLimits,
) -> Result[@execution.ManagedViewPlan[T], NativeQueryIssue] {
  guard query.query is FilterSelect(_) else { return Err(UnsupportedShape) }
  if limits.max_entries < 0 || limits.max_sql_bytes < 0 {
    return Err(InvalidLimits)
  }
  if !managed_fixed_query_matches(query, query.input) {
    return Err(InputUnavailable)
  }
  let kernels = []
  for step in 0..<2 {
    match
      @lower.prepare_kernel(
        fixed_query_owner(query.query),
        step,
        max_bindings=limits.max_entries,
        max_name_bytes=limits.max_sql_bytes,
        limits.expressions,
      ) {
      Ok(kernel) => kernels.push(kernel)
      Err(issue) => return Err(Lowering(issue))
    }
  }
  match
    @execution.prepare_managed_view_plan(
      query.input,
      kernels,
      limits.max_entries,
      limits.max_sql_bytes,
      limits.max_entries,
    ) {
    Ok(plan) => Ok(plan)
    Err(ForeignInput) => Err(InputUnavailable)
    Err(InvalidPath | UnsupportedKernel) => Err(UnsupportedShape)
    Err(InvalidLimits) => Err(InvalidLimits)
    Err(Limit) => Err(Limit)
  }
}
