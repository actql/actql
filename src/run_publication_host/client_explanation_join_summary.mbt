///|
priv struct ExplanationJoinTopology {
  steps : Map[String, @canonical.CanonicalValue]
  ports : Map[String, (String, @canonical.CanonicalValue)]
  sources : Map[String, @canonical.CanonicalValue]
  stage_producers : Map[String, String]
}

///|
priv enum ExplanationJoinInput {
  CheckedSource(@canonical.CanonicalValue)
  JoinedRows
  ModelOutput
}

///|
fn explanation_join_topology(
  facts : @canonical.CanonicalValue,
  context : @canonical.CanonicalValue?,
  logical_map : @canonical.CanonicalValue,
  stage_result_links : @canonical.CanonicalValue?,
  budget : ExplanationNarrativeBudget,
) -> ExplanationJoinTopology raise ClientExplanationNarrativeIssue {
  if explanation_narrative_string(facts, "logical_map_cid") !=
    explanation_narrative_string(logical_map, "self_cid") ||
    explanation_narrative_string(facts, "compiled_plan_cid") !=
    explanation_narrative_string(logical_map, "compiled_plan_cid") ||
    explanation_narrative_string(facts, "program_definition_cid") !=
    explanation_narrative_string(logical_map, "program_definition_cid") {
    raise InvalidExplanation
  }
  let steps : Map[String, @canonical.CanonicalValue] = Map([])
  let ports : Map[String, (String, @canonical.CanonicalValue)] = Map([])
  let sources : Map[String, @canonical.CanonicalValue] = Map([])
  let stage_producers : Map[String, String] = Map([])
  visit_explanation_narrative_array(
    explanation_narrative_field(logical_map, "steps"),
    budget,
    (_, step) => {
      let id = explanation_narrative_string(step, "step_id")
      if steps.contains(id) {
        raise InvalidExplanation
      }
      steps[id] = step
      visit_explanation_narrative_array(
        explanation_narrative_field(step, "ports"),
        budget,
        (_, port) => {
          let port_id = explanation_narrative_string(port, "port_id")
          if ports.contains(port_id) {
            raise InvalidExplanation
          }
          ports[port_id] = (id, port)
        },
      )
    },
  )
  if context is Some(context) && stage_result_links is Some(_) {
    visit_explanation_narrative_array(
      explanation_narrative_field(context, "items"),
      budget,
      (_, item) => {
        if explanation_narrative_string(item, "kind") == "source" {
          let locator = explanation_narrative_field(item, "stage_input")
          guard explanation_narrative_string(locator, "kind") == "stage_input" &&
            explanation_narrative_field(locator, "stage_ordinal")
            is @canonical.Number(source_stage) &&
            explanation_narrative_field(locator, "input_port_ordinal")
            is @canonical.Number(source_input) else {
            raise InvalidExplanation
          }
          let view = explanation_narrative_field(item, "source_view")
          visit_explanation_narrative_array(
            explanation_narrative_field(item, "consuming_ports"),
            budget,
            (_, consumer) => {
              let port_id = explanation_narrative_string(consumer, "port_id")
              let step_id = explanation_narrative_string(consumer, "step_id")
              guard ports.get(port_id) is Some((owner, port)) &&
                owner == step_id &&
                !sources.contains(port_id) &&
                explanation_narrative_string(port, "role") == "input" &&
                @canonical.object_field(port, "source") is Some(original) &&
                explanation_narrative_string(original, "kind") == "stage_input" &&
                explanation_narrative_field(original, "stage_ordinal")
                is @canonical.Number(stage) &&
                explanation_narrative_field(original, "input_port_ordinal")
                is @canonical.Number(input) &&
                stage == source_stage &&
                input == source_input else {
                raise InvalidExplanation
              }
              sources[port_id] = view
            },
          )
        }
      },
    )
  }
  if stage_result_links is Some(links) {
    visit_explanation_narrative_array(links, budget, (_, link) => {
      let from = explanation_narrative_field(link, "producer")
      let to = explanation_narrative_field(link, "consumer")
      let producer_id = explanation_narrative_string(from, "step_id")
      let input_id = explanation_narrative_string(to, "port_id")
      guard ports.get(explanation_narrative_string(from, "port_id"))
        is Some((producer, output)) &&
        ports.get(input_id) is Some((consumer, input)) &&
        producer == producer_id &&
        consumer == explanation_narrative_string(to, "step_id") &&
        producer != consumer &&
        !stage_producers.contains(input_id) &&
        explanation_narrative_string(output, "role") == "output" &&
        explanation_narrative_string(input, "role") == "input" &&
        @canonical.object_field(input, "source") is Some(locator) &&
        explanation_narrative_string(locator, "kind") == "stage_input" &&
        explanation_narrative_field(locator, "stage_ordinal")
        is @canonical.Number(locator_stage) &&
        explanation_narrative_string(input, "carrier") ==
        explanation_narrative_string(output, "carrier") &&
        steps.get(producer) is Some(prior) &&
        steps.get(consumer) is Some(next) &&
        explanation_narrative_field(
          explanation_narrative_field(prior, "key"),
          "stage_ordinal",
        )
        is @canonical.Number(from_stage) &&
        explanation_narrative_field(
          explanation_narrative_field(next, "key"),
          "stage_ordinal",
        )
        is @canonical.Number(to_stage) &&
        locator_stage == to_stage &&
        from_stage < to_stage &&
        (
          explanation_narrative_field(link, "result_projection")
          is @canonical.Bool(true) ||
          explanation_narrative_string(input, "carrier_contract_cid") ==
          explanation_narrative_string(output, "carrier_contract_cid")
        ) else {
        raise InvalidExplanation
      }
      stage_producers[input_id] = producer_id
    })
  }
  { steps, ports, sources, stage_producers, }
}

