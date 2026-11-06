///|
// Private presentation buffer only. The original Plan/envelope remains the
// source of every displayed fact; this is neither a Plan nor an admission.
priv struct LocalExplainText {
  text : StringBuilder
  mut remaining : Int
}

///|
fn LocalExplainText::append(
  self : LocalExplainText,
  text : String,
) -> Unit raise ClientStop {
  let bytes = @utf8.encode(text).length()
  if bytes > self.remaining {
    stop("LocalExplainDisplayLimit")
  }
  self.remaining -= bytes
  self.text.write_string(text)
}

///|
fn local_explain_field(value : Json, name : String) -> Json raise ClientStop {
  guard value is Object(fields) && fields.get(name) is Some(field) else {
    stop("LocalExplainDisplayUnavailable")
  }
  field
}

///|
fn local_explain_items(value : Json) -> Array[Json] raise ClientStop {
  guard value is Array(items) else { stop("LocalExplainDisplayUnavailable") }
  items
}

///|
// JSON quoting keeps authored names/targets and all control characters inert
// in a terminal. A presentation label is never used as a resource selector.
fn local_explain_literal(value : Json) -> String raise ClientStop {
  encode_request_json(value, 65536)
}

///|
fn local_explain_computation_verbose(
  output : LocalExplainText,
  plan : Json,
) -> Unit raise ClientStop {
  let map = local_explain_field(plan, "logical_map")
  for
    (label, field) in [
      ("Program", "program_definition_cid"),
      ("Logical map", "self_cid"),
    ] {
    output.append(
      label +
      ": " +
      local_explain_literal(local_explain_field(map, field)) +
      "\n",
    )
  }
  output.append(
    "Compiled computation: " +
    local_explain_literal(local_explain_field(plan, "compiled_plan_cid")) +
    "\n",
  )
  output.append(
    "Site / Engine / pushdown: not represented in this static projection\n",
  )
  output.append(
    "Quantities: " +
    local_explain_literal(local_explain_field(plan, "quantities")) +
    "\n",
  )
  let steps = local_explain_items(local_explain_field(map, "steps"))
  output.append("\nLogical occurrences: " + steps.length().to_string() + "\n")
  for step in steps {
    output.append(
      "\nStep " +
      local_explain_literal(local_explain_field(step, "step_id")) +
      "\n  Operator: " +
      local_explain_literal(local_explain_field(step, "operator")) +
      "\n  Names: " +
      local_explain_literal(local_explain_field(step, "names")) +
      "\n",
    )
    // Explicit original locators, never adjacency inferred from array order.
    for port in local_explain_items(local_explain_field(step, "ports")) {
      output.append(
        "  Port " +
        local_explain_literal(local_explain_field(port, "port_id")) +
        " " +
        local_explain_literal(local_explain_field(port, "role")) +
        " " +
        local_explain_literal(local_explain_field(port, "carrier")) +
        "\n    Source: " +
        local_explain_literal(local_explain_field(port, "source")) +
        "\n",
      )
    }
  }
}

///|
fn local_explain_effects_verbose(
  output : LocalExplainText,
  envelope : Json,
) -> Unit raise ClientStop {
  let effects = local_explain_field(envelope, "effect_set")
  output.append(
    "\nDeclared Effects; computation CID above covers only its computation component.\n" +
    "Unit: " +
    local_explain_literal(local_explain_field(effects, "unit_id")) +
    "\n",
  )
  for entry in local_explain_items(local_explain_field(effects, "members")) {
    output.append(
      "\nEffect " +
      local_explain_literal(local_explain_field(entry, "effect_id")) +
      " " +
      local_explain_literal(local_explain_field(entry, "effect_kind")) +
      "\n  Contract: " +
      local_explain_literal(local_explain_field(entry, "contract")) +
      "\n  Input: " +
      local_explain_literal(local_explain_field(entry, "input")) +
      "\n  Minimum approval: " +
      local_explain_literal(local_explain_field(entry, "minimum_approval")) +
      "\n  Failure policy: " +
      local_explain_literal(local_explain_field(entry, "failure_policy")) +
      "\n",
    )
  }
  output.append(
    "\nA contract minimum is not current permission or an approval decision.\n",
  )
  let observations = local_explain_field(envelope, "observations")
  for
    (label, field) in [
      ("Permission", "permission"),
      ("Gate", "gate"),
      ("Approval", "approval"),
      ("Resolved targets", "resolved_targets"),
      ("Changed values", "changed_values"),
      ("Preview", "preview"),
    ] {
    output.append(
      label +
      ": " +
      local_explain_literal(local_explain_field(observations, field)) +
      "\n",
    )
  }
}

