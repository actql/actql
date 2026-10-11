///|
pub(all) struct DecisionLimits {
  max_questions : Int
  max_options : Int
  max_levels : Int
  max_name_bytes : Int
  max_work : Int
}

///|
pub(all) enum DecisionIssueKind {
  InvalidLimits
  WorkLimit
  UnsupportedTask
  InvalidPrompt
  InputField
  OutputContract
  InvalidAnswer
  Precision
  Distribution
  ChoiceMaximum
  ScoreConsistency
} derive(Eq, Debug)

///|
pub(all) struct DecisionIssue {
  kind : DecisionIssueKind
  source : @decode.Cursor?
}

///|
priv enum DecisionQuestionKind {
  Choice(Array[String])
  Score(Int)
  Boolean
}

///|
priv struct DecisionQuestion {
  id : String
  kind : DecisionQuestionKind
}

///|
/// Checked question/output correspondence, not execution or provider authority.
struct DecisionContract {
  task : ModelTaskContract
  prompt : ModelDependency
  state_input : String
  questions : Array[DecisionQuestion]
  output : @value_contract.Contract
  work : Int
}

///|
/// A registered physical precision profile, separate from the generic answer
/// shape. Selecting this profile does not establish a provider's conformance.
struct DecisionProbabilityProfile {
  cid : String
  scale : Double
  half_unit : Double
  arithmetic_margin : Double
  grid_margin_scaled : Double
}

///|
priv struct DecisionBudget {
  limit : Int
  mut work : Int
}

///|
priv suberror DecisionStop {
  DecisionStop(DecisionIssue)
}

///|
fn[T] decision_fail(
  kind : DecisionIssueKind,
  source : @decode.Cursor,
) -> T raise DecisionStop {
  raise DecisionStop({ kind, source: Some(source), })
}

///|
fn decision_charge(
  b : DecisionBudget,
  n : Int,
  source : @decode.Cursor,
) -> Unit raise DecisionStop {
  if n < 0 || n > b.limit - b.work {
    decision_fail(WorkLimit, source)
  }
  b.work += n
}

///|
fn decision_object(
  source : @decode.Cursor,
  names : Array[String],
  b : DecisionBudget,
  issue : DecisionIssueKind,
) -> @decode.ObjectView raise DecisionStop {
  let count = match @decode.object_length(source) {
    Some(n) => n
    None => decision_fail(issue, source)
  }
  decision_charge(b, count + 1, source)
  for i in 0..<count {
    let (name, value) = @decode.field_at(source, i).unwrap()
    decision_charge(b, name.length(), value)
  }
  match @decode.closed_object(source, names) {
    Ok(value) => value
    Err(_) => decision_fail(issue, source)
  }
}

///|
fn decision_required(
  o : @decode.ObjectView,
  name : String,
  source : @decode.Cursor,
  issue : DecisionIssueKind,
) -> @decode.Cursor raise DecisionStop {
  match @decode.required(o, name) {
    Ok(value) => value
    Err(_) => decision_fail(issue, source)
  }
}

///|
fn decision_text(
  source : @decode.Cursor,
  b : DecisionBudget,
  issue : DecisionIssueKind,
  nonempty? : Bool = true,
) -> String raise DecisionStop {
  let text = match @decode.text(source) {
    Ok(value) if !nonempty || !value.is_empty() => value
    _ => decision_fail(issue, source)
  }
  decision_charge(b, text.length() + 1, source)
  text
}

///|
fn decision_list(
  source : @decode.Cursor,
  minimum : Int,
  maximum : Int,
  b : DecisionBudget,
  issue : DecisionIssueKind,
) -> Int raise DecisionStop {
  let n = match @decode.array_length(source) {
    Some(n) if n >= minimum && n <= maximum => n
    _ => decision_fail(issue, source)
  }
  decision_charge(b, n + 1, source)
  n
}

///|
fn decision_output_object(
  entries : Array[(String, @value_contract.Contract)],
  limits : DecisionLimits,
  source : @decode.Cursor,
) -> @value_contract.Contract raise DecisionStop {
  match
    @value_contract.object_contract(
      entries,
      nullable=false,
      max_fields=limits.max_questions.max(3),
      max_name_bytes=limits.max_name_bytes,
    ) {
    Ok(value) => value
    Err(_) => decision_fail(OutputContract, source)
  }
}

