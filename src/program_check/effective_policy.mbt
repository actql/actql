///|
struct EffectivePolicy {
  classification : @environment.DataClassification
  unknown_provenance : Bool
  sources : Array[String]
  responses : Array[String]
  occurrences : Array[DirectSourcePolicy]
}

///|
// Callers select contributors using owned checked edges. This constructor does
// not infer selection from equal CIDs or from the surrounding Catalog.
fn prepare_effective_policy(
  occurrences : Array[DirectSourcePolicy],
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
    sources.push(
      (
        @environment.contract_identity(
          @environment.data_policy_envelope(
            @environment.source_view_data_policy(policy.response.authoritative),
          ),
        ).2,
        (),
      ),
    )
    responses.push((policy.response_cid, ()))
    classification = combine_classification(
      classification,
      policy.classification,
    )
    unknown_provenance = unknown_provenance || policy.unknown_provenance
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
) -> DirectSourcePolicy? {
  value.occurrences.get(index)
}

///|
pub fn emit_effective_policy(
  value : EffectivePolicy,
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
  for cid in value.sources {
    @encode.string_value(writer, cid)
  }
  @encode.end_array(writer)
  @encode.key(writer, "source_response_policy_cids")
  @encode.begin_array(writer)
  for cid in value.responses {
    @encode.string_value(writer, cid)
  }
  @encode.end_array(writer)
  @encode.key(writer, "unknown_provenance")
  @encode.bool_value(writer, value.unknown_provenance)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-effective-data-policy/0.1")
  @encode.end_object(writer)
}
