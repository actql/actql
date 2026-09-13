///|
// The authoritative envelope remains distinct from the authored lower bound.
// This is classification selection, not a fabricated effective-policy CID or
// admission of the request's combined egress provenance.
pub struct SourceResponsePolicy {
  source : @sourceviews.ResolvedInput
  authoritative : @environment.SourceViewPolicy
  minimum : String?
  classification : @environment.DataClassification
}

///|
fn source_classification(
  base : @environment.DataClassification,
  minimum : String?,
) -> @environment.DataClassification raise UnitBuildFailure {
  let requested = match minimum {
    None => return base
    Some("public") => @environment.Public
    Some("internal") => @environment.Internal
    Some("confidential") => @environment.Confidential
    Some("restricted") => @environment.Restricted
    Some(_) => raise ForeignOwner
  }
  match (base, requested) {
    (Unknown, _) => Unknown
    (Restricted, _) | (_, Restricted) => Restricted
    (Confidential, _) | (_, Confidential) => Confidential
    (Internal, _) | (_, Internal) => Internal
    (Public, Public) => Public
    (_, Unknown) => raise ForeignOwner
  }
}

///|
fn prepare_source_response_policy(
  source : @sourceviews.ResolvedInput,
) -> SourceResponsePolicy raise UnitBuildFailure {
  let policies = @environment.value_contract_policies(
    @environment.source_view_shape_values(
      @environment.read_mode_shapes(
        @environment.carrier_schema_modes(
          @environment.source_request_carriers(
            @sourceviews.catalog_owner(source),
          ),
        ),
      ),
    ),
  )
  let selected_member = @environment.source_request_member(
    @sourceviews.selected_contract(source),
  )
  guard @environment.source_view_policy(policies, selected_member)
    is Some(authoritative) else {
    raise ForeignOwner
  }
  let minimum = @sourceviews.declaration(source).minimum_classification
  {
    source,
    authoritative,
    minimum,
    classification: source_classification(
      @environment.data_classification(
        @environment.source_view_data_policy(authoritative),
      ),
      minimum,
    ),
  }
}
