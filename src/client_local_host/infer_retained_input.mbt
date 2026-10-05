///|
/// A bounded view of the exact pre-INFER completion. Exported bytes describe
/// the completed occurrence but do not prove durable Store custody.
pub struct ClientInferRetainedInputExport {
  input : @execution.CompletedOutput
  evidence : @execution.RetainedCompletionEvidence
  binding : String
  descriptor_wire : String
  rows : Array[String]
}

///|
/// The receiving instance borrows authenticated durable custody. Reclaiming
/// it revokes local consumers without deleting any retained Store original.
priv struct ClientInferRetainedInput {
  output : @execution.CompletedOutput
  live : Ref[Bool]
}

///|
pub(all) enum ClientInferRetainedInputIssue {
  BindingMismatch
  InvalidDescriptor
  CustodyUnavailable
  Export(@execution.CompletedExportIssue)
  Evidence(@execution.RetainedCompletionEvidenceIssue)
  Content(@execution.RetainedContentReadIssue)
  Readmission(@execution.TrustedOutputIssue)
  Import(@execution.CompletedImportIssue)
}

///|
fn infer_retained_descriptor_wire(
  value : @execution.RetainedCompletionDescriptor,
) -> String? {
  let document : Json = {
    "version": "actql-host-model-input-completion/0.1",
    "registry_cid": value.registry_cid,
    "values_contract_cid": value.values_contract_cid,
    "rows_cid": value.rows_cid,
    "output_step": value.output_step,
    "input_count": value.input_count,
    "columns": value.columns,
    "rows": value.rows,
    "bytes": value.bytes,
    "nodes": value.nodes,
    "depth": value.depth,
    "values": {
      "nodes": value.values.nodes,
      "text_bytes": value.values.text_bytes,
      "work": value.values.work,
    },
  }
  let canonical = @identity.from_json(document, 128, 8, 8192) catch {
    _ => return None
  }
  Some(@identity.stringify_value(canonical, 8192, 128, 8)) catch {
    _ => None
  }
}

///|
pub fn read_client_infer_retained_input_descriptor(
  wire : String,
) -> Result[
  @execution.RetainedCompletionDescriptor,
  ClientInferRetainedInputIssue,
] {
  if wire.length() > 8192 {
    return Err(InvalidDescriptor)
  }
  let value = @identity.from_json(@json.parse(wire), 128, 8, 8192) catch {
    _ => return Err(InvalidDescriptor)
  }
  guard @identity.object_field_count(value) == Some(12) &&
    @identity.object_field(value, "version")
    is Some(String("actql-host-model-input-completion/0.1")) &&
    source_capture_descriptor_cid(value, "registry_cid") is Some(registry_cid) &&
    source_capture_descriptor_cid(value, "values_contract_cid")
    is Some(values_contract_cid) &&
    source_capture_descriptor_cid(value, "rows_cid") is Some(rows_cid) &&
    source_capture_descriptor_number(value, "output_step") is Some(output_step) &&
    source_capture_descriptor_number(value, "input_count") is Some(input_count) &&
    source_capture_descriptor_number(value, "columns") is Some(columns) &&
    source_capture_descriptor_number(value, "rows") is Some(rows) &&
    source_capture_descriptor_number(value, "bytes") is Some(bytes) &&
    source_capture_descriptor_number(value, "nodes") is Some(nodes) &&
    source_capture_descriptor_number(value, "depth") is Some(depth) &&
    @identity.object_field(value, "values") is Some(values) &&
    @identity.object_field_count(values) == Some(3) &&
    source_capture_descriptor_number(values, "nodes") is Some(value_nodes) &&
    source_capture_descriptor_number(values, "text_bytes") is Some(text_bytes) &&
    source_capture_descriptor_number(values, "work") is Some(work) else {
    return Err(InvalidDescriptor)
  }
  let descriptor : @execution.RetainedCompletionDescriptor = {
    registry_cid,
    values_contract_cid,
    rows_cid,
    output_step,
    input_count,
    columns,
    rows,
    bytes,
    nodes,
    depth,
    values: { nodes: value_nodes, text_bytes, work, },
  }
  if infer_retained_descriptor_wire(descriptor) != Some(wire) {
    return Err(InvalidDescriptor)
  }
  Ok(descriptor)
}

