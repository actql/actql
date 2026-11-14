///|
/// Sizing DATA for the original static-plan projection, never an allocation,
/// permission or proof of physical backing. Native callers must separately
/// fund each constructor and its overlapping retained owners before issuance.
/// Extents include complete self-identity fields. Aggregate maxima may combine
/// dimensions from different occurrences and are conservative, not identities.
pub(all) struct ClientStaticPlanViewConstruction {
  step_count : Int
  input_port_count : Int
  output_port_count : Int
  max_stage_producers : Int
  max_step_ports : Int
  source_field_count : Int64
  max_source_fields : Int
  quoted_text_bytes : Int64
  max_quoted_text_bytes : Int
  ports_wire_bytes : Int64
  steps_wire_bytes : Int64
  max_step : (Int, Int, Int)
  step_key : (Int, Int, Int)
  port_key : (Int, Int, Int)
  carrier_contract : (Int, Int, Int)
  max_port : (Int, Int, Int)
  map_body : (Int, Int, Int)
  map_sealed : (Int, Int, Int)
  view : (Int, Int, Int)
} derive(Eq, Debug)

///|
fn interactive_geometry_max(
  a : (Int, Int, Int),
  b : (Int, Int, Int),
) -> (Int, Int, Int) {
  (Int::max(a.0, b.0), Int::max(a.1, b.1), Int::max(a.2, b.2))
}

///|
// Every identity in this protocol is sha256 plus 64 ASCII hexadecimal digits.
// The placeholder has the same wire geometry, but is never admitted or issued.
let interactive_geometry_cid : String = "sha256:0000000000000000000000000000000000000000000000000000000000000000"

///|
fn interactive_geometry_text(
  w : @encode.Writer,
  key : String,
  value : String,
) -> Unit raise {
  @encode.key(w, key)
  @encode.string_value(w, value)
}

///|
fn interactive_geometry_number(
  w : @encode.Writer,
  key : String,
  value : Int,
) -> Unit raise {
  @encode.key(w, key)
  @encode.number_value(w, value.to_double())
}

///|
fn interactive_geometry_boolean(
  w : @encode.Writer,
  key : String,
  value : Bool,
) -> Unit raise {
  @encode.key(w, key)
  @encode.bool_value(w, value)
}

///|
fn interactive_geometry_step_key(
  w : @encode.Writer,
  stage : Int,
  occurrence : Int,
  input_only : Bool,
) -> Unit raise {
  @encode.begin_object(w)
  interactive_geometry_text(w, "version", "actql-logical-step-key/0.1")
  interactive_geometry_text(w, "compiled_plan_cid", interactive_geometry_cid)
  interactive_geometry_number(w, "stage_ordinal", stage)
  @encode.key(w, "occurrence")
  @encode.begin_object(w)
  interactive_geometry_text(
    w,
    "kind",
    if input_only {
      "input_output"
    } else {
      "operation"
    },
  )
  interactive_geometry_number(
    w,
    if input_only {
      "input_port_ordinal"
    } else {
      "operation_ordinal"
    },
    if input_only {
      0
    } else {
      occurrence
    },
  )
  @encode.end_object(w)
  interactive_geometry_text(w, "self_cid", interactive_geometry_cid)
  @encode.end_object(w)
}

///|
fn interactive_geometry_port_key(
  w : @encode.Writer,
  role : String,
  ordinal : Int,
) -> Unit raise {
  @encode.begin_object(w)
  interactive_geometry_text(w, "version", "actql-logical-port-key/0.1")
  interactive_geometry_text(w, "compiled_plan_cid", interactive_geometry_cid)
  interactive_geometry_text(w, "step_id", interactive_geometry_cid)
  interactive_geometry_text(w, "role", role)
  interactive_geometry_number(w, "port_ordinal", ordinal)
  interactive_geometry_text(w, "self_cid", interactive_geometry_cid)
  @encode.end_object(w)
}

