///|
/// The selected words and the corresponding entries of the admitted Context
/// or Facts, in their original order. No new program or execution identity.
pub struct ClientExplanationSummaryClause {
  kind : String
  text : String
  context_items : Array[Int]
  step_ids : Array[String]
}

///|
pub enum ClientExplanationNarrativeItem {
  ContextItem(Int)
  FactStep(Int, String)
}

///|
fn explanation_summary_append_separator(
  text : ExplanationNarrativeText,
  index : Int,
) -> Unit raise ClientExplanationNarrativeIssue {
  if index > 0 {
    text.say(", ", "、")
  }
}

///|
fn explanation_summary_sources(
  value : @canonical.CanonicalValue,
  text : ExplanationNarrativeText,
  indices : Array[Int],
) -> Unit raise ClientExplanationNarrativeIssue {
  // Keep the connector and resource distinct. Several views or inputs can
  // refer to the same pair. All original indices remain navigable.
  let seen : Map[String, Map[String, Unit]] = Map([])
  let mut count = 0
  visit_explanation_narrative_array(value, text.budget, (index, item) => {
    if explanation_narrative_string(item, "kind") == "source" {
      indices.push(index)
      let view = explanation_narrative_field(item, "source_view")
      let connector = explanation_narrative_string(view, "connector")
      let resource = explanation_narrative_string(view, "resource")
      let resources = match seen.get(connector) {
        Some(resources) => resources
        None => {
          let resources = Map([])
          seen[connector] = resources
          resources
        }
      }
      if !resources.contains(resource) {
        resources[resource] = ()
        explanation_summary_append_separator(text, count)
        if count == 0 {
          text.say("Read ", "")
        }
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
        count += 1
      }
    }
  })
  if count > 0 {
    text.say("", " を読み取る")
  }
}

///|
fn explanation_summary_target(
  target : String,
  text : ExplanationNarrativeText,
) -> Unit raise ClientExplanationNarrativeIssue {
  let prefix = "connector://"
  if target.length() <= 128 && target.has_prefix(prefix) {
    let part = target.unsafe_substring(
      start=prefix.length(),
      end=target.length(),
    )
    let pieces = part.split("/").to_array()
    if pieces.length() == 2 && !pieces[0].is_empty() && !pieces[1].is_empty() {
      match text.budget.language {
        English => {
          text.quote(pieces[1].to_owned())
          text.append(" in ")
          text.quote(pieces[0].to_owned())
        }
        Japanese => {
          text.quote(pieces[0].to_owned())
          text.append(" の ")
          text.quote(pieces[1].to_owned())
        }
      }
      return
    }
  }
  text.quote(target)
}

///|
fn explanation_summary_effects(
  item : @canonical.CanonicalValue,
  text : ExplanationNarrativeText,
) -> Unit raise ClientExplanationNarrativeIssue {
  visit_explanation_narrative_array(
    explanation_narrative_field(item, "members"),
    text.budget,
    (index, entry) => {
      if index > 0 {
        text.say(". ", "。")
      }
      let declaration = explanation_narrative_field(entry, "declaration")
      let contract = explanation_narrative_field(declaration, "contract")
      match explanation_narrative_string(contract, "kind") {
        "mapping" => {
          text.say("Plan to ", "")
          let kind = explanation_narrative_string(declaration, "effect_kind")
          match kind {
            "create" => text.say("create records in ", "")
            "update" => text.say("update ", "")
            "delete" => text.say("delete records in ", "")
            "upsert" => text.say("upsert records in ", "")
            "store" => text.say("store data in ", "")
            _ => raise InvalidExplanation
          }
          explanation_summary_target(
            explanation_narrative_string(contract, "declared_target"),
            text,
          )
          let writes = explanation_narrative_field(entry, "write_fields")
          if explanation_narrative_string(writes, "state") == "declared" &&
            @canonical.object_field(writes, "fields") is Some(fields_value) &&
            fields_value is @canonical.Array(fields) &&
            @canonical.array_count(fields) > 0 {
            visit_explanation_narrative_array(fields_value, text.budget, (
              index,
              field,
            ) => {
              if index == 0 {
                text.say(" (", " の ")
              }
              explanation_summary_append_separator(text, index)
              guard field is @canonical.String(name) else {
                raise InvalidExplanation
              }
              text.quote(name)
            })
            text.say(")", "")
          }
          match kind {
            "create" => text.say("", " にレコードを作成する計画")
            "update" => text.say("", " を更新する計画")
            "delete" => text.say("", " のレコードを削除する計画")
            "upsert" =>
              text.say(
                "", " にレコードを作成または更新する計画",
              )
            "store" => text.say("", " にデータを保存する計画")
            _ => raise InvalidExplanation
          }
        }
        "command" => {
          text.say("Plan to send command ", "コマンド ")
          text.quote(explanation_narrative_string(contract, "reference"))
          text.say("", " を送る計画")
        }
        _ => raise InvalidExplanation
      }
    },
  )
}

