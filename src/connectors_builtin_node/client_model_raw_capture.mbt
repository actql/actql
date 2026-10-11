///|
// Private installed Node ports. These exports do not enable an asynchronous
// profile or confer capacity, capture installation or raw disclosure rights.
#export_name("clientProgramInferRawCaptureSaveBinding")
pub fn client_program_infer_raw_capture_save_binding(
  value : @model.ModelRawCaptureSave,
) -> (String, String, String, String, Int) {
  @publication.model_raw_response_store_binding(
    @model.model_raw_capture_save_binding(value),
  )
}

///|
#export_name("clientProgramInferRawCaptureSaveOriginals")
pub fn client_program_infer_raw_capture_save_originals(
  value : @model.ModelRawCaptureSave,
) -> Array[(String, String, String)] {
  @model.model_raw_capture_save_originals(value).map(original => {
    (
      @publication.captured_effect_dependency_body_kind(original),
      @publication.captured_effect_dependency_body_cid(original),
      @publication.captured_effect_dependency_body_json(original),
    )
  })
}

///|
#export_name("clientProgramInferRawCaptureSaveCurrent")
pub fn client_program_infer_raw_capture_save_current(
  value : @model.ModelRawCaptureSave,
) -> Result[Unit, @model.ModelRawCaptureSaveIssue] {
  @model.model_raw_capture_save_current(value)
}

///|
#export_name("clientProgramAcknowledgeSavedInferRawCapture")
pub fn client_program_acknowledge_saved_infer_raw_capture(
  value : @model.ModelRawCaptureSave,
) -> Result[@model.ModelSavedRawReceipt, @model.ModelRawCaptureSaveIssue] {
  @model.acknowledge_saved_model_raw_capture(value)
}

///|
#export_name("clientProgramInferSavedRawReceiptMatches")
pub fn client_program_infer_saved_raw_receipt_matches(
  receipt : @model.ModelSavedRawReceipt,
  call : @model.ModelPhysicalCall,
  response : @publication.RunEvidenceValue,
) -> Bool {
  @model.model_saved_raw_receipt_matches(receipt, call, response)
}

///|
#export_name("clientProgramInferSavedRawChatResponse")
pub fn client_program_infer_saved_raw_chat_response(
  receipt : @model.ModelSavedRawReceipt,
  body : String,
  metadata : @identity.CanonicalValue?,
) -> Result[@model.ModelPhysicalChatResponse, @model.ModelRawCaptureSaveIssue] {
  @model.model_saved_raw_chat_response(receipt, body, metadata)
}
