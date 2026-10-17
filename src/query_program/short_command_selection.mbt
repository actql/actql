///|
/// The original selection and the exact occurrence emitted by the same
/// compiler. This is not target issuance, currentness or execution authority.
struct ShortCommandSelection {
  target : ResolvedCommandTarget
  stage_index : Int
  effect_id : String
}

///|
pub fn short_command_selection_target(
  value : ShortCommandSelection,
) -> ResolvedCommandTarget {
  value.target
}

///|
pub fn short_command_selection_stage(value : ShortCommandSelection) -> Int {
  value.stage_index
}

///|
pub fn short_command_selection_effect(value : ShortCommandSelection) -> String {
  value.effect_id
}

///|
/// Retain the exact original target selected before expressions, paired with
/// the occurrence actually emitted by the ordinary script compiler. A legacy
/// field target need not encode its logical operation as a canonical field.
pub fn compile_short_command_with_source(
  query : @query.Query,
  context : Context,
  limits : Limits,
  publication : CommandTargetPublication,
  table_writes? : Array[TableWriteBinding] = [],
  update_targets? : UpdateTargetPublication? = None,
  store_targets? : StoreTargetPublication? = None,
) -> Result[(@program.Program, @builder.Source, ShortCommandSelection), Issue] {
  guard @query.terminal_short_command_effect(query) is Some(_) else {
    return Err(UnsupportedEffect)
  }
  let occurrences : Array[ShortCommandSelection] = []
  match
    compile_query_script_with_source(
      @query.single_query_script(query),
      context,
      limits,
      table_writes~,
      update_targets~,
      store_targets~,
      command_targets=Some(publication),
      command_occurrences=Some(occurrences),
    ) {
    Err(issue) => Err(issue)
    Ok((program, source)) => {
      guard occurrences.length() == 1 else { return Err(UnsupportedEffect) }
      Ok((program, source, occurrences[0]))
    }
  }
}
