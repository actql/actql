///|
/// Immutable request-set metadata for one original checked lookup. Its
/// predispatch preparation and later completed publication reuse this SAME
/// value; it proves no response, attempt, access or physical cleanup.
struct ClientKeyedLookupRequestIdentity {
  original : ClientKeyedLookupInput
  keys : @publication.PublicationContract
  static_request : String
  static_request_cid : String
  scope : @publication.PublicationContract
}

///|
/// Borrow the completed assembly's actual checked request originals. The
/// caller's original capture operation backs late-issued metadata; the early
/// publication purpose instead retains the SAME metadata on its lookup. This
/// issues no request or reference and rechecks no input row, Model, Program or
/// provider response.
pub fn client_keyed_lookup_request_identity(
  lookup : ClientKeyedLookupInput,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientKeyedLookupRequestIdentity, ClientKeyedRequestIssue] {
  if client_keyed_lookup_input_identity(lookup) is None ||
    lookup.pending_history is Some(_) {
    return Err(Assembly("unavailable_request_identity"))
  }
  if lookup.publication_identity is Some(original) {
    return Ok(original)
  }
  build_client_keyed_lookup_request_identity(
    lookup, max_bytes, max_nodes, max_depth, false,
  ).map(value => value.0)
}

///|
fn build_client_keyed_lookup_request_identity(
  lookup : ClientKeyedLookupInput,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  retain_order : Bool,
) -> Result[
  (ClientKeyedLookupRequestIdentity, Array[Int]),
  ClientKeyedRequestIssue,
] {
  let template = @acquisition.keyed_join_request(
    lookup.left.acquisition.binding.join,
  )
  let request = @acquisition.parameterized_keyed_request(template)
  let correlation = @acquisition.keyed_request_correlation(request)
  let count = @environment.source_correlation_pair_count(correlation)
  if count < 1 || count > max_nodes || lookup.known.length() > max_nodes / count {
    return Err(Assembly("request_identity_limit"))
  }
  let roles = Array::makei(count, index => {
    let role = @environment.source_correlation_pair_at(correlation, index).unwrap().request
    (role.name, role.contract)
  })
  roles.sort_by((a, b) => @canonical_value.compare_utf16(a.0, b.0))
  let tuples : Array[Array[@values.CheckedValue]] = []
  for (_, _, history) in lookup.known {
    guard history is Some(history) else {
      return Err(Assembly("missing_request_history"))
    }
    let original = history.request.request
    guard physical_equal(
      @acquisition.keyed_row_request_owner(original),
      template,
    ) else {
      return Err(Assembly("foreign_request_identity"))
    }
    let tuple = []
    for (role, _) in roles {
      guard @acquisition.keyed_row_request_field(original, role) is Some(value) else {
        return Err(Assembly("missing_request_identity_role"))
      }
      tuple.push(value)
    }
    tuples.push(tuple)
  }
  let selected = @acquisition.keyed_request_input(request)
  let schema = @environment.contract_identity(
      @environment.reference_contract(
        @environment.source_request_reference(
          @acquisition.selected_contract(selected),
        ),
      ),
    ).2
  let issued = if retain_order {
    @publication.issue_lookup_request_key_set_with_order(
      @acquisition.selected_cid(selected),
      schema,
      roles,
      tuples,
      max_bytes,
      max_nodes,
      max_depth,
    )
  } else {
    @publication.issue_lookup_request_key_set(
      @acquisition.selected_cid(selected),
      schema,
      roles,
      tuples,
      max_bytes,
      max_nodes,
      max_depth,
    ).map(keys => (keys, []))
  }
  let (keys, order) = match issued {
    Ok(value) => value
    Err(issue) => return Err(Identity(issue))
  }
  if retain_order && (lookup.closed || lookup.left.lookup_issue is Some(_)) {
    return Err(Assembly("retired_publication_input"))
  }
  let static_document = match
    @acquisition.parameterized_keyed_static_request_document(
      template, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Wire(issue))
  }
  let static_request = @encode.document_text(static_document)
  // Static reference emission can invoke original current too. This is the
  // original post-emission boundary, before pure hash/scope construction.
  if retain_order {
    if !client_keyed_left_available(lookup.left) ||
      lookup.closed ||
      lookup.left.lookup_issue is Some(_) {
      return Err(Assembly("retired_publication_input"))
    }
  } else if client_keyed_lookup_input_identity(lookup) is None {
    return Err(Assembly("retired_request_identity"))
  }
  if lookup.native_read_profile is Some(_) {
    lookup.native_static_request = Some(static_document)
  }
  let static_request_cid = match @sha.text_hex(static_request) {
    Ok(hash) => "sha256:" + hash
    Err(_) => return Err(Assembly("static_request_encoding"))
  }
  let scope = match
    @publication.issue_keyed_source_acquisition_scope(
      @acquisition.selected_cid(selected),
      static_request_cid,
      keys,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(scope) => scope
    Err(issue) => return Err(Identity(issue))
  }
  Ok(
    (
      { original: lookup, keys, static_request, static_request_cid, scope, },
      order,
    ),
  )
}

