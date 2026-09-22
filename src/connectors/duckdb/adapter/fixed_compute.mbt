///|
/// An owned import and native query agree on the exact receiving preparation.
/// This is a physical realization, not proof of execution or input admission.
struct FixedCompute {
  imports : Array[FixedImport]
  query : FixedQuery
  join_inputs : FixedJoinInputs?
  output_ceiling : Int?
}

///|
/// Static eligibility only: compile the same import schema and native expression
/// without inventing a future ProducerRead. Runtime binding remains mandatory.
pub fn check_fixed_compute_static(
  owner : @lower.BoundPrepared,
  tables : Array[String],
  limits : NativeQueryLimits,
) -> Result[Unit, NativeQueryIssue] {
  let prepared = @lower.bound_preparation(owner)
  if tables.length() != @lower.preparation_input_count(prepared) ||
    tables.is_empty() {
    return Err(UnsupportedShape)
  }
  let join = @lower.node_at(prepared, 0) is Some(node) &&
    @lower.node_input_target(node, 1) is Some(_)
  let checked = if join &&
    @lower.node_at(prepared, 0) is Some(node) &&
    @lower.node_input_target(node, 1) is Some(_) {
    compile_fixed_inner_join(owner, "main", tables, limits).map(_ => ())
  } else if tables.length() == 1 {
    compile_fixed_query(owner, "main", tables[0], limits).map(_ => ())
  } else {
    Err(UnsupportedShape)
  }
  match checked {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let mut columns = limits.max_entries
  let mut bytes = limits.max_sql_bytes
  for port in 0..<tables.length() {
    guard @lower.preparation_input_schema(prepared, port) is Some(schema) else {
      return Err(UnsupportedShape)
    }
    match
      compile_fixed_import_schema(
        schema,
        tables[port],
        columns,
        bytes,
        ordinal=join,
      ) {
      Err(issue) => return Err(issue)
      Ok((create_sql, insert_sql, count)) => {
        columns -= count
        for text in [create_sql, insert_sql] {
          match @scalar.admit_utf8_length(text, bytes) {
            Ok(size) => bytes -= size
            Err(_) => return Err(Limit)
          }
        }
      }
    }
  }
  Ok(())
}

///|
pub fn prepare_fixed_compute(
  input : @execution.ProducerRead,
  table : String,
  limits : NativeQueryLimits,
) -> Result[FixedCompute, NativeQueryIssue] {
  let imported = match
    prepare_fixed_import(input, table, limits.max_entries, limits.max_sql_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let query = match
    compile_fixed_query(
      @execution.producer_read_receiver(input),
      "main",
      table,
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ imports: [imported], query, join_inputs: None, output_ceiling: None, })
}

///|
pub fn fixed_compute_import(value : FixedCompute, port : Int) -> FixedImport? {
  value.imports.get(port)
}

///|
pub fn fixed_compute_import_count(value : FixedCompute) -> Int {
  value.imports.length()
}

///|
/// Binds validated inputs and a selected output ceiling. Neither preparation
/// nor provisional output is execution evidence. The authored guard can only
/// tighten the selected ceiling, never be waived by backend choice.
pub fn prepare_fixed_join_compute(
  inputs : FixedJoinInputs,
  max_output_rows : Int,
) -> Result[FixedCompute, NativeQueryIssue] {
  if max_output_rows < 0 {
    return Err(InvalidLimits)
  }
  if !fixed_join_inputs_available(inputs) {
    return Err(UnsupportedShape)
  }
  let mut ceiling = max_output_rows
  if inputs.query.output_limit is Some(bound) && bound < ceiling.to_int64() {
    ceiling = bound.to_int()
  }
  Ok({
    imports: inputs.imports.copy(),
    query: InnerJoin(inputs.query),
    join_inputs: Some(inputs),
    output_ceiling: Some(ceiling),
  })
}

///|
pub fn fixed_compute_inputs_available(value : FixedCompute) -> Bool {
  if value.join_inputs is Some(inputs) && !fixed_join_inputs_available(inputs) {
    return false
  }
  for imported in value.imports {
    if !@execution.producer_read_available(imported.input) {
      return false
    }
  }
  true
}

///|
/// Runtime binding is exact per input port, not schema/content equivalence.
pub fn fixed_compute_inputs_match(
  value : FixedCompute,
  inputs : Array[@execution.ProducerRead],
) -> Bool {
  if inputs.length() != value.imports.length() ||
    !fixed_compute_inputs_available(value) {
    return false
  }
  for port in 0..<inputs.length() {
    if !physical_equal(inputs[port], value.imports[port].input) {
      return false
    }
  }
  true
}

///|
pub fn fixed_compute_join_output_ceiling(value : FixedCompute) -> Int? {
  value.output_ceiling
}

///|
pub fn fixed_compute_query(value : FixedCompute) -> FixedQuery {
  value.query
}

///|
/// Checked output width used to reserve managed measurement metadata when a
/// standard fixed task publishes through the managed profile.
pub fn fixed_compute_output_column_count(value : FixedCompute) -> Int {
  @lower.preparation_schema_at(
    @lower.bound_preparation(fixed_query_owner(value.query)),
    fixed_query_target(value.query),
  )
  .map(@schema.field_count)
  .unwrap_or(0)
}

///|
/// Invoke only after common input guards. Preparation binds immutable inputs
/// but cannot choose a join failure before the consumer's input-value ceiling.
pub fn validate_fixed_compute_join(
  value : FixedCompute,
) -> Result[@execution.FixedJoinValidation?, @execution.RowIssue] {
  match value.join_inputs {
    None => Ok(None)
    Some(inputs) =>
      validate_fixed_join_preflight(inputs).map(value => Some(value))
  }
}

///|
/// Value-sensitive retained joins collect keys during their verified imports.
/// This prepares scratch, never validation evidence or SQL permission.
pub fn fixed_compute_retains_join_keys(value : FixedCompute) -> Bool {
  match value.join_inputs {
    None => false
    Some(inputs) =>
      @lower.inner_join_fails_null(inputs.query.profile) ||
      @lower.inner_join_assertion(inputs.query.profile) is Some(_)
  }
}

///|
pub fn prepare_fixed_compute_join_stream(
  value : FixedCompute,
) -> Result[@execution.FixedJoinStream?, @execution.RowIssue] {
  guard value.join_inputs is Some(inputs) else { return Ok(None) }
  if inputs.inputs.all(input => @execution.producer_read_has_cell_access(input)) ||
    !fixed_compute_retains_join_keys(value) {
    return Ok(None)
  }
  @execution.prepare_fixed_join_stream(
    inputs.query.owner,
    inputs.query.profile,
    inputs.inputs,
    inputs.validation_limits,
  ).map(stream => Some(stream))
}

///|
pub fn fixed_compute_join_validation_matches(
  value : FixedCompute,
  validation : @execution.FixedJoinValidation?,
) -> Bool {
  match (value.join_inputs, validation) {
    (None, None) => true
    (Some(inputs), Some(validation)) =>
      @execution.fixed_join_validation_matches(
        validation,
        inputs.query.owner,
        inputs.query.profile,
        inputs.inputs,
      )
    _ => false
  }
}