///|
/// Builds the generic answer type from the original ordered questions. Nullable
/// distribution syntax is not permission to omit a native-required distribution.
pub fn read_decision_contract(
  task : ModelTaskContract,
  prompt : ModelDependency,
  limits : DecisionLimits,
) -> Result[DecisionContract, DecisionIssue] {
  if limits.max_questions < 1 ||
    limits.max_options < 1 ||
    limits.max_levels < 2 ||
    limits.max_name_bytes < 0 ||
    limits.max_work < 0 {
    return Err({ kind: InvalidLimits, source: None, })
  }
  if task.kind != Decision ||
    prompt.kind != ModelPrompt ||
    prompt.cid != task.prompt {
    return Err({ kind: UnsupportedTask, source: None, })
  }
  guard prompt.payload is Some(root) else {
    return Err({ kind: InvalidPrompt, source: None, })
  }
  let b = { limit: limits.max_work, work: 0, }
  try {
    let o = decision_object(
      root,
      ["format", "state_input", "questions"],
      b,
      InvalidPrompt,
    )
    if decision_text(
        decision_required(o, "format", root, InvalidPrompt),
        b,
        InvalidPrompt,
      ) !=
      "actql.decision_prompt/0.1" {
      decision_fail(InvalidPrompt, root)
    }
    let input_source = decision_required(o, "state_input", root, InvalidPrompt)
    let state_input = decision_text(input_source, b, InvalidPrompt)
    guard task.input.shape is @value_contract.Object(fields) else {
      decision_fail(InputField, input_source)
    }
    let mut found = false
    for i in 0..<@value_contract.field_count(fields) {
      let field = @value_contract.field_at(fields, i).unwrap()
      decision_charge(b, field.name.length() + 1, input_source)
      if field.name == state_input {
        found = true
      }
    }
    if !found {
      decision_fail(InputField, input_source)
    }
    let list = decision_required(o, "questions", root, InvalidPrompt)
    let n = decision_list(list, 1, limits.max_questions, b, InvalidPrompt)
    let questions = []
    let entries = []
    let seen : Map[String, Bool] = Map([])
    let text = @value_contract.primitive(StringType, nullable=false)
    let number = @value_contract.primitive(NumberType, nullable=false)
    for i in 0..<n {
      let source = @decode.element_at(list, i).unwrap()
      let q = decision_object(
        source,
        ["id", "type", "instructions", "options", "levels"],
        b,
        InvalidPrompt,
      )
      let id = decision_text(
        decision_required(q, "id", source, InvalidPrompt),
        b,
        InvalidPrompt,
      )
      if seen.contains(id) {
        decision_fail(InvalidPrompt, source)
      }
      seen[id] = true
      let kind = decision_text(
        decision_required(q, "type", source, InvalidPrompt),
        b,
        InvalidPrompt,
      )
      let _ = decision_text(
        decision_required(q, "instructions", source, InvalidPrompt),
        b,
        InvalidPrompt,
        nonempty=false,
      )
      let (kind, answer) = match kind {
        "choice" => {
          if @decode.lookup(q, "levels") is Some(_) {
            decision_fail(InvalidPrompt, source)
          }
          let options_source = decision_required(
            q,
            "options",
            source,
            InvalidPrompt,
          )
          let count = decision_list(
            options_source,
            1,
            limits.max_options,
            b,
            InvalidPrompt,
          )
          let options = []
          let unique : Map[String, Bool] = Map([])
          for index in 0..<count {
            let item = @decode.element_at(options_source, index).unwrap()
            let option = decision_object(
              item,
              ["id", "description"],
              b,
              InvalidPrompt,
            )
            let name = decision_text(
              decision_required(option, "id", item, InvalidPrompt),
              b,
              InvalidPrompt,
            )
            if unique.contains(name) {
              decision_fail(InvalidPrompt, item)
            }
            unique[name] = true
            let _ = decision_text(
              decision_required(option, "description", item, InvalidPrompt),
              b,
              InvalidPrompt,
              nonempty=false,
            )
            options.push(name)
          }
          let item = decision_output_object(
            [("option", text), ("probability", number)],
            limits,
            source,
          )
          let distribution = @value_contract.array_contract(item, nullable=true).unwrap()
          (
            DecisionQuestionKind::Choice(options),
            decision_output_object(
              [("choice", text), ("probabilities", distribution)],
              limits,
              source,
            ),
          )
        }
        "score" => {
          if @decode.lookup(q, "options") is Some(_) {
            decision_fail(InvalidPrompt, source)
          }
          let levels = decision_required(q, "levels", source, InvalidPrompt)
          let count = decision_list(
            levels,
            2,
            limits.max_levels,
            b,
            InvalidPrompt,
          )
          for index in 0..<count {
            let _ = decision_text(
              @decode.element_at(levels, index).unwrap(),
              b,
              InvalidPrompt,
              nonempty=false,
            )
          }
          let item = decision_output_object(
            [("level", number), ("probability", number)],
            limits,
            source,
          )
          let distribution = @value_contract.array_contract(item, nullable=true).unwrap()
          (
            DecisionQuestionKind::Score(count),
            decision_output_object(
              [("score", number), ("probabilities", distribution)],
              limits,
              source,
            ),
          )
        }
        "boolean" => {
          if @decode.lookup(q, "options") is Some(_) ||
            @decode.lookup(q, "levels") is Some(_) {
            decision_fail(InvalidPrompt, source)
          }
          (
            DecisionQuestionKind::Boolean,
            decision_output_object([("probability", number)], limits, source),
          )
        }
        _ => decision_fail(InvalidPrompt, source)
      }
      decision_charge(b, 8, source)
      questions.push({ id, kind, })
      entries.push((id, answer))
    }
    let output = decision_output_object(entries, limits, root)
    // The equality cursor bounds recursive correspondence independently of
    // payload inspection, rather than trusting the authored output-schema CID.
    let equality = @value_contract.start_type_equality(
      output,
      task.output,
      b.limit - b.work,
    ) catch {
      _ => decision_fail(WorkLimit, root)
    }
    let mut equal = None
    while equal is None {
      decision_charge(b, 1, root)
      equal = @value_contract.advance_type_equality(equality) catch {
        _ => decision_fail(WorkLimit, root)
      }
    }
    if equal != Some(true) {
      decision_fail(OutputContract, root)
    }
    Ok({ task, prompt, state_input, questions, output, work: b.work, })
  } catch {
    DecisionStop(issue) => Err(issue)
  }
}

