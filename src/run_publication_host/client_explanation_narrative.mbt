///|
pub(all) enum ClientExplanationLanguage {
  English
  Japanese
}

///|
pub(all) suberror ClientExplanationNarrativeIssue {
  InvalidExplanation
  ExplanationPresentationLimit
} derive(Debug)

///|
/// Text for the Context items and Fact steps, in their original order. The
/// caller retains the original identities and owns current disclosure.
pub struct ClientExplanationNarrative {
  context : Array[String]
  steps : Array[String]
}

///|
priv struct ExplanationNarrativeBudget {
  language : ClientExplanationLanguage
  mut characters : Int
  mut visits : Int
}

///|
fn ExplanationNarrativeBudget::debit(
  self : ExplanationNarrativeBudget,
  count : Int,
) -> Unit raise ClientExplanationNarrativeIssue {
  if count > self.characters {
    raise ExplanationPresentationLimit
  }
  self.characters -= count
}

///|
fn ExplanationNarrativeBudget::visit(
  self : ExplanationNarrativeBudget,
) -> Unit raise ClientExplanationNarrativeIssue {
  if self.visits == 0 {
    raise ExplanationPresentationLimit
  }
  self.visits -= 1
}

///|
priv struct ExplanationNarrativeText {
  budget : ExplanationNarrativeBudget
  out : StringBuilder
}

///|
fn ExplanationNarrativeText::append(
  self : ExplanationNarrativeText,
  value : String,
) -> Unit raise ClientExplanationNarrativeIssue {
  self.budget.debit(value.length())
  self.out.write_string(value)
}

///|
fn ExplanationNarrativeText::say(
  self : ExplanationNarrativeText,
  en : String,
  ja : String,
) -> Unit raise ClientExplanationNarrativeIssue {
  self.append(
    match self.budget.language {
      English => en
      Japanese => ja
    },
  )
}

///|
let explanation_narrative_hex : Array[Char] = [
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
]

///|
// Canonical input has valid Unicode. Debit each escape before creating it;
// control strings and repeated DAG children cannot grow unbounded buffers.
fn ExplanationNarrativeText::quote(
  self : ExplanationNarrativeText,
  value : String,
) -> Unit raise ClientExplanationNarrativeIssue {
  self.append("\"")
  for char in value {
    match char {
      '"' => self.append("\\\"")
      '\\' => self.append("\\\\")
      '\b' => self.append("\\b")
      '\t' => self.append("\\t")
      '\n' => self.append("\\n")
      '\u000c' => self.append("\\f")
      '\r' => self.append("\\r")
      _ => {
        let code = char.to_int()
        if code < 32 {
          self.budget.debit(6)
          self.out.write_string("\\u00")
          self.out.write_char(explanation_narrative_hex[code / 16])
          self.out.write_char(explanation_narrative_hex[code % 16])
        } else {
          self.budget.debit(if code > 65535 { 2 } else { 1 })
          self.out.write_char(char)
        }
      }
    }
  }
  self.append("\"")
}

///|
fn explanation_narrative_field(
  value : @canonical.CanonicalValue,
  name : String,
) -> @canonical.CanonicalValue raise ClientExplanationNarrativeIssue {
  guard @canonical.object_field(value, name) is Some(field) else {
    raise InvalidExplanation
  }
  field
}

///|
fn explanation_narrative_string(
  value : @canonical.CanonicalValue,
  name : String,
) -> String raise ClientExplanationNarrativeIssue {
  guard explanation_narrative_field(value, name) is @canonical.String(text) else {
    raise InvalidExplanation
  }
  text
}

///|
fn visit_explanation_narrative_array(
  value : @canonical.CanonicalValue,
  budget : ExplanationNarrativeBudget,
  visit : (Int, @canonical.CanonicalValue) -> Unit raise ClientExplanationNarrativeIssue,
) -> Unit raise ClientExplanationNarrativeIssue {
  guard value is @canonical.Array(items) else { raise InvalidExplanation }
  for index in 0..<@canonical.array_count(items) {
    budget.visit()
    visit(index, @canonical.array_at(items, index).unwrap())
  }
}

