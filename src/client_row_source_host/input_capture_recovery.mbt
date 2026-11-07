///|
/// Current constructor policy DATA, shared by capture and private recovery.
pub fn row_input_acquisition_limits(
  value : RowInputAcquisition,
) -> RowInputLimits {
  value.preparation.limits
}

///|
/// Existing checked Source facts, invocation and exact input occurrence. This
/// private snapshot identity grants neither custody nor execution authority.
pub fn row_input_capture_identity(
  value : RowInputAcquisition,
) -> Array[String]? {
  let preparation = value.preparation
  let stage = @sourcequery.declaration(
      @sourcequery.mode_input(
        @sourcequery.source_acquisition_mode(preparation.original),
      ),
    ).stage_index
  let facts = @planning.query_source_evidence_fact_values(preparation.facts)
  let identity = [
    @context.program_identity_definition_cid(preparation.program),
    @context.program_identity_parameter_values_cid(preparation.program),
    stage.to_string(),
    preparation.input_index.to_string(),
    @sourcequery.source_acquisition_source_index(preparation.original).to_string(),
  ]
  for fact in facts {
    identity.push(fact)
  }
  Some(identity)
}

///|
pub fn export_row_input_original_read(
  acquisition : RowInputAcquisition,
  read : @execution.SuppliedRelationRead,
) -> Result[RowOriginalCaptureExport, RowOriginalCaptureIssue] {
  let preparation = acquisition.preparation
  if !@execution.supplied_relation_read_matches_input(
      read,
      preparation.owner,
      preparation.input_index,
    ) {
    return Err(InvalidBinding)
  }
  export_original_read_with_limits(
    read,
    preparation.limits.max_rows,
    preparation.limits.wire,
    row_input_capture_schema_limits(acquisition),
  )
}

///|
fn row_input_capture_schema_limits(
  value : RowInputAcquisition,
) -> @execution.RelationSchemaIdentityLimits {
  let wire = value.preparation.limits.wire
  {
    max_fields: wire.max_columns,
    max_bytes: wire.max_bytes,
    max_nodes: wire.max_nodes,
    max_depth: wire.max_depth,
  }
}

///|
pub fn restore_row_input_original_read(
  acquisition : RowInputAcquisition,
  schema_cid : String,
  rows_cid : String,
  rows : Array[String],
  available : () -> Bool,
  reference_issuer? : @admitted.ReferenceIssuer,
) -> Result[RowRestoredOriginalInput, RowOriginalCaptureIssue] {
  let preparation = acquisition.preparation
  let limits = preparation.limits
  restore_original_read_with_limits(
    preparation.owner,
    preparation.input_index,
    schema_cid,
    rows_cid,
    rows,
    limits.max_rows,
    limits.retention,
    limits.wire,
    row_input_capture_schema_limits(acquisition),
    available,
    reference_issuer?,
  )
}

///|
/// Reuse the original trusted Source Input port after row/schema verification.
/// The caller already reserved the receiving Source allocation on its Ledger.
pub fn restore_row_input_capture(
  acquisition : RowInputAcquisition,
  schema_cid : String,
  rows_cid : String,
  rows : Array[String],
  available : () -> Bool,
  reference_issuer? : @admitted.ReferenceIssuer,
) -> Result[
  (RowRestoredOriginalInput, @query.CapturedInputSource),
  RowOriginalCaptureIssue,
] {
  let original = match
    restore_row_input_original_read(
      acquisition,
      schema_cid,
      rows_cid,
      rows,
      available,
      reference_issuer?,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let preparation = acquisition.preparation
  let read = original.read
  let measured = match
    @execution.supplied_relation_read_rows_identity(
      read,
      preparation.limits.wire,
    ) {
    Ok(value) => value
    Err(issue) => {
      discard_failed_original_input(original.input)
      return Err(Wire(issue))
    }
  }
  let port = match
    @query.prepare_trusted_source_input_capture_port(
      preparation.contracts,
      preparation.sequence,
      preparation.original,
      preparation.program,
      preparation.limits.wire.max_columns,
      preparation.limits.wire.max_bytes,
      fn(proof : RowRestoredOriginalInput) {
        if physical_equal(proof, original) &&
          restored_row_original_read(proof) is Some(current) &&
          physical_equal(current, read) {
          Some((read, @execution.row_wire_usage(measured).0))
        } else {
          None
        }
      },
    ) {
    Ok(value) => value
    Err(_) => {
      discard_failed_original_input(original.input)
      return Err(Unavailable)
    }
  }
  match @query.capture_verified_source_input(port, original) {
    Ok(source) => Ok((original, source))
    Err(_) => {
      discard_failed_original_input(original.input)
      Err(Unavailable)
    }
  }
}

///|
/// Count the actual checked schema through the existing measuring codec.
/// Constructor ceilings remain validation policy, never reservation demand.
pub fn row_input_capture_schema_geometry(
  value : RowInputAcquisition,
) -> (Int, Int, Int, Int)? {
  @execution.measure_relation_schema_identity(
    value.preparation.schema,
    row_input_capture_schema_limits(value),
  )
  .to_option()
  .map(measured => {
    (value.preparation.columns.length(), measured.0, measured.1, measured.2)
  })
}
