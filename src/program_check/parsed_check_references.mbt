///|
pub struct ParsedReferencesInput {
  priv owner : ParsedCheckRegistry
  priv geometry : @environment.CatalogReferenceGeometry?
  priv initial_work : Int
  priv inspection_work : Int64
}

///|
pub fn parsed_check_references_inspection_bound(
  owner : ParsedCheckRegistry,
) -> Int64 {
  match owner.start {
    Contents(value, _) =>
      @environment.reference_construction_observation_work(value)
    _ => 0L
  }
}

///|
pub fn prepare_parsed_references_input(
  owner : ParsedCheckRegistry,
) -> Result[ParsedReferencesInput, ParsedCheckPreludeIssue] {
  if !owner.available {
    return Err(AlreadyConsumed)
  }
  match owner.start {
    Contents(value, b) =>
      Ok({
        owner,
        geometry: Some(
          @environment.observe_reference_construction_geometry(value),
        ),
        initial_work: b.work,
        inspection_work: @environment.reference_construction_observation_work(
          value,
        ),
      })
    ReusedContents(_, _, b) =>
      Ok({ owner, geometry: None, initial_work: b.work, inspection_work: 0L, })
    _ => Err(AlreadyConsumed)
  }
}

///|
pub fn parsed_references_inspection_work(
  input : ParsedReferencesInput,
) -> Int64 {
  input.inspection_work
}

///|
pub fn parsed_references_semantic_work(input : ParsedReferencesInput) -> Int {
  input.initial_work
}

///|
pub fn parsed_references_construction_extent(
  input : ParsedReferencesInput,
) -> @environment.RegistryConstructionExtent {
  let domain = match input.geometry {
    Some(g) => @environment.catalog_reference_construction_extent(g).unwrap()
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
pub fn parsed_references_retained_extent(
  input : ParsedReferencesInput,
) -> @environment.RegistryConstructionExtent {
  let domain = match input.geometry {
    Some(g) => @environment.catalog_reference_retained_extent(g).unwrap()
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
pub fn observe_parsed_check_references(
  input : ParsedReferencesInput,
) -> (Result[Unit, ParsedCatalogPreparationIssue], Int) {
  let owner = input.owner
  if !owner.available {
    return (Err(Prelude(AlreadyConsumed)), 0)
  }
  let result = match owner.start {
    Contents(value, b) => {
      owner.available = false
      try {
        let next = prepare_environment_references(value, b)
        owner.start = References(next, b)
        owner.available = true
        Ok(())
      } catch {
        issue => Err(Check(Environment(issue)))
      }
    }
    ReusedContents(catalog, references, b) => {
      owner.start = ReusedReferences(catalog, references, b)
      Ok(())
    }
    _ => return (Err(Prelude(AlreadyConsumed)), 0)
  }
  (result, input.initial_work - environment_start_budget(owner.start).work)
}
