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
  rows : Int, bytes : Int, nodes : Int, depth : Int, columns : Int,
  text : Int,
) -> @execution.ExecutionCapacity? {
  if rows < 0 || bytes < 0 || nodes < 0 || depth < 0 || columns < 0 || text < 0 ||
    bytes > source_capture_wire().max_bytes || nodes > source_capture_wire().max_nodes ||
    depth > source_capture_wire().max_depth || columns > source_capture_wire().max_columns {
    return None
  }
  let b = Int64::max(1L, bytes.to_int64() + rows.to_int64() + 2L)
  let n = Int64::max(1L, nodes.to_int64() + rows.to_int64() + 1L)
  if b > 2147483647L || n > 2147483647L { return None }
  guard program_artifact_parse_layout((b.to_int(), n.to_int(), depth + 1)) is Some(parse) &&
    @encode.text_writer_construction_inventory(b.to_int(), n.to_int(), depth + 1) is Some(writer) &&
    @execution.preparation_array_representation(8L, 8L * rows.to_int64() + 12L * columns.to_int64(), true) is Some(arrays) &&
    @execution.compose_preparation_representation([
      // Retained decoded row, readmission/import copy and typed mapping roots
      // coexist. Their closed parser/canonical recipe uses actual node/depth
      // observations, never policy ceilings or a generic objects*nodes fee.
      parse.value, parse.value, parse.value, arrays,
      {record_headers: 32L + 2L * rows.to_int64() + 4L * columns.to_int64(),
        reference_slots: 64L + 4L * rows.to_int64() + 3L * rows.to_int64() * columns.to_int64(),
        scalar_words: 48L + 6L * columns.to_int64(),
        // Row String slices, JS snapshot originals and sealed/unsealed wire
        // frames. JSON quoting expands at most six units per observed unit.
        owned_utf16_units: 8L * b + 6L * text.to_int64() +
          4L * ("versionregistry_cidvalues_contract_cidrows_cidoutput_stepinput_countcolumnsrowsbytesnodesdepthvaluesrun_definition_cidscope_cidinput_artifact_cidtask_indexstrategy_revision".length().to_int64() + 9L * 71L + 12L * 20L),
        owned_wire_bytes: 2L * b},
    ]) is Some(retained) &&
    @execution.compose_preparation_representation([
      parse.temporary,
      {record_headers: writer.record_headers + 24L,
        reference_slots: writer.reference_slots + 48L,
        scalar_words: writer.scalar_words + 32L,
        owned_utf16_units: writer.owned_utf16_units,
        owned_wire_bytes: b},
    ]) is Some(scratch) &&
    @execution.preparation_representation_cost(retained) is Some(r) &&
    @execution.preparation_representation_cost(scratch) is Some(s) &&
    @execution.checked_preparation_add_product(r, s, 1L) is Some(e) else {return None}
  @execution.execution_capacity(r, e)
}

///|
// A real Resource grow, not the presence of a callback or a quoted scalar.
fn grow_original_infer_retained_input(
  original : ClientInferOriginalInputRead,
  next : @execution.ExecutionCapacity,
) -> Bool {
  let (read, consumer, compiled, definition, plan, held) = original
  guard @execution.checked_preparation_add_product(held.val.0, @execution.execution_capacity_retained_bytes(next), 1L) is Some(r) &&
    @execution.checked_preparation_add_product(held.val.1, @execution.execution_capacity_execution_bytes(next), 1L) is Some(e) else {return false}
  if @publication_host.grow_client_model_read_preparation_consumer_capacity(read, consumer, compiled, definition, plan, r, e) is Err(_) {return false}
  held.val = (r, e)
  true
}

///|
/// The completed input and SAME handed-off Read already paid before Model
/// startup. This entrance never grows a ConsumerOwnedInputs/Ready reservation.
pub fn export_original_client_infer_retained_input(
  input : @execution.CompletedOutput,
  binding : String,
  original : ClientInferOriginalInputRead,
) -> Result[ClientInferRetainedInputExport, ClientInferRetainedInputIssue] {
  let (read, consumer, compiled, definition, plan, held) = original
  if !@publication_host.client_model_handed_off_preparation_capacity_available(read, consumer, compiled, definition, plan, held.val.0, held.val.1) {
    return Err(CustodyUnavailable)
  }
  export_client_infer_retained_input_owned(input, binding, @execution.completed_row_count(input))
}
