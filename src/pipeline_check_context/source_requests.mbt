///|
pub enum SourceRequestIssue {
  InvalidLimits
  ForeignSource
  MissingSourceViews
  BudgetExceeded
  Context(@sourceviews.RequestIssue)
  Parameters(@sourceviews.RequestParameterIssue)
  Stage(Int, @sourceviews.AcquisitionIssue)
  Join(Int, @sourceviews.KeyedJoinIssue)
  Facts(@environment.LookupCapacityIssue)
  KeyedFacts(Int, @sourceviews.KeyedFactsIssue)
}

///|
struct SourceRequestContexts {
  inputs : ReconciledContexts
  slots : @request_slots.Slots
  parameters : @sourceviews.RequestParameters?
  stages : Array[@sourceviews.PipelineRequests]
  joins : Array[@sourceviews.CheckedKeyedJoins]
  facts : @environment.LookupCapacities?
  keyed_facts : Array[@sourceviews.CheckedKeyedFacts]
  work : Int
  pairs : Int
  nodes : Int
  text : Int
}

///|
/// Build every stage's source request checks from the actual Program consumers
/// and the already selected Program bindings. Host authorization is not implied.
pub fn check_source_requests(
  inputs : ReconciledContexts,
  slots : @request_slots.Slots,
  limits : @sourceviews.RequestLimits,
) -> Result[SourceRequestContexts, SourceRequestIssue] {
  if limits.max_work < 0 ||
    limits.max_pairs < 0 ||
    limits.values.max_nodes < 0 ||
    limits.values.max_depth < 0 ||
    limits.values.max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  let operations = inputs.wired.stages.operations
  let source = @stages.operations_source(@stages.bound_operations(operations))
  if !physical_equal(@request_slots.source(slots), source) {
    return Err(ForeignSource)
  }
  let mut work = inputs.usage.work
  if work > limits.max_work {
    return Err(BudgetExceeded)
  }
  let mut pairs = 0
  let mut nodes = 0
  let mut text = 0
  let stages = []
  let joins = []
  let mut facts = None
  let keyed_facts = []
  let parameters = match inputs.sourceviews {
    None => {
      if @request_slots.count(slots) != 0 {
        return Err(MissingSourceViews)
      }
      if @request_slots.work(slots) > limits.max_work - work {
        return Err(BudgetExceeded)
      }
      work += @request_slots.work(slots)
      None
    }
    Some(views) => {
      let resolved = @sourceviews.pipeline_resolution(views)
      let available = limits.max_work - (work - @sourceviews.work(resolved))
      let context = match
        @sourceviews.prepare_requests(resolved, slots, available) {
        Ok(v) => v
        Err(e) => return Err(Context(e))
      }
      let bound = @references.bound_values(
        @stages.bound_program_index(operations),
      )
      let prepared = match
        @sourceviews.prepare_request_parameters(context, bound, available) {
        Ok(v) => v
        Err(e) => return Err(Parameters(e))
      }
      // Only this exact resolution has already been charged by input assembly.
      // The shared request/binding index is constructed and charged once.
      let added = @sourceviews.request_parameter_work(prepared) -
        @sourceviews.work(resolved)
      if added > limits.max_work - work {
        return Err(BudgetExceeded)
      }
      work += added
      let checked_facts = match
        @environment.check_lookup_capacities(
          @sourceviews.pipeline_catalog_references(views),
          {
            max_work: limits.max_work - work,
            max_facts: limits.max_work - work,
          },
        ) {
        Ok(v) => v
        Err(e) => return Err(Facts(e))
      }
      work += @environment.lookup_capacity_usage(checked_facts).0
      facts = Some(checked_facts)
      for i in 0..<inputs.uses.length() {
        let checked = match
          @sourceviews.check_pipeline_requests(inputs.uses[i], prepared, {
            max_work: limits.max_work - work,
            max_pairs: limits.max_pairs - pairs,
            values: {
              max_nodes: limits.values.max_nodes - nodes,
              max_depth: limits.values.max_depth,
              max_text_bytes: limits.values.max_text_bytes - text,
            },
          }) {
          Ok(v) => v
          Err(e) => return Err(Stage(i, e))
        }
        let (used_work, used_pairs, used_nodes, used_text) = @sourceviews.pipeline_requests_usage(
          checked,
        )
        work += used_work
        pairs += used_pairs
        nodes += used_nodes
        text += used_text
        let linked = match
          @sourceviews.check_keyed_joins(checked, limits.max_work - work) {
          Ok(v) => v
          Err(e) => return Err(Join(i, e))
        }
        work += @sourceviews.keyed_joins_work(linked)
        let owned_facts = match
          @sourceviews.check_keyed_facts(
            linked,
            checked_facts,
            limits.max_work - work,
          ) {
          Ok(v) => v
          Err(e) => return Err(KeyedFacts(i, e))
        }
        work += @sourceviews.keyed_facts_work(owned_facts)
        keyed_facts.push(owned_facts)
        joins.push(linked)
        stages.push(checked)
      }
      Some(prepared)
    }
  }
  Ok({
    inputs,
    slots,
    parameters,
    stages,
    joins,
    facts,
    keyed_facts,
    work,
    pairs,
    nodes,
    text,
  })
}

///|
pub fn source_request_facts(
  v : SourceRequestContexts,
) -> @environment.LookupCapacities? {
  v.facts
}

///|
pub fn source_request_keyed_facts(
  v : SourceRequestContexts,
  i : Int,
) -> @sourceviews.CheckedKeyedFacts? {
  v.keyed_facts.get(i)
}

///|
pub fn source_request_joins(
  v : SourceRequestContexts,
  i : Int,
) -> @sourceviews.CheckedKeyedJoins? {
  v.joins.get(i)
}

///|
pub fn source_request_inputs(v : SourceRequestContexts) -> ReconciledContexts {
  v.inputs
}

///|
pub fn source_request_slots(v : SourceRequestContexts) -> @request_slots.Slots {
  v.slots
}

///|
pub fn source_request_parameters(
  v : SourceRequestContexts,
) -> @sourceviews.RequestParameters? {
  v.parameters
}

///|
pub fn source_request_stage(
  v : SourceRequestContexts,
  i : Int,
) -> @sourceviews.PipelineRequests? {
  v.stages.get(i)
}

///|
pub fn source_request_usage(v : SourceRequestContexts) -> (Int, Int, Int, Int) {
  (v.work, v.pairs, v.nodes, v.text)
}
