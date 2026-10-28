///|
/// The next DATA continuation of the consumed registry, not another Resource
/// owner. All constructor/input/borrowed frames require outside backing before
/// entry. The existing read exposes its original per-phase inventories; this
/// holder does not infer funding from semantic limits or completed Catalog work.
pub struct ParsedSourceRegistration {
  priv registry : ParsedCheckRegistry
  priv catalog : @environment.SourceRequestContracts
  priv references : @environment.CatalogReferences
  priv budget : IdentityBudget
  priv limits : SourceLimits
  priv read : @context.SourceRegistrationRead
  priv mut available : Bool
}

///|
pub suberror ParsedSourceRegistrationIssue {
  RegistryUnavailable
  RegistrationConstruction(LocalConstructionFailure)
  Pending
  Unavailable
}

///|
/// Only the completed original Catalog can enter. Consume that continuation
/// BEFORE any constructor, retaining its exact Program, Catalog, limits and
/// remaining budget. No fallback Catalog reader or replacement tuple is used.
/// The caller backs Stage preparation, this holder and registration entrance
/// before calling, then each selected read phase before advancing it.
pub fn begin_parsed_source_registration(
  registry : ParsedCheckRegistry,
) -> Result[ParsedSourceRegistration, ParsedSourceRegistrationIssue] {
  if !registry.available {
    return Err(RegistryUnavailable)
  }
  let (catalog, references, budget) = match registry.start {
    Requests(catalog, budget) => {
      let (_, references) = finish_environment_requests(catalog, budget, budget)
      (catalog, references, budget)
    }
    ReusedRequests(catalog, references, budget) => (catalog, references, budget)
    _ => return Err(Unavailable)
  }
  registry.available = false
  let original = registry.prelude.original
  let limits = source_limits_after_catalog(
    compile_source_limits(original.limits),
    budget,
  )
  let source = prepare_catalog_stage_source(
    original.program,
    limits,
    original.source_preparation,
  ) catch {
    issue => return Err(RegistrationConstruction(Source(issue)))
  }
  let read = match
    @context.begin_source_registration(
      source,
      catalog,
      catalog_registration_limits(limits),
      max_inputs=limits.max_slots,
      max_views=limits.max_slots,
      max_order_keys=limits.max_slots,
    ) {
    Err(issue) =>
      return Err(RegistrationConstruction(Source(Registration(issue))))
    Ok(value) => value
  }
  Ok({ registry, catalog, references, budget, limits, read, available: true, })
}

///|
/// The SAME reader for original phase quotation/advance/clear. Taking or
/// clearing it externally cannot recreate a result or upgrade this continuation.
pub fn parsed_source_registration_read(
  prepared : ParsedSourceRegistration,
) -> @context.SourceRegistrationRead {
  prepared.read
}

///|
/// Consume the original registration result once, then enter the existing
/// Context/identity/closure checker without recollecting Source or Catalog.
/// The caller must fund that entire remaining overlap before entry. Pending
/// retains the same read; cancellation/taken results never restart a reader.
pub fn finish_parsed_source_registration(
  prepared : ParsedSourceRegistration,
) -> Result[CheckOutcome, ParsedSourceRegistrationIssue] {
  if !prepared.available {
    return Err(Unavailable)
  }
  match @context.source_registration_phase(prepared.read) {
    RegistrationCollect
    | RegistrationSelect
    | RegistrationPipeline
    | RegistrationLocal => return Err(Pending)
    RegistrationTransferred | RegistrationRetired => {
      prepared.available = false
      return Err(Unavailable)
    }
    RegistrationComplete | RegistrationFailed => ()
  }
  prepared.available = false
  let result = @context.take_source_registration_result(prepared.read).unwrap()
  match result {
    Err(issue) => {
      let original = prepared.registry.prelude.original
      Ok(
        checking_outcome(original.program, original.environment, () => {
          raise LocalConstructionFailure::Source(Registration(issue))
        }),
      )
    }
    Ok((views, locals)) => {
      prepared.registry.start = Registered(
        prepared.catalog,
        prepared.references,
        prepared.budget,
        prepared.limits,
        views,
        locals,
      )
      Ok(finish_parsed_check_registry_owned(prepared.registry))
    }
  }
}
