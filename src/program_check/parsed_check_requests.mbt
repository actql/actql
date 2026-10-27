///|
pub struct ParsedRequestsInput {
  priv owner : ParsedCheckRegistry
  priv inventory : @environment.SourceRequestConstructionGeometry?
  priv initial_work : Int
  priv inspection_work : Int64
}

///|
/// Must be funded before metadata construction. This constant call-expanded
/// packet is reused across envelope iterations, not multiplied by their count.
pub fn parsed_requests_inspection_extent(
  owner : ParsedCheckRegistry,
) -> @environment.RegistryConstructionExtent {
  let domain = match owner.start {
    Carriers(value, _) =>
      @environment.source_request_construction_inspection_extent(value)
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
  // domain quote frames retire before actual Source request construction begins.
  {
    ..domain,
    record_headers: domain.record_headers + 45L,
    reference_slots: domain.reference_slots + 56L,
    scalar_words: domain.scalar_words + 66L,
  }
}

///|
/// Original13-scalar geometry, its Some and ParsedRequestsInput survive.
/// The owner's input Some/quote tuple was already funded by initial controls.
pub fn parsed_requests_inspection_retained_extent() -> @environment.RegistryConstructionExtent {
  {
    record_headers: 3L,
    reference_slots: 3L,
    scalar_words: 16L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}

///|
pub fn parsed_check_requests_inspection_bound(
  owner : ParsedCheckRegistry,
) -> Int64 {
  match owner.start {
    Carriers(value, _) =>
      @environment.source_request_construction_inspection_bound(value)
    _ => 0L
  }
}

///|
pub fn prepare_parsed_requests_input(
  owner : ParsedCheckRegistry,
) -> Result[ParsedRequestsInput, ParsedCheckPreludeIssue] {
  if !owner.available {
    return Err(AlreadyConsumed)
  }
  match owner.start {
    Carriers(value, b) => {
      let inventory = @environment.observe_source_request_construction_geometry(
        value,
      )
      Ok({
        owner,
        inventory: Some(inventory),
        initial_work: b.work,
        inspection_work: inventory.inspection_work,
      })
    }
    ReusedCarriers(_, _, b) =>
      Ok({ owner, inventory: None, initial_work: b.work, inspection_work: 0L, })
    _ => Err(AlreadyConsumed)
  }
}

///|
pub fn parsed_requests_inspection_work(input : ParsedRequestsInput) -> Int64 {
  input.inspection_work
}

///|
pub fn parsed_requests_semantic_work(input : ParsedRequestsInput) -> Int {
  input.initial_work
}

///|
pub fn parsed_requests_construction_extent(
  input : ParsedRequestsInput,
) -> @environment.RegistryConstructionExtent {
  let domain = match input.inventory {
    Some(value) =>
      @environment.source_request_construction_extent(value).unwrap()
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
pub fn parsed_requests_retained_extent(
  input : ParsedRequestsInput,
) -> @environment.RegistryConstructionExtent {
  let domain = match input.inventory {
    Some(value) =>
      @environment.source_request_retained_construction_extent(value).unwrap()
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
pub fn observe_parsed_check_requests(
  input : ParsedRequestsInput,
) -> (Result[Unit, ParsedCatalogPreparationIssue], Int) {
  let owner = input.owner
  if !owner.available {
    return (Err(Prelude(AlreadyConsumed)), 0)
  }
  let result = match owner.start {
    Carriers(value, b) => {
      owner.available = false
      try {
        let next = prepare_environment_requests(value, b)
        owner.start = Requests(next, b)
        owner.available = true
        Ok(())
      } catch {
        issue => Err(Check(Environment(issue)))
      }
    }
    ReusedCarriers(catalog, references, b) => {
      owner.start = ReusedRequests(catalog, references, b)
      Ok(())
    }
    _ => return (Err(Prelude(AlreadyConsumed)), 0)
  }
  (result, input.initial_work - environment_start_budget(owner.start).work)
}