///|
fn local_explain_reply(
  wire : String,
  json : Bool,
  max_bytes? : Int = 65536,
  verbose? : Bool = false,
) -> String raise ClientStop {
  // JSON is the exact compiler-issued response, not a re-encoded display.
  if json {
    return wire
  }
  let cursor = local_input_cursor(wire)
  let fields = @decode.open_object(cursor).unwrap_or_else(() => {
    stop("LocalExplainDisplayUnavailable")
  })
  let version = @decode.text(
    @decode.required(fields, "version").unwrap_or_else(() => {
      stop("LocalExplainDisplayUnavailable")
    }),
  ).unwrap_or_else(() => stop("LocalExplainDisplayUnavailable"))
  let kind = match version {
    "actql-plan-view/0.1" => "plan_view"
    "actql-effectful-static-plan-view/0.1" => "effectful_static_plan_view"
    _ => stop("LocalExplainDisplayUnavailable")
  }
  // Reuse the same bounded closed reader. Display shape does not confer
  // compiler provenance, current authority, Preview or runtime observation.
  ignore(
    @publication.parse_interactive_run_control_shape(
      kind, wire, 65536, 8192, 64,
    ).unwrap_or_else(() => stop("LocalExplainDisplayUnavailable")),
  )
  let value = @json.parse(wire) catch {
    _ => stop("LocalExplainDisplayUnavailable")
  }
  let output = { text: StringBuilder(), remaining: max_bytes, }
  output.append(
    "ActQL EXPLAIN · static\nRun: not started by EXPLAIN\nProvider I/O: 0\n",
  )
  let plan = if kind == "effectful_static_plan_view" {
    if verbose {
      output.append(
        "Check environment: " +
        local_explain_literal(
          local_explain_field(value, "check_environment_cid"),
        ) +
        "\n",
      )
    }
    local_explain_field(local_explain_field(value, "computation"), "plan_view")
  } else {
    value
  }
  local_explain_computation(output, plan, verbose~)
  if kind == "effectful_static_plan_view" {
    if verbose {
      local_explain_effects_verbose(output, value)
    } else {
      local_explain_effects_summary(output, value)
    }
  }
  output.text.to_string()
}

///|
fn local_explain_ordinal(value : Json) -> String raise ClientStop {
  guard value is Number(number, ..) else {
    stop("LocalExplainDisplayUnavailable")
  }
  // Display ordinals are one-based; the original zero-based wire is unchanged.
  (number.to_int64() + 1L).to_string()
}

///|
fn local_explain_source(
  source : Json,
  outputs : Map[String, String],
) -> String raise ClientStop {
  match local_explain_field(source, "kind") {
    String("stage_input") =>
      "stage " +
      local_explain_ordinal(local_explain_field(source, "stage_ordinal")) +
      " input " +
      local_explain_ordinal(local_explain_field(source, "input_port_ordinal"))
    String("logical_output") => {
      let key = local_explain_literal(local_explain_field(source, "step_id")) +
        "/" +
        local_explain_literal(local_explain_field(source, "output_port_id"))
      outputs
      .get(key)
      .unwrap_or_else(() => stop("LocalExplainDisplayUnavailable"))
    }
    _ => stop("LocalExplainDisplayUnavailable")
  }
}

