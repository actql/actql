///|
// One retained ordinary lowerer call on the same Request. This is DATA, not a
// second preparation owner, permission or mutable installation cache.
priv struct ClientRequestQueryLowering {
  publication : @source_publication.PreparedPublishedQueryEnvironment
  environment : @checked.CheckEnvironment
  declarations : String?
  public_primary : Bool
  binding_limits : @admitted.Limits?
  mut refusal_binding : ClientRequestQueryRefusalBinding?
  quote : (Int64, Int64)
  mut output : Result[
    (
      @frontend.Lowered,
      @checked.PreparedSourceCatalog,
      @frontend.DiagnosticSource,
    ),
    ClientRequestQueryLoweringIssue,
  ]?
}

///|
pub suberror ClientRequestQueryLoweringIssue {
  Request(ClientRequestPreparationIssue)
  Publication(@source_publication.PreparedPublicationIssue)
  WithBinding(ClientRequestQueryLoweringIssue, @parameters.Issue)
  BindingFailure(ClientRequestQueryLoweringIssue, ClientRequestPreparationIssue)
  BindingException(ClientRequestQueryLoweringIssue, QueryBindingForeignFailure)
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
  publication : @source_publication.PreparedPublishedQueryEnvironment,
) -> Int64? {
  let usage = @checked.source_catalog_usage(catalog)
  // Each emitted external input has an authored relation occurrence with at
  // least one token. CTE reuse imports its captured Result rather than replaying
  // its external input. The complete original token count therefore bounds
  // initial alias imports across joins, set arms and nested query bodies.
  // Prefix, member and demand-copy overlap is accounted separately below.
  guard query.query is Some(Ok(parsed)) else { return None }
  let occurrences = @query_syntax.token_count(
    @query_syntax.query_source(parsed),
  )
  let copy_bytes = request_query_literal_copy_bytes(request_copy, occurrences)
  guard copy_bytes is Some(copy_bytes) &&
    request_integer_context_data_bytes(
      if query.query is Some(Ok(parsed)) &&
        !@query_syntax.integer_function_context_required(parsed) {
        0L
      } else {
        occurrences.to_int64()
      },
    )
    is Some(integer_context) else {
    return None
  }
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
  guard @execution.checked_preparation_add_product(base, copy_bytes, 1L)
    is Some(base) else {
    return None
  }
  guard @execution.checked_preparation_add_product(base, integer_context, 1L)
    is Some(base) &&
    request_query_namespace_scope_fields_bytes(occurrences.to_int64())
    is Some(scope_fields) else {
    return None
  }
  guard request_query_namespace_data_bytes(
      parsed,
      publication,
      catalog,
      query.document.length().to_int64() +
      declarations.map(value => value.length().to_int64()).unwrap_or(0L),
    )
    is Some(namespace_bytes) &&
    @execution.checked_preparation_add_product(base, scope_fields, 1L)
    is Some(base) else {
    return None
  }
  guard @execution.checked_preparation_add_product(base, namespace_bytes, 1L)
    is Some(base) else {
    return None
  }
  request_query_extra_construction_bytes(
    base,
    units,
    @query_syntax.rollup_item_count(parsed).to_int64() +
    @query_syntax.scalar_projection_count(parsed).to_int64(),
  )
}

