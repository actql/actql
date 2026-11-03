///|
// One retained ordinary lowerer call on the same Request. This is DATA, not a
// second preparation owner, permission or mutable installation cache.
priv struct ClientRequestQueryLowering {
  publication : @source_publication.PreparedPublishedQueryEnvironment
  environment : @checked.CheckEnvironment
  declarations : String?
  public_primary : Bool
  quote : (Int64, Int64)
  mut output : (
    @frontend.Lowered,
    @checked.PreparedSourceCatalog,
    @frontend.DiagnosticSource,
  )?
}

///|
pub suberror ClientRequestQueryLoweringIssue {
  Request(ClientRequestPreparationIssue)
  Publication(@source_publication.PreparedPublicationIssue)
  Overflow
}

///|
// Query text/declarations and retained Catalog sizes bound the generated
// syntax, expanded fields, maps and canonical output overlap. The Catalog is
// borrowed; its original usage is DATA, not a repeated admission or charge
// for its historical work. One shared coarse tariff replaces a helper census.
fn request_query_lowering_data_bytes(
  query : ClientRequestQuerySyntax,
  declarations : String?,
  catalog : @checked.PreparedSourceCatalog,
  request_copy : (Int, Int64),
) -> Int64? {
  let usage = @checked.source_catalog_usage(catalog)
  // Each emitted external input has an authored relation occurrence with at
  // least one token. CTE reuse imports its captured Result rather than replaying
  // its external input. The complete original token count therefore bounds
  // initial alias imports across joins, set arms and nested query bodies.
  // Prefix, member and demand-copy overlap is accounted separately below.
  let occurrences = match query.query {
    Some(parsed) =>
      @query_syntax.token_count(@query_syntax.query_source(parsed))
    None => return None
  }
  let copy_bytes = request_query_literal_copy_bytes(request_copy, occurrences)
  guard copy_bytes is Some(copy_bytes) else { return None }
  let units = query.document.length().to_int64() +
    (match declarations {
      Some(value) => value.length().to_int64()
      None => 0L
    }) +
    usage.bytes.to_int64() +
    usage.nodes.to_int64() +
    1L
  guard request_snapshot_data_bytes(units, units) is Some(base) else {
    return None
  }
  @execution.checked_preparation_add_product(base, copy_bytes, 1L)
}