///|
// The complete paired presentation uses one budget with the existing
// individual descriptions. Preserve every original item and relevant Step.
fn explain_narrative_summary(
  context : @canonical.CanonicalValue?,
  facts : @canonical.CanonicalValue,
  steps : Array[String],
  logical_map : @canonical.CanonicalValue?,
  budget : ExplanationNarrativeBudget,
) -> (
  String,
  Array[ClientExplanationSummaryClause],
  Array[ClientExplanationNarrativeItem],
) raise ClientExplanationNarrativeIssue {
  let items : Array[ClientExplanationNarrativeItem] = []
  let sources : Array[Int] = []
  let models : Array[Int] = []
  let results : Array[Int] = []
  let effects : Array[Int] = []
  let joins : Array[String] = []
  let mut topology = None
  let filters : Array[String] = []
  let read : ExplanationNarrativeText = { budget, out: StringBuilder(), }
  let ask : ExplanationNarrativeText = { budget, out: StringBuilder(), }
  let output : ExplanationNarrativeText = { budget, out: StringBuilder(), }
  let effect : ExplanationNarrativeText = { budget, out: StringBuilder(), }
  let join : ExplanationNarrativeText = { budget, out: StringBuilder(), }
  let filter : ExplanationNarrativeText = { budget, out: StringBuilder(), }
  if context is Some(context) {
    let original_items = explanation_narrative_field(context, "items")
    explanation_summary_sources(original_items, read, sources)
    visit_explanation_narrative_array(original_items, budget, (index, item) => {
      items.push(ContextItem(index))
      match explanation_narrative_string(item, "kind") {
        "model_task" => {
          if models.is_empty() {
            ask.say("Ask ", "")
          }
          explanation_summary_append_separator(ask, models.length())
          ask.quote(explanation_narrative_string(item, "task_id"))
          models.push(index)
        }
        "result" => {
          if results.is_empty() {
            output.say("Return ", "")
          }
          explanation_summary_append_separator(output, results.length())
          output.quote(explanation_narrative_string(item, "name"))
          results.push(index)
        }
        "effect_set" => {
          if !effects.is_empty() {
            raise InvalidExplanation
          }
          explanation_summary_effects(item, effect)
          effects.push(index)
        }
        "source" => ()
        _ => raise InvalidExplanation
      }
    })
  }
  if !models.is_empty() {
    ask.say(" about each input row", " に入力行ごとに問い合わせる")
  }
  if !results.is_empty() {
    output.say("", " を結果として返す")
  }
  visit_explanation_narrative_array(
    explanation_narrative_field(facts, "steps"),
    budget,
    (index, fact) => {
      let id = explanation_narrative_string(fact, "step_id")
      items.push(FactStep(index, id))
      if @canonical.object_field(fact, "operator")
        is Some(@canonical.String(operator)) {
        match operator {
          "join" => {
            if joins.length() < 2 {
              if joins.is_empty() && logical_map is Some(map) {
                topology = Some(
                  explanation_join_topology(facts, context, map, budget),
                )
              }
              if !joins.is_empty() {
                join.say(". ", "。")
              }
              explain_summary_join(fact, topology, join)
            }
            joins.push(id)
          }
          "filter" => {
            if !filters.is_empty() {
              filter.say(". ", "。")
            }
            let line = steps[index]
            if line.length() <= 128 {
              filter.append(line)
            } else {
              filter.say(
                "Filter rows using the checked condition shown in Steps", "Steps に示す確認済みの条件で行を絞り込む",
              )
            }
            filters.push(id)
          }
          _ => ()
        }
      }
    },
  )
  if joins.length() > 2 {
    join.say(
      ". See the other checked join keys in Steps", "。ほかの確認済みの結合キーは Steps に表示",
    )
  }
  let clauses : Array[ClientExplanationSummaryClause] = []
  let summary : ExplanationNarrativeText = { budget, out: StringBuilder(), }
  for
    (kind, part, context_items, step_ids) in [
      ("source", read, sources, []),
      ("join", join, [], joins),
      ("model_task", ask, models, []),
      ("filter", filter, [], filters),
      ("result", output, results, []),
      ("effect", effect, effects, []),
    ] {
    if !context_items.is_empty() || !step_ids.is_empty() {
      if !clauses.is_empty() {
        summary.say(" ", "")
      }
      let text = part.out.to_string()
      summary.append(text)
      summary.say(".", "。")
      clauses.push({ kind, text, context_items, step_ids, })
    }
  }
  if clauses.is_empty() {
    summary.say(
      "Describe the checked computation.", "確認済みの処理を説明する。",
    )
  }
  (summary.out.to_string(), clauses, items)
}
