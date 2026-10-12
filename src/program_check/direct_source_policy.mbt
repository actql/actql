///|
// Owned direct-request composition. Correlation provenance is deliberately not
// represented by this type; keyed acquisitions require their producer policy.
pub struct DirectSourcePolicy {
  request : @sourceviews.ParameterizedRequest
  response : SourceResponsePolicy
  response_cid : String
  classification : @environment.DataClassification
  unknown_provenance : Bool
  request_value_policy : @environment.SourceDataPolicy?
}

///|
fn prepare_direct_source_policy(
  request : @sourceviews.ParameterizedRequest,
  response : SourceResponsePolicy,
  response_cid : String,
  request_value_policy? : @environment.SourceDataPolicy? = None,
) -> DirectSourcePolicy raise UnitBuildFailure {
  guard physical_equal(
    @sourceviews.request_input(@sourceviews.parameterized_request(request)),
    response.source,
  ) else {
    raise ForeignOwner
  }
  // Type admission alone supplies no policy. Only Host-verified evidence
  // selected for this exact request may discharge static value provenance.
  let unknown_provenance = @sourceviews.parameterized_request_field_count(
      request,
    ) >
    0 &&
    request_value_policy is None
  {
    request,
    response,
    response_cid,
    classification: if unknown_provenance {
      @environment.Unknown
    } else {
      combine_classification(
        response.classification,
        request_value_policy
        .map(@environment.data_classification)
        .unwrap_or(@environment.Public),
      )
    },
    unknown_provenance,
    request_value_policy,
  }
}

///|
pub fn emit_direct_source_policy(
  value : DirectSourcePolicy,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  emit_source_policy(value, value.unknown_provenance, writer)
}

///|
fn emit_source_policy(
  value : DirectSourcePolicy,
  unknown_provenance : Bool,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "classification")
  @encode.string_value(
    writer,
    match
      (if unknown_provenance {
        @environment.Unknown
      } else {
        value.classification
      }) {
      Public => "public"
      Internal => "internal"
      Confidential => "confidential"
      Restricted => "restricted"
      Unknown => "unknown"
    },
  )
  @encode.key(writer, "source_data_policy_cids")
  @encode.begin_array(writer)
  let response_cid = @environment.contract_identity(
      @environment.data_policy_envelope(
        @environment.source_view_data_policy(value.response.authoritative),
      ),
    ).2
  let request_cid = value.request_value_policy.map(policy => {
    @environment.contract_identity(@environment.data_policy_envelope(policy)).2
  })
  if request_cid is Some(cid) && @canonical.compare_utf16(cid, response_cid) < 0 {
    @encode.string_value(writer, cid)
  }
  @encode.string_value(writer, response_cid)
  if request_cid is Some(cid) && @canonical.compare_utf16(cid, response_cid) > 0 {
    @encode.string_value(writer, cid)
  }
  @encode.end_array(writer)
  @encode.key(writer, "source_response_policy_cids")
  @encode.begin_array(writer)
  @encode.string_value(writer, value.response_cid)
  @encode.end_array(writer)
  @encode.key(writer, "unknown_provenance")
  @encode.bool_value(writer, unknown_provenance)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-effective-data-policy/0.1")
  @encode.end_object(writer)
}
