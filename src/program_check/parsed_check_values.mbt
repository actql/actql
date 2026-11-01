///|
pub struct ParsedValuesInput {
  priv owner : ParsedCheckRegistry
  priv inventory : @environment.ProtocolValueConstructionInventory?
  priv initial_work : Int
  priv inspection_work : Int64
}

///|
/// Must be funded before metadata construction. This constant call-expanded
/// packet is reused across envelope iterations, not multiplied by their count.
pub fn parsed_values_inspection_extent() -> @environment.RegistryConstructionExtent {
  parsed_values_inspection_controls
}

///|
// Subtree record1/0/9 +selected-name Array3/22/2; Value quote52/11/101;
// Command quote42/4/84 +root facts9/7/8; checked folds10/5/15;
// workspace max controls3/0/9; root quotes42/4/84; Core input3/5/6;
// two sequential receipt alternatives40/48/56; typed outcomes8/8/12.
// Co-counted controls, not payload, policy ceiling, minimum or physical supply.
let parsed_values_inspection_controls : @environment.RegistryConstructionExtent = {
  record_headers: 213L,
  reference_slots: 114L,
  scalar_words: 386L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
/// Actual inventory record+two unit records and this input/Some survive.
pub fn parsed_values_inspection_retained_extent() -> @environment.RegistryConstructionExtent {
  {
    record_headers: 5L,
    reference_slots: 5L,
    scalar_words: 12L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}

///|
pub fn parsed_check_values_inspection_bound(
  owner : ParsedCheckRegistry,
) -> Int64 {
  match owner.start {
    Policies(value, _) =>
      @environment.protocol_value_construction_inspection_bound(value)
    _ => 0L
  }
}

///|
pub fn prepare_parsed_values_input(
  owner : ParsedCheckRegistry,
) -> Result[ParsedValuesInput, ParsedCheckPreludeIssue] {
  if !owner.available {
    return Err(AlreadyConsumed)
  }
  match owner.start {
    Policies(value, b) => {
      let inventory = @environment.observe_protocol_value_construction(value)
      Ok({
        owner,
        inventory: Some(inventory),
        initial_work: b.work,
        inspection_work: inventory.work,
      })
    }
    ReusedPolicies(_, _, b) =>
      Ok({ owner, inventory: None, initial_work: b.work, inspection_work: 0L, })
    _ => Err(AlreadyConsumed)
  }
}

///|
pub fn parsed_values_inspection_work(input : ParsedValuesInput) -> Int64 {
  input.inspection_work
}

///|
pub fn parsed_values_semantic_work(input : ParsedValuesInput) -> Int {
  input.initial_work
}

///|
pub fn parsed_values_construction_extent(
  input : ParsedValuesInput,
) -> @environment.RegistryConstructionExtent {
  let domain = match input.inventory {
    Some(value) => @environment.protocol_value_construction_extent(value)
    None =>
      {
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      }
  }
  // Actual caps/limits, start, nested observation tuples and typed error paths.
  // Metadata is already reserved separately before inspection, not added here.
  {
    ..domain,
    record_headers: domain.record_headers + 13L,
    reference_slots: domain.reference_slots + 13L,
    scalar_words: domain.scalar_words + 14L,
  }
}

///|
pub fn parsed_values_retained_extent(
  input : ParsedValuesInput,
) -> @environment.RegistryConstructionExtent {
  let domain = match input.inventory {
    Some(value) => @environment.protocol_value_retained_extent(value)
    None =>
      {
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      }
  }
  {
    ..domain,
    record_headers: domain.record_headers + 13L,
    reference_slots: domain.reference_slots + 13L,
    scalar_words: domain.scalar_words + 14L,
  }
}

///|
pub fn observe_parsed_check_values(
  input : ParsedValuesInput,
) -> (Result[Unit, ParsedCatalogPreparationIssue], Int) {
  let owner = input.owner
  if !owner.available {
    return (Err(Prelude(AlreadyConsumed)), 0)
  }
  let result = match owner.start {
    Policies(value, b) => {
      owner.available = false
      try {
        let next = prepare_environment_values(value, b)
        owner.start = Values(next, b)
        owner.available = true
        Ok(())
      } catch {
        issue => Err(Check(Environment(issue)))
      }
    }
    ReusedPolicies(catalog, references, b) => {
      owner.start = ReusedValues(catalog, references, b)
      Ok(())
    }
    _ => return (Err(Prelude(AlreadyConsumed)), 0)
  }
  (result, input.initial_work - environment_start_budget(owner.start).work)
}
