///|
// Exact original compiler metadata inside the existing Run row, not a status,
// authorization, restored physical compilation or a new journal/identity domain.
fn native_run_observation_originals_wire(
  original : @host.ClientRunObservationOriginals,
  plan? : NativeClientRunPlanOriginal? = None,
  before_construction? : ((Int64, Int64, Int64) -> Result[
    Unit,
    NativeClientRunJournalIssue,
  ])? = None,
) -> Result[String, NativeClientRunJournalIssue] {
  let plan_wire = match plan {
    None => None
    Some(value) =>
      match native_run_plan_original_wire(value, before_construction~) {
        Ok(wire) => Some(wire)
        Err(issue) => return Err(issue)
      }
  }
  let authorization = @publication.run_evidence_value_json(
    original.authorization(),
  )
  let prepared = @publication.run_evidence_value_json(original.prepared())
  guard @encode.quoted_string_construction_extent(authorization)
    is Some((authorization_bytes, authorization_units)) &&
    @encode.quoted_string_construction_extent(prepared)
    is Some((prepared_bytes, prepared_units)) else {
    return Err(Encoding)
  }
  let mut bytes = "{\"authorization\":,\"prepared\":}".length().to_int64() +
    authorization_bytes +
    prepared_bytes
  let mut units = "{\"authorization\":,\"prepared\":}".length().to_int64() +
    authorization_units +
    prepared_units
  if plan_wire is Some(wire) {
    guard @encode.quoted_string_construction_extent(wire)
      is Some((plan_bytes, plan_units)) else {
      return Err(Encoding)
    }
    bytes += ",\"plan\":".length().to_int64() + plan_bytes
    units += ",\"plan\":".length().to_int64() + plan_units
  }
  let maximum = match
    native_metadata_writer_limit(bytes, units, before_construction) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  try {
    let writer = @encode.writer(maximum, 8, 1)
    @encode.begin_object(writer)
    @encode.key(writer, "authorization")
    @encode.string_value(
      writer,
      @publication.run_evidence_value_json(original.authorization()),
    )
    if plan_wire is Some(wire) {
      @encode.key(writer, "plan")
      @encode.string_value(writer, wire)
    }
    @encode.key(writer, "prepared")
    @encode.string_value(
      writer,
      @publication.run_evidence_value_json(original.prepared()),
    )
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    @encode.OutputLimit => Err(CapacityExceeded)
    _ => Err(Encoding)
  }
}

///|
fn capture_native_run_observation_originals(
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
) -> Result[@host.ClientRunObservationOriginals, NativeClientRunJournalIssue] {
  @host.capture_client_run_observation_originals(compiled, definition).map_err(_ => {
    ForeignRun
  })
}

///|
fn native_run_observation_fields(
  wire : String,
  names : Array[String],
  before_construction? : ((Int64, Int64, Int64) -> Result[
    Unit,
    NativeClientRunJournalIssue,
  ])? = None,
) -> Result[@decode.ObjectView, NativeClientRunJournalIssue] {
  if before_construction is Some(reserve) {
    let cursor = match native_metadata_fields_in_original_read(wire, reserve) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    return @decode.closed_object(cursor, names).map_err(_ => CustodyLost)
  }
  let source = match
    @source.parse_json_bytes_preserving(@utf8.encode(wire), {
      max_input_bytes: 131072,
      max_nodes: 8,
      max_depth: 1,
    }) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let cursor = match
    @decode.admit(source, {
      max_nodes: 8,
      max_depth: 1,
      max_string_bytes: 131072,
      max_total_string_bytes: 131072,
    }) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  @decode.closed_object(cursor, names).map_err(_ => CustodyLost)
}

///|
// Immutable metadata from the existing bounded row reader. These exact
// originals supply no current permission, execution or physical lifetime.
priv struct NativeClientStoredRunObservation {
  wire : String
  definition_cid : String
  program_cid : String?
  observation : @host.ClientRunObservationOriginals
  plan : NativeClientRunPlanOriginal?
}

///|
fn NativeClientStoredRunObservation::matches(
  self : NativeClientStoredRunObservation,
  wire : String,
  definition : @publication.PublicationContract,
  program_cid : String?,
) -> Bool {
  self.wire == wire &&
  self.definition_cid == @publication.publication_contract_identity(definition) &&
  self.program_cid == program_cid
}

///|
fn read_native_stored_run_observation(
  wire : String,
  definition : @publication.PublicationContract,
  program_cid : String?,
  before_construction? : ((Int64, Int64, Int64) -> Result[
    Unit,
    NativeClientRunJournalIssue,
  ])? = None,
) -> Result[NativeClientStoredRunObservation, NativeClientRunJournalIssue] {
  let fields = match
    native_run_observation_fields(
      wire,
      ["authorization", "plan", "prepared"],
      before_construction~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard epoch_text(fields, "authorization") is Some(authorization) &&
    epoch_text(fields, "prepared") is Some(prepared) else {
    return Err(CustodyLost)
  }
  let plan = match @decode.lookup(fields, "plan") {
    None => None
    Some(_) => {
      guard epoch_text(fields, "plan") is Some(wire) else {
        return Err(CustodyLost)
      }
      match
        read_native_run_plan_original(
          wire,
          definition,
          program_cid,
          before_construction~,
        ) {
        Ok(value) => Some(value)
        Err(issue) => return Err(issue)
      }
    }
  }
  let original = match
    @host.restore_client_run_observation_originals(
      definition, prepared, authorization, 65536, 8192, 64,
    ) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  guard native_run_observation_originals_wire(
      original,
      plan~,
      before_construction~,
    )
    is Ok(canonical) &&
    canonical == wire else {
    return Err(CustodyLost)
  }
  Ok({
    wire,
    definition_cid: @publication.publication_contract_identity(definition),
    program_cid,
    observation: original,
    plan,
  })
}

///|
// Only a fresh checked Computation capture can avoid cold readmission. Typed
// observations alone (including Effect callers) carry no such Run binding.
fn captured_native_run_stored_observation(
  captured : NativeClientCapturedRunPlan,
  observation : @host.ClientRunObservationOriginals,
  definition : @publication.PublicationContract,
  program : String,
  before_construction? : ((Int64, Int64, Int64) -> Result[
    Unit,
    NativeClientRunJournalIssue,
  ])? = None,
) -> Result[NativeClientStoredRunObservation, NativeClientRunJournalIssue] {
  if captured.definition_cid !=
    @publication.publication_contract_identity(definition) ||
    captured.program_cid != program ||
    captured.prepared !=
    @publication.run_evidence_value_json(observation.prepared()) ||
    captured.authorization !=
    @publication.run_evidence_value_json(observation.authorization()) {
    return Err(ForeignRun)
  }
  let wire = match
    native_run_observation_originals_wire(
      observation,
      plan=Some(captured.original),
      before_construction~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    wire,
    definition_cid: captured.definition_cid,
    program_cid: Some(captured.program_cid),
    observation,
    plan: Some(captured.original),
  })
}
