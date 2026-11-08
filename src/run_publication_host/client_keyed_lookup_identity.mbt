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
/// caller's original capture operation backs the returned key-set/static
/// request metadata. This issues no request or reference and rechecks no
/// input row, Model, Program or provider response.
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
  let keys = match
    @publication.issue_lookup_request_key_set(
      @acquisition.selected_cid(selected),
      schema,
      roles,
      tuples,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Identity(issue))
  }
  let static_request = match
    @acquisition.parameterized_keyed_static_request_wire(
      template, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Wire(issue))
  }
  if client_keyed_lookup_input_identity(lookup) is None {
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
  Ok({ original: lookup, keys, static_request, static_request_cid, scope, })
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
