///|
// Private response custody for bounded checking and capture. The synchronous
// provider API remains unchanged; restored records use the original typed
// observation reader. Neither branch grants dispatch or profile authority.
priv struct ModelObservedResponse {
  value : @admitted.Value
  observation : @publication.ModelCaptureObservation
}

///|
fn lift_historical_model_response(
  response : ModelResponse,
) -> ModelObservedResponse {
  {
    value: response.value,
    observation: {
      origin: @publication.HistoricalAdmitted,
      provider_model: Some(response.provider_model),
      provider_revision: None,
      provider_request_id: Some(response.provider_request_id),
      gateway_request_id: None,
      input_tokens: Some(response.input_tokens),
      output_tokens: Some(response.output_tokens),
      provider_finish_reason: None,
      historical_finish_reason: Some("stop"),
      response_profile_cid: None,
      response_complete: None,
      raw_response_artifact_cid: None,
      provider_metadata: None,
      observed_at: response.observed_at,
    },
  }
}

///|
fn emit_model_optional_text(
  writer : @encode.Writer,
  value : String?,
) -> Unit raise @encode.EncodeFailure {
  match value {
    Some(text) => @encode.string_value(writer, text)
    None => @encode.null_value(writer)
  }
}

///|
fn emit_model_optional_tokens(
  writer : @encode.Writer,
  value : Int64?,
) -> Unit raise @encode.EncodeFailure {
  match value {
    Some(tokens) => @encode.decimal_number_value(writer, tokens.to_string())
    None => @encode.null_value(writer)
  }
}

///|
fn valid_model_optional_text(value : String?) -> Bool {
  match value {
    Some(text) => !text.is_empty()
    None => true
  }
}

///|
fn valid_model_optional_tokens(value : Int64?) -> Bool {
  match value {
    Some(tokens) => tokens >= 0L
    None => true
  }
}
