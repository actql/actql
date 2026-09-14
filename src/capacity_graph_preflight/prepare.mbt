///|
/// Unchecked coordinates into this pipeline and its admitted mixed limit set.
/// These are requests for validation, not successful consumer applications.
pub(all) enum ConsumerRequest {
  Sequence(step~ : Int, matches~ : Int, output~ : Int)
  Join(step~ : Int, output~ : Int)
  Components(step~ : Int, nodes~ : Int, output~ : Int)
  Traversal(step~ : Int, paths~ : Int, output~ : Int)
} derive(Eq, Debug)

///|
pub(all) struct PreparationLimits {
  max_work : Int
  max_name_bytes : Int
  max_input_work : Int
  max_operand_work : Int
} derive(Eq, Debug)

///|
pub(all) enum PreparationIssue {
  InvalidLimits
  WorkLimit
  ForeignGuardOwner
  ForeignGuardBindings
  Graph(Issue)
  Program(@program.PreparationIssue)
  Sequence(Int, @sequence.Issue)
  Join(Int, @program.JoinLimitIssue)
  Components(Int, @program.ComponentsLimitIssue)
  Traversal(Int, @program.TraversalLimitIssue)
  SequenceCollection(@sequence.CollectionIssue)
  JoinCollection(@program.JoinCollectionIssue)
  ComponentsCollection(@program.ComponentsCollectionIssue)
  TraversalCollection(@program.TraversalCollectionIssue)
  Coverage(ApplicationCoverageIssue)
} derive(Eq, Debug)

///|
/// Construct graph input, ordinary derived proof and local consumer coverage
/// from one admitted source owner and selected policy. Every consumer family
/// is checked for omitted operations and the final join checks limit coverage.
/// Prior Host/wire admission, enclosing Program correspondence and runtime
/// enforcement remain separate; unsupported proofs are not silently deferred.
pub fn prepare_application_coverage(
  pipeline : @pipeline.CheckedPipeline,
  sources : @host.HostSources,
  policy : @policy.Policy,
  requests : Array[ConsumerRequest],
  limits : PreparationLimits,
  bindings? : @program.CountBindings? = None,
  guards? : @pipeline.BoundAuthorGuards? = None,
  producers? : Array[@program.Applications] = [],
) -> Result[ApplicationCoverage, PreparationIssue] {
  if limits.max_work < 0 ||
    limits.max_name_bytes < 0 ||
    limits.max_input_work < 0 ||
    limits.max_operand_work < 0 {
    return Err(InvalidLimits)
  }
  if requests.length() > limits.max_work / 2 {
    return Err(WorkLimit)
  }
  if guards is Some(bound) {
    if !physical_equal(
        @pipeline.author_guards_pipeline(
          @pipeline.bound_guard_occurrences(bound),
        ),
        pipeline,
      ) {
      return Err(ForeignGuardOwner)
    }
    if bindings is Some(counts) {
      guard @pipeline.bound_guard_bindings(bound) is Some(values) &&
        physical_equal(values, @program.parameter_values(counts)) else {
        return Err(ForeignGuardBindings)
      }
    }
  }
  let mut remaining = limits.max_work - requests.length() * 2
  let graph = match
    check(pipeline, sources, policy, {
      max_work: remaining,
      max_name_bytes: limits.max_name_bytes,
    }) {
    Ok(v) => v
    Err(e) => return Err(Graph(e))
  }
  remaining -= usage(graph).0
  let sequences : Array[@sequence.SequenceLimits] = []
  let joins : Array[@program.JoinLimit] = []
  let components : Array[@program.ComponentsLimits] = []
  let traversals : Array[@program.TraversalLimits] = []
  for index, request in requests {
    match request {
      Sequence(step~, matches~, output~) => {
        let selected = match guards {
          Some(bound) =>
            @sequence.check_bound_limits(
              pipeline,
              step,
              sources,
              policy,
              matches,
              output,
              bound,
              max_work=remaining,
            )
          None =>
            @sequence.check_host_limits(
              pipeline,
              step,
              sources,
              policy,
              matches,
              output,
              max_work=remaining,
            )
        }
        let v = match selected {
          Ok(v) => v
          Err(e) => return Err(Sequence(index, e))
        }
        remaining -= @sequence.usage(v)
        sequences.push(v)
      }
      _ => ()
    }
  }
  let sequence = match
    @sequence.check_applications(
      pipeline,
      sources,
      policy,
      sequences,
      max_work=remaining,
    ) {
    Ok(v) => v
    Err(e) => return Err(SequenceCollection(e))
  }
  remaining -= @sequence.application_work(sequence)
  let program = match
    @program.prepare_derived_applications(
      pipeline,
      @host.source_claims(sources),
      {
        max_work: remaining,
        max_input_work: limits.max_input_work,
        max_operand_work: limits.max_operand_work,
      },
      bindings~,
      graph_inputs=Some(graph),
      sequences=Some(sequence),
      producers~,
    ) {
    Ok(v) => v
    Err(e) => return Err(Program(e))
  }
  remaining -= @program.application_work(program)
  for index, request in requests {
    match request {
      Sequence(..) => ()
      Join(step~, output~) => {
        let v = match
          @program.check_join_limit(
            pipeline,
            step,
            sources,
            program,
            policy,
            output,
            max_work=remaining,
          ) {
          Ok(v) => v
          Err(e) => return Err(Join(index, e))
        }
        remaining -= @program.join_limit_work(v)
        joins.push(v)
      }
      Components(step~, nodes~, output~) => {
        let v = match
          @program.check_components_limits(
            pipeline,
            step,
            sources,
            program,
            policy,
            nodes,
            output,
            guards~,
            max_work=remaining,
          ) {
          Ok(v) => v
          Err(e) => return Err(Components(index, e))
        }
        remaining -= @program.components_limit_work(v)
        components.push(v)
      }
      Traversal(step~, paths~, output~) => {
        let v = match
          @program.check_traversal_limits(
            pipeline,
            step,
            sources,
            program,
            policy,
            paths,
            output,
            guards~,
            max_work=remaining,
          ) {
          Ok(v) => v
          Err(e) => return Err(Traversal(index, e))
        }
        remaining -= @program.traversal_limit_work(v)
        traversals.push(v)
      }
    }
  }
  let joined = match
    @program.check_join_applications(
      pipeline,
      sources,
      program,
      policy,
      joins,
      max_work=remaining,
    ) {
    Ok(v) => v
    Err(e) => return Err(JoinCollection(e))
  }
  remaining -= @program.join_application_work(joined)
  let component = match
    @program.check_components_applications(
      pipeline,
      sources,
      program,
      policy,
      components,
      max_work=remaining,
    ) {
    Ok(v) => v
    Err(e) => return Err(ComponentsCollection(e))
  }
  remaining -= @program.components_application_work(component)
  let traversal = match
    @program.check_traversal_applications(
      pipeline,
      sources,
      program,
      policy,
      traversals,
      max_work=remaining,
    ) {
    Ok(v) => v
    Err(e) => return Err(TraversalCollection(e))
  }
  remaining -= @program.traversal_application_work(traversal)
  match
    check_application_coverage(
      graph,
      program,
      sequence,
      joins=Some(joined),
      components=Some(component),
      traversals=Some(traversal),
      max_work=remaining,
    ) {
    Ok(v) => Ok({ ..v, work: limits.max_work - remaining + v.work, })
    Err(e) => Err(Coverage(e))
  }
}