///|
fn explain_narrative_effect(
  item : @canonical.CanonicalValue,
  text : ExplanationNarrativeText,
) -> Unit raise ClientExplanationNarrativeIssue {
  visit_explanation_narrative_array(
    explanation_narrative_field(item, "members"),
    text.budget,
    (index, entry) => {
      if index > 0 {
        text.append("; ")
      }
      let declaration = explanation_narrative_field(entry, "declaration")
      let contract = explanation_narrative_field(declaration, "contract")
      match explanation_narrative_string(contract, "kind") {
        "mapping" => {
          text.say("Declared write ", "宣言された書き込み ")
          match explanation_narrative_string(declaration, "effect_kind") {
            "create" => text.say("create", "作成")
            "update" => text.say("update", "更新")
            "upsert" => text.say("upsert", "更新または挿入")
            "delete" => text.say("delete", "削除")
            "store" => text.say("store", "保存")
            _ => raise InvalidExplanation
          }
          text.append(" ")
          text.quote(explanation_narrative_string(contract, "declared_target"))
        }
        "command" => {
          text.say("Declared command ", "宣言されたコマンド ")
          text.quote(explanation_narrative_string(contract, "reference"))
        }
        _ => raise InvalidExplanation
      }
      let writes = explanation_narrative_field(entry, "write_fields")
      match explanation_narrative_string(writes, "state") {
        "not_projected" =>
          text.say(
            " · Fields not projected", " · 対象フィールドは未提供",
          )
        "declared" =>
          visit_explanation_narrative_array(
            explanation_narrative_field(writes, "fields"),
            text.budget,
            (index, field) => {
              if index == 0 {
                text.say(" on fields ", "、対象フィールド ")
              } else {
                text.append(", ")
              }
              guard field is @canonical.String(name) else {
                raise InvalidExplanation
              }
              text.quote(name)
            },
          )
        _ => raise InvalidExplanation
      }
      text.say(
        " · Contract minimum approval: ", " · 契約上の最低承認要件 ",
      )
      let minimum = explanation_narrative_field(declaration, "minimum_approval")
      match explanation_narrative_string(minimum, "kind") {
        "not_represented" => text.say("not represented", "未提供")
        "contract_minimum" =>
          match explanation_narrative_string(minimum, "value") {
            "required" => text.say("required", "必要")
            "none" => text.say("none", "なし")
            _ => raise InvalidExplanation
          }
        _ => raise InvalidExplanation
      }
      text.say(" · Current decision unknown", " · 現在の判断は不明")
    },
  )
}

///|
fn explain_narrative_context(
  item : @canonical.CanonicalValue,
  text : ExplanationNarrativeText,
) -> Unit raise ClientExplanationNarrativeIssue {
  match explanation_narrative_string(item, "kind") {
    "source" => {
      let view = explanation_narrative_field(item, "source_view")
      text.say("Read ", "読む ")
      text.quote(explanation_narrative_string(view, "connector"))
      text.append(".")
      text.quote(explanation_narrative_string(view, "resource"))
      text.say(" through view ", "、ビュー ")
      text.quote(explanation_narrative_string(view, "view"))
      if explanation_narrative_string(item, "link_state") == "not_projected" {
        text.say(" (consumer not projected)", "（利用先は未提供）")
      }
    }
    "model_task" => {
      text.say("Apply model task ", "モデルタスク ")
      text.quote(explanation_narrative_string(item, "task_id"))
      text.say(" to each input row", " を各入力行に適用")
    }
    "result" => {
      text.say("Declare Result ", "結果を宣言 ")
      text.quote(explanation_narrative_string(item, "name"))
    }
    "effect_set" => explain_narrative_effect(item, text)
    _ => raise InvalidExplanation
  }
}

///|
fn explain_narrative_type(
  value : @canonical.CanonicalValue,
  text : ExplanationNarrativeText,
) -> Unit raise ClientExplanationNarrativeIssue {
  text.append(explanation_narrative_string(value, "kind"))
  guard explanation_narrative_field(value, "nullable")
    is @canonical.Bool(nullable) else {
    raise InvalidExplanation
  }
  if nullable {
    text.append("?")
  }
}

///|
fn explain_narrative_operator(
  name : String,
  text : ExplanationNarrativeText,
) -> Unit raise ClientExplanationNarrativeIssue {
  match name {
    "and" => text.say("AND", "かつ")
    "or" => text.say("OR", "または")
    "not" => text.say("NOT", "否定")
    "is_null" => text.say("IS NULL", "NULLである")
    "not_null" => text.say("IS NOT NULL", "NULLではない")
    "is_distinct_from" =>
      text.say("IS DISTINCT FROM", "NULLを区別して異なる")
    "eq" => text.append("=")
    "neq" => text.append("≠")
    "lt" => text.append("<")
    "lte" => text.append("≤")
    "gt" => text.append(">")
    "gte" => text.append("≥")
    _ => raise InvalidExplanation
  }
}

