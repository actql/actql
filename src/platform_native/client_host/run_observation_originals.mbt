///|
// Exact original compiler metadata inside the existing Run row, not a status,
// authorization, restored physical compilation or a new journal/identity domain.
fn native_run_observation_originals_wire(
  original : @host.ClientRunObservationOriginals,
) -> Result[String, NativeClientRunJournalIssue] {
  try {
    let writer = @encode.writer(131072, 8, 1)
    @encode.begin_object(writer)
    @encode.key(writer, "authorization")
    @encode.string_value(
      writer,
      @publication.run_evidence_value_json(original.authorization()),
    )
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
fn read_native_run_observation_originals(
  wire : String,
  definition : @publication.PublicationContract,
) -> Result[@host.ClientRunObservationOriginals, NativeClientRunJournalIssue] {
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
  guard @decode.closed_object(cursor, ["authorization", "prepared"])
    is Ok(fields) &&
    epoch_text(fields, "authorization") is Some(authorization) &&
    epoch_text(fields, "prepared") is Some(prepared) else {
    return Err(CustodyLost)
  }
  let original = match
    @host.restore_client_run_observation_originals(
      definition, prepared, authorization, 65536, 8192, 64,
    ) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  guard native_run_observation_originals_wire(original) is Ok(canonical) &&
    canonical == wire else {
    return Err(CustodyLost)
  }
  Ok(original)
}
