///|
/// Actual Local constructor progress, not Resource ownership, permission or
/// physical retirement. Fund each selected step and its borrowed frame before
/// entry. A nested failure has no invented zero work or completed Usage.
pub(all) enum LocalEnvironmentPhase {
  LocalEnvironmentIndex
  LocalEnvironmentGroups
  LocalEnvironmentSnapshot
  LocalEnvironmentDeclaration
  LocalEnvironmentReconciliation
  LocalEnvironmentAssembly
  LocalEnvironmentComplete
  LocalEnvironmentFailed
  LocalEnvironmentTransferred
  LocalEnvironmentRetired
} derive(Eq, Debug)

///|
priv struct LocalEnvironmentArguments {
  source : @stages.Source
  environment : @environment.WireEnvironment
  limits : Limits
  sourceviews : @sourceviews.Inputs?
}

///|
priv struct LocalStageGroups {
  names : Map[String, Int]
  by_stage : Array[Array[@snapshot.EnvironmentSnapshot]]
}

///|
priv struct LocalEnvironmentPending {
  prepared : Prepared
  limits : Limits
}

///|
priv struct LocalIndexConstruction {
  geometry : @refs.IndexConstructionGeometry
  limits : @refs.Limits
  work : Int64?
}

///|
priv struct LocalSnapshotConstruction {
  member_index : Int
  original_member : @environment.Member
  limits : @snapshot.Limits
  geometry : (Int, Int, Int)?
}

///|
priv enum LocalEnvironmentState {
  ReadIndex
  MakeGroups
  ReadSnapshot(Int)
  ReadDeclaration(Int)
  ReconcileStage(Int)
  AssembleStages
  LocalDone(Result[ProgramEnvironmentInputs, PrepareEnvironmentIssue])
  LocalHandedOff
  LocalCleared
}

///|
/// One original Source/Environment/partition and selected limits. Completed
/// index/member/Stage aliases and pending declaration survive a failed step
/// until this read's caller takes or clears them. No second Ledger or quota.
struct LocalEnvironmentPreparation {
  mut arguments : LocalEnvironmentArguments?
  count : Int
  members : Int
  mut index : @refs.Index?
  mut index_observation : @refs.Usage?
  mut index_construction : LocalIndexConstruction?
  mut groups_work : Int?
  mut snapshot_emission : (Int, (Int, Int, Int)?)?
  mut snapshot_construction : LocalSnapshotConstruction?
  mut groups : LocalStageGroups?
  mut stages : Array[EnvironmentInputs]?
  mut pending : LocalEnvironmentPending?
  mut pending_member : @snapshot.EnvironmentSnapshot?
  mut work : Int
  mut nodes : Int
  mut text : Int
  mut stage_work : Int
  mut stage_nodes : Int
  mut stage_text : Int
  mut failed_at : LocalEnvironmentPhase?
  mut state : LocalEnvironmentState
}

///|
pub fn begin_local_environment_preparation(
  source : @stages.Source,
  environment : @environment.WireEnvironment,
  limits : Limits,
  sourceviews? : @sourceviews.Inputs? = None,
) -> Result[LocalEnvironmentPreparation, PrepareEnvironmentIssue] {
  if limits.max_work < 0 ||
    limits.max_nodes < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  if sourceviews is Some(views) &&
    !physical_equal(@sourceviews.source(views), source) {
    return Err(ForeignSourceViews)
  }
  let count = @stages.stage_count(source)
  let members = @environment.member_count(
    environment,
    @environment.SchemaSnapshots,
  )
  if count >= limits.max_work || members > limits.max_work - count - 1 {
    return Err(BudgetExceeded)
  }
  Ok({
    arguments: Some({ source, environment, limits, sourceviews, }),
    count,
    members,
    index: None,
    index_observation: None,
    index_construction: None,
    groups_work: None,
    snapshot_emission: None,
    snapshot_construction: None,
    groups: None,
    stages: None,
    pending: None,
    pending_member: None,
    work: limits.max_work - count - members - 1,
    nodes: limits.max_nodes,
    text: limits.max_text_bytes,
    stage_work: 0,
    stage_nodes: 0,
    stage_text: 0,
    failed_at: None,
    state: ReadIndex,
  })
}

