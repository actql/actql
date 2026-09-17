///|
/// A single-input native realization bound to an exact managed receiving use.
/// No legacy CID-bearing input is manufactured. This is preparation only:
/// dispatch still needs input obligations, a physical representation matching
/// the checked view, a live pin, current authority and resource admission.
priv enum ManagedFixedQueryBody[T] {
  Fixed(FixedQuery)
  Take(ManagedTakeQuery[T])
}

///|
struct ManagedFixedQuery[T] {
  input : @execution.ManagedProducerRead[T]
  body : ManagedFixedQueryBody[T]
  table : String
  create_sql : String
  compilation : NativeQueryLimits
}

///|
fn managed_input_ordinal_column() -> String {
  "__actql_input_ordinal"
}

///|
fn compile_managed_fixed_create_schema(
  schema : @schema.Schema,
  table : String,
  max_columns : Int,
  max_sql_bytes : Int,
) -> Result[String, NativeQueryIssue] {
  let count = @schema.field_count(schema)
  if count == 0 || count >= max_columns {
    return Err(if count == 0 { UnsupportedShape } else { Limit })
  }
  if !physical_column_names_unique(schema) {
    return Err(UnsupportedField)
  }
  let ordinal = managed_input_ordinal_column()
  for index in 0..<count {
    let name = @schema.reference_name(
      @schema.field_at(schema, index).unwrap().name,
    )
    if physical_column_name_key(name) == physical_column_name_key(ordinal) {
      return Err(UnsupportedField)
    }
  }
  let create = { builder: StringBuilder(), remaining: max_sql_bytes, }
  try {
    sql_text(create, "CREATE TEMP TABLE ")
    sql_identifier(create, table)
    sql_text(create, " (")
    for index in 0..<count {
      let field = @schema.field_at(schema, index).unwrap()
      if index > 0 {
        sql_text(create, ", ")
      }
      sql_identifier(create, @schema.reference_name(field.name))
      sql_text(create, " ")
      let (id, decimal) = match parameter_type(field.contract) {
        Ok(value) => value
        Err(issue) => return Err(Parameter(issue))
      }
      if decimal is Some((precision, scale)) {
        sql_text(create, "DECIMAL(")
        sql_text(create, precision.to_string())
        sql_text(create, ",")
        sql_text(create, scale.to_string())
        sql_text(create, ")")
      } else {
        sql_text(create, if id == "TIMESTAMP_TZ" { "TIMESTAMPTZ" } else { id })
      }
      if !field.contract.nullable {
        sql_text(create, " NOT NULL")
      }
    }
    sql_text(create, ", ")
    sql_identifier(create, ordinal)
    sql_text(create, " BIGINT NOT NULL)")
    Ok(create.builder.to_string())
  } catch {
    TextLimit => Err(Limit)
    BadIdentifier => Err(InvalidIdentifier)
  }
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
  let create_sql = match
    compile_managed_fixed_create_schema(
      @execution.managed_producer_read_schema(input),
      table,
      limits.max_entries,
      limits.max_sql_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let body = match
    prepare_managed_take_query(
      input,
      "main",
      table,
      managed_input_ordinal_column(),
      "__actql_occurrence",
      limits,
    ) {
    Ok(query) => Take(query)
    Err(UnsupportedShape) =>
      match compile_fixed_query(owner, "main", table, limits) {
        Ok(query) => Fixed(query)
        Err(issue) => return Err(issue)
      }
    Err(issue) => return Err(issue)
  }
  if !@execution.managed_producer_read_available(input) {
    return Err(InputUnavailable)
  }
  Ok({ input, body, table, create_sql, compilation: limits, })
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
pub fn[T] managed_fixed_query_owner(
  value : ManagedFixedQuery[T],
) -> @lower.BoundPrepared {
  match value.body {
    Fixed(query) => fixed_query_owner(query)
    Take(_) => @execution.managed_producer_read_receiver(value.input)
  }
}

///|
pub fn[T] managed_fixed_query_target(
  value : ManagedFixedQuery[T],
) -> @pipeline.Target {
  match value.body {
    Fixed(query) => fixed_query_target(query)
    Take(_) => {
      let prepared = @lower.bound_preparation(
        @execution.managed_producer_read_receiver(value.input),
      )
      Step(@lower.node_count(prepared) - 1)
    }
  }
}

///|
pub fn[T] managed_fixed_query_sql(value : ManagedFixedQuery[T]) -> String {
  match value.body {
    Fixed(query) => fixed_query_sql(query)
    Take(query) => managed_take_query_sql(query)
  }
}

///|
pub fn[T] managed_fixed_query_parameter_count(
  value : ManagedFixedQuery[T],
) -> Int {
  match value.body {
    Fixed(query) => fixed_query_parameter_count(query)
    Take(_) => 0
  }
}

///|
pub fn[T] managed_fixed_query_parameter(
  value : ManagedFixedQuery[T],
  index : Int,
) -> PhysicalParameter? {
  match value.body {
    Fixed(query) => fixed_query_parameter(query, index)
    Take(_) => None
  }
}

///|
/// Whether the installed fixed realization consumes a runtime expression
/// fragment. Checked take/projection/copy uses only its finite view plan.
pub fn[T] managed_fixed_query_requires_fragment(
  value : ManagedFixedQuery[T],
) -> Bool {
  managed_fixed_query_fragment_start(value) >= 0
}

///|
/// First checked step covered by the runtime fragment, or -1 when this fixed
/// realization has no expression fragment obligation.
pub fn[T] managed_fixed_query_fragment_start(
  value : ManagedFixedQuery[T],
) -> Int {
  match value.body {
    Fixed(FilterSelect(_)) => 0
    Take(query) => managed_take_query_fragment_start(query)
    Fixed(_) => -1
  }
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
/// Checked filter/select SQL with the exact input occurrence attached. The
/// fixed alias is Host-private and cannot be selected by Program input. An
/// unsupported checked shape keeps the ordinary validation path available.
pub fn[T] managed_fixed_query_occurrence_sql(
  value : ManagedFixedQuery[T],
) -> String? {
  match value.body {
    Take(query) => Some(managed_take_query_sql(query))
    Fixed(_) =>
      match
        managed_fixed_selection_sql(
          value,
          managed_input_ordinal_column(),
          "__actql_occurrence",
          value.compilation,
        ) {
        Ok(sql) => Some(sql)
        Err(_) => None
      }
  }
}

///|
/// Bind actual ordered native occurrences to the already checked query. This
/// copies finite measurement evidence; it is not proof that native execution
/// produced these occurrences.
pub fn[T] prepare_managed_fixed_query_selection(
  value : ManagedFixedQuery[T],
  rows : Array[Int],
  max_cells : Int,
  max_work : Int,
) -> Result[@execution.ManagedViewSelection[T], NativeQueryIssue] {
  match value.body {
    Fixed(_) =>
      prepare_managed_filter_selection(
        value,
        rows,
        value.compilation,
        max_cells,
        max_work,
      )
    Take(query) => {
      let selection = match
        prepare_managed_take_selection(query, max_cells, max_work) {
        Ok(value) => value
        Err(@execution.InvalidLimits) => return Err(InvalidLimits)
        Err(@execution.Limit) => return Err(Limit)
        Err(_) => return Err(UnsupportedShape)
      }
      for index, row in rows {
        if @execution.managed_view_selection_row(selection, index) != Some(row) {
          return Err(UnsupportedShape)
        }
      }
      if @execution.managed_view_selection_row(selection, rows.length())
        is Some(_) {
        return Err(UnsupportedShape)
      }
      Ok(selection)
    }
  }
}

///|
/// Finite installed physical codec for Number and Text columns. Each bounded
/// newline-delimited object contains `c0` through `cN` typed column lists.
/// This compiles only the import; exact Store generation, integrity, use
/// authority and the subsequent typed managed completion remain mandatory.
pub fn[T] managed_fixed_query_column_file_sql(
  value : ManagedFixedQuery[T],
  max_sql_bytes : Int,
) -> String? {
  let schema = @execution.managed_producer_read_schema(value.input)
  guard max_sql_bytes > 0 &&
    @schema.field_count(schema) > 0 &&
    managed_fixed_query_input_table(value) is Some(table) else {
    return None
  }
  let physical = []
  for index in 0..<@schema.field_count(schema) {
    guard @schema.field_at(schema, index) is Some(field) else { return None }
    match field.contract.shape {
      @contract.Number => physical.push("DOUBLE")
      @contract.Text(_) => physical.push("VARCHAR")
      _ => return None
    }
  }
  let output = { builder: StringBuilder(), remaining: max_sql_bytes, }
  try {
    sql_text(output, "INSERT INTO ")
    sql_identifier(output, table)
    sql_text(output, " SELECT ")
    for index, _ in physical {
      if index > 0 {
        sql_text(output, ", ")
      }
      sql_text(output, "unnest(c" + index.to_string() + ")")
    }
    sql_text(output, ", unnest(o)")
    sql_text(
      output, " FROM read_json(?, format='newline_delimited', auto_detect=false, columns={",
    )
    for index, kind in physical {
      if index > 0 {
        sql_text(output, ",")
      }
      sql_text(output, "c" + index.to_string() + ":'" + kind + "[]'")
    }
    if physical.length() > 0 {
      sql_text(output, ",")
    }
    sql_text(output, "o:'BIGINT[]'")
    sql_text(output, "}, ignore_errors=false)")
    Some(output.builder.to_string())
  } catch {
    _ => None
  }
}

///|
fn[T] managed_fixed_query_input_table(value : ManagedFixedQuery[T]) -> String? {
  match value.body {
    Fixed(query) => fixed_query_input_table(query, 0)
    Take(_) => Some(value.table)
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
  if limits.max_entries < 0 || limits.max_sql_bytes < 0 {
    return Err(InvalidLimits)
  }
  if !managed_fixed_query_matches(query, query.input) {
    return Err(InputUnavailable)
  }
  match query.body {
    Take(take) => return Ok(take.plan)
    Fixed(FilterSelect(_)) => ()
    Fixed(_) => return Err(UnsupportedShape)
  }
  let kernels = []
  for step in 0..<2 {
    match
      @lower.prepare_kernel(
        managed_fixed_query_owner(query),
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
