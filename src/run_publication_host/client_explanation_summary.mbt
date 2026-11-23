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
  let seen : Map[String, Unit] = Map([])
  let mut count = 0
  visit_explanation_narrative_array(value, text.budget, (index, item) => {
    if explanation_narrative_string(item, "kind") == "source" {
      indices.push(index)
      let view = explanation_narrative_field(item, "source_view")
      let connector = explanation_narrative_string(view, "connector")
      if !seen.contains(connector) {
        seen[connector] = ()
        explanation_summary_append_separator(text, count)
        if count == 0 {
          text.say("Read from ", "")
        }
        text.quote(connector)
        count += 1
      }
    }
  })
  if count > 0 {
    text.say("", " から読み取る")
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
    ask.say("", " に問い合わせる")
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
          "join" => joins.push(id)
          "filter" => filters.push(id)
          _ => ()
        }
      }
    },
  )
  if !joins.is_empty() {
    join.say("Join inputs", "入力を結合する")
  }
  if !filters.is_empty() {
    filter.say("Filter rows", "行を絞り込む")
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
