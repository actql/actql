///|
pub struct ParsedContentsInput {
  priv owner : ParsedCheckRegistry
  priv geometry : @environment.CatalogConstructionGeometry?
  priv initial_work : Int
  priv inspection_work : Int64
}

///|
pub fn parsed_check_contents_inspection_bound(
  owner : ParsedCheckRegistry,
) -> Int64 {
  match owner.start {
    Registry(registry, _, _) =>
      4L +
      @environment.member_count(
        @environment.contract_registry_environment(registry),
        @environment.ConnectorCatalogs,
      ).to_int64()
    _ => 0L
  }
}

///|
pub fn prepare_parsed_contents_input(
  owner : ParsedCheckRegistry,
) -> Result[ParsedContentsInput, ParsedCheckPreludeIssue] {
  if !owner.available {
    return Err(AlreadyConsumed)
  }
  match owner.start {
    Registry(registry, b, _) => {
      let geometry = @environment.observe_catalog_construction_geometry(
        registry,
      )
      Ok({
        owner,
        geometry: Some(geometry),
        initial_work: b.work,
        inspection_work: 4L + geometry.catalogs.to_int64(),
      })
    }
    Reused(_, _, b) =>
      Ok({ owner, geometry: None, initial_work: b.work, inspection_work: 0L, })
    _ => Err(AlreadyConsumed)
  }
}

///|
pub fn parsed_contents_inspection_work(input : ParsedContentsInput) -> Int64 {
  input.inspection_work
}

///|
pub fn parsed_contents_semantic_work(input : ParsedContentsInput) -> Int {
  input.initial_work
}

///|
pub fn parsed_contents_construction_extent(
  input : ParsedContentsInput,
) -> @environment.RegistryConstructionExtent {
  let domain = match input.geometry {
    Some(g) => @environment.catalog_contents_construction_extent(g).unwrap()
    None =>
      {
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      }
  }
  // Existing start replacement, caps/usage, typed return/error alternatives
  // and observation tuple. Original owner/budget/registry stay borrowed.
  {
    ..domain,
    record_headers: domain.record_headers + 9L,
    reference_slots: domain.reference_slots + 9L,
    scalar_words: domain.scalar_words + 12L,
  }
}

///|
/// Advance the SAME original continuation. On typed failure its prior original
/// state stays retained but cannot execute; no body replay or fake permission.
pub fn observe_parsed_check_contents(
  input : ParsedContentsInput,
) -> (Result[Unit, ParsedCatalogPreparationIssue], Int) {
  let owner = input.owner
  if !owner.available {
    return (Err(Prelude(AlreadyConsumed)), 0)
  }
  let before = input.initial_work
  let result = match owner.start {
    Registry(registry, b, limits) => {
      owner.available = false
      try {
        let contents = prepare_environment_contents(registry, b, limits)
        owner.start = Contents(contents, b)
        owner.available = true
        Ok(())
      } catch {
        issue => Err(Check(Environment(issue)))
      }
    }
    Reused(catalog, references, b) => {
      owner.start = ReusedContents(catalog, references, b)
      Ok(())
    }
    _ => return (Err(Prelude(AlreadyConsumed)), 0)
  }
  let remaining = environment_start_budget(owner.start).work
  (result, before - remaining)
}

///|
pub fn parsed_contents_retained_extent(
  input : ParsedContentsInput,
) -> @environment.RegistryConstructionExtent {
  let domain = match input.geometry {
    Some(g) => @environment.catalog_contents_retained_extent(g).unwrap()
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
    record_headers: domain.record_headers + 9L,
    reference_slots: domain.reference_slots + 9L,
    scalar_words: domain.scalar_words + 12L,
  }
}
