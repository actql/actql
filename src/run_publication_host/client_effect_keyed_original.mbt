///|
/// Exact Source-only Effect/Request/compiler binding on its original Resource
/// inventory. This is retained DATA; it grants neither Source access nor IO.
struct ClientEffectKeyedOriginal {
  prepared : PreparedClientEffectComputation
  compilation : ClientEffectCompilation
  compiled : ClientCompiledRun
  definition : @publication.PublicationContract
  request : ClientRequestIdentity
  plan : ClientEffectKeyedPlanGraph
  keyed : ClientKeyedAcquisition
  ledger : @resources.Ledger
  identity : @resources.OriginalLedgerIdentity
  mut started : Bool
  mut generic : ClientEffectKeyedGenericState?
}

///|
pub fn client_effect_keyed_original_construction_inventory() -> @execution.PreparationRepresentationUnits {
  // Retained binding H1/R10/W1 (consumed start and generic state), owner Some H1/R1/W1
  // and transient Result H1/R1/W1.
  {
    record_headers: 3L,
    reference_slots: 12L,
    scalar_words: 3L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}

///|
pub fn bind_client_effect_keyed_original(
  prepared : PreparedClientEffectComputation,
  compilation : ClientEffectCompilation,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  request : ClientRequestIdentity,
  plan : ClientEffectKeyedPlanGraph,
  keyed : ClientKeyedAcquisition,
  ledger : @resources.Ledger,
  identity : @resources.OriginalLedgerIdentity,
) -> Result[ClientEffectKeyedOriginal, ClientKeyedRequestIssue] {
  guard client_compiled_run_matches_effect(compiled, prepared, compilation) &&
    client_effect_keyed_plan_graph_matches(plan, prepared, keyed) &&
    check_client_compiled_run_definition(compiled, definition) is Ok(_) &&
    prepared_client_effect_request_scope(prepared, request) is Ok(_) &&
    @resources.original_ledger_preparation_available(identity) else {
    return Err(ForeignLeft)
  }
  // Claim the existing Run association exactly once, including the nominal
  // same-Ledger check. No second inventory or capacity is created.
  match @resources.claim_original_ledger_run_binding(identity, ledger) {
    Err(_) => return Err(ForeignLeft)
    Ok(_) => ()
  }
  Ok({
    prepared,
    compilation,
    compiled,
    definition,
    request,
    plan,
    keyed,
    ledger,
    identity,
    started: false,
    generic: None,
  })
}

///|
fn client_effect_keyed_original_available(
  value : ClientEffectKeyedOriginal,
) -> Bool {
  client_compiled_run_matches_effect(
    value.compiled,
    value.prepared,
    value.compilation,
  ) &&
  client_effect_keyed_plan_graph_matches(
    value.plan,
    value.prepared,
    value.keyed,
  ) &&
  @resources.original_ledger_inventory_available(value.identity)
}

///|
pub fn start_client_effect_keyed_capture_lookup_input(
  original : ClientEffectKeyedOriginal,
  rows : Array[@row_host.RowCapturedInput],
  max_entries : Int,
  max_name_bytes : Int,
  max_bytes : Int,
  max_work : Int,
  source_sequence? : @execution.GeneratedSequence? = None,
  max_nodes? : Int = max_work,
) -> Result[ClientKeyedLookupInput, ClientKeyedRequestIssue] {
  guard client_effect_keyed_original_available(original) && !original.started else {
    return Err(ForeignLeft)
  }
  // Consume this original before the first callback. Refusal retains the fact;
  // recursive or second start cannot create another lookup/attempt history.
  original.started = true
  guard rows is [row] &&
    @row_host.row_captured_input_source(row) is Some(source) &&
    @row_host.borrow_row_captured_input_originals(
      rows,
      original.ledger,
      max_entries,
    )
    is Some(captures) else {
    return Err(ForeignLeft)
  }
  let left = match
    prepare_client_keyed_capture_left_read(
      original.keyed,
      source,
      max_entries,
      max_name_bytes,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  guard @execution.producer_read_original_output(left.read) is Some(output) &&
    @query.captured_source_matches_segment_input(source, left.read) &&
    client_effect_keyed_original_available(original) else {
    return Err(ForeignLeft)
  }
  let join = @acquisition.keyed_join_step(original.keyed.binding.join)
  let sequence = match source_sequence {
    Some(sequence) => {
      guard physical_equal(
        @execution.generated_sequence_owner(sequence),
        original.keyed.owner,
      ) else {
        return Err(ForeignLeft)
      }
      sequence
    }
    None => {
      guard @row_host.row_captured_input_requirement_at(captures, 0)
        is Some(requirement) else {
        return Err(ForeignLeft)
      }
      @query.query_generated_sequence(
        @planning.query_material_owner(
          @planning.query_requirement_material(requirement),
        ),
      )
    }
  }
  let composed : ClientComposedKeyedOriginal = {
    origin: SourceEffectOrigin(original),
    compiled: original.compiled,
    definition: original.definition,
    keyed: original.keyed,
    sources: [source],
    captures,
    // This sequence is compiler DATA only, never a completed prefix. The
    // actual captured operation's read/output above supplies its completion.
    sequence,
    inputs: [(join, 0, left.read)],
    completed: None,
    direct_output: Some(output),
    prefix: None,
    prefix_work: 0L,
    producers: NoProducers,
    host: None,
    host_sources: [],
  }
  let bound : ClientKeyedLeftRead = { ..left, composed: Some(composed), }
  start_client_keyed_lookup_input_owned(
    bound,
    original.ledger,
    max_bytes,
    max_work,
    None,
    max_nodes~,
  )
}

///|
/// Nominal correspondence of the Source-only preparation retained on its SAME
/// installed Plan. This does not admit IO or replace a current observation.
pub fn client_effect_keyed_original_matches(
  value : ClientEffectKeyedOriginal,
  prepared : PreparedClientEffectComputation,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  request : ClientRequestIdentity,
  plan : ClientEffectKeyedPlanGraph,
  keyed : ClientKeyedAcquisition,
  ledger : @resources.Ledger,
) -> Bool {
  physical_equal(value.prepared, prepared) &&
  physical_equal(value.compiled, compiled) &&
  physical_equal(value.definition, definition) &&
  client_request_identity_relation(value.request, request) is SameRequest &&
  physical_equal(value.plan, plan) &&
  physical_equal(value.keyed, keyed) &&
  physical_equal(value.ledger, ledger) &&
  client_effect_keyed_original_available(value)
}

///|
/// Callback-free live original inventory. External current/permission checks
/// remain with the actual installed Source and Journal operation.
pub fn client_effect_keyed_original_current(
  value : ClientEffectKeyedOriginal,
) -> Bool {
  client_effect_keyed_original_available(value)
}

///|
pub fn client_effect_keyed_lookup_matches_parent(
  lookup : ClientKeyedLookupInput,
  parent : ClientEffectKeyedOriginal,
  ledger : @resources.Ledger,
) -> Bool {
  lookup.left.composed is Some(original) &&
  original.origin is SourceEffectOrigin(bound) &&
  physical_equal(bound, parent) &&
  physical_equal(lookup.ledger, ledger) &&
  physical_equal(parent.ledger, ledger) &&
  physical_equal(original.keyed, lookup.left.acquisition) &&
  lookup.left.source is Some(source) &&
  original.sources is [same] &&
  physical_equal(source, same) &&
  !lookup.closed &&
  client_composed_keyed_original_current(original)
}

///|
pub fn client_effect_keyed_request_matches_parent(
  request : ClientKeyedRequest,
  parent : ClientEffectKeyedOriginal,
  ledger : @resources.Ledger,
) -> Bool {
  client_keyed_request_matches_acquisition(request, parent.keyed) &&
  request.assembly_accounting is Some(lookup) &&
  physical_equal(request.left, lookup.left) &&
  lookup.selected_request is Some(selected) &&
  physical_equal(selected, request) &&
  lookup.selected_index == Some(-1) &&
  request.row == keyed_lookup_next_original_row(lookup) &&
  request.attempts == 0L &&
  !request.io_complete &&
  lookup.completed is None &&
  lookup.copying is None &&
  lookup.preparation is None &&
  client_effect_keyed_lookup_matches_parent(lookup, parent, ledger) &&
  @resources.original_borrowed_reservation_available(
    parent.identity,
    ledger,
    lookup.reservation,
  )
}

///|
/// The existing child may retain its SAME request after the selected slot or
/// physical attempt advances. This cannot authorize a second attempt.
pub fn client_effect_keyed_request_retained_parent(
  request : ClientKeyedRequest,
  parent : ClientEffectKeyedOriginal,
  ledger : @resources.Ledger,
) -> Bool {
  client_keyed_request_matches_acquisition(request, parent.keyed) &&
  request.assembly_accounting is Some(lookup) &&
  physical_equal(request.left, lookup.left) &&
  client_effect_keyed_lookup_matches_parent(lookup, parent, ledger)
}

///|
pub fn client_effect_keyed_request_rows(
  request : ClientKeyedRequest,
  parent : ClientEffectKeyedOriginal,
  ledger : @resources.Ledger,
) -> Int? {
  guard client_effect_keyed_request_retained_parent(request, parent, ledger) else {
    return None
  }
  let rows = @execution.producer_read_row_count(request.left.read)
  guard request.row >= 0 &&
    request.row < rows &&
    client_effect_keyed_request_retained_parent(request, parent, ledger) else {
    return None
  }
  Some(rows)
}

///|
pub fn client_effect_keyed_lookup_sources_match(
  lookup : ClientKeyedLookupInput,
  parent : ClientEffectKeyedOriginal,
  sources : Array[@query.CapturedInputSource],
) -> Bool {
  guard client_effect_keyed_lookup_matches_parent(lookup, parent, parent.ledger) &&
    lookup.left.composed is Some(original) &&
    sources.length() == original.sources.length() else {
    return false
  }
  for index, source in sources {
    if !physical_equal(source, original.sources[index]) {
      return false
    }
  }
  true
}

///|
/// Exact extra Source-original controls before start. Rows remain in their
/// original capture and the existing lookup grows its own empty assembly on
/// use; no row-count or codec ceiling is converted into preallocated bytes.
/// The columns are the actual checked receiver schema at this selected JOIN.
pub fn client_effect_keyed_capture_start_construction_inventory(
  original : ClientEffectKeyedOriginal,
) -> @execution.PreparationRepresentationUnits? {
  guard client_effect_keyed_original_available(original) &&
    !original.started &&
    @lower.preparation_schema_at(
      @lower.bound_preparation(original.keyed.owner),
      @acquisition.keyed_join_left(original.keyed.binding.join),
    )
    is Some(schema) &&
    @row_host.row_captured_inputs_construction_inventory(1) is Some(captures) &&
    @shape.collection_construction_extent({
      // Restricted completion/output/closure/Some, bound producer+identity,
      // producer preparation/read/Result/Some and original left+copy/Options,
      // composed original+closed origin, input tuple and return carriers.
      // Same Host raw-confirmation reader duty/flight and its narrow Store
      // callbacks add H4/R12/W3 before the Node publication port exists.
      records: 24L,
      record_references: 74L,
      record_words: 45L,
      reference_arrays: 3L,
      reference_items: 2L,
      scalar_arrays: 1L,
      scalar_items: @schema.field_count(schema).to_int64(),
      maps: 0L,
      map_entries: 0L,
    })
    is Some(controls) else {
    return None
  }
  @execution.compose_preparation_representation([
    captures,
    {
      record_headers: controls.record_headers,
      reference_slots: controls.reference_slots,
      scalar_words: controls.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
  ])
}

///|
/// Borrow the same immutable left object already owned by this lookup. This
/// neither starts a second assembly nor confers a current Source permission.
pub fn client_keyed_lookup_left(
  lookup : ClientKeyedLookupInput,
) -> ClientKeyedLeftRead {
  lookup.left
}