///|
/// The same already parsed Query enters the existing published lowerer once.
/// A failed capacity grow retains the original immutable tuple and quote;
/// it cannot trigger a second parse, Catalog read or completed lowerer call.
/// Existing lowerer budgets retain their bounds. Syntax work observations do
/// not become a complete meter of this later semantic/construction phase.
pub fn[I] lower_request_published_query(
  owner : ClientRequestPreparation[I],
  input : I,
  publication : @source_publication.PreparedPublishedQueryEnvironment,
  environment : @checked.CheckEnvironment,
  declarations : String?,
  public_primary? : Bool = false,
) -> Result[
  (
    @frontend.Lowered,
    @checked.PreparedSourceCatalog,
    @frontend.DiagnosticSource,
  ),
  ClientRequestQueryLoweringIssue,
] {
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(Request(ForeignOriginal))
  }
  guard (owner.phase == QuerySyntaxParsed || owner.phase == QueryLoweringQuoted) &&
    owner.query_syntax is Some(query) &&
    query.query is Some(parsed) else {
    return Err(Request(WrongPhase))
  }
  let source = if owner.source_input is Some(context) {
    guard request_source_input_original(owner) is Some(source) &&
      physical_equal(context.environment, environment) else {
      return Err(Request(ForeignOriginal))
    }
    let parts = match @publication_host.client_source_input_parts(source) {
      Err(issue) => return Err(Request(SourceInput(Source(issue))))
      Ok(parts) => parts
    }
    if parts.2 != declarations {
      return Err(Request(ForeignOriginal))
    }
    Some(source)
  } else {
    None
  }
  if source is None && owner.native_parameters_ready && declarations is Some(_) {
    return Err(Request(ForeignOriginal))
  }
  if owner.phase == QuerySyntaxParsed {
    let catalog = match
      @source_publication.prepared_published_query_catalog(
        publication, environment,
      ) {
      Err(issue) => return Err(Publication(issue))
      Ok(value) => value
    }
    let request_copy = match
      @source_publication.prepared_published_request_copy_geometry(
        publication, environment,
      ) {
      Err(issue) => return Err(Publication(issue))
      Ok(value) => value
    }
    guard request_query_lowering_data_bytes(
        query, declarations, catalog, request_copy,
      )
      is Some(bytes) else {
      return Err(Overflow)
    }
    let (r, e) = match
      @resources.preparation_capacity_working_extents(owner.capacity, input) {
      Err(issue) => return Err(Request(Capacity(issue)))
      Ok(value) => value
    }
    guard @execution.checked_preparation_add_product(r, bytes, 1L) is Some(r) &&
      @execution.checked_preparation_add_product(e, bytes, 1L) is Some(e) else {
      return Err(Overflow)
    }
    query.lowering = Some({
      publication,
      environment,
      declarations,
      public_primary,
      quote: (r, e),
      output: None,
    })
    owner.phase = QueryLoweringQuoted
  }
  guard query.lowering is Some(selected) &&
    physical_equal(selected.publication, publication) &&
    physical_equal(selected.environment, environment) &&
    selected.declarations == declarations &&
    selected.public_primary == public_primary else {
    return Err(Request(ForeignOriginal))
  }
  owner.phase = Selecting
  match
    @resources.reserve_working_preparation_phase(
      owner.capacity,
      input,
      selected.quote.0,
      selected.quote.1,
    ) {
    Err(issue) => {
      owner.phase = QueryLoweringQuoted
      return Err(Request(Capacity(issue)))
    }
    Ok(_) => ()
  }
  let outcome = if source is Some(source) {
    @publication_host.lower_client_source_input_query(
      source,
      selected.publication,
      selected.environment,
      parsed,
      public_primary=selected.public_primary,
    ).map_err(issue => {
      ClientRequestQueryLoweringIssue::Request(SourceInput(Source(issue)))
    })
  } else if owner.native_parameters_ready {
    @source_publication.lower_prepared_query_with_declarations(
      selected.publication,
      selected.environment,
      parsed,
      owner.native_query_declarations.map(pair => pair.1),
      public_primary=selected.public_primary,
    ).map_err(issue => Publication(issue))
  } else {
    @source_publication.lower_prepared_published_parsed_query(
      selected.publication,
      selected.environment,
      parsed,
      selected.declarations,
      public_primary=selected.public_primary,
    ).map_err(issue => Publication(issue))
  }
  owner.phase = QueryLoweringFailed
  match outcome {
    Err(issue) => Err(issue)
    Ok(output) => {
      guard output.0.program is Some(program) else {
        return Err(Request(WrongPhase))
      }
      selected.output = Some(output)
      owner.held_program = Some(program)
      owner.phase = QueryLowered
      Ok(output)
    }
  }
}

///|
/// Completed original DATA only. This performs no Catalog admission, lowerer,
/// encoding or external current callback and grants no execution permission.
pub fn[I] prepared_request_query_lowering(
  owner : ClientRequestPreparation[I],
  input : I,
) -> Result[
  (
    @frontend.Lowered,
    @checked.PreparedSourceCatalog,
    @frontend.DiagnosticSource,
  ),
  ClientRequestQueryLoweringIssue,
] {
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(Request(ForeignOriginal))
  }
  guard owner.phase != Selecting &&
    owner.query_syntax is Some(query) &&
    query.lowering is Some(selected) &&
    selected.output is Some(output) else {
    return Err(Request(WrongPhase))
  }
  Ok(output)
}