///|
fn local_explain_computation(
  output : LocalExplainText,
  plan : Json,
  verbose? : Bool = false,
) -> Unit raise ClientStop {
  if verbose {
    local_explain_computation_verbose(output, plan)
    return
  }
  let steps = local_explain_items(
    local_explain_field(local_explain_field(plan, "logical_map"), "steps"),
  )
  let outputs : Map[String, String] = Map([])
  // Resolve only explicit original step AND output-port locators. Numbering
  // is presentation, not execution order, adjacency, a selector or an identity.
  for index, step in steps {
    for port in local_explain_items(local_explain_field(step, "ports")) {
      if local_explain_field(port, "role") == Json::string("output") {
        let key = local_explain_literal(local_explain_field(step, "step_id")) +
          "/" +
          local_explain_literal(local_explain_field(port, "port_id"))
        if outputs.contains(key) {
          stop("LocalExplainDisplayUnavailable")
        }
        outputs[key] = "step " +
          (index + 1).to_string() +
          " output " +
          local_explain_ordinal(local_explain_field(port, "port_ordinal"))
      }
    }
  }
  output.append("\nPlan: " + steps.length().to_string() + " logical steps\n")
  for index, step in steps {
    let operator = match local_explain_field(step, "operator") {
      String(name) => name.replace(old="_", new=" ")
      Null => "stage input"
      _ => stop("LocalExplainDisplayUnavailable")
    }
    output.append("\n" + (index + 1).to_string() + ". " + operator)
    let names = local_explain_items(local_explain_field(step, "names"))
    if !names.is_empty() {
      output.append(
        " · " + names.map(name => local_explain_literal(name)).join(", "),
      )
    }
    output.append("\n")
    for port in local_explain_items(local_explain_field(step, "ports")) {
      let role = match local_explain_field(port, "role") {
        String("input") => "Input"
        String("output") => "Output"
        _ => stop("LocalExplainDisplayUnavailable")
      }
      let carrier = match local_explain_field(port, "carrier") {
        String(name) => name
        _ => stop("LocalExplainDisplayUnavailable")
      }
      output.append(
        "   " +
        role +
        " " +
        local_explain_ordinal(local_explain_field(port, "port_ordinal")) +
        ": " +
        carrier,
      )
      let source = local_explain_field(port, "source")
      let own_output = local_explain_field(source, "kind") ==
        Json::string("logical_output") &&
        local_explain_field(source, "step_id") ==
        local_explain_field(step, "step_id") &&
        local_explain_field(source, "output_port_id") ==
        local_explain_field(port, "port_id")
      if role == "Input" || !own_output {
        output.append(" from " + local_explain_source(source, outputs))
      }
      output.append("\n")
    }
  }
  output.append(
    "\nSite / Engine / pushdown: not represented in this static projection\n",
  )
  for quantity in local_explain_items(local_explain_field(plan, "quantities")) {
    output.append(
      "Quantity " +
      local_explain_literal(local_explain_field(quantity, "unit")) +
      ": ",
    )
    if local_explain_field(quantity, "kind") == Json::string("unknown") {
      output.append(
        "unknown (" +
        local_explain_literal(local_explain_field(quantity, "reason")) +
        ")\n",
      )
    } else {
      output.append(
        local_explain_literal(local_explain_field(quantity, "value")) +
        " (" +
        local_explain_literal(local_explain_field(quantity, "kind")) +
        ")\n",
      )
    }
  }
  output.append(
    "Step numbers are display labels, not execution order.\nUse --verbose for full identities and ports, or --json for machine-readable output.\n",
  )
}

///|
fn local_explain_effects_summary(
  output : LocalExplainText,
  envelope : Json,
) -> Unit raise ClientStop {
  let effects = local_explain_field(envelope, "effect_set")
  let entries = local_explain_items(local_explain_field(effects, "members"))
  output.append(
    "\nDeclared Effects: " +
    entries.length().to_string() +
    "\nUnit: " +
    local_explain_literal(local_explain_field(effects, "unit_id")) +
    "\n",
  )
  for entry in entries {
    output.append(
      "\nEffect " +
      local_explain_literal(local_explain_field(entry, "effect_id")) +
      " · " +
      local_explain_literal(local_explain_field(entry, "effect_kind")) +
      "\n",
    )
    let contract = local_explain_field(entry, "contract")
    let target_field = if local_explain_field(contract, "kind") ==
      Json::string("mapping") {
      "declared_target"
    } else {
      "resource_kind"
    }
    output.append(
      "  Declared target: " +
      local_explain_literal(local_explain_field(contract, target_field)) +
      "\n  Contract: " +
      local_explain_literal(local_explain_field(contract, "reference")) +
      "\n",
    )
    let input = local_explain_field(entry, "input")
    let input_kind = local_explain_field(input, "kind")
    output.append("  Input: " + local_explain_literal(input_kind))
    if input_kind == Json::string("result") {
      output.append(
        " " + local_explain_literal(local_explain_field(input, "result_name")),
      )
    } else if input_kind == Json::string("table") {
      output.append(
        " " + local_explain_literal(local_explain_field(input, "table_name")),
      )
    }
    let minimum = local_explain_field(entry, "minimum_approval")
    let approval = if local_explain_field(minimum, "kind") ==
      Json::string("contract_minimum") {
      local_explain_literal(local_explain_field(minimum, "value")) +
      " (contract minimum)"
    } else {
      "not represented"
    }
    output.append(
      "\n  Minimum approval: " +
      approval +
      "\n  Failure policy: " +
      local_explain_literal(local_explain_field(entry, "failure_policy")) +
      "\n",
    )
  }
  output.append(
    "\nA contract minimum is not current permission or an approval decision.\n",
  )
  let observations = local_explain_field(envelope, "observations")
  for
    (label, field) in [
      ("Permission", "permission"),
      ("Gate", "gate"),
      ("Approval", "approval"),
      ("Resolved targets", "resolved_targets"),
      ("Changed values", "changed_values"),
      ("Preview", "preview"),
    ] {
    let observation = local_explain_field(observations, field)
    output.append(
      label +
      ": " +
      local_explain_literal(local_explain_field(observation, "state")) +
      " (" +
      local_explain_literal(local_explain_field(observation, "reason")) +
      ")\n",
    )
  }
}
