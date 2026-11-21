///|
// Text budget is shared with the Native renderer. Each character can occupy
// six bytes in JSON; account for both arrays, their quotes and separators.
let explanation_narrative_max_characters = 65536

///|
let explanation_narrative_max_items = 10000

///|
/// Project text from an already disclosed static Explanation. This entry
/// owns no Host, Run or authorization and cannot reopen the original read.
#export_name("clientValuesHostRenderStaticExplanation")
pub fn client_values_host_render_static_explanation(
  wire : String,
  locale : String,
) -> Result[String, Int] {
  let selected : @host.ClientExplanationLanguage = match locale {
    "en" => English
    "ja" => Japanese
    _ => return Err(0)
  }
  if wire.length() > explanation_narrative_max_characters {
    return Err(1)
  }
  let view = match
    @publication.parse_interactive_run_control_shape(
      "static_explanation_view", wire, explanation_narrative_max_characters, explanation_narrative_max_items,
      64,
    ) {
    Ok(value) => value
    Err(_) => return Err(0)
  }
  guard @canonical.object_field(view, "facts") is Some(facts) &&
    @canonical.object_field(view, "context") is Some(context) else {
    return Err(0)
  }
  let narrative = @host.render_client_explanation_narrative(
    facts, context, selected, explanation_narrative_max_characters,
  ) catch {
    @host.InvalidExplanation => return Err(0)
    @host.ExplanationPresentationLimit => return Err(1)
  }
  try {
    let reply = @encode.writer(
      6 * explanation_narrative_max_characters +
      3 * explanation_narrative_max_items +
      64,
      explanation_narrative_max_items + 16,
      4,
    )
    @encode.begin_object(reply)
    @encode.key(reply, "context")
    @encode.begin_array(reply)
    for line in narrative.context {
      @encode.string_value(reply, line)
    }
    @encode.end_array(reply)
    @encode.key(reply, "steps")
    @encode.begin_array(reply)
    for line in narrative.steps {
      @encode.string_value(reply, line)
    }
    @encode.end_array(reply)
    @encode.end_object(reply)
    Ok(@encode.finish(reply))
  } catch {
    _ => Err(1)
  }
}
