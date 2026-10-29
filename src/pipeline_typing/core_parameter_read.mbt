///|
/// SAME original declarations, source selector and Budget. Each Contract uses
/// the original shared stack continuation; sync and funded readers drive this
/// body, never a second parameter checker or a new execution owner.
fn advance_pipeline_core_parameters(body : PipelineCoreBody) -> Unit raise Stop {
  let b = body.b
  let source = body.source
  match body.parameter_step {
    Count => {
      if body.parameters is Some(parameters) {
        spend(b, source, @parameter.declaration_count(parameters))
      }
      body.parameter_step = Name
    }
    Name =>
      if body.parameters is Some(parameters) &&
        body.parameter_index < @parameter.declaration_count(parameters) {
        let declaration = @parameter.declaration_at(
          parameters,
          body.parameter_index,
        ).unwrap()
        charge(b, source, declaration.name)
        body.parameter_read = Some(
          begin_contract_preflight_read(
            b,
            source,
            declaration.parameter_type.contract,
            0,
          ),
        )
        body.parameter_step = Contract
      } else {
        body.parameter_step = Select
      }
    Contract => {
      let read = body.parameter_read.unwrap()
      advance_contract_preflight_read(read)
      match read.state {
        Pending => ()
        Complete => {
          clear_contract_preflight_read(read)
          body.parameter_read = None
          body.parameter_index += 1
          body.parameter_step = Name
        }
        Rejected(issue) => raise Stop(issue)
        Cleared =>
          abort("original Parameter Contract was retired before its Core")
      }
    }
    Select => {
      body.current = match body.from {
        Some(cursor) => {
          let key = read_name(b, cursor)
          match body.names.get(key) {
            Some(value) => Some(value)
            None => fail(cursor, UnknownName(key))
          }
        }
        None => if body.inputs.length() == 1 { Some(Input(0)) } else { None }
      }
      body.parameter_step = Arrays
    }
    Arrays => {
      body.steps = Some([])
      body.ranked_steps = Some([])
      body.keyed_steps = Some([])
      body.phase = ImportedEvidence
    }
  }
}
