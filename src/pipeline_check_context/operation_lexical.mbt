///|
pub(all) enum OperationLexicalIssue {
  InvalidLimits
  BudgetExceeded
  ForeignEnvironment
  MissingArtifact
  Selection(@environment.TextRankSelectionIssue)
  MissingProfile(Int, Int, Int)
  ProfileMismatch(Int, Int, Int)
} derive(Eq, Debug)

///|
pub struct OperationLexicalResolution {
  stage : Int
  producer_visit : Int
  step : Int
  operation : @vector.CheckedTextRank
  selected : @environment.SelectedTextRankProfile
}

///|
struct ProgramOperationLexical {
  requirements : ProgramOperationRequirements
  cells : ProgramOperationCells
  profile : @environment.SelectedTextRankProfile?
  entries : Array[OperationLexicalResolution]
  work : Int
}

///|
pub fn check_program_operation_lexical(
  cells : ProgramOperationCells,
  profile : @environment.SelectedTextRankProfile?,
  max_work : Int,
  max_resolutions : Int,
) -> Result[ProgramOperationLexical, OperationLexicalIssue] {
  if max_work < 0 || max_resolutions < 0 {
    return Err(InvalidLimits)
  }
  if cells.work >= max_work {
    return Err(BudgetExceeded)
  }
  let b = { remaining: max_work - cells.work - 1, }
  let requirements = cells.requirements
  let environment = @environment.capacity_environment(requirements.capacity)
  let stages = requirements.stages
  let entries : Array[OperationLexicalResolution] = []
  try {
    match profile {
      Some(p) => {
        let selection = @environment.selected_text_rank_selection(p)
        if !physical_equal(
            @environment.text_rank_selection_environment(selection),
            environment,
          ) {
          return Err(ForeignEnvironment)
        }
        scalar_spend(b, @environment.text_rank_selection_work(selection))
      }
      None =>
        match @environment.read_text_rank_selection(environment, b.remaining) {
          Ok(_) => return Err(MissingArtifact)
          Err(MissingSelection) =>
            scalar_spend(
              b,
              @decode.object_length(@environment.host_policy(environment)).unwrap() +
              1,
            )
          Err(BudgetExceeded) => return Err(BudgetExceeded)
          Err(issue) => return Err(Selection(issue))
        }
    }
    for stage in 0..<stages.contexts.length() {
      scalar_spend(b, 1)
      let visits = stages.contexts[stage].visits
      for visit in 0..<visits.length() {
        scalar_spend(b, 1)
        let pipeline = @parameter_slots.pipeline(visits[visit].collected)
        for step in 0..<@pipeline.step_count(pipeline) {
          scalar_spend(b, 1)
          guard @pipeline.step_at(pipeline, step).unwrap().operation
            is @pipeline.TextRank(checked=operation, ..) else {
            continue
          }
          guard profile is Some(selected) else {
            return Err(MissingProfile(stage, visit, step))
          }
          if entries.length() == max_resolutions {
            return Err(BudgetExceeded)
          }
          if @vector.text_rank_profile(operation) is Some(existing) {
            let actual = @lexical.cid(existing)
            let expected = @lexical.cid(
              @environment.selected_text_rank_profile(selected),
            )
            scalar_spend(b, actual.length())
            scalar_spend(b, expected.length())
            if actual != expected {
              return Err(ProfileMismatch(stage, visit, step))
            }
          }
          entries.push({
            stage,
            producer_visit: visit,
            step,
            operation,
            selected,
          })
        }
      }
    }
    Ok({ cells, requirements, profile, entries, work: max_work - b.remaining, })
  } catch {
    OperationScalarStop(_) => Err(BudgetExceeded)
  }
}

///|
pub fn operation_lexical_cells(
  v : ProgramOperationLexical,
) -> ProgramOperationCells {
  v.cells
}

///|
pub fn operation_lexical_profile(
  v : ProgramOperationLexical,
) -> @environment.SelectedTextRankProfile? {
  v.profile
}

///|
pub fn operation_lexical_count(v : ProgramOperationLexical) -> Int {
  v.entries.length()
}

///|
pub fn operation_lexical_at(
  v : ProgramOperationLexical,
  index : Int,
) -> OperationLexicalResolution? {
  v.entries.get(index)
}

///|
pub fn operation_lexical_work(v : ProgramOperationLexical) -> Int {
  v.work
}
