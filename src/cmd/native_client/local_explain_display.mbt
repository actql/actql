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
fn local_explain_computation(
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
fn local_explain_effects(
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
  for member in local_explain_items(local_explain_field(effects, "members")) {
    output.append(
      "\nEffect " +
      local_explain_literal(local_explain_field(member, "effect_id")) +
      " " +
      local_explain_literal(local_explain_field(member, "effect_kind")) +
      "\n  Contract: " +
      local_explain_literal(local_explain_field(member, "contract")) +
      "\n  Input: " +
      local_explain_literal(local_explain_field(member, "input")) +
      "\n  Minimum approval: " +
      local_explain_literal(local_explain_field(member, "minimum_approval")) +
      "\n  Failure policy: " +
      local_explain_literal(local_explain_field(member, "failure_policy")) +
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
    output.append(
      "Check environment: " +
      local_explain_literal(local_explain_field(value, "check_environment_cid")) +
      "\n",
    )
    local_explain_field(local_explain_field(value, "computation"), "plan_view")
  } else {
    value
  }
  local_explain_computation(output, plan)
  if kind == "effectful_static_plan_view" {
    local_explain_effects(output, value)
  }
  output.text.to_string()
}