///|
// New literal DATA is a separate constructor family. Do not spend the old
// Catalog-derived tariff or unused capacity on imported request trees.
fn request_query_literal_copy_bytes(
  geometry : (Int, Int64),
  occurrences : Int,
) -> Int64? {
  let (nodes, text) = geometry
  if nodes < 0 ||
    text < 0L ||
    occurrences < 1 ||
    text > 2147483640L ||
    nodes == 2147483647 {
    return None
  }
  if nodes == 0 {
    return if text == 0L { Some(0L) } else { None }
  }
  // Include the enclosing request field and its parent wrapper, not only the
  // subtree leaf values. Maxima come from the same immutable publication.
  let nodes = nodes + 1
  let text = text + 7L
  guard @source_builder.cursor_import_construction_extent(nodes, text.to_int())
    is Some(imported) &&
    @canonical.nfc_lf_retained_output_units(text) is Some(normalized) else {
    return None
  }
  // Every scalar number needs <=25 bytes;32N also covers all punctuation,
  // quotes and literal control words. Unicode/escaping needs <=6 bytes/unit.
  let output = 32L * nodes.to_int64() + 6L * (normalized + text)
  if output > 2147483647L {
    return None
  }
  guard @encode.text_writer_construction_inventory(
      output.to_int(),
      nodes,
      nodes,
    )
    is Some(writer) &&
    @syntax.admitted_source_emission_construction_extent(nodes) is Some(emitter) else {
    return None
  }
  // Four named lifetime lanes, not four invocations or a physical GC claim:
  // 1. Original Construction's imported annotated tree and final Source.
  // 2. checked_query_prefix_pipeline's original full-prefix snapshot.
  // 3. MemberResolution.finish replacement OR its synchronous nested
  //    source_prefix_carrier import/snapshot (the scan ends before finish).
  // 4. prune_query_binding_source's demanded copy beside the original checked
  //    pipeline/source. This later phase does not run another member pass.
  // Each lane deliberately includes BOTH builder and admitted/indexed trees.
  // CheckedInfer/nearest pipeline Cursors remain in lane 2/3 until consumed;
  // only Cursor-free Carrier/schema facts enter ScriptSources caches. See the
  // request DATA interface for the complete source-lifetime argument.
  let original = imported
  // Later imports see NFC/LF-normalized keys and unchanged scalar values.
  // NFC/LF is idempotent: all later copies share this retained-text envelope,
  // rather than repeatedly expanding the bound at every prefix/probe.
  let retained_text = normalized + text
  if retained_text > 2147483647L {
    return None
  }
  guard @source_builder.cursor_import_construction_extent(
      nodes,
      retained_text.to_int(),
    )
    is Some(later) else {
    return None
  }
  let prefix = later
  let resolved = later
  let demanded = later
  guard @execution.preparation_representation_cost({
      record_headers: original.record_headers +
      prefix.record_headers +
      resolved.record_headers +
      demanded.record_headers +
      writer.record_headers +
      emitter.record_headers,
      reference_slots: original.reference_slots +
      prefix.reference_slots +
      resolved.reference_slots +
      demanded.reference_slots +
      writer.reference_slots +
      emitter.reference_slots,
      scalar_words: original.scalar_words +
      prefix.scalar_words +
      resolved.scalar_words +
      demanded.scalar_words +
      writer.scalar_words +
      emitter.scalar_words,
      owned_utf16_units: original.owned_utf16_units +
      prefix.owned_utf16_units +
      resolved.owned_utf16_units +
      demanded.owned_utf16_units +
      writer.owned_utf16_units,
      owned_wire_bytes: 0L,
    })
    is Some(bytes) else {
    return None
  }
  // Sum the complete simultaneous lanes for every possible original import.
  // Reusing a lane requires the prior logical Source to be unreachable from
  // later lowering; no claim is made about when the backend releases memory.
  @execution.checked_preparation_add_product(0L, bytes, occurrences.to_int64())
}
