///|
pub enum SourceViewProgramIssue {
  InvalidLimits
  Unavailable
  ForeignEnvironment
  ForeignCalendarEnvironment
  CalendarSelection(@environment.CalendarSelectionIssue)
  MissingCalendarArtifact(@environment.CalendarSelection)
  MissingCalendarSelection(Int, @pipeline.Issue)
  ForeignSource
  ForeignPartition(Int)
  BudgetExceeded
  Program(@stage_results.LocalProgramIssue)
  Registration(Int, @sourceviews.PipelineIssue)
}

///|
/// Construct Stage pipelines/imports using the selected type registrations and
/// validate their exact Catalog-backed owners before returning any wiring.
/// Parameter value binding and complete Program closure are separate.
pub fn prepare_sourceview_program(
  views : @sourceviews.PipelineInputs,
  locals : @local_inputs.ProgramEnvironmentInputs,
  limits : @stage_results.LocalProgramLimits,
  calendar? : @environment.SelectedCalendarProfile? = None,
  model_tasks? : @environment.ModelTasks? = None,
) -> Result[
  (@stage_results.ResultWiring, @stage_results.LocalProgramUsage),
  SourceViewProgramIssue,
] {
  match
    prepare_sourceview_program_internal(
      views,
      locals,
      limits,
      calendar~,
      model_tasks~,
    ) {
    Ok((wiring, usage, _)) => Ok((wiring, usage))
    Err(e) => Err(e)
  }
}

///|
// Retain nonshared orchestration cost for enclosing preparation. This is
// computed here, never supplied by a caller as a claimed accounting adjustment.
fn prepare_sourceview_program_internal(
  views : @sourceviews.PipelineInputs,
  locals : @local_inputs.ProgramEnvironmentInputs,
  limits : @stage_results.LocalProgramLimits,
  calendar? : @environment.SelectedCalendarProfile? = None,
  model_tasks? : @environment.ModelTasks? = None,
) -> Result[
  (@stage_results.ResultWiring, @stage_results.LocalProgramUsage, Int),
  SourceViewProgramIssue,
] {
  match
    prepare_sourceview_topology_internal(
      views,
      locals,
      limits,
      calendar~,
      model_tasks~,
      check_only=false,
    ) {
    Ok((Publication(wiring), usage, extra)) => Ok((wiring, usage, extra))
    Ok(_) => abort("mixed preparation modes")
    Err(e) => Err(e)
  }
}

///|
struct SourceViewCheckedTopology {
  topology : @stage_results.CheckedTopology
  views : @sourceviews.PipelineInputs
  attachments : Array[@sourceviews.PipelineAttachment]
}

///|
priv enum SourceViewPreparation {
  Publication(@stage_results.ResultWiring)
  Topology(SourceViewCheckedTopology)
}

///|
/// Check source-owned topology without issuing publication ports. Catalog,
/// partition and local owners are retained; runtime debts remain conditional.
pub fn check_sourceview_program(
  views : @sourceviews.PipelineInputs,
  locals : @local_inputs.ProgramEnvironmentInputs,
  limits : @stage_results.LocalProgramLimits,
  calendar? : @environment.SelectedCalendarProfile? = None,
  model_tasks? : @environment.ModelTasks? = None,
) -> Result[
  (SourceViewCheckedTopology, @stage_results.LocalProgramUsage),
  SourceViewProgramIssue,
] {
  match
    prepare_sourceview_topology_internal(
      views,
      locals,
      limits,
      calendar~,
      model_tasks~,
      check_only=true,
    ) {
    Ok((Topology(topology), usage, _)) => Ok((topology, usage))
    Ok(_) => abort("mixed preparation modes")
    Err(e) => Err(e)
  }
}

///|
pub fn sourceview_checked_topology(
  value : SourceViewCheckedTopology,
) -> @stage_results.CheckedTopology {
  value.topology
}

///|
pub fn topology_sourceviews(
  value : SourceViewCheckedTopology,
) -> @sourceviews.PipelineInputs {
  value.views
}

///|
pub fn topology_sourceview_attachment_at(
  value : SourceViewCheckedTopology,
  index : Int,
) -> @sourceviews.PipelineAttachment? {
  value.attachments.get(index)
}

///|
/// Original SourceView registration gathering, not a checked topology, Plan,
/// Resource Owner or permission. The SAME Source/locals/views/selected inputs
/// stay private; no caller can supply a replacement registration array.
priv enum SourceViewProgramReadState {
  Ready
  Reading(@stage_results.LocalProgramRead)
  Rejected(@stage_results.LocalProgramIssue)
  Consumed
  Retired
}

