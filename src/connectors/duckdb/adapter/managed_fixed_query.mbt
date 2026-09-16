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
