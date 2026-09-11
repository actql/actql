///|
pub(all) enum BindingIssue {
  InvalidLimits
  ForeignDeclarations
  WorkLimit
  MissingValue(String)
} derive(Eq, Debug)

///|
struct BoundIndex {
  index : Index
  values : @parameter.BoundValues
  selected : Array[@parameter.BoundParameter]
  work : Int
}

///|
/// Bind an exact declaration owner to the names selected by this index.
/// Index completeness for a Program remains the enclosing compiler's duty.
pub fn bind_values(
  index : Index,
  values : @parameter.BoundValues,
  max_work~ : Int,
) -> Result[BoundIndex, BindingIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  if !physical_equal(index.declarations, @parameter.bound_declarations(values)) {
    return Err(ForeignDeclarations)
  }
  let n = @parameter.bound_value_count(values)
  if n > max_work || index.used.length() > max_work - n {
    return Err(WorkLimit)
  }
  let names : Map[String, @parameter.BoundParameter] = Map([])
  for i in 0..<n {
    let entry = @parameter.bound_value_at(values, i).unwrap()
    names[entry.name] = entry
  }
  let selected : Array[@parameter.BoundParameter] = []
  for i in index.used {
    let declaration = @parameter.declaration_at(index.declarations, i).unwrap()
    let entry = match names.get(declaration.name) {
      Some(v) => v
      None => return Err(MissingValue(declaration.name))
    }
    selected.push(entry)
  }
  Ok({ index, values, selected, work: n + selected.length(), })
}

///|
pub fn bound_index(v : BoundIndex) -> Index {
  v.index
}

///|
pub fn bound_values(v : BoundIndex) -> @parameter.BoundValues {
  v.values
}

///|
pub fn binding_work(v : BoundIndex) -> Int {
  v.work
}

///|
pub fn used_value_count(v : BoundIndex) -> Int {
  v.selected.length()
}

///|
pub fn used_value_at(v : BoundIndex, index : Int) -> @parameter.BoundParameter? {
  v.selected.get(index)
}

///|
/// Exact Parameter Values preimage for this index's selected names. Repeated
/// occurrences select one map entry, but remain present in emit_references.
/// This is not a Program/stage/Invocation envelope or an execution wire value.
pub fn emit_used_values(
  v : BoundIndex,
  output : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(output)
  @encode.key(output, "values")
  @encode.begin_object(output)
  for entry in v.selected {
    @encode.key(output, entry.name)
    @parameter.emit_value_identity(entry, output)
  }
  @encode.end_object(output)
  @encode.key(output, "version")
  @encode.string_value(output, "actql-parameter-values/0.1")
  @encode.end_object(output)
}
