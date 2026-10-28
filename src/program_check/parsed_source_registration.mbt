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
  priv mut registered : Bool
  priv mut context_geometry : @context.SourceViewContextInputGeometry?
  priv mut context_input : Result[
    @context.SourceViewContextInput,
    @context.SourceViewContextIssue,
  ]?
}

///|
pub suberror ParsedSourceRegistrationIssue {
  RegistryUnavailable
  SourceNotRetained
  RegistrationConstruction(LocalConstructionFailure)
  Pending
  Unavailable
  ContextInput(@context.SourceViewContextIssue)
}

///|
/// Only the completed original Catalog can enter. Consume that continuation
/// BEFORE any constructor, retaining its exact Program, Catalog, limits and
/// remaining budget. No fallback Catalog reader or replacement tuple is used.
/// The caller already owns/backed this original Source, and backs this holder
/// and registration entrance before calling. This entry never prepares missing
/// declarations or copies Stages. Each selected read phase is backed separately.
pub fn begin_parsed_source_registration(
  registry : ParsedCheckRegistry,
  source : @stages.Source,
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
  if original.source_preparation is Some(selected) &&
    !physical_equal(selected, source) {
    return Err(SourceNotRetained)
  }
  guard @stages.reuse_prepared(source, original.program, {
      max_parameters: limits.max_parameters,
      max_nodes: limits.topology.max_nodes,
      max_depth: limits.topology.max_depth,
      max_text_bytes: limits.topology.max_text_bytes,
    })
    is Some(_) else {
    return Err(SourceNotRetained)
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
  Ok({
    registry,
    catalog,
    references,
    budget,
    limits,
    read,
    available: true,
    registered: false,
    context_geometry: None,
    context_input: None,
  })
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
  if prepared.registered {
    prepared.available = false
    return match prepared.context_input {
      Some(Err(issue)) => {
        let original = prepared.registry.prelude.original
        Ok(
          checking_outcome(original.program, original.environment, () => {
            raise LocalConstructionFailure::Source(SourceView(issue))
          }),
        )
      }
      Some(Ok(input)) =>
        Ok(
          finish_parsed_check_registry_owned(
            prepared.registry,
            source_context=Some(input),
          ),
        )
      None => Err(Unavailable)
    }
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

///|
/// Observe the SAME completed Source result once without consuming it. Caller
/// backs this metadata frame and retains the returned quantity across grow.
pub fn observe_parsed_source_context_input_geometry(
  prepared : ParsedSourceRegistration,
) -> @context.SourceViewContextInputGeometry? {
  if !prepared.available || prepared.registered {
    return None
  }
  if prepared.context_geometry is Some(_) {
    return prepared.context_geometry
  }
  let observed = @context.observe_source_registration_context_input_geometry(
    prepared.read,
  )
  prepared.context_geometry = observed
  observed
}

///|
pub fn parsed_source_context_input_geometry(
  prepared : ParsedSourceRegistration,
) -> @context.SourceViewContextInputGeometry? {
  prepared.context_geometry
}

///|
/// Consume the original registration once, then retain the original Context
/// entrance result. A failed result stays failed; no replacement tuple, limits,
/// Program or caller-supplied prepared Context can enter this continuation.
pub fn prepare_parsed_source_context_input(
  prepared : ParsedSourceRegistration,
) -> Result[@context.SourceViewContextInput, ParsedSourceRegistrationIssue] {
  if !prepared.available {
    return Err(Unavailable)
  }
  if prepared.context_input is Some(completed) {
    return completed.map_err(issue => ContextInput(issue))
  }
  if @context.source_registration_phase(prepared.read) != RegistrationComplete {
    return Err(Pending)
  }
  let (views, locals) = match
    @context.take_source_registration_result(prepared.read) {
    Some(Ok(pair)) => pair
    _ => return Err(Unavailable)
  }
  prepared.registered = true
  prepared.registry.start = Registered(
    prepared.catalog,
    prepared.references,
    prepared.budget,
    prepared.limits,
    views,
    locals,
  )
  let original = prepared.registry.prelude.original
  let result = @context.prepare_sourceview_context_input(
    views,
    locals,
    prepared.limits.topology,
    prepared.limits.context,
    calendar=original.environment.calendar,
    model_tasks=original.environment.model_tasks,
  )
  prepared.context_input = Some(result)
  result.map_err(issue => ContextInput(issue))
}

///|
/// Original result only; a presence is not proof of success, funding or check.
pub fn parsed_source_context_input(
  prepared : ParsedSourceRegistration,
) -> Result[@context.SourceViewContextInput, @context.SourceViewContextIssue]? {
  prepared.context_input
}

///|
/// Original selected semantic-work bound only, never a memory quantity.
pub fn parsed_source_context_input_work_bound(
  prepared : ParsedSourceRegistration,
) -> Int? {
  if !prepared.available || prepared.registered {
    return None
  }
  if @context.source_registration_phase(prepared.read) != RegistrationComplete {
    return None
  }
  Some(
    Int::min(
      prepared.limits.topology.max_work,
      prepared.limits.context.stages.max_work,
    ),
  )
}

///|
/// Original owner cancellation, not physical cleanup. Any retained Context
/// entrance must retire with this same continuation; the old read may already
/// be Transferred after its successful registration was captured here.
pub fn clear_parsed_source_registration(
  prepared : ParsedSourceRegistration,
) -> Unit {
  prepared.available = false
  if prepared.context_input is Some(Ok(input)) {
    @context.retire_sourceview_context_input(input)
  }
  prepared.context_input = None
  prepared.context_geometry = None
  @context.clear_source_registration(prepared.read)
}
