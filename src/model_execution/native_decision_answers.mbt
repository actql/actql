///|
pub(all) enum NativeDecisionAnswerIssue {
  ForeignRequest
  Malformed
  Limit
} derive(Eq, Debug)

///|
priv struct NativeAnswerBudget {
  limit : Int
  mut work : Int
}

///|
priv suberror NativeAnswerStop {
  NativeAnswerStop(NativeDecisionAnswerIssue)
}

///|
fn native_answer_charge(
  b : NativeAnswerBudget,
  count : Int,
) -> Unit raise NativeAnswerStop {
  if count < 0 || count > b.limit - b.work {
    raise NativeAnswerStop(Limit)
  }
  b.work += count
}

///|
// Prepay every retained field-name traversal before building the existing
// decoder lookup. This is a finite synchronous codec, not a quantum cursor.
fn native_answer_object(
  source : @decode.Cursor,
  b : NativeAnswerBudget,
) -> @decode.ObjectView raise NativeAnswerStop {
  guard @decode.object_length(source) is Some(count) else {
    raise NativeAnswerStop(Malformed)
  }
  native_answer_charge(b, count + 1)
  for i in 0..<count {
    let (name, _) = @decode.field_at(source, i).unwrap()
    native_answer_charge(b, name.length())
  }
  match @decode.open_object(source) {
    Ok(value) => value
    Err(_) => raise NativeAnswerStop(Malformed)
  }
}

///|
fn native_answer_required(
  object : @decode.ObjectView,
  name : String,
  b : NativeAnswerBudget,
) -> @decode.Cursor raise NativeAnswerStop {
  native_answer_charge(b, name.length() + 1)
  match @decode.required(object, name) {
    Ok(value) => value
    Err(_) => raise NativeAnswerStop(Malformed)
  }
}

///|
fn native_answer_text(
  source : @decode.Cursor,
  b : NativeAnswerBudget,
) -> String raise NativeAnswerStop {
  match @decode.text(source) {
    Ok(text) => {
      native_answer_charge(b, text.length() + 1)
      text
    }
    Err(_) => raise NativeAnswerStop(Malformed)
  }
}

///|
fn native_answer_number(
  source : @decode.Cursor,
  b : NativeAnswerBudget,
) -> Double raise NativeAnswerStop {
  native_answer_charge(b, 1)
  match @decode.finite_number(source) {
    Ok(value) => value
    Err(_) => raise NativeAnswerStop(Malformed)
  }
}