///|
/// The SAME original entrance plus its newly charged work. All three early
/// refusals precede the initial charge; they report actual zero charged work,
/// not missing nested usage. No Index or snapshot constructor runs here.
/// The ordinary result-only entrance allocates no additional observation pair.
pub fn observe_begin_local_environment_preparation(
  source : @stages.Source,
  environment : @environment.WireEnvironment,
  limits : Limits,
  sourceviews? : @sourceviews.Inputs? = None,
) -> (Result[LocalEnvironmentPreparation, PrepareEnvironmentIssue], Int) {
  let result = begin_local_environment_preparation(
    source,
    environment,
    limits,
    sourceviews~,
  )
  let spent = match result {
    Ok(read) => limits.max_work - read.work
    Err(InvalidLimits) | Err(ForeignSourceViews) | Err(BudgetExceeded) => 0
    Err(_) => abort("Local entrance cannot return a later constructor failure")
  }
  (result, spent)
}

///|
pub fn local_environment_preparation_phase(
  read : LocalEnvironmentPreparation,
) -> LocalEnvironmentPhase {
  match read.state {
    ReadIndex => LocalEnvironmentIndex
    MakeGroups => LocalEnvironmentGroups
    ReadSnapshot(_) => LocalEnvironmentSnapshot
    ReadDeclaration(_) => LocalEnvironmentDeclaration
    ReconcileStage(_) => LocalEnvironmentReconciliation
    AssembleStages => LocalEnvironmentAssembly
    LocalDone(Ok(_)) => LocalEnvironmentComplete
    LocalDone(Err(_)) => LocalEnvironmentFailed
    LocalHandedOff => LocalEnvironmentTransferred
    LocalCleared => LocalEnvironmentRetired
  }
}

///|
/// Retained origin of the first failed step, including after result transfer.
/// It does not imply measured nested work or a Resource cleanup observation.
pub fn local_environment_preparation_failure_phase(
  read : LocalEnvironmentPreparation,
) -> LocalEnvironmentPhase? {
  read.failed_at
}

///|
// Original cumulative semantic Usage is defined only by completed assembly.
// A missing observation on a failed nested call is not a zero debit/refund.
pub fn local_environment_preparation_usage(
  read : LocalEnvironmentPreparation,
) -> Usage? {
  match read.state {
    LocalDone(Ok(result)) => Some(program_environment_usage(result))
    _ => None
  }
}

///|
/// The SAME original index's charged-policy and admitted-name-byte observation.
/// None means unstarted, never a missing failed observation converted to0.
/// This scalar fact survives alias clear/take; it does not debit/refund a Ledger.
pub fn local_environment_preparation_index_usage(
  read : LocalEnvironmentPreparation,
) -> @refs.Usage? {
  read.index_observation
}

///|
/// Newly charged Stage-name work of the original grouping loop only. None
/// means unstarted; a completed zero or partial refusal is an actual Some.
/// The same observation survives take/clear, without refunding consumed work.
pub fn local_environment_preparation_groups_work(
  read : LocalEnvironmentPreparation,
) -> Int? {
  read.groups_work
}

///|
/// Last actual Local member emission: original member index and SAME writer
/// observation, including a partial typed refusal. Some(index,None) records
/// an attempted read without a constructed writer; outer None is unstarted.
/// Connector-only members do not replace this fact. No whole nested work or
/// physical use/retirement follows from these charged-writer cells.
pub fn local_environment_preparation_snapshot_emission(
  read : LocalEnvironmentPreparation,
) -> (Int, (Int, Int, Int)?)? {
  read.snapshot_emission
}

///|
/// Original observer plus stored index/observation pair1H1R1W and Some1H1R1W.
/// The Source wrapper forwards this SAME Option without another observation
/// record. Quotation, borrowed-call and VM frames stay separate.
pub fn local_environment_snapshot_emission_observation_extent() -> @shape.CollectionConstructionExtent {
  @shape.add_collection_construction_extents(
    @snapshot.member_emission_observation_extent(),
    { record_headers: 2L, reference_slots: 2L, scalar_words: 2L, },
  ).unwrap()
}

