///|
pub enum SourcePolicyOccurrence {
  DirectPolicy(DirectSourcePolicy)
  KeyedResponsePolicy(SourceExecution)
  KeyedStaticRequestPolicy(SourceExecution)
}

///|
struct EffectivePolicy {
  classification : @environment.DataClassification
  unknown_provenance : Bool
  sources : Array[String]
  responses : Array[String]
  occurrences : Array[SourcePolicyOccurrence]
}

///|
// Callers select contributors using owned checked edges. This constructor does
// not infer selection from equal CIDs or from the surrounding Catalog.
fn prepare_effective_policy(
  occurrences : Array[SourcePolicyOccurrence],
  unknown : Bool,
  budget : IdentityBudget,
) -> EffectivePolicy raise UnitBuildFailure {
  identity_charge(budget, occurrences.length())
  let owned = occurrences.copy()
  let sources : Array[(String, Unit)] = []
  let responses : Array[(String, Unit)] = []
  let mut classification = @environment.Public
  let mut unknown_provenance = unknown
  for policy in owned {
    identity_charge(budget, 2)
    // Static Request values keep their exact original Host subject. They do
    // not contribute the future response policy to a pre-dispatch request.
    if policy is KeyedStaticRequestPolicy(check) {
      guard check.kind is KeyedRequest(binding) &&
        check.subject.request is @sourceviews.Keyed(_, request) &&
        physical_equal(request, @sourceviews.keyed_join_request(binding.join)) else {
        raise ForeignOwner
      }
      if check.subject.request_value_policy is Some(selected) {
        sources.push(
          (
            @environment.contract_identity(
              @environment.data_policy_envelope(selected),
            ).2,
            (),
          ),
        )
        classification = combine_classification(
          classification,
          @environment.data_classification(selected),
        )
      } else if @sourceviews.parameterized_keyed_request_field_count(request) >
        0 {
        unknown_provenance = true
      }
      continue
    }
    let (response, response_cid, contribution, missing, request_policy) = match
      policy {
      KeyedStaticRequestPolicy(_) => raise ForeignOwner
      DirectPolicy(policy) =>
        (
          policy.response,
          policy.response_cid,
          policy.classification,
          policy.unknown_provenance,
          policy.request_value_policy,
        )
      KeyedResponsePolicy(check) => {
        guard check.kind is KeyedResponse(binding) &&
          check.subject.request is @sourceviews.Keyed(_, request) &&
          physical_equal(request, @sourceviews.keyed_join_request(binding.join)) else {
          raise ForeignOwner
        }
        // Correlation remains separate from Host-verified static request values.
        let missing = @sourceviews.parameterized_keyed_request_field_count(
            request,
          ) >
          0 &&
          check.subject.request_value_policy is None
        (
          check.subject.response_policy,
          check.subject.response_policy_cid,
          check.subject.response_policy.classification,
          missing,
          check.subject.request_value_policy,
        )
      }
    }
    sources.push(
      (
        @environment.contract_identity(
          @environment.data_policy_envelope(
            @environment.source_view_data_policy(response.authoritative),
          ),
        ).2,
        (),
      ),
    )
    responses.push((response_cid, ()))
    if request_policy is Some(selected) {
      sources.push(
        (
          @environment.contract_identity(
            @environment.data_policy_envelope(selected),
          ).2,
          (),
        ),
      )
      classification = combine_classification(
        classification,
        @environment.data_classification(selected),
      )
    }
    classification = combine_classification(classification, contribution)
    unknown_provenance = unknown_provenance || missing
  }
  let sources = policy_unique_cids(sources, budget)
  let responses = policy_unique_cids(responses, budget)
  if unknown_provenance || owned.is_empty() {
    classification = @environment.Unknown
  }
  {
    classification,
    unknown_provenance,
    sources,
    responses,
    occurrences: owned,
  }
}

///|
fn policy_unique_cids(
  values : Array[(String, Unit)],
  budget : IdentityBudget,
) -> Array[String] raise UnitBuildFailure {
  identity_sort(values, budget)
  let result : Array[String] = []
  for (cid, _) in values {
    identity_charge(budget, 1)
    if result.last() is Some(previous) &&
      identity_compare(previous, cid, budget) == 0 {
      continue
    }
    result.push(cid)
  }
  result
}

///|
pub fn effective_policy_classification(
  value : EffectivePolicy,
) -> @environment.DataClassification {
  value.classification
}

///|
pub fn effective_policy_occurrence_count(value : EffectivePolicy) -> Int {
  value.occurrences.length()
}

///|
pub fn effective_policy_occurrence_at(
  value : EffectivePolicy,
  index : Int,
) -> SourcePolicyOccurrence? {
  value.occurrences.get(index)
}

///|
pub fn emit_effective_policy(
  value : EffectivePolicy,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  emit_effective_policy_parts(
    value.classification,
    value.unknown_provenance,
    value.sources.length(),
    index => value.sources[index],
    value.responses.length(),
    index => value.responses[index],
    writer,
  )
}

///|
// The original emission and its pre-construction geometry share the same
// spelling/order. Count-only callers issue no policy, identity or provenance.
fn emit_effective_policy_parts(
  classification : @environment.DataClassification,
  unknown : Bool,
  sources : Int,
  source_at : (Int) -> String,
  responses : Int,
  response_at : (Int) -> String,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "classification")
  @encode.string_value(
    writer,
    match classification {
      Public => "public"
      Internal => "internal"
      Confidential => "confidential"
      Restricted => "restricted"
      Unknown => "unknown"
    },
  )
  @encode.key(writer, "source_data_policy_cids")
  @encode.begin_array(writer)
  for index in 0..<sources {
    @encode.string_value(writer, source_at(index))
  }
  @encode.end_array(writer)
  @encode.key(writer, "source_response_policy_cids")
  @encode.begin_array(writer)
  for index in 0..<responses {
    @encode.string_value(writer, response_at(index))
  }
  @encode.end_array(writer)
  @encode.key(writer, "unknown_provenance")
  @encode.bool_value(writer, unknown)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-effective-data-policy/0.1")
  @encode.end_object(writer)
}

///|
/// Borrow the exact deduplicated policy references without a wire parse or copy.
/// Occurrence correspondence remains in this same original effective policy.
pub fn effective_policy_source_count(value : EffectivePolicy) -> Int {
  value.sources.length()
}

///|
pub fn effective_policy_source_at(
  value : EffectivePolicy,
  index : Int,
) -> String? {
  value.sources.get(index)
}
