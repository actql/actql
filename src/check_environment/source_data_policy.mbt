///|
pub(all) enum DataClassification {
  Public
  Internal
  Confidential
  Restricted
  Unknown
} derive(Eq, Debug)

///|
pub(all) struct DataPolicyLimits {
  max_work : Int
  max_policies : Int
}

///|
pub(all) enum DataPolicyIssue {
  InvalidLimits
  WorkLimit
  PolicyLimit
  InvalidPolicy(Int)
} derive(Eq, Debug)

///|
struct SourceDataPolicy {
  envelope : ContractEnvelope
  source_ref : String
  classification : DataClassification
}

///|
struct SourceViewPolicy {
  reference : CatalogReference
  policy : SourceDataPolicy
}

///|
struct SourceDataPolicies {
  references : CatalogReferences
  entries : Array[SourceDataPolicy]
  views : Map[Int, SourceViewPolicy]
  work : Int
}

///|
/// Validates every data_policy body, retaining output-role ownership. This is
/// neither effective Host policy nor publisher/egress authorization.
pub fn check_source_data_policies(
  references : CatalogReferences,
  limits : DataPolicyLimits,
) -> Result[SourceDataPolicies, DataPolicyIssue] {
  if limits.max_work < 0 || limits.max_policies < 0 {
    return Err(InvalidLimits)
  }
  let registry = references.contents.registry
  let entries = []
  let by_cid : Map[String, SourceDataPolicy] = Map([])
  let views : Map[Int, SourceViewPolicy] = Map([])
  let mut work = 0
  for i in 0..<registry.entries.length() {
    if work >= limits.max_work {
      return Err(WorkLimit)
    }
    work += 1
    let envelope = registry.entries[i]
    if envelope.kind != "data_policy" {
      continue
    }
    if entries.length() >= limits.max_policies {
      return Err(PolicyLimit)
    }
    let root = envelope.body
    if @decode.object_length(root) != Some(3) {
      return Err(InvalidPolicy(i))
    }
    // Charge before constructing the object's lookup map.
    for j in 0..<3 {
      let (key, value) = @decode.field_at(root, j).unwrap()
      if key.length() > limits.max_work - work {
        return Err(WorkLimit)
      }
      work += key.length()
      let text = match @decode.text(value) {
        Ok(v) => v
        Err(_) => return Err(InvalidPolicy(i))
      }
      if text.length() > limits.max_work - work {
        return Err(WorkLimit)
      }
      work += text.length()
    }
    let object = @decode.open_object(root).unwrap()
    let values = Some(
      (
        string(object, "version"),
        string(object, "source_ref"),
        string(object, "classification"),
      ),
    ) catch {
      _ => None
    }
    guard values is Some((version, source_ref, name)) else {
      return Err(InvalidPolicy(i))
    }
    if version != "actql-source-data-policy/0.1" || source_ref == "" {
      return Err(InvalidPolicy(i))
    }
    let classification = match name {
      "public" => Public
      "internal" => Internal
      "confidential" => Confidential
      "restricted" => Restricted
      "unknown" => Unknown
      _ => return Err(InvalidPolicy(i))
    }
    let policy = { envelope, source_ref, classification, }
    by_cid[envelope.cid] = policy
    entries.push(policy)
  }
  for reference in references.references {
    if work >= limits.max_work {
      return Err(WorkLimit)
    }
    work += 1
    if reference.contract.kind != "data_policy" {
      continue
    }
    // The generated role table admits data_policy only at SourceView.output.
    let policy = by_cid[reference.contract.cid]
    views[member_index(reference.item)] = { reference, policy, }
  }
  Ok({ references, entries, views, work, })
}

///|
pub fn data_policy_references(v : SourceDataPolicies) -> CatalogReferences {
  v.references
}

///|
pub fn data_policy_usage(v : SourceDataPolicies) -> (Int, Int) {
  (v.work, v.entries.length())
}

///|
pub fn data_policy_at(v : SourceDataPolicies, i : Int) -> SourceDataPolicy? {
  v.entries.get(i)
}

///|
pub fn data_policy_envelope(v : SourceDataPolicy) -> ContractEnvelope {
  v.envelope
}

///|
pub fn data_policy_source(v : SourceDataPolicy) -> String {
  v.source_ref
}

///|
pub fn data_classification(v : SourceDataPolicy) -> DataClassification {
  v.classification
}

///|
pub fn source_view_policy(
  v : SourceDataPolicies,
  item : Member,
) -> SourceViewPolicy? {
  if member_section(item) != SourceViews ||
    !physical_equal(
      member_environment(item),
      v.references.contents.registry.environment,
    ) {
    return None
  }
  v.views.get(member_index(item))
}

///|
pub fn source_view_policy_reference(v : SourceViewPolicy) -> CatalogReference {
  v.reference
}

///|
pub fn source_view_data_policy(v : SourceViewPolicy) -> SourceDataPolicy {
  v.policy
}