///|
fn explanation_join_input(
  topology : ExplanationJoinTopology,
  step_id : String,
  port_id : String,
  ordinal : Int,
  budget : ExplanationNarrativeBudget,
) -> ExplanationJoinInput? raise ClientExplanationNarrativeIssue {
  budget.visit()
  guard topology.ports.get(port_id) is Some((owner, port)) &&
    owner == step_id &&
    explanation_narrative_string(port, "role") == "input" &&
    explanation_narrative_field(port, "port_ordinal")
    is @canonical.Number(original_ordinal) &&
    original_ordinal == ordinal.to_double() else {
    raise InvalidExplanation
  }
  if !topology.stage_producers.contains(port_id) &&
    topology.sources.get(port_id) is Some(view) {
    return Some(CheckedSource(view))
  }
  let locator = explanation_narrative_field(port, "source")
  let producer_id = match explanation_narrative_string(locator, "kind") {
    "stage_input" => topology.stage_producers.get(port_id)
    "logical_output" => {
      let step = explanation_narrative_string(locator, "step_id")
      let output_id = explanation_narrative_string(locator, "output_port_id")
      guard topology.ports.get(output_id) is Some((owner, output)) &&
        owner == step &&
        explanation_narrative_string(output, "role") == "output" &&
        explanation_narrative_string(port, "carrier_contract_cid") ==
        explanation_narrative_string(output, "carrier_contract_cid") else {
        raise InvalidExplanation
      }
      Some(step)
    }
    _ => None
  }
  guard producer_id is Some(id) && topology.steps.get(id) is Some(producer) else {
    return None
  }
  match @canonical.object_field(producer, "operator") {
    Some(@canonical.String("join")) => return Some(JoinedRows)
    Some(@canonical.String("infer")) => return Some(ModelOutput)
    Some(@canonical.Null)
    | Some(@canonical.String("select" | "rename" | "drop" | "filter")) => ()
    _ => return None
  }
  // An input or recognized one-input projection can name its verified
  // upstream Source. Its emitted rows are still the projection's output.
  let mut seen = 0
  let mut source = None
  visit_explanation_narrative_array(
    explanation_narrative_field(producer, "ports"),
    budget,
    (_, prior) => {
      if explanation_narrative_string(prior, "role") == "input" {
        seen += 1
        source = topology.sources.get(
          explanation_narrative_string(prior, "port_id"),
        )
      }
    },
  )
  if seen == 1 {
    source.map(view => CheckedSource(view))
  } else {
    None
  }
}