///|
fn interactive_geometry_port(
  w : @encode.Writer,
  role : String,
  ordinal : Int,
  kind : String,
  stage : Int,
  source_input : Int?,
) -> Unit raise {
  @encode.begin_object(w)
  interactive_geometry_text(w, "port_id", interactive_geometry_cid)
  interactive_geometry_text(w, "role", role)
  interactive_geometry_number(w, "port_ordinal", ordinal)
  interactive_geometry_text(w, "carrier", kind)
  interactive_geometry_text(w, "carrier_contract_cid", interactive_geometry_cid)
  @encode.key(w, "source")
  @encode.begin_object(w)
  match source_input {
    Some(input) => {
      interactive_geometry_text(w, "kind", "stage_input")
      interactive_geometry_number(w, "stage_ordinal", stage)
      interactive_geometry_number(w, "input_port_ordinal", input)
    }
    None => {
      interactive_geometry_text(w, "kind", "logical_output")
      interactive_geometry_text(w, "step_id", interactive_geometry_cid)
      interactive_geometry_text(w, "output_port_id", interactive_geometry_cid)
    }
  }
  @encode.end_object(w)
  interactive_geometry_boolean(w, "can_sample", false)
  interactive_geometry_text(w, "sample_reason", "not_installed")
  @encode.end_object(w)
}

///|
fn interactive_geometry_map(
  w : @encode.Writer,
  steps : (Int, Int, Int),
  complete : Bool,
) -> Unit raise {
  @encode.begin_object(w)
  interactive_geometry_text(w, "version", "actql-logical-map/0.1")
  interactive_geometry_text(w, "compiled_plan_cid", interactive_geometry_cid)
  interactive_geometry_text(
    w, "program_definition_cid", interactive_geometry_cid,
  )
  @encode.key(w, "steps")
  @encode.emit_measurement(w, steps)
  if complete {
    interactive_geometry_text(w, "self_cid", interactive_geometry_cid)
  }
  @encode.end_object(w)
}

///|
fn interactive_geometry_view(
  w : @encode.Writer,
  map : (Int, Int, Int),
  inspect_installed : Bool,
) -> Unit raise {
  @encode.begin_object(w)
  interactive_geometry_text(w, "version", "actql-plan-view/0.1")
  interactive_geometry_text(w, "compiled_plan_cid", interactive_geometry_cid)
  @encode.key(w, "logical_map")
  @encode.emit_measurement(w, map)
  interactive_geometry_text(w, "observation", "static")
  interactive_geometry_number(w, "provider_io", 0)
  @encode.key(w, "quantities")
  @encode.begin_array(w)
  @encode.begin_object(w)
  interactive_geometry_text(w, "kind", "unknown")
  interactive_geometry_text(w, "unit", "work")
  interactive_geometry_text(w, "reason", "not_observed")
  @encode.end_object(w)
  @encode.end_array(w)
  @encode.key(w, "capabilities")
  @encode.begin_object(w)
  interactive_geometry_boolean(w, "static_plan", true)
  interactive_geometry_boolean(w, "inspect", inspect_installed)
  interactive_geometry_boolean(w, "durable_control", false)
  @encode.key(w, "sample_capture")
  @encode.begin_array(w)
  @encode.end_array(w)
  @encode.key(w, "full_intermediate_retention")
  @encode.begin_array(w)
  @encode.end_array(w)
  interactive_geometry_boolean(w, "cost_guard", false)
  interactive_geometry_boolean(w, "execution_batch", false)
  interactive_geometry_text(w, "policy_revision_cid", interactive_geometry_cid)
  @encode.end_object(w)
  @encode.end_object(w)
}

///|
/// Measure the SAME checked occurrences without building steps/ports arrays,
/// producer maps, keys, identities or a logical-map wire. The existing codec
/// measures escaping and node/depth limits. This does not admit a plan, replay
/// semantic checking or fund the measuring writer/carrier helper itself.
pub fn measure_client_compiled_run_static_plan_view(
  compiled : ClientCompiledRun,
  prepared : PreparedClientProgram,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  inspect_installed? : Bool = false,
  before_carrier_measurement? : ((@carrier.Carrier) -> Bool)? = None,
) -> Result[ClientStaticPlanViewConstruction, ClientCompiledRunPlanIssue] {
  if !client_compiled_run_matches(compiled, prepared) {
    return Err(ForeignCompilation)
  }
  match compiled.compilation {
    Effects(_) => return Err(UnsupportedCompilation)
    _ => ()
  }
  measure_client_static_plan_view(
    prepared,
    max_bytes,
    max_nodes,
    max_depth,
    inspect_installed,
    before_carrier_measurement~,
  ).map_err(issue => Projection(issue))
}