///|
/// Capture the exact selected Member once before its original constructor.
/// Geometry comes from that same Entry's retained hash metrics, with no body
/// traversal or new admission. Repeats return the SAME geometry Some; no
/// caller Member, replacement limits or asserted quantity is accepted.
pub fn observe_local_environment_snapshot_construction(
  read : LocalEnvironmentPreparation,
) -> (Int, Int, Int)? {
  guard read.state is ReadSnapshot(i) && read.arguments is Some(original) else {
    return None
  }
  if read.snapshot_construction is Some(captured) {
    if captured.member_index != i {
      abort("original snapshot construction index changed")
    }
    return captured.geometry
  }
  let original_member = @environment.member_at(
    original.environment,
    @environment.SchemaSnapshots,
    i,
  ).unwrap()
  let geometry = Some(@environment.member_emission_geometry(original_member))
  read.snapshot_construction = Some({
    member_index: i,
    original_member,
    limits: local_environment_snapshot_limits(read, original),
    geometry,
  })
  geometry
}

///|
/// A failed original step retains its same member/metadata aliases until
/// explicit take/clear. This DATA is not an admission or cleanup receipt.
pub fn local_environment_snapshot_construction_geometry(
  read : LocalEnvironmentPreparation,
) -> (Int, Int, Int)? {
  read.snapshot_construction.bind(captured => captured.geometry)
}

///|
/// Derive the selected original Member's text-emission quantity only after its
/// existing capture. None is unobserved, not zero. The caller owns this returned
/// DATA and its quotation frame; retain it once across the actual grow/current
/// boundary. UTF8/reader/schema/parent backing and retirement stay separate.
pub fn local_environment_snapshot_text_construction(
  read : LocalEnvironmentPreparation,
) -> @environment.RegistryConstructionExtent? {
  read.snapshot_construction.map(captured => {
    @environment.member_text_emission_construction_extent(
      captured.original_member,
    )
  })
}

///|
/// Member access controls plus Member1H2R2W, scalar tuple1H3W, its Some1H1R1W,
/// captured record1H3R1W, its Some1H1R1W and SAME selected Limits1H3W.
/// No input-sized work container or second selection. The body borrows Limits.
pub fn local_environment_snapshot_construction_inspection_extent() -> @shape.CollectionConstructionExtent {
  @shape.add_collection_construction_extents(
    @environment.member_access_construction_extent(),
    local_snapshot_inspection_retained_units,
  ).unwrap()
}

///|
pub fn local_environment_snapshot_construction_retained_extent() -> @shape.CollectionConstructionExtent {
  local_snapshot_inspection_retained_units
}

///|
/// Scalar geometry/Some and captured metadata only. The SAME Member wrapper
/// has its own common-owner extent and may transfer into the Snapshot result.
/// Caller-held geometry Some and input borrowers can outlive a cache clear;
/// neither this split nor an absent cache acknowledges physical retirement.
pub fn local_environment_snapshot_construction_metadata_extent() -> @shape.CollectionConstructionExtent {
  local_snapshot_metadata_units
}

///|
let local_snapshot_metadata_units : @shape.CollectionConstructionExtent = {
  record_headers: 5L,
  reference_slots: 5L,
  scalar_words: 9L,
}

///|
let local_snapshot_inspection_retained_units : @shape.CollectionConstructionExtent = @shape.add_collection_construction_extents(
  @environment.member_instance_construction_extent(),
  local_snapshot_metadata_units,
).unwrap()

///|
/// Constructor inventory for the SAME original grouping step. Every empty
/// inner Array is allocated up front, even if a later name charge refuses.
/// At most count names enter the Map; no name/body rescan is needed to quote
/// that bound. Source IDs stay borrowed, never copied or re-admitted here.
/// Shared Map/Array growth rules expand these DATA quantities. With no members,
/// this SAME step also allocates the empty successor Stage array. Include that
/// original tail here; later snapshot pushes/Stage growth and failure/quotation
/// controls remain separate. This inventory does not grant capacity.
pub fn local_environment_groups_construction(
  read : LocalEnvironmentPreparation,
) -> @shape.CollectionConstructionInventory? {
  guard read.state is MakeGroups else { return None }
  let count = read.count.to_int64()
  Some({
    // Groups/Some/work are3H3R3W; the next phase adds1H1W.
    // No members: successor Some adds1H1R1W and its empty Array below.
    records: if read.members == 0 {
      5L
    } else {
      4L
    },
    record_references: if read.members == 0 {
      4L
    } else {
      3L
    },
    record_words: if read.members == 0 {
      5L
    } else {
      4L
    },
    reference_arrays: (if read.members == 0 { 2L } else { 1L }) + count,
    reference_items: count,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 1L,
    map_entries: count,
  })
}

