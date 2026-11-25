///|
// Follow the original checked imports, using the Context writer's remaining
// work. Every projected edge keeps the original Map's two port identities.
fn write_static_explanation_transfers(
  checked : @checked.CheckedProgram,
  steps : @canonical.FrozenArray[@canonical.CanonicalValue],
  writer : @encode.Writer,
  remaining : Ref[Int],
) -> Unit raise {
  @encode.begin_array(writer)
  for i in 0..<@canonical.array_count(steps) {
    spend_static_explanation_work(remaining)
    let step = @canonical.array_at(steps, i).unwrap()
    let key = explanation_original_field(step, "key")
    let stage = explanation_original_ordinal(key, "stage_ordinal")
    guard @canonical.object_field(step, "ports")
      is Some(@canonical.Array(ports)) else {
      raise @encode.InvalidStructure
    }
    for j in 0..<@canonical.array_count(ports) {
      spend_static_explanation_work(remaining)
      let port = @canonical.array_at(ports, j).unwrap()
      guard explanation_original_text(port, "role") == "input" &&
        @canonical.object_field(port, "source") is Some(locator) &&
        @canonical.object_field(locator, "kind")
        is Some(@canonical.String("stage_input")) else {
        continue
      }
      if explanation_original_ordinal(locator, "stage_ordinal") != stage {
        raise StaticExplanationForeignSubject
      }
      let input = explanation_original_ordinal(locator, "input_port_ordinal")
      guard @checked.unit_input_completeness(checked, stage, input)
        is Some(requirement) else {
        raise StaticExplanationForeignSubject
      }
      guard requirement.binding is @checked.Imported(interface, producer) else {
        continue
      }
      guard @checked.unit_pipeline(checked, stage) is Some(consumer) &&
        @pipeline.input_producer(consumer, input) is Some(selected) &&
        physical_equal(selected, producer) else {
        raise StaticExplanationForeignSubject
      }
      // A Result projection may change the contract between the two ports.
      // Keep its lineage explicit without asserting identical carrier DATA.
      let projected = @pipeline.producer_projection(producer) is Some(_)
      let predecessor = static_explanation_transfer_stage(
        checked, stage, interface, producer, remaining,
      )
      if static_explanation_output(
          steps,
          predecessor,
          @pipeline.producer_target(producer),
          remaining,
        )
        is Some((source_step, source_port)) &&
        explanation_original_text(source_port, "carrier") ==
        explanation_original_text(port, "carrier") &&
        (
          projected ||
          explanation_original_text(source_port, "carrier_contract_cid") ==
          explanation_original_text(port, "carrier_contract_cid")
        ) {
        @encode.begin_object(writer)
        @encode.key(writer, "consumer")
        write_static_explanation_transfer_port(writer, step, port)
        @encode.key(writer, "producer")
        write_static_explanation_transfer_port(writer, source_step, source_port)
        @encode.key(writer, "result_projection")
        @encode.bool_value(writer, projected)
        @encode.end_object(writer)
      }
    }
  }
  @encode.end_array(writer)
}

///|
fn static_explanation_transfer_stage(
  checked : @checked.CheckedProgram,
  stage : Int,
  interface : @checked.BuiltResultInterface,
  producer : @pipeline.ProducedInput,
  remaining : Ref[Int],
) -> Int raise {
  let pipeline = @pipeline.producer_pipeline(producer)
  for prior in 0..<stage {
    spend_static_explanation_work(remaining)
    if @checked.unit_pipeline(checked, prior) is Some(original) &&
      physical_equal(original, pipeline) &&
      @checked.unit_definition_cid(checked, prior) ==
      Some(interface.producer_unit_definition_cid) {
      return prior
    }
  }
  raise StaticExplanationForeignSubject
}

///|
fn write_static_explanation_transfer_port(
  writer : @encode.Writer,
  step : @canonical.CanonicalValue,
  port : @canonical.CanonicalValue,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  explanation_text(
    writer,
    "port_id",
    explanation_original_text(port, "port_id"),
  )
  explanation_text(
    writer,
    "step_id",
    explanation_original_text(step, "step_id"),
  )
  @encode.end_object(writer)
}
