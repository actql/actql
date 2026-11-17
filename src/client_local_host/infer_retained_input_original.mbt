///|
// Borrowed aliases of the SAME claimed Read. This tuple has no issuer, Ledger,
// cleanup authority or independent byte balance. Ref retains the actual grown
// prefix even when a receiving constructor fails after Resource admission.
pub type ClientInferOriginalInputRead = (
  @publication_host.ClientModelReadPreparation,
  @publication_host.ClientModelReadConsumer,
  @publication_host.ClientCompiledRun,
  @publication.PublicationContract,
  @publication_host.ClientInferPlanGraph,
  Ref[(Int64, Int64)],
)

///|
/// Same completed identity/export or saved descriptor observations. Quote all
/// coheld export strings, receiving parser/readmission/import values, mapping
/// cells and control arrays; no Task/row/token maximum is multiplied here.
pub fn client_infer_retained_input_construction_capacity(
  rows : Int,
  bytes : Int,
  nodes : Int,
  depth : Int,
  columns : Int,
  text : Int,
) -> @execution.ExecutionCapacity? {
  if rows < 0 ||
    bytes < 0 ||
    nodes < 0 ||
    depth < 0 ||
    columns < 0 ||
    text < 0 ||
    bytes > source_capture_wire().max_bytes ||
    nodes > source_capture_wire().max_nodes ||
    depth > source_capture_wire().max_depth ||
    columns > source_capture_wire().max_columns {
    return None
  }
  let b = Int64::max(1L, bytes.to_int64() + rows.to_int64() + 2L)
  let n = Int64::max(1L, nodes.to_int64() + rows.to_int64() + 1L)
  if b > 2147483647L || n > 2147483647L {
    return None
  }
  guard program_artifact_parse_layout((b.to_int(), n.to_int(), depth + 1))
    is Some(parse) &&
    @encode.text_writer_construction_inventory(
      b.to_int(),
      n.to_int(),
      depth + 1,
    )
    is Some(writer) &&
    @execution.preparation_array_representation(
      8L,
      8L * rows.to_int64() + 12L * columns.to_int64(),
      true,
    )
    is Some(arrays) &&
    @execution.compose_preparation_representation([
      // Retained decoded row, readmission/import copy and typed mapping roots
      // coexist. Their closed parser/canonical recipe uses actual node/depth
      // observations, never policy ceilings or a generic objects*nodes fee.
      parse.value,
      parse.value,
      parse.value,
      arrays,
      {
        record_headers: 32L + 2L * rows.to_int64() + 4L * columns.to_int64(),
        reference_slots: 64L +
        4L * rows.to_int64() +
        3L * rows.to_int64() * columns.to_int64(),
        scalar_words: 48L + 6L * columns.to_int64(),
        // Row String slices, JS snapshot originals and sealed/unsealed wire
        // frames. JSON quoting expands at most six units per observed unit.
        owned_utf16_units: 8L * b +
        6L * text.to_int64() +
        4L *
        (
          "versionregistry_cidvalues_contract_cidrows_cidoutput_stepinput_countcolumnsrowsbytesnodesdepthvaluesrun_definition_cidscope_cidinput_artifact_cidtask_indexstrategy_revision"
          .length()
          .to_int64() +
          9L * 71L +
          12L * 20L
        ),
        owned_wire_bytes: 2L * b,
      },
    ])
    is Some(retained) &&
    @execution.compose_preparation_representation([
      parse.temporary,
      {
        record_headers: writer.record_headers + 24L,
        reference_slots: writer.reference_slots + 48L,
        scalar_words: writer.scalar_words + 32L,
        owned_utf16_units: writer.owned_utf16_units,
        owned_wire_bytes: b,
      },
    ])
    is Some(scratch) &&
    @execution.preparation_representation_cost(retained) is Some(r) &&
    @execution.preparation_representation_cost(scratch) is Some(s) &&
    @execution.checked_preparation_add_product(r, s, 1L) is Some(e) else {
    return None
  }
  @execution.execution_capacity(r, e)
}

