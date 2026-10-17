///|
/// Original mock answer DATA inside the existing Model owner. These limits
/// bound document/typing work, not an installation, grant or physical funds.
pub(all) struct ModelMockAnswerLimits {
  document : @environment.Limits
  values : @admitted.Limits
  max_entries : Int
  max_work : Int
}

///|
pub(all) enum ModelMockAnswerIssue {
  InvalidLimits
  BodyLimit
  WorkLimit
  EntryLimit
  InvalidBody
  TaskIdentity
  OutputValue
  ForeignOriginal
  Retired
} derive(Eq, Debug)

///|
/// No public constructor, Provider selector or canonical identity is issued.
/// Retain the same declaration and its checked output contract, not a CID or
/// an equal re-read Task. The Host separately retains project/file originals.
struct ModelMockAnswers {
  mut original : ModelMockAnswers?
  mut task : @environment.PublicModelTaskDeclaration?
  mut document : @decode.Cursor?
  mut fallback : @admitted.CheckedValue?
  entries : Array[(String, @admitted.CheckedValue)]
  work : Int
  nodes : Int
  text : Int
}

///|
priv struct MockAnswerBudget {
  mut remaining : Int
  mut nodes : Int
  mut text : Int
  depth : Int
}

///|
priv suberror MockAnswerStop {
  MockAnswerStop(ModelMockAnswerIssue)
}

///|
fn mock_answer_charge(
  b : MockAnswerBudget,
  amount : Int,
) -> Unit raise MockAnswerStop {
  if amount < 0 || amount > b.remaining {
    raise MockAnswerStop(WorkLimit)
  }
  b.remaining -= amount
}

///|
fn mock_answer_object(
  cursor : @decode.Cursor,
  names : Array[String],
  max_members : Int,
  b : MockAnswerBudget,
) -> @decode.ObjectView raise MockAnswerStop {
  guard @decode.object_length(cursor) is Some(count) else {
    raise MockAnswerStop(InvalidBody)
  }
  if count > max_members {
    raise MockAnswerStop(EntryLimit)
  }
  mock_answer_charge(b, count)
  for index in 0..<count {
    let (name, _) = @decode.field_at(cursor, index).unwrap()
    mock_answer_charge(b, name.length())
  }
  match @decode.closed_object(cursor, names) {
    Ok(value) => value
    Err(_) => raise MockAnswerStop(InvalidBody)
  }
}

///|
fn mock_answer_value(
  output : @contract.Contract,
  cursor : @decode.Cursor,
  b : MockAnswerBudget,
) -> @admitted.CheckedValue raise MockAnswerStop {
  let admission = match
    @admitted.start_typed_admission(output, cursor, {
      max_nodes: b.nodes,
      max_depth: b.depth,
      max_text_bytes: b.text,
    }) {
    Ok(value) => value
    Err(_) => raise MockAnswerStop(OutputValue)
  }
  errdefer @admitted.cancel_typed_admission(admission)
  while true {
    mock_answer_charge(b, 1)
    match @admitted.advance_typed_admission(admission) {
      TypedAdmissionContinue => ()
      TypedAdmissionComplete(value, nodes, text) => {
        b.nodes -= nodes
        b.text -= text
        return value
      }
      TypedAdmissionFailed(_) | TypedAdmissionTerminal =>
        raise MockAnswerStop(OutputValue)
    }
  } nobreak {
    raise MockAnswerStop(OutputValue)
  }
}

