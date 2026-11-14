///|
pub(all) enum ClientInteractivePlanIssue {
  ForeignCompilation
  InvalidReadLimits
  ConstructionRefused
  MissingCheckedOccurrence
  UnsupportedCarrierContract
  Encoding
  Evidence(@publication.RunEvidenceValueIssue)
  Contract(@publication.PublicationContractIssue)
} derive(Eq, Debug)

///|
/// Read only the exact compiler-issued Values owner. Shape/CID admission
/// alone is not compiler provenance and cannot be substituted here.
/// The trusted read consumer must explicitly declare installed Inspect. This
/// portable issuer does not infer Host support from a schema or compilation.
pub fn client_values_static_plan_view(
  prepared : PreparedClientProgram,
  compiled : ClientValuesCompilation,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  inspect_installed? : Bool = false,
) -> Result[String, ClientInteractivePlanIssue] {
  if !physical_equal(compiled.owner, prepared) {
    return Err(ForeignCompilation)
  }
  issue_client_static_plan_view(
    prepared,
    compiled.compiled_plan,
    max_bytes,
    max_nodes,
    max_depth,
    inspect_installed,
  )
}

///|
/// Logical occurrences come from the original checked Stage IR, not the
/// physical task split, generated backend nodes or caller-supplied JSON.
pub fn client_task_static_plan_view(
  prepared : PreparedClientProgram,
  compiled : ClientTaskCompilation,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  inspect_installed? : Bool = false,
) -> Result[String, ClientInteractivePlanIssue] {
  if !physical_equal(compiled.owner, prepared) {
    return Err(ForeignCompilation)
  }
  issue_client_static_plan_view(
    prepared,
    compiled.compiled_plan,
    max_bytes,
    max_nodes,
    max_depth,
    inspect_installed,
  )
}

///|
fn interactive_quote(value : String, max_bytes : Int) -> String raise {
  let writer = @encode.writer(max_bytes, 1, 1)
  @encode.string_value(writer, value)
  @encode.finish(writer)
}

///|
fn interactive_key(
  name : String,
  body : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@publication.RunEvidenceValue, ClientInteractivePlanIssue] {
  @publication.seal_run_evidence_value(
    name, body, max_bytes, max_nodes, max_depth,
  ).map_err(issue => Evidence(issue))
}