///|
// Project the selected SDK's positional aliases back to original question and
// option IDs. The admitted raw tree remains independently owned by its caller,
// including unknown/confidence/usage fields. This DATA transformation issues no
// saved response, completeness, profile, precision, typed answer or send grant.
// Original Model validation must still apply validate_decision_answers and the
// output contract. Synchronous codec/Map/writer overlap requires physical funds
// and an operationally justified finite profile before runtime installation.
pub fn project_native_decision_answers(
  original : NativeDecisionRequest,
  provider : AdmittedModelProvider,
  request : ModelRequest,
  response : @decode.Cursor,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_work : Int,
) -> Result[(String, Int), NativeDecisionAnswerIssue] {
  if !native_decision_request_matches(original, provider, request) {
    return Err(ForeignRequest)
  }
  guard original.questions is Some(questions) &&
    @decode.array_length(questions) is Some(count) else {
    return Err(ForeignRequest)
  }
  if max_bytes < 1 || max_nodes < 1 || max_depth < 1 || max_work < 0 {
    return Err(Limit)
  }
  let b = { limit: max_work, work: 0, }
  let mut held_writer = None
  try {
    let root = native_answer_object(response, b)
    let answers_source = native_answer_required(root, "answers", b)
    if @decode.object_length(answers_source) != Some(count) {
      raise NativeAnswerStop(Malformed)
    }
    let answers = native_answer_object(answers_source, b)
    let writer = @encode.writer(max_bytes, max_nodes, max_depth)
    held_writer = Some(writer)
    @encode.begin_object(writer)
    for i in 0..<count {
      native_answer_charge(b, 1)
      let question = @decode.element_at(questions, i).unwrap()
      let id = native_decision_question_id(original, i).unwrap()
      // Identity text is borrowed unchanged, never NFC-normalized or replaced
      // by a position alias. No semantic CID is calculated from this wire.
      native_answer_charge(b, id.length())
      @encode.key(writer, id)
      let answer_source = native_answer_required(
        answers,
        native_decision_wire_key("q", i),
        b,
      )
      let answer = native_answer_object(answer_source, b)
      let kind = native_decision_text(question, "type").unwrap()
      let observed = native_answer_text(
        native_answer_required(answer, "type", b),
        b,
      )
      if observed != (if kind == "boolean" { "noul" } else { kind }) {
        raise NativeAnswerStop(Malformed)
      }
      @encode.begin_object(writer)
      if kind == "boolean" {
        @encode.key(writer, "probability")
        @encode.number_value(
          writer,
          native_answer_number(native_answer_required(answer, "noul", b), b),
        )
      } else {
        let items = native_decision_field(
          question,
          if kind == "choice" {
            "options"
          } else {
            "levels"
          },
        ).unwrap()
        let item_count = @decode.array_length(items).unwrap()
        let probabilities_source = native_answer_required(
          answer, "probabilities", b,
        )
        if @decode.object_length(probabilities_source) != Some(item_count) {
          raise NativeAnswerStop(Malformed)
        }
        let probabilities = native_answer_object(probabilities_source, b)
        if kind == "choice" {
          let chosen = native_answer_text(
            native_answer_required(answer, "choice", b),
            b,
          )
          let mut chosen_original = None
          for j in 0..<item_count {
            native_answer_charge(b, 12)
            if chosen == native_decision_wire_key("o", j) {
              chosen_original = native_decision_option_id(original, i, j)
              break
            }
          }
          guard chosen_original is Some(chosen_id) else {
            raise NativeAnswerStop(Malformed)
          }
          native_answer_charge(b, chosen_id.length())
          @encode.key(writer, "choice")
          @encode.string_value(writer, chosen_id)
        } else if kind != "score" {
          raise NativeAnswerStop(Malformed)
        }
        @encode.key(writer, "probabilities")
        @encode.begin_array(writer)
        // Original option/level order, never response object enumeration.
        for j in 0..<item_count {
          native_answer_charge(b, 1)
          let position_key = if kind == "choice" {
            native_decision_wire_key("o", j)
          } else {
            j.to_string()
          }
          let p = native_answer_number(
            native_answer_required(probabilities, position_key, b),
            b,
          )
          @encode.begin_object(writer)
          if kind == "choice" {
            let option = native_decision_option_id(original, i, j).unwrap()
            native_answer_charge(b, option.length())
            @encode.key(writer, "option")
            @encode.string_value(writer, option)
          } else {
            @encode.key(writer, "level")
            @encode.number_value(writer, j.to_double())
          }
          @encode.key(writer, "probability")
          @encode.number_value(writer, p)
          @encode.end_object(writer)
        }
        @encode.end_array(writer)
        if kind == "score" {
          @encode.key(writer, "score")
          @encode.number_value(
            writer,
            native_answer_number(native_answer_required(answer, "score", b), b),
          )
        }
      }
      @encode.end_object(writer)
    }
    @encode.end_object(writer)
    let wire = @encode.finish(writer)
    held_writer = None
    Ok((wire, b.work))
  } catch {
    NativeAnswerStop(issue) => {
      if held_writer is Some(writer) {
        @encode.cancel_writer(writer)
      }
      Err(issue)
    }
    _ => {
      if held_writer is Some(writer) {
        @encode.cancel_writer(writer)
      }
      Err(Limit)
    }
  }
}
