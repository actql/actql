///|
pub struct ParsedCarriersInput {
  priv owner : ParsedCheckRegistry
  priv inventory : @environment.ProtocolCarrierConstructionInventory?
  priv initial_work : Int
  priv inspection_work : Int64
}

///|
/// Must be funded before metadata construction. This constant call-expanded
/// packet is reused across envelope iterations, not multiplied by their count.
pub fn parsed_carriers_inspection_extent(
  owner : ParsedCheckRegistry,
) -> @environment.RegistryConstructionExtent {
  let domain = match owner.start {
    Modes(value, _) =>
      @environment.protocol_carrier_construction_inspection_extent(value)
    _ =>
      {
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      }
  }
  // Same original work receipts/Core input/typed alternatives. The Map and
  // domain quote frames retire before actual Carrier construction begins.
  {
    ..domain,
    record_headers: domain.record_headers + 45L,
    reference_slots: domain.reference_slots + 56L,
    scalar_words: domain.scalar_words + 66L,
  }
}

///|
/// Inventory+two five-word extents and the original input/Some survive.
pub fn parsed_carriers_inspection_retained_extent() -> @environment.RegistryConstructionExtent {
  {
    record_headers: 6L,
    reference_slots: 6L,
    scalar_words: 15L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}

///|
pub fn parsed_check_carriers_inspection_bound(
  owner : ParsedCheckRegistry,
) -> Int64 {
  match owner.start {
    Modes(value, _) =>
      @environment.protocol_carrier_construction_inspection_bound(value)
    _ => 0L
  }
}

///|
pub fn prepare_parsed_carriers_input(
  owner : ParsedCheckRegistry,
) -> Result[ParsedCarriersInput, ParsedCheckPreludeIssue] {
  if !owner.available {
    return Err(AlreadyConsumed)
  }
  match owner.start {
    Modes(value, b) => {
      let inventory = @environment.observe_protocol_carrier_construction(value)
      Ok({
        owner,
        inventory: Some(inventory),
        initial_work: b.work,
        inspection_work: inventory.work,
      })
    }
    ReusedModes(_, _, b) =>
      Ok({ owner, inventory: None, initial_work: b.work, inspection_work: 0L, })
    _ => Err(AlreadyConsumed)
  }
}

///|
pub fn parsed_carriers_inspection_work(input : ParsedCarriersInput) -> Int64 {
  input.inspection_work
}

///|
pub fn parsed_carriers_semantic_work(input : ParsedCarriersInput) -> Int {
  input.initial_work
}

///|
pub fn parsed_carriers_construction_extent(
  input : ParsedCarriersInput,
) -> @environment.RegistryConstructionExtent {
  let domain = match input.inventory {
    Some(value) => @environment.protocol_carrier_construction_extent(value)
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
pub fn parsed_carriers_retained_extent(
  input : ParsedCarriersInput,
) -> @environment.RegistryConstructionExtent {
  let domain = match input.inventory {
    Some(value) => @environment.protocol_carrier_retained_extent(value)
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
pub fn observe_parsed_check_carriers(
  input : ParsedCarriersInput,
) -> (Result[Unit, ParsedCatalogPreparationIssue], Int) {
  let owner = input.owner
  if !owner.available {
    return (Err(Prelude(AlreadyConsumed)), 0)
  }
  let result = match owner.start {
    Modes(value, b) => {
      owner.available = false
      try {
        let next = prepare_environment_carriers(value, b)
        owner.start = Carriers(next, b)
        owner.available = true
        Ok(())
      } catch {
        issue => Err(Check(Environment(issue)))
      }
    }
    ReusedModes(catalog, references, b) => {
      owner.start = ReusedCarriers(catalog, references, b)
      Ok(())
    }
    _ => return (Err(Prelude(AlreadyConsumed)), 0)
  }
  (result, input.initial_work - environment_start_budget(owner.start).work)
}