///|
priv struct SourceViewProgramInput {
  source : @stages.Source
  views : @sourceviews.PipelineInputs
  locals : @local_inputs.ProgramEnvironmentInputs
  limits : @stage_results.LocalProgramLimits
  calendar : @environment.SelectedCalendarProfile?
  model_tasks : @environment.ModelTasks?
  registrations : Array[Array[(String, @pipeline.InputContract)]]
  missing_calendar : @environment.CalendarSelection?
  extra : Int
  prior : Int
  mut topology : SourceViewProgramReadState
}

///|
/// Prepare only the original calendar/partition/registration entrance. All
/// later topology constructors still require their own complete backing.
fn prepare_sourceview_program_input(
  views : @sourceviews.PipelineInputs,
  locals : @local_inputs.ProgramEnvironmentInputs,
  limits : @stage_results.LocalProgramLimits,
  calendar? : @environment.SelectedCalendarProfile? = None,
  model_tasks? : @environment.ModelTasks? = None,
) -> Result[SourceViewProgramInput, SourceViewProgramIssue] {
  if limits.max_work < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_tokens < 0 ||
    limits.max_depth < 0 ||
    limits.max_stages < 0 ||
    limits.max_steps < 0 ||
    limits.max_results < 0 {
    return Err(InvalidLimits)
  }
  if !physical_equal(
      @sourceviews.pipeline_environment(views),
      @local_inputs.program_environment(locals),
    ) {
    return Err(ForeignEnvironment)
  }
  let source = @source_inputs.source(
    @sourceviews.inputs(@sourceviews.pipeline_resolution(views)),
  )
  if !physical_equal(source, @local_inputs.environment_program(locals)) {
    return Err(ForeignSource)
  }
  let partition = @sourceviews.inputs(@sourceviews.pipeline_resolution(views))
  let count = @stages.stage_count(source)
  let prior = @sourceviews.pipeline_inputs_work(views)
  if prior > limits.max_work {
    return Err(BudgetExceeded)
  }
  let (calendar_work, missing_calendar) = match calendar {
    None => {
      let environment = @sourceviews.pipeline_environment(views)
      match
        @environment.read_calendar_selection(
          environment,
          limits.max_work - prior,
        ) {
        Ok(selection) =>
          (@environment.calendar_selection_work(selection), Some(selection))
        Err(MissingSelection) =>
          (
            @decode.object_length(@environment.host_policy(environment)).unwrap() +
            1,
            None,
          )
        Err(BudgetExceeded) => return Err(BudgetExceeded)
        Err(issue) => return Err(CalendarSelection(issue))
      }
    }
    Some(profile) => {
      let selection = @environment.selected_calendar_selection(profile)
      if !physical_equal(
          @environment.calendar_selection_environment(selection),
          @sourceviews.pipeline_environment(views),
        ) {
        return Err(ForeignCalendarEnvironment)
      }
      (@environment.calendar_selection_work(selection), None)
    }
  }
  if prior > limits.max_work ||
    calendar_work > limits.max_work - prior ||
    count > (limits.max_work - prior - calendar_work) / 2 {
    return Err(BudgetExceeded)
  }
  let mut extra = prior + calendar_work + count * 2
  let registrations : Array[Array[(String, @pipeline.InputContract)]] = []
  for stage in 0..<count {
    let admitted = @local_inputs.program_environment_stage(locals, stage).unwrap()
    let retained = @local_inputs.sourceview_inputs(
      @local_inputs.snapshot_inputs(
        @local_inputs.environment_assertions(admitted),
      ),
    )
    if !(retained is Some(v) && physical_equal(v, partition)) {
      return Err(ForeignPartition(stage))
    }
    let n = @sourceviews.pipeline_input_count(views, stage).unwrap()
    if n > limits.max_work - extra {
      return Err(BudgetExceeded)
    }
    extra += n
    registrations.push(
      Array::makei(n, i => {
        @sourceviews.pipeline_input_at(views, stage, i).unwrap()
      }),
    )
  }
  Ok({
    source,
    views,
    locals,
    limits,
    calendar,
    model_tasks,
    registrations,
    missing_calendar,
    extra,
    prior,
    topology: Ready,
  })
}

///|
fn prepare_sourceview_topology_internal(
  views : @sourceviews.PipelineInputs,
  locals : @local_inputs.ProgramEnvironmentInputs,
  limits : @stage_results.LocalProgramLimits,
  calendar? : @environment.SelectedCalendarProfile? = None,
  model_tasks? : @environment.ModelTasks? = None,
  check_only~ : Bool,
) -> Result[
  (SourceViewPreparation, @stage_results.LocalProgramUsage, Int),
  SourceViewProgramIssue,
] {
  let original = match
    prepare_sourceview_program_input(
      views,
      locals,
      limits,
      calendar~,
      model_tasks~,
    ) {
    Err(issue) => return Err(issue)
    Ok(original) => original
  }
  finish_sourceview_program_input_owned(original, check_only~)
}