///|
/// Conversion of a live completion issued by the existing execution owner.
/// A complete export receipt and retained-completion evidence are both kept;
/// descriptor or content equality cannot recreate this live export token.
pub fn export_client_infer_retained_input(
  input : @execution.CompletedOutput,
  binding : String,
) -> Result[ClientInferRetainedInputExport, ClientInferRetainedInputIssue] {
  if binding.is_empty() || binding.length() > 262144 {
    return Err(BindingMismatch)
  }
  let stream = match
    @execution.prepare_completed_output_export(
      input,
      100,
      source_capture_values(),
      source_capture_wire(),
      1000000,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Export(issue))
  }
  let rows : Array[String] = []
  while true {
    match
      @execution.next_completed_output_export_canonical_row(
        stream, 100000, 100, 1000000,
      ) {
      Ok(Some((_, batch, _))) => rows.push(batch[1:].to_owned())
      Ok(None) => break
      Err(issue) => {
        @execution.cancel_completed_output_export(stream)
        return Err(Export(issue))
      }
    }
  }
  let (receipt, _) = match @execution.finish_completed_output_export(stream) {
    Ok(value) => value
    Err(issue) => {
      @execution.cancel_completed_output_export(stream)
      return Err(Export(issue))
    }
  }
  let handle = @execution.retain_admitted_output_stream(
    @execution.completed_export_content(receipt),
    (),
    fn() { @execution.completed_output_available(input) },
  )
  let retained = match
    @execution.bind_completed_output_export(
      receipt,
      @execution.retained_output_material(handle),
    ) {
    Ok(value) => value
    Err(issue) => {
      @execution.cancel_completed_export_receipt(receipt)
      return Err(Export(issue))
    }
  }
  let evidence = match
    @execution.retain_completion_evidence(retained, 100, 100) {
    Ok(value) => value
    Err(issue) => return Err(Evidence(issue))
  }
  guard infer_retained_descriptor_wire(
      @execution.retained_completion_descriptor(evidence),
    )
    is Some(descriptor_wire) else {
    return Err(InvalidDescriptor)
  }
  Ok({ input, evidence, binding, descriptor_wire, rows, })
}

///|
pub fn client_infer_retained_input_export_matches(
  value : ClientInferRetainedInputExport,
  input : @execution.CompletedOutput,
) -> Bool {
  physical_equal(value.input, input) &&
  @execution.completed_output_available(input) &&
  @execution.retained_completion_matches_output(value.evidence, input)
}

///|
pub fn client_infer_retained_input_export_binding(
  value : ClientInferRetainedInputExport,
) -> String {
  value.binding
}

///|
pub fn client_infer_retained_input_export_descriptor(
  value : ClientInferRetainedInputExport,
) -> String {
  value.descriptor_wire
}

///|
pub fn client_infer_retained_input_export_rows(
  value : ClientInferRetainedInputExport,
) -> Array[String] {
  value.rows.copy()
}

