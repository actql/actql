///|
/// Advance only the next original input operation. Name/Source/key admission
/// and Carrier/Contract traversal retain their original order, exact Budget and
/// typed refusals. Sync and staged checking drive this SAME body.
fn advance_pipeline_core_inputs(original : PipelineCoreBody) -> Unit raise Stop {
  if original.input_index == original.inputs.length() {
    original.phase = Parameters
    return
  }
  let i = original.input_index
  let (key, schema) = original.inputs[i]
  let b = original.b
  let source = original.source
  match original.input_step {
    Name => {
      name(b, source, key)
      if original.input_contracts[i] is SourceViewInput(stage, _, _, _) {
        let count = @stage.stage_input_declaration_count(stage)
        spend(b, source, count)
        original.source_count = count
        original.source_index = 0
        original.input_step = SourceFields
      } else {
        original.input_step = Duplicate
      }
    }
    SourceFields => {
      guard original.input_contracts[i] is SourceViewInput(stage, _, _, _) else {
        abort("original Source input expected")
      }
      if original.source_index < original.source_count {
        charge(
          b,
          source,
          @stage.stage_input_declaration_name_at(stage, original.source_index).unwrap(),
        )
        original.source_index += 1
      } else {
        original.input_step = SourceBinding
      }
    }
    SourceBinding => {
      guard original.input_contracts[i]
        is SourceViewInput(stage, declared, retained, _) else {
        abort("original Source input expected")
      }
      let steps = @stage.stage_steps_source(stage)
      let selected = @stage.stage_input_declaration(stage, declared)
      if declared != key ||
        @decode.tree_index(steps, source) != @decode.tree_index(steps, steps) ||
        !(selected is Some(value) &&
        @decode.tree_index(value, retained) == @decode.tree_index(value, value)) {
        fail(source, KeyEvidence(InputContractMismatch))
      }
      original.input_step = Duplicate
    }
    Duplicate => {
      if original.names.contains(key) {
        fail(source, DuplicateName(key))
      }
      original.input_step = CarrierStart
    }
    CarrierStart => {
      original.carrier_read = Some(
        begin_carrier_preflight_read(b, source, schema),
      )
      original.input_step = Carrier
    }
    Carrier => {
      let read = original.carrier_read.unwrap()
      advance_carrier_preflight_read(read)
      match read.state {
        Pending => ()
        Complete => {
          clear_carrier_preflight_read(read)
          original.carrier_read = None
          if original.keyed_inputs[i] is Some(collection) {
            let count = @evidence.key_witness_count(collection)
            spend(b, source, count)
            original.key_count = count
            original.key_index = 0
            original.input_step = Keys
          } else {
            original.input_step = Register
          }
        }
        Rejected(issue) => raise Stop(issue)
        Cleared =>
          abort("original Carrier preflight was retired before its input")
      }
    }
    Keys =>
      if original.key_index < original.key_count {
        let collection = original.keyed_inputs[i].unwrap()
        let declaration = @evidence.key_witness_at(
          collection,
          original.key_index,
        ).unwrap()
        let count = @evidence.key_field_count(declaration)
        spend(b, source, count)
        original.field_count = count
        original.field_index = 0
        original.input_step = KeyField
      } else {
        original.input_step = Register
      }
    KeyField =>
      if original.field_index < original.field_count {
        let collection = original.keyed_inputs[i].unwrap()
        let declaration = @evidence.key_witness_at(
          collection,
          original.key_index,
        ).unwrap()
        let count = @evidence.key_alias_count(declaration, original.field_index)
        spend(b, source, count)
        original.alias_count = count
        original.alias_index = 0
        original.input_step = KeyAlias
      } else {
        original.key_index += 1
        original.input_step = Keys
      }
    KeyAlias =>
      if original.alias_index < original.alias_count {
        let collection = original.keyed_inputs[i].unwrap()
        let declaration = @evidence.key_witness_at(
          collection,
          original.key_index,
        ).unwrap()
        let field = @evidence.key_alias_at(
          declaration,
          original.field_index,
          original.alias_index,
        ).unwrap()
        charge(b, source, @schema.reference_name(field.name))
        original.alias_index += 1
      } else {
        original.field_index += 1
        original.input_step = KeyField
      }
    Register => {
      original.names[key] = Input(i)
      original.input_index += 1
      original.input_step = Name
    }
  }
}
