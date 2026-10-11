///|
priv struct ScriptDemand {
  steps : Array[Array[Bool]]
  inputs : Array[Array[Bool]]
  pipelines : Array[@pipeline.CheckedPipeline]
}

///|
priv suberror DemandStop {
  DemandStop(BindingDemandIssue)
}

///|
// The graph is issued by the common checker. Ranges merely say which emitted
// operations belong to one authored body: demanding any of them keeps all
// operations in that body, including assertions unrelated to its output slot.
// More deeply nested bindings keep their separate ownership and demand.
fn trace_query_binding_demand(
  wiring : @stage_results.ResultWiring,
  stage_arrays : Array[Array[@builder.Node]],
  capture_count : Int,
  ranges : Array[ScriptBindingRange],
  max_work : Int,
) -> Result[ScriptDemand, BindingDemandIssue] {
  let source = @stage_results.wiring_source(wiring)
  let stage_count = @stage_parameters.stage_count(source)
  if capture_count < 0 || capture_count + stage_arrays.length() != stage_count {
    return Err(ForeignStage)
  }
  let mut work = max_work
  fn spend(count : Int) -> Unit raise DemandStop {
    if count < 0 || count > work {
      raise DemandStop(WorkLimit)
    }
    work -= count
  }
  try {
    spend(stage_count)
    let pipelines = Array::makei(stage_count, stage => {
      @pipeline_parameters.pipeline(
        @stage_parameters.collection(
          @stage_results.stage_port_source(
            @stage_results.wiring_stage_at(wiring, stage).unwrap(),
          ),
        ),
      )
    })
    let owners = []
    let steps = []
    let inputs = []
    for stage, pipeline in pipelines {
      let n = @pipeline.step_count(pipeline)
      let m = @pipeline.input_count(pipeline)
      spend(n + m)
      if stage >= capture_count && stage_arrays[stage - capture_count].length() != n {
        raise DemandStop(ForeignStage)
      }
      owners.push(Array::make(n, -1))
      steps.push(Array::make(n, false))
      inputs.push(Array::make(m, false))
    }
    for index, range in ranges {
      let mut owner = None
      for stage, array in stage_arrays {
        spend(1)
        if physical_equal(array, range.steps) {
          owner = Some(stage + capture_count)
          break
        }
      }
      guard owner is Some(stage) else { raise DemandStop(ForeignStage) }
      if range.start < 0 || range.end < range.start || range.end > owners[stage].length() {
        raise DemandStop(InvalidRange)
      }
      spend(range.end - range.start)
      for step in range.start..<range.end {
        let previous = owners[stage][step]
        if previous < 0 || range.end - range.start < ranges[previous].end - ranges[previous].start {
          owners[stage][step] = index
        }
      }
    }
    let pending : Array[(Int, @pipeline.Target)] = []
    let demanded_bodies = Array::make(ranges.length(), false)
    fn enqueue(stage : Int, target : @pipeline.Target) -> Unit raise DemandStop {
      spend(1)
      pending.push((stage, target))
    }
    // Statement operations and all explicit Results/Effects are compulsory.
    // Generated capture ports alone are not public roots.
    for stage in capture_count..<stage_count {
      for step in 0..<owners[stage].length() {
        spend(1)
        if owners[stage][step] < 0 {
          enqueue(stage, @pipeline.Step(step))
        }
      }
    }
    for index in 0..<@stage_results.export_count(wiring) {
      let root = @stage_results.export_at(wiring, index).unwrap()
      let stage = @stage_parameters.stage_index(
        @stage_results.stage_port_source(@stage_results.export_stage(root)),
      )
      enqueue(stage, @relation_results.port_target(@stage_results.export_port(root)))
    }
    while pending.pop() is Some((stage, target)) {
      spend(1)
      match target {
        Step(step) => {
          if steps[stage][step] { continue }
          steps[stage][step] = true
          let body = owners[stage][step]
          if body >= 0 && !demanded_bodies[body] {
            demanded_bodies[body] = true
            for sibling in 0..<owners[stage].length() {
              spend(1)
              if owners[stage][sibling] == body {
                enqueue(stage, @pipeline.Step(sibling))
              }
            }
          }
          let checked = @pipeline.step_at(pipelines[stage], step).unwrap()
          for occurrence in @pipeline.input_occurrences(checked) {
            enqueue(stage, occurrence.target)
          }
        }
        Input(input) => {
          if inputs[stage][input] { continue }
          inputs[stage][input] = true
          let name = @pipeline.input_at(pipelines[stage], input).unwrap().0
          let imports = @stage_results.attached_imports(
            @stage_results.wiring_imports_at(wiring, stage).unwrap(),
          )
          let mut found = false
          for index in 0..<@stage_results.import_count(imports) {
            spend(1)
            let edge = @stage_results.import_at(imports, index).unwrap()
            if @stage_results.input_name(edge) == name {
              let producer_stage = @stage_parameters.stage_index(
                @stage_results.stage_port_source(@stage_results.input_stage(edge)),
              )
              let producer = @stage_results.input_producer(edge)
              if !physical_equal(@pipeline.producer_pipeline(producer), pipelines[producer_stage]) {
                raise DemandStop(ForeignStage)
              }
              enqueue(producer_stage, @pipeline.producer_target(producer))
              found = true
              break
            }
          }
          if !found {
            let stage_source = @stage_parameters.stage_at(source, stage).unwrap()
            for (imported, _) in @program.imports(stage_source) {
              spend(1)
              if imported == name { raise DemandStop(MissingImport) }
            }
          }
        }
      }
    }
    Ok({ steps, inputs, pipelines, })
  } catch {
    DemandStop(issue) => Err(issue)
  }
}
