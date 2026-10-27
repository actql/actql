///|
pub struct ParsedPoliciesInput {
  priv owner : ParsedCheckRegistry
  priv geometry : @environment.DataPolicyConstructionGeometry?
  priv initial_work : Int
  priv inspection_work : Int64
}

///|
pub fn parsed_check_policies_inspection_bound(
  owner : ParsedCheckRegistry,
) -> Int64 {
  match owner.start {
    References(value, _) =>
      @environment.data_policy_construction_observation_work(value)
    _ => 0L
  }
}

///|
pub fn prepare_parsed_policies_input(
  owner : ParsedCheckRegistry,
) -> Result[ParsedPoliciesInput, ParsedCheckPreludeIssue] {
  if !owner.available {
    return Err(AlreadyConsumed)
  }
  match owner.start {
    References(value, b) =>
      Ok({
        owner,
        geometry: Some(
          @environment.observe_data_policy_construction_geometry(value),
        ),
        initial_work: b.work,
        inspection_work: @environment.data_policy_construction_observation_work(
          value,
        ),
      })
    ReusedReferences(_, _, b) =>
      Ok({ owner, geometry: None, initial_work: b.work, inspection_work: 0L, })
    _ => Err(AlreadyConsumed)
  }
}

///|
pub fn parsed_policies_inspection_work(input : ParsedPoliciesInput) -> Int64 {
  input.inspection_work
}

///|
pub fn parsed_policies_semantic_work(input : ParsedPoliciesInput) -> Int {
  input.initial_work
}

///|
pub fn parsed_policies_construction_extent(
  input : ParsedPoliciesInput,
) -> @environment.RegistryConstructionExtent {
  let domain = match input.geometry {
    Some(g) => @environment.data_policy_construction_extent(g).unwrap()
    None =>
      {
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      }
  }
  // Existing continuation/budget, original limits, both actual reader/phase
  // observation tuples and typed-return alternatives. Original bodies borrowed.
  {
    ..domain,
    record_headers: domain.record_headers + 12L,
    reference_slots: domain.reference_slots + 12L,
    scalar_words: domain.scalar_words + 15L,
  }
}

///|
pub fn parsed_policies_retained_extent(
  input : ParsedPoliciesInput,
) -> @environment.RegistryConstructionExtent {
  let domain = match input.geometry {
    Some(g) => @environment.data_policy_retained_extent(g).unwrap()
    None =>
      {
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      }
  }
  // Conservatively retain the control envelope; only returned reader scratch
  // can retire. No physical backing, spent work or parent is released here.
  {
    ..domain,
    record_headers: domain.record_headers + 12L,
    reference_slots: domain.reference_slots + 12L,
    scalar_words: domain.scalar_words + 15L,
  }
}

///|
pub fn observe_parsed_check_policies(
  input : ParsedPoliciesInput,
) -> (Result[Unit, ParsedCatalogPreparationIssue], Int) {
  let owner = input.owner
  if !owner.available {
    return (Err(Prelude(AlreadyConsumed)), 0)
  }
  let result = match owner.start {
    References(value, b) => {
      owner.available = false
      try {
        let next = prepare_environment_policies(value, b)
        owner.start = Policies(next, b)
        owner.available = true
        Ok(())
      } catch {
        issue => Err(Check(Environment(issue)))
      }
    }
    ReusedReferences(catalog, references, b) => {
      owner.start = ReusedPolicies(catalog, references, b)
      Ok(())
    }
    _ => return (Err(Prelude(AlreadyConsumed)), 0)
  }
  (result, input.initial_work - environment_start_budget(owner.start).work)
}
