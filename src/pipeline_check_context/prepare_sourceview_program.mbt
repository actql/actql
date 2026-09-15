///|
pub enum SourceViewProgramIssue {
  InvalidLimits
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
) -> Result[
  (@stage_results.ResultWiring, @stage_results.LocalProgramUsage),
  SourceViewProgramIssue,
] {
  match prepare_sourceview_program_internal(views, locals, limits, calendar~) {
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
) -> Result[
  (@stage_results.ResultWiring, @stage_results.LocalProgramUsage, Int),
  SourceViewProgramIssue,
] {
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
  let (wiring, used) = match
    @stage_results.prepare_local_program(
      source,
      { ..limits, max_work: limits.max_work - extra, },
      environment=Some(locals),
      sourceview_registrations=Some(registrations),
      calendar_profile=calendar.map(@environment.selected_calendar_profile),
    ) {
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
    let collected = @stage_results.stage_port_source(
      @stage_results.wiring_stage_at(wiring, stage).unwrap(),
    )
    // The exact view/collection prefixes are already charged; reserve only this
    // correspondence check's additional work, never a same-shaped substitute.
    let shared = prior + @stages.collection_work(collected)
    let checked = match
      @sourceviews.attach_pipeline_inputs(views, collected, shared + remaining) {
      Ok(v) => v
      Err(e) => return Err(Registration(stage, e))
    }
    remaining -= @sourceviews.pipeline_attachment_work(checked) - shared
  }
  let work = limits.max_work - remaining
  Ok((wiring, { ..used, work, }, work - used.work - prior))
}
