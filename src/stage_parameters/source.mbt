///|
struct Source {
  program : @stage.Program
  stages : Array[@stage.Stage]
  declarations : @parameter.Declarations
}

///|
pub(all) enum Issue {
  Declarations(@parameter.Issue)
  InvalidStage
  ForeignDeclarations
  ForeignSteps
  ForeignInitialFrom
  Collection(@collection.Issue)
} derive(Eq, Debug)

///|
struct CollectedStage {
  source : Source
  stage_index : Int
  collection : @collection.Collected
}

///|
/// Read declarations from the retained Program, not from a separate caller map.
pub fn prepare(
  program : @stage.Program,
  limits : @parameter.DeclarationLimits,
) -> Result[Source, Issue] {
  let root = @decode.open_object(@stage.program_body(program)).unwrap()
  match @parameter.read_declarations(@decode.lookup(root, "params"), limits) {
    Err(e) => Err(Declarations(e))
    Ok(declarations) =>
      Ok({ program, stages: @stage.stages(program), declarations, })
  }
}

///|
pub fn declarations(source : Source) -> @parameter.Declarations {
  source.declarations
}

///|
pub fn program(source : Source) -> @stage.Program {
  source.program
}

///|
pub fn stage_count(source : Source) -> Int {
  source.stages.length()
}

///|
pub fn stage_at(source : Source, index : Int) -> @stage.Stage? {
  source.stages.get(index)
}

///|
fn same_cursor(a : @decode.Cursor, b : @decode.Cursor) -> Bool {
  @decode.tree_index(a, b) == @decode.tree_index(a, a)
}

///|
fn same_optional(a : @decode.Cursor?, b : @decode.Cursor?) -> Bool {
  match (a, b) {
    (None, None) => true
    (Some(a), Some(b)) => same_cursor(a, b)
    _ => false
  }
}

///|
/// Collect local operation references with paths relative to the stage body.
/// This does not certify input contracts, Results, Effects or full Program use.
pub fn collect(
  source : Source,
  index : Int,
  pipeline : @pipeline.CheckedPipeline,
  limits : @collection.Limits,
) -> Result[CollectedStage, Issue] {
  let stage = match stage_at(source, index) {
    None => return Err(InvalidStage)
    Some(stage) => stage
  }
  match @pipeline.parameters(pipeline) {
    Some(d) =>
      if !physical_equal(d, source.declarations) {
        return Err(ForeignDeclarations)
      }
    None => return Err(ForeignDeclarations)
  }
  let body = @stage.stage_body(stage)
  let object = @decode.open_object(body).unwrap()
  let steps = @decode.required(object, "steps").unwrap()
  if !same_cursor(steps, @pipeline.source(pipeline)) {
    return Err(ForeignSteps)
  }
  if !same_optional(
      @decode.lookup(object, "from"),
      @pipeline.initial_from(pipeline),
    ) {
    return Err(ForeignInitialFrom)
  }
  match @collection.collect(body, pipeline, limits) {
    Err(e) => Err(Collection(e))
    Ok(collection) => Ok({ source, stage_index: index, collection, })
  }
}

///|
pub fn source(value : CollectedStage) -> Source {
  value.source
}

///|
pub fn stage_index(value : CollectedStage) -> Int {
  value.stage_index
}

///|
pub fn collection(value : CollectedStage) -> @collection.Collected {
  value.collection
}
