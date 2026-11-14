///|
// Constructor DATA on the SAME Request, not another Resource or input issuer.
priv struct ClientRequestHttpInput {
  base : (Int64, Int64)
  mut wire : Int
  mut chunks : Int
  mut json_attempted : Bool
  mut work : @resources.PreparationPhaseWork64?
}

///|
fn request_http_copy_bytes(wire : Int, chunks : Int, quantum : Int) -> Int64? {
  if wire < 0 || chunks < 1 || quantum < 1 ||
    wire > 2147483519 || chunks > 2147483519 || quantum > 2147483519 {
    return None
  }
  let n = chunks.to_int64()
  let cursor = @source.json_source_preflight_control_extent()
  let work = @resources.preparation_phase_work_construction_inventory()
  // Original own Buffer/backing pairs and old/new chunk reference arrays;
  // one bounded read/copy overlap, concat and fatal UTF8 decoding. External
  // IncomingMessage producer allocations are NOT supplied by this inventory.
  @execution.preparation_representation_cost({
    record_headers: 2L * n + 12L + cursor.record_headers + work.record_headers,
    reference_slots: 4L * n + 24L + cursor.reference_slots + work.reference_slots,
    scalar_words: 2L * n + 16L + cursor.scalar_words + work.scalar_words,
    owned_utf16_units: wire.to_int64(),
    owned_wire_bytes: 2L * wire.to_int64() + 2L * quantum.to_int64(),
  })
}

///|
/// Before the HTTP consumer's own read/copy/concat/decode constructors. The
/// original stream producer and explicit attack policy remain separate.
pub fn[I] reserve_request_http_input(
  owner : ClientRequestPreparation[I],
  input : I,
  wire : Int,
  chunks : Int,
  quantum : Int,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard owner.phase == Open && !owner.intent_attempted &&
    owner.snapshot_base is None && owner.native_intake_base is None else {
    return Err(WrongPhase)
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  guard request_http_copy_bytes(wire, chunks, quantum) is Some(bytes) else {
    return Err(Policy)
  }
  if owner.http_input is None {
    owner.phase = Selecting
    let base = preparation_module_call(
      () => @resources.preparation_capacity_working_extents(owner.capacity, input)
        .map_err(issue => ClientRequestPreparationIssue::Capacity(issue)),
      () => owner.phase = Open,
    )
    owner.http_input = Some({
      base: base?, wire: 0, chunks: 0, json_attempted: false, work: None,
    })
  }
  let original = owner.http_input.unwrap()
  guard !original.json_attempted && wire >= original.wire &&
    chunks >= original.chunks else { return Err(WrongPhase) }
  guard @execution.checked_preparation_add_product(original.base.0, bytes, 1L)
    is Some(r) &&
    @execution.checked_preparation_add_product(original.base.1, bytes, 1L)
    is Some(e) else { return Err(Policy) }
  owner.phase = Selecting
  let reserved = preparation_module_call(
    () => @resources.reserve_working_preparation_phase(owner.capacity, input, r, e)
      .map_err(issue => ClientRequestPreparationIssue::Capacity(issue)),
    () => owner.phase = Open,
  )
  reserved?
  original.wire = wire
  original.chunks = chunks
  Ok(())
}

///|
/// Size the SAME decoded wire before native JSON.parse. Existing Source
/// preflight observes raw geometry only, not JSON grammar or admission. It is
/// cancelled before the native parser, including every failed prefix. Actual
/// observed nodes/Text price the native tree; wire bytes are never node demand.
pub fn[I] prepare_request_http_json(
  owner : ClientRequestPreparation[I],
  input : I,
  wire : String,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard owner.phase == Open && owner.http_input is Some(original) &&
    !original.json_attempted && owner.snapshot_base is None &&
    !owner.intent_attempted else { return Err(WrongPhase) }
  guard owner.input is Some(value) && physical_equal(value, input) else {
    return Err(ForeignOriginal)
  }
  guard wire.length() <= original.wire &&
    wire.length().to_int64() * 3L < 2147483519L else { return Err(Policy) }
  original.json_attempted = true
  owner.phase = Selecting
  let mut cursor : @source.JsonSourcePreflight? = None
  let result = preparation_module_call(
    () => {
      let work = @resources.begin_preparation_phase_work64(
        owner.capacity, input, @resources.HttpInputPreflight,
        wire.length().to_int64() + 1L,
      ).map_err(issue => ClientRequestPreparationIssue::Work(issue))?
      original.work = Some(work)
      let source = @source.start_json_source_preflight(wire, {
        max_input_bytes: Int::max(1, 3 * wire.length()),
        max_nodes: Int::max(1, wire.length()),
        max_depth: @publication_host.client_standard_program_preparation_limits().checking.input.source.max_depth,
      }, data_keys=true).map_err(_ => ClientRequestPreparationIssue::Policy)?
      cursor = Some(source)
      while true {
        let poll = @source.advance_json_source_preflight(source, 4096)
          .map_err(_ => ClientRequestPreparationIssue::Policy)?
        let (geometry, spent) = match poll {
          @source.JsonSourceContinue(work~) => (None, work)
          @source.JsonSourceReady(value, work~) => (Some(value), work)
          @source.JsonSourceFailed(_, work~) => {
            @resources.spend_preparation_phase_work64(work, work.to_int64())
            |> ignore
            return Err(Policy)
          }
        }
        @resources.spend_preparation_phase_work64(work, spent.to_int64())
          .map_err(issue => ClientRequestPreparationIssue::Work(issue))?
        if geometry is Some(value) {
          @source.cancel_json_source_preflight(source)
          cursor = None
          let nodes = value.node_upper.to_int64()
          let units = nodes + value.quoted_raw_utf16_units.to_int64()
          guard request_snapshot_data_bytes(units, nodes) is Some(tree) else {
            return Err(Policy)
          }
          let (r, e) = @resources.preparation_capacity_working_extents(owner.capacity, input)
            .map_err(issue => ClientRequestPreparationIssue::Capacity(issue))?
          guard @execution.checked_preparation_add_product(r, tree, 1L) is Some(r) &&
            @execution.checked_preparation_add_product(e, tree, 1L) is Some(e) else {
            return Err(Policy)
          }
          return @resources.reserve_working_preparation_phase(owner.capacity, input, r, e)
            .map_err(issue => ClientRequestPreparationIssue::Capacity(issue))
        }
      } nobreak { Err(Policy) }
    },
    () => {
      if cursor is Some(source) { @source.cancel_json_source_preflight(source) }
      owner.phase = Open
    },
  )
  if original.work is Some(work) {
    let closed = @resources.finish_preparation_phase_work64(work)
    if closed is Ok(_) { original.work = None }
    if result is Ok(_) { closed.map_err(issue => Work(issue))? }
  }
  result
}
