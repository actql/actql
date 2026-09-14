///|
/// Owned fixed imports and bounded deferred join preflight. This is preparation, not
/// authority to publish output or skip transport/output-capacity verification.
struct FixedJoinInputs {
  query : NativeInnerJoin
  inputs : Array[@execution.ProducerRead]
  imports : Array[FixedImport]
  validation_limits : @execution.FixedJoinValidationLimits
}

///|
pub(all) enum FixedJoinInputIssue {
  Validation(@execution.RowIssue)
  Import(NativeQueryIssue)
}

///|
pub fn prepare_fixed_join_inputs(
  query : NativeInnerJoin,
  inputs : Array[@execution.ProducerRead],
  validation_limits : @execution.FixedJoinValidationLimits,
  max_columns : Int,
  max_sql_bytes : Int,
) -> Result[FixedJoinInputs, FixedJoinInputIssue] {
  if max_columns < 0 ||
    max_sql_bytes < 0 ||
    validation_limits.max_rows < 0 ||
    validation_limits.max_work < 0 ||
    validation_limits.max_entries < 0 {
    return Err(Import(InvalidLimits))
  }
  if inputs.length() != query.tables.length() {
    return Err(Validation(InputMismatch))
  }
  for port in 0..<inputs.length() {
    if !@execution.producer_read_available(inputs[port]) ||
      !physical_equal(
        @execution.producer_read_receiver(inputs[port]),
        query.owner,
      ) ||
      @execution.producer_read_input_index(inputs[port]) != port {
      return Err(Validation(InputMismatch))
    }
  }
  let mut columns = max_columns
  let mut bytes = max_sql_bytes
  let imports = []
  for port in 0..<inputs.length() {
    let imported = match
      prepare_fixed_import(inputs[port], query.tables[port], columns, bytes) {
      Ok(value) => value
      Err(issue) => return Err(Import(issue))
    }
    columns -= imported.columns
    for text in [imported.create_sql, imported.insert_sql] {
      match @scalar.admit_utf8_length(text, bytes) {
        Ok(size) => bytes -= size
        Err(_) => return Err(Import(Limit))
      }
    }
    imports.push(imported)
  }
  Ok({ query, inputs: inputs.copy(), imports, validation_limits, })
}

///|
pub fn fixed_join_inputs_available(value : FixedJoinInputs) -> Bool {
  value.inputs.all(input => @execution.producer_read_available(input))
}

///|
pub fn fixed_join_inputs_query(value : FixedJoinInputs) -> NativeInnerJoin {
  value.query
}

///|
pub fn fixed_join_import_count(value : FixedJoinInputs) -> Int {
  value.imports.length()
}

///|
pub fn fixed_join_import_at(
  value : FixedJoinInputs,
  port : Int,
) -> FixedImport? {
  value.imports.get(port)
}

///|
pub fn validate_fixed_join_preflight(
  value : FixedJoinInputs,
) -> Result[@execution.FixedJoinValidation, @execution.RowIssue] {
  @execution.validate_fixed_join_inputs(
    value.query.owner,
    value.query.profile,
    value.inputs,
    value.validation_limits,
  )
}
