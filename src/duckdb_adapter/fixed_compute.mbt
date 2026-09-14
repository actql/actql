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
  let pipeline = @lower.pipeline(@lower.bound_preparation(owner))
  if tables.length() != @pipeline.input_count(pipeline) || tables.is_empty() {
    return Err(UnsupportedShape)
  }
  let checked = if @pipeline.step_at(pipeline, 0) is Some(step) &&
    step.operation is @pipeline.Join(_) {
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
    guard @pipeline.schema_at(pipeline, Input(port)) is Some(schema) else {
      return Err(UnsupportedShape)
    }
    match compile_fixed_import_schema(schema, tables[port], columns, bytes) {
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
