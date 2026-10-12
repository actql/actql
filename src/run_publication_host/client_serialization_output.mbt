///|
pub(all) enum ClientSerializationOutputIssue {
  GenerationIncomplete
  ForeignReference
  InputUnavailable
  OutputUnavailable
  InvalidLimits
  InvalidSchema
  Admission(@execution.CaptureIssue)
  Completion(@execution.TrustedOutputIssue)
}

///|
/// Join exact whole-input generation and an already issued opaque reference to
/// the original checked Serialize target. No caller rows, replacement Program,
/// issuer installation or fabricated execution boolean can enter this output.
/// The installing driver retains physical byte custody and its existing output
/// lifetime; this function does not create another cleanup or accounting owner.
pub fn complete_client_serialization_output(
  input : ClientSerializationInput,
  candidate : @publication.GeneratedContentReference,
  content : @values.CheckedValue,
  available : () -> Bool,
  limits : @execution.ValueLimits,
  max_name_bytes : Int,
) -> Result[@execution.CompletedOutput, ClientSerializationOutputIssue] {
  if limits.max_nodes <= 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_depth < 0 ||
    limits.max_work <= 0 ||
    max_name_bytes < 0 {
    return Err(InvalidLimits)
  }
  guard @publication.generated_content_reference_completion_for(
      candidate,
      input.encoder,
    )
    is Some(generated) &&
    generated.row_count == input.rows else {
    return Err(GenerationIncomplete)
  }
  guard content.value is @values.Reference(reference) &&
    @values.reference_available(reference) &&
    @values.reference_identity_cid(reference) ==
    @publication.generated_content_reference_identity(candidate) &&
    @values.reference_wire(reference) ==
    @publication.generated_content_reference_wire(candidate) else {
    return Err(ForeignReference)
  }
  if !available() {
    return Err(OutputUnavailable)
  }
  guard @execution.prepare_serialization_completion(input.input, input.barrier)
    is Some(preparation) else {
    return Err(InputUnavailable)
  }
  let owner = @lower.serialization_owner(input.barrier)
  let target = @pipeline.Step(@lower.serialization_step(input.barrier))
  guard @lower.preparation_schema_at(@lower.bound_preparation(owner), target)
    is Some(schema) &&
    @schema.field_count(schema) == 5 &&
    @schema.all_fields_required(schema) else {
    return Err(InvalidSchema)
  }
  // Schema indices are canonical UTF-16 order, not the public Result's
  // declared projection order. Bind each scalar by its original field name.
  for
    index, name in ["content", "media_type", "name", "row_count", "size_bytes"] {
    if @schema.field_reference_name_at(schema, index) != Some(name) {
      return Err(InvalidSchema)
    }
  }
  let stream = match
    @execution.prepare_admitted_output(owner, target, 1, limits) {
    Ok(value) => value
    Err(issue) => return Err(Admission(issue))
  }
  // Issuance and the checked output schema have distinct contract objects.
  // Validate the same opaque Ref under the exact destination contract; never
  // reissue it or parse its envelope to manufacture authority. A Reference is
  // one immutable value node, so reserve its recheck work before validation.
  if !@execution.admitted_output_charge_control_work(stream, 1) {
    @execution.cancel_admitted_output(stream) |> ignore
    return Err(Admission(@execution.CaptureLimit))
  }
  let values : Array[@values.CheckedValue] = []
  for index in 0..<5 {
    let contract = @schema.field_contract(
      @schema.field_at(schema, index).unwrap(),
    )
    let value = match index {
      0 =>
        @values.recheck_runtime_value(content.value, contract, {
          max_nodes: 1,
          max_text_bytes: 0,
          max_depth: 0,
        })
      1 => @values.checked_text_value(generated.media_type, contract)
      2 => @values.checked_text_value(generated.name, contract)
      3 =>
        @values.checked_number_value(
          generated.row_count.to_double(),
          contract,
        )
      _ =>
        @values.checked_number_value(
          generated.size_bytes.to_double(),
          contract,
        )
    }
    guard value is Some(value) else {
      @execution.cancel_admitted_output(stream) |> ignore
      return Err(InvalidSchema)
    }
    values.push(value)
  }
  match @execution.append_admitted_output(stream, values) {
    Ok(_) => ()
    Err(issue) => {
      @execution.cancel_admitted_output(stream) |> ignore
      return Err(Admission(issue))
    }
  }
  let rows = match @execution.finish_admitted_output(stream) {
    Ok(value) => value
    Err(issue) => {
      @execution.cancel_admitted_output(stream) |> ignore
      return Err(Admission(issue))
    }
  }
  let port = match
    @execution.prepare_trusted_output_port(
      preparation,
      target,
      5,
      max_name_bytes,
      fn(_ : Unit) {
        if available() && @values.reference_available(reference) {
          Some(rows)
        } else {
          None
        }
      },
    ) {
    Ok(value) => value
    Err(issue) => return Err(Completion(issue))
  }
  @execution.complete_trusted_output(port, ()).map_err(issue => {
    Completion(issue)
  })
}