///|
// One added optional-reference slot at each of the eighteen existing Scope
// constructor sites and two ScriptSources sites, at most once per original
// token occurrence. None is not an erased field or spare baseline capacity.
// The conditional arrays/records require their separate namespace inventory.
fn request_query_namespace_scope_fields_bytes(tokens : Int64) -> Int64? {
  guard @execution.checked_preparation_add_product(0L, tokens, 20L)
    is Some(references) else {
    return None
  }
  @execution.preparation_representation_cost({
    record_headers: 0L,
    reference_slots: references,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}

///|
// A ROLLUP item adds Group/Append and an authored scalar adds a singleton
// Group, cardinality assertion and projection. For each occurrence, one lane
// over the original document and catalog covers their extra step nodes,
// references, serialized annotations, generated names and retained overlap.
// The existing input/output terms remain in the base envelope.
fn request_query_extra_construction_bytes(
  base : Int64,
  units : Int64,
  occurrences : Int64,
) -> Int64? {
  if occurrences == 0L {
    return Some(base)
  }
  guard occurrences > 0L && units > 0L && units <= 9223372036854775807L / 64L else {
    return None
  }
  guard @execution.preparation_representation_cost({
      record_headers: 8L * units,
      reference_slots: 24L * units,
      scalar_words: 8L * units,
      owned_utf16_units: 64L * units,
      owned_wire_bytes: 0L,
    })
    is Some(prefix) else {
    return None
  }
  @execution.checked_preparation_add_product(base, prefix, occurrences)
}

///|
// Original token count bounds the added query-local context inventory. Each
// syntax occurrence has one task/immutable scope link, work/desired-column
// entries and at most one rebuilt query/operation/expression. The 20H/72R/40W
// envelope includes original/rewritten overlap, Option/tuple tags, compacting
// subtree maps, nullable typed literals and the already-returned child arrays.
// 128 UTF16 units cover full signed64 spellings plus collision-free companion
// identifiers (three bounded Int indices and the fixed private prefix).
// Immutable scope links (not copied visible-name vectors) and idempotent
// subtree reuse keep simultaneous storage linear in this original inventory.
// This is added to, not borrowed from, the existing lowerer/writer quote, and
// is reserved on the SAME Request before any contextual AST construction.
fn request_integer_context_data_bytes(tokens : Int64) -> Int64? {
  if tokens < 0L || tokens > 9223372036854775807L / 128L {
    return None
  }
  @execution.preparation_representation_cost({
    record_headers: 20L * tokens,
    reference_slots: 72L * tokens,
    scalar_words: 40L * tokens,
    owned_utf16_units: 128L * tokens,
    owned_wire_bytes: 0L,
  })
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
  binding_limits? : @admitted.Limits? = None,
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
    query.query is Some(Ok(parsed)) else {
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
    let control = if owner.native_query_declarations is Some(_) &&
      owner.native_parameters is Some(_) &&
      binding_limits is Some(_) {
      request_query_refusal_binding_control_bytes()
    } else {
      Some(0L)
    }
    guard request_query_lowering_data_bytes(
        query, declarations, catalog, request_copy, publication,
      )
      is Some(data) &&
      control is Some(control) &&
      @execution.checked_preparation_add_product(data, control, 1L)
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
      binding_limits,
      refusal_binding: None,
      quote: (r, e),
      output: None,
    })
    owner.phase = QueryLoweringQuoted
  }
  guard query.lowering is Some(selected) &&
    physical_equal(selected.publication, publication) &&
    physical_equal(selected.environment, environment) &&
    selected.declarations == declarations &&
    selected.public_primary == public_primary &&
    selected.binding_limits == binding_limits else {
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
  guard owner.computation_limits is Some(program_limits) else {
    return Err(Request(WrongPhase))
  }
  let limits = @publication_host.client_program_query_lowering_limits(
    program_limits,
  )
  let calls = Ref(0L)
  let outcome = if source is Some(source) {
    @publication_host.lower_client_source_input_query(
      source,
      selected.publication,
      selected.environment,
      parsed,
      public_primary=selected.public_primary,
      calls_out=Some(calls),
      limits=Some(limits),
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
      calls_out=Some(calls),
      limits=Some(limits),
    ).map_err(issue => Publication(issue))
  } else {
    @source_publication.lower_prepared_published_parsed_query(
      selected.publication,
      selected.environment,
      parsed,
      selected.declarations,
      public_primary=selected.public_primary,
      calls_out=Some(calls),
      limits=Some(limits),
    ).map_err(issue => Publication(issue))
  }
  owner._observed_query_lower_calls += calls.val
  owner.phase = QueryLoweringFailed
  selected.output = Some(outcome)
  match outcome {
    Err(issue) => {
      if owner.native_query_declarations is None ||
        owner.native_parameters is None ||
        selected.binding_limits is None {
        return Err(issue)
      }
      match
        query_binding_protected_call(
          () => finish_request_query_refusal_binding(owner, input, selected),
          () => {
            pause_request_query_refusal_binding(selected)
            if owner.phase == Selecting {
              owner.phase = QueryLoweringFailed
            }
          },
        ) {
        Ok(Ok(Some(binding))) => Err(WithBinding(issue, binding))
        Ok(Ok(None)) => Err(issue)
        Ok(Err(failure)) => Err(BindingFailure(issue, failure))
        Err(failure) => Err(BindingException(issue, failure))
      }
    }
    Ok(output) => {
      guard output.0.program is Some(program) else {
        return Err(Request(WrongPhase))
      }
      owner.held_program = Some(program)
      // The parser consumed the original SQL/Pipe wire envelope. The checker
      // reuses this generated Program, admitted by the SAME lowerer envelope;
      // it must not reapply a raw-document node/byte limit to that artifact.
      owner.computation_limits = Some({
        ..program_limits,
        checking: { ..program_limits.checking, input: limits.program, },
      })
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
    selected.output is Some(Ok(output)) else {
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
