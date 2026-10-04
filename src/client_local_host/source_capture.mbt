///|
/// A bounded export of one live, checked acquisition occurrence. The descriptor
/// and row bodies are facts for private Store custody, never replay authority.
struct ClientSourceCaptureExport {
  requirement_cid : String
  binding : String
  descriptor_wire : String
  rows : Array[String]
}

///|
/// A receiving instance borrows independently verified durable custody. Closing
/// this instance revokes consumers, not the Store's physical cleanup obligation.
struct ClientSourceCapture {
  source : @query.CapturedInputSource
  live : Ref[Bool]
}

///|
pub(all) enum ClientSourceCaptureIssue {
  BindingMismatch
  InvalidDescriptor
  CustodyUnavailable
  Capture(@query.CapturedSourceIssue)
  Export(@execution.CompletedExportIssue)
  Evidence(@execution.RetainedCompletionEvidenceIssue)
  Content(@execution.RetainedContentReadIssue)
  Readmission(@execution.TrustedOutputIssue)
  Import(@execution.CompletedImportIssue)
  Physical(@resources.LedgerIssue)
}

///|
fn source_capture_values() -> @execution.ValueLimits {
  {
    max_nodes: 20000,
    max_text_bytes: 1000000,
    max_depth: 100,
    max_work: 20000000,
  }
}

///|
fn source_capture_wire() -> @execution.RowWireLimits {
  {
    max_columns: 100,
    max_order_work: 10000,
    max_bytes: 1000000,
    max_nodes: 100000,
    max_depth: 100,
  }
}

///|
fn source_capture_decode() -> @execution.RetainedRowDecodeLimits {
  {
    max_bytes: 1000000,
    max_nodes: 100000,
    max_depth: 64,
    max_text_bytes: 1000000,
  }
}