///|
/// Readmission consumes exact stored bytes under a Host-authenticated original
/// Run/scope/input binding. The trusted callback must keep that Store custody
/// available; it is not supplied by a Program or by a provider response.
fn restore_client_infer_retained_input(
  sequence : @execution.GeneratedSequence,
  infer_step : Int,
  expected_binding : String,
  saved_binding : String,
  descriptor_wire : String,
  supplied_rows : Array[String],
  custody_available : () -> Bool,
) -> Result[ClientInferRetainedInput, ClientInferRetainedInputIssue] {
  let descriptor = match
    read_client_infer_retained_input_descriptor(descriptor_wire) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let owner = @execution.generated_sequence_owner(sequence)
  if expected_binding.is_empty() ||
    expected_binding.length() > 262144 ||
    expected_binding != saved_binding ||
    supplied_rows.length() > 100 ||
    descriptor.rows != supplied_rows.length() ||
    descriptor.output_step != infer_step - 1 {
    return Err(BindingMismatch)
  }
  guard @lower.node_at(@lower.bound_preparation(owner), infer_step)
    is Some(node) &&
    @lower.payload(node) is @lower.Infer(_) &&
    @lower.node_input_target(node, 0) ==
    Some(@pipeline.Step(descriptor.output_step)) else {
    return Err(BindingMismatch)
  }
  if !custody_available() {
    return Err(CustodyUnavailable)
  }
  let rows = supplied_rows.copy()
  let preparation = @execution.generated_completion_preparation(sequence)
  let reader = match
    @execution.prepare_retained_content_read(
      preparation,
      descriptor,
      100,
      source_capture_values(),
      source_capture_wire(),
      1000000,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Content(issue))
  }
  for row in rows {
    if !custody_available() {
      @execution.cancel_retained_content_read(reader) |> ignore
      return Err(CustodyUnavailable)
    }
    match
      @execution.append_retained_content_read(
        reader,
        row,
        source_capture_decode(),
      ) {
      Ok(_) => ()
      Err(issue) => {
        @execution.cancel_retained_content_read(reader) |> ignore
        return Err(Content(issue))
      }
    }
  }
  let receipt = match @execution.finish_retained_content_read(reader) {
    Ok(value) => value
    Err(issue) => return Err(Content(issue))
  }
  let live = Ref(true)
  let available = fn() { live.val && custody_available() }
  let held = @execution.retain_admitted_output_stream(receipt, (), available)
  let material = @execution.retained_output_material(held)
  let port = match
    @execution.prepare_trusted_retained_readmission(
      preparation,
      descriptor,
      100,
      10000,
      fn(proof : @execution.AdmittedOutputStreamReceipt) {
        if available() &&
          physical_equal(proof, receipt) &&
          @execution.retained_output_matches_receipt(material, proof) {
          Some(material)
        } else {
          None
        }
      },
    ) {
    Ok(value) => value
    Err(issue) => return Err(Readmission(issue))
  }
  let restored = match
    @execution.readmit_trusted_retained_output(port, receipt) {
    Ok(value) => value
    Err(issue) => return Err(Readmission(issue))
  }
  let importing = match
    @execution.prepare_completed_output_import(
      restored,
      100,
      source_capture_values(),
      source_capture_wire(),
      1000000,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Import(issue))
  }
  for row in rows {
    if !available() {
      @execution.cancel_completed_output_import(importing) |> ignore
      return Err(CustodyUnavailable)
    }
    match
      @execution.append_completed_output_import_wire(
        importing,
        row,
        source_capture_decode(),
      ) {
      Ok(_) => ()
      Err(issue) => {
        @execution.cancel_completed_output_import(importing) |> ignore
        return Err(Import(issue))
      }
    }
  }
  let output = match @execution.finish_completed_output_import(importing) {
    Ok(value) => value
    Err(issue) => return Err(Import(issue))
  }
  if !available() {
    return Err(CustodyUnavailable)
  }
  Ok({ output, live, })
}

///|
fn close_client_infer_retained_input(value : ClientInferRetainedInput) -> Bool {
  let was_live = value.live.val
  value.live.val = false
  was_live
}

///|
/// Prepare only the checked sequence, then restore its original completed
/// prefix. No Local execution, Source open, or model invocation occurs here.
pub fn start_client_restored_infer_input(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
  step : Int,
  registry_body : String,
  values_body : String,
  expected_binding : String,
  saved_binding : String,
  descriptor_wire : String,
  rows : Array[String],
  custody_available : () -> Bool,
  execution : @execution.SequenceExecutionLimits,
  mapping : @execution.InferPreparationLimits,
  fragment_body? : String? = None,
  ordered_body? : String? = None,
) -> Result[ClientInferInputExecution, ClientInferInputIssue] {
  if execution.max_work < 0 ||
    mapping.max_work < 0 ||
    rows.length() > execution.rows.max_rows {
    return Err(InvalidLimits)
  }
  guard prepare_client_infer_prefix(
      prepared,
      task,
      step,
      registry_body,
      values_body,
      fragment_body~,
      ordered_body~,
    )
    is Some(sequence) else {
    return Err(UnsupportedProgram)
  }
  start_client_restored_infer_input_sequence(
    sequence, step, expected_binding, saved_binding, descriptor_wire, rows, custody_available,
    mapping,
  )
}

