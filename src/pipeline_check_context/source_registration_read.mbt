///|
/// Semantic progress DATA only. No phase implies capacity, current permission
/// or physical retirement. The caller backs each original constructor before
/// advancing and keeps every returned/borrowed owner alive until real release.
pub(all) enum SourceRegistrationPhase {
  RegistrationCollect
  RegistrationSelect
  RegistrationPipeline
  RegistrationLocal
  RegistrationComplete
  RegistrationFailed
  RegistrationTransferred
  RegistrationRetired
} derive(Eq, Debug)

///|
priv struct SourceRegistrationArguments {
  source : @stages.Source
  catalog : @environment.SourceRequestContracts
  limits : @local_inputs.Limits
  max_inputs : Int
  max_views : Int
  max_order_keys : Int
}

///|
priv enum SourceRegistrationState {
  ReadDeclarations
  SelectDeclarations
  BuildRegistrations(@sourceviews.Resolved)
  BuildLocal(@sourceviews.PipelineInputs)
  RegistrationDone(
    Result[
      (@sourceviews.PipelineInputs, @local_inputs.ProgramEnvironmentInputs),
      SourceRegistrationIssue,
    ]
  )
  RegistrationHandedOff
  RegistrationCleared
}

///|
/// The original Source, Catalog and selected limits are bound once. Later
/// phases accept no replacement inputs/limits, equal owner or caller verdict.
/// This is constructor DATA on the outside parent's lifetime, not a Resource
/// owner, grant, checked Program, or an independently releasable reservation.
struct SourceRegistrationRead {
  mut arguments : SourceRegistrationArguments?
  mut collected : @source_inputs.Inputs?
  mut collection_work : Int
  mut state : SourceRegistrationState
}

///|
pub fn begin_source_registration(
  source : @stages.Source,
  catalog : @environment.SourceRequestContracts,
  limits : @local_inputs.Limits,
  max_inputs~ : Int,
  max_views~ : Int,
  max_order_keys~ : Int,
) -> Result[SourceRegistrationRead, SourceRegistrationIssue] {
  if limits.max_work < 0 ||
    limits.max_nodes < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_depth < 0 ||
    max_inputs < 0 ||
    max_views < 0 ||
    max_order_keys < 0 {
    return Err(InvalidLimits)
  }
  Ok({
    arguments: Some({
      source,
      catalog,
      limits,
      max_inputs,
      max_views,
      max_order_keys,
    }),
    collected: None,
    collection_work: 0,
    state: ReadDeclarations,
  })
}

///|
pub fn source_registration_phase(
  read : SourceRegistrationRead,
) -> SourceRegistrationPhase {
  match read.state {
    ReadDeclarations => RegistrationCollect
    SelectDeclarations => RegistrationSelect
    BuildRegistrations(_) => RegistrationPipeline
    BuildLocal(_) => RegistrationLocal
    RegistrationDone(Ok(_)) => RegistrationComplete
    RegistrationDone(Err(_)) => RegistrationFailed
    RegistrationHandedOff => RegistrationTransferred
    RegistrationCleared => RegistrationRetired
  }
}

///|
/// Borrow the SAME collected Inputs/Option for the next original constructor's
/// metadata and selection. No recollection, copied partition or new Source.
/// The outside caller must retain backing for its borrowed synchronous frame.
pub fn source_registration_collected_inputs(
  read : SourceRegistrationRead,
) -> @source_inputs.Inputs? {
  read.collected
}

///|
/// Charged work of collection ONLY, including its partial typed refusal. This
/// is not total registration/Local work, CPU or a budget grant. Later passes
/// retain their own existing work conventions; no missing failure cost is zero.
pub fn source_registration_collection_work(
  read : SourceRegistrationRead,
) -> Int {
  read.collection_work
}

