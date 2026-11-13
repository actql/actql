///|
// Only first admission's checked compilation supplies this private ticket.
// Stored bytes are read-only metadata, never a restored compilation or grant.
priv struct NativeClientRunPlanOriginal {
  plan : @publication.PublicationContract
  view : String
}

///|
// Same-owner first-capture binding. The saved DATA reader cannot create this
// admission ticket or substitute metadata from another checked Run.
priv struct NativeClientCapturedRunPlan {
  program_cid : String
  definition_cid : String
  prepared : String
  authorization : String
  original : NativeClientRunPlanOriginal
}

///|
fn native_run_plan_field(wire : String, field : String) -> String? {
  let source = match
    @source.parse_json_bytes_preserving(@utf8.encode(wire), {
      max_input_bytes: 65536,
      max_nodes: 8192,
      max_depth: 64,
    }) {
    Ok(value) => value
    Err(_) => return None
  }
  let cursor = match
    @decode.admit(source, {
      max_nodes: 8192,
      max_depth: 64,
      max_string_bytes: 65536,
      max_total_string_bytes: 65536,
    }) {
    Ok(value) => value
    Err(_) => return None
  }
  let fields = match @decode.open_object(cursor) {
    Ok(value) => value
    Err(_) => return None
  }
  epoch_text(fields, field)
}

///|
fn validate_native_run_plan_original(
  original : NativeClientRunPlanOriginal,
  definition : @publication.PublicationContract,
  program_cid : String?,
) -> Result[Unit, NativeClientRunJournalIssue] {
  if @publication.publication_contract_name(original.plan) != "compiled_plan" ||
    @publication.publication_contract_name(definition) != "run_definition" {
    return Err(ForeignRun)
  }
  let plan_cid = @publication.publication_contract_identity(original.plan)
  guard native_run_plan_field(
      @publication.publication_contract_json(definition),
      "compiled_plan_cid",
    ) ==
    Some(plan_cid) &&
    native_run_plan_field(
      @publication.publication_contract_json(original.plan),
      "program_definition_cid",
    )
    is Some(actual_program) else {
    return Err(ForeignRun)
  }
  if program_cid is Some(expected) && actual_program != expected {
    return Err(ForeignRun)
  }
  let view = match
    @publication.parse_interactive_run_control_shape(
      "plan_view",
      original.view,
      65536,
      8192,
      64,
    ) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  guard @canonical.object_field(view, "compiled_plan_cid")
    is Some(@canonical.String(selected)) &&
    selected == plan_cid &&
    @canonical.object_field(view, "logical_map") is Some(map) else {
    return Err(ForeignRun)
  }
  let wire = @canonical.stringify_value(map, 65536, 8192, 64) catch {
    _ => return Err(CapacityExceeded)
  }
  let map = match
    @publication.admit_run_evidence_value("logical_map", wire, 65536, 8192, 64) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  match
    @publication.check_interactive_logical_map_binding(
      map,
      original.plan,
      65536,
      8192,
      64,
    ) {
    Ok(_) => Ok(())
    Err(_) => Err(ForeignRun)
  }
}

///|
fn capture_native_run_plan_original(
  prepared : @host.PreparedClientProgram,
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
) -> Result[NativeClientCapturedRunPlan, NativeClientRunJournalIssue] {
  if !@host.client_compiled_run_matches(compiled, prepared) ||
    @host.check_client_compiled_run_definition(compiled, definition) is Err(_) {
    return Err(ForeignRun)
  }
  let view = match
    @host.client_compiled_run_static_plan_view(
      compiled, prepared, 65536, 8192, 64,
    ) {
    Ok(value) => value
    Err(_) => return Err(UnsupportedPreparation)
  }
  let original = { plan: @host.client_compiled_run_plan(compiled), view, }
  // The immutable typed issuer already sealed keys/map and checked the final
  // shape from this SAME checked owner and compiled Plan. Keep its provenance
  // ticket; do not reparse the fresh view as if it were cold stored bytes.
  Ok({
    program_cid: @host.prepared_client_identity(prepared).program_definition_cid,
    definition_cid: @publication.publication_contract_identity(definition),
    prepared: @publication.run_evidence_value_json(
      @host.client_compiled_run_prepared(compiled),
    ),
    authorization: @publication.run_evidence_value_json(
      @host.client_compiled_run_authorization(compiled),
    ),
    original,
  })
}

///|
fn native_run_plan_original_wire(
  original : NativeClientRunPlanOriginal,
  before_construction? : ((Int64, Int64, Int64) -> Result[
    Unit,
    NativeClientRunJournalIssue,
  ])? = None,
) -> Result[String, NativeClientRunJournalIssue] {
  let plan = @publication.publication_contract_json(original.plan)
  guard @encode.quoted_string_construction_extent(plan)
    is Some((plan_bytes, plan_units)) &&
    @encode.quoted_string_construction_extent(original.view)
    is Some((view_bytes, view_units)) else {
    return Err(Encoding)
  }
  let structure = "{\"compiled_plan\":,\"plan_view\":}".length().to_int64()
  let maximum = match
    native_metadata_writer_limit(
      structure + plan_bytes + view_bytes,
      structure + plan_units + view_units,
      before_construction,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  try {
    let writer = @encode.writer(maximum, 8, 1)
    @encode.begin_object(writer)
    @encode.key(writer, "compiled_plan")
    @encode.string_value(
      writer,
      @publication.publication_contract_json(original.plan),
    )
    @encode.key(writer, "plan_view")
    @encode.string_value(writer, original.view)
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    @encode.OutputLimit => Err(CapacityExceeded)
    _ => Err(Encoding)
  }
}

///|
fn read_native_run_plan_original(
  wire : String,
  definition : @publication.PublicationContract,
  program_cid : String?,
  before_construction? : ((Int64, Int64, Int64) -> Result[
    Unit,
    NativeClientRunJournalIssue,
  ])? = None,
) -> Result[NativeClientRunPlanOriginal, NativeClientRunJournalIssue] {
  let fields = match
    native_run_observation_fields(
      wire,
      ["compiled_plan", "plan_view"],
      before_construction~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard epoch_text(fields, "compiled_plan") is Some(plan_wire) &&
    epoch_text(fields, "plan_view") is Some(view) else {
    return Err(CustodyLost)
  }
  let plan = match
    @publication.admit_publication_contract(
      "compiled_plan", plan_wire, 65536, 8192, 64,
    ) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  if @publication.publication_contract_json(plan) != plan_wire {
    return Err(CustodyLost)
  }
  let original = { plan, view, }
  match validate_native_run_plan_original(original, definition, program_cid) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard native_run_plan_original_wire(original, before_construction~)
    is Ok(canonical) &&
    canonical == wire else {
    return Err(CustodyLost)
  }
  Ok(original)
}
