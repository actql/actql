///|
/// Trusted Host wiring, not a Connector registration or Program capability.
/// The verifier must return only exact retained material from successful live
/// execution evidence. Creating this port is part of the Host's trusted base.
/// Provider-facing entry points must install their verifier internally.
/// Verification is synchronous and side-effect-free, including repeated checks.
struct TrustedOutputPort[P] {
  generated : CompletionPreparation
  target : @pipeline.Target
  id : String
  names : Array[String]
  verify : (P) -> AdmittedOutputRows?
  input_bindings : Array[ProducerBindingIdentity]
}

///|
/// One exact trusted input used to establish Relation output provenance.
/// Carrier references retain only their checked use-site binding and current
/// availability; this value does not expose the underlying family storage.
struct TrustedOutputInput {
  value : TrustedOutputInputValue
}

///|
priv enum TrustedOutputInputValue {
  RelationInput(ProducerRead)
  SuppliedRelationInput(SuppliedRelationRead)
  CarrierInput(@managed_carrier.ProducerReadReference)
}

///|
pub fn trusted_output_relation_input(
  input : ProducerRead,
) -> TrustedOutputInput {
  { value: RelationInput(input), }
}

///|
pub fn trusted_output_supplied_relation_input(
  input : SuppliedRelationRead,
) -> TrustedOutputInput {
  { value: SuppliedRelationInput(input), }
}

///|
pub fn trusted_output_carrier_input(
  input : @managed_carrier.ProducerReadReference,
) -> TrustedOutputInput {
  { value: CarrierInput(input), }
}

///|
pub(all) enum TrustedOutputIssue {
  InvalidLimits
  Limit
  InvalidTarget
  NotRetained
  Unverified
  ForeignOutput
  ForeignInputs
} derive(Eq, Debug)

///|
/// A low-level trusted-runtime API, deliberately not a raw-data completion
/// constructor. Do not expose verifier installation through untrusted exports.
/// Fixed-input Compute supplies its exact receiving ports; Acquisition omits
/// them and does not claim fixed-input provenance. The saved identities retain
/// neither input rows nor a liveness callback to an upstream result. The installed
/// verifier must still validate live inputs before sealing successful output.
pub fn[P] prepare_trusted_output_port(
  generated : CompletionPreparation,
  target : @pipeline.Target,
  max_entries : Int,
  max_name_bytes : Int,
  verify : (P) -> AdmittedOutputRows?,
  inputs? : Array[ProducerRead],
) -> Result[TrustedOutputPort[P], TrustedOutputIssue] {
  let (id, names, input_bindings) = match
    validate_trusted_output_contract(
      generated, target, max_entries, max_name_bytes, inputs,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ generated, target, id, names, verify, input_bindings, })
}

///|
/// Carrier-aware trusted output construction. Every supplied use site must
/// match its exact external input position and remain available at admission.
pub fn[P] prepare_trusted_output_port_with_inputs(
  generated : CompletionPreparation,
  target : @pipeline.Target,
  max_entries : Int,
  max_name_bytes : Int,
  verify : (P) -> AdmittedOutputRows?,
  inputs? : Array[TrustedOutputInput],
) -> Result[TrustedOutputPort[P], TrustedOutputIssue] {
  let (id, names, input_bindings) = match
    validate_trusted_output_contract_with_inputs(
      generated, target, max_entries, max_name_bytes, inputs,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ generated, target, id, names, verify, input_bindings, })
}

///|
fn validate_trusted_output_contract(
  generated : CompletionPreparation,
  target : @pipeline.Target,
  max_entries : Int,
  max_name_bytes : Int,
  inputs : Array[ProducerRead]?,
) -> Result[
  (String, Array[String], Array[ProducerBindingIdentity]),
  TrustedOutputIssue,
] {
  validate_trusted_output_contract_with_inputs(
    generated,
    target,
    max_entries,
    max_name_bytes,
    inputs.map(values => values.map(trusted_output_relation_input)),
  )
}

