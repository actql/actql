///|
/// A native realization bound to exact managed receiving uses.
/// No legacy CID-bearing input is manufactured. This is preparation only:
/// dispatch still needs input obligations, a physical representation matching
/// the checked view, a live pin, current authority and resource admission.
priv enum ManagedFixedQueryBody[T] {
  Fixed(FixedQuery)
  Take(ManagedTakeQuery[T])
}

///|
struct ManagedFixedQuery[T] {
  inputs : Array[@execution.ManagedProducerRead[T]]
  obligations : @execution.ManagedObligations
  body : ManagedFixedQueryBody[T]
  tables : Array[String]
  create_sql : Array[String]
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
  if max_columns < 0 || max_sql_bytes < 0 {
    return Err(InvalidLimits)
  }
  if count == 0 {
    return Err(UnsupportedShape)
  }
  if count > max_columns {
    return Err(Limit)
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
/// request. The finite initial profile supports unary fixed queries and the
/// registered two-input inner join; no port may be silently dropped.
pub fn[T] prepare_managed_fixed_request_query(
  request : @connector.ManagedFixedComputeRequest[T],
  table : String,
  limits : NativeQueryLimits,
) -> Result[ManagedFixedQuery[T], NativeQueryIssue] {
  let inputs = @connector.managed_fixed_compute_request_inputs(request)
  let obligations = @connector.managed_fixed_compute_request_obligations(
    request,
  )
  if inputs.length() == 1 {
    return prepare_managed_fixed_query_inputs(
      inputs,
      [table],
      limits,
      obligations,
    )
  }
  if inputs.length() != 2 {
    return Err(UnsupportedShape)
  }
  prepare_managed_fixed_query_inputs(
    inputs,
    Array::makei(inputs.length(), index => table + "_" + index.to_string()),
    limits,
    obligations,
  )
}

///|
pub fn[T] prepare_managed_fixed_query(
  input : @execution.ManagedProducerRead[T],
  table : String,
  limits : NativeQueryLimits,
) -> Result[ManagedFixedQuery[T], NativeQueryIssue] {
  prepare_managed_fixed_query_inputs(
    [input],
    [table],
    limits,
    @execution.process_managed_obligations(
      @execution.managed_producer_read_receiver(input),
    ),
  )
}

///|
fn[T] prepare_managed_fixed_query_inputs(
  inputs : Array[@execution.ManagedProducerRead[T]],
  tables : Array[String],
  limits : NativeQueryLimits,
  obligations : @execution.ManagedObligations,
) -> Result[ManagedFixedQuery[T], NativeQueryIssue] {
  if inputs.is_empty() || inputs.length() != tables.length() {
    return Err(UnsupportedShape)
  }
  if limits.max_entries < 0 || limits.max_sql_bytes < 0 {
    return Err(InvalidLimits)
  }
  let owner = @execution.managed_producer_read_receiver(inputs[0])
  if !physical_equal(@execution.managed_obligations_owner(obligations), owner) {
    return Err(UnsupportedShape)
  }
  if @lower.preparation_input_count(@lower.bound_preparation(owner)) !=
    inputs.length() {
    return Err(UnsupportedShape)
  }
  for index, input in inputs {
    if !@execution.managed_producer_read_available(input) {
      return Err(InputUnavailable)
    }
    if !physical_equal(@execution.managed_producer_read_receiver(input), owner) ||
      @execution.managed_producer_read_input_index(input) != index {
      return Err(UnsupportedShape)
    }
  }
  let create_sql = []
  let mut columns = limits.max_entries
  let mut bytes = limits.max_sql_bytes
  for index, input in inputs {
    let schema = @execution.managed_producer_read_schema(input)
    let count = @schema.field_count(schema)
    let create = match
      compile_managed_fixed_create_schema(schema, tables[index], columns, bytes) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    columns -= count
    match @scalar.admit_utf8_length(create, bytes) {
      Ok(size) => bytes -= size
      Err(_) => return Err(Limit)
    }
    create_sql.push(create)
  }
  let body = if inputs.length() == 1 {
    match
      prepare_managed_take_query(
        inputs[0],
        "main",
        tables[0],
        managed_input_ordinal_column(),
        "__actql_occurrence",
        limits,
      ) {
      Ok(query) => Take(query)
      Err(UnsupportedShape) =>
        match compile_fixed_query(owner, "main", tables[0], limits) {
          Ok(query) => Fixed(query)
          Err(issue) => return Err(issue)
        }
      Err(issue) => return Err(issue)
    }
  } else {
    let join = match compile_fixed_inner_join(owner, "main", tables, limits) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let profile = native_inner_join_profile(join)
    if @lower.inner_join_fails_null(profile) ||
      @lower.inner_join_assertion(profile) is Some(_) {
      // These laws need ordered key evidence, not only retained column totals.
      return Err(UnsupportedShape)
    }
    Fixed(InnerJoin(join))
  }
  if inputs.any(input => !@execution.managed_producer_read_available(input)) {
    return Err(InputUnavailable)
  }
  Ok({
    inputs: inputs.copy(),
    obligations,
    body,
    tables: tables.copy(),
    create_sql,
    compilation: limits,
  })
}

///|
/// A second preparation of the same completed material is still a different
/// consumer use. Schema/content equality is insufficient for this match.
pub fn[T] managed_fixed_query_matches(
  value : ManagedFixedQuery[T],
  input : @execution.ManagedProducerRead[T],
) -> Bool {
  value.inputs.length() == 1 &&
  @execution.managed_producer_read_same_binding(value.inputs[0], input) &&
  @execution.managed_producer_read_available(value.inputs[0])
}

///|
pub fn[T] managed_fixed_query_matches_inputs(
  value : ManagedFixedQuery[T],
  inputs : Array[@execution.ManagedProducerRead[T]],
) -> Bool {
  if value.inputs.length() != inputs.length() {
    return false
  }
  for index, input in inputs {
    if !@execution.managed_producer_read_same_binding(
        value.inputs[index],
        input,
      ) ||
      !@execution.managed_producer_read_available(value.inputs[index]) {
      return false
    }
  }
  true
}

///|
pub fn[T] managed_fixed_query_owner(
  value : ManagedFixedQuery[T],
) -> @lower.BoundPrepared {
  match value.body {
    Fixed(query) => fixed_query_owner(query)
    Take(_) => @execution.managed_producer_read_receiver(value.inputs[0])
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
        @execution.managed_producer_read_receiver(value.inputs[0]),
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
/// Physical output names are compiler-owned transport bindings. Callers use
/// them only to admit the exact query result into its logical output schema.
pub fn[T] managed_fixed_query_output_names(
  value : ManagedFixedQuery[T],
) -> Array[String]? {
  match value.body {
    Fixed(query) => fixed_query_output_names(query)
    Take(_) => None
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
  value.inputs[0]
}

///|
pub fn[T] managed_fixed_query_inputs(
  value : ManagedFixedQuery[T],
) -> Array[@execution.ManagedProducerRead[T]] {
  value.inputs.copy()
}

///|
pub fn[T] managed_fixed_query_obligations(
  value : ManagedFixedQuery[T],
) -> @execution.ManagedObligations {
  value.obligations
}

///|
pub fn[T] managed_fixed_query_input_count(value : ManagedFixedQuery[T]) -> Int {
  value.inputs.length()
}

///|
/// The current managed compiler delegates joins wholly to DuckDB and retains no
/// Host-side key array. Keep this query fact separate from input count so a
/// future implementation that adds such preflight cannot reuse the bounded
/// scratch estimate without changing its selected-query facts.
pub fn[T] managed_fixed_query_retains_host_join_keys(
  _value : ManagedFixedQuery[T],
) -> Bool {
  false
}

///|
pub fn[T] managed_fixed_query_input_at(
  value : ManagedFixedQuery[T],
  index : Int,
) -> @execution.ManagedProducerRead[T]? {
  value.inputs.get(index)
}

///|
/// Finite row ceiling for retained measurement metadata. Every installed
/// unary query emits no more rows than its input, except a global count,
/// which emits exactly one row even for empty input. This is a capacity bound,
/// not evidence that execution produced that many rows. `input_max_rows` is the
/// admitted input bound, so zero does not cap a global count's output to zero.
pub fn[T] managed_fixed_query_output_row_ceiling(
  value : ManagedFixedQuery[T],
  input_max_rows : Int,
) -> Int {
  if input_max_rows < 0 {
    return 0
  }
  match value.body {
    Fixed(CountGroup(query)) if @lower.count_group_key_count(
        fixed_count_group_profile(query),
      ) ==
      0 => 1
    Fixed(InnerJoin(query)) => {
      let mut ceiling = input_max_rows
      if native_inner_join_output_limit(query) is Some(bound) &&
        bound < ceiling.to_int64() {
        ceiling = bound.to_int()
      }
      ceiling
    }
    _ =>
      Int::min(
        input_max_rows,
        @execution.managed_producer_read_row_count(value.inputs[0]),
      )
  }
}

///|
/// Checked output width used only to reserve bounded measurement metadata.
pub fn[T] managed_fixed_query_output_column_count(
  value : ManagedFixedQuery[T],
) -> Int {
  @lower.preparation_schema_at(
    @lower.bound_preparation(managed_fixed_query_owner(value)),
    managed_fixed_query_target(value),
  )
  .map(@schema.field_count)
  .unwrap_or(0)
}

///|
pub fn[T] managed_fixed_query_create_sql(
  value : ManagedFixedQuery[T],
) -> String {
  value.create_sql[0]
}

///|
pub fn[T] managed_fixed_query_create_sql_at(
  value : ManagedFixedQuery[T],
  index : Int,
) -> String? {
  value.create_sql.get(index)
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
        prepare_managed_take_actual_selection(query, rows, max_cells, max_work) {
        Ok(value) => value
        Err(@execution.InvalidLimits) => return Err(InvalidLimits)
        Err(@execution.Limit) => return Err(Limit)
        Err(_) => return Err(UnsupportedShape)
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
  managed_fixed_query_column_file_sql_at(value, 0, max_sql_bytes)
}

///|
pub fn[T] managed_fixed_query_column_file_sql_at(
  value : ManagedFixedQuery[T],
  input_index : Int,
  max_sql_bytes : Int,
) -> String? {
  guard value.inputs.get(input_index) is Some(input) else { return None }
  let schema = @execution.managed_producer_read_schema(input)
  guard max_sql_bytes > 0 &&
    @schema.field_count(schema) > 0 &&
    managed_fixed_query_input_table(value, input_index) is Some(table) else {
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
      physical_input_identifier(
        output,
        "__actql_import",
        "c" + index.to_string(),
      )
    }
    sql_text(output, ", CASE WHEN ")
    physical_input_identifier(output, "__actql_import", "valid")
    sql_text(output, " AND ")
    physical_input_identifier(output, "__actql_import", "o")
    sql_text(output, " = row_number() OVER () - 1 THEN ")
    physical_input_identifier(output, "__actql_import", "o")
    sql_text(output, " ELSE NULL END FROM (SELECT ")
    for index, _ in physical {
      if index > 0 {
        sql_text(output, ", ")
      }
      sql_text(output, "unnest(c" + index.to_string() + ") AS ")
      sql_identifier(output, "c" + index.to_string())
    }
    sql_text(output, ", unnest(o) AS ")
    sql_identifier(output, "o")
    sql_text(output, ", ")
    for index, _ in physical {
      if index > 0 {
        sql_text(output, " AND ")
      }
      sql_text(output, "length(c" + index.to_string() + ") = length(o)")
    }
    sql_text(output, " AS ")
    sql_identifier(output, "valid")
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
    sql_text(output, "}, ignore_errors=false)) AS ")
    sql_identifier(output, "__actql_import")
    Some(output.builder.to_string())
  } catch {
    _ => None
  }
}

///|
/// Compile a direct scan view over the installed managed-column file. The
/// exact path is substituted only by the Host's authorized file-view command;
/// this template is never exposed as Program-provided SQL. The producer's
/// admitted immutable generation already owns value validation, while the
/// ordinal remains part of the checked logical view.
pub fn[T] managed_fixed_query_column_file_view_sql_at(
  value : ManagedFixedQuery[T],
  input_index : Int,
  max_sql_bytes : Int,
) -> String? {
  guard value.inputs.get(input_index) is Some(input) else { return None }
  let schema = @execution.managed_producer_read_schema(input)
  guard max_sql_bytes > 0 &&
    @schema.field_count(schema) > 0 &&
    managed_fixed_query_input_table(value, input_index) is Some(table) else {
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
    sql_text(output, "CREATE TEMP VIEW ")
    sql_identifier(output, table)
    sql_text(output, " AS SELECT ")
    for index, _ in physical {
      if index > 0 {
        sql_text(output, ", ")
      }
      physical_input_identifier(
        output,
        "__actql_import",
        "c" + index.to_string(),
      )
      sql_text(output, " AS ")
      sql_identifier(
        output,
        @schema.reference_name(@schema.field_at(schema, index).unwrap().name),
      )
    }
    sql_text(output, ", ")
    physical_input_identifier(output, "__actql_import", "o")
    sql_text(output, " AS ")
    sql_identifier(output, managed_input_ordinal_column())
    sql_text(output, " FROM (SELECT ")
    for index, _ in physical {
      if index > 0 {
        sql_text(output, ", ")
      }
      sql_text(output, "unnest(c" + index.to_string() + ") AS ")
      sql_identifier(output, "c" + index.to_string())
    }
    sql_text(output, ", unnest(o) AS ")
    sql_identifier(output, "o")
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
    sql_text(output, "}, ignore_errors=false)) AS ")
    sql_identifier(output, "__actql_import")
    Some(output.builder.to_string())
  } catch {
    _ => None
  }
}

///|
/// Import the installed direct DuckDB Parquet representation. The file keeps
/// logical columns in positional `cN` fields, an exact dense output ordinal and
/// the source occurrence used by the checked evidence-transfer path. This is
/// only a physical import compiler; Store integrity, current use authority and
/// managed completion remain independently mandatory.
pub fn[T] managed_fixed_query_parquet_file_sql(
  value : ManagedFixedQuery[T],
  max_sql_bytes : Int,
) -> String? {
  managed_fixed_query_parquet_file_sql_at(value, 0, max_sql_bytes)
}

///|
pub fn[T] managed_fixed_query_parquet_file_sql_at(
  value : ManagedFixedQuery[T],
  input_index : Int,
  max_sql_bytes : Int,
) -> String? {
  guard value.inputs.get(input_index) is Some(input) else { return None }
  let schema = @execution.managed_producer_read_schema(input)
  guard max_sql_bytes > 0 &&
    @schema.field_count(schema) > 0 &&
    managed_fixed_query_input_table(value, input_index) is Some(table) else {
    return None
  }
  for index in 0..<@schema.field_count(schema) {
    guard @schema.field_at(schema, index) is Some(field) else { return None }
    match field.contract.shape {
      @contract.Number | @contract.Text(_) => ()
      _ => return None
    }
  }
  let output = { builder: StringBuilder(), remaining: max_sql_bytes, }
  try {
    sql_text(output, "INSERT INTO ")
    sql_identifier(output, table)
    sql_text(output, " SELECT ")
    for index in 0..<@schema.field_count(schema) {
      if index > 0 {
        sql_text(output, ", ")
      }
      physical_input_identifier(
        output,
        "__actql_import",
        "c" + index.to_string(),
      )
    }
    sql_text(output, ", CASE WHEN ")
    physical_input_identifier(output, "__actql_import", "o")
    sql_text(output, " = row_number() OVER (ORDER BY ")
    physical_input_identifier(output, "__actql_import", "o")
    sql_text(output, ") - 1 AND ")
    physical_input_identifier(output, "__actql_import", "__actql_occurrence")
    sql_text(output, " >= 0 THEN ")
    physical_input_identifier(output, "__actql_import", "o")
    sql_text(output, " ELSE NULL END FROM read_parquet(?) AS ")
    sql_identifier(output, "__actql_import")
    sql_text(output, " ORDER BY ")
    physical_input_identifier(output, "__actql_import", "o")
    Some(output.builder.to_string())
  } catch {
    _ => None
  }
}

///|
/// Compile a direct Parquet scan view without first copying every row into a
/// temporary table. The physical manifest and Store pin remain mandatory; the
/// file digest is not promoted to logical identity.
pub fn[T] managed_fixed_query_parquet_file_view_sql_at(
  value : ManagedFixedQuery[T],
  input_index : Int,
  max_sql_bytes : Int,
) -> String? {
  guard value.inputs.get(input_index) is Some(input) else { return None }
  let schema = @execution.managed_producer_read_schema(input)
  guard max_sql_bytes > 0 &&
    @schema.field_count(schema) > 0 &&
    managed_fixed_query_input_table(value, input_index) is Some(table) else {
    return None
  }
  for index in 0..<@schema.field_count(schema) {
    guard @schema.field_at(schema, index) is Some(field) else { return None }
    match field.contract.shape {
      @contract.Number | @contract.Text(_) => ()
      _ => return None
    }
  }
  let output = { builder: StringBuilder(), remaining: max_sql_bytes, }
  try {
    sql_text(output, "CREATE TEMP VIEW ")
    sql_identifier(output, table)
    sql_text(output, " AS SELECT ")
    for index in 0..<@schema.field_count(schema) {
      if index > 0 {
        sql_text(output, ", ")
      }
      physical_input_identifier(
        output,
        "__actql_import",
        "c" + index.to_string(),
      )
      sql_text(output, " AS ")
      sql_identifier(
        output,
        @schema.reference_name(@schema.field_at(schema, index).unwrap().name),
      )
    }
    sql_text(output, ", ")
    physical_input_identifier(output, "__actql_import", "o")
    sql_text(output, " AS ")
    sql_identifier(output, managed_input_ordinal_column())
    sql_text(output, " FROM read_parquet(?) AS ")
    sql_identifier(output, "__actql_import")
    Some(output.builder.to_string())
  } catch {
    _ => None
  }
}

///|
fn[T] managed_fixed_query_input_table(
  value : ManagedFixedQuery[T],
  input_index : Int,
) -> String? {
  match value.body {
    Fixed(query) => fixed_query_input_table(query, input_index)
    Take(_) => if input_index == 0 { Some(value.tables[0]) } else { None }
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
  if query.inputs.length() != 1 ||
    !managed_fixed_query_matches(query, query.inputs[0]) {
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
      query.inputs[0],
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
