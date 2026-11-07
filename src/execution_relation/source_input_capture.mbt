///|
/// Trusted Source custody wiring only. The same immutable admitted input is
/// borrowed, without copying rows, running a prefix or manufacturing a Result.
/// The installed Source issuer must separately verify actual settled transport.
pub fn capture_supplied_source_input(
  contracts : RegisteredRelationContracts,
  sequence : @lower.PreparedSequence,
  read : SuppliedRelationRead,
  max_fields : Int,
  max_name_bytes : Int,
) -> Result[CompletedOutput, TrustedOutputIssue] {
  if max_fields < 0 || max_name_bytes < 0 {
    return Err(InvalidLimits)
  }
  let owner = @lower.sequence_owner(sequence)
  if !supplied_relation_read_matches_input(read, owner, read.input_index) {
    return Err(ForeignInputs)
  }
  let schema = read.rows.schema
  let count = @schema.field_count(schema)
  if count > max_fields {
    return Err(Limit)
  }
  let mut remaining = max_name_bytes
  let names = []
  for column in 0..<count {
    let name = @schema.field_reference_name(
      @schema.field_at(schema, column).unwrap(),
    )
    match @scalar.admit_utf8_length(name, remaining) {
      Ok(size) => remaining -= size
      Err(_) => return Err(Limit)
    }
    names.push(name)
  }
  guard @lower.input_id(@lower.bound_preparation(owner), read.input_index)
    is Some(id) &&
    supplied_relation_read_available(read) else {
    return Err(ForeignInputs)
  }
  let table = if @schema.all_fields_required(schema) {
    CompletedTable::AdmittedTable({ owner, id, names, rows: read.rows.rows, })
  } else {
    CompletedTable::PresenceTable({
      owner,
      id,
      names,
      rows: read.rows.presence_rows,
    })
  }
  let target = @pipeline.Input(read.input_index)
  let completion : CompletedSequence = {
    result_identity: Ref(()),
    // Imported input evidence may supply a consumer. It cannot complete any
    // pending Compute task, including a zero-operation authored Stage.
    readmitted: true,
    serialization_output: None,
    contracts,
    sequence,
    store: ImportedStore(
      @lower.preparation_input_count(@lower.bound_preparation(owner)),
      target,
      table,
    ),
    _producer_inputs: [],
    input_bindings: [read.identity],
    live: Some(fn() { supplied_relation_read_available(read) }),
  }
  Ok({ completion, target, table: Some(table), representation: None, })
}

///|
/// Original input occurrence, not equality of rows or input coordinates.
pub fn completed_source_input_matches_read(
  output : CompletedOutput,
  read : SuppliedRelationRead,
) -> Bool {
  output.completion.readmitted &&
  completed_output_matches_port(
    output,
    read.receiver,
    @pipeline.Input(read.input_index),
  ) &&
  supplied_relation_read_available(read) &&
  output.completion.input_bindings.length() == 1 &&
  physical_equal(output.completion.input_bindings[0], read.identity)
}

///|
/// A checked consumer borrows the same original Source input. This is separate
/// from binding a completed Step, and creates neither a synthetic Step nor an
/// execution-success claim for the input's enclosing Stage.
pub fn bind_completed_source_input_operation(
  receiver : @lower.BoundPrepared,
  consumer_step : Int,
  edge : Int,
  output : CompletedOutput,
  read : SuppliedRelationRead,
) -> Result[BoundProducerInput, ProducerBindingIssue] {
  if !completed_source_input_matches_read(output, read) {
    return Err(ProducerUnavailable)
  }
  if !supplied_relation_read_matches_operation_input(
      read, receiver, consumer_step, edge,
    ) {
    return Err(ProducerBindingMismatch)
  }
  let input_index = match
    @lower.node_at(@lower.bound_preparation(receiver), consumer_step) {
    Some(node) =>
      match @lower.node_input_target(node, edge) {
        Some(@pipeline.Input(index)) => index
        _ => return Err(ProducerBindingMismatch)
      }
    None => return Err(ProducerBindingMismatch)
  }
  Ok({
    identity: { input_index, carrier: None, supplied: Some(read.rows), },
    receiver,
    consumer_step: None,
    input_index,
    output,
    projection: None,
  })
}

///|
/// Identity export of the exact imported Source input. Ordinary completed
/// Result export keeps its existing output-target gate. This entry requires
/// the same live native read and does not make that input a completed task.
pub fn prepare_completed_source_input_relation_export(
  output : CompletedOutput,
  read : SuppliedRelationRead,
  max_rows : Int,
  values : ValueLimits,
  payload_wire : RowWireLimits,
  logical_wire : RowWireLimits,
  schema_limits : RelationSchemaIdentityLimits,
  max_batch_bytes : Int,
) -> Result[CompletedOutputExport, CompletedExportIssue] {
  if !completed_source_input_matches_read(output, read) {
    return Err(Unavailable)
  }
  prepare_completed_export_rows(
    output,
    completed_output_export_rows(output),
    max_rows,
    values,
    payload_wire,
    Some(logical_wire),
    Some(schema_limits),
    max_batch_bytes,
  )
}