///|
pub fn decision_output_contract(
  value : DecisionContract,
) -> @value_contract.Contract {
  value.output
}

///|
pub fn decision_contract_usage(value : DecisionContract) -> Int {
  value.work
}

///|
pub fn decision_state_input(value : DecisionContract) -> String {
  value.state_input
}

///|
pub fn decision_contract_matches(
  value : DecisionContract,
  task : ModelTaskContract,
  prompt : ModelDependency,
) -> Bool {
  physical_equal(value.task, task) && physical_equal(value.prompt, prompt)
}

///|
fn decision_abs(x : Double) -> Double {
  if x < 0.0 {
    -x
  } else {
    x
  }
}

///|
fn decision_distribution_error_allowed(
  error : Double,
  count : Int,
  profile : DecisionProbabilityProfile,
) -> Bool {
  count > 0 &&
  error >= 0.0 &&
  error <= count.to_double() * profile.half_unit + profile.arithmetic_margin
}

///|
fn decision_score_error_allowed(
  error : Double,
  sum_indices : Double,
  profile : DecisionProbabilityProfile,
) -> Bool {
  sum_indices >= 0.0 &&
  sum_indices <= 9007199254740991.0 &&
  error >= 0.0 &&
  error <=
  profile.half_unit * sum_indices +
  profile.half_unit +
  profile.arithmetic_margin
}

///|
fn decision_number(
  source : @decode.Cursor,
  maximum : Double,
  profile : DecisionProbabilityProfile,
  b : DecisionBudget,
) -> Double raise DecisionStop {
  decision_charge(b, 1, source)
  let x = match @decode.finite_number(source) {
    Ok(x) if x >= 0.0 && x <= maximum => x
    _ => decision_fail(InvalidAnswer, source)
  }
  let scaled = x * profile.scale
  // Only convert inside the admitted nonnegative Int domain. This protects
  // nearest-integer calculation for unusually large caller-selected bounds.
  if scaled > 2147483646.0 {
    decision_fail(InvalidLimits, source)
  }
  let nearest = (scaled + 0.5).to_int().to_double()
  if decision_abs(scaled - nearest) > profile.grid_margin_scaled {
    decision_fail(Precision, source)
  }
  x
}