///|
/// Read exactly the documented answer record. Every default and keyed answer,
/// including unused entries, is typed against this declaration's own output.
/// Key labels stay exact DATA; this admission does not establish a row's key
/// or choose an answer for a ModelRequest. No model/default/handling is guessed.
pub fn read_model_mock_answer_document(
  task : @environment.PublicModelTaskDeclaration,
  wire : String,
  format : String,
  limits : ModelMockAnswerLimits,
) -> Result[ModelMockAnswers, ModelMockAnswerIssue] {
  let d = limits.document
  if limits.max_entries < 0 ||
    limits.max_work < 0 ||
    d.max_bytes < 0 ||
    d.max_nodes < 0 ||
    d.max_depth < 0 ||
    d.max_members < 0 ||
    limits.values.max_nodes < 0 ||
    limits.values.max_depth < 0 ||
    limits.values.max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  if format != "json" && format != "yaml" {
    return Err(InvalidBody)
  }
  let bytes = match @scalar.admit_utf8_length(wire, d.max_bytes) {
    Ok(bytes) => bytes
    Err(_) => return Err(BodyLimit)
  }
  let budget : MockAnswerBudget = {
    remaining: limits.max_work,
    nodes: limits.values.max_nodes,
    text: limits.values.max_text_bytes,
    depth: limits.values.max_depth,
  }
  try {
    // Reserve encoding, source parsing and decoded-tree work before those
    // complete bounded materializations. Their retained copies still overlap.
    for amount in [bytes, bytes, d.max_nodes, d.max_nodes] {
      mock_answer_charge(budget, amount)
    }
    let parse_limits : @source.ParseLimits = {
      max_input_bytes: d.max_bytes,
      max_nodes: d.max_nodes,
      max_depth: d.max_depth,
    }
    let parsed = if format == "json" {
      @source.parse_json_bytes_preserving(@utf8.encode(wire), parse_limits)
    } else {
      @source.parse_yaml_bytes_preserving(@utf8.encode(wire), parse_limits)
    }
    let source = match parsed {
      Ok(value) => value
      Err(_) => raise MockAnswerStop(InvalidBody)
    }
    let document = match
      @decode.admit(source, {
        max_nodes: d.max_nodes,
        max_depth: d.max_depth,
        max_string_bytes: d.max_bytes,
        max_total_string_bytes: d.max_bytes,
      }) {
      Ok(value) => value
      Err(_) => raise MockAnswerStop(BodyLimit)
    }
    let root = mock_answer_object(
      document,
      ["task", "answers"],
      d.max_members,
      budget,
    )
    guard @decode.lookup(root, "task") is Some(id) && @decode.text(id) is Ok(id) else {
      raise MockAnswerStop(InvalidBody)
    }
    mock_answer_charge(budget, id.length())
    if id != @environment.public_model_task_declaration_identity(task).0 {
      raise MockAnswerStop(TaskIdentity)
    }
    guard @decode.lookup(root, "answers") is Some(answers) else {
      raise MockAnswerStop(InvalidBody)
    }
    let answers = mock_answer_object(
      answers,
      ["default", "by_key"],
      d.max_members,
      budget,
    )
    let output = @environment.public_model_task_contract(
      @environment.public_model_task_declaration_contracts(task).1,
    )
    let fallback = match @decode.lookup(answers, "default") {
      None => None
      Some(value) => Some(mock_answer_value(output, value, budget))
    }
    let entries : Array[(String, @admitted.CheckedValue)] = []
    match @decode.field(answers, "by_key") {
      Missing => ()
      ExplicitNull => raise MockAnswerStop(InvalidBody)
      Present(values) => {
        guard @decode.object_length(values) is Some(count) else {
          raise MockAnswerStop(InvalidBody)
        }
        if count > limits.max_entries || count > d.max_members {
          raise MockAnswerStop(EntryLimit)
        }
        mock_answer_charge(budget, count)
        for index in 0..<count {
          let (key, value) = @decode.field_at(values, index).unwrap()
          mock_answer_charge(budget, key.length())
          entries.push((key, mock_answer_value(output, value, budget)))
        }
      }
    }
    let result : ModelMockAnswers = {
      original: None,
      task: Some(task),
      document: Some(document),
      fallback,
      entries,
      work: limits.max_work - budget.remaining,
      nodes: limits.values.max_nodes - budget.nodes,
      text: limits.values.max_text_bytes - budget.text,
    }
    result.original = Some(result)
    Ok(result)
  } catch {
    MockAnswerStop(issue) => Err(issue)
  }
}

///|
fn ModelMockAnswers::require_original(
  self : Self,
  task : @environment.PublicModelTaskDeclaration,
) -> Result[Unit, ModelMockAnswerIssue] {
  guard self.original is Some(original) && self.task is Some(retained) else {
    return Err(Retired)
  }
  if !physical_equal(self, original) || !physical_equal(task, retained) {
    Err(ForeignOriginal)
  } else {
    Ok(())
  }
}

///|
pub fn model_mock_answer_default(
  original : ModelMockAnswers,
  task : @environment.PublicModelTaskDeclaration,
) -> Result[@admitted.CheckedValue?, ModelMockAnswerIssue] {
  original.require_original(task).map(_ => original.fallback)
}

///|
pub fn model_mock_answer_count(
  original : ModelMockAnswers,
  task : @environment.PublicModelTaskDeclaration,
) -> Result[Int, ModelMockAnswerIssue] {
  original.require_original(task).map(_ => original.entries.length())
}

///|
pub fn model_mock_answer_at(
  original : ModelMockAnswers,
  task : @environment.PublicModelTaskDeclaration,
  index : Int,
) -> Result[(String, @admitted.CheckedValue)?, ModelMockAnswerIssue] {
  original.require_original(task).map(_ => original.entries.get(index))
}

///|
pub fn model_mock_answer_usage(original : ModelMockAnswers) -> (Int, Int, Int) {
  (original.work, original.nodes, original.text)
}

///|
/// Drop only the original answer DATA/Task aliases. This is not a Model Call,
/// filesystem/Store/IO cleanup ACK, GC observation or capacity release.
pub fn retire_model_mock_answers(
  original : ModelMockAnswers,
  task : @environment.PublicModelTaskDeclaration,
) -> Result[Unit, ModelMockAnswerIssue] {
  match original.require_original(task) {
    Err(issue) => Err(issue)
    Ok(_) => {
      original.entries.clear()
      original.fallback = None
      original.document = None
      original.task = None
      original.original = None
      Ok(())
    }
  }
}
