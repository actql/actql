///|
// Owned direct-request composition. Correlation provenance is deliberately not
// represented by this type; keyed acquisitions require their producer policy.
pub struct DirectSourcePolicy {
  request : @sourceviews.ParameterizedRequest
  response : SourceResponsePolicy
  response_cid : String
  classification : @environment.DataClassification
  unknown_provenance : Bool
}

///|
fn prepare_direct_source_policy(
  request : @sourceviews.ParameterizedRequest,
  response : SourceResponsePolicy,
  response_cid : String,
) -> DirectSourcePolicy raise UnitBuildFailure {
  guard physical_equal(
    @sourceviews.request_input(@sourceviews.parameterized_request(request)),
    response.source,
  ) else {
    raise ForeignOwner
  }
  // Current static request admission carries literal/Parameter/Host-binding
  // values but no authoritative policy attestation for those values. Preserve
  // their exact occurrences through request; never infer a public default.
  let unknown_provenance = @sourceviews.parameterized_request_field_count(
      request,
    ) >
    0
  {
    request,
    response,
    response_cid,
    classification: if unknown_provenance {
      @environment.Unknown
    } else {
      response.classification
    },
    unknown_provenance,
  }
}

///|
pub fn emit_direct_source_policy(
  value : DirectSourcePolicy,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "classification")
  @encode.string_value(
    writer,
    match value.classification {
      Public => "public"
      Internal => "internal"
      Confidential => "confidential"
      Restricted => "restricted"
      Unknown => "unknown"
    },
  )
  @encode.key(writer, "source_data_policy_cids")
  @encode.begin_array(writer)
  @encode.string_value(
    writer,
    @environment.contract_identity(
      @environment.data_policy_envelope(
        @environment.source_view_data_policy(value.response.authoritative),
      ),
    ).2,
  )
  @encode.end_array(writer)
  @encode.key(writer, "source_response_policy_cids")
  @encode.begin_array(writer)
  @encode.string_value(writer, value.response_cid)
  @encode.end_array(writer)
  @encode.key(writer, "unknown_provenance")
  @encode.bool_value(writer, value.unknown_provenance)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-effective-data-policy/0.1")
  @encode.end_object(writer)
}