///|
pub fn local_environment_index_inspection_bound(
  read : LocalEnvironmentPreparation,
) -> Int64? {
  guard read.state is ReadIndex && read.arguments is Some(original) else {
    return None
  }
  Some(
    @refs.index_construction_inspection_bound(original.source, {
      max_work: read.work,
      max_text_bytes: read.text,
    }),
  )
}

///|
/// Observe once and retain the exact selected Limits for the actual index
/// call after grow. Repeated inspection returns the SAME work Some, not a
/// second traversal or debit opportunity. No foreign geometry/limits enter.
pub fn observe_local_environment_index_construction(
  read : LocalEnvironmentPreparation,
) -> Int64? {
  guard read.state is ReadIndex && read.arguments is Some(original) else {
    return None
  }
  if read.index_construction is Some(completed) {
    return completed.work
  }
  let limits : @refs.Limits = {
    max_work: read.work,
    max_text_bytes: read.text,
  }
  let geometry = @refs.observe_index_construction_geometry(
    original.source,
    limits,
  )
  let work = Some(geometry.inspection_work)
  read.index_construction = Some({ geometry, limits, work, })
  work
}

///|
pub fn local_environment_index_inspection_work(
  read : LocalEnvironmentPreparation,
) -> Int64? {
  read.index_construction.bind(completed => completed.work)
}

///|
pub fn local_environment_index_construction(
  read : LocalEnvironmentPreparation,
) -> @refs.IndexConstructionInventory? {
  guard read.state is ReadIndex && read.index_construction is Some(completed) else {
    return None
  }
  @refs.index_construction_inventory(completed.geometry, completed.limits)
}

///|
/// Same geometry owner plus Limits1H2W, work Some1H2W, captured wrapper1H3R,
/// stored Some1H1R1W and bound Some1H2W. Quote frames/UTF/VM stay separate.
pub fn local_environment_index_inspection_extent() -> @shape.CollectionConstructionExtent {
  @shape.add_collection_construction_extents(
    @refs.index_construction_inspection_extent(),
    { record_headers: 5L, reference_slots: 4L, scalar_words: 7L, },
  ).unwrap()
}

///|
pub fn local_environment_index_inspection_retained_extent() -> @shape.CollectionConstructionExtent {
  @shape.add_collection_construction_extents(
    @refs.index_construction_geometry_extent(),
    { record_headers: 4L, reference_slots: 4L, scalar_words: 5L, },
  ).unwrap()
}

///|
fn fail_local_environment_preparation(
  read : LocalEnvironmentPreparation,
  issue : PrepareEnvironmentIssue,
) -> LocalEnvironmentPhase {
  read.failed_at = Some(local_environment_preparation_phase(read))
  read.state = LocalDone(Err(issue))
  LocalEnvironmentFailed
}

///|
fn local_environment_after_snapshots(
  read : LocalEnvironmentPreparation,
) -> Unit {
  // This Array exists at its original point, after every snapshot read, not
  // before a failed member. All earlier groups/index aliases stay retained.
  read.stages = Some([])
  read.state = if read.count == 0 { AssembleStages } else { ReadDeclaration(0) }
}

