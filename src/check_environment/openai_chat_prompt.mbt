///|
/// Provider-specific payload admission inside the unchanged prompt envelope.
/// A String is borrowed without normalization. This observation grants no I/O.
pub fn model_openai_chat_instructions(prompt : ModelDependency) -> String? {
  if prompt.kind != ModelPrompt {
    return None
  }
  let payload = match prompt.payload {
    Some(value) => value
    None => return None
  }
  let object = match
    @decode.closed_object(payload, ["format", "instructions"]) {
    Ok(value) => value
    Err(_) => return None
  }
  let format = match @decode.required(object, "format") {
    Ok(value) => value
    Err(_) => return None
  }
  let instructions = match @decode.required(object, "instructions") {
    Ok(value) => value
    Err(_) => return None
  }
  if @decode.text(format) != Ok("actql.openai_chat_prompt/0.1") {
    return None
  }
  match @decode.text(instructions) {
    Ok(value) => Some(value)
    Err(_) => None
  }
}