///|
fn finish_sourceview_program_input_owned(
  original : SourceViewProgramInput,
  check_only~ : Bool,
) -> Result[
  (SourceViewPreparation, @stage_results.LocalProgramUsage, Int),
  SourceViewProgramIssue,
] {
  let {
    source,
    views,
    locals,
    limits,
    calendar,
    model_tasks,
    registrations,
    missing_calendar,
    extra,
    prior,
    ..
  } = original
  let count = @stages.stage_count(source)
  let prepared = if check_only {
    guard original.topology is Ready else { return Err(Unavailable) }
    original.topology = Consumed
    @stage_results.check_local_program(
      source,
      { ..limits, max_work: limits.max_work - extra, },
      environment=Some(locals),
      sourceview_registrations=Some(registrations),
      calendar_profile=calendar.map(@environment.selected_calendar_profile),
      model_tasks~,
    ).map(fn(result) {
      let (topology, usage) = result
      (Topology({ topology, views, attachments: [], }), usage)
    })
  } else {
    let read = match begin_sourceview_program_topology_read(original) {
      Err(issue) => {
        original.topology = Consumed
        return Err(issue)
      }
      Ok(read) => read
    }
    original.topology = Consumed
    let mut phase = @stage_results.local_program_read_phase(read)
    while phase != @stage_results.Complete && phase != @stage_results.Failed {
      if phase == @stage_results.Cleared || phase == @stage_results.Taken {
        return Err(Unavailable)
      }
      phase = @stage_results.advance_local_program_read(read)
    }
    @stage_results.take_local_program_read(read)
    .unwrap()
    .map(fn(result) {
      let (wiring, usage) = result
      guard wiring is @stage_results.Publication(wiring) else {
        abort("mixed preparation modes")
      }
      (Publication(wiring), usage)
    })
  }
  let (wiring, used) = match prepared {
    Ok(v) => v
    Err(Pipeline(stage, issue)) if issue.kind
      is @pipeline.Calendar(MissingProfile) =>
      return Err(
        match missing_calendar {
          Some(selection) => MissingCalendarArtifact(selection)
          None => MissingCalendarSelection(stage, issue)
        },
      )
    Err(e) => return Err(Program(e))
  }
  let mut remaining = limits.max_work - extra - used.work
  for stage in 0..<count {
    let collected = match wiring {
      Publication(v) =>
        @stage_results.stage_port_source(
          @stage_results.wiring_stage_at(v, stage).unwrap(),
        )
      Topology(v) =>
        @stage_results.topology_stage_source(
          @stage_results.topology_stage_at(v.topology, stage).unwrap(),
        )
    }
    // The exact view/collection prefixes are already charged; reserve only this
    // correspondence check's additional work, never a same-shaped substitute.
    let shared = prior + @stages.collection_work(collected)
    let checked = match
      @sourceviews.attach_pipeline_inputs(views, collected, shared + remaining) {
      Ok(v) => v
      Err(e) => return Err(Registration(stage, e))
    }
    remaining -= @sourceviews.pipeline_attachment_work(checked) - shared
    if wiring is Topology(v) {
      v.attachments.push(checked)
    }
  }
  let work = limits.max_work - remaining
  Ok((wiring, { ..used, work, }, work - used.work - prior))
}

///|
/// Retain exactly the original topology constructor. A repeated borrow returns
/// the SAME reader, never a freshly checked Source or reconstructed Program.
fn begin_sourceview_program_topology_read(
  original : SourceViewProgramInput,
) -> Result[@stage_results.LocalProgramRead, SourceViewProgramIssue] {
  match original.topology {
    Reading(read) => return Ok(read)
    Rejected(issue) => return Err(Program(issue))
    Consumed | Retired => return Err(Unavailable)
    Ready => ()
  }
  let result = @stage_results.begin_local_program_read(
    original.source,
    { ..original.limits, max_work: original.limits.max_work - original.extra, },
    environment=Some(original.locals),
    sourceview_registrations=Some(original.registrations),
    calendar_profile=original.calendar.map(
      @environment.selected_calendar_profile,
    ),
    model_tasks=original.model_tasks,
  )
  match result {
    Ok(read) => {
      original.topology = Reading(read)
      Ok(read)
    }
    Err(issue) => {
      original.topology = Rejected(issue)
      Err(Program(issue))
    }
  }
}
