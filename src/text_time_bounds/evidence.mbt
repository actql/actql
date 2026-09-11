///|
/// Emit the canonical input-evidence preimage, not a complete envelope or proof.
/// The writer owns shared byte/node/depth budgets and failure closure.
pub fn emit_input_evidence(
  input : Input,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  match input.origin {
    ValueContract | DerivedOutput =>
      @contract.emit_checked(input.contract, writer)
    KnownValue => {
      @encode.begin_object(writer)
      @encode.key(writer, "value")
      match input.value {
        Some({ value: @value.Null, .. }) => @encode.null_value(writer)
        Some({ value: @value.Text(text) | @value.Timestamp(text), .. }) =>
          @encode.string_value(writer, text)
        _ => raise @encode.InvalidStructure
      }
      @encode.key(writer, "version")
      @encode.string_value(writer, "actql-literal-text-extent/0.1")
      @encode.end_object(writer)
    }
    RuntimePreflight => {
      @encode.begin_object(writer)
      @encode.key(writer, "contract")
      @contract.emit_checked(input.contract, writer)
      @encode.key(writer, "policy")
      @policy.emit(input.policy, writer)
      @encode.key(writer, "version")
      @encode.string_value(writer, "actql-text-time-runtime-preflight/0.1")
      @encode.end_object(writer)
    }
  }
}

///|
/// Hash the same bounded stream without materializing serialized text.
pub fn input_evidence_cid(
  input : Input,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> String raise @encode.EncodeFailure {
  let writer = @encode.hashing_writer(max_bytes, max_nodes, max_depth)
  emit_input_evidence(input, writer)
  "sha256:" + @encode.finish_hash(writer)
}

///|
/// Wire classification; DerivedOutput still retains its producer separately.
pub fn input_evidence_source(input : Input) -> String {
  match input.origin {
    ValueContract | DerivedOutput => "value_contract"
    KnownValue => "literal"
    RuntimePreflight => "runtime_preflight"
  }
}