///|
/// One actual original phase per call. No callback/current observation, second
/// semantic reader or capacity computation is added. Completed/failed/taken/
/// retired calls do not re-enter any reader. The caller must quote and fund
/// the selected phase's complete input/overlap BEFORE invoking this method.
pub fn advance_source_registration(
  read : SourceRegistrationRead,
) -> SourceRegistrationPhase {
  guard read.arguments is Some(original) else {
    return source_registration_phase(read)
  }
  match read.state {
    ReadDeclarations => {
      let (result, spent) = @source_inputs.observe_collect(original.source, {
        max_work: original.limits.max_work,
        max_order_keys: original.max_order_keys,
      })
      read.collection_work = spent
      match result {
        Err(issue) => read.state = RegistrationDone(Err(Declarations(issue)))
        Ok(inputs) => {
          read.collected = Some(inputs)
          read.state = SelectDeclarations
        }
      }
    }
    SelectDeclarations => {
      let result = @sourceviews.resolve(
        read.collected.unwrap(),
        original.catalog,
        {
          max_work: original.limits.max_work,
          max_inputs: original.max_inputs,
          max_views: original.max_views,
        },
      )
      read.state = match result {
        Err(issue) => RegistrationDone(Err(Selection(issue)))
        Ok(resolved) => BuildRegistrations(resolved)
      }
    }
    BuildRegistrations(resolved) => {
      let result = @sourceviews.prepare_pipeline_inputs(
        resolved,
        original.limits.max_work,
      )
      read.state = match result {
        Err(issue) => RegistrationDone(Err(Registration(issue)))
        Ok(views) => BuildLocal(views)
      }
    }
    BuildLocal(views) => {
      // The same original convention includes collection/selection in views.
      // Only that completed prefix is subtracted for the Local reader. Its
      // sourceview partition is the SAME collected Inputs, not another scan.
      let result = @local_inputs.prepare_environment(
        original.source,
        @sourceviews.pipeline_environment(views),
        {
          ..original.limits,
          max_work: original.limits.max_work -
          @sourceviews.pipeline_inputs_work(views),
        },
        sourceviews=read.collected,
      )
      read.state = RegistrationDone(
        match result {
          Err(issue) => Err(LocalInputs(issue))
          Ok(locals) => Ok((views, locals))
        },
      )
    }
    RegistrationDone(_) | RegistrationHandedOff | RegistrationCleared => ()
  }
  source_registration_phase(read)
}

///|
/// Transfer the SAME success tuple or typed failure once. Issue/Result backing
/// can also escape: both transfers remain sticky through later clear. This
/// method drops only this read's aliases, not backing/permission/physical use.
pub fn take_source_registration_result(
  read : SourceRegistrationRead,
) -> Result[
  (@sourceviews.PipelineInputs, @local_inputs.ProgramEnvironmentInputs),
  SourceRegistrationIssue,
]? {
  match read.state {
    RegistrationDone(result) => {
      read.arguments = None
      read.collected = None
      read.state = RegistrationHandedOff
      Some(result)
    }
    _ => None
  }
}

///|
/// Drop only this pure reader's aliases. A real handoff stays Transferred;
/// ordinary untransferred cancellation stays Retired. Neither acknowledges a
/// borrower, successor, native buffer, current callback or physical cleanup.
pub fn clear_source_registration(read : SourceRegistrationRead) -> Unit {
  let transferred = read.state is RegistrationHandedOff
  read.arguments = None
  read.collected = None
  read.state = if transferred {
    RegistrationHandedOff
  } else {
    RegistrationCleared
  }
}

///|
/// Installed constructor DATA, not capacity. Argument record1H3R3W, its Some
///1H1R1W, read1H3R1W, initial phase1H1W and returned Ok1H1R1W. The supplied
/// Source/Catalog/limits and each phase's metadata/constructor overlap remain
/// separately backed. The collection phase also adds its original observer.
pub fn source_registration_initial_construction_extent() -> @shape.CollectionConstructionExtent {
  { record_headers: 5L, reference_slots: 8L, scalar_words: 7L, }
}