///|
fn validate_trusted_output_contract_with_inputs(
  generated : CompletionPreparation,
  target : @pipeline.Target,
  max_entries : Int,
  max_name_bytes : Int,
  inputs : Array[TrustedOutputInput]?,
) -> Result[
  (String, Array[String], Array[ProducerBindingIdentity]),
  TrustedOutputIssue,
] {
  if max_entries < 0 || max_name_bytes < 0 {
    return Err(InvalidLimits)
  }
  let owner = completion_preparation_owner(generated)
  let prepared = @lower.bound_preparation(owner)
  let input_bindings = []
  if inputs is Some(inputs) {
    if inputs.length() > max_entries {
      return Err(Limit)
    }
    let expected_input_count = match generated.selected_step {
      Some(step) =>
        @lower.node_at(prepared, step)
        .map(node => @lower.node_input_count(node))
        .unwrap_or(-1)
      None => @lower.preparation_input_count(prepared)
    }
    if inputs.length() != expected_input_count {
      return Err(ForeignInputs)
    }
    for index, input in inputs {
      match input.value {
        RelationInput(input) => {
          let exact = match generated.selected_step {
            Some(step) =>
              producer_read_matches_operation_input(input, owner, step, index)
            None =>
              physical_equal(input.bound.receiver, owner) &&
              input.bound.input_index == index &&
              producer_read_available(input)
          }
          if !exact {
            return Err(ForeignInputs)
          }
          input_bindings.push(input.bound.identity)
        }
        SuppliedRelationInput(input) => {
          let exact = match generated.selected_step {
            Some(step) =>
              supplied_relation_read_matches_operation_input(
                input, owner, step, index,
              )
            None => supplied_relation_read_matches_input(input, owner, index)
          }
          if !exact {
            return Err(ForeignInputs)
          }
          input_bindings.push(supplied_relation_read_identity(input))
        }
        CarrierInput(input) => {
          let exact = match generated.selected_step {
            Some(step) =>
              @managed_carrier.producer_read_reference_matches_operation_input(
                input, owner, step, index,
              )
            None =>
              @managed_carrier.producer_read_reference_matches_input(
                input, owner, index,
              )
          }
          if !exact {
            return Err(ForeignInputs)
          }
          input_bindings.push({
            input_index: index,
            carrier: Some(input),
            supplied: None,
          })
        }
      }
    }
  }
  guard target is Step(index) &&
    index == completion_preparation_terminal_step(generated) &&
    @lower.node_at(prepared, index) is Some(node) &&
    @lower.preparation_schema_at(prepared, target) is Some(schema) else {
    return Err(InvalidTarget)
  }
  // This bridge publishes only the completed final target, never intermediate
  // operations for which a backend's success evidence may provide no material.
  if generated.retained_ids.length() != 1 {
    return Err(NotRetained)
  }
  let id = @lower.node_id(node)
  let mut bytes = max_name_bytes
  for name in [id, generated.retained_ids[0]] {
    match @scalar.admit_utf8_length(name, bytes) {
      Ok(size) => bytes -= size
      Err(_) => return Err(Limit)
    }
  }
  if generated.retained_ids[0] != id {
    return Err(NotRetained)
  }
  let width = @schema.field_count(schema)
  if width > max_entries {
    return Err(Limit)
  }
  let names = []
  for column in 0..<width {
    let name = @schema.reference_name(
      @schema.field_at(schema, column).unwrap().name,
    )
    match @scalar.admit_utf8_length(name, bytes) {
      Ok(size) => bytes -= size
      Err(_) => return Err(Limit)
    }
    names.push(name)
  }
  Ok((id, names, input_bindings))
}

///|
/// Evidence selects the retained data through the installed verifier. Neither
/// caller-supplied rows nor a boolean can substitute for that relationship.
pub fn[P] complete_trusted_output(
  port : TrustedOutputPort[P],
  proof : P,
) -> Result[CompletedOutput, TrustedOutputIssue] {
  guard (port.verify)(proof) is Some(rows) else { return Err(Unverified) }
  let owner = completion_preparation_owner(port.generated)
  if !physical_equal(rows.owner, owner) || rows.target != port.target {
    return Err(ForeignOutput)
  }
  let prepared = @lower.bound_preparation(owner)
  guard @lower.preparation_schema_at(prepared, port.target) is Some(schema) &&
    physical_equal(schema, rows.schema) else {
    return Err(ForeignOutput)
  }
  let table = if @schema.all_fields_required(rows.schema) {
    CompletedTable::AdmittedTable({
      owner,
      id: port.id,
      names: port.names,
      rows: rows.rows,
    })
  } else {
    CompletedTable::PresenceTable({
      owner,
      id: port.id,
      names: port.names,
      rows: rows.presence_rows,
    })
  }
  let live = fn() {
    match (port.verify)(proof) {
      Some(current) => physical_equal(current, rows)
      None => false
    }
  }
  let completion : CompletedSequence = {
    result_identity: Ref(()),
    readmitted: false,
    contracts: port.generated.contracts,
    sequence: port.generated.sequence,
    store: ImportedStore(
      @lower.preparation_input_count(prepared),
      port.target,
      table,
    ),
    _producer_inputs: [],
    input_bindings: port.input_bindings,
    live: Some(live),
  }
  Ok({
    completion,
    target: port.target,
    table: Some(table),
    representation: None,
  })
}

///|
fn completion_is_live(completion : CompletedSequence) -> Bool {
  match completion.live {
    None => true
    Some(check) => check()
  }
}