///|
/// One actual original constructor step. No callback/current, second semantic
/// reader, resource calculation or retry is introduced. Terminal calls do not
/// re-enter children. The same outer owner must back each step before entry.
pub fn advance_local_environment_preparation(
  read : LocalEnvironmentPreparation,
) -> LocalEnvironmentPhase {
  guard read.arguments is Some(original) else {
    return local_environment_preparation_phase(read)
  }
  match read.state {
    ReadIndex => {
      let limits = match read.index_construction {
        Some(metadata) => metadata.limits
        None => { max_work: read.work, max_text_bytes: read.text, }
      }
      let (result, usage) = @refs.observe_prepare(original.source, limits)
      read.index_observation = Some(usage)
      read.index = match result {
        Ok(index) => Some(index)
        Err(issue) =>
          return fail_local_environment_preparation(read, Index(issue))
      }
      // As before, Stage reconciliation accounts for the index prefix. Do not
      // deduct it from the outer remaining-work convention a second time.
      read.state = MakeGroups
    }
    MakeGroups => {
      let before = read.work
      let names : Map[String, Int] = Map([])
      let by_stage : Array[Array[@snapshot.EnvironmentSnapshot]] = Array::makei(
        read.count,
        _ => [],
      )
      read.groups = Some({ names, by_stage, })
      for i in 0..<read.count {
        let name = @stages.stage_at(original.source, i).unwrap().id
        if name.length() > read.work {
          read.groups_work = Some(before - read.work)
          return fail_local_environment_preparation(read, BudgetExceeded)
        }
        read.work -= name.length()
        names[name] = i
      }
      read.groups_work = Some(before - read.work)
      if read.members == 0 {
        local_environment_after_snapshots(read)
      } else {
        read.state = ReadSnapshot(0)
      }
    }
    ReadSnapshot(i) => {
      let entry = match read.snapshot_construction {
        Some(captured) => {
          if captured.member_index != i {
            abort("original snapshot construction index changed")
          }
          captured.original_member
        }
        None =>
          @environment.member_at(
            original.environment,
            @environment.SchemaSnapshots,
            i,
          ).unwrap()
      }
      let connector = match
        @environment.connector_source_snapshot_selector(entry) {
        Ok(Some(_)) => true
        Ok(None) => false
        Err(issue) =>
          return fail_local_environment_preparation(
            read,
            ConnectorSnapshot(i, issue),
          )
      }
      if connector {
        let (bytes, n) = @environment.member_usage(entry)
        if bytes > read.text || n > read.nodes || n > read.work {
          return fail_local_environment_preparation(read, BudgetExceeded)
        }
        read.text -= bytes
        read.nodes -= n
        read.work -= n
      } else {
        let limits = match read.snapshot_construction {
          Some(captured) => captured.limits
          None => local_environment_snapshot_limits(read, original)
        }
        let (result, emitted) = @snapshot.observe_read_member(entry, limits)
        read.snapshot_emission = Some((i, emitted))
        let admitted = match result {
          Ok(value) => value
          Err(issue) =>
            return fail_local_environment_preparation(read, Snapshot(i, issue))
        }
        read.pending_member = Some(admitted)
        let snapshot = @snapshot.environment_snapshot(
          read.pending_member.unwrap(),
        )
        let (bytes, n) = @snapshot.usage(snapshot)
        read.text -= bytes
        read.nodes -= n
        read.work -= n
        let name = @source_ref.stage_name(@snapshot.source_reference(snapshot))
        if name.length() > read.work {
          return fail_local_environment_preparation(read, BudgetExceeded)
        }
        read.work -= name.length()
        let groups = read.groups.unwrap()
        let at = match groups.names.get(name) {
          Some(at) => at
          None =>
            return fail_local_environment_preparation(
              read,
              UnknownStage(i, name),
            )
        }
        groups.by_stage[at].push(read.pending_member.unwrap())
        read.pending_member = None
      }
      read.snapshot_construction = None
      if i + 1 == read.members {
        local_environment_after_snapshots(read)
      } else {
        read.state = ReadSnapshot(i + 1)
      }
    }
    ReadDeclaration(i) => {
      let remaining : Limits = {
        max_work: read.work,
        max_nodes: read.nodes,
        max_text_bytes: read.text,
        max_depth: original.limits.max_depth,
      }
      let prepared = match
        prepare(original.source, i, remaining, sourceviews=original.sourceviews) {
        Ok(value) => value
        Err(issue) =>
          return fail_local_environment_preparation(read, Stage(i, issue))
      }
      read.pending = Some({ prepared, limits: remaining, })
      read.state = ReconcileStage(i)
    }
    ReconcileStage(i) => {
      let pending = read.pending.unwrap()
      let checked = match
        reconcile_environment(
          pending.prepared,
          read.index.unwrap(),
          original.environment,
          read.groups.unwrap().by_stage[i],
          pending.limits,
        ) {
        Ok(value) => value
        Err(issue) =>
          return fail_local_environment_preparation(read, Environment(i, issue))
      }
      let used = environment_usage(checked)
      read.work -= used.work
      read.nodes -= used.nodes
      read.text -= used.text_bytes
      read.stage_work += used.work
      read.stage_nodes += used.nodes
      read.stage_text += used.text_bytes
      read.stages.unwrap().push(checked)
      read.pending = None
      read.state = if i + 1 == read.count {
        AssembleStages
      } else {
        ReadDeclaration(i + 1)
      }
    }
    AssembleStages => {
      let result = match
        assemble_environment(
          original.source,
          original.environment,
          read.stages.unwrap(),
          {
            max_work: read.work + read.stage_work,
            max_nodes: read.nodes + read.stage_nodes,
            max_text_bytes: read.text + read.stage_text,
            max_depth: original.limits.max_depth,
          },
        ) {
        Ok(value) => value
        Err(issue) =>
          return fail_local_environment_preparation(read, Collection(issue))
      }
      let used = program_environment_usage(result)
      read.state = LocalDone(
        Ok({
          ..result,
          usage: {
            work: original.limits.max_work -
            read.work +
            (used.work - read.stage_work),
            nodes: original.limits.max_nodes -
            read.nodes +
            (used.nodes - read.stage_nodes),
            text_bytes: original.limits.max_text_bytes -
            read.text +
            (used.text_bytes - read.stage_text),
          },
        }),
      )
    }
    LocalDone(_) | LocalHandedOff | LocalCleared => ()
  }
  local_environment_preparation_phase(read)
}