///|
/// The composed caller supplies its original checked prefix, not a freshly
/// evaluated substitute. Its actual restored input still uses the same mapper.
pub fn start_client_restored_composed_infer_input(
  occurrence : @publication_host.ClientInferOccurrence,
  sequence : @execution.GeneratedSequence,
  expected_binding : String,
  saved_binding : String,
  descriptor_wire : String,
  rows : Array[String],
  custody_available : () -> Bool,
  execution : @execution.SequenceExecutionLimits,
  mapping : @execution.InferPreparationLimits,
) -> Result[ClientInferInputExecution, ClientInferInputIssue] {
  let (_, _, step) = @publication_host.client_infer_occurrence_coordinates(
    occurrence,
  )
  if execution.max_work < 0 ||
    mapping.max_work < 0 ||
    rows.length() > execution.rows.max_rows ||
    !physical_equal(
      @publication_host.client_infer_occurrence_preparation(occurrence),
      @execution.generated_sequence_owner(sequence),
    ) ||
    @execution.generated_sequence_step_count(sequence) != step {
    return Err(UnsupportedProgram)
  }
  for index in 0..<step {
    if @execution.generated_sequence_step_index_at(sequence, index) !=
      Some(index) {
      return Err(UnsupportedProgram)
    }
  }
  start_client_restored_infer_input_sequence(
    sequence, step, expected_binding, saved_binding, descriptor_wire, rows, custody_available,
    mapping,
  )
}

///|
fn start_client_restored_infer_input_sequence(
  sequence : @execution.GeneratedSequence,
  step : Int,
  expected_binding : String,
  saved_binding : String,
  descriptor_wire : String,
  rows : Array[String],
  custody_available : () -> Bool,
  limits : @execution.InferPreparationLimits,
) -> Result[ClientInferInputExecution, ClientInferInputIssue] {
  let owner = @execution.generated_sequence_owner(sequence)
  guard @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.payload(node) is @lower.Infer(infer) &&
    @lower.node_input_target(node, 0) is Some(target) else {
    return Err(UnsupportedProgram)
  }
  let expressions = match
    @lower.prepare_infer_inputs(
      infer,
      @lower.parameter_bindings(owner),
      @publication_host.client_standard_values_sequence_limits().expressions,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Preparation(issue))
  }
  let retained = match
    restore_client_infer_retained_input(
      sequence, step, expected_binding, saved_binding, descriptor_wire, rows, custody_available,
    ) {
    Ok(value) => value
    Err(issue) => return Err(RetainedInput(issue))
  }
  let bound = match
    @execution.bind_infer_completed_input(
      expressions,
      owner,
      target,
      retained.output,
    ) {
    Ok(value) => value
    Err(issue) => {
      close_client_infer_retained_input(retained) |> ignore
      return Err(Mapping(issue))
    }
  }
  let control = @bounded.control()
  let mapping = match
    @execution.start_infer_rows_preparation(control, bound, limits) {
    Ok(value) => value
    Err(issue) => {
      close_client_infer_retained_input(retained) |> ignore
      return Err(Mapping(issue))
    }
  }
  Ok({
    prefix: None,
    retained_input: Some(retained),
    sequence,
    infer_step: step,
    owner,
    target,
    expressions,
    limits,
    control,
    mapping: Some(mapping),
    rows: None,
    completed_input: Some(retained.output),
    prefix_done: true,
    stopped: false,
    cancelled: false,
    reclaimed: false,
    work: 0L,
  })
}