///|
fn measure_client_static_plan_view(
  prepared : PreparedClientProgram,
  b : Int,
  n : Int,
  d : Int,
  inspect_installed : Bool,
  before_carrier_measurement? : ((@carrier.Carrier) -> Bool)? = None,
) -> Result[ClientStaticPlanViewConstruction, ClientInteractivePlanIssue] {
  if b <= 0 || n <= 0 || d <= 0 {
    return Err(InvalidReadLimits)
  }
  let checked = @strategy.graph_program(prepared.graph)
  let mut steps = 0
  let mut inputs = 0
  let mut max_producers = 0
  let mut max_ports = 0
  let mut fields_total = 0L
  let mut fields_max = 0
  let mut quoted_total = 0L
  let mut quoted_max = 0
  let mut ports_bytes = 0L
  let mut steps_bytes = 0L
  let mut max_step = (0, 0, 0)
  let mut max_step_key = (0, 0, 0)
  let mut max_port_key = (0, 0, 0)
  let mut max_contract = (0, 0, 0)
  let mut max_port = (0, 0, 0)
  let mut remaining = n
  try {
    let all_steps = @encode.measuring_writer(b, n, d)
    @encode.begin_array(all_steps)
    for stage in 0..<@checked.unit_count(checked) {
      guard @checked.unit_pipeline(checked, stage) is Some(pipeline) else {
        return Err(MissingCheckedOccurrence)
      }
      let count = @pipeline.step_count(pipeline)
      let occurrences = if count == 0 { 1 } else { count }
      max_producers = Int::max(max_producers, occurrences)
      for occurrence in 0..<occurrences {
        if remaining < 1 {
          return Err(InvalidReadLimits)
        }
        remaining -= 1
        steps += 1
        let input_only = count == 0
        let key_writer = @encode.measuring_writer(b, n, d)
        interactive_geometry_step_key(key_writer, stage, occurrence, input_only)
        let key = @encode.finish_measurement_usage(key_writer)
        max_step_key = interactive_geometry_max(max_step_key, key)
        let step = if input_only {
          None
        } else {
          @pipeline.step_at(pipeline, occurrence)
        }
        if !input_only && step is None {
          return Err(MissingCheckedOccurrence)
        }
        let input_count = match step {
          Some(value) => @pipeline.input_occurrence_count(value)
          None => 1
        }
        if input_count >= 2147483647 {
          return Err(InvalidReadLimits)
        }
        max_ports = Int::max(max_ports, input_count + 1)
        let ports = @encode.measuring_writer(b, n, d)
        @encode.begin_array(ports)
        for ordinal in 0..<(input_count + 1) {
          let output = ordinal == input_count
          if !output {
            if !input_only {
              if remaining < 1 {
                return Err(InvalidReadLimits)
              }
              remaining -= 1
            }
            if inputs == 2147483647 {
              return Err(InvalidReadLimits)
            }
            inputs += 1
          }
          let carrier_and_source = match step {
            None => {
              if @pipeline.input_count(pipeline) != 1 ||
                @pipeline.current(pipeline) != Some(@pipeline.Input(0)) {
                return Err(MissingCheckedOccurrence)
              }
              guard @pipeline.input_at(pipeline, 0) is Some((_, carrier)) &&
                @carrier.kind(carrier) == RelationKind else {
                return Err(UnsupportedCarrierContract)
              }
              (carrier, Some(0))
            }
            Some(value) if output => (value.output, None)
            Some(value) => {
              guard @pipeline.input_occurrence_at(value, ordinal) is Some(input) &&
                @pipeline.carrier_at(pipeline, input.target) is Some(carrier) else {
                return Err(MissingCheckedOccurrence)
              }
              let source = match input.target {
                @pipeline.Input(index) => Some(index)
                @pipeline.Step(index) => {
                  if index < 0 || index >= occurrence {
                    return Err(MissingCheckedOccurrence)
                  }
                  None
                }
              }
              (carrier, source)
            }
          }
          let (carrier, source) = carrier_and_source
          // A caller may fund this original Carrier's measurement helpers in
          // its existing scope. Failure cannot fall back to unguarded emission.
          if before_carrier_measurement is Some(prepare) && !prepare(carrier) {
            return Err(ConstructionRefused)
          }
          guard measure_client_task_carrier_contract(carrier, b, n, d)
            is Some(contract) else {
            return Err(UnsupportedCarrierContract)
          }
          max_contract = interactive_geometry_max(max_contract, contract)
          let role = if output { "output" } else { "input" }
          let index = if output { 0 } else { ordinal }
          let port_key_writer = @encode.measuring_writer(b, n, d)
          interactive_geometry_port_key(port_key_writer, role, index)
          max_port_key = interactive_geometry_max(
            max_port_key,
            @encode.finish_measurement_usage(port_key_writer),
          )
          let kind = match @carrier.kind(carrier) {
            RelationKind => "relation"
            GraphKind => "graph"
            EventsKind => "events"
            VectorsKind => "vectors"
          }
          let port_writer = @encode.measuring_writer(b, n, d)
          interactive_geometry_port(
            port_writer, role, index, kind, stage, source,
          )
          let port = @encode.finish_measurement_usage(port_writer)
          if ports_bytes > 9223372036854775807L - port.0.to_int64() {
            return Err(InvalidReadLimits)
          }
          ports_bytes += port.0.to_int64()
          max_port = interactive_geometry_max(max_port, port)
          @encode.emit_measurement(ports, port)
        }
        @encode.end_array(ports)
        let port_array = @encode.finish_measurement_usage(ports)
        let names = @encode.measuring_writer(b, n, d)
        @encode.begin_array(names)
        let mut operator : String? = None
        if step is Some(value) {
          let mut index = 0
          while @decode.field_at(value.source, index) is Some((field, _)) {
            if field != "from" && field != "as" && field != "meta" {
              operator = Some(field)
              guard @encode.quoted_string_construction_extent(field)
                is Some((quoted_bytes, _)) &&
                quoted_bytes <= b.to_int64() else {
                return Err(Encoding)
              }
              let bytes = quoted_bytes.to_int()
              if quoted_total > 9223372036854775807L - bytes.to_int64() {
                return Err(InvalidReadLimits)
              }
              quoted_total += bytes.to_int64()
              quoted_max = Int::max(quoted_max, bytes)
            }
            if index == 2147483647 {
              return Err(InvalidReadLimits)
            }
            index += 1
          }
          fields_total += index.to_int64()
          fields_max = Int::max(fields_max, index)
          if value.binding_name is Some(name) {
            @encode.string_value(names, name)
            guard @encode.quoted_string_construction_extent(name)
              is Some((quoted_bytes, _)) &&
              quoted_bytes <= b.to_int64() else {
              return Err(Encoding)
            }
            let bytes = quoted_bytes.to_int()
            if quoted_total > 9223372036854775807L - bytes.to_int64() {
              return Err(InvalidReadLimits)
            }
            quoted_total += bytes.to_int64()
            quoted_max = Int::max(quoted_max, bytes)
          }
        }
        @encode.end_array(names)
        let name_array = @encode.finish_measurement_usage(names)
        let item = @encode.measuring_writer(b, n, d)
        @encode.begin_object(item)
        interactive_geometry_text(item, "step_id", interactive_geometry_cid)
        @encode.key(item, "key")
        @encode.emit_measurement(item, key)
        @encode.key(item, "names")
        @encode.emit_measurement(item, name_array)
        @encode.key(item, "operator")
        match operator {
          Some(value) => @encode.string_value(item, value)
          None => @encode.null_value(item)
        }
        @encode.key(item, "ports")
        @encode.emit_measurement(item, port_array)
        interactive_geometry_boolean(item, "can_stop_before", false)
        interactive_geometry_boolean(item, "can_stop_after", false)
        interactive_geometry_text(item, "stop_reason", "not_installed")
        @encode.end_object(item)
        let geometry = @encode.finish_measurement_usage(item)
        steps_bytes += geometry.0.to_int64()
        max_step = interactive_geometry_max(max_step, geometry)
        @encode.emit_measurement(all_steps, geometry)
      }
    }
    @encode.end_array(all_steps)
    let steps_geometry = @encode.finish_measurement_usage(all_steps)
    let map_body_writer = @encode.measuring_writer(b, n, d)
    interactive_geometry_map(map_body_writer, steps_geometry, false)
    let map_body = @encode.finish_measurement_usage(map_body_writer)
    let map_writer = @encode.measuring_writer(b, n, d)
    interactive_geometry_map(map_writer, steps_geometry, true)
    let map_sealed = @encode.finish_measurement_usage(map_writer)
    let view_writer = @encode.measuring_writer(b, n, d)
    interactive_geometry_view(view_writer, map_sealed, inspect_installed)
    let view = @encode.finish_measurement_usage(view_writer)
    Ok({
      step_count: steps,
      input_port_count: inputs,
      output_port_count: steps,
      max_stage_producers: max_producers,
      max_step_ports: max_ports,
      source_field_count: fields_total,
      max_source_fields: fields_max,
      quoted_text_bytes: quoted_total,
      max_quoted_text_bytes: quoted_max,
      ports_wire_bytes: ports_bytes,
      steps_wire_bytes: steps_bytes,
      max_step,
      step_key: max_step_key,
      port_key: max_port_key,
      carrier_contract: max_contract,
      max_port,
      map_body,
      map_sealed,
      view,
    })
  } catch {
    _ => Err(Encoding)
  }
}
