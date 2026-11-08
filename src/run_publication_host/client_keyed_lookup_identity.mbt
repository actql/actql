///|
/// Immutable semantic publication metadata for one original completed lookup.
/// The retained lookup identifies its provenance; this value grants no access
/// and cannot restore a retired physical child.
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
    lookup.pending_request is Some(_) {
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
  for (_, original, _) in lookup.known {
    guard original is Some(original) &&
      physical_equal(@acquisition.keyed_row_request_owner(original), template) else {
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
  let static_request = match
    @acquisition.parameterized_keyed_static_request_wire(
      template, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Wire(issue))
  }
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
) -> Result[@execution.SuppliedRelationRead, ClientKeyedRequestIssue] {
  if lookup.publication_identity is Some(_) {
    return finish_client_keyed_lookup_input(lookup)
  }
  if lookup.closed ||
    lookup.growing ||
    lookup.completed is Some(_) ||
    lookup.copying is Some(_) ||
    lookup.preparation is Some(_) ||
    lookup.pending_request is Some(_) ||
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
  let metadata = 16L * max_bytes.to_int64() + 128L * slots
  if metadata > 9223372036854775807L - lookup.retained_bytes {
    return Err(Assembly("capacity_overflow"))
  }
  let retained = lookup.retained_bytes + metadata
  lookup.growing = true
  let grown = @resources.grow_execution_reservation_capacity(
    lookup.ledger,
    lookup.reservation,
    retained,
    Int64::max(lookup.execution_bytes, metadata),
  )
  lookup.growing = false
  match grown {
    Err(issue) => {
      keyed_lookup_fail(lookup.left, Physical(issue)) |> ignore
      return Err(Physical(issue))
    }
    Ok(_) => {
      lookup.retained_bytes = retained
      lookup.execution_bytes = Int64::max(lookup.execution_bytes, metadata)
    }
  }
  if lookup.closed ||
    lookup.left.lookup_issue is Some(_) ||
    !client_keyed_left_available(lookup.left) ||
    lookup.closed {
    let issue = Assembly("retired_publication_input")
    keyed_lookup_fail(lookup.left, issue) |> ignore
    return Err(issue)
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
  let rows = match @execution.finish_ordered_admitted_input(input, order) {
    Ok(rows) => rows
    Err(issue) => {
      keyed_lookup_fail(lookup.left, InputCapture(issue)) |> ignore
      return Err(InputCapture(issue))
    }
  }
  lookup.completed = Some(rows)
  lookup.publication_identity = Some(identity)
  finish_client_keyed_lookup_input(lookup)
}