///|
fn drop_local_environment_preparation_aliases(
  read : LocalEnvironmentPreparation,
) -> Unit {
  read.arguments = None
  read.index = None
  read.groups = None
  read.stages = None
  read.pending = None
  read.pending_member = None
  read.snapshot_construction = None
}

///|
/// Transfer the SAME original Result once. A failed read keeps its completed
/// and pending aliases until explicit clear. Neither handoff nor alias clear
/// is physical stop, consumed-work refund or Resource cleanup acknowledgement.
pub fn take_local_environment_preparation_result(
  read : LocalEnvironmentPreparation,
) -> Result[ProgramEnvironmentInputs, PrepareEnvironmentIssue]? {
  match read.state {
    LocalDone(result) => {
      // On failure, completed/pending holders are not part of the returned
      // error. Keep those aliases until the caller's explicit later clear.
      if result is Ok(_) {
        drop_local_environment_preparation_aliases(read)
      }
      read.state = LocalHandedOff
      Some(result)
    }
    _ => None
  }
}

///|
pub fn clear_local_environment_preparation(
  read : LocalEnvironmentPreparation,
) -> Unit {
  let transferred = read.state is LocalHandedOff
  drop_local_environment_preparation_aliases(read)
  read.state = if transferred { LocalHandedOff } else { LocalCleared }
}

///|
/// Installed initial constructor DATA only: arguments1H4R and its Some1H1R1W;
/// read1H13R8W; initial phase1H1W; returned Ok1H1R1W. Borrowed original Source,
/// Environment, limits/partition and every later phase frame are separate.
pub fn local_environment_preparation_initial_construction_extent() -> @shape.CollectionConstructionExtent {
  local_environment_initial_units
}

///|
let local_environment_initial_units : @shape.CollectionConstructionExtent = {
  record_headers: 5L,
  reference_slots: 19L,
  scalar_words: 11L,
}

///|
/// The success owner/arguments/phase survive; only its returned Ok is scratch.
pub fn local_environment_preparation_retained_construction_extent() -> @shape.CollectionConstructionExtent {
  local_environment_initial_retained_units
}

///|
let local_environment_initial_retained_units : @shape.CollectionConstructionExtent = {
  record_headers: local_environment_initial_units.record_headers - 1L,
  reference_slots: local_environment_initial_units.reference_slots - 1L,
  scalar_words: local_environment_initial_units.scalar_words - 1L,
}

///|
pub fn local_environment_preparation_observation_extent() -> @shape.CollectionConstructionExtent {
  @shape.int_work_result_pair_construction_extent()
}

///|
// Original selector used both by the ordinary reader and the retained entry.
// Construction has no callback or admission; later data is never substituted.
fn local_environment_snapshot_limits(
  read : LocalEnvironmentPreparation,
  original : LocalEnvironmentArguments,
) -> @snapshot.Limits {
  {
    max_bytes: read.text,
    max_nodes: Int::min(read.nodes, read.work),
    max_depth: original.limits.max_depth,
  }
}

///|
/// SAME selected limits associated with the captured original Member. None is
/// unobserved; these DATA are neither permission nor full reader backing.
pub fn local_environment_snapshot_construction_limits(
  read : LocalEnvironmentPreparation,
) -> @snapshot.Limits? {
  read.snapshot_construction.map(captured => captured.limits)
}
