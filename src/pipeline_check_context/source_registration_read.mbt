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
priv struct SourceResolutionConstruction {
  geometry : @sourceviews.ResolutionConstructionGeometry
  work : Int64?
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
  mut selection_work : Int
  mut pipeline_work : Int
  mut resolution_construction : SourceResolutionConstruction?
  mut local_child : @local_inputs.LocalEnvironmentPreparation?
  mut local_index_usage : @refs.Usage?
  mut local_index_inspection_work : Int64?
  mut local_groups_work : Int?
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
    selection_work: 0,
    pipeline_work: 0,
    resolution_construction: None,
    local_child: None,
    local_index_usage: None,
    local_index_inspection_work: None,
    local_groups_work: None,
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
/// New selection work ONLY. The resolver's inherited completed collection
/// prefix is excluded; success/failure/clear never debit or refund it again.
/// Later pipeline/Local costs remain their distinct original pass conventions.
pub fn source_registration_selection_work(read : SourceRegistrationRead) -> Int {
  read.selection_work
}

///|
/// New pipeline-registration work ONLY. Completed resolution remains its
/// semantic inherited prefix, not another debit. Local costs remain separate.
pub fn source_registration_pipeline_work(read : SourceRegistrationRead) -> Int {
  read.pipeline_work
}

///|
/// Metadata work envelope for the SAME original inputs/selected limits, before
/// inspection. Caller backs this bound/extent/borrowed argument frame first.
pub fn source_registration_resolution_inspection_bound(
  read : SourceRegistrationRead,
) -> Int64? {
  guard read.state is SelectDeclarations &&
    read.arguments is Some(original) &&
    read.collected is Some(inputs) else {
    return None
  }
  Some(
    @sourceviews.resolution_construction_inspection_bound(inputs, {
      max_work: original.limits.max_work,
      max_inputs: original.max_inputs,
      max_views: original.max_views,
    }),
  )
}

///|
/// Observe once on the same immutable input/Catalog/limits. Cached repeats
/// return the same work Some; they are not another walk or debit opportunity.
/// Actual Resource receipts/current/grow/retirement remain outside this DATA.
pub fn observe_source_registration_resolution_construction(
  read : SourceRegistrationRead,
) -> Int64? {
  guard read.state is SelectDeclarations &&
    read.arguments is Some(original) &&
    read.collected is Some(inputs) else {
    return None
  }
  if read.resolution_construction is Some(completed) {
    return completed.work
  }
  let geometry = @sourceviews.observe_resolution_construction_geometry(
    inputs,
    original.catalog,
    {
      max_work: original.limits.max_work,
      max_inputs: original.max_inputs,
      max_views: original.max_views,
    },
  )
  let work = Some(geometry.inspection_work)
  read.resolution_construction = Some({ geometry, work, })
  work
}

///|
pub fn source_registration_resolution_inspection_work(
  read : SourceRegistrationRead,
) -> Int64? {
  match read.resolution_construction {
    None => None
    Some(completed) => completed.work
  }
}

///|
/// Only stored same-original geometry and selected limits can quote this
/// phase. No caller geometry, alternate Catalog/limits or permission enters.
/// Caller separately funds this quotation frame and the existing observer.
pub fn source_registration_resolution_construction(
  read : SourceRegistrationRead,
) -> @sourceviews.ResolutionConstructionInventory? {
  guard read.state is SelectDeclarations &&
    read.arguments is Some(original) &&
    read.resolution_construction is Some(completed) else {
    return None
  }
  @sourceviews.resolution_construction_inventory(completed.geometry, {
    max_work: original.limits.max_work,
    max_inputs: original.max_inputs,
    max_views: original.max_views,
  })
}

///|
/// Additional cache wrapper1H2R, work Some1H2W and stored Some1H1R1W.
/// Inspection peak also includes selected Limits1H3W and bound Some1H2W.
/// The geometry owner supplies its actual record extent; no field table here.
pub fn source_registration_resolution_inspection_extent() -> @shape.CollectionConstructionExtent {
  @shape.add_collection_construction_extents(
    @sourceviews.resolution_construction_inspection_extent(),
    { record_headers: 5L, reference_slots: 3L, scalar_words: 8L, },
  ).unwrap()
}

///|
pub fn source_registration_resolution_inspection_retained_extent() -> @shape.CollectionConstructionExtent {
  @shape.add_collection_construction_extents(
    @sourceviews.resolution_construction_geometry_extent(),
    { record_headers: 3L, reference_slots: 3L, scalar_words: 3L, },
  ).unwrap()
}

///|
/// O(1) constructor quantities from the SAME held Resolved and original limit.
/// No replacement Source/Catalog/counts, metadata walk or permission enters.
/// The quotation frame and original work-result pair remain separately backed.
pub fn source_registration_pipeline_construction(
  read : SourceRegistrationRead,
) -> @sourceviews.PipelinePreparationConstruction? {
  guard read.state is BuildRegistrations(resolved) &&
    read.arguments is Some(original) else {
    return None
  }
  @sourceviews.pipeline_preparation_construction(
    resolved,
    original.limits.max_work,
  )
}

///|
/// Original nested Local phase DATA, including a retained failed child. The
/// child itself cannot escape this registration read or be taken externally.
pub fn source_registration_local_phase(
  read : SourceRegistrationRead,
) -> @local_inputs.LocalEnvironmentPhase? {
  read.local_child.map(@local_inputs.local_environment_preparation_phase)
}

///|
pub fn source_registration_local_failure_phase(
  read : SourceRegistrationRead,
) -> @local_inputs.LocalEnvironmentPhase? {
  read.local_child.bind(
    @local_inputs.local_environment_preparation_failure_phase,
  )
}

///|
pub fn source_registration_local_index_usage(
  read : SourceRegistrationRead,
) -> @refs.Usage? {
  read.local_index_usage
}

///|
/// SAME original Local grouping observation, including partial typed refusal.
/// No inherited Index work, second loop or replacement zero enters this fact.
pub fn source_registration_local_groups_work(
  read : SourceRegistrationRead,
) -> Int? {
  read.local_groups_work
}

///|
pub fn source_registration_local_groups_construction(
  read : SourceRegistrationRead,
) -> @shape.CollectionConstructionInventory? {
  read.local_child.bind(@local_inputs.local_environment_groups_construction)
}

///|
pub fn source_registration_local_index_inspection_bound(
  read : SourceRegistrationRead,
) -> Int64? {
  read.local_child.bind(@local_inputs.local_environment_index_inspection_bound)
}

///|
pub fn observe_source_registration_local_index_construction(
  read : SourceRegistrationRead,
) -> Int64? {
  let work = read.local_child.bind(
    @local_inputs.observe_local_environment_index_construction,
  )
  if work is Some(_) {
    read.local_index_inspection_work = work
  }
  work
}

///|
pub fn source_registration_local_index_inspection_work(
  read : SourceRegistrationRead,
) -> Int64? {
  read.local_index_inspection_work
}

///|
pub fn source_registration_local_index_construction(
  read : SourceRegistrationRead,
) -> @refs.IndexConstructionInventory? {
  read.local_child.bind(@local_inputs.local_environment_index_construction)
}

///|
fn clear_source_registration_local(read : SourceRegistrationRead) -> Unit {
  if read.local_child is Some(child) {
    @local_inputs.clear_local_environment_preparation(child)
  }
  read.local_child = None
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
      let (result, spent) = @sourceviews.observe_resolve(
        read.collected.unwrap(),
        original.catalog,
        {
          max_work: original.limits.max_work,
          max_inputs: original.max_inputs,
          max_views: original.max_views,
        },
      )
      read.selection_work = spent
      read.state = match result {
        Err(issue) => RegistrationDone(Err(Selection(issue)))
        Ok(resolved) => BuildRegistrations(resolved)
      }
    }
    BuildRegistrations(resolved) => {
      let (result, spent) = @sourceviews.observe_prepare_pipeline_inputs(
        resolved,
        original.limits.max_work,
      )
      read.pipeline_work = spent
      read.state = match result {
        Err(issue) => RegistrationDone(Err(Registration(issue)))
        Ok(views) => BuildLocal(views)
      }
    }
    BuildLocal(views) =>
      // The same original convention includes collection/selection in views.
      // Only that completed prefix is subtracted for the Local reader. Its
      // sourceview partition is the SAME collected Inputs, not another scan.
      match read.local_child {
        None =>
          match
            @local_inputs.begin_local_environment_preparation(
              original.source,
              @sourceviews.pipeline_environment(views),
              {
                ..original.limits,
                max_work: original.limits.max_work -
                @sourceviews.pipeline_inputs_work(views),
              },
              sourceviews=read.collected,
            ) {
            Err(issue) => read.state = RegistrationDone(Err(LocalInputs(issue)))
            Ok(child) => read.local_child = Some(child)
          }
        Some(child) => {
          let phase = @local_inputs.advance_local_environment_preparation(child)
          read.local_index_usage = @local_inputs.local_environment_preparation_index_usage(
            child,
          )
          read.local_groups_work = @local_inputs.local_environment_preparation_groups_work(
            child,
          )
          match phase {
            LocalEnvironmentComplete | LocalEnvironmentFailed => {
              let result = @local_inputs.take_local_environment_preparation_result(
                child,
              ).unwrap()
              // A taken failure retains completed/pending child aliases until
              // the outside caller clears/takes this original registration.
              read.state = RegistrationDone(
                match result {
                  Err(issue) => Err(LocalInputs(issue))
                  Ok(locals) => Ok((views, locals))
                },
              )
            }
            LocalEnvironmentIndex
            | LocalEnvironmentGroups
            | LocalEnvironmentSnapshot
            | LocalEnvironmentDeclaration
            | LocalEnvironmentReconciliation
            | LocalEnvironmentAssembly => ()
            LocalEnvironmentTransferred | LocalEnvironmentRetired =>
              abort("unexposed original Local child cannot retire externally")
          }
        }
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
      read.resolution_construction = None
      clear_source_registration_local(read)
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
  read.resolution_construction = None
  clear_source_registration_local(read)
  read.state = if transferred {
    RegistrationHandedOff
  } else {
    RegistrationCleared
  }
}

///|
/// Installed constructor DATA, not capacity. Argument record1H3R3W, its Some
///1H1R1W, read1H8R3W, initial phase1H1W and returned Ok1H1R1W. The supplied
/// Source/Catalog/limits and each phase's metadata/constructor overlap remain
/// separately backed. The collection phase also adds its original observer.
pub fn source_registration_initial_construction_extent() -> @shape.CollectionConstructionExtent {
  { record_headers: 5L, reference_slots: 13L, scalar_words: 9L, }
}