///|
fn explain_join_input(
  input : ExplanationJoinInput?,
  text : ExplanationNarrativeText,
) -> Unit raise ClientExplanationNarrativeIssue {
  match input {
    Some(CheckedSource(view)) => {
      let connector = explanation_narrative_string(view, "connector")
      let resource = explanation_narrative_string(view, "resource")
      match text.budget.language {
        English => {
          text.quote(resource)
          text.append(" from ")
          text.quote(connector)
        }
        Japanese => {
          text.quote(connector)
          text.append(" の ")
          text.quote(resource)
        }
      }
    }
    Some(JoinedRows) => text.say("the joined rows", "前の結合結果")
    Some(ModelOutput) => text.say("the Model output", "モデル出力")
    None =>
      text.say(
        "an input with no projected origin", "元の参照が未提供の入力",
      )
  }
}

///|
fn explain_summary_join(
  fact : @canonical.CanonicalValue,
  topology : ExplanationJoinTopology?,
  text : ExplanationNarrativeText,
) -> Unit raise ClientExplanationNarrativeIssue {
  let meaning = explanation_narrative_field(fact, "meaning")
  guard explanation_narrative_string(meaning, "kind") == "join" else {
    text.say(
      "Checked join (keys and input origins are unavailable)", "確認済みの結合（キーと入力の参照は未提供）",
    )
    return
  }
  let step = explanation_narrative_string(fact, "step_id")
  let (left, right) = match
    (topology, explanation_narrative_field(fact, "input_ports")) {
    (Some(topology), @canonical.Array(inputs)) if @canonical.array_count(inputs) ==
      2 => {
      guard topology.steps.get(step) is Some(original) &&
        explanation_narrative_string(original, "operator") == "join" else {
        raise InvalidExplanation
      }
      fn read(
        index : Int,
      ) -> ExplanationJoinInput? raise ClientExplanationNarrativeIssue {
        guard @canonical.array_at(inputs, index)
          is Some(@canonical.String(port)) else {
          raise InvalidExplanation
        }
        explanation_join_input(topology, step, port, index, text.budget)
      }
      (read(0), read(1))
    }
    _ => (None, None)
  }
  let kind = explanation_narrative_string(meaning, "join_kind")
  text.say(
    match kind {
      "inner" => "Match"
      "left" => "Left join"
      "right" => "Right join"
      "full" => "Full join"
      "semi" => "Semi join"
      "anti" => "Anti join"
      _ => raise InvalidExplanation
    },
    match kind {
      "inner" => "内部結合"
      "left" => "左外部結合"
      "right" => "右外部結合"
      "full" => "完全外部結合"
      "semi" => "半結合"
      "anti" => "反結合"
      _ => raise InvalidExplanation
    },
  )
  if left is Some(_) || right is Some(_) {
    text.say(" ", "で")
    explain_join_input(left, text)
    text.say(" with ", " と ")
    explain_join_input(right, text)
    let source_keys = left is Some(JoinedRows) &&
      right is Some(CheckedSource(_))
    if source_keys {
      text.say(" on the Source keys ", " を読み取り元のキー ")
    } else {
      text.say(" on ", " を ")
    }
    explain_narrative_join_keys(
      meaning,
      text,
      compact=true,
      right_source_keys=source_keys,
    )
    text.say("", " で照合する")
  } else {
    text.say(if kind == "inner" { " rows on " } else { " on " }, "のキー ")
    explain_narrative_join_keys(meaning, text, compact=true)
    text.say(
      " (input origins not projected)", "（入力の参照は未提供）",
    )
  }
}
