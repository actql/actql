///|
pub struct ParsedViewsInput {
  priv owner : ParsedCheckRegistry
  priv inventory : @environment.ProtocolViewConstructionInventory?
  priv initial_work : Int
  priv inspection_work : Int64
}

///|
/// Must be funded before metadata construction. This constant call-expanded
/// packet is reused across envelope iterations, not multiplied by their count.
pub fn parsed_views_inspection_extent() -> @environment.RegistryConstructionExtent {
  parsed_views_inspection_controls
}

///|
// Subtree1/0/9; three indexed-field sites15/21/3, two child sites8/8/4;
// five existing collection-quote scopes105/10/210; checked folds10/5/15;
// two sequential receipts40/48/56; typed/control16/16/24; input/Some2/3/2;
// structural metadata/quote record1/0/12. Co-counted constructor controls,
// not body backing, policy ceilings, CPU or physical supply.
let parsed_views_inspection_controls : @environment.RegistryConstructionExtent = {
  record_headers: 198L,
  reference_slots: 111L,
  scalar_words: 335L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
/// Actual inventory+four unit records and original input/Some survive.
pub fn parsed_views_inspection_retained_extent() -> @environment.RegistryConstructionExtent {
  {
    record_headers: 7L,
    reference_slots: 7L,
    scalar_words: 15L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}

///|
pub fn parsed_check_views_inspection_bound(
  owner : ParsedCheckRegistry,
) -> Int64 {
  match owner.start {
    Values(value, _) =>
      @environment.protocol_view_construction_inspection_bound(value)
    _ => 0L
  }
}

///|
pub fn prepare_parsed_views_input(
  owner : ParsedCheckRegistry,
) -> Result[ParsedViewsInput, ParsedCheckPreludeIssue] {
  if !owner.available {
    return Err(AlreadyConsumed)
  }
  match owner.start {
    Values(value, b) => {
      let inventory = @environment.observe_protocol_view_construction(value)
      Ok({
        owner,
        inventory: Some(inventory),
        initial_work: b.work,
        inspection_work: inventory.work,
      })
    }
    ReusedValues(_, _, b) =>
      Ok({ owner, inventory: None, initial_work: b.work, inspection_work: 0L, })
    _ => Err(AlreadyConsumed)
  }
}

///|
pub fn parsed_views_inspection_work(input : ParsedViewsInput) -> Int64 {
  input.inspection_work
}

///|
pub fn parsed_views_semantic_work(input : ParsedViewsInput) -> Int {
  input.initial_work
}

///|
pub fn parsed_views_construction_extent(
  input : ParsedViewsInput,
) -> @environment.RegistryConstructionExtent {
  let domain = match input.inventory {
    Some(value) => @environment.protocol_view_construction_extent(value)
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
pub fn parsed_views_retained_extent(
  input : ParsedViewsInput,
) -> @environment.RegistryConstructionExtent {
  let domain = match input.inventory {
    Some(value) => @environment.protocol_view_retained_extent(value)
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
pub fn observe_parsed_check_views(
  input : ParsedViewsInput,
) -> (Result[Unit, ParsedCatalogPreparationIssue], Int) {
  let owner = input.owner
  if !owner.available {
    return (Err(Prelude(AlreadyConsumed)), 0)
  }
  let result = match owner.start {
    Values(value, b) => {
      owner.available = false
      try {
        let next = prepare_environment_views(value, b)
        owner.start = Modes(next, b)
        owner.available = true
        Ok(())
      } catch {
        issue => Err(Check(Environment(issue)))
      }
    }
    ReusedValues(catalog, references, b) => {
      owner.start = ReusedModes(catalog, references, b)
      Ok(())
    }
    _ => return (Err(Prelude(AlreadyConsumed)), 0)
  }
  (result, input.initial_work - environment_start_budget(owner.start).work)
}