///|
fn explain_narrative_node_index(
  value : @canonical.CanonicalValue,
  length : Int,
) -> Int raise ClientExplanationNarrativeIssue {
  guard value is @canonical.Number(number) &&
    number >= 0.0 &&
    number < length.to_double() &&
    number.to_int().to_double() == number else {
    raise InvalidExplanation
  }
  number.to_int()
}

///|
fn explain_narrative_predicate(
  value : @canonical.CanonicalValue,
  text : ExplanationNarrativeText,
) -> Unit raise ClientExplanationNarrativeIssue {
  if explanation_narrative_string(value, "state") == "not_projected" {
    text.say(
      "Predicate form not projected", "この述語形式の説明は未提供",
    )
    return
  }
  guard explanation_narrative_field(value, "nodes") is @canonical.Array(nodes) else {
    raise InvalidExplanation
  }
  let count = @canonical.array_count(nodes)
  if count > 1024 {
    raise ExplanationPresentationLimit
  }
  let root = explain_narrative_node_index(
    explanation_narrative_field(value, "root"),
    count,
  )
  let active = Array::make(count, false)
  let rendered : Array[String?] = Array::make(count, None)
  let heights = Array::make(count, 0)
  fn render(
    index : Int,
    depth : Int,
  ) -> String raise ClientExplanationNarrativeIssue {
    if depth > 64 {
      raise ExplanationPresentationLimit
    }
    if active[index] {
      raise InvalidExplanation
    }
    if rendered[index] is Some(cached) {
      if depth + heights[index] > 64 {
        raise ExplanationPresentationLimit
      }
      return cached
    }
    text.budget.visit()
    active[index] = true
    let mut height = 0
    let original = @canonical.array_at(nodes, index).unwrap()
    let part : ExplanationNarrativeText = {
      budget: text.budget,
      out: StringBuilder(),
    }
    match explanation_narrative_string(original, "form") {
      "literal_redacted" => {
        part.say("[redacted ", "[非開示 ")
        explain_narrative_type(
          explanation_narrative_field(original, "type"),
          part,
        )
        part.append("]")
      }
      "field" | "parameter" as form => {
        if form == "field" {
          part.append(explanation_narrative_string(original, "scope"))
          part.append(".")
          part.quote(explanation_narrative_string(original, "name"))
        } else {
          part.append("$")
          part.append(explanation_narrative_string(original, "name"))
        }
        part.append(":")
        explain_narrative_type(
          explanation_narrative_field(original, "type"),
          part,
        )
      }
      "operation" => {
        let operator = explanation_narrative_string(original, "operator")
        guard explanation_narrative_field(original, "children")
          is @canonical.Array(children) else {
          raise InvalidExplanation
        }
        let arity = @canonical.array_count(children)
        match operator {
          "not" | "is_null" | "not_null" =>
            if arity != 1 {
              raise InvalidExplanation
            }
          "and" | "or" => if arity < 2 { raise InvalidExplanation }
          _ => if arity != 2 { raise InvalidExplanation }
        }
        if operator == "not" {
          explain_narrative_operator(operator, part)
          part.append(" ")
        }
        for child_index in 0..<arity {
          text.budget.visit()
          if child_index > 0 {
            part.append(" ")
            explain_narrative_operator(operator, part)
            part.append(" ")
          }
          let child = explain_narrative_node_index(
            @canonical.array_at(children, child_index).unwrap(),
            count,
          )
          part.append("(")
          part.append(render(child, depth + 1))
          part.append(")")
          height = Int::max(height, heights[child] + 1)
        }
        if operator == "is_null" || operator == "not_null" {
          part.append(" ")
          explain_narrative_operator(operator, part)
        }
      }
      _ => raise InvalidExplanation
    }
    let result = part.out.to_string()
    rendered[index] = Some(result)
    heights[index] = height
    active[index] = false
    result
  }
  let result = render(root, 0)
  if rendered.any(value => value is None) {
    raise InvalidExplanation
  }
  text.append(result)
}

