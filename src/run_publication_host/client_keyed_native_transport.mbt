///|
// Same checked Catalog, not a new profile issuer or a Host-supplied grant.
fn check_client_keyed_native_read_profile(
  lookup : ClientKeyedLookupInput,
  profile : @publication.PublicationContract,
) -> Result[Unit, ClientKeyedRequestIssue] {
  if lookup.left.composed is Some(original) &&
    original.plan.keyed is Some(component) {
    guard physical_equal(original.keyed, lookup.left.acquisition) &&
      physical_equal(component.original.fragments.acquisition, original.keyed) &&
      physical_equal(component.original.profile, profile) else {
      return Err(Assembly("foreign_native_read_profile"))
    }
    return Ok(())
  }
  check_client_keyed_native_acquisition_profile(
    lookup.left.acquisition,
    profile,
  )
}

///|
// Shared by first-Plan construction and the existing physical reader. The
// selected original Catalog is the authority for implementation correspondence.
fn check_client_keyed_native_acquisition_profile(
  keyed : ClientKeyedAcquisition,
  profile : @publication.PublicationContract,
) -> Result[Unit, ClientKeyedRequestIssue] {
  let selected = @acquisition.keyed_request_input(
    @acquisition.parameterized_keyed_request(
      @acquisition.keyed_join_request(keyed.binding.join),
    ),
  )
  let request = @environment.contract_identity(
      @environment.reference_contract(
        @environment.source_request_reference(
          @acquisition.selected_contract(selected),
        ),
      ),
    ).2
  guard @planning.keyed_source_evidence_facts(keyed.facts) is Some(facts) &&
    @publication.native_file_read_profile_contract_bindings(profile)
    is Some((source, request_schema, response)) &&
    source == facts.source_view_contract_cid &&
    request_schema == request &&
    response == facts.carrier_schema_contract_cid else {
    return Err(Assembly("foreign_native_read_profile"))
  }
  guard @planning.keyed_source_evidence_members(keyed.facts) is Ok(members) &&
    @environment.connector_source_evidence_supports(members, [
      @publication.publication_contract_identity(profile),
    ]) else {
    return Err(Assembly("undeclared_native_read_profile"))
  }
  Ok(())
}

///|
// Called only inside the same predispatch metadata construction. The actual
// original static document survived its first writer; no new Request/check.
fn prepare_client_keyed_native_transport(
  lookup : ClientKeyedLookupInput,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, ClientKeyedRequestIssue] {
  guard lookup.native_read_profile is Some(profile) &&
    lookup.native_static_request is Some(document) else {
    return Err(Assembly("missing_native_transport_originals"))
  }
  let (_, nodes, _) = @encode.document_usage(document)
  // Reuse the same bounded protocol-metadata recipe with the actual static
  // subtree nodes,16 envelope values,16 field names and the final CID pair.
  match
    grow_keyed_lookup_protocol_metadata(
      lookup,
      max_bytes,
      34L + nodes.to_int64(),
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  lookup.growing = true
  let result = @publication.issue_native_file_lookup_transport(
    profile, document, max_bytes, max_nodes, max_depth,
  )
  lookup.growing = false
  if lookup.closed || lookup.left.lookup_issue is Some(_) {
    return Err(Assembly("retired_native_transport"))
  }
  let transport = match result {
    Ok(value) => value
    Err(issue) => return Err(Identity(@publication.Contract(issue)))
  }
  lookup.native_transport = Some(transport)
  Ok(())
}

///|
/// Pure original DATA borrow. Access and actual dispatch remain with the same
/// checked lookup/read; this is neither a batch nor a completed attempt proof.
pub fn client_keyed_lookup_native_transport(
  lookup : ClientKeyedLookupInput,
) -> @publication.PublicationContract? {
  if lookup.closed ||
    lookup.left.lookup_issue is Some(_) ||
    lookup.planned_order is None {
    None
  } else {
    lookup.native_transport
  }
}