///|
/// Returns actual validation work only. Original response values are never
/// rounded, normalized, copied into defaults or used as provider authority.
pub fn validate_decision_answers(
  value : DecisionContract,
  answer : @decode.Cursor,
  profile : DecisionProbabilityProfile,
  max_work : Int,
) -> Result[Int, DecisionIssue] {
  if max_work < 0 {
    return Err({ kind: InvalidLimits, source: None, })
  }
  let b = { limit: max_work, work: 0, }
  try {
    let names = value.questions.map(q => q.id)
    decision_charge(b, names.length(), answer)
    let outer = decision_object(answer, names, b, InvalidAnswer)
    for question in value.questions {
      let source = decision_required(outer, question.id, answer, InvalidAnswer)
      let allowed = match question.kind {
        Choice(_) => ["choice", "probabilities"]
        Score(_) => ["score", "probabilities"]
        Boolean => ["probability"]
      }
      let object = decision_object(source, allowed, b, InvalidAnswer)
      match question.kind {
        Boolean => {
          let _ = decision_number(
            decision_required(object, "probability", source, InvalidAnswer),
            1.0,
            profile,
            b,
          )
        }
        Choice(_) | Score(_) => {
          let count = match question.kind {
            Choice(ids) => ids.length()
            Score(n) => n
            _ => 0
          }
          let distribution = decision_required(
            object,
            "probabilities",
            source,
            InvalidAnswer,
          )
          let _ = decision_list(distribution, count, count, b, InvalidAnswer)
          let mut sum = 0.0
          let mut weighted = 0.0
          let mut sum_indices = 0.0
          let mut maximum = -1.0
          let mut selected_probability = -1.0
          let chosen = match question.kind {
            Choice(_) =>
              Some(
                decision_text(
                  decision_required(object, "choice", source, InvalidAnswer),
                  b,
                  InvalidAnswer,
                ),
              )
            _ => None
          }
          for i in 0..<count {
            let item = @decode.element_at(distribution, i).unwrap()
            let field = if chosen is Some(_) { "option" } else { "level" }
            let entry = decision_object(
              item,
              [field, "probability"],
              b,
              InvalidAnswer,
            )
            let identity = decision_required(entry, field, item, InvalidAnswer)
            match question.kind {
              Choice(ids) => {
                let id = decision_text(identity, b, InvalidAnswer)
                if id != ids[i] {
                  decision_fail(InvalidAnswer, identity)
                }
              }
              Score(_) => {
                decision_charge(b, 1, identity)
                if @decode.safe_integer(identity) != Ok(i.to_int64()) {
                  decision_fail(InvalidAnswer, identity)
                }
              }
              _ => ()
            }
            let p = decision_number(
              decision_required(entry, "probability", item, InvalidAnswer),
              1.0,
              profile,
              b,
            )
            decision_charge(b, 4, item)
            if i.to_double() > 9007199254740991.0 - sum_indices {
              decision_fail(InvalidLimits, item)
            }
            sum += p
            weighted += i.to_double() * p
            sum_indices += i.to_double()
            maximum = maximum.max(p)
            if question.kind is Choice(ids) && chosen == Some(ids[i]) {
              selected_probability = p
            }
          }
          // Doubles represent these finite integer coefficients exactly; never
          // wrap a caller's level count or use untrusted response tolerances.
          if !decision_distribution_error_allowed(
              decision_abs(sum - 1.0),
              count,
              profile,
            ) {
            decision_fail(Distribution, distribution)
          }
          match question.kind {
            Choice(_) =>
              if selected_probability != maximum {
                decision_fail(ChoiceMaximum, source)
              }
            Score(n) => {
              let score = decision_number(
                decision_required(object, "score", source, InvalidAnswer),
                (n - 1).to_double(),
                profile,
                b,
              )
              if !decision_score_error_allowed(
                  decision_abs(score - weighted),
                  sum_indices,
                  profile,
                ) {
                decision_fail(ScoreConsistency, source)
              }
            }
            _ => ()
          }
        }
      }
    }
    Ok(b.work)
  } catch {
    DecisionStop(issue) => Err(issue)
  }
}