///|
/// Host-private transport of bounded completion facts. This does not widen
/// process-evidence or establish durable custody by decoding a descriptor.
fn source_capture_descriptor_wire(
  value : @execution.RetainedCompletionDescriptor,
) -> String? {
  let document : Json = {
    "version": "actql-host-source-completion/0.1",
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
fn source_capture_descriptor_number(
  value : @identity.CanonicalValue,
  name : String,
) -> Int? {
  guard @identity.object_field(value, name) is Some(Number(number)) &&
    number >= 0 &&
    number <= 2147483647.0 else {
    return None
  }
  let integer = number.to_int()
  if integer.to_double() == number {
    Some(integer)
  } else {
    None
  }
}

///|
fn source_capture_descriptor_cid(
  value : @identity.CanonicalValue,
  name : String,
) -> String? {
  guard @identity.object_field(value, name) is Some(String(cid)) &&
    cid.length() == 71 &&
    cid.has_prefix("sha256:") else {
    return None
  }
  for char in cid[7:].iter() {
    if !((char >= '0' && char <= '9') || (char >= 'a' && char <= 'f')) {
      return None
    }
  }
  Some(cid)
}

///|
pub fn read_client_source_capture_descriptor(
  wire : String,
) -> Result[@execution.RetainedCompletionDescriptor, ClientSourceCaptureIssue] {
  if wire.length() > 8192 {
    return Err(InvalidDescriptor)
  }
  let value = @identity.from_json(@json.parse(wire), 128, 8, 8192) catch {
    _ => return Err(InvalidDescriptor)
  }
  guard @identity.object_field_count(value) == Some(12) &&
    @identity.object_field(value, "version")
    is Some(String("actql-host-source-completion/0.1")) &&
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
  // Closed shape and canonical spelling, including normalized keys and integers.
  if source_capture_descriptor_wire(descriptor) != Some(wire) {
    return Err(InvalidDescriptor)
  }
  Ok(descriptor)
}

///|
/// The Host binds Run/request, occurrence, selected configuration, physical
/// Source, original attempt and authority in its immutable private record.
/// This string is not an authorization grant. The source/requirement pair is
/// checked here before any export; copied descriptors cannot issue this owner.
pub fn export_client_source_capture(
  source : @query.CapturedInputSource,
  requirement : @planning.QueryRequirement,
  binding : String,
) -> Result[ClientSourceCaptureExport, ClientSourceCaptureIssue] {
  let query = @planning.query_material_owner(
    @planning.query_requirement_material(requirement),
  )
  if binding.is_empty() ||
    binding.length() > 262144 ||
    !@query.captured_source_matches_query(source, query) {
    return Err(BindingMismatch)
  }
  let stream = match
    @query.prepare_captured_source_relation_export(
      source,
      100,
      source_capture_values(),
      source_capture_wire(),
      source_capture_wire(),
      { max_fields: 100, max_bytes: 100000, max_nodes: 10000, max_depth: 100, },
      1000000,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Capture(issue))
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
  // A representation conversion preserves the real completion identity. Its
  // liveness is bounded by the original capture while its descriptor is issued.
  let handle = @execution.retain_admitted_output_stream(
    @execution.completed_export_content(receipt),
    (),
    fn() { @query.captured_source_available(source) },
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
  guard source_capture_descriptor_wire(
      @execution.retained_completion_descriptor(evidence),
    )
    is Some(descriptor_wire) else {
    return Err(InvalidDescriptor)
  }
  Ok({
    requirement_cid: @planning.query_requirement_cid(requirement),
    binding,
    descriptor_wire,
    rows,
  })
}

///|
pub fn client_source_capture_export_requirement(
  value : ClientSourceCaptureExport,
) -> String {
  value.requirement_cid
}

///|
pub fn client_source_capture_export_binding(
  value : ClientSourceCaptureExport,
) -> String {
  value.binding
}

///|
pub fn client_source_capture_export_descriptor(
  value : ClientSourceCaptureExport,
) -> String {
  value.descriptor_wire
}

///|
pub fn client_source_capture_export_rows(
  value : ClientSourceCaptureExport,
) -> Array[String] {
  value.rows.copy()
}

///|
/// Installed Host recovery only. Before this call the Host authenticates its
/// persisted record and compares the original task/input/attempt, Run identity,
/// physical binding and selected configuration with the fenced continuation.
/// The fixed custody callback must retain those checks and current receiving
/// permission. It is not supplied by Program text, a Connector or wire input.
/// Rows and descriptor alone never constitute successful execution evidence.
pub fn restore_client_source_capture(
  requirement : @planning.QueryRequirement,
  saved_requirement_cid : String,
  expected_binding : String,
  saved_binding : String,
  descriptor_wire : String,
  supplied_rows : Array[String],
  custody_available : () -> Bool,
) -> Result[ClientSourceCapture, ClientSourceCaptureIssue] {
  let descriptor = match
    read_client_source_capture_descriptor(descriptor_wire) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if saved_requirement_cid != @planning.query_requirement_cid(requirement) ||
    expected_binding.is_empty() ||
    expected_binding.length() > 262144 ||
    expected_binding != saved_binding ||
    supplied_rows.length() > 100 ||
    descriptor.rows != supplied_rows.length() {
    return Err(BindingMismatch)
  }
  if !custody_available() {
    return Err(CustodyUnavailable)
  }
  let rows = supplied_rows.copy()
  let query = @planning.query_material_owner(
    @planning.query_requirement_material(requirement),
  )
  let preparation = @execution.generated_completion_preparation(
    @query.query_generated_sequence(query),
  )
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
  // The existing Local consumers use cell access. Convert the exact admitted
  // retained completion, preserving its identity and receiving revocation.
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
  let capture_port = match
    @query.prepare_trusted_capture_port(
      query,
      @planning.query_requirement_program(requirement),
      fn(_ : Unit) {
        if available() && @execution.completed_output_available(output) {
          Some((output, descriptor.bytes))
        } else {
          None
        }
      },
    ) {
    Ok(value) => value
    Err(issue) => return Err(Capture(issue))
  }
  @query.capture_verified_source(capture_port, ())
  .map(source => { source, live, })
  .map_err(issue => Capture(issue))
}

///|
pub fn client_source_capture_source(
  value : ClientSourceCapture,
) -> @query.CapturedInputSource? {
  if value.live.val && @query.captured_source_available(value.source) {
    Some(value.source)
  } else {
    None
  }
}

///|
pub fn close_client_source_capture(value : ClientSourceCapture) -> Bool {
  let was_live = value.live.val
  value.live.val = false
  was_live
}

///|
/// Exact receiving allocation on the original Run ledger. Logical close does
/// not release this allocation while a DAG consumer still owns it.
struct ClientAccountedSourceCapture {
  capture : ClientSourceCapture
  ledger : @resources.Ledger
  holding : @resources.Holding
  closed : Ref[Bool]
  mut dag : (@strategy.CapturedDAG, Int)?
}

///|
pub fn restore_accounted_client_source_capture(
  requirement : @planning.QueryRequirement,
  saved_requirement_cid : String,
  expected_binding : String,
  saved_binding : String,
  descriptor_wire : String,
  rows : Array[String],
  ledger : @resources.Ledger,
  capacity : ClientDuckDBCaptureCapacity,
  custody_available : () -> Bool,
) -> Result[ClientAccountedSourceCapture, ClientSourceCaptureIssue] {
  if !client_duckdb_capture_capacity_matches_requirement(capacity, requirement) {
    return Err(BindingMismatch)
  }
  let quantities = client_duckdb_capture_capacity_values(capacity)
  let reservation = match
    @resources.reserve_attempt(ledger, 0L, quantities[0], quantities[1]) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  let capture = match
    restore_client_source_capture(
      requirement, saved_requirement_cid, expected_binding, saved_binding, descriptor_wire,
      rows, custody_available,
    ) {
    Ok(value) => value
    Err(issue) => {
      @resources.settle_reservation(ledger, reservation) |> ignore
      return Err(issue)
    }
  }
  let holding = match
    @resources.retain_allocation(ledger, reservation, quantities[0]) {
    Ok(value) => value
    Err(issue) => {
      close_client_source_capture(capture) |> ignore
      @resources.settle_reservation(ledger, reservation) |> ignore
      return Err(Physical(issue))
    }
  }
  match @resources.settle_reservation(ledger, reservation) {
    Ok(_) => ()
    Err(issue) => {
      close_client_source_capture(capture) |> ignore
      @resources.release_allocation(ledger, holding) |> ignore
      return Err(Physical(issue))
    }
  }
  Ok({ capture, ledger, holding, closed: Ref(false), dag: None, })
}

///|
pub fn accounted_client_source_capture_source(
  value : ClientAccountedSourceCapture,
) -> @query.CapturedInputSource? {
  if value.closed.val ||
    !@resources.holding_available(value.ledger, value.holding) {
    None
  } else {
    client_source_capture_source(value.capture)
  }
}

///|
pub fn retain_accounted_client_source_capture_task(
  value : ClientAccountedSourceCapture,
  dag : @strategy.CapturedDAG,
  task : Int,
) -> Result[Unit, ClientSourceCaptureIssue] {
  guard !value.closed.val &&
    value.dag is None &&
    accounted_client_source_capture_source(value) is Some(source) &&
    @strategy.captured_task_source_matches(dag, task, source) else {
    return Err(BindingMismatch)
  }
  let closed = value.closed
  match
    @strategy.retain_captured_task_allocation(dag, task, value.holding, release_confirmed=fn() {
      closed.val
    }) {
    Ok(_) => value.dag = Some((dag, task))
    Err(issue) => return Err(Physical(issue))
  }
  Ok(())
}

///|
pub fn accounted_client_source_capture_usage(
  value : ClientAccountedSourceCapture,
) -> @resources.LedgerUsage {
  @resources.ledger_usage(value.ledger)
}

///|
pub fn accounted_client_source_capture_cleanup_pending(
  value : ClientAccountedSourceCapture,
) -> Bool {
  if value.closed.val && value.dag is Some((dag, _)) {
    @strategy.refresh_captured_retention(dag)
  }
  @resources.holding_available(value.ledger, value.holding)
}

///|
pub fn close_accounted_client_source_capture(
  value : ClientAccountedSourceCapture,
) -> Bool {
  if !value.closed.val {
    value.closed.val = true
    close_client_source_capture(value.capture) |> ignore
    match value.dag {
      Some((dag, task)) => @strategy.close_captured_task_output(dag, task)
      None =>
        @resources.release_allocation(value.ledger, value.holding) |> ignore
    }
  }
  !accounted_client_source_capture_cleanup_pending(value)
}