///|
fn explain_narrative_fact(
  fact : @canonical.CanonicalValue,
  text : ExplanationNarrativeText,
) -> Unit raise ClientExplanationNarrativeIssue {
  let meaning = explanation_narrative_field(fact, "meaning")
  match explanation_narrative_string(meaning, "kind") {
    "input_output" =>
      text.say(
        "Original input/output binding", "元の入力と出力の対応",
      )
    "not_projected" =>
      text.say("Meaning not projected", "意味の説明は未提供")
    "values" => {
      text.say(
        "Declared input fields: ", "宣言された入力フィールド: ",
      )
      let schema = explanation_narrative_field(meaning, "schema")
      visit_explanation_narrative_array(
        explanation_narrative_field(schema, "fields"),
        text.budget,
        (index, field) => {
          if index > 0 {
            text.append(", ")
          }
          text.quote(explanation_narrative_string(field, "name"))
          text.append(":")
          explain_narrative_type(
            explanation_narrative_field(field, "type"),
            text,
          )
          if explanation_narrative_string(field, "presence") == "conditional" {
            text.say(" (conditional)", " (条件付き)")
          }
        },
      )
    }
    "filter" => {
      text.say("Keep rows where: ", "この条件を満たす行を残す: ")
      explain_narrative_predicate(
        explanation_narrative_field(meaning, "predicate"),
        text,
      )
    }
    "projection" => {
      match explanation_narrative_string(meaning, "operation") {
        "select" =>
          text.say("Select output fields: ", "出力するフィールド: ")
        "rename" =>
          text.say(
            "Rename output fields: ", "出力フィールド名の変更: ",
          )
        "drop" =>
          text.say(
            "Output fields after dropping: ", "削除後の出力フィールド: ",
          )
        _ => raise InvalidExplanation
      }
      visit_explanation_narrative_array(
        explanation_narrative_field(meaning, "fields"),
        text.budget,
        (index, field) => {
          if index > 0 {
            text.append(", ")
          }
          text.quote(explanation_narrative_string(field, "output"))
          text.append(" ← ")
          text.quote(explanation_narrative_string(field, "input"))
        },
      )
    }
    "join" => {
      text.append(explanation_narrative_string(meaning, "join_kind"))
      text.say(" join on: ", " 結合のキー: ")
      visit_explanation_narrative_array(
        explanation_narrative_field(meaning, "keys"),
        text.budget,
        (index, key) => {
          if index > 0 {
            text.append(", ")
          }
          text.append("left.")
          text.quote(explanation_narrative_string(key, "left"))
          text.append(" = right.")
          text.quote(explanation_narrative_string(key, "right"))
        },
      )
      text.say("; Null keys: ", "; NULLキー: ")
      match explanation_narrative_string(meaning, "null_key") {
        "no_match" => text.say("do not match", "一致させない")
        "fail" => text.say("fail", "失敗")
        _ => raise InvalidExplanation
      }
    }
    _ => raise InvalidExplanation
  }
}

///|
/// Render an already admitted Explanation's original structural parts. The
/// entered caller owns their full wire validation, currentness, and backing.
/// No compiler, Host or application callback is invoked by the renderer.
pub fn render_client_explanation_narrative(
  facts : @canonical.CanonicalValue,
  context : @canonical.CanonicalValue,
  language : ClientExplanationLanguage,
  max_characters : Int,
) -> ClientExplanationNarrative raise ClientExplanationNarrativeIssue {
  if max_characters < 1 || max_characters > 65536 {
    raise ExplanationPresentationLimit
  }
  let budget : ExplanationNarrativeBudget = {
    language,
    characters: max_characters,
    visits: 10000,
  }
  let context_items : Array[String] = []
  visit_explanation_narrative_array(
    explanation_narrative_field(context, "items"),
    budget,
    (_, item) => {
      let text : ExplanationNarrativeText = { budget, out: StringBuilder(), }
      explain_narrative_context(item, text)
      context_items.push(text.out.to_string())
    },
  )
  let steps : Array[String] = []
  visit_explanation_narrative_array(
    explanation_narrative_field(facts, "steps"),
    budget,
    (_, fact) => {
      if steps.length() == 256 {
        raise ExplanationPresentationLimit
      }
      let text : ExplanationNarrativeText = { budget, out: StringBuilder(), }
      explain_narrative_fact(fact, text)
      steps.push(text.out.to_string())
    },
  )
  { context: context_items, steps, }
}