///|
/// Pure original-reference correspondence, not a physical-current observation.
pub fn client_keyed_lookup_request_identity_matches(
  value : ClientKeyedLookupRequestIdentity,
  lookup : ClientKeyedLookupInput,
) -> Bool {
  physical_equal(value.original, lookup)
}

///|
/// Read the already-issued metadata. No re-encoding, rehashing or callback;
/// actual access and publication still require the original live capture.
pub fn client_keyed_lookup_request_identity_parts(
  value : ClientKeyedLookupRequestIdentity,
) -> (
  @publication.PublicationContract,
  String,
  String,
  @publication.PublicationContract,
) {
  (value.keys, value.static_request, value.static_request_cid, value.scope)
}

///|
/// Complete the original one-response-per-request assembly in typed request
/// order before its first supplied read/logical identity escapes. The bounded
/// protocol constructor and actual tuple/row controls use the SAME lookup
/// reservation, not a whole-file ceiling or a second acquisition allowance.
/// Equal-key response identity remains the Source's declared response law;
/// the returned tuple order alone is never evidence of response admission.
pub fn finish_client_keyed_lookup_publication_input(
  lookup : ClientKeyedLookupInput,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  retain_body? : Bool = false,
  native_completion? : (String, Int64)? = None,
) -> Result[@execution.SuppliedRelationRead, ClientKeyedRequestIssue] {
  if native_completion is Some(_) && !retain_body {
    return Err(Assembly("native_completion_requires_original_body"))
  }
  if lookup.publication_identity is Some(_) {
    if lookup.planned_requests is Some(_) && lookup.completed is None {
      guard !lookup.closed &&
        !lookup.growing &&
        !lookup.identifying &&
        lookup.left.lookup_issue is None &&
        lookup.accepted == lookup.rows &&
        lookup.copying is None &&
        lookup.preparation is None &&
        lookup.pending_history is None &&
        lookup.input is Some(input) &&
        lookup.planned_order is Some(order) else {
        return Err(Assembly("unavailable_planned_publication"))
      }
      let completed = if lookup.native_batch_plan is Some(_) {
        // Physical singleton responses were already admitted in this frozen
        // canonical key order. Applying the original-slot permutation again
        // would reorder them twice. Left occurrence order remains upstream.
        if lookup.planned_dispatch_order is None ||
          lookup.completed_responses != order.length() {
          return Err(Assembly("incomplete_native_batch_responses"))
        }
        @execution.finish_admitted_input(input)
      } else {
        @execution.finish_ordered_admitted_input(input, order)
      }
      let rows = match completed {
        Ok(rows) => rows
        Err(issue) => return Err(InputCapture(issue))
      }
      lookup.completed = Some(rows)
    }
    return if retain_body {
      finish_keyed_lookup_identity_bodies(
        lookup,
        native_completion=native_completion.map(value => {
          (value.0, value.1, max_bytes, max_nodes, max_depth)
        }),
      )
    } else {
      finish_client_keyed_lookup_input(lookup)
    }
  }
  if lookup.closed ||
    lookup.growing ||
    lookup.identifying ||
    lookup.completed is Some(_) ||
    lookup.copying is Some(_) ||
    lookup.preparation is Some(_) ||
    lookup.pending_history is Some(_) ||
    lookup.accepted != lookup.rows ||
    lookup.left.lookup_issue is Some(_) ||
    !client_keyed_left_available(lookup.left) {
    return Err(Assembly("unavailable_publication_input"))
  }
  guard lookup.input is Some(input) else {
    return Err(Assembly("closed_input"))
  }
  if lookup.closed || lookup.left.lookup_issue is Some(_) {
    return Err(Assembly("retired_publication_input"))
  }
  let (identity, order) = match
    prepare_keyed_lookup_request_metadata(
      lookup, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let rows = match @execution.finish_ordered_admitted_input(input, order) {
    Ok(rows) => rows
    Err(issue) => {
      keyed_lookup_fail(lookup.left, InputCapture(issue)) |> ignore
      return Err(InputCapture(issue))
    }
  }
  lookup.completed = Some(rows)
  lookup.publication_identity = Some(identity)
  if retain_body {
    finish_keyed_lookup_identity_bodies(
      lookup,
      native_completion=native_completion.map(value => {
        (value.0, value.1, max_bytes, max_nodes, max_depth)
      }),
    )
  } else {
    finish_client_keyed_lookup_input(lookup)
  }
}

///|
fn prepare_keyed_lookup_request_metadata(
  lookup : ClientKeyedLookupInput,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (ClientKeyedLookupRequestIdentity, Array[Int]),
  ClientKeyedRequestIssue,
] {
  guard lookup.input is Some(input) else {
    return Err(Assembly("closed_input"))
  }
  let template = @acquisition.keyed_join_request(
    lookup.left.acquisition.binding.join,
  )
  let request = @acquisition.parameterized_keyed_request(template)
  let role_count = @environment.source_correlation_pair_count(
    @acquisition.keyed_request_correlation(request),
  )
  if max_bytes < 1 ||
    max_nodes < 1 ||
    max_depth < 1 ||
    role_count < 1 ||
    role_count > max_nodes ||
    lookup.known.length() > max_nodes / role_count {
    return Err(Assembly("request_identity_limit"))
  }
  // Same finite protocol-metadata envelope used by the native publication
  // boundary. The row/reference/index overlap scales with ACTUAL stored
  // request slots. This occurs only at the explicit publication constructor,
  // never at Source startup and never from a file/output policy maximum.
  let slots = role_count.to_int64() * lookup.known.length().to_int64() +
    role_count.to_int64() +
    lookup.known.length().to_int64()
  let metadata_phase = match
    grow_keyed_lookup_protocol_metadata(
      lookup,
      max_bytes,
      slots,
      // Retained EncodedDocument1H1R3W + Some1H1R1W. Text stays borrowed.
      extra_controls=if lookup.native_read_profile is Some(_) {
        80L
      } else {
        0L
      },
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  // Reference key projection can invoke its original current observer. Keep
  // the original input/response holders until that synchronous borrow ends.
  lookup.growing = true
  let built = build_client_keyed_lookup_request_identity(
    lookup, max_bytes, max_nodes, max_depth, true,
  )
  lookup.growing = false
  let (identity, order) = match built {
    Ok(value) => value
    Err(issue) => {
      keyed_lookup_fail(lookup.left, issue) |> ignore
      return Err(issue)
    }
  }
  // The builder already observed original current after its last reference
  // callback. Pure hash/scope work adds no new external-state boundary here.
  if lookup.closed ||
    lookup.left.lookup_issue is Some(_) ||
    !(lookup.input is Some(original) && physical_equal(original, input)) {
    let issue = Assembly("retired_publication_input")
    keyed_lookup_fail(lookup.left, issue) |> ignore
    return Err(issue)
  }
  match
    finish_keyed_lookup_protocol_metadata(
      lookup,
      metadata_phase,
      max_nodes,
      max_depth,
      [identity.keys, identity.scope],
      texts=[identity.static_request, identity.static_request_cid],
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  Ok((identity, order))
}

///|
/// Close the actual checked key set/static request/scope before the first
/// provider dispatch. This DATA is not a batch or attempt receipt. The existing
/// transport/batch/activation owners still have to bind their actual history.
pub fn finish_client_keyed_lookup_request_plan(
  lookup : ClientKeyedLookupInput,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientKeyedLookupRequestIdentity, ClientKeyedRequestIssue] {
  guard !lookup.closed &&
    !lookup.growing &&
    !lookup.identifying &&
    lookup.planned_requests is Some(requests) &&
    requests.length() == lookup.rows &&
    lookup.planned_order is None &&
    lookup.publication_identity is None &&
    lookup.accepted == 0 &&
    lookup.selected_request is None &&
    lookup.preparation is None &&
    lookup.pending_history is None &&
    lookup.copying is None &&
    lookup.left.lookup_issue is None else {
    return Err(Assembly("unfinished_request_plan"))
  }
  let (identity, order) = match
    prepare_keyed_lookup_request_metadata(
      lookup, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // Distinct wire requests for one typed equality key need a declared
  // canonical request mapping. Never pick an authorization envelope by input
  // enumeration merely because its semantic Ref identity is equal.
  if @publication.lookup_request_key_set_tuple_count(identity.keys) !=
    Some(lookup.known.length()) {
    let issue = Assembly("ambiguous_typed_request")
    keyed_lookup_fail(lookup.left, issue) |> ignore
    return Err(issue)
  }
  if lookup.native_read_profile is Some(_) {
    match
      prepare_client_keyed_native_transport(
        lookup, max_bytes, max_nodes, max_depth,
      ) {
      Err(issue) => {
        keyed_lookup_fail(lookup.left, issue) |> ignore
        return Err(issue)
      }
      Ok(_) => ()
    }
  }
  lookup.publication_identity = Some(identity)
  lookup.planned_order = Some(order)
  Ok(identity)
}

///|
/// Borrow the already-closed predispatch metadata, without re-encoding/hash or
/// current callbacks. Its original lookup still owns all access and cleanup.
pub fn client_keyed_lookup_planned_request_identity(
  lookup : ClientKeyedLookupInput,
) -> ClientKeyedLookupRequestIdentity? {
  if lookup.closed ||
    lookup.left.lookup_issue is Some(_) ||
    lookup.planned_order is None {
    None
  } else {
    lookup.publication_identity
  }
}

///|
/// Existing closed-protocol writer/parser construction quote. These quantities
/// are DATA only; the owning Run must fund them before encoding. Share the same
/// quote between keyed metadata and ordinary whole-Source Model evidence.
pub fn client_protocol_metadata_construction_bytes(
  max_bytes : Int,
  slots : Int64,
  extra_controls? : Int64 = 0L,
  copies? : Int = 1,
) -> (Int64, Int64)? {
  guard copies > 0 &&
    @execution.checked_preparation_add_product(
      0L,
      16L * max_bytes.to_int64(),
      copies.to_int64(),
    )
    is Some(bodies) &&
    @execution.checked_preparation_add_product(0L, 128L, slots) is Some(fields) &&
    @execution.checked_preparation_add_product(fields, extra_controls, 1L)
    is Some(controls) &&
    @execution.checked_preparation_add_product(bodies, controls, 1L)
    is Some(metadata) else {
    return None
  }
  Some((metadata, controls))
}

///|
fn grow_keyed_lookup_protocol_metadata(
  lookup : ClientKeyedLookupInput,
  max_bytes : Int,
  slots : Int64,
  extra_controls? : Int64 = 0L,
  copies? : Int = 1,
) -> Result[(Int64, Int64, Int64), ClientKeyedRequestIssue] {
  guard client_protocol_metadata_construction_bytes(
      max_bytes,
      slots,
      extra_controls~,
      copies~,
    )
    is Some((metadata, controls)) else {
    return Err(Assembly("capacity_overflow"))
  }
  if metadata > 9223372036854775807L - lookup.retained_bytes ||
    metadata > 9223372036854775807L - lookup.execution_bytes {
    return Err(Assembly("capacity_overflow"))
  }
  let basis = (lookup.retained_bytes, lookup.execution_bytes, controls)
  let retained = lookup.retained_bytes + metadata
  let execution = lookup.execution_bytes + metadata
  lookup.growing = true
  let grown = @resources.grow_execution_reservation_capacity(
    lookup.ledger,
    lookup.reservation,
    retained,
    execution,
  )
  lookup.growing = false
  match grown {
    Err(issue) => {
      keyed_lookup_fail(lookup.left, Physical(issue)) |> ignore
      return Err(Physical(issue))
    }
    Ok(_) => {
      lookup.retained_bytes = retained
      lookup.execution_bytes = execution
    }
  }
  if lookup.closed ||
    lookup.left.lookup_issue is Some(_) ||
    !client_keyed_left_available(lookup.left) {
    let issue = Assembly("retired_publication_input")
    keyed_lookup_fail(lookup.left, issue) |> ignore
    return Err(issue)
  }
  Ok(basis)
}

///|
// Price only the original closed protocol backing, using the shared tariff.
// Canonical nodes are conservatively charged as payload-bearing variants;
// FrozenArray/Array/backing and object entry tuples include spare slots.
// Contract/evidence control, optional wire-usage tuple and Strings remain.
fn keyed_lookup_protocol_extent_cost(
  extent : @publication.PublicationRepresentationExtent,
) -> Int64? {
  let tree = extent.canonical
  let containers = tree.arrays + tree.objects
  @execution.preparation_representation_cost({
    record_headers: 3L * extent.contract_records +
    extent.contract_strings +
    tree.nodes +
    tree.strings +
    3L * containers +
    tree.object_backing_slots,
    reference_slots: 7L * extent.contract_records +
    tree.nodes +
    2L * containers +
    tree.array_backing_slots +
    3L * tree.object_backing_slots,
    scalar_words: 5L * extent.contract_records +
    2L * tree.nodes +
    2L * containers,
    owned_utf16_units: extent.contract_text_utf16_units + tree.text_utf16_units,
    owned_wire_bytes: 0L,
  })
}

///|
// Called only after the actual writers/scans have returned and their outputs
// are retained on this same lookup (or the original returning frame). Failure
// keeps the construction peak. Success returns only unused codec workspace;
// all previous backing, actual bodies and call controls remain charged.
fn finish_keyed_lookup_protocol_metadata(
  lookup : ClientKeyedLookupInput,
  phase : (Int64, Int64, Int64),
  max_nodes : Int,
  max_depth : Int,
  contracts : Array[@publication.PublicationContract],
  evidence? : Array[@publication.RunEvidenceValue] = [],
  texts? : Array[String] = [],
) -> Result[Unit, ClientKeyedRequestIssue] {
  if max_nodes < 1 || max_depth < 1 || lookup.closed || lookup.growing {
    return Err(Assembly("unavailable_protocol_workspace_return"))
  }
  // Bound the existing immutable extent walk BEFORE allocating its depth
  // stack. No wire is re-encoded/hashed/admitted and no permission is observed.
  let frames = 4L * (max_depth.to_int64() + 1L) +
    4L * (contracts.length().to_int64() + evidence.length().to_int64() + 1L)
  let scratch = @execution.preparation_representation_cost({
    record_headers: 12L + frames,
    reference_slots: 24L + 4L * frames,
    scalar_words: 16L + 4L * frames,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  match
    keyed_lookup_body_grow(
      lookup,
      lookup.retained_bytes,
      lookup.execution_bytes,
      scratch,
      None,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let mut retained = phase.2
  for contract in contracts {
    let extent = match
      @publication.publication_contract_representation_extent(
        contract, max_nodes, max_depth, 2147483647,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Identity(@publication.Contract(issue)))
    }
    guard keyed_lookup_protocol_extent_cost(extent) is Some(bytes) &&
      @execution.checked_preparation_add_product(retained, bytes, 1L)
      is Some(total) else {
      return Err(Assembly("capacity_overflow"))
    }
    retained = total
  }
  for original in evidence {
    let extent = match
      @publication.run_evidence_value_representation_extent(
        original, max_nodes, max_depth, 2147483647,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Identity(@publication.Contract(issue)))
    }
    guard keyed_lookup_protocol_extent_cost(extent) is Some(bytes) &&
      @execution.checked_preparation_add_product(retained, bytes, 1L)
      is Some(total) else {
      return Err(Assembly("capacity_overflow"))
    }
    retained = total
  }
  for text in texts {
    guard @execution.preparation_representation_cost({
        record_headers: 1L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: text.length().to_int64(),
        owned_wire_bytes: 0L,
      })
      is Some(bytes) &&
      @execution.checked_preparation_add_product(retained, bytes, 1L)
      is Some(total) else {
      return Err(Assembly("capacity_overflow"))
    }
    retained = total
  }
  guard @execution.checked_preparation_add_product(phase.0, retained, 1L)
    is Some(r) &&
    @execution.checked_preparation_add_product(phase.1, retained, 1L) is Some(e) else {
    return Err(Assembly("capacity_overflow"))
  }
  lookup.growing = true
  let reduced = @resources.reduce_execution_reservation_capacity(
    lookup.ledger,
    lookup.reservation,
    r,
    e,
  )
  match reduced {
    Err(issue) => {
      lookup.growing = false
      return Err(Physical(issue))
    }
    Ok(_) => {
      lookup.retained_bytes = r
      lookup.execution_bytes = e
    }
  }
  let available = client_keyed_left_available(lookup.left)
  lookup.growing = false
  if lookup.closed || lookup.left.lookup_issue is Some(_) || !available {
    return Err(Assembly("retired_publication_input"))
  }
  Ok(())
}