///|
/// Named, bound geometry is the production capacity entrance. The scalar
/// compatibility quote above remains DATA only and cannot issue readmission.
pub fn client_infer_retained_input_facts_capacity(
  facts : @execution.RetainedReadmissionFacts,
  bytes : Int,
  nodes : Int,
  depth : Int,
  text : Int,
) -> @execution.ExecutionCapacity? {
  guard client_infer_retained_input_construction_capacity(
      @execution.retained_readmission_rows(facts),
      bytes,
      nodes,
      depth,
      @execution.retained_readmission_schema_columns(facts),
      text,
    )
    is Some(base) &&
    @execution.preparation_array_representation(
      1L,
      @execution.retained_readmission_binding_entries(facts).to_int64(),
      true,
    )
    is Some(bindings) &&
    @execution.preparation_representation_cost(bindings) is Some(copy) &&
    // The existing materialization witness and exported input each retain
    // one immutable facts link; neither enlarges the facts identity domain.
    @execution.preparation_representation_cost({
      record_headers: 0L,
      reference_slots: 2L,
      scalar_words: 0L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(link) &&
    @execution.checked_preparation_add_product(copy, link, 1L) is Some(extra) &&
    @execution.checked_preparation_add_product(
      @execution.execution_capacity_retained_bytes(base),
      extra,
      1L,
    )
    is Some(r) &&
    @execution.checked_preparation_add_product(
      @execution.execution_capacity_execution_bytes(base),
      extra,
      1L,
    )
    is Some(e) else {
    return None
  }
  @execution.execution_capacity(r, e)
}

///|
// A real Resource grow, not the presence of a callback or a quoted scalar.
fn grow_original_infer_retained_input_span(
  original : ClientInferOriginalInputRead,
  next : @execution.ExecutionCapacity,
) -> (Int64, Int64)? {
  let (read, consumer, compiled, definition, plan, held) = original
  let (r, e) = match
    @publication_host.grow_client_model_read_preparation_consumer_span(
      read,
      consumer,
      compiled,
      definition,
      plan,
      @execution.execution_capacity_retained_bytes(next),
      @execution.execution_capacity_execution_bytes(next),
    ) {
    Err(_) => return None
    Ok(value) => value
  }
  held.val = (r, e)
  Some((r, e))
}

///|
fn grow_original_infer_retained_input(
  original : ClientInferOriginalInputRead,
  next : @execution.ExecutionCapacity,
) -> Bool {
  grow_original_infer_retained_input_span(original, next) is Some(_)
}

///|
/// Borrowed one-shot materialization DATA on an existing original Read. The
/// public type cannot be constructed or mutated by callers. Refs or quotes cannot
/// create or alter its exact input/required-prefix binding. Not another owner.
pub struct ClientInferInputMaterialization {
  mut input : @execution.CompletedOutput?
  mut facts : @execution.RetainedReadmissionFacts?
  mut original : ClientInferOriginalInputRead?
  retained : Int64
  execution : Int64
  artifact_cid : String
  task : Int
  revision : Int
  mut used : Bool
}

///|
/// Issue BEFORE handoff from the SAME completed input and emitter receipt.
/// Derive demand here, then add it to the actual Read token, not caller Ref0.
pub fn prepare_original_client_infer_input_materialization(
  original : ClientInferOriginalInputRead,
  occurrence : @publication_host.ClientInferOccurrence,
  scope : @publication_host.ClientInferCallScope,
  input : @execution.CompletedOutput,
  rows : @execution.PreparedInferRows,
  identity : @execution.CompletedRelationIdentityScan,
) -> Result[ClientInferInputMaterialization, ClientInferRetainedInputIssue] {
  let (read, consumer, compiled, definition, plan, _) = original
  guard @publication_host.client_model_input_materialization_matches(
      read, consumer, compiled, definition, plan, scope, rows, input,
    ) &&
    @publication_host.client_infer_occurrence_matches_compiled_run(
      occurrence, compiled,
    ) &&
    @publication_host.client_infer_occurrence_matches_plan(occurrence, plan) &&
    @publication_host.client_infer_call_scope_input(scope) is Some(same) &&
    physical_equal(same, input) &&
    @execution.completed_relation_identity_scan_body_receipt(identity)
    is Some(receipt) &&
    @execution.completed_relation_export_matches_output(receipt, input) &&
    @execution.completed_relation_identity_scan_body(identity, receipt)
    is Some(body) else {
    return Err(BindingMismatch)
  }
  // The SAME existing Read owns fixed fact/return controls before issuance.
  let control = @execution.retained_readmission_facts_control_bytes()
  guard @execution.execution_capacity(control, control) is Some(fixed) &&
    grow_original_infer_retained_input_span(original, fixed) is Some(_) else {
    return Err(CustodyUnavailable)
  }
  let facts = match @execution.retained_input_facts(input) {
    Ok(value) => value
    Err(_) => return Err(BindingMismatch)
  }
  let (count, bytes, nodes, depth, _) = @execution.completed_relation_export_scalar_geometry(
    receipt,
  )
  guard count == @execution.retained_readmission_rows(facts) &&
    client_infer_retained_input_facts_capacity(
      facts,
      bytes,
      nodes,
      depth,
      body.length(),
    )
    is Some(next) &&
    grow_original_infer_retained_input_span(original, next) is Some(required) else {
    return Err(CustodyUnavailable)
  }
  guard @publication_host.client_infer_call_scope_input(scope)
    is Some(still_input) &&
    physical_equal(still_input, input) &&
    @execution.completed_relation_export_matches_output(receipt, input) else {
    return Err(CustodyUnavailable)
  }
  // The issuer's frame/Some, immutable requirement and same-input links are
  // part of the existing fixed constructor controls in next, before allocation.
  let boundary = @publication_host.client_infer_plan_boundary(plan)
  Ok({
    input: Some(input),
    facts: Some(facts),
    original: Some(original),
    retained: required.0,
    execution: required.1,
    artifact_cid: @publication.run_evidence_value_identity(
      @publication_host.client_infer_call_scope_artifact(scope),
    ),
    task: boundary.0,
    revision: boundary.2,
    used: false,
  })
}

///|
fn original_fixed_input_binding_valid(
  binding : String,
  witness : ClientInferInputMaterialization,
  definition : @publication.PublicationContract,
) -> Bool {
  // Exact canonical fixed-binding grammar. Validate the fixed-width slot
  // directly: no generic JSON parser can construct an unrelated tree before
  // this small existing protocol's own control/String envelope is paid.
  let prefix = "{\"input_artifact_cid\":\"" +
    witness.artifact_cid +
    "\",\"run_definition_cid\":\"" +
    @publication.publication_contract_identity(definition) +
    "\",\"scope_cid\":\""
  let suffix = "\",\"strategy_revision\":" +
    witness.revision.to_string() +
    ",\"task_index\":" +
    witness.task.to_string() +
    ",\"version\":\"actql-model-fixed-input-binding/0.1\"}"
  if binding.length() != prefix.length() + 71 + suffix.length() ||
    !binding.has_prefix(prefix) ||
    !binding.has_suffix(suffix) {
    return false
  }
  let scope = binding[prefix.length():prefix.length() + 71].to_owned()
  if !scope.has_prefix("sha256:") {
    return false
  }
  for char in scope[7:].iter() {
    if !((char >= '0' && char <= '9') || (char >= 'a' && char <= 'f')) {
      return false
    }
  }
  true
}

///|
/// Exact already-prefunded input/Read only; this never grows after handoff.
pub fn export_original_client_infer_retained_input(
  input : @execution.CompletedOutput,
  binding : String,
  witness : ClientInferInputMaterialization,
) -> Result[ClientInferRetainedInputExport, ClientInferRetainedInputIssue] {
  if witness.used {
    return Err(CustodyUnavailable)
  }
  witness.used = true
  let original = witness.original
  let same = witness.input
  let facts = witness.facts
  // A spent/failed witness cannot retain a large original graph or be retried
  // under another binding. Actual Read cleanup/prefix remain with its owner.
  witness.original = None
  witness.input = None
  witness.facts = None
  guard same is Some(same) &&
    physical_equal(same, input) &&
    facts is Some(facts) &&
    original is Some((read, consumer, compiled, definition, plan, _)) else {
    return Err(BindingMismatch)
  }
  if !@publication_host.client_model_handed_off_preparation_capacity_available(
      read,
      consumer,
      compiled,
      definition,
      plan,
      witness.retained,
      witness.execution,
    ) {
    return Err(CustodyUnavailable)
  }
  if !original_fixed_input_binding_valid(binding, witness, definition) {
    return Err(BindingMismatch)
  }
  export_client_infer_retained_input_owned(
    input,
    binding,
    @execution.retained_readmission_rows(facts),
    facts=Some(facts),
  )
}

///|
/// Retire borrowed aliases only. This acknowledges no physical cleanup and
/// returns no capacity; the existing Read keeps its own prefix until cleanup.
pub fn retire_client_infer_input_materialization(
  value : ClientInferInputMaterialization,
) -> Unit {
  value.used = true
  value.original = None
  value.input = None
  value.facts = None
}