///|
fn interactive_port(
  plan_cid : String,
  step_id : String,
  role : String,
  ordinal : Int,
  carrier : @carrier.Carrier,
  source : String?,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[(String, String), ClientInteractivePlanIssue] {
  guard client_task_carrier_contract(carrier, max_bytes, max_nodes, max_depth)
    is Some((kind, contract)) else {
    return Err(UnsupportedCarrierContract)
  }
  let key = match
    interactive_key(
      "logical_port_key",
      "{\"version\":\"actql-logical-port-key/0.1\",\"compiled_plan_cid\":\"" +
      plan_cid +
      "\",\"step_id\":\"" +
      step_id +
      "\",\"role\":\"" +
      role +
      "\",\"port_ordinal\":" +
      ordinal.to_string() +
      "}",
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let port_id = @publication.run_evidence_value_identity(key)
  let locator = source.unwrap_or_else(() => {
    "{\"kind\":\"logical_output\",\"step_id\":\"" +
    step_id +
    "\",\"output_port_id\":\"" +
    port_id +
    "\"}"
  })
  Ok(
    (
      port_id,
      "{\"port_id\":\"" +
      port_id +
      "\",\"role\":\"" +
      role +
      "\",\"port_ordinal\":" +
      ordinal.to_string() +
      ",\"carrier\":\"" +
      kind +
      "\",\"carrier_contract_cid\":\"" +
      contract +
      "\",\"source\":" +
      locator +
      ",\"can_sample\":false,\"sample_reason\":\"not_installed\"}",
    ),
  )
}

///|
fn interactive_stage_input(stage : Int, input : Int) -> String {
  "{\"kind\":\"stage_input\",\"stage_ordinal\":" +
  stage.to_string() +
  ",\"input_port_ordinal\":" +
  input.to_string() +
  "}"
}

///|
fn issue_client_static_plan_view(
  prepared : PreparedClientProgram,
  plan : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  inspect_installed : Bool,
) -> Result[String, ClientInteractivePlanIssue] {
  if max_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidReadLimits)
  }
  let checked = @strategy.graph_program(prepared.graph)
  let plan_cid = @publication.publication_contract_identity(plan)
  let steps : Array[String] = []
  let step_ids : Map[String, Unit] = Map([])
  let port_ids : Map[String, Unit] = Map([])
  let mut remaining = max_nodes
  for stage in 0..<@checked.unit_count(checked) {
    guard @checked.unit_pipeline(checked, stage) is Some(pipeline) else {
      return Err(MissingCheckedOccurrence)
    }
    let count = @pipeline.step_count(pipeline)
    let producers : Array[(String, String)] = []
    let occurrences = if count == 0 { 1 } else { count }
    for occurrence in 0..<occurrences {
      if remaining < 1 {
        return Err(InvalidReadLimits)
      }
      remaining -= 1
      let input_only = count == 0
      let coordinate = if input_only {
        if @pipeline.input_count(pipeline) != 1 ||
          @pipeline.current(pipeline) != Some(@pipeline.Input(0)) {
          return Err(MissingCheckedOccurrence)
        }
        "{\"kind\":\"input_output\",\"input_port_ordinal\":0}"
      } else {
        "{\"kind\":\"operation\",\"operation_ordinal\":" +
        occurrence.to_string() +
        "}"
      }
      let key = match
        interactive_key(
          "logical_step_key",
          "{\"version\":\"actql-logical-step-key/0.1\",\"compiled_plan_cid\":\"" +
          plan_cid +
          "\",\"stage_ordinal\":" +
          stage.to_string() +
          ",\"occurrence\":" +
          coordinate +
          "}",
          max_bytes,
          max_nodes,
          max_depth,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let step_id = @publication.run_evidence_value_identity(key)
      if step_ids.contains(step_id) {
        return Err(Evidence(RunEvidenceReferenceMismatch("logical_map.step")))
      }
      step_ids[step_id] = ()
      let ports : Array[String] = []
      let mut names = "[]"
      let mut operator = "null"
      let output = if input_only {
        guard @pipeline.input_at(pipeline, 0) is Some((_, carrier)) &&
          @carrier.kind(carrier) == RelationKind else {
          return Err(UnsupportedCarrierContract)
        }
        let (input_id, wire) = match
          interactive_port(
            plan_cid,
            step_id,
            "input",
            0,
            carrier,
            Some(interactive_stage_input(stage, 0)),
            max_bytes,
            max_nodes,
            max_depth,
          ) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        if port_ids.contains(input_id) {
          return Err(Evidence(RunEvidenceReferenceMismatch("logical_map.port")))
        }
        port_ids[input_id] = ()
        ports.push(wire)
        carrier
      } else {
        guard @pipeline.step_at(pipeline, occurrence) is Some(step) else {
          return Err(MissingCheckedOccurrence)
        }
        let fields = @decode.object_field_names(step.source).to_option()
        guard fields is Some(fields) else {
          return Err(MissingCheckedOccurrence)
        }
        // The ordinary checker has already closed and admitted this exact
        // operation. Read its retained tag; do not parse another Program.
        for field in fields {
          if field != "from" && field != "as" && field != "meta" {
            operator = interactive_quote(field, max_bytes) catch {
              _ => return Err(Encoding)
            }
          }
        }
        if step.binding_name is Some(name) {
          names = "[" +
            (interactive_quote(name, max_bytes) catch {
              _ => return Err(Encoding)
            }) +
            "]"
        }
        for input in 0..<@pipeline.input_occurrence_count(step) {
          if remaining < 1 {
            return Err(InvalidReadLimits)
          }
          remaining -= 1
          let target = @pipeline.input_occurrence_at(step, input).unwrap().target
          guard @pipeline.carrier_at(pipeline, target) is Some(carrier) else {
            return Err(MissingCheckedOccurrence)
          }
          let source = match target {
            @pipeline.Input(index) => interactive_stage_input(stage, index)
            @pipeline.Step(index) => {
              guard producers.get(index) is Some((producer, port)) else {
                return Err(MissingCheckedOccurrence)
              }
              "{\"kind\":\"logical_output\",\"step_id\":\"" +
              producer +
              "\",\"output_port_id\":\"" +
              port +
              "\"}"
            }
          }
          let (input_id, wire) = match
            interactive_port(
              plan_cid,
              step_id,
              "input",
              input,
              carrier,
              Some(source),
              max_bytes,
              max_nodes,
              max_depth,
            ) {
            Ok(value) => value
            Err(issue) => return Err(issue)
          }
          if port_ids.contains(input_id) {
            return Err(
              Evidence(RunEvidenceReferenceMismatch("logical_map.port")),
            )
          }
          port_ids[input_id] = ()
          ports.push(wire)
        }
        step.output
      }
      let (output_id, wire) = match
        interactive_port(
          plan_cid,
          step_id,
          "output",
          0,
          output,
          if input_only {
            Some(interactive_stage_input(stage, 0))
          } else {
            None
          },
          max_bytes,
          max_nodes,
          max_depth,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if port_ids.contains(output_id) {
        return Err(Evidence(RunEvidenceReferenceMismatch("logical_map.port")))
      }
      port_ids[output_id] = ()
      ports.push(wire)
      producers.push((step_id, output_id))
      steps.push(
        "{\"step_id\":\"" +
        step_id +
        "\",\"key\":" +
        @publication.run_evidence_value_json(key) +
        ",\"names\":" +
        names +
        ",\"operator\":" +
        operator +
        ",\"ports\":[" +
        ports.join(",") +
        "],\"can_stop_before\":false,\"can_stop_after\":false," +
        "\"stop_reason\":\"not_installed\"}",
      )
    }
  }
  let map = match
    interactive_key(
      "logical_map",
      "{\"version\":\"actql-logical-map/0.1\",\"compiled_plan_cid\":\"" +
      plan_cid +
      "\",\"program_definition_cid\":\"" +
      prepared_client_identity(prepared).program_definition_cid +
      "\",\"steps\":[" +
      steps.join(",") +
      "]}",
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // Each key and carrier above was just issued from this exact checked
  // occurrence and Plan. Producer references use the retained prior output;
  // uniqueness is checked in that same pass. Rechecking this fresh map through
  // the external binding reader would parse and hash those unchanged keys
  // again. External maps and control admission retain that full reader.
  let body = "{\"version\":\"actql-plan-view/0.1\",\"compiled_plan_cid\":\"" +
    plan_cid +
    "\",\"logical_map\":" +
    @publication.run_evidence_value_json(map) +
    ",\"observation\":\"static\",\"provider_io\":0,\"quantities\":[" +
    "{\"kind\":\"unknown\",\"unit\":\"work\",\"reason\":\"not_observed\"}]," +
    "\"capabilities\":{\"static_plan\":true,\"inspect\":" +
    inspect_installed.to_string() +
    "," +
    "\"durable_control\":false,\"sample_capture\":[]," +
    "\"full_intermediate_retention\":[],\"cost_guard\":false," +
    "\"execution_batch\":false,\"policy_revision_cid\":\"" +
    @checked.checked_local_policy_cid(checked) +
    "\"}}"
  guard parse_plan_identity_value(body, max_bytes, max_nodes, max_depth)
    is Some(value) else {
    return Err(Encoding)
  }
  let wire = @canonical.stringify_value(value, max_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  match
    @publication.parse_interactive_run_control_shape(
      "plan_view", wire, max_bytes, max_nodes, max_depth,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Contract(issue))
  }
  Ok(wire)
}
