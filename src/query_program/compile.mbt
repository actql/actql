///|
pub(all) struct Input {
  relation : Array[@query.NamePart]
  name : String
  source : InputSource
  visible_fields : Array[String]
  graph_bindings : Array[GraphBinding]
}

///|
pub(all) struct GraphBinding {
  variable : @query.NamePart
  prefix : String
  fields : Array[String]
  kind : GraphBindingKind
  hops : Int
  label_field : String?
}

///|
pub(all) enum GraphBindingKind {
  NodeIdentity(String)
  Edge
  Path
}

///|
pub(all) enum InputSource {
  Captured(@wire.Cursor)
  GeneratedValues(@wire.Cursor)
  StageResult(String, String)
  // A logical producer already emitted in the current Program pipeline.
  // Only script composition can consume it; standalone query compilation
  // rejects it rather than fabricating a source or retained Stage Result.
  StepReference
}

///|
pub(all) struct Context {
  program_id : String
  stage_id : String
  stage_result : String
  result_name : String
  captured_stage : String?
  parameter_declarations : @parameters.Declarations?
  inputs : Array[Input]
  input_schemas : Array[(String, @schema.Schema)]
  // Actual admitted Catalog; schema-only attachments do not establish Source provenance.
  source_catalog : @environment.SourceRequestContracts?
  // Exact selected contract owner; this does not authorize model execution.
  model_tasks : @environment.ModelTasks?
  // Exact optional Calendar owner selected by the Host, never authored data.
  calendar_profile : @environment.SelectedCalendarProfile?
}

///|
pub(all) struct Limits {
  source : @builder.Limits
  program : @program.Limits
  max_expression_work : Int
  max_join_output_rows : Int64
  max_collection_items : Int64
  max_collection_bytes : Int64
}

///|
pub(all) enum Issue {
  InvalidContext
  // A proven authored semantic violation, distinct from a lowering gap.
  InvalidQuery
  // Actual resolved Carrier disagrees with the authored FROM GRAPH operand.
  GraphExpected(@origin.Origin?)
  // Row range aliases require an actual Relation, independently of FROM spelling.
  RangeAliasRequiresRelation
  UnknownRelation
  // The existing relation resolver exhausted the admitted inputs for this
  // exact semantic path. This witness alone is not a Source absence proof.
  UnresolvedRelation(RelationResolutionReference)
  AmbiguousRelation
  UnknownColumn
  AmbiguousColumn
  DuplicateOutput
  UnsupportedProjection
  UnsupportedGrouping
  UnsupportedAggregate
  UnsupportedHaving
  UnsupportedOrdering
  UnsupportedAnalytic
  UnsupportedSet
  UnsupportedJoin
  UnsupportedCte
  UnsupportedGraph
  UnsupportedInfer
  InferKeyLabel(InferKeyLabelIssue, @origin.Origin?)
  UnsupportedNearest
  FileListing(FileListingIssue)
  UnsupportedResult
  UnsupportedEffect
  TableWriteBinding(TableWriteBindingIssue)
  UpdateTargetBinding(UpdateTargetIssue)
  StoreTargetBinding(StoreTargetIssue)
  CommandTargetBinding(CommandTargetPublicationIssue)
  Construction(@builder.Issue)
  Expression(@expression.Diagnostic)
  // Retain the common checker's cause and authored cursor from scope probes.
  ExpressionTyping(@typing.Issue)
  // Common metadata/pipeline preparation before selecting demanded bindings.
  // The original typed cause is retained; this is not execution admission.
  BindingPreparation(BindingPreparationIssue)
  // Diagnostic-only snapshot from the exact failed preparation check. The
  // snapshot is neither a completed Program nor checking/execution authority.
  BindingPreparationSource(BindingPreparationIssue, @builder.Source)
  Admission(@program.SyntaxError)
}

///|
// Label projection follows Common's selected key. Missing compiler metadata
// remains an implementation limit; authored label conflicts are input errors.
pub(all) enum InferKeyLabelIssue {
  MissingCorrespondence
  EmptyOrAmbiguousLabel
  ReservedRole
  DuplicateLabel
  DuplicateSlot
}

///|
/// Ordinary callers retain the original error contract without diagnostic
/// construction annotations. No new admission or compilation occurs here.
pub fn issue_without_source(issue : Issue) -> Issue {
  match issue {
    BindingPreparationSource(cause, _) => BindingPreparation(cause)
    _ => issue
  }
}

///|
priv suberror Abort {
  Abort(Issue)
}

///|
priv struct Construction {
  builder : @builder.Builder
  generated : @origin.Origin
  // Published contract owner for resolving named INFER INPUT fields only.
  model_tasks : @environment.ModelTasks?
  parameter_names : ParameterNames?
  infer_labels : Bool
  infer_budget : InferPrefixBudget
}

///|
fn Construction::add(
  self : Construction,
  value : @builder.Value,
) -> @builder.Node raise Abort {
  match @builder.add(self.builder, value, self.generated) {
    Ok(node) => node
    Err(error) => raise Abort(Construction(error))
  }
}

///|
fn Construction::text(
  self : Construction,
  value : String,
) -> @builder.Node raise Abort {
  self.add(String(value))
}

///|
fn Construction::object(
  self : Construction,
  fields : Array[(String, @builder.Node)],
) -> @builder.Node raise Abort {
  self.add(
    Object(
      fields.map(pair => { key: pair.0, origin: self.generated, value: pair.1, }),
    ),
  )
}

///|
fn Construction::array(
  self : Construction,
  elements : Array[@builder.Node],
) -> @builder.Node raise Abort {
  self.add(Array(elements))
}

///|
priv struct RetainedResult {
  name : String
  port : String
  from : String
  fields : Array[String]
  terminal : Bool
  carrier_complete : Bool
  // Frontend construction metadata for closed private Effect inputs, not
  // captured-value receipts, key proofs or execution authority.
  update : (String, Array[(String, @builder.Node)])?
  store : Bool
  insert : Array[(String, @builder.Node)]?
  command : (String, String?, Array[(String, @builder.Node)])?
}

///|
fn retained_result_port(default_port : String, port : String) -> String {
  if port == default_port {
    port + "_retained"
  } else {
    port
  }
}

///|
fn retained_result_exports(
  context : Context,
  retained : Array[RetainedResult],
  keep_default? : Bool = false,
  implicit_primary? : Bool = true,
) -> Array[(String, String)]? raise Abort {
  let public = retained.filter(result => {
    result.update is None &&
    !result.store &&
    result.insert is None &&
    result.command is None
  })
  if public.is_empty() {
    return if retained.is_empty() {
      None
    } else if keep_default {
      Some([(context.result_name, context.stage_result)])
    } else {
      Some([])
    }
  }
  let retained = public
  let exports = retained.map(result => {
    (
      result.name,
      if result.terminal {
        context.stage_result
      } else {
        retained_result_port(context.stage_result, result.port)
      },
    )
  })
  if implicit_primary && !retained[retained.length() - 1].terminal {
    if retained.any(result => {
        ascii_upper(result.name) == ascii_upper(context.result_name)
      }) {
      raise Abort(DuplicateOutput)
    }
    exports.push((context.result_name, context.stage_result))
  }
  Some(exports)
}

///|
fn retained_stage_results(
  construction : Construction,
  default_port : String,
  final_result : @builder.Node,
  retained : Array[RetainedResult],
  keep_default? : Bool = false,
  implicit_primary? : Bool = true,
) -> @builder.Node raise Abort {
  let definitions = if (
      !implicit_primary &&
      !retained.any(result => {
        result.update is None &&
        !result.store &&
        result.insert is None &&
        result.command is None &&
        result.terminal
      })
    ) ||
    (
      !keep_default &&
      retained.any(result => {
        result.update is Some(_) ||
        result.store ||
        result.insert is Some(_) ||
        result.command is Some(_)
      }) &&
      retained.all(result => {
        result.update is Some(_) ||
        result.store ||
        result.insert is Some(_) ||
        result.command is Some(_)
      })
    ) {
    []
  } else {
    [(default_port, final_result)]
  }
  for result in retained {
    if !result.terminal {
      definitions.push(
        (
          retained_result_port(default_port, result.port),
          construction.object([
            ("from", construction.text(result.from)),
            (
              "fields",
              construction.array(
                result.fields.map(field => construction.text(field)),
              ),
            ),
          ]),
        ),
      )
    }
  }
  construction.object(definitions)
}

///|
fn program_root(
  construction : Construction,
  context : Context,
  stages : Array[@builder.Node],
  result_exports? : Array[(String, String)]? = None,
  staged_result_exports? : Array[(String, (String, String))]? = None,
) -> @builder.Node raise Abort {
  let entries = [
    ("version", construction.text("actql/0.1")),
    ("id", construction.text(context.program_id)),
    ("stages", construction.array(stages)),
    (
      "results",
      construction.object(
        staged_result_exports
        .unwrap_or_else(() => {
          result_exports
          .unwrap_or([(context.result_name, context.stage_result)])
          .map(pair => (pair.0, (context.stage_id, pair.1)))
        })
        .map(pair => {
          (
            pair.0,
            construction.object([
              (
                "from",
                construction.object([
                  ("stage", construction.text(pair.1.0)),
                  ("result", construction.text(pair.1.1)),
                ]),
              ),
            ]),
          )
        }),
      ),
    ),
  ]
  if context.parameter_declarations is Some(declarations) {
    let parameters : Array[(String, @builder.Node)] = []
    for declaration in @parameters.declarations(declarations) {
      let imported = match
        @builder.import_cursor(
          construction.builder,
          @parameters.declaration_source(declaration),
          construction.generated,
        ) {
        Ok(value) => value
        Err(issue) => raise Abort(Construction(issue))
      }
      parameters.push((declaration.name, imported))
    }
    entries.push(("params", construction.object(parameters)))
  }
  construction.object(entries)
}

///|
fn ascii_upper(value : String) -> String {
  let out = StringBuilder()
  for char in value {
    let code = char.to_int()
    out.write_char(
      (if code >= 97 && code <= 122 { code - 32 } else { code }).unsafe_to_char(),
    )
  }
  out.to_string()
}

///|
fn has_retained_result(query : @query.Query) -> Bool {
  for index in 0..<@query.operation_count(query) {
    if @query.operation_at(query, index) is Some(RetainResult(_)) {
      return true
    }
  }
  false
}

///|
fn same_name(left : @query.NamePart, right : @query.NamePart) -> Bool {
  ascii_upper(left.value) == ascii_upper(right.value)
}

///|
// Relation path spelling has its own rule. Quoting does not change column,
// field or alias lookup, but a quoted relation path remains exact.
fn same_relation_name(left : @query.NamePart, right : @query.NamePart) -> Bool {
  @query.same_relation_name(left, right)
}

///|
fn same_path(
  left : Array[@query.NamePart],
  right : Array[@query.NamePart],
) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for i in 0..<left.length() {
    if !same_name(left[i], right[i]) {
      return false
    }
  }
  true
}

///|
/// Installation aliases use the same relation spelling rule as query lookup.
/// A quoted relation path remains exact; field and SELECT aliases differ.
pub fn same_relation_path(
  left : Array[@query.NamePart],
  right : Array[@query.NamePart],
) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for i in 0..<left.length() {
    if !same_relation_name(left[i], right[i]) {
      return false
    }
  }
  true
}

///|
fn qualify_cached_slot(
  expression : @query.Expression,
  entries : Array[(@query.Expression, String)],
) -> String? {
  for (candidate, slot) in entries {
    if same_expression(candidate, expression) {
      return Some(slot)
    }
  }
  None
}

///|
// Classify only numeric literal atoms already folded by the expression
// lowerer. A single postorder pass avoids rescanning nested signs during
// subtree comparison. References, calls and arithmetic are never evaluated.
fn comparison_numeric_atoms(
  expression : @query.Expression,
) -> Array[Result[Double?, @expression.Issue]] {
  let atoms : Array[Result[Double?, @expression.Issue]] = []
  for index in 0..<@query.expression_node_count(expression) {
    let atom = match @query.expression_node(expression, index).unwrap().kind {
      Number(text) =>
        @expression.numeric_literal(text).map(value => Some(value))
      Parenthesized(child) | Unary("+", child) => atoms[child]
      Unary("-", child) =>
        // Signed source zero normalizes to the canonical Number zero.
        match atoms[child] {
          Ok(Some(value)) => Ok(Some(if value == 0.0 { 0.0 } else { -value }))
          other => other
        }
      _ => Ok(None)
    }
    atoms.push(atom)
  }
  atoms
}

///|
// Compare semantic source trees, ignoring grouping parentheses and spans.
// Indices are local to each expression owner and cannot be compared directly.
fn same_expression(
  left : @query.Expression,
  right : @query.Expression,
  references? : (Array[@query.NamePart], Array[@query.NamePart]) -> Bool = same_path,
  nodes? : (@query.Expression, Int, @query.Expression, Int) -> Bool? = (
    _,
    _,
    _,
    _,
  ) => None,
) -> Bool {
  let left_atoms = comparison_numeric_atoms(left)
  let right_atoms = comparison_numeric_atoms(right)
  let pending = [(@query.expression_root(left), @query.expression_root(right))]
  while pending.pop() is Some((a_index, b_index)) {
    if nodes(left, a_index, right, b_index) is Some(equal) {
      if !equal {
        return false
      }
      continue
    }
    match (left_atoms[a_index], right_atoms[b_index]) {
      (Ok(Some(a)), Ok(Some(b))) => {
        if a != b {
          return false
        }
        continue
      }
      (Err(_), _) | (_, Err(_)) => return false
      _ => ()
    }
    let a = @query.expression_node(left, a_index).unwrap().kind
    let b = @query.expression_node(right, b_index).unwrap().kind
    if two_operand_coalesce_shape(left, a_index) is Some(a_items) &&
      two_operand_coalesce_shape(right, b_index) is Some(b_items) {
      for index in 0..<a_items.length() {
        pending.push((a_items[index], b_items[index]))
      }
      continue
    }
    if negated_is_predicate_shape(left, a_index) is Some((a_name, a_items)) &&
      negated_is_predicate_shape(right, b_index) is Some((b_name, b_items)) {
      if a_name != b_name || a_items.length() != b_items.length() {
        return false
      }
      for index in 0..<a_items.length() {
        pending.push((a_items[index], b_items[index]))
      }
      continue
    }
    if literal_membership_shape(left, a_index)
      is Some((a_name, a_value, a_items)) &&
      literal_membership_shape(right, b_index)
      is Some((b_name, b_value, b_items)) {
      if a_name != b_name || a_items.length() != b_items.length() {
        return false
      }
      pending.push((a_value, b_value))
      for index in 0..<a_items.length() {
        pending.push((a_items[index], b_items[index]))
      }
      continue
    }
    if strict_concat_pair(a) is Some((a_left, a_right)) &&
      strict_concat_pair(b) is Some((b_left, b_right)) {
      // These two spellings already lower to the same ordered two-operand
      // concat_strict node. Keep clause-aware receiver checks on each child;
      // neither a legacy CONCAT nor a differently shaped call is equivalent.
      pending.push((a_left, b_left))
      pending.push((a_right, b_right))
      continue
    }
    match (a, b) {
      (Parenthesized(child), _) => pending.push((child, b_index))
      (_, Parenthesized(child)) => pending.push((a_index, child))
      (Number(x), Number(y)) =>
        // Compare the admitted Number values, not decimal/exponent spelling.
        // Failed admission never proves equivalence or hides an invalid token.
        match (@expression.numeric_literal(x), @expression.numeric_literal(y)) {
          (Ok(a), Ok(b)) => if a != b { return false }
          _ => return false
        }
      (ParameterReference(x), ParameterReference(y)) =>
        if ascii_upper(x) != ascii_upper(y) {
          return false
        }
      (Reference(x), Reference(y)) => if !references(x, y) { return false }
      (Call(x, ax), Call(y, ay)) => {
        if (
            !same_path(x, y) &&
            !@expression.same_scalar_function(x, y, arity=Some(ax.length()))
          ) ||
          ax.length() != ay.length() {
          return false
        }
        for i in 0..<ax.length() {
          pending.push((ax[i], ay[i]))
        }
      }
      (ArrayOffset(av, ai, ax), ArrayOffset(bv, bi, bx)) => {
        if ax != bx {
          return false
        }
        pending.push((av, bv))
        pending.push((ai, bi))
      }
      (StructConstructor(ax), StructConstructor(ay)) => {
        if ax.length() != ay.length() {
          return false
        }
        for i in 0..<ax.length() {
          if !same_name(ax[i].0, ay[i].0) {
            return false
          }
          pending.push((ax[i].1, ay[i].1))
        }
      }
      (ArrayConstructor(ax, tx), ArrayConstructor(ay, ty)) => {
        if tx != ty || ax.length() != ay.length() {
          return false
        }
        for i in 0..<ax.length() {
          pending.push((ax[i], ay[i]))
        }
      }
      (Interval(ax, ux), Interval(ay, uy)) => {
        if ux != uy {
          return false
        }
        pending.push((ax, ay))
      }
      (Unary(x, child_a), Unary(y, child_b)) => {
        if x != y {
          return false
        }
        pending.push((child_a, child_b))
      }
      (Binary(x, left_a, right_a), Binary(y, left_b, right_b)) => {
        if x != y && !@expression.same_binary_operator(x, y) {
          return false
        }
        pending.push((left_a, left_b))
        pending.push((right_a, right_b))
      }
      (Predicate(x, ax), Predicate(y, ay)) => {
        if x != y || ax.length() != ay.length() {
          return false
        }
        for i in 0..<ax.length() {
          pending.push((ax[i], ay[i]))
        }
      }
      (SearchedCase(ax, a_else), SearchedCase(ay, b_else)) => {
        if ax.length() != ay.length() {
          return false
        }
        for i in 0..<ax.length() {
          pending.push((ax[i].0, ay[i].0))
          pending.push((ax[i].1, ay[i].1))
        }
        pending.push((a_else, b_else))
      }
      (Cast(a_child, a_type), Cast(b_child, b_type)) => {
        if a_type != b_type {
          return false
        }
        pending.push((a_child, b_child))
      }
      (Property(a_child, a_name), Property(b_child, b_name)) => {
        if !same_name(a_name, b_name) {
          return false
        }
        pending.push((a_child, b_child))
      }
      _ => if a != b { return false }
    }
  }
  true
}

///|
// Compare receivers in their own clause scopes before matching property members.
fn same_group_reference_in_scopes(
  left : Array[@query.NamePart],
  right : Array[@query.NamePart],
  resolve_left : (Array[@query.NamePart]) -> String?,
  resolve_right : (Array[@query.NamePart]) -> String?,
) -> Bool {
  let prefix = fn(
    path : Array[@query.NamePart],
    resolve : (Array[@query.NamePart]) -> String?,
  ) -> (String, Int)? {
    let mut length = path.length()
    while length > 0 {
      if resolve(path[:length].to_owned()) is Some(slot) {
        return Some((slot, length))
      }
      length -= 1
    }
    None
  }
  match (prefix(left, resolve_left), prefix(right, resolve_right)) {
    (Some((a, a_length)), Some((b, b_length))) => {
      if a != b || left.length() - a_length != right.length() - b_length {
        return false
      }
      for index in 0..<(left.length() - a_length) {
        if !same_name(left[a_length + index], right[b_length + index]) {
          return false
        }
      }
      true
    }
    _ => false
  }
}

///|
fn selected_input(
  query : @query.Query,
  context : Context,
  limits : Limits,
) -> Input raise Abort {
  if @query.relation(query).is_empty() {
    if @query.bound_source(query) is Some(current) {
      // An inline Carrier bridge retains its actual current producer. Keep
      // that private anchor out of authored peer and range-name resolution.
      match
        context.inputs
        .filter(input => {
          input.source is StepReference && input.name == current.value
        })
        .get(0) {
        Some(input) => return input
        None => raise Abort(UnknownRelation)
      }
    }
    source_free_input(query, limits)
  } else {
    let input = selected_relation(@query.relation(query), context)
    match @query.file_list_selector(query) {
      None => input
      Some(selector) =>
        lower_file_listing_input(query, selector, input, context, limits)
    }
  }
}

///|
fn selected_relation(
  relation : Array[@query.NamePart],
  context : Context,
) -> Input raise Abort {
  resolve_relation_input(relation, context.inputs)
}

///|
// WITH producer aliases and published relation paths retain their
// respective rules at every query and constructor entry.
fn input_relation_matches(
  relation : Array[@query.NamePart],
  input : Input,
) -> Bool {
  if input.source is StepReference &&
    relation.length() == 1 &&
    input.relation.length() == 1 {
    same_name(relation[0], input.relation[0])
  } else {
    same_relation_path(relation, input.relation)
  }
}

///|
fn resolve_relation_input(
  relation : Array[@query.NamePart],
  inputs : Array[Input],
) -> Input raise Abort {
  let mut found : Input? = None
  for input in inputs {
    if input_relation_matches(relation, input) {
      if found is Some(_) {
        raise Abort(AmbiguousRelation)
      }
      found = Some(input)
    }
  }
  match found {
    Some(input) => input
    None => raise Abort(unresolved_relation_issue(relation))
  }
}

///|
fn columns(input : Input) -> Array[String] raise Abort {
  if input.source is StageResult(_, _) || input.source is StepReference {
    return input.visible_fields.copy()
  }
  let source = match input.source {
    Captured(declaration) => declaration
    GeneratedValues(step) => {
      let step = match @wire.open_object(step) {
        Ok(object) => object
        Err(_) => raise Abort(InvalidContext)
      }
      let name = match @wire.lookup(step, "as") {
        Some(name) =>
          match @wire.text(name) {
            Ok(value) => value
            Err(_) => raise Abort(InvalidContext)
          }
        None => raise Abort(InvalidContext)
      }
      if name != input.name {
        raise Abort(InvalidContext)
      }
      match @wire.lookup(step, "values") {
        Some(values) => values
        None => raise Abort(InvalidContext)
      }
    }
    StageResult(_, _) | StepReference => raise Abort(InvalidContext)
  }
  let declaration = match @wire.open_object(source) {
    Ok(object) => object
    Err(_) => raise Abort(InvalidContext)
  }
  match @wire.lookup(declaration, "schema") {
    Some(schema) => {
      let actual = match @wire.object_field_names(schema) {
        Ok(fields) => fields
        Err(_) => raise Abort(InvalidContext)
      }
      if actual.length() != input.visible_fields.length() {
        raise Abort(InvalidContext)
      }
      for i in 0..<actual.length() {
        if actual[i] != input.visible_fields[i] {
          raise Abort(InvalidContext)
        }
      }
      actual
    }
    None => input.visible_fields.copy()
  }
}

///|
fn resolve_column(
  path : Array[@query.NamePart],
  query : @query.Query,
  input : Input,
  fields : Array[String],
) -> String? {
  if path.length() == 0 || path.length() > 2 {
    return None
  }
  if path.length() == 1 &&
    input.graph_bindings.is_empty() &&
    !@query.relation(query).is_empty() &&
    same_name(path[0], query_range_name(query)) {
    return None
  }
  if !input.graph_bindings.is_empty() {
    let mut found : String? = None
    for binding in input.graph_bindings {
      if path.length() == 2 && !same_name(path[0], binding.variable) {
        continue
      }
      for field in binding.fields {
        if same_name(path.last().unwrap(), { value: field, quoted: false, }) {
          let slot = binding.prefix + field
          if fields.contains(slot) {
            if found is Some(_) {
              return None
            }
            found = Some(slot)
          }
        }
      }
    }
    if found is Some(_) || path.length() == 2 {
      return found
    }
  }
  if path.length() == 2 {
    let qualifier = query_range_name(query)
    if !same_name(path[0], qualifier) {
      return None
    }
  }
  let mut found : String? = None
  let name = path[path.length() - 1]
  for field in fields {
    if same_name(name, { value: field, quoted: false, }) {
      if found is Some(_) {
        return None
      }
      found = Some(field)
    }
  }
  ignore(input)
  found
}

///|
fn ambiguous_column(
  path : Array[@query.NamePart],
  query : @query.Query,
  input : Input,
  fields : Array[String],
) -> Bool {
  if path.length() == 0 || path.length() > 2 {
    return false
  }
  if path.length() == 1 &&
    input.graph_bindings.is_empty() &&
    !@query.relation(query).is_empty() &&
    same_name(path[0], query_range_name(query)) {
    return false
  }
  if !input.graph_bindings.is_empty() {
    let mut count = 0
    for binding in input.graph_bindings {
      if path.length() == 2 && !same_name(path[0], binding.variable) {
        continue
      }
      for field in binding.fields {
        if same_name(path.last().unwrap(), { value: field, quoted: false, }) &&
          fields.contains(binding.prefix + field) {
          count += 1
        }
      }
    }
    if count > 1 {
      return true
    }
    if path.length() == 2 {
      return false
    }
  }
  if path.length() == 2 {
    let qualifier = query_range_name(query)
    if !same_name(path[0], qualifier) {
      return false
    }
  }
  let mut seen = false
  for field in fields {
    if same_name(path.last().unwrap(), { value: field, quoted: false, }) {
      if seen {
        return true
      }
      seen = true
    }
  }
  false
}

///|
fn query_range_name(query : @query.Query) -> @query.NamePart {
  match @query.graph_query(query) {
    Some(graph) =>
      match graph.pattern {
        Some(pattern) if pattern.nodes.length() == 1 =>
          match pattern.nodes[0].variable {
            Some(variable) => return variable
            None => ()
          }
        _ => ()
      }
    None => ()
  }
  @query.relation_alias(query).unwrap_or(
    @query.relation(query).last().unwrap_or({ value: "", quoted: false, }),
  )
}

///|
// Pipe's visible names and range aliases refer to immutable physical slots.
// SET and DROP may change visibility without changing an older alias snapshot.
fn pipe_slot(
  path : Array[@query.NamePart],
  visible : Array[(String, String)],
  ranges : Array[(@query.NamePart, Array[(String, String)])],
) -> String? {
  if path.length() == 0 || path.length() > 2 {
    return None
  }
  let mut scope = visible
  if path.length() == 2 {
    let mut found = false
    for range in ranges {
      if same_name(path[0], range.0) {
        if found {
          return None
        }
        scope = range.1
        found = true
      }
    }
    if !found {
      return None
    }
  }
  let mut selected : String? = None
  for entry in scope {
    if same_name(path[path.length() - 1], { value: entry.0, quoted: false, }) {
      if selected is Some(_) {
        return None
      }
      selected = Some(entry.1)
    }
  }
  selected
}

///|
fn append_pipe_expression(
  construction : Construction,
  expression : @query.Expression,
  visible : Array[(String, String)],
  ranges : Array[(@query.NamePart, Array[(String, String)])],
  max_work : Int,
  value_ranges? : Array[@query.NamePart] = [],
) -> @builder.Node raise Abort {
  append_pipe_range_expression(
    construction,
    expression,
    visible,
    ranges,
    max_work,
    value_ranges~,
  )
}

///|
fn pipe_name_exists(
  entries : Array[(String, String)],
  name : @query.NamePart,
) -> Bool {
  entries.any(entry => same_name(name, { value: entry.0, quoted: false, }))
}

///|
fn analytic_output_slot(
  name : String,
  outputs : Array[(String, String)],
) -> String? {
  for output in outputs {
    if output.0 == name {
      return Some(output.1)
    }
  }
  None
}

///|
fn pipe_physical_name(physical : Array[String], prefix : String) -> String {
  let mut index = physical.length()
  let mut name = prefix + index.to_string()
  while physical.any(field => ascii_upper(field) == ascii_upper(name)) {
    index += 1
    name = prefix + index.to_string()
  }
  name
}

///|
// One authored-name rule for SELECT output and its GROUP/HAVING alias tables.
// Anonymous expressions do not gain a synthetic alias or an input binding.
fn projection_alias(projection : @query.Projection) -> @query.NamePart? {
  match projection.name {
    Some(name) => Some(name)
    None =>
      match projection.expression {
        Some(expression) =>
          match
            @query.expression_node(
              expression,
              @query.expression_root(expression),
            ).unwrap().kind {
            Reference(path) => path.last()
            Property(_, name) => Some(name)
            _ => None
          }
        None => None
      }
  }
}

///|
fn projection_output_name(projection : @query.Projection) -> String raise Abort {
  match projection_alias(projection) {
    Some(name) => name.value
    None => raise Abort(UnsupportedProjection)
  }
}

///|
fn output_name(
  projection : @query.Projection,
  query : @query.Query,
  input : Input,
  fields : Array[String],
  row_ranges? : Array[(@query.NamePart, Array[(String, String)])]? = None,
) -> String raise Abort {
  let name = projection_output_name(projection)
  if projection.name is None &&
    projection.expression is Some(expression) &&
    @query.expression_node(expression, @query.expression_root(expression)).unwrap().kind
    is Reference(path) {
    // Keep the ordinary resolver, including its ambiguity and prefix rules.
    // An unaliased projection retains the same authored expression occurrence
    // as an aliased projection; no source-text search supplies this origin.
    let mut length = path.length()
    while length > 0 {
      let prefix = path[:length].to_owned()
      if resolve_column(prefix, query, input, fields) is Some(_) {
        return name
      }
      if ambiguous_column(prefix, query, input, fields) {
        raise Abort(AmbiguousColumn)
      }
      length -= 1
    }
    let ranges = row_ranges.unwrap_or(
      if @query.relation(query).is_empty() {
        []
      } else {
        [(query_range_name(query), fields.map(field => (field, field)))]
      },
    )
    if row_reference_fields(
        path,
        name => ambiguous_column([name], query, input, fields),
        ranges,
      )
      is Some(_) {
      return name
    }
    if @query.expression_origin(expression, @query.expression_root(expression))
      is Some(origin) {
      raise Abort(
        Expression({
          issue: @expression.UnknownReference,
          origin: Some(origin),
        }),
      )
    }
    raise Abort(UnknownColumn)
  }
  name
}

///|
fn append_expression(
  construction : Construction,
  expression : @query.Expression,
  query : @query.Query,
  input : Input,
  fields : Array[String],
  max_work : Int,
  private_columns? : Array[(String, String)] = [],
) -> @builder.Node raise Abort {
  let resolve = fn(path : Array[@query.NamePart]) -> String? {
    if path.length() == 1 {
      for (name, slot) in private_columns {
        if path[0].value == name {
          return Some(slot)
        }
      }
    }
    resolve_column(path, query, input, fields)
  }
  let (bound, slots, remaining) = bind_range_property_expression(
    expression,
    resolve,
    name => {
      resolve([name]) is Some(_) ||
      ambiguous_column([name], query, input, fields)
    },
    max_work,
  )
  let bound_resolve = fn(path : Array[@query.NamePart]) -> String? {
    if path.length() == 1 {
      for (name, slot) in slots {
        if path[0].value == name {
          return Some(slot)
        }
      }
    }
    resolve(path)
  }
  let lowered = if input.graph_bindings.is_empty() {
    @expression.append_with_properties(
      bound,
      bound_resolve,
      construction.builder,
      remaining,
      resolve_parameter=construction.parameter_resolver(),
      resolve_row=Some(path => {
        if @query.relation(query).is_empty() {
          return None
        }
        row_reference_fields(
          path,
          name => {
            resolve([name]) is Some(_) ||
            ambiguous_column([name], query, input, fields)
          },
          [(query_range_name(query), fields.map(field => (field, field)))],
        )
      }),
    )
  } else {
    @expression.append_with_macros(
      bound,
      bound_resolve,
      (path, argument) => {
        graph_macro_value(path, argument, input.graph_bindings)
      },
      construction.builder,
      remaining,
      resolve_properties=true,
      resolve_parameter=construction.parameter_resolver(),
    )
  }
  match lowered {
    Ok(node) => node
    Err(error) => {
      for index in 0..<@query.expression_node_count(expression) {
        if @query.expression_node(expression, index).unwrap().kind
          is Reference(path) &&
          ambiguous_column(path, query, input, fields) {
          raise Abort(AmbiguousColumn)
        }
      }
      raise Abort(Expression(error))
    }
  }
}

///|
fn order_output_slot(
  path : Array[@query.NamePart],
  selected : Array[(String, String)],
) -> String? {
  if path.length() == 1 {
    for binding in selected {
      if same_name(path[0], { value: binding.0, quoted: false, }) {
        return Some(binding.1)
      }
    }
  }
  None
}

///|
// Match append_with_properties: the longest resolved prefix is the receiver,
// and the remaining path is property access. Both the slot and prefix length
// participate in reference identity; a range is not an object property.
fn order_reference_identity(
  path : Array[@query.NamePart],
  resolve : (Array[@query.NamePart]) -> String?,
) -> (String, Int)? {
  let mut length = path.length()
  while length > 0 {
    match resolve(path[:length].to_owned()) {
      Some(slot) => return Some((slot, length))
      None => length -= 1
    }
  }
  None
}

///|
// Expression equality only permits reuse when ORDER has the same reference
// meaning as SELECT, including the receiver of a nested property access.
fn reusable_order_expression(
  expression : @query.Expression,
  selected : Array[(@query.Expression, String)],
  aliases : Array[(String, String)],
  input_slot : (Array[@query.NamePart]) -> String?,
) -> String? {
  for path in join_reference_paths(expression) {
    let selected_reference = order_reference_identity(path, input_slot)
    let order_reference = order_reference_identity(path, prefix => {
      match order_output_slot(prefix, aliases) {
        Some(slot) => Some(slot)
        None =>
          if prefix.length() > 1 &&
            order_output_slot([prefix[0]], aliases) is Some(_) {
            None
          } else {
            input_slot(prefix)
          }
      }
    })
    if selected_reference is None || selected_reference != order_reference {
      return None
    }
  }
  for (value, slot) in selected {
    // Keep explicit properties separate until their receivers resolve, just
    // as the expression lowerer does. Different AST spellings can denote
    // the same evaluated value; a range column and an object member cannot.
    if same_group_expression_in_scopes(
        expression, value, input_slot, input_slot,
      ) {
      return Some(slot)
    }
  }
  None
}

///|
fn order_expression_slot(
  path : Array[@query.NamePart],
  query : @query.Query,
  input : Input,
  fields : Array[String],
  selected : Array[(String, String)],
) -> String? {
  if path.length() > 1 && order_output_slot([path[0]], selected) is Some(_) {
    return None
  }
  match order_output_slot(path, selected) {
    Some(slot) => Some(slot)
    None => resolve_column(path, query, input, fields)
  }
}

///|
fn append_order_expression(
  construction : Construction,
  expression : @query.Expression,
  query : @query.Query,
  input : Input,
  fields : Array[String],
  selected : Array[(String, String)],
  max_work : Int,
) -> @builder.Node raise Abort {
  let resolve = path => {
    order_expression_slot(path, query, input, fields, selected)
  }
  let lowered = if input.graph_bindings.is_empty() {
    @expression.append_with_properties(
      expression,
      resolve,
      construction.builder,
      max_work,
      resolve_parameter=construction.parameter_resolver(),
      resolve_row=Some(path => {
        if @query.relation(query).is_empty() {
          return None
        }
        row_reference_fields(
          path,
          name => {
            resolve([name]) is Some(_) ||
            ambiguous_column([name], query, input, fields)
          },
          [(query_range_name(query), fields.map(field => (field, field)))],
        )
      }),
    )
  } else {
    @expression.append_with_macros(
      expression,
      resolve,
      (path, argument) => {
        graph_macro_value(path, argument, input.graph_bindings)
      },
      construction.builder,
      max_work,
      resolve_parameter=construction.parameter_resolver(),
    )
  }
  match lowered {
    Ok(node) => node
    Err(error) => {
      for index in 0..<@query.expression_node_count(expression) {
        if @query.expression_node(expression, index).unwrap().kind
          is Reference(path) &&
          order_expression_slot(path, query, input, fields, selected) is None &&
          ambiguous_column(path, query, input, fields) {
          raise Abort(AmbiguousColumn)
        }
      }
      raise Abort(Expression(error))
    }
  }
}

///|
fn selected_projections(query : @query.Query) -> Array[@query.Projection] {
  for index in 0..<@query.operation_count(query) {
    match @query.operation_at(query, index) {
      Some(Select(projections, _)) => return projections
      _ => ()
    }
  }
  []
}

///|
// SQL's parser records ORDER-only calls as private Group projections. Their
// references occur in ORDER, never as authored SELECT aliases or inputs.
// SELECT ownership must use the same expanded replacement projections as Group.
fn order_aggregate_calls(
  query : @query.Query,
  projections : Array[@query.Projection],
  selected : Array[@query.Projection],
) -> Array[(@query.NamePart, @query.AggregateCall)] {
  let references : Array[Array[@query.NamePart]] = []
  for index in 0..<@query.operation_count(query) {
    match @query.operation_at(query, index) {
      Some(Order(terms)) =>
        for term in terms {
          references.append(join_reference_paths(term.expression))
        }
      Some(OrderAnalytic(windows, true)) =>
        for projection in windows {
          guard projection.analytic is Some(call) else { continue }
          for expression in call.window.partition_by {
            references.append(join_reference_paths(expression))
          }
          for term in call.window.order_by {
            references.append(join_reference_paths(term.expression))
          }
          if call.expression is Some(expression) {
            references.append(join_reference_paths(expression))
          }
          if call.aggregate is Some(aggregate) &&
            aggregate.argument is Some(expression) {
            references.append(join_reference_paths(expression))
          }
        }
      _ => ()
    }
  }
  projections.filter_map(projection => {
    guard projection.name is Some(name) &&
      projection.aggregate is Some(call) &&
      !selected.any(item => {
        item.aggregate is Some(_) &&
        item.name is Some(selected_name) &&
        same_name(selected_name, name)
      }) &&
      references.any(path => path.length() == 1 && path[0] == name) else {
      return None
    }
    Some((name, call))
  })
}

///|
// Public aliases and lowering share this closed operation-name mapping.
// COUNTIF's DISTINCT rewrite remains a separate argument/filter contract.
fn aggregate_common_function(name : String) -> String? {
  match name {
    "COUNT" => Some("count")
    "COUNTIF" => Some("count_if")
    "SUM" => Some("sum")
    "AVG" => Some("avg")
    "MIN" => Some("min")
    "MAX" => Some("max")
    "VAR_POP" => Some("var_pop")
    "VAR_SAMP" | "VARIANCE" => Some("var_samp")
    "STDDEV_POP" => Some("stddev_pop")
    "STDDEV_SAMP" | "STDDEV" => Some("stddev_samp")
    "ARRAY_AGG" => Some("array_agg")
    "STRING_AGG" => Some("string_agg")
    _ => None
  }
}

///|
fn same_aggregate_call(
  left : @query.AggregateCall,
  right : @query.AggregateCall,
  left_resolve : (Array[@query.NamePart]) -> String?,
  right_resolve : (Array[@query.NamePart]) -> String?,
) -> Bool {
  guard aggregate_common_function(left.function_name) is Some(left_function) &&
    aggregate_common_function(right.function_name) is Some(right_function) else {
    return false
  }
  if left_function != right_function ||
    left.distinct != right.distinct ||
    left.delimiter != right.delimiter ||
    left.order_by.length() != right.order_by.length() {
    return false
  }
  let same = (a, b) => {
    // Clause scopes resolve the receiver before comparing static members.
    // Equivalent Property/Reference AST spellings may reuse one aggregate;
    // an output alias and the original input remain different value slots.
    same_group_expression_in_scopes(a, b, left_resolve, right_resolve)
  }
  match (left.argument, right.argument) {
    (None, None) => ()
    (Some(a), Some(b)) => if !same(a, b) { return false }
    _ => return false
  }
  match (left.filter, right.filter) {
    (None, None) => ()
    (Some(a), Some(b)) => if !same(a, b) { return false }
    _ => return false
  }
  for index in 0..<left.order_by.length() {
    let a = left.order_by[index]
    let b = right.order_by[index]
    if a.direction != b.direction ||
      a.nulls != b.nulls ||
      !same(a.expression, b.expression) {
      return false
    }
  }
  true
}

///|
fn group_key_expression(
  key : @query.Expression,
  projections : Array[@query.Projection],
) -> @query.Expression raise Abort {
  let mut root_index = @query.expression_root(key)
  while @query.expression_node(key, root_index).unwrap().kind
        is Parenthesized(child) {
    root_index = child
  }
  let root = @query.expression_node(key, root_index).unwrap()
  if root.kind is Number(_) {
    raise Abort(UnsupportedGrouping)
  }
  guard root.kind is Reference(path) && path.length() == 1 else { return key }
  let mut matched : @query.Expression? = None
  for projection in projections {
    match projection_alias(projection) {
      Some(name) if same_name(name, path[0]) => {
        if matched is Some(_) {
          raise Abort(InvalidQuery)
        }
        if projection.aggregate is Some(_) || projection.analytic is Some(_) {
          raise Abort(UnsupportedGrouping)
        }
        matched = projection.expression
      }
      _ => ()
    }
  }
  match matched {
    Some(expression) => expression
    None => key
  }
}

///|
fn lower_aggregate_resolved(
  construction : Construction,
  call : @query.AggregateCall,
  resolve : (Array[@query.NamePart]) -> String?,
  max_work : Int,
  max_collection_items : Int64,
  max_collection_bytes : Int64,
  order_fields? : Array[String]? = None,
  analytic? : Bool = false,
) -> @builder.Node raise Abort {
  let conditional_count = call.function_name == "COUNTIF" &&
    call.distinct &&
    !analytic
  let name = match aggregate_common_function(call.function_name) {
    Some(name) => if conditional_count { "count" } else { name }
    None => raise Abort(UnsupportedAggregate)
  }
  let entries : Array[(String, @builder.Node)] = [
    ("fn", construction.text(name)),
  ]
  match call.argument {
    Some(argument) => {
      let mut root_index = @query.expression_root(argument)
      while @query.expression_node(argument, root_index).unwrap().kind
            is Parenthesized(child) {
        root_index = child
      }
      let root = @query.expression_node(argument, root_index).unwrap()
      let field = if conditional_count {
        None
      } else {
        match root.kind {
          Reference(path) => resolve(path)
          _ => None
        }
      }
      match field {
        Some(field) => entries.push(("field", construction.text(field)))
        None =>
          entries.push(
            (
              "expr",
              {
                let argument = match
                  @expression.append_with_properties(
                    argument,
                    resolve,
                    construction.builder,
                    max_work,
                    resolve_parameter=construction.parameter_resolver(),
                  ) {
                  Ok(value) => value
                  Err(error) => raise Abort(Expression(error))
                }
                // TRUE is the only qualifying distinct Boolean observation.
                // The existing conditional and COUNT owners exclude FALSE/NULL
                // without evaluating the authored predicate a second time.
                if conditional_count {
                  construction.object([
                    (
                      "if",
                      construction.array([
                        argument,
                        construction.object([
                          ("literal", construction.add(Bool(true))),
                        ]),
                        construction.object([
                          ("literal", construction.add(Null)),
                        ]),
                      ]),
                    ),
                  ])
                } else {
                  argument
                }
              },
            ),
          )
      }
    }
    None =>
      if name != "count" || call.distinct {
        raise Abort(UnsupportedAggregate)
      }
  }
  match call.filter {
    Some(filter) =>
      entries.push(
        (
          "filter",
          match
            @expression.append_with_properties(
              filter,
              resolve,
              construction.builder,
              max_work,
              resolve_parameter=construction.parameter_resolver(),
            ) {
            Ok(value) => value
            Err(error) => raise Abort(Expression(error))
          },
        ),
      )
    None => ()
  }
  // Grouped extrema are unchanged by duplicate observations, including NULL
  // exclusion and empty input. The common MIN/MAX operation therefore needs
  // no distinct modifier or separate deduplication/evaluation pass.
  if call.distinct && !(!analytic && (name == "min" || name == "max")) {
    entries.push(("distinct", construction.add(Bool(true))))
  }
  if name == "array_agg" || name == "string_agg" {
    let bound = if name == "array_agg" {
      max_collection_items
    } else {
      max_collection_bytes
    }
    if bound < 1L || bound > 9007199254740991L {
      raise Abort(UnsupportedAggregate)
    }
    entries.push(
      (
        if name == "array_agg" {
          "max_items"
        } else {
          "max_bytes"
        },
        construction.add(Number(bound.to_double())),
      ),
    )
    let order : Array[@builder.Node] = []
    for index in 0..<call.order_by.length() {
      let term = call.order_by[index]
      let root = @query.expression_node(
        term.expression,
        @query.expression_root(term.expression),
      ).unwrap()
      let field = match order_fields {
        Some(fields) => fields[index]
        None => {
          guard root.kind is Reference(path) else {
            raise Abort(UnsupportedAggregate)
          }
          match resolve(path) {
            Some(field) => field
            None => raise Abort(UnknownColumn)
          }
        }
      }
      order.push(
        construction.object([
          ("field", construction.text(field)),
          ("dir", construction.text(term.direction)),
          ("nulls", construction.text(term.nulls)),
        ]),
      )
      if call.distinct {
        guard call.argument is Some(argument) &&
          aggregate_order_matches_argument(argument, term.expression, resolve) else {
          raise Abort(UnsupportedAggregate)
        }
      }
    }
    if !analytic {
      entries.push(("order_by", construction.array(order)))
    }
  }
  match call.delimiter {
    Some(delimiter) => entries.push(("delimiter", construction.text(delimiter)))
    None => ()
  }
  construction.object(entries)
}

///|
fn lower_aggregate(
  construction : Construction,
  call : @query.AggregateCall,
  query : @query.Query,
  input : Input,
  fields : Array[String],
  max_work : Int,
  max_collection_items : Int64,
  max_collection_bytes : Int64,
  order_fields? : Array[String]? = None,
) -> @builder.Node raise Abort {
  lower_aggregate_resolved(
    construction,
    call,
    path => resolve_column(path, query, input, fields),
    max_work,
    max_collection_items,
    max_collection_bytes,
    order_fields~,
  )
}

///|
fn analytic_boundary(
  construction : Construction,
  boundary : @query.FrameBoundary,
) -> @builder.Node raise Abort {
  match boundary {
    UnboundedPreceding => construction.text("unbounded_preceding")
    CurrentRow => construction.text("current_row")
    UnboundedFollowing => construction.text("unbounded_following")
    Preceding(0L) | Following(0L) => construction.text("current_row")
    Preceding(distance) =>
      construction.object([
        ("preceding", construction.add(Number(distance.to_double()))),
      ])
    Following(distance) =>
      construction.object([
        ("following", construction.add(Number(distance.to_double()))),
      ])
    PrecedingParameter(name) =>
      construction.object([
        (
          "preceding",
          construction.object([("$param", construction.parameter_text(name))]),
        ),
      ])
    FollowingParameter(name) =>
      construction.object([
        (
          "following",
          construction.object([("$param", construction.parameter_text(name))]),
        ),
      ])
  }
}

///|
// Zero physical distance denotes the current row. Validate authored boundary
// categories before that projection: zero cannot make an illegal interval
// spelling legal. Parameter distances remain with the common positive domain.
fn validate_literal_zero_frame(
  frame : @query.AnalyticFrame,
) -> Unit raise Abort {
  let zero = frame.start is Preceding(0L) ||
    frame.start is Following(0L) ||
    frame.end is Preceding(0L) ||
    frame.end is Following(0L)
  if !zero {
    return
  }
  let category = fn(boundary : @query.FrameBoundary) -> Int {
    match boundary {
      UnboundedPreceding => 0
      Preceding(_) | PrecedingParameter(_) => 1
      CurrentRow => 2
      Following(_) | FollowingParameter(_) => 3
      UnboundedFollowing => 4
    }
  }
  if category(frame.start) > category(frame.end) ||
    frame.start is UnboundedFollowing ||
    frame.end is UnboundedPreceding {
    raise Abort(InvalidQuery)
  }
}

///|
fn lower_analytic_call(
  construction : Construction,
  call : @query.AnalyticCall,
  resolve : (Array[@query.NamePart]) -> String?,
  max_work : Int,
  max_collection_bytes : Int64,
) -> @builder.Node raise Abort {
  if call.window.frame is Some(frame) {
    validate_literal_zero_frame(frame)
  }
  match call.aggregate {
    Some(aggregate) => {
      // The selected SQL analytic contract forbids DISTINCT with window ORDER
      // BY or an authored frame. Default/unordered DISTINCT needs a separate
      // common window connection; never turn it into this explicit ROWS path.
      if aggregate.distinct {
        raise Abort(UnsupportedAnalytic)
      }
      if call.window.frame is None {
        raise Abort(UnsupportedAnalytic)
      }
      if ![
          "COUNT", "COUNTIF", "SUM", "AVG", "MIN", "MAX", "VAR_POP", "VAR_SAMP",
          "VARIANCE", "STDDEV_POP", "STDDEV_SAMP", "STDDEV", "STRING_AGG",
        ].contains(aggregate.function_name) {
        raise Abort(UnsupportedAnalytic)
      }
      if aggregate.function_name == "STRING_AGG" &&
        (
          aggregate.distinct ||
          aggregate.filter is Some(_) ||
          !aggregate.order_by.is_empty()
        ) {
        raise Abort(UnsupportedAnalytic)
      }
      lower_aggregate_resolved(
        construction,
        aggregate,
        resolve,
        max_work,
        0L,
        max_collection_bytes,
        analytic=true,
      )
    }
    None => {
      let expression = call.expression.unwrap()
      let root = @query.expression_node(
        expression,
        @query.expression_root(expression),
      ).unwrap()
      guard root.kind is Call(path, arguments) && path.length() == 1 else {
        raise Abort(UnsupportedAnalytic)
      }
      let name = ascii_upper(path[0].value)
      let needs_frame = name == "FIRST_VALUE" || name == "LAST_VALUE"
      if needs_frame != (call.window.frame is Some(_)) {
        raise Abort(UnsupportedAnalytic)
      }
      let wire_name = match name {
        "ROW_NUMBER" => "row_number"
        "RANK" => "rank"
        "DENSE_RANK" => "dense_rank"
        "LAG" => "lag"
        "LEAD" => "lead"
        "FIRST_VALUE" => "first_value"
        "LAST_VALUE" => "last_value"
        _ => raise Abort(UnsupportedAnalytic)
      }
      let entries = [("fn", construction.text(wire_name))]
      if name == "ROW_NUMBER" || name == "RANK" || name == "DENSE_RANK" {
        if !arguments.is_empty() {
          raise Abort(
            Expression({
              issue: @expression.InvalidArguments,
              origin: @query.expression_origin(
                expression,
                @query.expression_root(expression),
              ),
            }),
          )
        }
      } else {
        if arguments.is_empty() ||
          arguments.length() >
          (if name == "LAG" || name == "LEAD" { 2 } else { 1 }) {
          raise Abort(UnsupportedAnalytic)
        }
        let argument = @query.expression_child(expression, arguments[0]).unwrap()
        entries.push(
          (
            "expr",
            match
              @expression.append_with_properties(
                argument,
                resolve,
                construction.builder,
                max_work,
                resolve_parameter=construction.parameter_resolver(),
              ) {
              Ok(node) => node
              Err(error) => raise Abort(Expression(error))
            },
          ),
        )
        if arguments.length() == 2 {
          entries.push(
            (
              "offset",
              lower_analytic_offset(
                construction,
                expression,
                arguments[1],
                max_work,
              ),
            ),
          )
        }
      }
      construction.object(entries)
    }
  }
}

///|
// Source parameter names share the admitted case-insensitive namespace.
// Literal boundaries and different boundary kinds remain distinct.
fn same_analytic_boundary(
  left : @query.FrameBoundary,
  right : @query.FrameBoundary,
) -> Bool {
  match (left, right) {
    (PrecedingParameter(a), PrecedingParameter(b))
    | (FollowingParameter(a), FollowingParameter(b)) =>
      ascii_upper(a) == ascii_upper(b)
    _ => left == right
  }
}

///|
fn same_analytic_frame(
  left : @query.AnalyticFrame?,
  right : @query.AnalyticFrame?,
) -> Bool {
  match (left, right) {
    (None, None) => true
    (Some(a), Some(b)) =>
      same_analytic_boundary(a.start, b.start) &&
      same_analytic_boundary(a.end, b.end)
    _ => false
  }
}

///|
fn same_analytic_window(
  left : @query.AnalyticWindow,
  right : @query.AnalyticWindow,
) -> Bool {
  if left.partition_by.length() != right.partition_by.length() ||
    left.order_by.length() != right.order_by.length() ||
    !same_analytic_frame(left.frame, right.frame) {
    return false
  }
  for index in 0..<left.partition_by.length() {
    if !same_expression(left.partition_by[index], right.partition_by[index]) {
      return false
    }
  }
  for index in 0..<left.order_by.length() {
    let a = left.order_by[index]
    let b = right.order_by[index]
    if a.direction != b.direction ||
      a.nulls != b.nulls ||
      !same_expression(a.expression, b.expression) {
      return false
    }
  }
  true
}

///|
// This table belongs to one SELECT input snapshot, not a clause alias scope.
// Positional column names do not identify evaluated window calls.
fn positional_set_analytic_slot(
  call : @query.AnalyticCall,
  slots : Array[(@query.AnalyticCall, String)],
  scope : JoinChainScope,
) -> String raise Abort {
  let resolve = path => scope_expression_slot(path, scope)
  for (previous, slot) in slots {
    if !same_analytic_window(previous.window, call.window) {
      continue
    }
    match (previous.expression, call.expression) {
      (None, None) => ()
      (Some(a), Some(b)) => if !same_expression(a, b) { continue }
      _ => continue
    }
    match (previous.aggregate, call.aggregate) {
      (None, None) => ()
      (Some(a), Some(b)) =>
        if !same_aggregate_call(a, b, resolve, resolve) {
          continue
        }
      _ => continue
    }
    return slot
  }
  raise Abort(UnsupportedAnalytic)
}

///|
fn lower_analytic(
  construction : Construction,
  projections : Array[@query.Projection],
  resolve : (Array[@query.NamePart]) -> String?,
  max_work : Int,
  max_collection_bytes : Int64,
  reserved : Array[String],
  evaluated : Array[(@query.Expression, String)],
  derives : Array[(String, @builder.Node)],
) -> @builder.Node raise Abort {
  let call = projections[0].analytic.unwrap()
  if projections.any(projection => {
      projection.analytic
      .map(call => call.window.reference is Some(_))
      .unwrap_or(false)
    }) {
    raise Abort(UnsupportedAnalytic)
  }
  let partitions : Array[@builder.Node] = []
  for expression in call.window.partition_by {
    let field = analytic_partition_field(
      construction, expression, resolve, reserved, evaluated, derives, max_work,
    )
    partitions.push(construction.text(field))
  }
  let order : Array[@builder.Node] = []
  for term in call.window.order_by {
    let field = analytic_order_field(
      construction,
      term.expression,
      resolve,
      reserved,
      evaluated,
      derives,
      max_work,
    )
    order.push(
      construction.object([
        ("field", construction.text(field)),
        ("dir", construction.text(term.direction)),
        ("nulls", construction.text(term.nulls)),
      ]),
    )
  }
  let functions : Array[(String, @builder.Node)] = []
  for projection in projections {
    functions.push(
      (
        projection.name.unwrap().value,
        lower_analytic_call(
          construction,
          projection.analytic.unwrap(),
          resolve,
          max_work,
          max_collection_bytes,
        ),
      ),
    )
  }
  let body = [
    ("partition_by", construction.array(partitions)),
    ("order_by", construction.array(order)),
    ("functions", construction.object(functions)),
  ]
  match call.window.frame {
    Some(frame) =>
      body.push(
        (
          "frame",
          construction.object([
            ("start", analytic_boundary(construction, frame.start)),
            ("end", analytic_boundary(construction, frame.end)),
          ]),
        ),
      )
    None => ()
  }
  construction.object(body)
}

///|
fn having_column(
  path : Array[@query.NamePart],
  query : @query.Query,
  input : Input,
  active_fields : Array[String],
  projections : Array[@query.Projection],
  group_keys : Array[(@query.Expression, String)],
  computed : Array[(@query.Expression, String)],
  scope? : JoinChainScope? = None,
) -> String? {
  let resolve = fn(source : Array[@query.NamePart]) -> String? {
    match scope {
      Some(scope) => scope_expression_slot(source, scope)
      None => resolve_column(source, query, input, active_fields)
    }
  }
  if path.length() == 1 {
    let mut selected : String? = None
    let mut matched = false
    let mut ambiguous = false
    for projection in projections {
      match projection_alias(projection) {
        Some(name) if same_name(name, path[0]) => {
          if matched {
            ambiguous = true
          }
          matched = true
          if projection.aggregate is Some(_) {
            selected = resolve([name])
          } else {
            match projection.expression {
              Some(expression) => {
                let mut slot : String? = None
                for pair in group_keys {
                  if same_expression(pair.0, expression) {
                    slot = Some(pair.1)
                  }
                }
                for pair in computed {
                  if same_expression(pair.0, expression) {
                    slot = Some(pair.1)
                  }
                }
                selected = match slot {
                  Some(_) => slot
                  None =>
                    match
                      @query.expression_node(
                        expression,
                        @query.expression_root(expression),
                      ).unwrap().kind {
                      Reference(source) => resolve(source)
                      _ => None
                    }
                }
              }
              None => selected = None
            }
          }
        }
        _ => ()
      }
    }
    if ambiguous {
      return None
    }
    if matched {
      return selected
    }
  }
  resolve(path)
}

///|
// A single-consumer pure projection may run after the existing acquisition
// capture port but before publishing its cross-stage Result. The common
// checker still owns the projected schema and publication-order obligation.
priv struct SourceProjectionCapture {
  projection_name : String
  mut steps : Array[@builder.Node]
  mut fields : Array[String]
  mut count : Int
}

///|
fn source_projection_capture_query(
  query : @query.Query,
  allow_vector? : Bool = true,
) -> Bool {
  let mut index = 0
  if @query.operation_at(query, index) is Some(Where(_)) {
    index += 1
  }
  guard @query.operation_at(query, index) is Some(Select(projections, false)) else {
    return false
  }
  // Field/parameter/literal projection has no evaluation-context callback.
  // Keep it inside the same acquisition capture before its cross-stage
  // publication, so an unselected structured column is not a Result field.
  // Other expressions retain their original placement, except the already
  // adopted Vector scalar route below with its original ORDER-only suffix.
  let mut direct_projection = true
  let mut has_vector_scalar = false
  for projection in projections {
    if projection.aggregate is Some(_) ||
      projection.analytic is Some(_) ||
      projection.star is Some(_) ||
      !projection.replacements.is_empty() {
      return false
    }
    if projection.expression is Some(expression) {
      for node_index in 0..<@query.expression_node_count(expression) {
        match @query.expression_node(expression, node_index).unwrap().kind {
          Null
          | Boolean(_)
          | Number(_)
          | StringLiteral(_)
          | Reference(_)
          | ParameterReference(_) => ()
          Call(path, _) => {
            direct_projection = false
            guard path.length() == 1 else { return false }
            match ascii_upper(path[0].value) {
              "VECTOR_COSINE_SIMILARITY"
              | "VECTOR_INNER_PRODUCT"
              | "VECTOR_L2_DISTANCE" => has_vector_scalar = true
              _ => return false
            }
          }
          _ => direct_projection = false
        }
      }
    }
  }
  if direct_projection {
    // The internal Result also establishes canonical order. Moving SELECT
    // across LIMIT/OFFSET or another order-consuming operation can therefore
    // change which rows it observes. Only these nonpositional suffixes enter
    // the direct case; the adopted Vector route keeps its separate contract.
    for tail in (index + 1)..<@query.operation_count(query) {
      match @query.operation_at(query, tail) {
        Some(AssertUnique(_)) | Some(RetainResult(_)) => ()
        _ => return false
      }
    }
    return true
  }
  if !allow_vector ||
    !has_vector_scalar ||
    !(@query.operation_at(query, index + 1) is Some(Order(_))) {
    return false
  }
  index += 2
  if @query.operation_at(query, index) is Some(Limit(_, _)) {
    index += 1
  }
  index == @query.operation_count(query)
}

///|
fn compile_steps(
  construction : Construction,
  query : @query.Query,
  input : Input,
  fields : Array[String],
  max_work : Int,
  query_limits : Limits,
  max_collection_items : Int64,
  max_collection_bytes : Int64,
  start_at : Int,
  preserve_identity_select : Bool,
  final_alias : String,
  graph_bindings_only? : Bool = false,
  nearest_inputs? : Array[Input] = [],
  nearest_vectors? : Array[(String, @carrier.Vectors)] = [],
  retained? : Array[RetainedResult]? = None,
  projected_input? : Bool = false,
  initial_scope? : JoinChainScope? = None,
  preserved_scope? : Array[JoinChainScope]? = None,
  value_table_scope? : Array[JoinChainScope]? = None,
  parameter_declarations? : @parameters.Declarations? = None,
  prefix_steps? : Array[@builder.Node] = [],
  reserved_bindings? : Array[String] = [],
  prefix_context? : Context? = None,
  positional_set_output? : Bool = false,
  source_projection_capture? : SourceProjectionCapture? = None,
  checked_infer_prefix? : ((
    Array[@builder.Node],
    String,
    InferInputLabels,
    Array[(String, String)],
  ) -> InferPrefixProjection raise Abort)? = None,
  checked_nearest_prefix? : ((Array[@builder.Node]) -> @pipeline.CheckedPipeline raise Abort)? = None,
) -> (Array[@builder.Node], Array[String]) raise Abort {
  // Internal parenthesized bindings retain their positional export role.
  // This parser fact never grants anonymous exports to authored CTEs.
  let positional_set_output = positional_set_output ||
    @query.positional_output(query)
  let positional_projection = if positional_set_output {
    positional_set_terminal_projection(query)
  } else {
    None
  }
  let positional_private_fields : Array[String] = []
  let positional_authored_aliases : Array[(String, String)] = []
  // A later authored column destination is a real column name. Reserve it
  // before assigning private storage names to anonymous/duplicate occurrences.
  let positional_destination_names : Array[@query.NamePart] = []
  if positional_projection is Some(projection) {
    for index in (projection + 1)..<@query.operation_count(query) {
      match @query.operation_at(query, index) {
        Some(Rename(names)) =>
          positional_destination_names.append(names.map(pair => pair.1))
        Some(Extend(columns)) =>
          for column in columns {
            if projection_alias(column) is Some(name) {
              positional_destination_names.push(name)
            }
          }
        Some(Infer(clause)) => {
          positional_destination_names.push(clause.name)
          for item in clause.keep {
            if item.name is Some(name) {
              positional_destination_names.push(name)
            }
          }
        }
        Some(Unpivot(clause)) => {
          positional_destination_names.append(clause.value_columns)
          positional_destination_names.push(clause.name_column)
        }
        Some(Pivot(clause)) =>
          for entry in clause.values {
            let suffix = entry.1.map(name => name.value).unwrap_or(entry.0)
            let name = clause.prefix
              .map(prefix => prefix.value + "_" + suffix)
              .unwrap_or(suffix)
            positional_destination_names.push({ value: name, quoted: false, })
          }
        Some(UnnestSource(_, element, offset)) => {
          positional_destination_names.push(element)
          if offset is Some(name) {
            positional_destination_names.push(name)
          }
        }
        _ => ()
      }
    }
  }
  let step_entries : Array[Array[(String, @builder.Node)]] = []
  let mut output = fields.copy()
  let mut requires_graph_projection = graph_bindings_only
  let mut active_fields = fields.copy()
  let mut grouped = false
  let mut sql_group_projection = false
  let mut sql_group_select_scope : JoinChainScope? = None
  let mut sql_group_expression_input_scope : JoinChainScope? = None
  let mut sql_group_order_input_scope : JoinChainScope? = None
  let mut sql_group_input_columns : Array[(String, String)] = []
  let mut sql_group_input_ranges : Array[
    (@query.NamePart, Array[(String, String)]),
  ] = []
  let grouped_keys : Array[(@query.Expression, String)] = []
  let mut sql_group_selected_projections : Array[@query.Projection] = []
  let having_values : Array[(@query.Expression, String)] = []
  let analytic_outputs : Array[(String, String)] = []
  let positional_set_analytic_slots : Array[(@query.AnalyticCall, String)] = []
  let analytic_expression_bindings : Array[(String, String)] = []
  let mut analytic_input_fields : Array[String]? = None
  let mut analytic_input_scope : JoinChainScope? = None
  let qualify_values : Array[(@query.Expression, String)] = []
  let sql_group_aggregate_slots : Array[(String, String)] = []
  let anonymous_set_aggregate_slots : Array[(@query.AggregateCall, String)] = []
  let positional_set_aggregate_slots : Array[(@query.AggregateCall, String)] = []
  let having_aggregate_slots : Array[(String, String)] = []
  let order_aggregate_slots : Array[(String, String)] = []
  let order_analytic_slots : Array[(String, String)] = []
  let mut first = true
  let mut input_from = input.name
  let mut terminal_result = false
  let mut pending_select : Array[(String, @builder.Node)]? = None
  let mut pending_bindings : Array[(String, String)] = []
  let mut selected_expressions : Array[(@query.Expression, String)] = []
  let mut selected_input_fields = fields.copy()
  let mut selected_output_slots : Array[(String, String)] = []
  let mut pipe_visible = initial_scope
    .map(scope => scope.visible.copy())
    .unwrap_or(fields.map(field => (field, field)))
  // Column ordinals count value-table columns once, independently of the
  // implicit fields exposed to expressions and star. Keep evaluated slots.
  let mut pipe_columns = initial_scope
    .map(scope => scope.columns.copy())
    .unwrap_or(pipe_visible.copy())
  let mut pipe_value_table = initial_scope
    .map(scope => scope.value_table)
    .unwrap_or(false)
  let mut pipe_value_columns = initial_scope
    .map(scope => scope.value_columns.copy())
    .unwrap_or([])
  let mut pipe_star_ranges = initial_scope
    .map(scope => scope.star_ranges.copy())
    .unwrap_or([])
  let initial_range = query_range_name(query)
  let mut pipe_ranges = if initial_scope is Some(scope) {
    scope.ranges.copy()
  } else if projected_input {
    []
  } else {
    [(initial_range, pipe_visible.copy())]
  }
  let mut scalar_value_table_ranges : Array[(@query.NamePart, String)] = initial_scope
    .map(scope => scope.scalar_ranges.copy())
    .unwrap_or([])
  let mut infer_key_labels = match initial_scope {
    Some(scope) => seed_infer_key_labels(construction, scope.key_labels, [])
    None => seed_infer_key_labels(construction, [], pipe_visible)
  }
  let mut selected_input_scope : JoinChainScope = {
    visible: pipe_visible.copy(),
    ranges: pipe_ranges.copy(),
    columns: pipe_columns.copy(),
    value_table: pipe_value_table,
    value_columns: pipe_value_columns.copy(),
    star_ranges: pipe_star_ranges.copy(),
    receivers: initial_scope.map(scope => scope.receivers.copy()).unwrap_or([]),
    key_labels: infer_key_labels.copy(),
    scalar_ranges: scalar_value_table_ranges.copy(),
  }
  let mut pipe_changed = initial_scope is Some(_)
  // Materializing a SELECT resets private slots, not the current row scope.
  // Once AS or SELECT replaces the source scope, later operators must not
  // recover its ranges through the initial query resolver.
  let mut pipe_rebound = projected_input || initial_scope is Some(_)
  let mut pipe_selected = false
  let mut value_table_receivers : Array[(@query.NamePart, String)] = initial_scope
    .map(scope => scope.receivers.copy())
    .unwrap_or([])
  let mut distinct_order_scope = false
  let expand_projections = fn(
    selected_query : @query.Query,
    projections : Array[@query.Projection],
    visible : Array[(String, String)],
    ranges : Array[(@query.NamePart, Array[(String, String)])],
    expression_work : Int,
  ) -> Array[@query.Projection] raise Abort {
    expanded_replacement_projections(
      selected_query,
      projections,
      visible,
      unnest_star_ranges(ranges, pipe_star_ranges).filter(range => {
        !scalar_value_table_ranges.any(receiver => {
          same_name(receiver.0, range.0)
        })
      }),
      expression_work,
      authored_aliases=positional_authored_aliases,
      object_columns=Some(receiver => {
        let prefix = if prefix_steps.is_empty() &&
          input.source is GeneratedValues(seed) {
          [import_query_cursor(construction, seed)]
        } else {
          prefix_steps.copy()
        }
        prefix.append(step_entries.map(entries => construction.object(entries)))
        let probe = pipe_physical_name(active_fields, "aql_object_star_probe_")
        let entries : Array[(String, @builder.Node)] = []
        if step_entries.is_empty() {
          entries.push(("from", construction.text(input_from)))
        }
        entries.push(
          (
            "derive",
            construction.object([
              (
                probe,
                append_pipe_expression(
                  construction,
                  receiver,
                  unnest_expression_columns(
                    visible, value_table_receivers, scalar_value_table_ranges, pipe_columns,
                  ),
                  ranges,
                  expression_work,
                  value_ranges=value_range_names(
                    value_table_receivers, scalar_value_table_ranges,
                  ),
                ),
              ),
            ]),
          ),
        )
        prefix.push(construction.object(entries))
        guard relation_prefix_column(
            construction, prefix, probe, receiver, prefix_context, parameter_declarations,
            query_limits, expression_work,
          )
          is Some(contract) else {
          raise Abort(UnsupportedProjection)
        }
        guard contract.shape is @contract.Object(fields) else {
          // Keep the existing scalar-qualified-star diagnostic; a scalar
          // value does not become a row or an object through star syntax.
          if @query.expression_node(receiver, @query.expression_root(receiver)).unwrap().kind
            is Reference(path) &&
            path.length() == 1 {
            raise Abort(UnknownColumn)
          }
          raise Abort(UnsupportedProjection)
        }
        // Read declared fields; do not inspect rows or create presence/key
        // evidence. Ordinary property projection retains receiver nullability.
        if @contract.field_count(fields) > expression_work {
          raise Abort(
            Expression({
              issue: @expression.WorkLimit,
              origin: @query.expression_origin(
                receiver,
                @query.expression_root(receiver),
              ),
            }),
          )
        }
        @contract.fields(fields).map(field => field.name)
      }),
    )
  }
  for i in start_at..<@query.operation_count(query) {
    let operation = @query.operation_at(query, i).unwrap()
    let mut reset_infer_key_labels = false
    // Scope-only operators cannot rename a value slot. Avoid rebuilding the
    // identity metadata for every predicate, assertion or ordinary range AS.
    let update_key_labels = construction.infer_labels &&
      (match operation {
        Where(_) | Limit(_, _) | AssertUnique(_) | RetainResult(_) => false
        Alias(_) => pipe_value_table
        Order(_) => pending_select is Some(_)
        _ => true
      })
    let previous_key_names = if update_key_labels {
      infer_key_column_names(
        construction, pipe_visible, positional_private_fields, positional_authored_aliases,
      )
    } else {
      []
    }
    if sql_group_projection &&
      sql_group_select_scope is None &&
      !(operation is Order(_) ||
      operation is Limit(_, _) ||
      operation is RetainResult(_)) {
      // A Pipe tail consumes the completed SQL projection. Its expressions
      // may now read aggregate output columns, but cannot recover the old
      // input ranges or reuse GROUP expressions over different value slots.
      sql_group_projection = false
      grouped_keys.clear()
      having_values.clear()
      order_aggregate_slots.clear()
      pipe_ranges = []
      pipe_star_ranges = []
      pipe_rebound = true
    }
    // Graph occurrence slots are an implementation detail, not a public
    // Relation schema. An explicit projection establishes that schema.
    if operation is Select(projections, _) {
      if requires_graph_projection &&
        projections.any(projection => projection.star is Some(_)) {
        raise Abort(UnsupportedProjection)
      }
      requires_graph_projection = false
    }
    if pipe_selected &&
      !(operation is Order(_) ||
      operation is Limit(_, _) ||
      operation is RetainResult(_)) {
      // SELECT has materialized its output. Later operators consume that
      // Relation, irrespective of whether SET introduced private slots.
      pipe_selected = false
      distinct_order_scope = false
      pipe_ranges = []
      pipe_star_ranges = []
      value_table_receivers = []
      pipe_value_columns = []
      pipe_value_table = false
      scalar_value_table_ranges = []
      sql_group_projection = false
    }
    if positional_projection is Some(projection) && i > projection {
      if operation is Rename(names) {
        for (target, _) in names {
          if positional_private_fields.any(field => {
              same_name(target, { value: field, quoted: false, })
            }) {
            raise Abort(UnknownColumn)
          }
        }
      }
      if operation is Drop(names) {
        for name in names {
          if positional_private_fields.any(field => {
              same_name(name, { value: field, quoted: false, })
            }) {
            raise Abort(UnknownColumn)
          }
        }
      }
      if operation is Set(assignments) {
        for assignment in assignments {
          if positional_private_fields.any(field => {
              same_name(assignment.0, { value: field, quoted: false, })
            }) {
            raise Abort(UnknownColumn)
          }
        }
      }
      // EXCEPT/REPLACE address authored names, never the storage name of an
      // anonymous value. The ordinary star helper retains all other columns.
      if operation is Select(columns, _) {
        for column in columns {
          for replacement in column.replacements {
            if positional_private_fields.any(field => {
                same_name(replacement.name, { value: field, quoted: false, })
              }) {
              raise Abort(UnknownColumn)
            }
          }
          for excluded in column.except_columns {
            if positional_private_fields.any(field => {
                same_name(excluded, { value: field, quoted: false, })
              }) {
              raise Abort(UnknownColumn)
            }
          }
        }
      }
      let expressions = match operation {
        Order(terms) => terms.map(term => term.expression)
        Where(predicate) => [predicate]
        Infer(clause) => clause.inputs.map(input => input.1)
        Pivot(clause) =>
          clause.argument_expression
          .map(expression => [expression])
          .unwrap_or([])
        UnnestSource(expression, _, _) => [expression]
        Set(assignments) => assignments.map(assignment => assignment.1)
        Select(columns, _)
        | Extend(columns)
        | Analytic(columns)
        | AnalyticExpressions(columns, _)
        | OrderAnalytic(columns, _) =>
          positional_projection_expressions(columns)
        _ => []
      }
      let resolve_input = path => {
        if operation is Where(_) ||
          operation is AssertUnique(_) ||
          operation is Infer(_) ||
          operation is Pivot(_) ||
          operation is UnnestSource(_, _, _) ||
          operation is Set(_) ||
          operation is Extend(_) ||
          operation is Select(_, _) ||
          operation is Analytic(_) ||
          operation is AnalyticExpressions(_, _) ||
          operation is OrderAnalytic(_, _) {
          pipe_slot(path, pipe_visible, pipe_ranges)
        } else if pipe_selected || pipe_changed || pipe_rebound {
          scope_expression_slot(path, selected_input_scope)
        } else {
          resolve_column(path, query, input, selected_input_fields)
        }
      }
      let projections = match @query.operation_at(query, projection).unwrap() {
        Select(projections, _) => projections
        _ => []
      }
      let remaining_projections = projections.filter(column => {
        guard projection_alias(column) is Some(name) &&
          duplicate_projection_alias(projections, name.value) else {
          return true
        }
        positional_authored_aliases.any(mapping => {
          same_name(name, { value: mapping.1, quoted: false, }) &&
          // Deferred SELECT keeps evaluated output occurrences in its column
          // scope before their physical names enter active_fields.
          pipe_columns.any(column => column.0 == mapping.0)
        })
      })
      let ambiguous_current_name = name => {
        pipe_columns
        .filter(column => {
          same_name(name, {
            value: positional_authored_column_name(
              column.0,
              positional_authored_aliases,
            ),
            quoted: false,
          })
        })
        .length() >
        1
      }
      if operation is Unpivot(clause) {
        for names in clause.column_sets {
          for name in names {
            if positional_private_fields.any(field => {
                same_name(name, { value: field, quoted: false, })
              }) {
              raise Abort(UnknownColumn)
            }
            if ambiguous_current_name(name) {
              raise Abort(AmbiguousColumn)
            }
          }
        }
      }
      if operation is Rename(names) {
        for (target, _) in names {
          if ambiguous_current_name(target) {
            raise Abort(AmbiguousColumn)
          }
        }
      }
      if operation is Set(assignments) {
        for assignment in assignments {
          if ambiguous_current_name(assignment.0) ||
            duplicate_projection_alias(
              remaining_projections,
              assignment.0.value,
            ) {
            raise Abort(AmbiguousColumn)
          }
        }
      }
      // Expressions and assertion key paths share the same authored scope.
      // This validates references only; the assertion's type/key checks and
      // execution remain with its existing lowering and common Owner.
      let check_references = fn(
        references : Array[Array[@query.NamePart]],
      ) -> Unit raise Abort {
        reject_duplicate_projection_references(
          remaining_projections, references, resolve_input,
        )
        for path in references {
          if path.length() > 1 &&
            pipe_ranges.any(range => {
              same_name(path[0], range.0) &&
              range.1
              .filter(column => {
                same_name(path[1], { value: column.0, quoted: false, })
              })
              .length() >
              1
            }) {
            raise Abort(AmbiguousColumn)
          }
          if ambiguous_current_name(path[0]) &&
            !order_reference_identity(path, resolve_input)
            .map(identity => identity.1 > 1)
            .unwrap_or(false) {
            raise Abort(AmbiguousColumn)
          }
          // Physical outputs are ordinal values, never authored aliases.
          // A longer valid input range prefix retains its own resolution.
          if positional_private_fields.any(field => {
              same_name(path[0], { value: field, quoted: false, })
            }) &&
            !order_reference_identity(path, resolve_input)
            .map(identity => identity.1 > 1)
            .unwrap_or(false) {
            raise Abort(UnknownColumn)
          }
        }
      }
      for expression in expressions {
        check_references(join_reference_paths(expression))
      }
      if operation is AssertUnique(keys) {
        check_references(keys)
      }
      if operation is Infer(clause) {
        check_references(clause.keys.unwrap_or([]))
        check_references(
          clause.keep.filter(item => !item.wildcard).map(item => item.path),
        )
      }
      if operation is Pivot(clause) {
        check_references(
          if clause.count_star || clause.argument_expression is Some(_) {
            [clause.column]
          } else {
            [clause.argument, clause.column]
          },
        )
      }
    }
    let entries : Array[(String, @builder.Node)] = []
    let mut deferred = false
    let mut add_distinct = false
    if first {
      entries.push(("from", construction.text(input_from)))
      first = false
    }
    match operation {
      Unpivot(clause) => {
        if pipe_value_table {
          raise Abort(UnsupportedProjection)
        }
        let (lowered, visible, physical) = lower_pipe_unpivot(
          construction, clause, pipe_columns,
        )
        for index in 0..<lowered.length() {
          if index == 0 {
            entries.append(lowered[index])
            step_entries.push(entries.copy())
            entries.clear()
          } else {
            step_entries.push(lowered[index])
          }
        }
        pipe_visible = visible
        pipe_columns = visible.copy()
        active_fields = physical
        output = visible.map(column => column.0)
        pipe_ranges = []
        pipe_star_ranges = []
        value_table_receivers = []
        pipe_value_columns = []
        scalar_value_table_ranges = []
        pipe_value_table = false
        pipe_rebound = true
        pipe_changed = true
        deferred = true
        if positional_projection is Some(projection) && i > projection {
          let names = pipe_visible.map(column => column.0)
          let bindings = pipe_visible.copy()
          let selected = pipe_visible.map(column => {
            construction.object([(column.0, construction.text(column.1))])
          })
          let private_fields = privatize_positional_duplicate_columns(
            construction,
            names,
            bindings,
            selected,
            active_fields,
            authored_aliases=Some(positional_authored_aliases),
            reserved_names=positional_destination_names,
          )
          if !private_fields.is_empty() {
            // UNPIVOT may name a new value/label like a retained column.
            // Copy each evaluated occurrence; neither value is overwritten.
            positional_private_fields.append(private_fields)
            entries.push(("select", construction.array(selected)))
            active_fields = names.copy()
            output = names
            pipe_visible = names.map(name => (name, name))
            pipe_columns = pipe_visible.copy()
            pipe_changed = false
            reset_infer_key_labels = true
            deferred = false
          }
        }
      }
      UnnestSource(expression, element, offset) => {
        let correlated = i != 0 || !@query.relation(query).is_empty()
        if correlated && pipe_ranges.any(range => same_name(range.0, element)) {
          raise Abort(AmbiguousColumn)
        }
        if correlated &&
          offset is Some(name) &&
          pipe_ranges.any(range => same_name(range.0, name)) {
          raise Abort(AmbiguousColumn)
        }
        if offset is Some(name) && same_name(element, name) {
          raise Abort(DuplicateOutput)
        }
        let mut element_contract = unnest_source_element(
          expression,
          parameter_declarations,
          query_limits,
          max_work,
          construction.parameter_resolver(),
        )
        let requires_element_scope = preserved_scope is Some(_) ||
          value_table_scope is Some(_) ||
          selected_projections(query).any(projection => {
            if projection.star is None {
              false
            } else {
              match projection.expression {
                None => true
                Some(receiver) =>
                  match
                    @query.expression_node(
                      receiver,
                      @query.expression_root(receiver),
                    ) {
                    Some({ kind: Reference(path), .. }) =>
                      !path.is_empty() && same_name(path[0], element)
                    _ => false
                  }
              }
            }
          })
        let physical = if correlated {
          active_fields.copy() + [element.value]
        } else {
          ["aql_source_free_unit", element.value]
        }
        if offset is Some(name) {
          physical.push(name.value)
        }
        let column = pipe_physical_name(physical, "aql_unnest_array_")
        physical.push(column)
        let element_slot = pipe_physical_name(physical, "aql_unnest_element_")
        physical.push(element_slot)
        let derived = append_pipe_expression(
          construction,
          expression,
          if correlated {
            unnest_expression_columns(
              pipe_visible, value_table_receivers, scalar_value_table_ranges, pipe_columns,
            )
          } else {
            []
          },
          if correlated {
            pipe_ranges
          } else {
            []
          },
          max_work,
          value_ranges=value_range_names(
            value_table_receivers, scalar_value_table_ranges,
          ),
        )
        entries.push(("derive", construction.object([(column, derived)])))
        step_entries.push(entries.copy())
        entries.clear()
        if correlated && requires_element_scope && element_contract is None {
          let prefix = if prefix_steps.is_empty() &&
            input.source is GeneratedValues(seed) {
            [import_query_cursor(construction, seed)]
          } else {
            prefix_steps.copy()
          }
          prefix.append(
            step_entries.map(entries => construction.object(entries)),
          )
          element_contract = unnest_prefix_element(
            construction, prefix, column, expression, prefix_context, parameter_declarations,
            query_limits, max_work,
          )
        }
        if requires_element_scope && element_contract is None {
          raise Abort(UnsupportedProjection)
        }
        let arguments : Array[(String, @builder.Node)] = [
          ("column", construction.text(column)),
          ("as", construction.text(element_slot)),
        ]
        let index_slot = if offset is Some(_) {
          let slot = pipe_physical_name(physical, "aql_unnest_offset_")
          physical.push(slot)
          arguments.push(("with_index", construction.text(slot)))
          Some(slot)
        } else {
          None
        }
        entries.push(("unnest", construction.object(arguments)))
        if !correlated {
          // The source-free witness is private, not a parent Relation.
          pipe_visible = []
          pipe_columns = []
          pipe_ranges = []
          pipe_star_ranges = []
          scalar_value_table_ranges = []
          active_fields = []
        }
        active_fields.append([column, element_slot])
        if index_slot is Some(slot) {
          active_fields.push(slot)
        }
        pipe_value_table = !correlated && offset is None
        pipe_columns.push((element.value, element_slot))
        if element_contract is Some({ shape: @contract.Object(fields), .. }) {
          step_entries.push(entries.copy())
          entries.clear()
          let properties : Array[(String, @builder.Node)] = []
          for field in @contract.fields(fields) {
            let slot = pipe_physical_name(physical, "aql_unnest_field_")
            physical.push(slot)
            active_fields.push(slot)
            properties.push(
              (
                slot,
                construction.object([
                  (
                    "property",
                    construction.object([
                      (
                        "value",
                        construction.object([
                          ("field", construction.text(element_slot)),
                        ]),
                      ),
                      ("name", construction.text(field.name)),
                    ]),
                  ),
                ]),
              ),
            )
            pipe_visible.push((field.name, slot))
          }
          if !properties.is_empty() {
            entries.push(("derive", construction.object(properties)))
          } else {
            // The UNNEST step was already emitted. An empty object needs no
            // property derivation; do not append an operator-free step.
            deferred = true
          }
          let element_fields = properties.map(pair => pair.0)
          pipe_ranges.push(
            (
              element,
              pipe_visible.filter(pair => element_fields.contains(pair.1)),
            ),
          )
          value_table_receivers.push((element, element_slot))
          pipe_value_columns.push(
            (
              element.value,
              element_slot,
              pipe_visible.filter(pair => element_fields.contains(pair.1)),
            ),
          )
        } else {
          pipe_visible.push((element.value, element_slot))
          // Scalar value tables still introduce a range name. They expose no
          // member columns, but RENAME and later UNNEST aliases must observe
          // that range until projection or a whole-column edit removes it.
          pipe_ranges.push((element, []))
          scalar_value_table_ranges.push((element, element_slot))
        }
        if offset is Some(name) && index_slot is Some(slot) {
          pipe_visible.push((name.value, slot))
          pipe_columns.push((name.value, slot))
          // WITH OFFSET is a scalar value-table column and range, just like
          // the array alias. Ordinary projection or whole-column edits end
          // that range through the existing scope transitions.
          pipe_ranges.push((name, []))
          scalar_value_table_ranges.push((name, slot))
        }
        pipe_rebound = true
        pipe_changed = true
        output = pipe_visible.map(pair => pair.0)
      }
      GraphCall(_) => raise Abort(UnsupportedGraph)
      AssertUnique(keys) => {
        let unique : Array[@builder.Node] = []
        for path in keys {
          guard pipe_slot(path, pipe_visible, pipe_ranges) is Some(slot) else {
            raise Abort(UnknownColumn)
          }
          unique.push(construction.text(slot))
        }
        entries.push(
          (
            "assert_rows",
            construction.object([("unique_by", construction.array(unique))]),
          ),
        )
      }
      RetainResult(name) => {
        guard retained is Some(retained) else { raise Abort(UnsupportedResult) }
        if requires_graph_projection {
          raise Abort(UnsupportedResult)
        }
        if retained.any(result => {
            ascii_upper(result.name) == ascii_upper(name.value)
          }) {
          raise Abort(DuplicateOutput)
        }
        terminal_result = i == @query.operation_count(query) - 1
        let needs_view = active_fields.length() != pipe_visible.length() ||
          pipe_visible.any(pair => pair.0 != pair.1)
        let checkpoint = if terminal_result && !needs_view {
          final_alias
        } else {
          let mut proposed = "aql_result_checkpoint_" + i.to_string()
          while proposed == input.name ||
                proposed == final_alias ||
                nearest_inputs.any(other => other.name == proposed) {
            proposed += "_generated"
          }
          proposed
        }
        // A terminal RESULT names this exact Content output; it does not
        // introduce another computation after the byte barrier. Do not
        // overwrite an existing alias or elide a nonterminal retained tap.
        let names_content_output = terminal_result &&
          !needs_view &&
          entries.is_empty() &&
          !step_entries.is_empty() &&
          step_entries.last().unwrap().any(entry => entry.0 == "serialize") &&
          !step_entries.last().unwrap().any(entry => entry.0 == "as")
        if names_content_output {
          step_entries
          .last()
          .unwrap()
          .push(("as", construction.text(checkpoint)))
        } else {
          entries.push(
            (
              "select",
              construction.array(
                active_fields.map(field => construction.text(field)),
              ),
            ),
          )
          entries.push(("as", construction.text(checkpoint)))
          step_entries.push(entries)
        }
        input_from = checkpoint
        let from = if needs_view {
          let view = if terminal_result {
            final_alias
          } else {
            let mut proposed = "aql_result_view_" + i.to_string()
            while proposed == input.name ||
                  proposed == final_alias ||
                  nearest_inputs.any(other => other.name == proposed) {
              proposed += "_generated"
            }
            proposed
          }
          step_entries.push([
            ("from", construction.text(checkpoint)),
            (
              "select",
              construction.array(
                pipe_visible.map(pair => {
                  if pair.0 == pair.1 {
                    construction.text(pair.1)
                  } else {
                    construction.object([(pair.0, construction.text(pair.1))])
                  }
                }),
              ),
            ),
            ("as", construction.text(view)),
          ])
          // A public projection cannot remove the immutable range snapshots
          // still visible to the continuing Pipe. Resume the original carrier.
          input_from = checkpoint
          first = true
          view
        } else {
          checkpoint
        }
        retained.push({
          name: name.value,
          port: "aql_retained_result_" + retained.length().to_string(),
          from,
          fields: pipe_visible.map(pair => pair.0),
          terminal: terminal_result,
          carrier_complete: !needs_view,
          update: None,
          store: false,
          insert: None,
          command: None,
        })
        if terminal_result {
          output = pipe_visible.map(pair => pair.0)
        }
        deferred = true
      }
      Nearest(clause) => {
        let matches = nearest_inputs.filter(candidate => {
          same_relation_path(candidate.relation, clause.relation)
        })
        guard matches.length() == 1 else { raise Abort(UnknownRelation) }
        let (steps, fields) = lower_nearest_steps(
          construction,
          clause,
          matches[0],
          pipe_visible,
          pipe_ranges,
          active_fields,
          entries,
          i,
          nearest_inputs.map(input => input.name),
          max_work,
          candidate_typed=nearest_vectors
            .filter(pair => pair.0 == matches[0].name)
            .get(0)
            .map(pair => pair.1),
          completion_limits=Some(query_limits),
          checked_prefix=checked_nearest_prefix.map(check => {
            nodes => {
              check(
                prefix_steps +
                step_entries.map(step => construction.object(step)) +
                nodes,
              )
            }
          }),
        )
        step_entries.append(steps)
        entries.clear()
        active_fields = fields.copy()
        output = fields
        value_table_receivers = []
        pipe_value_columns = []
        pipe_value_table = false
        pipe_visible = active_fields.map(field => (field, field))
        pipe_columns = pipe_visible.copy()
        pipe_ranges = []
        pipe_star_ranges = []
        scalar_value_table_ranges = []
        pipe_rebound = true
        pipe_changed = false
        reset_infer_key_labels = true
        grouped = false
        selected_expressions = []
        deferred = true
      }
      Serialize(clause) => {
        let (steps, fields) = lower_serialization_steps(
          construction,
          clause,
          pipe_visible,
          pipe_ranges,
          active_fields,
          entries,
          i,
          input.name,
          max_work,
        )
        step_entries.append(steps)
        entries.clear()
        active_fields = fields.copy()
        output = fields
        value_table_receivers = []
        pipe_value_columns = []
        pipe_value_table = false
        pipe_visible = fields.map(field => (field, field))
        pipe_columns = pipe_visible.copy()
        pipe_ranges = []
        pipe_star_ranges = []
        scalar_value_table_ranges = []
        pipe_rebound = true
        pipe_changed = false
        reset_infer_key_labels = true
        grouped = false
        selected_expressions = []
        deferred = true
      }
      Infer(clause) => {
        let (steps, fields) = lower_infer_steps(
          construction,
          clause,
          pipe_visible,
          pipe_ranges,
          active_fields,
          entries,
          i,
          input.name,
          max_work,
          authored_aliases=positional_authored_aliases,
          key_labels=infer_key_labels,
          checked_prefix=checked_infer_prefix.map(check => {
            (nodes, producer, visible, authored_aliases) => {
              check(
                prefix_steps +
                step_entries.map(step => construction.object(step)) +
                nodes,
                producer,
                visible,
                authored_aliases,
              )
            }
          }),
        )
        for step in steps {
          step_entries.push(step)
        }
        entries.clear()
        active_fields = fields.copy()
        output = fields
        value_table_receivers = []
        pipe_value_columns = []
        pipe_value_table = false
        pipe_visible = active_fields.map(field => (field, field))
        pipe_columns = pipe_visible.copy()
        pipe_ranges = []
        pipe_star_ranges = []
        scalar_value_table_ranges = []
        pipe_rebound = true
        pipe_changed = false
        reset_infer_key_labels = true
        grouped = false
        selected_expressions = []
        deferred = true
      }
      Where(predicate) if i > 0 &&
        @query.operation_at(query, i - 1) is Some(AnalyticExpressions(_, _)) => {
        entries.push(
          (
            "filter",
            append_pipe_expression(
              construction,
              predicate,
              private_expression_columns(
                unnest_expression_columns(
                  pipe_visible, value_table_receivers, scalar_value_table_ranges,
                  pipe_columns,
                ),
                analytic_expression_bindings,
              ),
              pipe_ranges,
              max_work,
              value_ranges=value_range_names(
                value_table_receivers, scalar_value_table_ranges,
              ),
            ),
          ),
        )
        // Predicate-owned window values cannot become columns or bindings
        // in a later operator. Publish only the unchanged current row.
        pipe_changed = true
        output = pipe_visible.map(field => field.0)
        analytic_outputs.clear()
        analytic_expression_bindings.clear()
        analytic_input_fields = None
        analytic_input_scope = None
      }
      Where(predicate) if pipe_changed || pipe_rebound =>
        entries.push(
          (
            "filter",
            append_pipe_expression(
              construction,
              predicate,
              unnest_expression_columns(
                pipe_visible, value_table_receivers, scalar_value_table_ranges, pipe_columns,
              ),
              pipe_ranges,
              max_work,
              value_ranges=value_range_names(
                value_table_receivers, scalar_value_table_ranges,
              ),
            ),
          ),
        )
      Where(predicate) =>
        entries.push(
          (
            "filter",
            append_expression(
              construction, predicate, query, input, active_fields, max_work,
            ),
          ),
        )
      Extend(projections) if i > 0 &&
        (
          @query.operation_at(query, i - 1) is Some(Analytic(_)) ||
          @query.operation_at(query, i - 1) is Some(AnalyticExpressions(_, _))
        ) => {
        // Window results are already evaluated slots. The public snapshot
        // excludes them until every sibling expression has been resolved.
        pipe_value_table = false
        let snapshot = pipe_visible.copy()
        let input_columns = pipe_columns.copy()
        let next = snapshot.copy()
        let derived : Array[(String, @builder.Node)] = []
        for projection in projections {
          let name = projection.name.unwrap()
          if pipe_name_exists(next, name) {
            raise Abort(DuplicateOutput)
          }
          let slot = if projection.analytic is Some(_) {
            match analytic_output_slot(name.value, analytic_outputs) {
              Some(slot) => slot
              None => raise Abort(UnsupportedAnalytic)
            }
          } else {
            let slot = pipe_physical_name(active_fields, "aql_pipe_extend_")
            active_fields.push(slot)
            derived.push(
              (
                slot,
                append_pipe_expression(
                  construction,
                  projection.expression.unwrap(),
                  private_expression_columns(
                    unnest_expression_columns(
                      snapshot, value_table_receivers, scalar_value_table_ranges,
                      input_columns,
                    ),
                    analytic_expression_bindings,
                  ),
                  pipe_ranges,
                  max_work,
                  value_ranges=value_range_names(
                    value_table_receivers, scalar_value_table_ranges,
                  ),
                ),
              ),
            )
            slot
          }
          next.push((name.value, slot))
          pipe_columns.push((name.value, slot))
        }
        if derived.is_empty() {
          deferred = true
        } else {
          entries.push(("derive", construction.object(derived)))
        }
        pipe_visible = next
        output = next.map(entry => entry.0)
        pipe_changed = true
      }
      Extend(projections) if pipe_changed || pipe_rebound => {
        pipe_value_table = false
        let snapshot = pipe_visible.copy()
        let input_columns = pipe_columns.copy()
        let derived : Array[(String, @builder.Node)] = []
        let next = snapshot.copy()
        for projection in projections {
          let name = projection.name.unwrap()
          if pipe_name_exists(next, name) {
            raise Abort(DuplicateOutput)
          }
          let physical = pipe_physical_name(active_fields, "aql_pipe_extend_")
          active_fields.push(physical)
          derived.push(
            (
              physical,
              append_pipe_expression(
                construction,
                projection.expression.unwrap(),
                unnest_expression_columns(
                  snapshot, value_table_receivers, scalar_value_table_ranges, input_columns,
                ),
                pipe_ranges,
                max_work,
                value_ranges=value_range_names(
                  value_table_receivers, scalar_value_table_ranges,
                ),
              ),
            ),
          )
          next.push((name.value, physical))
          pipe_columns.push((name.value, physical))
        }
        entries.push(("derive", construction.object(derived)))
        pipe_visible = next
        output = next.map(entry => entry.0)
        pipe_changed = true
      }
      Extend(projections) => {
        pipe_value_table = false
        let derived : Array[(String, @builder.Node)] = []
        let new_fields : Array[String] = []
        let snapshot = active_fields.copy()
        for projection in projections {
          let name = projection.name.unwrap().value
          if snapshot.any(field => ascii_upper(field) == ascii_upper(name)) ||
            new_fields.any(field => ascii_upper(field) == ascii_upper(name)) {
            raise Abort(DuplicateOutput)
          }
          derived.push(
            (
              name,
              append_expression(
                construction,
                projection.expression.unwrap(),
                query,
                input,
                snapshot,
                max_work,
              ),
            ),
          )
          new_fields.push(name)
        }
        entries.push(("derive", construction.object(derived)))
        for name in new_fields {
          active_fields.push(name)
          output.push(name)
          pipe_visible.push((name, name))
          pipe_columns.push((name, name))
        }
        // EXTEND adds current columns, not members of an existing immutable
        // range. Later expressions resolve the saved range and current row.
        pipe_rebound = true
      }
      Set(assignments) => {
        pipe_value_table = false
        let snapshot = pipe_visible.copy()
        let target_columns = pipe_columns.copy()
        let window_bindings = if i > 0 &&
          @query.operation_at(query, i - 1) is Some(AnalyticExpressions(_, _)) {
          analytic_expression_bindings.copy()
        } else {
          []
        }
        let derived : Array[(String, @builder.Node)] = []
        let targets : Array[String] = []
        let replacements : Array[(String, String)] = []
        for assignment in assignments {
          // SET addresses one current column, not every matching JOIN slot.
          let matching_targets = target_columns.filter(entry => {
            same_name(assignment.0, { value: entry.0, quoted: false, })
          })
          if matching_targets.is_empty() {
            raise Abort(UnknownColumn)
          }
          if matching_targets.length() > 1 {
            raise Abort(AmbiguousColumn)
          }
          if targets.any(name => {
              same_name(assignment.0, { value: name, quoted: false, })
            }) {
            raise Abort(DuplicateOutput)
          }
          let physical = pipe_physical_name(active_fields, "aql_pipe_set_")
          active_fields.push(physical)
          derived.push(
            (
              physical,
              append_pipe_expression(
                construction,
                assignment.1,
                private_expression_columns(
                  unnest_expression_columns(
                    snapshot, value_table_receivers, scalar_value_table_ranges, pipe_columns,
                  ),
                  window_bindings,
                ),
                pipe_ranges,
                max_work,
                value_ranges=value_range_names(
                  value_table_receivers, scalar_value_table_ranges,
                ),
              ),
            ),
          )
          targets.push(assignment.0.value)
          replacements.push((assignment.0.value, physical))
        }
        let next = unnest_edit_visible(
          snapshot,
          pipe_value_columns,
          active_fields,
          replacements.map(replacement => (replacement.0, Some(replacement.1))),
        )
        entries.push(("derive", construction.object(derived)))
        pipe_visible = next
        pipe_value_columns = pipe_value_columns.filter(column => {
          !assignments.any(assignment => {
            same_name(assignment.0, { value: column.0, quoted: false, })
          })
        })
        pipe_columns = pipe_columns.map(column => {
          let matching = replacements.filter(replacement => {
            same_name({ value: column.0, quoted: false, }, {
              value: replacement.0,
              quoted: false,
            })
          })
          if matching.is_empty() {
            column
          } else {
            (column.0, matching[0].1)
          }
        })
        // Resolve every sibling against the old snapshot before removing a
        // range hidden by a replacement current column of the same name.
        pipe_ranges = pipe_ranges.filter(range => {
          !assignments.any(assignment => same_name(assignment.0, range.0))
        })
        value_table_receivers = value_table_receivers.filter(receiver => {
          !assignments.any(assignment => same_name(assignment.0, receiver.0))
        })
        scalar_value_table_ranges = scalar_value_table_ranges.filter(receiver => {
          !assignments.any(assignment => same_name(assignment.0, receiver.0))
        })
        output = pipe_visible.map(entry => entry.0)
        pipe_changed = true
        // All assignments use the pre-SET snapshot. Private window bindings
        // cannot become names in the next operator or immutable ranges.
        if !window_bindings.is_empty() {
          analytic_outputs.clear()
          analytic_expression_bindings.clear()
          analytic_input_fields = None
          analytic_input_scope = None
        }
      }
      Drop(names) => {
        // A positional DROP removes all occurrences of an authored name. Use
        // the star-exclusion correspondence before ordinary physical removal.
        let names = if positional_projection is Some(projection) &&
          i > projection {
          let physical : Array[@query.NamePart] = []
          for name in names {
            if names.filter(other => same_name(name, other)).length() != 1 {
              raise Abort(DuplicateOutput)
            }
            let matches = pipe_columns.filter(column => {
              same_name(name, {
                value: positional_authored_column_name(
                  column.0,
                  positional_authored_aliases,
                ),
                quoted: false,
              })
            })
            if matches.is_empty() {
              raise Abort(UnknownColumn)
            }
            physical.append(
              matches.map(column => { value: column.0, quoted: false, }),
            )
          }
          physical
        } else {
          names
        }
        // A structural DROP does not read values from retained columns. When
        // the current visible names already are the physical row slots, use
        // the existing operation rather than manufacturing a final SELECT
        // that would require presence for every retained Conditional column.
        let mut structural_tail = true
        for next_index in (i + 1)..<@query.operation_count(query) {
          match @query.operation_at(query, next_index) {
            Some(Order(terms)) =>
              if !terms.all(term => {
                  match
                    @query.expression_node(
                      term.expression,
                      @query.expression_root(term.expression),
                    ).unwrap().kind {
                    Reference(path) => path.length() == 1
                    _ => false
                  }
                }) {
                structural_tail = false
              }
            Some(Limit(_, _)) => ()
            _ => structural_tail = false
          }
        }
        // A later projection/expression may still use a retained input range.
        // Do not discard those physical slots while that scope is observable.
        let direct = preserved_scope is None &&
          value_table_receivers.is_empty() &&
          structural_tail &&
          active_fields.length() == pipe_visible.length() &&
          pipe_visible.all(pair => {
            pair.0 == pair.1 && active_fields.contains(pair.1)
          })
        let dropped = pipe_visible.filter(current => {
          names.any(name => {
            same_name(name, { value: current.0, quoted: false, })
          })
        })
        let target_columns = pipe_columns.copy()
        for name in names {
          if !pipe_name_exists(target_columns, name) {
            raise Abort(UnknownColumn)
          }
          if names.filter(other => same_name(name, other)).length() != 1 {
            raise Abort(DuplicateOutput)
          }
        }
        let next = unnest_edit_visible(
          pipe_visible,
          pipe_value_columns,
          active_fields,
          names.map(name => (name.value, None)),
        )
        pipe_visible = next
        pipe_value_columns = pipe_value_columns.filter(column => {
          !names.any(name => {
            same_name(name, { value: column.0, quoted: false, })
          })
        })
        pipe_columns = pipe_columns.filter(column => {
          !names.any(name => {
            same_name(name, { value: column.0, quoted: false, })
          })
        })
        output = next.map(entry => entry.0)
        if next.is_empty() {
          raise Abort(UnsupportedProjection)
        }
        // DROP excludes matching range names as well as current columns.
        // Other ranges keep their original slots, including dropped columns.
        pipe_ranges = pipe_ranges.filter(range => {
          !names.any(name => same_name(name, range.0))
        })
        value_table_receivers = value_table_receivers.filter(receiver => {
          !names.any(name => same_name(name, receiver.0))
        })
        scalar_value_table_ranges = scalar_value_table_ranges.filter(receiver => {
          !names.any(name => same_name(name, receiver.0))
        })
        if direct {
          entries.push(
            (
              "drop",
              construction.array(dropped.map(pair => construction.text(pair.1))),
            ),
          )
          active_fields = next.map(pair => pair.1)
          pipe_changed = false
          pipe_ranges = []
          pipe_star_ranges = []
          scalar_value_table_ranges = []
          value_table_receivers = []
          pipe_value_columns = []
          pipe_value_table = false
          pipe_rebound = true
        } else {
          pipe_changed = true
          deferred = true
        }
      }
      Rename(names) => {
        let target_columns = pipe_columns.copy()
        // RENAME targets the pre-operator current row. Unrelated duplicate
        // names, and ambiguities introduced by renaming, can be resolved by
        // a later projection through the retained immutable ranges.
        for replacement in names {
          let matches = target_columns.filter(current => {
            same_name(replacement.0, { value: current.0, quoted: false, })
          })
          if matches.is_empty() {
            raise Abort(UnknownColumn)
          }
          if names.filter(other => same_name(other.0, replacement.0)).length() !=
            1 {
            raise Abort(DuplicateOutput)
          }
          if matches.length() > 1 {
            raise Abort(AmbiguousColumn)
          }
          // Unlike SET/DROP, RENAME requires an unambiguous scope target;
          // a range of the same name takes precedence over the column.
          if pipe_ranges.any(range => same_name(replacement.0, range.0)) ||
            value_table_receivers.any(receiver => {
              same_name(replacement.0, receiver.0)
            }) {
            raise Abort(AmbiguousColumn)
          }
        }
        let next : Array[(String, String)] = []
        for current in pipe_visible {
          let mut name = current.0
          for replacement in names {
            if pipe_columns.any(column => {
                column.1 == current.1 &&
                same_name(replacement.0, { value: column.0, quoted: false, })
              }) {
              name = replacement.1.value
            }
          }
          next.push((name, current.1))
        }
        pipe_visible = next
        pipe_value_columns = pipe_value_columns.map(column => {
          let renamed = names.filter(replacement => {
            same_name(replacement.0, { value: column.0, quoted: false, })
          })
          if renamed.is_empty() {
            column
          } else {
            (renamed[0].1.value, column.1, column.2)
          }
        })
        pipe_columns = pipe_columns.map(column => {
          let matching = names.filter(replacement => {
            same_name(replacement.0, { value: column.0, quoted: false, })
          })
          if matching.is_empty() {
            column
          } else {
            (matching[0].1.value, column.1)
          }
        })
        output = next.map(entry => entry.0)
        pipe_changed = true
        deferred = true
        if positional_projection is Some(projection) && i > projection {
          let names = next.map(entry => entry.0)
          let bindings = next.copy()
          let selected = next.map(entry => {
            construction.object([(entry.0, construction.text(entry.1))])
          })
          let private_fields = privatize_positional_duplicate_columns(
            construction,
            names,
            bindings,
            selected,
            active_fields,
            authored_aliases=Some(positional_authored_aliases),
            reserved_names=positional_destination_names,
          )
          if !private_fields.is_empty() {
            positional_private_fields.append(private_fields)
            entries.push(("select", construction.array(selected)))
            active_fields = names.copy()
            output = names
            pipe_visible = names.map(name => (name, name))
            pipe_columns = pipe_visible.copy()
            pipe_changed = false
            reset_infer_key_labels = true
            deferred = false
          }
        }
      }
      Alias(name) => {
        // Preserve a single value table. On an ordinary row, former value
        // ranges become current whole columns; neither case computes values.
        if pipe_value_table && pipe_columns.length() == 1 {
          let slot = pipe_columns[0].1
          pipe_columns = [(name.value, slot)]
          if !pipe_value_columns.is_empty() {
            pipe_value_columns = pipe_value_columns.map(column => {
              (name.value, column.1, column.2)
            })
            value_table_receivers = [(name, slot)]
            scalar_value_table_ranges = []
            pipe_ranges = [(name, pipe_visible.copy())]
          } else {
            pipe_visible = [(name.value, slot)]
            value_table_receivers = []
            scalar_value_table_ranges = [(name, slot)]
            pipe_ranges = [(name, [])]
          }
        } else {
          let columns = unnest_expression_columns(
            pipe_visible,
            [],
            [],
            pipe_columns,
          )
          let columns = if positional_projection is Some(projection) &&
            i > projection {
            positional_named_expression_columns(
              columns, positional_private_fields, positional_authored_aliases,
            )
          } else {
            columns
          }
          pipe_ranges = [(name, columns)]
          scalar_value_table_ranges = []
          value_table_receivers = []
          pipe_value_table = false
        }
        // The new range captures the current star layout, independently of
        // whole columns admitted for expression lookup. SET/DROP/RENAME keep
        // this snapshot immutable, just like ordinary table range bindings.
        pipe_star_ranges = [(name, pipe_visible.copy())]
        output = pipe_visible.map(column => column.0)
        pipe_rebound = true
        pipe_changed = true
        deferred = true
      }
      Pivot(clause) => {
        if pipe_value_table {
          raise Abort(UnsupportedGrouping)
        }
        let row_witness = if clause.count_star {
          // Every matching row counts, including NULLs in other columns.
          // This private value is not an implicit grouping column.
          let reserved = active_fields + pipe_columns.map(column => column.0)
          for entry in clause.values {
            let suffix = entry.1.map(name => name.value).unwrap_or(entry.0)
            reserved.push(
              clause.prefix
              .map(prefix => prefix.value + "_" + suffix)
              .unwrap_or(suffix),
            )
          }
          let name = pipe_physical_name(reserved, "aql_pivot_row_")
          entries.push(
            (
              "derive",
              construction.object([
                (
                  name,
                  construction.object([
                    ("literal", construction.add(Number(1.0))),
                  ]),
                ),
              ]),
            ),
          )
          step_entries.push(entries.copy())
          entries.clear()
          active_fields.push(name)
          Some(name)
        } else {
          None
        }
        let consumed_fields : Array[String] = []
        let direct_argument = clause.argument_expression
          .map(expression => {
            @query.expression_node(
              expression,
              @query.expression_root(expression),
            ).unwrap().kind
            is Reference(_) &&
            pipe_expression_slot(
              clause.argument,
              pipe_visible,
              pipe_ranges,
              value_ranges=value_range_names(
                value_table_receivers, scalar_value_table_ranges,
              ),
            )
            is Some(_)
          })
          .unwrap_or(false)
        let argument_value = if !clause.count_star &&
          clause.argument_expression is Some(expression) &&
          !direct_argument {
          let resolve = path => {
            pipe_expression_slot(
              path,
              pipe_visible,
              pipe_ranges,
              value_ranges=value_range_names(
                value_table_receivers, scalar_value_table_ranges,
              ),
            )
          }
          if @query.expression_node(
              expression,
              @query.expression_root(expression),
            ).unwrap().kind
            is Reference(path) &&
            order_reference_identity(path, resolve) is None &&
            !(path.length() == 1 &&
            pipe_ranges.any(range => same_name(path[0], range.0))) {
            // Preserve the existing unknown-column diagnostic for a simple
            // argument; a known receiver's property goes through common typing.
            raise Abort(UnknownColumn)
          }
          for path in join_reference_paths(expression) {
            if order_reference_identity(path, resolve) is Some((slot, _)) {
              if !consumed_fields.contains(slot) {
                consumed_fields.push(slot)
              }
            } else if path.length() == 1 {
              // A whole-row receiver statically references its range fields.
              for range in pipe_ranges {
                if same_name(path[0], range.0) {
                  for field in range.1 {
                    if !consumed_fields.contains(field.1) {
                      consumed_fields.push(field.1)
                    }
                  }
                }
              }
            }
          }
          let value = append_pipe_expression(
            construction,
            expression,
            unnest_expression_columns(
              pipe_visible, value_table_receivers, scalar_value_table_ranges, pipe_columns,
            ),
            pipe_ranges,
            max_work,
            value_ranges=value_range_names(
              value_table_receivers, scalar_value_table_ranges,
            ),
          )
          let reserved = active_fields + pipe_columns.map(field => field.0)
          for entry in clause.values {
            let suffix = entry.1.map(name => name.value).unwrap_or(entry.0)
            reserved.push(
              clause.prefix
              .map(prefix => prefix.value + "_" + suffix)
              .unwrap_or(suffix),
            )
          }
          let name = pipe_physical_name(reserved, "aql_pivot_argument_")
          entries.push(("derive", construction.object([(name, value)])))
          step_entries.push(entries.copy())
          entries.clear()
          active_fields.push(name)
          Some(name)
        } else {
          None
        }
        let (pivot, visible) = compile_pipe_pivot(
          construction,
          clause,
          pipe_visible,
          pipe_columns,
          pipe_ranges,
          argument_value~,
          row_witness~,
          consumed_fields~,
          authored_aliases=positional_authored_aliases,
        )
        entries.push(("pivot", pivot))
        step_entries.push(entries)
        pipe_visible = visible
        pipe_columns = visible.copy()
        active_fields = visible.map(pair => pair.1)
        output = visible.map(pair => pair.0)
        pipe_ranges = []
        pipe_star_ranges = []
        value_table_receivers = []
        scalar_value_table_ranges = []
        pipe_value_columns = []
        pipe_rebound = true
        pipe_changed = true
        deferred = true
      }
      Group(keys, projections, grouping_scope) => {
        anonymous_set_aggregate_slots.clear()
        positional_set_aggregate_slots.clear()
        let scoped = pipe_changed || pipe_rebound
        let input_visible = pipe_visible.copy()
        let input_ranges = pipe_ranges.copy()
        let input_fields = active_fields.copy()
        let projections = expand_projections(
          query, projections, input_visible, input_ranges, max_work,
        )
        sql_group_projection = grouping_scope == @query.SqlSelect ||
          grouping_scope == @query.SqlSelectAll
        let all = grouping_scope == @query.SqlSelectAll
        let keys = if all {
          inferred_group_keys(
            query,
            projections,
            input_visible,
            input_ranges,
            path => {
              if scoped {
                pipe_slot(
                  path,
                  unnest_expression_columns(
                    input_visible, value_table_receivers, scalar_value_table_ranges,
                    pipe_columns,
                  ),
                  input_ranges,
                )
              } else {
                resolve_column(path, query, input, input_fields)
              }
            },
            max_work,
          )
        } else {
          keys
        }
        if sql_group_projection {
          // SQL star names the input row, before grouping removes columns or
          // adds aggregate slots. Every expanded value must still be grouped.
          sql_group_expression_input_scope = Some({
            visible: unnest_expression_columns(
              input_visible, value_table_receivers, scalar_value_table_ranges, pipe_columns,
            ),
            ranges: input_ranges.copy(),
            columns: pipe_columns.copy(),
            value_table: pipe_value_table,
            value_columns: pipe_value_columns.copy(),
            star_ranges: pipe_star_ranges.copy(),
            receivers: value_table_receivers.copy(),
            key_labels: infer_key_labels.copy(),
            scalar_ranges: scalar_value_table_ranges.copy(),
          })
          sql_group_input_columns = input_visible.copy()
          sql_group_input_ranges = unnest_star_ranges(
            input_ranges, pipe_star_ranges,
          )
          sql_group_selected_projections = expand_projections(
            query,
            selected_projections(query),
            input_visible,
            input_ranges,
            max_work,
          )
        }
        let hidden_calls = match @query.operation_at(query, i + 1) {
          Some(Having(_, calls)) => calls.copy()
          _ => []
        }
        for next in (i + 1)..<@query.operation_count(query) {
          match @query.operation_at(query, next) {
            Some(Qualify(_, calls)) => hidden_calls.append(calls)
            Some(Select(_, _)) => break
            _ => ()
          }
        }
        // Classify against expanded SELECT aggregates, preserving input aliases.
        let order_calls = if sql_group_projection {
          order_aggregate_calls(
            query, projections, sql_group_selected_projections,
          )
        } else {
          []
        }
        hidden_calls.append(order_calls)
        grouped_keys.clear()
        having_values.clear()
        having_aggregate_slots.clear()
        sql_group_aggregate_slots.clear()
        order_aggregate_slots.clear()
        // A sole global DISTINCT ARRAY_AGG ordered by the same referenced
        // value can obtain its candidate key from ordinary row DISTINCT.
        // Project the value first so no unrelated column supplies a chosen
        // representative. The checker still rejects nullable keys.
        if !scoped &&
          keys.is_empty() &&
          projections.length() == 1 &&
          hidden_calls.is_empty() {
          match projections[0].aggregate {
            Some(call) if call.function_name == "ARRAY_AGG" &&
              call.filter is None &&
              call.distinct &&
              call.order_by.length() == 1 =>
              match call.argument {
                Some(argument) if aggregate_order_matches_argument(
                    argument,
                    call.order_by[0].expression,
                    path => resolve_column(path, query, input, active_fields),
                  ) => {
                  let mut root_index = @query.expression_root(argument)
                  while @query.expression_node(argument, root_index).unwrap().kind
                        is Parenthesized(child) {
                    root_index = child
                  }
                  let root = @query.expression_node(argument, root_index).unwrap()
                  match root.kind {
                    // This key is established only for a complete input column.
                    // Static members retain ordinary property/order checking.
                    Reference(path) if resolve_column(
                        path, query, input, active_fields,
                      )
                      is Some(field) => {
                      let selected = entries.copy()
                      entries.clear()
                      selected.push(
                        (
                          "select",
                          construction.array([construction.text(field)]),
                        ),
                      )
                      step_entries.push(selected)
                      step_entries.push([
                        (
                          "distinct",
                          construction.array([construction.text(field)]),
                        ),
                      ])
                    }
                    _ => ()
                  }
                }
                _ => ()
              }
            _ => ()
          }
        }
        let derives : Array[(String, @builder.Node)] = []
        let hidden_order_derives : Array[(String, @builder.Node)] = []
        let key_names : Array[String] = []
        let key_display_names : Array[String] = []
        let key_aliases = match grouping_scope {
          SqlSelect | SqlSelectAll => []
          PipeAggregate(names, _) => names
        }
        let pipe_embedded = match grouping_scope {
          SqlSelect | SqlSelectAll => []
          PipeAggregate(_, names) => names
        }
        let by : Array[@builder.Node] = []
        let mut key_reuse_work = max_work
        let resolve_key_input = path => {
          if scoped {
            pipe_slot(
              path,
              unnest_expression_columns(
                input_visible, value_table_receivers, scalar_value_table_ranges,
                pipe_columns,
              ),
              input_ranges,
            )
          } else {
            resolve_column(path, query, input, input_fields)
          }
        }
        for index in 0..<keys.length() {
          // Inferred SELECT expressions already name the input snapshot.
          // Applying explicit GROUP alias/ordinal resolution would change them.
          let key = if all {
            GroupKeyReference::Expression(keys[index])
          } else {
            resolved_group_key(
              keys[index],
              projections,
              input_visible,
              sql_group_projection,
              ranges=input_ranges,
            )
          }
          let expression = match key {
            Expression(expression) => expression
            StarColumn(column) => {
              if key_names.contains(column.1) {
                continue
              }
              key_names.push(column.1)
              key_display_names.push(column.0)
              by.push(construction.text(column.1))
              // A positional reference is not the literal expression at that
              // position. Never add it to SELECT-expression reuse evidence.
              continue
            }
          }
          if sql_group_projection {
            // SQL repeats a grouping value, not a new output column. Use the
            // resolved input meaning rather than authored alias/path spelling.
            // Pipe AGGREGATE retains its separate named-output contract.
            let mut reused = false
            for (previous, _) in grouped_keys {
              for
                charge in [
                  1,
                  @query.expression_node_count(previous),
                  @query.expression_node_count(expression),
                ] {
                if charge > key_reuse_work {
                  raise Abort(
                    Expression({
                      issue: @expression.WorkLimit,
                      origin: @query.expression_origin(
                        expression,
                        @query.expression_root(expression),
                      ),
                    }),
                  )
                }
                key_reuse_work -= charge
              }
              if same_group_expression_in_scopes(
                  previous, expression, resolve_key_input, resolve_key_input,
                ) {
                reused = true
                break
              }
            }
            if reused {
              continue
            }
          }
          let mut root_index = @query.expression_root(expression)
          while @query.expression_node(expression, root_index).unwrap().kind
                is Parenthesized(child) {
            root_index = child
          }
          let root = @query.expression_node(expression, root_index).unwrap()
          let direct = match root.kind {
            Reference(path) =>
              if scoped {
                pipe_slot(
                  path,
                  unnest_expression_columns(
                    pipe_visible, value_table_receivers, scalar_value_table_ranges,
                    pipe_columns,
                  ),
                  pipe_ranges,
                )
              } else {
                resolve_column(path, query, input, active_fields)
              }
            _ => None
          }
          if sql_group_projection &&
            direct is Some(field) &&
            key_names.contains(field) {
            // A prior expanded-star ordinal has no expression tree, but its
            // checked physical field still proves this direct key's identity.
            grouped_keys.push((expression, field))
            continue
          }
          let name = match direct {
            Some(field) => field
            None => {
              if root.kind is Reference(path) && path.length() == 1 {
                raise Abort(UnknownColumn)
              }
              let mut serial = index
              let mut name = "aql_group_key_" + serial.to_string()
              // Authored input/output names do not reserve a language prefix.
              // Keep each computed key in a distinct private physical slot.
              while (active_fields + key_names).any(field => {
                      ascii_upper(field) == ascii_upper(name)
                    }) ||
                    projections.any(projection => {
                      projection_alias(projection) is Some(column_name) &&
                      ascii_upper(column_name.value) == ascii_upper(name)
                    }) {
                serial += 1
                name = "aql_group_key_" + serial.to_string()
              }
              derives.push(
                (
                  name,
                  if scoped {
                    append_pipe_expression(
                      construction,
                      expression,
                      unnest_expression_columns(
                        pipe_visible, value_table_receivers, scalar_value_table_ranges,
                        pipe_columns,
                      ),
                      pipe_ranges,
                      max_work,
                      value_ranges=value_range_names(
                        value_table_receivers, scalar_value_table_ranges,
                      ),
                    )
                  } else {
                    append_expression(
                      construction, expression, query, input, active_fields, max_work,
                    )
                  },
                ),
              )
              name
            }
          }
          key_names.push(name)
          key_display_names.push(
            match key_aliases.get(index).bind(value => value) {
              Some(output_name) => output_name.value
              None =>
                match root.kind {
                  Reference(path) => path.last().unwrap().value
                  Property(_, name) => name.value
                  _ => name
                }
            },
          )
          by.push(construction.text(name))
          grouped_keys.push((expression, name))
          if sql_group_projection {
            // GROUP retains the complete numeric operation. Its operand has
            // the same value only after that key passes ordinary admission;
            // SELECT/HAVING/ORDER may then reuse the evaluated key slot.
            let charge = 1 + @query.expression_node_count(expression)
            if charge > key_reuse_work {
              raise Abort(
                Expression({
                  issue: @expression.WorkLimit,
                  origin: @query.expression_origin(
                    expression,
                    @query.expression_root(expression),
                  ),
                }),
              )
            }
            key_reuse_work -= charge
            if group_unary_plus_operand(expression) is Some(operand) {
              grouped_keys.push((operand, name))
            }
          }
        }
        if sql_group_projection {
          // Record only SELECT trees proven to mean the same evaluated key.
          // Reusing the key does not revive its original object after GROUP.
          let keys = grouped_keys.copy()
          let resolve = path => {
            if scoped {
              pipe_slot(
                path,
                unnest_expression_columns(
                  input_visible, value_table_receivers, scalar_value_table_ranges,
                  pipe_columns,
                ),
                input_ranges,
              )
            } else {
              resolve_column(path, query, input, active_fields)
            }
          }
          for projection in projections {
            if projection.expression is Some(expression) {
              for (key, slot) in keys {
                if same_group_expression_in_scopes(
                    key, expression, resolve, resolve,
                  ) {
                  grouped_keys.push((expression, slot))
                  break
                }
              }
            }
          }
        }
        if sql_group_projection {
          // SELECT siblings resolve against retained GROUP input values.
          // Newly declared aggregate aliases are visible to HAVING/ORDER,
          // not to ordinary expressions in that same SELECT list.
          sql_group_select_scope = Some({
            visible: unnest_expression_columns(
              input_visible, value_table_receivers, scalar_value_table_ranges, pipe_columns,
            ).filter(entry => key_names.contains(entry.1)),
            ranges: input_ranges.map(range => {
              (range.0, range.1.filter(entry => key_names.contains(entry.1)))
            }),
            columns: pipe_columns.copy(),
            value_table: pipe_value_table,
            value_columns: pipe_value_columns.copy(),
            star_ranges: pipe_star_ranges.copy(),
            receivers: value_table_receivers.copy(),
            key_labels: infer_key_labels.copy(),
            scalar_ranges: scalar_value_table_ranges.filter(receiver => {
              key_names.contains(receiver.1)
            }),
          })
        }
        if sql_group_projection {
          for projection in projections {
            if projection.star is Some(_) &&
              expanded_star_columns(
                projection,
                sql_group_input_columns,
                ranges=sql_group_input_ranges,
              ).any(column => !key_names.contains(column.1)) {
              // Excluded input columns are not projected; every retained star
              // value must still be grouped before aggregate slots are added.
              raise Abort(InvalidQuery)
            }
          }
        }
        let order_reserved = active_fields.copy() + key_names
        for projection in projections {
          if projection_alias(projection) is Some(name) {
            order_reserved.push(name.value)
          }
        }
        let order_evaluated : Array[(@query.Expression, String)] = []
        let aggregates : Array[(String, @builder.Node)] = []
        let result_fields : Array[String] = []
        for name in key_names {
          if !result_fields.contains(name) {
            result_fields.push(name)
          }
        }
        let selected = if sql_group_projection {
          sql_group_selected_projections
        } else {
          selected_projections(query)
        }
        let select_calls : Array[(@query.AggregateCall, String)] = []
        let pipe_embedded_slots : Array[(String, String)] = []
        let pipe_output_slots : Array[(String, String)] = []
        let resolve_input = path => {
          if scoped {
            pipe_slot(
              path,
              unnest_expression_columns(
                input_visible, value_table_receivers, scalar_value_table_ranges,
                pipe_columns,
              ),
              input_ranges,
            )
          } else {
            resolve_column(path, query, input, input_fields)
          }
        }
        for projection in projections {
          if order_calls.any(pair => projection.name == Some(pair.0)) {
            // ORDER arguments use the same alias-aware input snapshot as
            // HAVING, rather than SELECT's input-only argument resolution.
            continue
          }
          match projection.aggregate {
            Some(call) => {
              let name = match projection.name {
                Some(name) => name.value
                None => {
                  if !positional_set_output || !sql_group_projection {
                    raise Abort(UnsupportedProjection)
                  }
                  pipe_physical_name(
                    order_reserved + result_fields,
                    "aql_set_aggregate_",
                  )
                }
              }
              let embedded = projection.name
                .map(name => pipe_embedded.contains(name))
                .unwrap_or(false) ||
                (
                  sql_group_projection &&
                  !selected.any(item => {
                    item.aggregate is Some(_) && item.name == projection.name
                  })
                )
              let mut reused : String? = None
              if embedded {
                for (previous, slot) in select_calls {
                  if same_aggregate_call(
                      previous, call, resolve_input, resolve_input,
                    ) {
                    reused = Some(slot)
                    break
                  }
                }
              }
              let slot = match reused {
                Some(slot) => slot
                None => {
                  let output_name = if (
                      embedded && active_fields.contains(name)
                    ) ||
                    result_fields.contains(name) ||
                    (
                      positional_set_output &&
                      sql_group_projection &&
                      positional_projection is Some(_) &&
                      duplicate_projection_alias(selected, name)
                    ) {
                    pipe_physical_name(
                      order_reserved + result_fields,
                      "aql_select_aggregate_",
                    )
                  } else {
                    name
                  }
                  if result_fields.contains(output_name) ||
                    aggregates.any(entry => entry.0 == output_name) {
                    raise Abort(DuplicateOutput)
                  }
                  let order_fields = aggregate_order_fields(
                    construction, call, resolve_input, order_reserved, order_evaluated,
                    derives, max_work,
                  )
                  aggregates.push(
                    (
                      output_name,
                      if scoped {
                        lower_aggregate_resolved(
                          construction,
                          call,
                          resolve_input,
                          max_work,
                          max_collection_items,
                          max_collection_bytes,
                          order_fields=Some(order_fields),
                        )
                      } else {
                        lower_aggregate(
                          construction,
                          call,
                          query,
                          input,
                          active_fields,
                          max_work,
                          max_collection_items,
                          max_collection_bytes,
                          order_fields=Some(order_fields),
                        )
                      },
                    ),
                  )
                  result_fields.push(output_name)
                  select_calls.push((call, output_name))
                  output_name
                }
              }
              if sql_group_projection && !embedded {
                // The SELECT alias may have the same name as a retained key.
                // The input binding and aggregate result are distinct values.
                sql_group_aggregate_slots.push((name, slot))
                if positional_set_output &&
                  positional_projection is Some(_) &&
                  duplicate_projection_alias(selected, name) {
                  positional_set_aggregate_slots.push((call, slot))
                }
                if projection.name is None {
                  anonymous_set_aggregate_slots.push((call, slot))
                }
              }
              if embedded && sql_group_projection {
                // Only parser-owned embedded calls enter SELECT's scalar
                // scope. An authored sibling alias still cannot be read here.
                let scope = sql_group_select_scope.unwrap()
                sql_group_select_scope = Some({
                  ..scope,
                  // fresh_producer excludes every authored token with this
                  // name. A star may still retain an implicit input column;
                  // its public selection keeps the original physical binding.
                  visible: scope.visible.filter(entry => {
                    ascii_upper(entry.0) != ascii_upper(name)
                  }) +
                  [(name, slot)],
                })
              } else if embedded {
                pipe_embedded_slots.push((name, slot))
              }
              if !sql_group_projection && !embedded {
                pipe_output_slots.push((name, slot))
              }
            }
            None => ()
          }
        }
        if sql_group_projection && !hidden_calls.is_empty() {
          let input_resolve = path => {
            if scoped {
              pipe_slot(
                path,
                unnest_expression_columns(
                  input_visible, value_table_receivers, scalar_value_table_ranges,
                  pipe_columns,
                ),
                input_ranges,
              )
            } else {
              resolve_column(path, query, input, active_fields)
            }
          }
          let aliases : Array[(String, String)] = []
          let physical = active_fields +
            key_names +
            projections.filter_map(projection => {
              projection_alias(projection).map(name => name.value)
            })
          let references : Array[Array[@query.NamePart]] = []
          for (_, call) in hidden_calls {
            if call.argument is Some(expression) {
              references.append(join_reference_paths(expression))
            }
            if call.filter is Some(expression) {
              references.append(join_reference_paths(expression))
            }
            for term in call.order_by {
              references.append(join_reference_paths(term.expression))
            }
          }
          for projection in projections {
            guard projection_alias(projection) is Some(column_name) &&
              projection.expression is Some(expression) else {
              continue
            }
            if !references.any(path => {
                if !same_name(path[0], column_name) {
                  return false
                }
                let mut length = path.length()
                while length > 1 {
                  if input_resolve(path[:length].to_owned()) is Some(_) {
                    return false
                  }
                  length -= 1
                }
                true
              }) {
              continue
            }
            // HAVING/ORDER arguments use pre-group SELECT alias values.
            // Evaluate each needed alias once in the original input snapshot.
            let mut slot : String? = None
            for (key, name) in grouped_keys {
              if same_group_expression_in_scopes(
                  key, expression, input_resolve, input_resolve,
                ) {
                slot = Some(name)
                break
              }
            }
            let slot = match slot {
              Some(slot) => slot
              None => {
                let slot = pipe_physical_name(physical, "aql_having_argument_")
                physical.push(slot)
                let value = match
                  @expression.append_with_properties(
                    expression,
                    input_resolve,
                    construction.builder,
                    max_work,
                    resolve_parameter=construction.parameter_resolver(),
                  ) {
                  Ok(value) => value
                  Err(error) => raise Abort(Expression(error))
                }
                derives.push((slot, value))
                slot
              }
            }
            aliases.push((column_name.value, slot))
          }
          let resolve = fn(path : Array[@query.NamePart]) -> String? {
            if path.length() != 1 {
              return input_resolve(path)
            }
            let matches = projections.filter(projection => {
              projection_alias(projection) is Some(name) &&
              same_name(name, path[0])
            })
            if matches.is_empty() {
              return input_resolve(path)
            }
            // An aggregate/analytic alias cannot become another aggregate input.
            if matches.length() != 1 || matches[0].expression is None {
              return None
            }
            for (name, slot) in aliases {
              if name == projection_alias(matches[0]).unwrap().value {
                return Some(slot)
              }
            }
            None
          }
          let known : Array[(@query.AggregateCall, String, Bool)] = []
          for (call, slot) in select_calls {
            known.push((call, slot, false))
          }
          // HAVING uses its resolved SELECT aliases; its order expressions must
          // not reuse projections cached in the SELECT aggregate input scope.
          let hidden_order_evaluated : Array[(@query.Expression, String)] = []
          for (name, call) in hidden_calls {
            let mut reuse : String? = None
            for (previous, slot, hidden) in known {
              if same_aggregate_call(
                  previous,
                  call,
                  if hidden {
                    resolve
                  } else {
                    input_resolve
                  },
                  resolve,
                ) {
                reuse = Some(slot)
                break
              }
            }
            let slot = match reuse {
              Some(slot) => slot
              None => {
                let slot = if result_fields.contains(name.value) {
                  pipe_physical_name(result_fields, "aql_having_aggregate_")
                } else {
                  name.value
                }
                let order_fields = aggregate_order_fields(
                  construction, call, resolve, order_reserved, hidden_order_evaluated,
                  hidden_order_derives, max_work,
                )
                aggregates.push(
                  (
                    slot,
                    lower_aggregate_resolved(
                      construction,
                      call,
                      resolve,
                      max_work,
                      max_collection_items,
                      max_collection_bytes,
                      order_fields=Some(order_fields),
                    ),
                  ),
                )
                result_fields.push(slot)
                known.push((call, slot, true))
                slot
              }
            }
            having_aggregate_slots.push((name.value, slot))
            if order_calls.any(pair => pair.0 == name) {
              order_aggregate_slots.push((name.value, slot))
            }
          }
        }
        // Property order can depend on a SELECT alias evaluated above. Common
        // derive fields share an input snapshot, so emit the dependency next.
        for fields in [derives, hidden_order_derives] {
          if fields.is_empty() {
            continue
          }
          let derive_step : Array[(String, @builder.Node)] = []
          if entries.length() == 1 {
            derive_step.push(entries[0])
            entries.clear()
          }
          derive_step.push(("derive", construction.object(fields)))
          step_entries.push(derive_step)
        }
        entries.push(
          (
            "group",
            construction.object([
              ("by", construction.array(by)),
              ("aggregates", construction.object(aggregates)),
            ]),
          ),
        )
        active_fields = result_fields.copy()
        output = result_fields
        if sql_group_projection &&
          (
            scoped ||
            !order_calls.is_empty() ||
            sql_group_aggregate_slots.any(entry => entry.0 != entry.1)
          ) {
          // SQL retains only grouped input bindings until its SELECT. Private
          // JOIN slots stay physical; qualified names are never flattened.
          pipe_visible = unnest_expression_columns(
            input_visible, value_table_receivers, scalar_value_table_ranges, pipe_columns,
          ).filter(entry => key_names.contains(entry.1))
          for entry in aggregates {
            pipe_visible.push((entry.0, entry.0))
          }
          for (name, slot) in sql_group_aggregate_slots {
            pipe_visible = pipe_visible.filter(entry => {
              !same_name({ value: name, quoted: false, }, {
                value: entry.0,
                quoted: false,
              })
            })
            pipe_visible.push((name, slot))
          }
          for (name, _) in order_calls {
            for (logical, slot) in having_aggregate_slots {
              if name.value == logical &&
                !pipe_visible.contains((logical, slot)) {
                // A star can expose an input whose name was absent from
                // authored tokens. Keep its public physical value separate
                // from this parser-owned aggregate reference.
                pipe_visible = pipe_visible.filter(entry => {
                  ascii_upper(entry.0) != ascii_upper(logical)
                })
                pipe_visible.push((logical, slot))
              }
            }
          }
          pipe_ranges = input_ranges.map(range => {
            (range.0, range.1.filter(entry => key_names.contains(entry.1)))
          })
          pipe_star_ranges = pipe_star_ranges.map(range => {
            (range.0, range.1.filter(entry => key_names.contains(entry.1)))
          })
          pipe_changed = true
        } else if !sql_group_projection {
          // Pipe AGGREGATE creates a new row scope. Rename only the retained
          // group keys after aggregation; arguments used the old value slots.
          let names : Array[String] = []
          let selected : Array[@builder.Node] = []
          for index in 0..<key_names.length() {
            let name = key_display_names[index]
            if names.any(previous => ascii_upper(previous) == ascii_upper(name)) {
              raise Abort(DuplicateOutput)
            }
            names.push(name)
            selected.push(
              if name == key_names[index] {
                construction.text(name)
              } else {
                construction.object([
                  (name, construction.text(key_names[index])),
                ])
              },
            )
          }
          // Scalar aggregate expressions read retained input keys and private
          // aggregate slots. Published sibling aliases are not input bindings.
          let scalar_visible = input_visible.filter(entry => {
              key_names.contains(entry.1)
            }) +
            pipe_embedded_slots
          let scalar_ranges = input_ranges.map(range => {
            (range.0, range.1.filter(entry => key_names.contains(entry.1)))
          })
          let scalar_derives : Array[(String, @builder.Node)] = []
          for projection in projections {
            if pipe_embedded.contains(projection.name.unwrap()) {
              continue
            }
            let name = projection.name.unwrap().value
            if names.any(previous => ascii_upper(previous) == ascii_upper(name)) {
              raise Abort(DuplicateOutput)
            }
            let slot = if projection.aggregate is Some(_) {
              let mut result : String? = None
              for entry in pipe_output_slots {
                if entry.0 == name {
                  result = Some(entry.1)
                  break
                }
              }
              result.unwrap()
            } else {
              let mut suffix = scalar_derives.length()
              let mut slot = "aql_pipe_aggregate_" + suffix.to_string()
              while active_fields.contains(slot) ||
                    names.contains(slot) ||
                    scalar_derives.any(entry => entry.0 == slot) {
                suffix += 1
                slot = "aql_pipe_aggregate_" + suffix.to_string()
              }
              let expression = projection.expression.unwrap()
              scalar_derives.push(
                (
                  slot,
                  append_grouped_expression(
                    construction, expression, grouped_keys, resolve_input, scalar_visible,
                    scalar_ranges, max_work,
                  ),
                ),
              )
              slot
            }
            names.push(name)
            selected.push(
              if name == slot {
                construction.text(slot)
              } else {
                construction.object([(name, construction.text(slot))])
              },
            )
          }
          if !scalar_derives.is_empty() {
            step_entries.push(entries.copy())
            entries.clear()
            step_entries.push([("derive", construction.object(scalar_derives))])
          }
          if names != active_fields {
            if !entries.is_empty() {
              step_entries.push(entries.copy())
            }
            entries.clear()
            entries.push(("select", construction.array(selected)))
          }
          reset_infer_key_labels = true
          active_fields = names.copy()
          output = names
          pipe_visible = names.map(name => (name, name))
          pipe_ranges = []
          pipe_star_ranges = []
          scalar_value_table_ranges = []
          pipe_changed = true
          pipe_rebound = true
        } else {
          pipe_visible = result_fields.map(name => (name, name))
        }
        if !anonymous_set_aggregate_slots.is_empty() ||
          !positional_set_aggregate_slots.is_empty() {
          // Set-only aggregate slots remain physical values for terminal
          // SELECT and ordinal alignment, never authored HAVING bindings.
          pipe_visible = pipe_visible.filter(entry => {
            !anonymous_set_aggregate_slots.any(pair => pair.1 == entry.1) &&
            !positional_set_aggregate_slots.any(pair => pair.1 == entry.1)
          })
          pipe_changed = true
        }
        pipe_columns = pipe_visible.copy()
        value_table_receivers = []
        pipe_value_columns = []
        pipe_value_table = false
        scalar_value_table_ranges = scalar_value_table_ranges.filter(receiver => {
          key_names.contains(receiver.1)
        })
        grouped = true
      }
      Having(predicate, _) => {
        if !grouped {
          raise Abort(UnsupportedHaving)
        }
        let projections = if sql_group_projection {
          sql_group_selected_projections
        } else {
          selected_projections(query)
        }
        let scope = if pipe_changed || pipe_rebound {
          Some({
            visible: unnest_expression_columns(
              pipe_visible, value_table_receivers, scalar_value_table_ranges, pipe_columns,
            ),
            ranges: pipe_ranges,
            columns: pipe_columns.copy(),
            value_table: pipe_value_table,
            value_columns: pipe_value_columns.copy(),
            star_ranges: pipe_star_ranges.copy(),
            receivers: value_table_receivers.copy(),
            key_labels: infer_key_labels.copy(),
            scalar_ranges: scalar_value_table_ranges.copy(),
          })
        } else {
          None
        }
        let references = join_reference_paths(predicate)
        if !positional_set_aggregate_slots.is_empty() {
          reject_duplicate_projection_references(projections, references, path => {
            pipe_slot(path, pipe_visible, pipe_ranges)
          })
        }
        let derives : Array[(String, @builder.Node)] = []
        let physical = active_fields.copy()
        for projection in projections {
          if projection_alias(projection) is Some(name) {
            physical.push(name.value)
          }
        }
        for projection in projections {
          guard projection_alias(projection) is Some(name) &&
            projection.expression is Some(expression) &&
            projection.aggregate is None &&
            projection.analytic is None else {
            continue
          }
          // Qualified input references keep their range meaning. Property
          // paths may ask the common expression lowerer for an alias prefix.
          if !references.any(path => {
              same_name(name, path[0]) &&
              (
                path.length() == 1 ||
                having_column(
                  path,
                  query,
                  input,
                  active_fields,
                  projections,
                  grouped_keys,
                  having_values,
                  scope~,
                )
                is None
              )
            }) {
            continue
          }
          if having_column(
              [name],
              query,
              input,
              active_fields,
              projections,
              grouped_keys,
              having_values,
              scope~,
            )
            is Some(_) {
            continue
          }
          let slot = pipe_physical_name(physical, "aql_having_expr_")
          physical.push(slot)
          let input_scope = sql_group_select_scope.unwrap()
          derives.push(
            (
              slot,
              if sql_group_expression_input_scope is Some(original_scope) {
                append_grouped_expression(
                  construction,
                  expression,
                  grouped_keys,
                  path => scope_expression_slot(path, original_scope),
                  input_scope.visible,
                  input_scope.ranges,
                  max_work,
                )
              } else {
                append_pipe_expression(
                  construction,
                  expression,
                  input_scope.visible,
                  input_scope.ranges,
                  max_work,
                  value_ranges=value_range_names(
                    value_table_receivers, scalar_value_table_ranges,
                  ),
                )
              },
            ),
          )
          having_values.push((expression, slot))
        }
        if !derives.is_empty() {
          let derive_step : Array[(String, @builder.Node)] = []
          if entries.length() == 1 {
            derive_step.push(entries[0])
            entries.clear()
          }
          derive_step.push(("derive", construction.object(derives)))
          step_entries.push(derive_step)
        }
        let resolve_having = fn(path : Array[@query.NamePart]) -> String? {
          if path.length() == 1 {
            for (name, slot) in having_aggregate_slots {
              if name == path[0].value {
                return Some(slot)
              }
            }
          }
          having_column(
            path,
            query,
            input,
            active_fields,
            projections,
            grouped_keys,
            having_values,
            scope~,
          )
        }
        let value = if sql_group_expression_input_scope is Some(original_scope) {
          let resolve_input = fn(path : Array[@query.NamePart]) -> String? {
            scope_expression_slot(path, original_scope)
          }
          // HAVING resolves bare SELECT aliases before inputs. A computed or
          // aggregate alias cannot prove that its value is the original input
          // receiver. Qualified inputs still resolve in their own range.
          let resolve_having_input = fn(
            path : Array[@query.NamePart],
          ) -> String? {
            if path.length() == 1 {
              let matches = projections.filter(projection => {
                projection_alias(projection) is Some(name) &&
                same_name(name, path[0])
              })
              if !matches.is_empty() {
                guard matches.length() == 1 &&
                  matches[0].aggregate is None &&
                  matches[0].analytic is None &&
                  matches[0].expression is Some(expression) else {
                  return None
                }
                let mut root = @query.expression_root(expression)
                while @query.expression_node(expression, root).unwrap().kind
                      is Parenthesized(child) {
                  root = child
                }
                return match
                  @query.expression_node(expression, root).unwrap().kind {
                  Reference(source) => resolve_input(source)
                  _ => None
                }
              }
            }
            resolve_input(path)
          }
          append_grouped_expression_resolved(
            construction, predicate, grouped_keys, resolve_input, resolve_having_input,
            resolve_having, physical, max_work,
          )
        } else {
          match
            @expression.append_with_properties(
              predicate,
              resolve_having,
              construction.builder,
              max_work,
              resolve_parameter=construction.parameter_resolver(),
            ) {
            Ok(value) => value
            Err(error) => raise Abort(Expression(error))
          }
        }
        entries.push(("filter", value))
      }
      Qualify(predicate, _) => {
        let input_scope = if sql_group_projection {
          sql_group_select_scope.unwrap()
        } else {
          analytic_input_scope.unwrap_or({
            visible: pipe_visible.copy(),
            ranges: pipe_ranges.copy(),
            columns: pipe_columns.copy(),
            value_table: pipe_value_table,
            value_columns: pipe_value_columns.copy(),
            star_ranges: pipe_star_ranges.copy(),
            receivers: value_table_receivers.copy(),
            key_labels: infer_key_labels.copy(),
            scalar_ranges: scalar_value_table_ranges.copy(),
          })
        }
        let projections = if sql_group_projection {
          sql_group_selected_projections
        } else {
          expand_projections(
            query,
            selected_projections(query),
            input_scope.visible,
            input_scope.ranges,
            max_work,
          )
        }
        let physical = active_fields.copy()
        let derives : Array[(String, @builder.Node)] = []
        let aliases = materialize_clause_aliases(
          projections,
          input_scope,
          join_reference_paths(predicate),
          active_fields,
          analytic_outputs,
          analytic_expression_bindings,
          grouped_keys + having_values,
          qualify_values,
          physical,
          derives,
          projection => {
            if sql_group_projection || pipe_rebound {
              projection_output_name(projection)
            } else {
              output_name(
                projection,
                query,
                input,
                input_scope.visible.map(entry => entry.0),
              )
            }
          },
          expression => {
            append_pipe_expression(
              construction,
              expression,
              private_expression_columns(
                input_scope.visible,
                analytic_expression_bindings,
              ),
              input_scope.ranges,
              max_work,
              value_ranges=value_range_names(
                value_table_receivers, scalar_value_table_ranges,
              ),
            )
          },
          "aql_qualify_expr_",
          false,
          aggregate_outputs=sql_group_aggregate_slots,
        )
        if !derives.is_empty() {
          let fields : Array[(String, @builder.Node)] = []
          if entries.length() == 1 {
            fields.push(entries.remove(0))
          }
          fields.push(("derive", construction.object(derives)))
          step_entries.push(fields)
        }
        let resolve = fn(path : Array[@query.NamePart]) -> String? {
          if path.length() > 1 &&
            scope_expression_slot(path, input_scope) is Some(slot) {
            return Some(slot)
          }
          if path.length() == 1 {
            for binding in aliases {
              if same_name(path[0], binding.0) {
                return Some(binding.1)
              }
            }
            for (name, slot) in analytic_outputs {
              if path[0].value == name {
                return Some(slot)
              }
            }
            for (name, slot) in having_aggregate_slots {
              if path[0].value == name {
                return Some(slot)
              }
            }
          }
          scope_expression_slot(path, input_scope)
        }
        let value = match
          @expression.append_with_properties(
            predicate,
            resolve,
            construction.builder,
            max_work,
            resolve_parameter=construction.parameter_resolver(),
          ) {
          Ok(value) => value
          Err(error) => raise Abort(Expression(error))
        }
        entries.push(("filter", value))
      }
      Analytic(projections)
      | AnalyticExpressions(projections, _)
      | OrderAnalytic(projections, _) => {
        let private_names = match operation {
          AnalyticExpressions(_, names) => names
          _ => []
        }
        let order_window = operation is OrderAnalytic(_, _)
        let select_order_window = operation is OrderAnalytic(_, true)
        if !order_window {
          analytic_expression_bindings.clear()
        }
        let projections = expand_projections(
          query,
          projections,
          if sql_group_projection {
            sql_group_input_columns
          } else {
            pipe_visible
          },
          if sql_group_projection {
            sql_group_input_ranges
          } else {
            pipe_ranges
          },
          max_work,
        )
        if projections.is_empty() {
          raise Abort(UnsupportedAnalytic)
        }
        let snapshot = active_fields.copy()
        let analytic_visible = pipe_visible.copy()
        if !order_window ||
          (select_order_window && analytic_input_scope is None) {
          analytic_input_scope = Some({
            visible: unnest_expression_columns(
              analytic_visible, value_table_receivers, scalar_value_table_ranges,
              pipe_columns,
            ).copy(),
            ranges: pipe_ranges.copy(),
            columns: pipe_columns.copy(),
            value_table: pipe_value_table,
            value_columns: pipe_value_columns.copy(),
            star_ranges: pipe_star_ranges.copy(),
            receivers: value_table_receivers.copy(),
            key_labels: infer_key_labels.copy(),
            scalar_ranges: scalar_value_table_ranges.copy(),
          })
          analytic_input_fields = Some(snapshot)
        }
        if !order_window {
          analytic_outputs.clear()
          positional_set_analytic_slots.clear()
        }
        let outputs = if order_window {
          order_analytic_slots
        } else {
          analytic_outputs
        }
        let physical = snapshot.copy()
        let alias_derives : Array[(String, @builder.Node)] = []
        let order_scope = if sql_group_projection {
          sql_group_select_scope.unwrap()
        } else {
          analytic_input_scope.unwrap_or({
            visible: unnest_expression_columns(
              analytic_visible, value_table_receivers, scalar_value_table_ranges,
              pipe_columns,
            ),
            ranges: pipe_ranges.copy(),
            columns: pipe_columns.copy(),
            value_table: pipe_value_table,
            value_columns: pipe_value_columns.copy(),
            star_ranges: pipe_star_ranges.copy(),
            receivers: value_table_receivers.copy(),
            key_labels: infer_key_labels.copy(),
            scalar_ranges: scalar_value_table_ranges.copy(),
          })
        }
        let order_aliases = if select_order_window {
          let selected = if sql_group_projection {
            sql_group_selected_projections
          } else {
            expand_projections(
              query,
              selected_projections(query),
              order_scope.visible,
              order_scope.ranges,
              max_work,
            )
          }
          let references : Array[Array[@query.NamePart]] = []
          for projection in projections {
            let call = projection.analytic.unwrap()
            for expression in call.window.partition_by {
              references.append(join_reference_paths(expression))
            }
            for term in call.window.order_by {
              references.append(join_reference_paths(term.expression))
            }
            if call.expression is Some(expression) {
              references.append(join_reference_paths(expression))
            }
            if call.aggregate is Some(aggregate) &&
              aggregate.argument is Some(expression) {
              references.append(join_reference_paths(expression))
            }
          }
          materialize_clause_aliases(
            selected,
            order_scope,
            references,
            active_fields,
            analytic_outputs,
            analytic_expression_bindings,
            grouped_keys + having_values,
            qualify_values,
            physical,
            alias_derives,
            projection => {
              if sql_group_projection || pipe_rebound {
                projection_output_name(projection)
              } else {
                output_name(
                  projection,
                  query,
                  input,
                  order_scope.visible.map(entry => entry.0),
                )
              }
            },
            expression => {
              if sql_group_projection {
                let source_scope = sql_group_expression_input_scope.unwrap()
                append_grouped_expression(
                  construction,
                  expression,
                  grouped_keys,
                  path => scope_expression_slot(path, source_scope),
                  order_scope.visible,
                  order_scope.ranges,
                  max_work,
                )
              } else {
                append_pipe_expression(
                  construction,
                  expression,
                  order_scope.visible + analytic_expression_bindings,
                  order_scope.ranges,
                  max_work,
                  value_ranges=value_range_names(
                    value_table_receivers, scalar_value_table_ranges,
                  ),
                )
              }
            },
            "aql_order_alias_",
            true,
            aggregate_outputs=sql_group_aggregate_slots,
          )
        } else {
          []
        }
        if !alias_derives.is_empty() {
          let fields : Array[(String, @builder.Node)] = []
          if !entries.is_empty() {
            fields.push(entries.remove(0))
          }
          fields.push(("derive", construction.object(alias_derives)))
          step_entries.push(fields)
        }
        for projection in projections {
          if projection.name is Some(name) &&
            !physical.any(field => ascii_upper(field) == ascii_upper(name.value)) {
            physical.push(name.value)
          }
        }
        let groups : Array[Array[@query.Projection]] = []
        for projection in projections {
          if projection.analytic is None {
            continue
          }
          let positional_terminal = !order_window &&
            positional_set_output &&
            positional_projection is Some(_)
          let positional_private = positional_terminal &&
            (match projection.name {
              None => true
              Some(name) => duplicate_projection_alias(projections, name.value)
            })
          let slot = match projection.name {
            None => {
              if !positional_terminal {
                raise Abort(UnsupportedProjection)
              }
              pipe_physical_name(physical, "aql_analytic_output_")
            }
            Some(name) => {
              if !positional_private &&
                outputs.any(output => {
                  ascii_upper(output.0) == ascii_upper(name.value)
                }) {
                raise Abort(DuplicateOutput)
              }
              if positional_private ||
                active_fields.any(field => {
                  ascii_upper(field) == ascii_upper(name.value)
                }) {
                pipe_physical_name(physical, "aql_analytic_output_")
              } else {
                name.value
              }
            }
          }
          // Only authored aliases enter clause lookup. Anonymous evaluated
          // slots stay private until the existing ordinal projection.
          physical.push(slot)
          if projection.name is Some(name) {
            outputs.push((name.value, slot))
          }
          if positional_private {
            positional_set_analytic_slots.push(
              (projection.analytic.unwrap(), slot),
            )
          }
          let projection = {
            ..projection,
            name: Some({ value: slot, quoted: false, }),
          }
          let mut found = false
          for group in groups {
            if same_analytic_window(
                group[0].analytic.unwrap().window,
                projection.analytic.unwrap().window,
              ) {
              group.push(projection)
              found = true
              break
            }
          }
          if !found {
            groups.push([projection])
          }
          active_fields.push(slot)
        }
        for name in private_names {
          guard analytic_output_slot(name.value, analytic_outputs) is Some(slot) else {
            raise Abort(UnsupportedAnalytic)
          }
          analytic_expression_bindings.push((name.value, slot))
        }
        let resolve = fn(path : Array[@query.NamePart]) -> String? {
          if select_order_window {
            if path.length() > 1 &&
              scope_expression_slot(path, order_scope) is Some(slot) {
              return Some(slot)
            }
            if path.length() == 1 {
              for (name, slot) in order_aggregate_slots {
                if same_name({ value: name, quoted: false, }, path[0]) {
                  return Some(slot)
                }
              }
              for (name, slot) in order_aliases {
                if same_name(name, path[0]) {
                  return Some(slot)
                }
              }
            }
            return scope_expression_slot(path, order_scope)
          }
          if sql_group_projection {
            // GROUP may reuse an authored aggregate slot for a private call.
            // Resolve SELECT window keys through retained input bindings and
            // parser-owned aggregate references, never sibling SELECT aliases.
            if path.length() == 1 {
              for (name, slot) in having_aggregate_slots {
                if same_name({ value: name, quoted: false, }, path[0]) {
                  return Some(slot)
                }
              }
            }
            return scope_expression_slot(path, order_scope)
          }
          if pipe_changed || pipe_rebound {
            pipe_slot(
              path,
              unnest_expression_columns(
                analytic_visible, value_table_receivers, scalar_value_table_ranges,
                pipe_columns,
              ),
              pipe_ranges,
            )
          } else {
            resolve_column(path, query, input, snapshot)
          }
        }
        let reserved = active_fields.copy()
        let evaluated : Array[(@query.Expression, String)] = []
        let derives : Array[(String, @builder.Node)] = []
        let operations : Array[@builder.Node] = []
        for group in groups {
          operations.push(
            lower_analytic(
              construction, group, resolve, max_work, max_collection_bytes, reserved,
              evaluated, derives,
            ),
          )
        }
        if !derives.is_empty() {
          let derive_step : Array[(String, @builder.Node)] = []
          if !entries.is_empty() {
            derive_step.push(entries[0])
            entries.clear()
          }
          derive_step.push(("derive", construction.object(derives)))
          step_entries.push(derive_step)
        }
        for body in operations {
          let operation = [("analytic", body)]
          if !entries.is_empty() {
            operation.insert(0, entries[0])
            entries.clear()
          }
          step_entries.push(operation)
        }
        if !order_window {
          output = active_fields.copy()
        }
        deferred = true
      }
      Distinct => {
        if requires_graph_projection {
          raise Abort(UnsupportedProjection)
        }
        // Compare only current visible values. Displaced range slots are not
        // representative-row payload and cannot survive this projection.
        let slots : Array[String] = []
        for field in pipe_visible {
          if !slots.contains(field.1) {
            slots.push(field.1)
          }
        }
        // The current keyed distinct contract does not compare closed value
        // tables. Do not expand them into nullable fields and change equality.
        if !value_table_receivers.is_empty() || !pipe_value_columns.is_empty() {
          raise Abort(UnsupportedProjection)
        }
        entries.push(
          (
            "distinct",
            construction.array(slots.map(slot => construction.text(slot))),
          ),
        )
        active_fields = slots
        pipe_ranges = pipe_ranges.map(range => {
          (range.0, range.1.filter(field => slots.contains(field.1)))
        })
        pipe_star_ranges = pipe_star_ranges.map(range => {
          (range.0, range.1.filter(field => slots.contains(field.1)))
        })
        pipe_rebound = true
        pipe_selected = false
        distinct_order_scope = false
        selected_expressions = []
        selected_output_slots = []
      }
      Select(original_projections, distinct) if pipe_changed || pipe_rebound => {
        let projections = if sql_group_projection {
          sql_group_selected_projections
        } else {
          expand_projections(
            query, original_projections, pipe_visible, pipe_ranges, max_work,
          )
        }
        let expression_scope = if sql_group_projection {
          let scope = sql_group_select_scope.unwrap()
          {
            ..scope,
            visible: private_expression_columns(
              scope.visible,
              analytic_expression_bindings,
            ),
          }
        } else {
          {
            visible: private_expression_columns(
              unnest_expression_columns(
                pipe_visible, value_table_receivers, scalar_value_table_ranges, pipe_columns,
              ),
              analytic_expression_bindings,
            ),
            ranges: pipe_ranges,
            columns: pipe_columns.copy(),
            value_table: pipe_value_table,
            value_columns: pipe_value_columns.copy(),
            star_ranges: pipe_star_ranges.copy(),
            receivers: value_table_receivers.copy(),
            key_labels: infer_key_labels.copy(),
            scalar_ranges: scalar_value_table_ranges.copy(),
          }
        }
        let lower_select_expression = fn(
          expression : @query.Expression,
          private_columns : Array[(String, String)],
        ) -> @builder.Node raise Abort {
          if sql_group_projection {
            let input_scope = sql_group_expression_input_scope.unwrap()
            append_private_grouped_expression(
              construction,
              expression,
              grouped_keys,
              path => scope_expression_slot(path, input_scope),
              expression_scope.visible + private_columns,
              expression_scope.ranges,
              analytic_expression_bindings + private_columns,
              max_work,
            )
          } else {
            append_pipe_expression(
              construction,
              expression,
              expression_scope.visible + private_columns,
              expression_scope.ranges,
              max_work,
              value_ranges=value_range_names(
                expression_scope.receivers,
                expression_scope.scalar_ranges,
              ),
            )
          }
        }
        let expanded_projections = projections
        let (projections, computed_star_bindings, receiver_derives) = materialize_computed_star_receivers(
          original_projections,
          expanded_projections,
          active_fields,
          expression => lower_select_expression(expression, []),
          expression => {
            qualify_cached_slot(expression, qualify_values) is Some(_) ||
            (
              sql_group_projection &&
              (
                grouped_keys.any(pair => same_expression(pair.0, expression)) ||
                having_values.any(pair => same_expression(pair.0, expression))
              )
            )
          },
          max_work,
        )
        if !receiver_derives.is_empty() {
          let receiver_step : Array[(String, @builder.Node)] = []
          if entries.length() == 1 && entries[0].0 == "from" {
            receiver_step.push(entries[0])
            entries.clear()
          }
          receiver_step.push(("derive", construction.object(receiver_derives)))
          step_entries.push(receiver_step)
          active_fields.append(computed_star_bindings.map(binding => binding.1))
        }
        let names : Array[String] = []
        let selected : Array[@builder.Node] = []
        let derives : Array[(String, @builder.Node)] = []
        let bindings : Array[(String, String)] = []
        let expressions : Array[(@query.Expression, String)] = []
        let expression_positions : Array[Int] = []
        let physical = active_fields.copy()
        for projection_index in 0..<projections.length() {
          let projection = projections[projection_index]
          match projection.star {
            Some("*") =>
              for
                visible in expanded_star_columns(
                  projection,
                  if sql_group_projection {
                    sql_group_input_columns
                  } else {
                    pipe_visible
                  },
                  ranges=if sql_group_projection {
                    sql_group_input_ranges
                  } else {
                    unnest_star_ranges(pipe_ranges, pipe_star_ranges)
                  },
                  authored_aliases=positional_authored_aliases,
                ) {
                names.push(visible.0)
                selected.push(
                  if visible.0 == visible.1 {
                    construction.text(visible.1)
                  } else {
                    construction.object([
                      (visible.0, construction.text(visible.1)),
                    ])
                  },
                )
                bindings.push(visible)
              }
            Some(_) => raise Abort(UnsupportedProjection)
            None => {
              if projection.aggregate is Some(call) {
                if !sql_group_projection {
                  raise Abort(UnsupportedAggregate)
                }
                let (name, slot) = match projection.name {
                  Some(name) =>
                    if positional_set_output &&
                      positional_projection == Some(i) &&
                      duplicate_projection_alias(projections, name.value) {
                      (
                        name.value,
                        positional_set_aggregate_slot(
                          call,
                          positional_set_aggregate_slots,
                          sql_group_expression_input_scope.unwrap(),
                        ),
                      )
                    } else {
                      let matches = sql_group_aggregate_slots.filter(entry => {
                        entry.0 == name.value
                      })
                      if matches.length() != 1 {
                        raise Abort(UnsupportedAggregate)
                      }
                      (name.value, matches[0].1)
                    }
                  None => {
                    if !positional_set_output ||
                      positional_projection != Some(i) {
                      raise Abort(UnsupportedProjection)
                    }
                    (
                      anonymous_set_projection_name(
                        projections,
                        physical,
                        names,
                        reserved_names=positional_destination_names,
                      ),
                      positional_set_aggregate_slot(
                        call,
                        anonymous_set_aggregate_slots,
                        sql_group_expression_input_scope.unwrap(),
                      ),
                    )
                  }
                }
                if !active_fields.contains(slot) {
                  raise Abort(UnsupportedAggregate)
                }
                if positional_projection == Some(i) &&
                  projection.star is None &&
                  projection_alias(projection) is None {
                  positional_private_fields.push(name)
                }
                names.push(name)
                bindings.push((name, slot))
                selected.push(
                  if slot == name {
                    construction.text(slot)
                  } else {
                    construction.object([(name, construction.text(slot))])
                  },
                )
                continue
              }
              if projection.analytic is Some(call) {
                let name = match projection.name {
                  Some(name) => name.value
                  None => {
                    if !positional_set_output ||
                      positional_projection != Some(i) {
                      raise Abort(UnsupportedProjection)
                    }
                    anonymous_set_projection_name(
                      projections,
                      physical,
                      names,
                      reserved_names=positional_destination_names,
                    )
                  }
                }
                let source = if positional_set_output &&
                  positional_projection == Some(i) &&
                  (
                    projection.name is None ||
                    duplicate_projection_alias(projections, name)
                  ) {
                  positional_set_analytic_slot(
                    call,
                    positional_set_analytic_slots,
                    analytic_input_scope.unwrap(),
                  )
                } else {
                  match analytic_output_slot(name, analytic_outputs) {
                    Some(slot) => slot
                    None => raise Abort(UnknownColumn)
                  }
                }
                if positional_projection == Some(i) &&
                  projection.star is None &&
                  projection_alias(projection) is None {
                  positional_private_fields.push(name)
                }
                names.push(name)
                bindings.push((name, source))
                selected.push(
                  if source == name {
                    construction.text(source)
                  } else {
                    construction.object([(name, construction.text(source))])
                  },
                )
                continue
              }
              let expression = projection.expression.unwrap()
              let mut grouped_slot : String? = None
              if sql_group_projection {
                for pair in grouped_keys {
                  if same_expression(pair.0, expression) {
                    grouped_slot = Some(pair.1)
                  }
                }
                for pair in having_values {
                  if same_expression(pair.0, expression) {
                    grouped_slot = Some(pair.1)
                  }
                }
              }
              let cached = qualify_cached_slot(expression, qualify_values)
              let source = if (match cached {
                  Some(_) => cached
                  None => grouped_slot
                })
                is Some(slot) {
                slot
              } else {
                match
                  @query.expression_node(
                    expression,
                    @query.expression_root(expression),
                  ).unwrap().kind {
                  Reference(path) =>
                    match scope_expression_slot(path, expression_scope) {
                      Some(slot) => slot
                      None => {
                        let slot = pipe_physical_name(
                          physical, "aql_pipe_expr_",
                        )
                        physical.push(slot)
                        derives.push(
                          (
                            slot,
                            lower_select_expression(
                              expression, computed_star_bindings,
                            ),
                          ),
                        )
                        slot
                      }
                    }
                  _ => {
                    let slot = pipe_physical_name(physical, "aql_pipe_expr_")
                    physical.push(slot)
                    derives.push(
                      (
                        slot,
                        lower_select_expression(
                          expression, computed_star_bindings,
                        ),
                      ),
                    )
                    slot
                  }
                }
              }
              let name = if positional_set_output &&
                positional_projection == Some(i) &&
                projection_alias(projection) is None {
                anonymous_set_projection_name(
                  projections,
                  physical,
                  names,
                  reserved_names=positional_destination_names,
                )
              } else {
                projection_output_name(projection)
              }
              if positional_projection == Some(i) &&
                projection.star is None &&
                projection_alias(projection) is None {
                positional_private_fields.push(name)
              }
              names.push(name)
              bindings.push((name, source))
              expression_positions.push(names.length() - 1)
              expressions.push(
                (
                  expanded_projections[projection_index].expression.unwrap(),
                  name,
                ),
              )
              selected.push(
                if name == source {
                  construction.text(source)
                } else {
                  construction.object([(name, construction.text(source))])
                },
              )
            }
          }
        }
        if positional_projection == Some(i) {
          positional_private_fields.append(
            privatize_positional_duplicate_columns(
              construction,
              names,
              bindings,
              selected,
              physical,
              authored_aliases=Some(positional_authored_aliases),
              reserved_names=positional_destination_names,
            ),
          )
          // ORDER reuses evaluated occurrences after duplicate aliases are
          // privatized; an authored alias is no longer their physical slot.
          for index in 0..<expressions.length() {
            expressions[index] = (
              expressions[index].0,
              names[expression_positions[index]],
            )
          }
        }
        for a in 0..<names.length() {
          for b in 0..<a {
            if ascii_upper(names[a]) == ascii_upper(names[b]) {
              raise Abort(DuplicateOutput)
            }
          }
        }
        if !derives.is_empty() {
          let derive_step : Array[(String, @builder.Node)] = []
          if entries.length() == 1 {
            derive_step.push(entries[0])
            entries.clear()
          }
          derive_step.push(("derive", construction.object(derives)))
          step_entries.push(derive_step)
        }
        entries.push(("select", construction.array(selected)))
        output = names
        selected_expressions = expressions
        // Preserve the SELECT input meaning even when projection/DISTINCT
        // materializes a public name that shadows an original input column.
        selected_input_scope = {
          visible: unnest_expression_columns(
            pipe_visible, value_table_receivers, scalar_value_table_ranges, pipe_columns,
          ).copy(),
          ranges: pipe_ranges.copy(),
          columns: pipe_columns.copy(),
          value_table: pipe_value_table,
          value_columns: pipe_value_columns.copy(),
          star_ranges: pipe_star_ranges.copy(),
          receivers: value_table_receivers.copy(),
          key_labels: infer_key_labels.copy(),
          scalar_ranges: scalar_value_table_ranges.copy(),
        }
        selected_output_slots = bindings.copy()
        pipe_columns = bindings.copy()
        if !distinct &&
          !(positional_projection is Some(projection) &&
          i > projection &&
          projections.any(column => !column.except_columns.is_empty())) &&
          @query.operation_at(query, i + 1) is Some(Order(_)) {
          if entries.length() == 2 && entries[0].0 == "from" {
            ignore(entries.remove(0))
            first = true
          }
          pending_select = Some(entries)
          pending_bindings = bindings
          deferred = true
        } else {
          active_fields = names.copy()
          pipe_visible = names.map(name => (name, name))
          pipe_columns = pipe_visible.copy()
          pipe_changed = false
          reset_infer_key_labels = true
        }
        pipe_selected = true
        if distinct {
          add_distinct = true
          distinct_order_scope = true
          pipe_ranges = []
          pipe_star_ranges = []
          scalar_value_table_ranges = []
        }
      }
      // An otherwise empty Stage Result consumer needs its own declared output
      // operation. A projection inside an existing JOIN pipeline may still elide.
      Select(projections, distinct) if !preserve_identity_select &&
        !(input.source is StageResult(_, _) &&
        step_entries.is_empty() &&
        !projected_input) &&
        !sql_group_projection &&
        !distinct &&
        projections.length() == 1 &&
        projections[0].star == Some("*") &&
        projections[0].expression is None &&
        projections[0].replacements.is_empty() &&
        projections[0].except_columns.is_empty() => {
        if entries.length() == 1 && entries[0].0 == "from" {
          entries.clear()
          first = true
        }
        deferred = true
      }
      Select(original_projections, distinct) => {
        let select_fields = analytic_input_fields.unwrap_or(
          active_fields.copy(),
        )
        selected_input_fields = select_fields.copy()
        let input_scope : JoinChainScope = {
          visible: unnest_expression_columns(
            pipe_visible, value_table_receivers, scalar_value_table_ranges, pipe_columns,
          ).copy(),
          ranges: pipe_ranges.copy(),
          columns: pipe_columns.copy(),
          value_table: pipe_value_table,
          value_columns: pipe_value_columns.copy(),
          star_ranges: pipe_star_ranges.copy(),
          receivers: value_table_receivers.copy(),
          key_labels: infer_key_labels.copy(),
          scalar_ranges: scalar_value_table_ranges.copy(),
        }
        let projections = if sql_group_projection {
          sql_group_selected_projections
        } else {
          expand_projections(
            query,
            original_projections,
            select_fields.map(field => (field, field)),
            pipe_ranges,
            max_work,
          )
        }
        let lower_select_expression = fn(
          expression : @query.Expression,
          private_columns : Array[(String, String)],
        ) -> @builder.Node raise Abort {
          if sql_group_projection {
            let scope = sql_group_select_scope.unwrap()
            let original_scope = sql_group_expression_input_scope.unwrap()
            append_private_grouped_expression(
              construction,
              expression,
              grouped_keys,
              path => scope_expression_slot(path, original_scope),
              scope.visible,
              scope.ranges,
              analytic_expression_bindings + private_columns,
              max_work,
            )
          } else {
            append_expression(
              construction,
              expression,
              query,
              input,
              select_fields,
              max_work,
              private_columns=analytic_expression_bindings + private_columns,
            )
          }
        }
        let expanded_projections = projections
        let (projections, computed_star_bindings, receiver_derives) = materialize_computed_star_receivers(
          original_projections,
          expanded_projections,
          active_fields,
          expression => lower_select_expression(expression, []),
          expression => {
            qualify_cached_slot(expression, qualify_values) is Some(_) ||
            grouped_keys.any(pair => same_expression(pair.0, expression)) ||
            having_values.any(pair => same_expression(pair.0, expression))
          },
          max_work,
        )
        if !receiver_derives.is_empty() {
          let receiver_step : Array[(String, @builder.Node)] = []
          if entries.length() == 1 && entries[0].0 == "from" {
            receiver_step.push(entries[0])
            entries.clear()
          }
          receiver_step.push(("derive", construction.object(receiver_derives)))
          step_entries.push(receiver_step)
          active_fields.append(computed_star_bindings.map(binding => binding.1))
        }
        let names : Array[String] = []
        let derives : Array[(String, @builder.Node)] = []
        let temporary_names : Array[String] = []
        let selected : Array[@builder.Node] = []
        let bindings : Array[(String, String)] = []
        let expressions : Array[(@query.Expression, String)] = []
        let expression_positions : Array[Int] = []
        for projection_index in 0..<projections.length() {
          let projection = projections[projection_index]
          match projection.star {
            Some(_) =>
              for
                (name, field) in expanded_star_columns(
                  projection,
                  if sql_group_projection {
                    sql_group_input_columns
                  } else {
                    select_fields.map(field => (field, field))
                  },
                  ranges=if sql_group_projection {
                    sql_group_input_ranges
                  } else {
                    unnest_star_ranges(pipe_ranges, pipe_star_ranges)
                  },
                  authored_aliases=positional_authored_aliases,
                ) {
                names.push(name)
                selected.push(
                  if name == field {
                    construction.text(field)
                  } else {
                    construction.object([(name, construction.text(field))])
                  },
                )
                bindings.push((name, field))
              }
            None => {
              // An implicit name describes the authored input path, even
              // after GROUP retains only its evaluated key. This naming
              // snapshot does not authorize reading the original receiver:
              // grouped expression lowering below still owns value access.
              let name = if positional_set_output &&
                positional_projection == Some(i) &&
                projection_alias(projection) is None {
                anonymous_set_projection_name(
                  projections,
                  active_fields,
                  names,
                  reserved_names=positional_destination_names,
                )
              } else {
                output_name(
                  projection,
                  query,
                  input,
                  if sql_group_projection {
                    sql_group_input_columns.map(entry => entry.0)
                  } else {
                    select_fields
                  },
                  row_ranges=Some(pipe_ranges),
                )
              }
              if positional_projection == Some(i) &&
                projection.star is None &&
                projection_alias(projection) is None {
                positional_private_fields.push(name)
              }
              names.push(name)
              if projection.aggregate is Some(_) ||
                projection.analytic is Some(_) {
                let source = if projection.analytic is Some(call) {
                  if positional_set_output &&
                    positional_projection == Some(i) &&
                    (
                      projection.name is None ||
                      duplicate_projection_alias(projections, name)
                    ) {
                    positional_set_analytic_slot(
                      call,
                      positional_set_analytic_slots,
                      analytic_input_scope.unwrap(),
                    )
                  } else {
                    match analytic_output_slot(name, analytic_outputs) {
                      Some(slot) => slot
                      None => raise Abort(UnsupportedAnalytic)
                    }
                  }
                } else if projection.name is None &&
                  projection.aggregate is Some(call) {
                  if !grouped || !sql_group_projection {
                    raise Abort(UnsupportedAggregate)
                  }
                  let slot = positional_set_aggregate_slot(
                    call,
                    anonymous_set_aggregate_slots,
                    sql_group_expression_input_scope.unwrap(),
                  )
                  if !active_fields.contains(slot) {
                    raise Abort(UnsupportedAggregate)
                  }
                  slot
                } else {
                  if !grouped || !active_fields.contains(name) {
                    raise Abort(UnsupportedAggregate)
                  }
                  name
                }
                selected.push(
                  if source == name {
                    construction.text(source)
                  } else {
                    construction.object([(name, construction.text(source))])
                  },
                )
                bindings.push((name, source))
                continue
              }
              let expression = projection.expression.unwrap()
              expression_positions.push(names.length() - 1)
              expressions.push(
                (
                  expanded_projections[projection_index].expression.unwrap(),
                  name,
                ),
              )
              let mut grouped_slot : String? = None
              for pair in grouped_keys {
                if same_expression(pair.0, expression) {
                  grouped_slot = Some(pair.1)
                }
              }
              for pair in having_values {
                if same_expression(pair.0, expression) {
                  grouped_slot = Some(pair.1)
                }
              }
              let direct = match
                @query.expression_node(
                  expression,
                  @query.expression_root(expression),
                ).unwrap().kind {
                Reference(path) =>
                  match grouped_slot {
                    Some(_) => grouped_slot
                    None =>
                      if sql_group_projection {
                        let scope = sql_group_select_scope.unwrap()
                        scope_expression_slot(path, scope)
                      } else {
                        resolve_column(path, query, input, select_fields)
                      }
                  }
                _ => None
              }
              let direct = match grouped_slot {
                Some(_) => grouped_slot
                None => direct
              }
              let cached = qualify_cached_slot(expression, qualify_values)
              let source = if (match cached {
                  Some(_) => cached
                  None => direct
                })
                is Some(column) {
                column
              } else {
                let mut suffix = names.length() - 1
                let mut temporary = "aql_query_expr_" + suffix.to_string()
                while active_fields.contains(temporary) ||
                      names.contains(temporary) ||
                      temporary_names.contains(temporary) {
                  suffix += 1
                  temporary = "aql_query_expr_" + suffix.to_string()
                }
                temporary_names.push(temporary)
                derives.push(
                  (
                    temporary,
                    lower_select_expression(expression, computed_star_bindings),
                  ),
                )
                temporary
              }
              selected.push(
                if source == name {
                  construction.text(source)
                } else {
                  construction.object([(name, construction.text(source))])
                },
              )
              bindings.push((name, source))
            }
          }
        }
        if positional_projection == Some(i) {
          positional_private_fields.append(
            privatize_positional_duplicate_columns(
              construction,
              names,
              bindings,
              selected,
              active_fields,
              authored_aliases=Some(positional_authored_aliases),
              reserved_names=positional_destination_names,
            ),
          )
          for index in 0..<expressions.length() {
            expressions[index] = (
              expressions[index].0,
              names[expression_positions[index]],
            )
          }
        }
        for a in 0..<names.length() {
          for b in 0..<a {
            if ascii_upper(names[a]) == ascii_upper(names[b]) {
              raise Abort(DuplicateOutput)
            }
          }
        }
        if !derives.is_empty() {
          let derive_fields : Array[(String, @builder.Node)] = []
          if entries.length() == 1 {
            derive_fields.push(entries[0])
            entries.clear()
          }
          derive_fields.push(("derive", construction.object(derives)))
          step_entries.push(derive_fields)
        }
        entries.push(("select", construction.array(selected)))
        output = names
        pipe_visible = names.map(name => (name, name))
        pipe_columns = pipe_visible.copy()
        selected_expressions = expressions
        selected_output_slots = bindings.copy()
        add_distinct = distinct
        if distinct {
          // DISTINCT materializes only the selected columns. Reuse the
          // existing projected-scope ORDER path for expressions over those
          // evaluated aliases; removed input columns remain unavailable.
          selected_input_scope = input_scope
          value_table_receivers = []
          pipe_value_columns = []
          pipe_value_table = false
          pipe_selected = true
          distinct_order_scope = true
          pipe_ranges = []
          pipe_star_ranges = []
          scalar_value_table_ranges = []
        }
        let excludes_columns = positional_projection is Some(projection) &&
          i > projection &&
          projections.any(column => !column.except_columns.is_empty())
        if excludes_columns {
          // EXCEPT establishes a projected Pipe scope. Its removed values
          // cannot supply a subsequent ORDER key through a deferred SELECT.
          pipe_selected = true
          pipe_rebound = true
          pipe_ranges = []
          pipe_star_ranges = []
          scalar_value_table_ranges = []
        }
        let needs_input_order = if distinct || excludes_columns {
          false
        } else {
          match @query.operation_at(query, i + 1) {
            Some(Order(terms)) =>
              terms.any(term => {
                let selected_expression = reusable_order_expression(
                    term.expression,
                    expressions,
                    bindings,
                    path => resolve_column(path, query, input, select_fields),
                  )
                  is Some(_)
                let selected_ordinal = order_ordinal_column(
                    term.expression,
                    output,
                  )
                  is Some(_)
                let selected_name = match
                  @query.expression_node(
                    term.expression,
                    @query.expression_root(term.expression),
                  ).unwrap().kind {
                  Reference(path) if path.length() == 1 =>
                    output.any(name => {
                      same_name(path[0], { value: name, quoted: false, })
                    })
                  _ => false
                }
                !selected_expression && !selected_name && !selected_ordinal
              })
            _ => false
          }
        }
        if needs_input_order {
          if entries.length() == 2 && entries[0].0 == "from" {
            ignore(entries.remove(0))
            first = true
          }
          pending_select = Some(entries)
          pending_bindings = bindings
          deferred = true
        } else {
          active_fields = names.copy()
        }
      }
      Order(terms) if pipe_selected || pipe_changed || pipe_rebound => {
        let sort : Array[@builder.Node] = []
        let hidden : Array[(@query.Expression, String)] = []
        let derives : Array[(String, @builder.Node)] = []
        let reserved = active_fields + output
        // SELECT aliases refer to already evaluated physical slots. Other
        // references use only the current Pipe scope, never the FROM scope.
        let resolve = fn(path : Array[@query.NamePart]) -> String? {
          if path.length() == 1 {
            for (logical, slot) in order_analytic_slots + order_aggregate_slots {
              if path[0].value == logical {
                if active_fields.contains(slot) {
                  return Some(slot)
                }
                if distinct_order_scope {
                  for (name, source) in selected_output_slots {
                    if source == slot {
                      return Some(name)
                    }
                  }
                }
                return None
              }
            }
          }
          if pending_select is Some(_) && path.length() == 1 {
            for binding in pending_bindings {
              if same_name(path[0], { value: binding.0, quoted: false, }) {
                return Some(binding.1)
              }
            }
          }
          // A materialized DISTINCT/SELECT cannot sort through a range slot
          // that its projection removed. An identical selected expression is
          // handled below using the evaluated output slot.
          if (pipe_selected || pending_select is Some(_)) &&
            path.length() > 1 &&
            order_output_slot(
              [path[0]],
              pending_bindings + selected_output_slots,
            )
            is Some(_) {
            return None
          }
          let current = pipe_expression_slot(
            path,
            unnest_expression_columns(
              pipe_visible, value_table_receivers, scalar_value_table_ranges, pipe_columns,
            ),
            pipe_ranges,
            value_ranges=value_range_names(
              value_table_receivers, scalar_value_table_ranges,
            ),
          ).filter(slot => active_fields.contains(slot))
          if current is Some(_) {
            return current
          }
          if distinct_order_scope {
            // A selected input column remains available through its output
            // slot even when aliased. This does not expose a removed input
            // or confuse an overwritten alias with its original value.
            if scope_expression_slot(path, selected_input_scope) is Some(source) {
              for binding in selected_output_slots {
                if binding.1 == source {
                  return Some(binding.0)
                }
              }
            }
          }
          None
        }
        for term in terms {
          let expression = term.expression
          let mut selected : String? = None
          if pipe_selected {
            selected = reusable_order_expression(
              expression,
              selected_expressions,
              order_aggregate_slots + selected_output_slots,
              path => scope_expression_slot(path, selected_input_scope),
            )
          }
          let ordinal = order_ordinal_column(
            expression,
            pipe_columns.map(pair => pair.1),
          )
          let direct = if ordinal is Some(slot) {
            // Positions address actual columns, not a same-named range or
            // an implicit field. A deferred SELECT supplies evaluated slots.
            Some(slot)
          } else {
            match
              @query.expression_node(
                expression,
                @query.expression_root(expression),
              ).unwrap().kind {
              Reference(path) => resolve(path)
              _ => None
            }
          }
          let name = if direct is Some(slot) {
            slot
          } else {
            match selected {
              Some(name) => {
                let mut slot = name
                if pending_select is Some(_) {
                  for binding in pending_bindings {
                    if binding.0 == name {
                      slot = binding.1
                    }
                  }
                }
                slot
              }
              None => {
                let mut reused : String? = None
                for pair in hidden {
                  if same_expression(expression, pair.0) {
                    reused = Some(pair.1)
                  }
                }
                match reused {
                  Some(slot) => slot
                  None => {
                    let slot = pipe_physical_name(reserved, "aql_pipe_sort_")
                    reserved.push(slot)
                    let value = if sql_group_order_input_scope is Some(scope) {
                      append_order_grouped_expression(
                        construction,
                        expression,
                        grouped_keys,
                        scope,
                        sql_group_selected_projections,
                        order_aggregate_slots,
                        resolve,
                        active_fields,
                        selected_output_slots,
                        pending_select is None,
                        distinct_order_scope,
                        max_work,
                      )
                    } else if distinct_order_scope {
                      append_distinct_order_member_expression(
                        construction,
                        expression,
                        selected_expressions,
                        selected_input_scope,
                        order_aggregate_slots + selected_output_slots,
                        resolve,
                        active_fields,
                        max_work,
                      )
                    } else {
                      append_resolved_range_expression(
                        construction,
                        expression,
                        resolve,
                        name => {
                          resolve([name]) is Some(_) ||
                          pipe_name_exists(
                            unnest_expression_columns(
                              pipe_visible, value_table_receivers, scalar_value_table_ranges,
                              pipe_columns,
                            ),
                            name,
                          )
                        },
                        max_work,
                        resolve_row=Some(path => {
                          row_reference_fields(
                            path,
                            name => resolve([name]) is Some(_),
                            pipe_ranges.filter(range => {
                              range.1.all(field => {
                                active_fields.contains(field.1)
                              })
                            }),
                          )
                        }),
                      )
                    }
                    derives.push((slot, value))
                    hidden.push((expression, slot))
                    slot
                  }
                }
              }
            }
          }
          sort.push(
            construction.object([
              ("field", construction.text(name)),
              ("dir", construction.text(term.direction)),
              ("nulls", construction.text(term.nulls)),
            ]),
          )
        }
        if !derives.is_empty() {
          let derive_step : Array[(String, @builder.Node)] = []
          if entries.length() == 1 && entries[0].0 == "from" {
            derive_step.push(entries.remove(0))
          }
          derive_step.push(("derive", construction.object(derives)))
          step_entries.push(derive_step)
        }
        entries.push(("sort", construction.array(sort)))
        if (!derives.is_empty() || !order_analytic_slots.is_empty()) &&
          pending_select is None {
          // With no deferred SELECT, remove sort-only slots immediately.
          // Retain demanded original slots for the existing range snapshots.
          step_entries.push(entries)
          // An immediately following RESULT already selects these exact
          // active fields and binds its checkpoint. There is no intervening
          // consumer of the hidden slots, so one projection does both jobs.
          let result_projects_next = match @query.operation_at(query, i + 1) {
            Some(RetainResult(_)) => true
            _ => false
          }
          if !result_projects_next {
            step_entries.push([
              (
                "select",
                construction.array(
                  active_fields
                  .filter(field => {
                    !order_analytic_slots.any(pair => pair.1 == field)
                  })
                  .map(field => construction.text(field)),
                ),
              ),
            ])
          }
          deferred = true
        }
      }
      Order(terms) => {
        let sort : Array[@builder.Node] = []
        let hidden : Array[(@query.Expression, String)] = []
        let derives : Array[(String, @builder.Node)] = []
        let reserved = active_fields + output
        for term in terms {
          let kind = @query.expression_node(
              term.expression,
              @query.expression_root(term.expression),
            ).unwrap().kind
          let mut selected = order_ordinal_column(term.expression, output)
          if kind is Reference(path) && path.length() == 1 {
            if analytic_output_slot(path[0].value, order_analytic_slots)
              is Some(slot) {
              selected = Some(slot)
            }
          }
          match kind {
            Reference(path) if path.length() == 1 =>
              for field in output {
                if same_name(path[0], { value: field, quoted: false, }) {
                  selected = Some(field)
                }
              }
            _ => ()
          }
          if selected is None {
            selected = reusable_order_expression(
              term.expression,
              selected_expressions,
              order_analytic_slots + selected_output_slots,
              path => resolve_column(path, query, input, selected_input_fields),
            )
          }
          let name = match selected {
            Some(field) => {
              let mut slot = field
              if pending_select is Some(_) {
                for pair in pending_bindings {
                  if pair.0 == field {
                    slot = pair.1
                  }
                }
              }
              slot
            }
            None => {
              if pending_select is None {
                raise Abort(UnsupportedOrdering)
              }
              let direct = match kind {
                Reference(path) =>
                  order_expression_slot(
                    path,
                    query,
                    input,
                    selected_input_fields,
                    order_analytic_slots + pending_bindings,
                  )
                _ => None
              }
              match direct {
                Some(field) => field
                None => {
                  let mut reused : String? = None
                  for pair in hidden {
                    if same_expression(term.expression, pair.0) {
                      reused = Some(pair.1)
                    }
                  }
                  match reused {
                    Some(field) => field
                    None => {
                      let field = pipe_physical_name(
                        reserved, "aql_query_sort_",
                      )
                      reserved.push(field)
                      derives.push(
                        (
                          field,
                          if sql_group_order_input_scope is Some(scope) {
                            append_order_grouped_expression(
                              construction,
                              term.expression,
                              grouped_keys,
                              scope,
                              sql_group_selected_projections,
                              order_aggregate_slots,
                              path => {
                                order_expression_slot(
                                  path,
                                  query,
                                  input,
                                  selected_input_fields,
                                  order_analytic_slots + pending_bindings,
                                )
                              },
                              active_fields,
                              selected_output_slots,
                              false,
                              false,
                              max_work,
                            )
                          } else {
                            append_order_expression(
                              construction,
                              term.expression,
                              query,
                              input,
                              selected_input_fields,
                              order_analytic_slots + pending_bindings,
                              max_work,
                            )
                          },
                        ),
                      )
                      hidden.push((term.expression, field))
                      field
                    }
                  }
                }
              }
            }
          }
          sort.push(
            construction.object([
              ("field", construction.text(name)),
              ("dir", construction.text(term.direction)),
              ("nulls", construction.text(term.nulls)),
            ]),
          )
        }
        if !derives.is_empty() {
          let derive_step : Array[(String, @builder.Node)] = []
          if entries.length() == 1 && entries[0].0 == "from" {
            derive_step.push(entries.remove(0))
          }
          derive_step.push(("derive", construction.object(derives)))
          step_entries.push(derive_step)
        }
        entries.push(("sort", construction.array(sort)))
        if !order_analytic_slots.is_empty() && pending_select is None {
          step_entries.push(entries)
          step_entries.push([
            (
              "select",
              construction.array(output.map(field => construction.text(field))),
            ),
          ])
          deferred = true
        }
      }
      Limit(count, offset) =>
        entries.push(
          (
            "take",
            construction.object([
              ("count", lower_query_integer(construction, count)),
              ("offset", lower_query_integer(construction, offset)),
            ]),
          ),
        )
    }
    if deferred && entries.length() == 1 && entries[0].0 == "from" {
      first = true
    }
    if !deferred {
      step_entries.push(entries)
    }
    if operation is Select(_, _) && sql_group_projection {
      // Only the SQL SELECT-owned ORDER may use the original grouping scope.
      // A later Pipe continuation cannot recover that input snapshot.
      sql_group_order_input_scope = if @query.operation_at(query, i + 1)
        is Some(Order(_)) {
        sql_group_expression_input_scope
      } else {
        None
      }
      sql_group_select_scope = None
      sql_group_expression_input_scope = None
    }
    if operation is Select(_, _) &&
      pending_select is None &&
      source_projection_capture is Some(capture) {
      // A deferred SELECT still needs the old input for ORDER and cannot be
      // moved across this boundary. No order failure is caught or retried.
      let prefix = step_entries.map(entries => entries.copy())
      if !prefix.is_empty() {
        prefix[0] = prefix[0].map(entry => {
          if entry.0 == "from" {
            ("from", construction.text("aql_capture_0"))
          } else {
            entry
          }
        })
        prefix[prefix.length() - 1].push(
          ("as", construction.text(capture.projection_name)),
        )
        capture.steps = prefix.map(entries => construction.object(entries))
        capture.fields = output.copy()
        capture.count = step_entries.length()
      }
    }
    if operation is Select(_, _) {
      pipe_value_table = false
      pipe_value_columns = []
      analytic_input_fields = None
      analytic_input_scope = None
      qualify_values.clear()
      analytic_outputs.clear()
      positional_set_analytic_slots.clear()
      analytic_expression_bindings.clear()
      if pending_select is None {
        reset_infer_key_labels = true
        value_table_receivers = []
        pipe_value_columns = []
        pipe_value_table = false
        // A projected table has its own columns. Input ranges are needed only
        // while the query's deferred ORDER still consumes the input snapshot.
        pipe_ranges = []
        pipe_star_ranges = []
        scalar_value_table_ranges = []
      }
      // Preserve the existing deferred query ORDER exception for the directly
      // following ORDER, including an elided identity projection.
      // Every other continuation uses only the materialized output scope.
      if !(@query.operation_at(query, i + 1) is Some(Order(_))) {
        pipe_rebound = true
        pipe_selected = false
        distinct_order_scope = false
      }
    }
    if add_distinct {
      step_entries.push([
        (
          "distinct",
          construction.array(output.map(name => construction.text(name))),
        ),
      ])
    }
    if operation is Order(_) {
      let private_slots = order_analytic_slots.map(pair => pair.1)
      active_fields = active_fields.filter(field => {
        !private_slots.contains(field)
      })
      order_analytic_slots.clear()
      sql_group_order_input_scope = None
      if i > 0 && @query.operation_at(query, i - 1) is Some(Select(_, _)) {
        // The SELECT-owned ORDER has consumed its input snapshot. Neither
        // initial-range fallback nor selected-expression reuse may revive it.
        pipe_rebound = true
        pipe_selected = false
        distinct_order_scope = false
      }
      match pending_select {
        Some(selection) => {
          step_entries.push(selection)
          pending_select = None
          value_table_receivers = []
          pipe_value_columns = []
          pipe_value_table = false
          pending_bindings = []
          pipe_ranges = []
          pipe_star_ranges = []
          scalar_value_table_ranges = []
          active_fields = output.copy()
          pipe_visible = output.map(name => (name, name))
          pipe_columns = pipe_visible.copy()
          pipe_changed = false
          reset_infer_key_labels = true
        }
        None => ()
      }
    }
    if update_key_labels {
      infer_key_labels = retain_infer_key_labels(
        construction,
        infer_key_labels,
        previous_key_names,
        infer_key_column_names(
          construction, pipe_visible, positional_private_fields, positional_authored_aliases,
        ),
        active_fields,
        reset=reset_infer_key_labels,
      )
    }
  }
  // An implicit UPDATE consumes this exact Relation scope, including its
  // immutable range slots. Save a branch before the ordinary public projection
  // can discard those slots; the Effect branch closes only its demanded fields.
  let effect_capture_steps : Array[Array[(String, @builder.Node)]] = []
  if @query.terminal_effect(query) is Some(clause) &&
    clause.result is None &&
    @query.set_part_count(query) == 0 &&
    retained is Some(retained) {
    let names = reserved_bindings +
      nearest_inputs.map(input => input.name) +
      [input.name, final_alias] +
      retained.map(result => result.from)
    let producer = pipe_physical_name(names, "aql_update_input_")
    reserved_bindings.push(producer)
    let checkpoint : Array[(String, @builder.Node)] = []
    if first || terminal_result {
      checkpoint.push(("from", construction.text(input_from)))
    }
    checkpoint.push(
      (
        "select",
        construction.array(active_fields.map(field => construction.text(field))),
      ),
    )
    checkpoint.push(("as", construction.text(producer)))
    step_entries.push(checkpoint)
    input_from = producer
    first = true
    let (capture, body) = lower_update_capture(
      construction,
      clause,
      producer,
      pipe_visible,
      pipe_ranges,
      active_fields,
      max_work,
      reserved_bindings~,
      expression_columns=Some(
        unnest_expression_columns(
          pipe_visible, value_table_receivers, scalar_value_table_ranges, pipe_columns,
        ),
      ),
      value_ranges=value_range_names(
        value_table_receivers, scalar_value_table_ranges,
      ),
    )
    retained.push(capture)
    effect_capture_steps.append(body)
  }
  if @query.terminal_store_effect(query) is Some(clause) &&
    @query.set_part_count(query) == 0 &&
    retained is Some(retained) {
    let names = reserved_bindings +
      nearest_inputs.map(input => input.name) +
      [input.name, final_alias] +
      retained.map(result => result.from)
    let producer = pipe_physical_name(names, "aql_store_input_")
    reserved_bindings.push(producer)
    let checkpoint : Array[(String, @builder.Node)] = []
    if first || terminal_result {
      checkpoint.push(("from", construction.text(input_from)))
    }
    checkpoint.push(
      (
        "select",
        construction.array(active_fields.map(field => construction.text(field))),
      ),
    )
    checkpoint.push(("as", construction.text(producer)))
    step_entries.push(checkpoint)
    input_from = producer
    first = true
    let (capture, body) = lower_store_capture(
      construction,
      clause,
      producer,
      pipe_visible,
      pipe_ranges,
      active_fields,
      max_work,
      reserved_bindings~,
      expression_columns=Some(
        unnest_expression_columns(
          pipe_visible, value_table_receivers, scalar_value_table_ranges, pipe_columns,
        ),
      ),
      value_ranges=value_range_names(
        value_table_receivers, scalar_value_table_ranges,
      ),
    )
    retained.push(capture)
    effect_capture_steps.append(body)
  }
  if @query.terminal_insert_effect(query) is Some(clause) &&
    @query.set_part_count(query) == 0 &&
    retained is Some(retained) {
    let names = reserved_bindings +
      nearest_inputs.map(input => input.name) +
      [input.name, final_alias] +
      retained.map(result => result.from)
    let producer = pipe_physical_name(names, "aql_insert_input_")
    reserved_bindings.push(producer)
    let checkpoint : Array[(String, @builder.Node)] = []
    if first || terminal_result {
      checkpoint.push(("from", construction.text(input_from)))
    }
    checkpoint.push(
      (
        "select",
        construction.array(active_fields.map(field => construction.text(field))),
      ),
    )
    checkpoint.push(("as", construction.text(producer)))
    step_entries.push(checkpoint)
    input_from = producer
    first = true
    let (capture, body) = lower_insert_capture(
      construction,
      clause,
      producer,
      pipe_visible,
      pipe_ranges,
      active_fields,
      max_work,
      reserved_bindings~,
      expression_columns=Some(
        unnest_expression_columns(
          pipe_visible, value_table_receivers, scalar_value_table_ranges, pipe_columns,
        ),
      ),
      value_ranges=value_range_names(
        value_table_receivers, scalar_value_table_ranges,
      ),
    )
    retained.push(capture)
    effect_capture_steps.append(body)
  }
  if @query.terminal_short_command_effect(query) is Some(clause) &&
    @query.set_part_count(query) == 0 &&
    retained is Some(retained) {
    let names = reserved_bindings +
      nearest_inputs.map(input => input.name) +
      [input.name, final_alias] +
      retained.map(result => result.from)
    let producer = pipe_physical_name(names, "aql_command_input_")
    reserved_bindings.push(producer)
    let checkpoint : Array[(String, @builder.Node)] = []
    if first || terminal_result {
      checkpoint.push(("from", construction.text(input_from)))
    }
    checkpoint.push(
      (
        "select",
        construction.array(active_fields.map(field => construction.text(field))),
      ),
    )
    checkpoint.push(("as", construction.text(producer)))
    step_entries.push(checkpoint)
    input_from = producer
    first = true
    let (capture, body) = lower_short_command_capture(
      construction,
      clause,
      producer,
      pipe_visible,
      pipe_ranges,
      active_fields,
      max_work,
      reserved_bindings~,
      expression_columns=Some(
        unnest_expression_columns(
          pipe_visible, value_table_receivers, scalar_value_table_ranges, pipe_columns,
        ),
      ),
      value_ranges=value_range_names(
        value_table_receivers, scalar_value_table_ranges,
      ),
    )
    retained.push(capture)
    effect_capture_steps.append(body)
  }
  let retained_scope = match preserved_scope {
    Some(scopes) => Some(scopes)
    None => if pipe_value_table { value_table_scope } else { None }
  }
  if retained_scope is Some(scopes) {
    // A private Pipe continuation carries value slots, not exported names.
    // Preserve existing scope/evidence; the consuming JOIN remaps these slots.
    scopes.push({
      visible: pipe_visible.copy(),
      ranges: pipe_ranges.copy(),
      columns: pipe_columns.copy(),
      value_table: pipe_value_table,
      value_columns: pipe_value_columns.copy(),
      star_ranges: pipe_star_ranges.copy(),
      receivers: value_table_receivers.copy(),
      key_labels: infer_key_labels.copy(),
      scalar_ranges: scalar_value_table_ranges.copy(),
    })
    output = active_fields.copy()
  } else if pipe_changed && !terminal_result {
    let selected : Array[@builder.Node] = []
    let exported : Array[String] = []
    for field in pipe_visible {
      if exported.any(prior => {
          same_name({ value: prior, quoted: false, }, {
            value: field.0,
            quoted: false,
          })
        }) {
        raise Abort(DuplicateOutput)
      }
      exported.push(field.0)
      selected.push(
        if field.0 == field.1 {
          construction.text(field.1)
        } else {
          construction.object([(field.0, construction.text(field.1))])
        },
      )
    }
    let entries : Array[(String, @builder.Node)] = []
    if first {
      entries.push(("from", construction.text(input_from)))
    }
    entries.push(("select", construction.array(selected)))
    step_entries.push(entries)
    output = pipe_visible.map(field => field.0)
  }
  if step_entries.is_empty() {
    return ([], output)
  }
  // The last step supplies a stable named stage result for ordinary routing.
  // This is a structural step alias, not a SQL range alias.
  if !terminal_result {
    if step_entries[step_entries.length() - 1].any(entry => entry.0 == "as") {
      // A scope-only tail must not overwrite the retained checkpoint's name.
      // Give the continuing primary output its own identity projection.
      step_entries.push([
        ("from", construction.text(input_from)),
        (
          "select",
          construction.array(output.map(field => construction.text(field))),
        ),
      ])
    }
    step_entries[step_entries.length() - 1].push(
      ("as", construction.text(final_alias)),
    )
  }
  step_entries.append(effect_capture_steps)
  let emitted = match source_projection_capture {
    Some(capture) if capture.count > 0 => {
      let tail = Array::makei(step_entries.length() - capture.count, i => {
        step_entries[capture.count + i]
      })
      if tail.is_empty() {
        // The projection itself was the complete Query. Preserve the normal
        // consumer Stage and public Result name without evaluating it twice.
        tail.push([
          (
            "select",
            construction.array(output.map(field => construction.text(field))),
          ),
          ("as", construction.text(final_alias)),
        ])
      }
      // Continue from the exact projected Result, not the raw provider input.
      tail[0].insert(0, ("from", construction.text(input.name)))
      tail
    }
    _ => step_entries
  }
  (emitted.map(entries => construction.object(entries)), output)
}

///|
// Reuse the same explicit acquisition boundary for ordinary and CTE sources.
// Downstream projection and shared CTE references consume the captured Result.
fn capture_source_boundary(
  construction : Construction,
  stage_id : String,
  input_name : String,
  imported : @builder.Node,
  fields : Array[String],
  predicate : @builder.Node,
  projection? : SourceProjectionCapture? = None,
) -> (@builder.Node, @builder.Node) raise Abort {
  let capture_filter = construction.object([
    ("from", construction.text(input_name)),
    ("filter", predicate),
  ])
  let capture_step = construction.object([
    (
      "select",
      construction.array(fields.map(field => construction.text(field))),
    ),
    ("as", construction.text("aql_capture_0")),
  ])
  let (publication_from, publication_fields, continuation) = match projection {
    Some(projection) if projection.count > 0 =>
      (projection.projection_name, projection.fields, projection.steps)
    _ => ("aql_capture_0", fields, [])
  }
  let capture_result = construction.object([
    ("from", construction.text(publication_from)),
    (
      "fields",
      construction.array(
        publication_fields.map(field => construction.text(field)),
      ),
    ),
  ])
  let capture = construction.object([
    ("id", construction.text(stage_id)),
    ("inputs", construction.object([(input_name, imported)])),
    ("steps", construction.array([capture_filter, capture_step] + continuation)),
    ("results", construction.object([("source", capture_result)])),
  ])
  let source_ref = construction.object([
    (
      "result",
      construction.object([
        ("stage", construction.text(stage_id)),
        ("result", construction.text("source")),
      ]),
    ),
  ])
  (capture, source_ref)
}

///|
// Supplied source fragments are admitted projections of a compile context.
// This frontend does not ask a provider for rows or infer schema during check.

///|
/// Return the existing construction owner alongside its exact admitted Program
/// for diagnostic projection only. This is the same lowering path as compile.
pub fn compile_with_source(
  query : @query.Query,
  context : Context,
  limits : Limits,
  table_writes? : Array[TableWriteBinding] = [],
  update_targets? : UpdateTargetPublication? = None,
  store_targets? : StoreTargetPublication? = None,
  command_targets? : CommandTargetPublication? = None,
) -> Result[(@program.Program, @builder.Source), Issue] {
  // Terminal operations use the ordinary script compiler's original target
  // selection and private Result capture; none may disappear into a pure query.
  // Binding and primary scopes must be installed before inspecting a JOIN
  // input. The standalone probe sees only Context inputs, not authored WITH
  // producers or transformed range inputs.
  if @query.terminal_short_command_effect(query) is Some(_) ||
    @query.terminal_store_effect(query) is Some(_) ||
    @query.terminal_insert_effect(query) is Some(_) ||
    @query.terminal_command_effect_count(query) > 0 ||
    @query.terminal_effect(query) is Some(_) ||
    @query.terminal_table_effect(query) is Some(_) ||
    has_pipe_range_input(query) ||
    script_has_carrier_calls(query) ||
    has_cte_unnest_input(query) ||
    @query.query_binding_count(query) > 0 ||
    @query.producer_primary(query) is Some(_) ||
    @query.graph_query(query) is Some(_) {
    return compile_query_script_with_source(
      @query.single_query_script(query),
      context,
      limits,
      table_writes~,
      update_targets~,
      store_targets~,
      command_targets~,
    )
  }
  let needs_input_binding = join_requires_input_binding(query, context) catch {
    Abort(issue) => return Err(issue)
  }
  if needs_input_binding {
    return compile_query_script_with_source(
      @query.single_query_script(query),
      context,
      limits,
      table_writes~,
      update_targets~,
      store_targets~,
      command_targets~,
    )
  }
  let mut has_nearest = false
  for i in 0..<@query.operation_count(query) {
    if @query.operation_at(query, i) is Some(Nearest(_)) {
      has_nearest = true
    }
  }
  if has_nearest &&
    (
      @query.query_binding_count(query) > 0 ||
      @query.set_part_count(query) > 0 ||
      @query.join_part_count(query) > 0 ||
      @query.graph_query(query) is Some(_)
    ) {
    return Err(UnsupportedNearest)
  }
  if @query.graph_query(query) is Some(_) {
    // A query-only context carries Relation inputs, not an admitted current
    // constructor definition. The retired tuple generator is not a fallback.
    // Current Graph construction and MATCH/TRAIL use the ordinary Program
    // checker; the Script frontend supplies that definition-scoped path.
    return Err(UnsupportedGraph)
  }
  if query_has_join_set_operand(query) || query_has_mixed_cte_join_input(query) {
    return compile_query_script_with_source(
      @query.single_query_script(query),
      context,
      limits,
      table_writes~,
      update_targets~,
      store_targets~,
      command_targets~,
    )
  }
  if @query.join_part_count(query) > 0 && context.captured_stage is Some(_) {
    // The Host requested a capture boundary. Reuse the script's existing
    // producer binding for raw/shared sources and derived-table CTEs, including
    // a single projected JOIN. Captured inputs cannot use the Values-only path.
    return compile_query_script_with_source(
      @query.single_query_script(query),
      context,
      limits,
    )
  }
  if @query.set_part_count(query) > 0 {
    return compile_set_query(query, context, limits)
  }
  if @query.join_part_count(query) > 0 {
    if @query.join_part_count(query) > 1 || join_requires_group_scope(query) {
      return compile_join_chain_query(query, context, limits)
    }
    return compile_join_query(query, context, limits)
  }
  if limits.max_expression_work < 0 ||
    context.program_id == "" ||
    context.stage_id == "" ||
    context.stage_result == "" ||
    context.result_name == "" ||
    context.captured_stage == Some(context.stage_id) ||
    context.captured_stage == Some("") {
    return Err(InvalidContext)
  }
  let input = selected_input(query, context, limits) catch {
    Abort(issue) => return Err(issue)
  }
  let fields = query_columns(query, input) catch {
    Abort(issue) => return Err(issue)
  }
  let document = @query.query_document(query)
  let generated = @origin.range(document, 0, 0, kind=Generated).unwrap()
  let builder = match @builder.create(document, limits.source) {
    Ok(builder) => builder
    Err(issue) => return Err(Construction(issue))
  }
  let parameter_names = query_parameter_names(
    context.parameter_declarations,
    limits.max_expression_work,
  ) catch {
    Abort(issue) => {
      @builder.discard(builder)
      return Err(issue)
    }
  }
  let construction : Construction = {
    builder,
    generated,
    model_tasks: context.model_tasks,
    parameter_names,
    infer_labels: query_has_omitted_infer(query),
    infer_budget: { remaining_work: limits.max_expression_work, },
  }
  try {
    let dependencies = nearest_dependencies(query, context.inputs)
    let reused_query_source = dependencies.any(other => other.name == input.name)
    let fragment = match input.source {
      Captured(declaration) => declaration
      GeneratedValues(step) => step
      StageResult(_, _) | StepReference => raise Abort(InvalidContext)
    }
    let imported = match @builder.import_cursor(builder, fragment, generated) {
      Ok(node) => node
      Err(issue) => raise Abort(Construction(issue))
    }
    let source_projection_capture : SourceProjectionCapture? = if input.source
      is Captured(_) &&
      context.captured_stage is Some(_) &&
      dependencies.is_empty() &&
      source_projection_capture_query(query) {
      Some({
        projection_name: pipe_physical_name(
          fields + [input.name],
          "aql_capture_projection_",
        ),
        steps: [],
        fields: [],
        count: 0,
      })
    } else {
      None
    }
    let capture_details : Array[(String, @builder.Node, @builder.Node)] = []
    let mut start_at = 0
    let (input_entries, seed_steps, capture_stage) = match input.source {
      Captured(_) =>
        match context.captured_stage {
          Some(stage_id) => {
            let predicate = match @query.operation_at(query, 0) {
              Some(Where(expression)) if !reused_query_source => {
                start_at = 1
                append_expression(
                  construction,
                  expression,
                  query,
                  input,
                  fields,
                  limits.max_expression_work,
                )
              }
              _ =>
                construction.object([("literal", construction.add(Bool(true)))])
            }
            capture_details.push((stage_id, imported, predicate))
            let (capture, source_ref) = capture_source_boundary(
              construction,
              stage_id,
              input.name,
              imported,
              fields,
              predicate,
            )
            ([(input.name, source_ref)], [], Some(capture))
          }
          None => ([(input.name, imported)], [], None)
        }
      GeneratedValues(_) => {
        if context.captured_stage is Some(_) &&
          !@query.relation(query).is_empty() {
          raise Abort(InvalidContext)
        }
        ([], [imported], None)
      }
      StageResult(_, _) | StepReference => raise Abort(InvalidContext)
    }
    let capture_stages = match capture_stage {
      Some(stage) => [stage]
      None => []
    }
    for candidate in dependencies {
      if candidate.name == input.name {
        if !same_relation_path(candidate.relation, input.relation) {
          raise Abort(InvalidContext)
        }
        continue
      }
      match candidate.source {
        GeneratedValues(step) => {
          if context.captured_stage is Some(_) {
            raise Abort(InvalidContext)
          }
          seed_steps.push(import_query_cursor(construction, step))
        }
        Captured(declaration) => {
          let imported = import_query_cursor(construction, declaration)
          match context.captured_stage {
            None => input_entries.push((candidate.name, imported))
            Some(stage_id) => {
              let capture_id = stage_id +
                "_nearest_" +
                capture_stages.length().to_string()
              if capture_id == context.stage_id ||
                context.inputs.any(input => input.name == capture_id) {
                raise Abort(InvalidContext)
              }
              let (capture, reference) = capture_source_boundary(
                construction,
                capture_id,
                candidate.name,
                imported,
                columns(candidate),
                construction.object([("literal", construction.add(Bool(true)))]),
              )
              capture_stages.push(capture)
              input_entries.push((candidate.name, reference))
            }
          }
        }
        StageResult(_, _) | StepReference => raise Abort(UnsupportedNearest)
      }
    }
    let infer_budget = construction.infer_budget
    let retained : Array[RetainedResult] = []
    let (steps, output) = compile_steps(
      construction,
      query,
      input,
      fields,
      limits.max_expression_work,
      limits,
      limits.max_collection_items,
      limits.max_collection_bytes,
      start_at,
      context.captured_stage is Some(_),
      "aql_gen_0",
      nearest_inputs=[input] +
        dependencies.filter(other => other.name != input.name),
      retained=Some(retained),
      parameter_declarations=context.parameter_declarations,
      prefix_steps=seed_steps,
      prefix_context=Some(context),
      source_projection_capture~,
      checked_nearest_prefix=Some(nodes => {
        checked_query_prefix_pipeline(
          construction, query, context, capture_stages, input_entries, nodes, limits,
          infer_budget,
        )
      }),
      checked_infer_prefix=Some((nodes, producer, visible, authored_aliases) => {
        infer_prefix_check(
          construction, query, context, capture_stages, input_entries, nodes, producer,
          limits, infer_budget, visible, authored_aliases,
        )
      }),
    )
    if source_projection_capture is Some(projection) && projection.count > 0 {
      let (stage_id, imported, predicate) = capture_details[0]
      let (capture, _) = capture_source_boundary(
        construction,
        stage_id,
        input.name,
        imported,
        fields,
        predicate,
        projection=Some(projection),
      )
      capture_stages[0] = capture
    }
    let all_steps = seed_steps + steps
    let result_source = if steps.is_empty() { input.name } else { "aql_gen_0" }
    let result = construction.object([
      ("from", construction.text(result_source)),
      (
        "fields",
        construction.array(output.map(name => construction.text(name))),
      ),
    ])
    let stage = construction.object([
      ("id", construction.text(context.stage_id)),
      ("inputs", construction.object(input_entries)),
      ("steps", construction.array(all_steps)),
      (
        "results",
        retained_stage_results(
          construction,
          context.stage_result,
          result,
          retained,
        ),
      ),
    ])
    let stages = capture_stages + [stage]
    let root = program_root(
      construction,
      context,
      stages,
      result_exports=retained_result_exports(context, retained),
    )
    let source = match @builder.finish(builder, root) {
      Ok(source) => source
      Err(issue) => raise Abort(Construction(issue))
    }
    match admit_query_source(source, document, context, limits) {
      Ok(program) => Ok(program)
      Err(issue) => Err(issue)
    }
  } catch {
    Abort(issue) => {
      @builder.discard(builder)
      Err(issue)
    }
  }
}

///|
// Enumerate the head and set operands for shared query composition. Binding
// resolution, demand and capture remain with the unified script owner.
fn query_terms(query : @query.Query) -> Array[@query.Query] {
  let terms = [query]
  for index in 0..<@query.set_part_count(query) {
    terms.push(@query.set_part_at(query, index).unwrap().right)
  }
  terms
}

///|
fn compile_join_steps(
  construction : Construction,
  query : @query.Query,
  left_name : @query.NamePart,
  left_fields : Array[String],
  right_name : @query.NamePart,
  right_fields : Array[String],
  limits : Limits,
  retained? : Array[RetainedResult]? = None,
  left_from? : String = "l",
  right_from? : String = "r",
  step_bindings? : Map[String, String] = Map([]),
  capture_left? : Bool = false,
  values_bound? : Int64? = None,
  prefix_steps? : Array[@builder.Node] = [],
  reserved_bindings? : Array[String] = [],
  checked_infer_prefix? : ((
    Array[@builder.Node],
    String,
    InferInputLabels,
    Array[(String, String)],
  ) -> InferPrefixProjection raise Abort)? = None,
  checked_nearest_prefix? : ((Array[@builder.Node]) -> @pipeline.CheckedPipeline raise Abort)? = None,
) -> (Array[@builder.Node], Array[String], String) raise Abort {
  if @query.operation_count(query) < 1 ||
    limits.max_join_output_rows < 1L ||
    limits.max_join_output_rows > 9007199254740991L {
    raise Abort(UnsupportedCte)
  }
  let part = @query.join_part_at(query, 0).unwrap()
  let max_output_rows = if part.max_output_rows is Some(_) {
    authored_join_bound(part, limits)
  } else {
    values_bound.unwrap_or_else(() => authored_join_bound(part, limits))
  }
  let left_qualifier = @query.relation_alias(query).unwrap_or(left_name)
  let right_qualifier = part.source_alias.unwrap_or(right_name)
  if same_name(left_qualifier, right_qualifier) {
    raise Abort(AmbiguousRelation)
  }
  let keys = join_keys(
    part, left_qualifier, right_qualifier, left_fields, right_fields,
  )
  let pre_steps : Array[@builder.Node] = []
  let mut join_from = left_from
  match part.pre_join_filter {
    Some(expression) => {
      let resolve = fn(path : Array[@query.NamePart]) -> String? {
        let selected = Some(
          join_field(path, left_qualifier, right_qualifier, left_fields, []),
        ) catch {
          Abort(_) => None
        }
        selected.map(field => field.1)
      }
      let filter = match
        @expression.append_with_properties(
          expression,
          resolve,
          construction.builder,
          limits.max_expression_work,
          resolve_parameter=construction.parameter_resolver(),
        ) {
        Ok(value) => value
        Err(error) => raise Abort(Expression(error))
      }
      pre_steps.push(
        construction.object([
          ("from", construction.text(join_from)),
          ("filter", filter),
          (
            "as",
            construction.text(
              join_step_binding(step_bindings, "aql_join_prefiltered"),
            ),
          ),
        ]),
      )
      join_from = join_step_binding(step_bindings, "aql_join_prefiltered")
    }
    None => ()
  }
  if capture_left {
    // The common Direct acquisition owns a filter/select capture prefix.
    // Preserve an authored pre-JOIN predicate above; SQL's post-JOIN WHERE
    // remains below the JOIN and must never become a content-read filter.
    if part.pre_join_filter is None {
      pre_steps.push(
        construction.object([
          ("from", construction.text(join_from)),
          (
            "filter",
            construction.object([("literal", construction.add(Bool(true)))]),
          ),
          (
            "as",
            construction.text(
              join_step_binding(step_bindings, "aql_join_prefiltered"),
            ),
          ),
        ]),
      )
      join_from = join_step_binding(step_bindings, "aql_join_prefiltered")
    }
    let capture = join_step_binding(step_bindings, "aql_join_captured")
    pre_steps.push(
      construction.object([
        ("from", construction.text(join_from)),
        (
          "select",
          construction.array(left_fields.map(field => construction.text(field))),
        ),
        ("as", construction.text(capture)),
      ]),
    )
    join_from = capture
  }
  let predicate = match @query.operation_at(query, 0) {
    Some(Where(expression)) => Some(expression)
    _ => None
  }
  let select_index = if predicate is Some(_) { 1 } else { 0 }
  guard @query.operation_at(query, select_index)
    is Some(Select(projections, distinct)) else {
    raise Abort(UnsupportedCte)
  }
  if part.kind != "full" {
    let (projected, visible_names, order_fields, order_expressions, next) = join_order_projection(
      query, projections, distinct, select_index, part, left_qualifier, right_qualifier,
      left_fields, right_fields,
    )
    let (select, tail, output, joined) = joined_projection(
      construction,
      projected,
      order_expressions,
      predicate,
      part,
      left_qualifier,
      right_qualifier,
      left_fields,
      right_fields,
      limits.max_expression_work,
      step_bindings~,
    )
    let operation = if part.kind == "cross" {
      (
        "cross_join",
        construction.object([
          ("with", construction.text(right_from)),
          (
            "max_output_rows",
            construction.add(Number(max_output_rows.to_double())),
          ),
          ("select", construction.object(select)),
        ]),
      )
    } else {
      (
        "join",
        construction.object([
          ("with", construction.text(right_from)),
          ("kind", construction.text(part.kind)),
          (
            "on",
            construction.array(
              keys.map(pair => {
                construction.object([
                  ("left", construction.text(pair.0)),
                  ("right", construction.text(pair.1)),
                ])
              }),
            ),
          ),
          (
            "max_output_rows",
            construction.add(Number(max_output_rows.to_double())),
          ),
          ("select", construction.object(select)),
        ]),
      )
    }
    let steps = pre_steps +
      [
        construction.object([
          ("from", construction.text(join_from)),
          operation,
          ("as", construction.text(joined)),
        ]),
      ] +
      tail
    if distinct {
      steps.push(
        construction.object([
          (
            "from",
            construction.text(
              join_step_binding(step_bindings, "aql_join_output"),
            ),
          ),
          (
            "distinct",
            construction.array(
              visible_names.map(name => construction.text(name)),
            ),
          ),
          (
            "as",
            construction.text(
              join_step_binding(step_bindings, "aql_join_unique"),
            ),
          ),
        ]),
      )
    }
    let final_from = append_join_order_steps(
      construction,
      query,
      steps,
      order_fields,
      visible_names,
      output.length(),
      if distinct {
        join_step_binding(step_bindings, "aql_join_unique")
      } else {
        join_step_binding(step_bindings, "aql_join_output")
      },
      next,
      result_tail=join_continuation_context(query, limits, retained),
      step_bindings~,
      prefix_steps~,
      reserved_bindings~,
      checked_infer_prefix~,
      checked_nearest_prefix~,
    )
    return (steps, visible_names, final_from)
  }
  if predicate is Some(_) {
    raise Abort(UnsupportedCte)
  }
  let select : Array[(String, @builder.Node)] = []
  let output : Array[String] = []
  for projection in projections {
    guard projection.expression is Some(expression) &&
      projection.aggregate is None &&
      projection.analytic is None &&
      @query.expression_node(expression, @query.expression_root(expression))
      is Some({ kind: Reference(path), .. }) else {
      raise Abort(UnsupportedCte)
    }
    let name = projection.name
      .map(value => value.value)
      .unwrap_or(path.last().unwrap().value)
    if output.any(field => ascii_upper(field) == ascii_upper(name)) {
      raise Abort(DuplicateOutput)
    }
    output.push(name)
  }
  if output.is_empty() {
    raise Abort(UnsupportedCte)
  }
  let reserved = left_fields + right_fields
  for name in output {
    reserved.push(name)
  }
  let merged : Array[(String, String, String)] = []
  for index in 0..<projections.length() {
    let projection = projections[index]
    let expression = projection.expression.unwrap()
    guard @query.expression_node(expression, @query.expression_root(expression))
      is Some({ kind: Reference(path), .. }) else {
      raise Abort(UnsupportedCte)
    }
    let name = output[index]
    if part.kind == "full" &&
      path.length() == 1 &&
      part.using_columns.any(key => same_name(key, path[0])) {
      let left = join_field(
        [left_qualifier, path[0]],
        left_qualifier,
        right_qualifier,
        left_fields,
        right_fields,
      )
      let right = join_field(
        [right_qualifier, path[0]],
        left_qualifier,
        right_qualifier,
        left_fields,
        right_fields,
      )
      let left_slot = pipe_physical_name(reserved, "aql_join_left_key_")
      reserved.push(left_slot)
      let right_slot = pipe_physical_name(reserved, "aql_join_right_key_")
      reserved.push(right_slot)
      select.push((left_slot, construction.text(left.0 + "." + left.1)))
      select.push((right_slot, construction.text(right.0 + "." + right.1)))
      merged.push((name, left_slot, right_slot))
    } else {
      let resolved = join_projection_field(
        path, part, left_qualifier, right_qualifier, left_fields, right_fields,
      )
      select.push((name, construction.text(resolved.0 + "." + resolved.1)))
    }
  }
  let operation = if part.kind == "cross" {
    (
      "cross_join",
      construction.object([
        ("with", construction.text(right_from)),
        (
          "max_output_rows",
          construction.add(Number(max_output_rows.to_double())),
        ),
        ("select", construction.object(select)),
      ]),
    )
  } else {
    (
      "join",
      construction.object([
        ("with", construction.text(right_from)),
        ("kind", construction.text(part.kind)),
        (
          "on",
          construction.array(
            keys.map(pair => {
              construction.object([
                ("left", construction.text(pair.0)),
                ("right", construction.text(pair.1)),
              ])
            }),
          ),
        ),
        (
          "max_output_rows",
          construction.add(Number(max_output_rows.to_double())),
        ),
        ("select", construction.object(select)),
      ]),
    )
  }
  let steps : Array[@builder.Node] = pre_steps.copy()
  steps.push(
    construction.object([
      ("from", construction.text(join_from)),
      operation,
      (
        "as",
        construction.text(
          if merged.is_empty() {
            join_step_binding(step_bindings, "aql_join_output")
          } else {
            join_step_binding(step_bindings, "aql_join_raw")
          },
        ),
      ),
    ]),
  )
  if !merged.is_empty() {
    steps.push(
      construction.object([
        (
          "from",
          construction.text(join_step_binding(step_bindings, "aql_join_raw")),
        ),
        (
          "derive",
          construction.object(
            merged.map(entry => {
              (
                entry.0,
                construction.object([
                  (
                    "coalesce",
                    construction.array([
                      construction.object([
                        ("field", construction.text(entry.1)),
                      ]),
                      construction.object([
                        ("field", construction.text(entry.2)),
                      ]),
                    ]),
                  ),
                ]),
              )
            }),
          ),
        ),
        (
          "as",
          construction.text(join_step_binding(step_bindings, "aql_join_merged")),
        ),
      ]),
    )
    steps.push(
      construction.object([
        (
          "from",
          construction.text(join_step_binding(step_bindings, "aql_join_merged")),
        ),
        (
          "select",
          construction.array(output.map(name => construction.text(name))),
        ),
        (
          "as",
          construction.text(join_step_binding(step_bindings, "aql_join_output")),
        ),
      ]),
    )
  }
  if distinct {
    steps.push(
      construction.object([
        (
          "from",
          construction.text(join_step_binding(step_bindings, "aql_join_output")),
        ),
        (
          "distinct",
          construction.array(output.map(name => construction.text(name))),
        ),
        (
          "as",
          construction.text(join_step_binding(step_bindings, "aql_join_unique")),
        ),
      ]),
    )
  }
  let from = append_join_order_steps(
    construction,
    query,
    steps,
    [],
    output,
    output.length(),
    if distinct {
      join_step_binding(step_bindings, "aql_join_unique")
    } else {
      join_step_binding(step_bindings, "aql_join_output")
    },
    select_index + 1,
    result_tail=join_continuation_context(query, limits, retained),
    step_bindings~,
    prefix_steps~,
    reserved_bindings~,
    checked_infer_prefix~,
    checked_nearest_prefix~,
  )
  (steps, output, from)
}

///|
// Set operands remain checked Program steps. Position matching is expressed
// as an ordinary simultaneous projection before the existing row-set kernel.
fn compile_set_query(
  query : @query.Query,
  context : Context,
  limits : Limits,
) -> Result[(@program.Program, @builder.Source), Issue] {
  if limits.max_expression_work < 0 ||
    context.program_id == "" ||
    context.stage_id == "" ||
    context.stage_result == "" ||
    context.result_name == "" ||
    context.captured_stage == Some("") ||
    context.captured_stage == Some(context.stage_id) {
    return Err(InvalidContext)
  }
  let document = @query.query_document(query)
  let generated = @origin.range(document, 0, 0, kind=Generated).unwrap()
  let builder = match @builder.create(document, limits.source) {
    Ok(builder) => builder
    Err(issue) => return Err(Construction(issue))
  }
  let parameter_names = query_parameter_names(
    context.parameter_declarations,
    limits.max_expression_work,
  ) catch {
    Abort(issue) => {
      @builder.discard(builder)
      return Err(issue)
    }
  }
  let construction : Construction = {
    builder,
    generated,
    model_tasks: context.model_tasks,
    parameter_names,
    infer_labels: query_has_omitted_infer(query),
    infer_budget: { remaining_work: limits.max_expression_work, },
  }
  try {
    let (stages, _) = compile_set_stages(
      construction, query, context, limits, "",
    )
    let root = program_root(construction, context, stages)
    let source = match @builder.finish(builder, root) {
      Ok(source) => source
      Err(issue) => raise Abort(Construction(issue))
    }
    match admit_query_source(source, document, context, limits) {
      Ok(program) => Ok(program)
      Err(issue) => Err(issue)
    }
  } catch {
    Abort(issue) => {
      @builder.discard(builder)
      Err(issue)
    }
  }
}

///|
// The same checked set emitter serves root queries and retained CTE bodies.
fn compile_set_stages(
  construction : Construction,
  query : @query.Query,
  context : Context,
  limits : Limits,
  prefix : String,
) -> (Array[@builder.Node], Array[String]) raise Abort {
  let terms : Array[@query.Query] = [query]
  for index in 0..<@query.set_part_count(query) {
    terms.push(@query.set_part_at(query, index).unwrap().right)
  }
  let stages : Array[@builder.Node] = []
  let sources : Array[String] = []
  let outputs : Array[Array[String]] = []
  let mut first_term : (
    Int,
    String,
    String,
    String,
    String,
    Array[@builder.Node],
  )? = None
  let captured : Array[(String, String, Bool)] = []
  let infer_budget = construction.infer_budget
  for index in 0..<terms.length() {
    let term = terms[index]
    if @query.join_part_count(term) > 0 {
      raise Abort(UnsupportedJoin)
    }
    let input = selected_input(term, context, limits)
    let fields = query_columns(term, input)
    let mut common_capture_filter = false
    let (seed_stage, seed_result) = match input.source {
      GeneratedValues(step) => {
        if context.captured_stage is Some(_) &&
          !@query.relation(term).is_empty() {
          raise Abort(InvalidContext)
        }
        let seed = match
          @builder.import_cursor(
            construction.builder,
            step,
            construction.generated,
          ) {
          Ok(node) => node
          Err(issue) => raise Abort(Construction(issue))
        }
        let seed_stage = prefix + "aql_set_seed_" + index.to_string()
        stages.push(
          construction.object([
            ("id", construction.text(seed_stage)),
            ("inputs", construction.object([])),
            ("steps", construction.array([seed])),
            (
              "results",
              construction.object([
                (
                  seed_stage,
                  construction.object([
                    ("from", construction.text(input.name)),
                    (
                      "fields",
                      construction.array(
                        columns(input).map(name => construction.text(name)),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          ]),
        )
        (seed_stage, seed_stage)
      }
      Captured(declaration) => {
        let mut prior : String? = None
        for pair in captured {
          if pair.0 == input.name {
            prior = Some(pair.1)
            common_capture_filter = pair.2
          }
        }
        let capture_stage = match prior {
          Some(name) => name
          None => {
            // The installed Host currently owns one physical acquisition
            // for a set query. Multiple distinct sources need separate
            // checked Host bindings before they can be admitted here.
            if !captured.is_empty() {
              raise Abort(UnsupportedSet)
            }
            let first_filter = match @query.operation_at(term, 0) {
              Some(Where(expression)) => Some(expression)
              _ => None
            }
            let mut common = first_filter is Some(_)
            for other in terms {
              let other_input = selected_input(other, context, limits)
              if other_input.name == input.name {
                match (first_filter, @query.operation_at(other, 0)) {
                  (Some(first), Some(Where(next))) =>
                    if !same_expression(first, next) {
                      common = false
                    }
                  _ => common = false
                }
              }
            }
            common_capture_filter = common
            let predicate = if common {
              append_expression(
                construction,
                first_filter.unwrap(),
                term,
                input,
                fields,
                limits.max_expression_work,
              )
            } else {
              construction.object([("literal", construction.add(Bool(true)))])
            }
            let name = if captured.is_empty() {
              context.captured_stage.unwrap_or(prefix + "aql_set_capture_0")
            } else {
              prefix + "aql_set_capture_" + captured.length().to_string()
            }
            let mut reserved = name == context.stage_id
            for term_index in 0..<terms.length() {
              reserved = reserved ||
                name == prefix + "aql_set_seed_" + term_index.to_string() ||
                name == prefix + "aql_set_term_" + term_index.to_string() ||
                name == prefix + "aql_set_aligned_" + term_index.to_string() ||
                name == prefix + "aql_set_merge_" + term_index.to_string() ||
                name == prefix + "aql_set_unique_" + term_index.to_string()
            }
            if reserved {
              raise Abort(InvalidContext)
            }
            let imported = match
              @builder.import_cursor(
                construction.builder,
                declaration,
                construction.generated,
              ) {
              Ok(node) => node
              Err(issue) => raise Abort(Construction(issue))
            }
            // The existing captured DAG binds the acquisition at unit zero.
            // A source-free earlier operand may already have emitted Values
            // stages; keep those producers and the ordinal append unchanged.
            stages.insert(
              0,
              construction.object([
                ("id", construction.text(name)),
                ("inputs", construction.object([(input.name, imported)])),
                (
                  "steps",
                  construction.array([
                    construction.object([
                      ("from", construction.text(input.name)),
                      ("filter", predicate),
                    ]),
                    construction.object([
                      (
                        "select",
                        construction.array(
                          fields.map(field => construction.text(field)),
                        ),
                      ),
                      ("as", construction.text("aql_capture_0")),
                    ]),
                  ]),
                ),
                (
                  "results",
                  construction.object([
                    (
                      "source",
                      construction.object([
                        ("from", construction.text("aql_capture_0")),
                        (
                          "fields",
                          construction.array(
                            fields.map(field => construction.text(field)),
                          ),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ]),
            )
            captured.push((input.name, name, common))
            name
          }
        }
        (capture_stage, "source")
      }
      StageResult(producer, result) => (producer, result)
      StepReference => raise Abort(InvalidContext)
    }
    let term_stage = prefix + "aql_set_term_" + index.to_string()
    if context.inputs.any(other => other.name == term_stage) {
      raise Abort(InvalidContext)
    }
    let term_name = "aql_set_output_" + index.to_string()
    let (body, compiled_output) = compile_steps(
      construction,
      term,
      input,
      fields,
      limits.max_expression_work,
      limits,
      limits.max_collection_items,
      limits.max_collection_bytes,
      if common_capture_filter {
        1
      } else {
        0
      },
      input.source is Captured(_),
      term_name,
      parameter_declarations=context.parameter_declarations,
      prefix_context=Some(context),
      checked_infer_prefix=Some((nodes, producer, visible, authored_aliases) => {
        infer_prefix_check(
          construction,
          term,
          { ..context, stage_id: term_stage, },
          stages,
          [
            (
              input.name,
              construction.object([
                (
                  "result",
                  construction.object([
                    ("stage", construction.text(seed_stage)),
                    ("result", construction.text(seed_result)),
                  ]),
                ),
              ]),
            ),
          ],
          nodes,
          producer,
          limits,
          infer_budget,
          visible,
          authored_aliases,
        )
      }),
      positional_set_output=index > 0 &&
        !@query.set_part_at(query, index - 1).unwrap().by_name,
    )
    let term_steps : Array[@builder.Node] = []
    for step in body {
      term_steps.push(step)
    }
    if term_steps.is_empty() {
      term_steps.push(
        construction.object([
          ("from", construction.text(input.name)),
          (
            "select",
            construction.array(fields.map(name => construction.text(name))),
          ),
          ("as", construction.text(term_name)),
        ]),
      )
    }
    let mut output = compiled_output
    let mut term_result = term_name
    if index == 0 && !@query.set_part_at(query, 0).unwrap().inner_by_name {
      let part = @query.set_part_at(query, 0).unwrap()
      let ordered = set_output_fields(output, part)
      let (matched, needed) = set_alignment_fields(ordered, output, true)
      if needed {
        term_result = term_name + "_ordered"
        term_steps.push(
          construction.object([
            ("from", construction.text(term_name)),
            ("select", set_select_fields(construction, ordered, matched)),
            ("as", construction.text(term_result)),
          ]),
        )
      }
      output = ordered
    }
    if index == 0 {
      first_term = Some(
        (
          stages.length(),
          input.name,
          seed_stage,
          seed_result,
          term_name,
          term_steps,
        ),
      )
    }
    stages.push(
      set_term_stage(
        construction,
        term_stage,
        input.name,
        seed_stage,
        seed_result,
        term_steps,
        term_result,
        output,
      ),
    )
    sources.push(term_stage)
    outputs.push(output)
  }
  let sql_inner_count = set_inner_chain_length(query)
  let sql_inner_fields = if sql_inner_count > 0 {
    let rights : Array[Array[String]] = []
    for index in 1..<(sql_inner_count + 1) {
      rights.push(outputs[index])
    }
    Some(
      set_inner_fields(
        outputs[0],
        rights,
        @query.set_part_at(query, 0).unwrap(),
      ),
    )
  } else {
    None
  }
  let first_part = @query.set_part_at(query, 0).unwrap()
  if first_part.inner_by_name {
    let ordered = match sql_inner_fields {
      Some(fields) => fields
      None => set_output_fields(outputs[0], first_part, right_fields=outputs[1])
    }
    let (matched, needed) = set_alignment_fields(
      ordered,
      outputs[0],
      true,
      allow_subset=true,
    )
    if needed {
      let (index, input, seed_stage, seed_result, term_name, steps) = first_term.unwrap()
      let steps = steps.copy()
      let result = term_name + "_ordered"
      steps.push(
        construction.object([
          ("from", construction.text(term_name)),
          ("select", set_select_fields(construction, ordered, matched)),
          ("as", construction.text(result)),
        ]),
      )
      stages[index] = set_term_stage(
        construction,
        sources[0],
        input,
        seed_stage,
        seed_result,
        steps,
        result,
        ordered,
      )
    }
    outputs[0] = ordered
  }
  let mut left_fields = outputs[0]
  let mut current_stage = sources[0]
  for index in 0..<@query.set_part_count(query) {
    let part = @query.set_part_at(query, index).unwrap()
    let right_fields = outputs[index + 1]
    let ordered = if index < sql_inner_count {
      sql_inner_fields.unwrap()
    } else {
      set_output_fields(left_fields, part, right_fields~)
    }
    let (left_matched, left_needed) = set_alignment_fields(
      ordered,
      left_fields,
      true,
      allow_subset=part.inner_by_name,
    )
    if left_needed {
      let aligned_name = prefix + "aql_set_left_" + index.to_string()
      stages.push(
        set_alignment_stage(
          construction, current_stage, aligned_name, ordered, left_matched,
        ),
      )
      current_stage = aligned_name
    }
    left_fields = ordered
    let (matched, alignment_needed) = set_alignment_fields(
      left_fields,
      right_fields,
      part.by_name,
      allow_subset=part.inner_by_name,
    )
    let aligned = left_fields.mapi((index, field) => {
      (field, construction.text(matched[index]))
    })
    let mut right_stage = sources[index + 1]
    if alignment_needed {
      let aligned_name = prefix + "aql_set_aligned_" + index.to_string()
      stages.push(
        construction.object([
          ("id", construction.text(aligned_name)),
          (
            "inputs",
            construction.object([
              (
                "r",
                construction.object([
                  (
                    "result",
                    construction.object([
                      ("stage", construction.text(right_stage)),
                      ("result", construction.text(right_stage)),
                    ]),
                  ),
                ]),
              ),
            ]),
          ),
          (
            "steps",
            construction.array([
              construction.object([
                ("from", construction.text("r")),
                (
                  "select",
                  construction.array(
                    aligned.mapi((index, entry) => {
                      if entry.0 == matched[index] {
                        entry.1
                      } else {
                        construction.object([(entry.0, entry.1)])
                      }
                    }),
                  ),
                ),
                ("as", construction.text("aligned_rows")),
              ]),
            ]),
          ),
          (
            "results",
            construction.object([
              (
                aligned_name,
                construction.object([
                  ("from", construction.text("aligned_rows")),
                  (
                    "fields",
                    construction.array(
                      left_fields.map(name => construction.text(name)),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ]),
      )
      right_stage = aligned_name
    }
    let combined = "aql_set_combined_" + index.to_string()
    let (operation, body) = set_operation_body(construction, part, "r")
    let merge_stage = prefix + "aql_set_merge_" + index.to_string()
    stages.push(
      construction.object([
        ("id", construction.text(merge_stage)),
        (
          "inputs",
          construction.object([
            (
              "l",
              construction.object([
                (
                  "result",
                  construction.object([
                    ("stage", construction.text(current_stage)),
                    ("result", construction.text(current_stage)),
                  ]),
                ),
              ]),
            ),
            (
              "r",
              construction.object([
                (
                  "result",
                  construction.object([
                    ("stage", construction.text(right_stage)),
                    ("result", construction.text(right_stage)),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
        (
          "steps",
          construction.array([
            construction.object([
              ("from", construction.text("l")),
              (operation, body),
              ("as", construction.text(combined)),
            ]),
          ]),
        ),
        (
          "results",
          construction.object([
            (
              merge_stage,
              construction.object([
                ("from", construction.text(combined)),
                (
                  "fields",
                  construction.array(
                    left_fields.map(name => construction.text(name)),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    )
    current_stage = merge_stage
    if part.kind == "union" && part.duplicates == "distinct" {
      let unique_stage = prefix + "aql_set_unique_" + index.to_string()
      stages.push(
        construction.object([
          ("id", construction.text(unique_stage)),
          (
            "inputs",
            construction.object([
              (
                "rows",
                construction.object([
                  (
                    "result",
                    construction.object([
                      ("stage", construction.text(current_stage)),
                      ("result", construction.text(current_stage)),
                    ]),
                  ),
                ]),
              ),
            ]),
          ),
          (
            "steps",
            construction.array([
              construction.object([
                ("from", construction.text("rows")),
                (
                  "distinct",
                  construction.array(
                    left_fields.map(name => construction.text(name)),
                  ),
                ),
                ("as", construction.text("unique_rows")),
              ]),
            ]),
          ),
          (
            "results",
            construction.object([
              (
                unique_stage,
                construction.object([
                  ("from", construction.text("unique_rows")),
                  (
                    "fields",
                    construction.array(
                      left_fields.map(name => construction.text(name)),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ]),
      )
      current_stage = unique_stage
    }
  }
  let steps : Array[@builder.Node] = []
  let mut current = append_set_final_steps(
    construction, query, limits, "set_rows", left_fields, steps, "",
  )
  if steps.is_empty() {
    current = "aql_set_final_0"
    steps.push(
      construction.object([
        ("from", construction.text("set_rows")),
        (
          "select",
          construction.array(left_fields.map(name => construction.text(name))),
        ),
        ("as", construction.text(current)),
      ]),
    )
  }
  let result = construction.object([
    ("from", construction.text(current)),
    (
      "fields",
      construction.array(left_fields.map(name => construction.text(name))),
    ),
  ])
  let stage = construction.object([
    ("id", construction.text(context.stage_id)),
    (
      "inputs",
      construction.object([
        (
          "set_rows",
          construction.object([
            (
              "result",
              construction.object([
                ("stage", construction.text(current_stage)),
                ("result", construction.text(current_stage)),
              ]),
            ),
          ]),
        ),
      ]),
    ),
    ("steps", construction.array(steps)),
    ("results", construction.object([(context.stage_result, result)])),
  ])
  stages.push(stage)
  (stages, left_fields)
}

///|
fn join_field(
  path : Array[@query.NamePart],
  left_qualifier : @query.NamePart,
  right_qualifier : @query.NamePart,
  left_fields : Array[String],
  right_fields : Array[String],
) -> (String, String) raise Abort {
  if path.is_empty() || path.length() > 2 {
    raise Abort(UnknownColumn)
  }
  let mut left = path.length() == 1 || same_name(path[0], left_qualifier)
  let mut right = path.length() == 1 || same_name(path[0], right_qualifier)
  if path.length() == 2 && left && right {
    raise Abort(AmbiguousRelation)
  }
  let name = path[path.length() - 1]
  let mut field : String? = None
  if left {
    for candidate in left_fields {
      if same_name(name, { value: candidate, quoted: false, }) {
        if field is Some(_) {
          raise Abort(AmbiguousColumn)
        }
        field = Some(candidate)
      }
    }
    if field is None {
      left = false
    }
  }
  let left_field = field
  field = None
  if right {
    for candidate in right_fields {
      if same_name(name, { value: candidate, quoted: false, }) {
        if field is Some(_) {
          raise Abort(AmbiguousColumn)
        }
        field = Some(candidate)
      }
    }
    if field is None {
      right = false
    }
  }
  if left && right {
    raise Abort(AmbiguousColumn)
  }
  if left {
    return ("left", left_field.unwrap())
  }
  if right {
    return ("right", field.unwrap())
  }
  raise Abort(UnknownColumn)
}

///|
fn join_projection_field(
  path : Array[@query.NamePart],
  part : @query.JoinPart,
  left_qualifier : @query.NamePart,
  right_qualifier : @query.NamePart,
  left_fields : Array[String],
  right_fields : Array[String],
) -> (String, String) raise Abort {
  if path.length() == 1 {
    for using_name in part.using_columns {
      if same_name(path[0], using_name) {
        if part.kind == "full" {
          raise Abort(UnsupportedJoin)
        }
        // INNER and LEFT USING expose one key while retaining qualified
        // access to both originals. FULL requires a coalesced output key.
        return join_field(
          [left_qualifier, using_name],
          left_qualifier,
          right_qualifier,
          left_fields,
          right_fields,
        )
      }
    }
  }
  join_field(path, left_qualifier, right_qualifier, left_fields, right_fields)
}

///|
// Resolve the same longest column prefix as append_with_properties. The
// suffix remains a common property expression, including NULL/type checking.
fn join_projection_receiver(
  path : Array[@query.NamePart],
  part : @query.JoinPart,
  left_qualifier : @query.NamePart,
  right_qualifier : @query.NamePart,
  left_fields : Array[String],
  right_fields : Array[String],
) -> (String, String, Int) raise Abort {
  let mut length = path.length()
  while length > 0 {
    let field = Some(
      join_projection_field(
        path[:length].to_owned(),
        part,
        left_qualifier,
        right_qualifier,
        left_fields,
        right_fields,
      ),
    ) catch {
      Abort(UnknownColumn) => None
      Abort(issue) => raise Abort(issue)
    }
    if field is Some((side, name)) {
      return (side, name, length)
    }
    length -= 1
  }
  raise Abort(UnknownColumn)
}

///|
fn join_keys(
  part : @query.JoinPart,
  left_qualifier : @query.NamePart,
  right_qualifier : @query.NamePart,
  left_fields : Array[String],
  right_fields : Array[String],
) -> Array[(String, String)] raise Abort {
  validate_join_using_names(part)
  let pairs : Array[(String, String)] = []
  if part.on is Some(expression) {
    let pending = [@query.expression_root(expression)]
    while pending.pop() is Some(index) {
      let node = @query.expression_node(expression, index).unwrap()
      match node.kind {
        Parenthesized(child) => pending.push(child)
        Binary("AND", left, right) => {
          pending.push(right)
          pending.push(left)
        }
        Binary("=", left, right) => {
          guard join_key_reference(expression, left) is Some(left_path) &&
            join_key_reference(expression, right) is Some(right_path) else {
            raise Abort(UnsupportedJoin)
          }
          let a = join_field(
            left_path, left_qualifier, right_qualifier, left_fields, right_fields,
          )
          let b = join_field(
            right_path, left_qualifier, right_qualifier, left_fields, right_fields,
          )
          if a.0 == "left" && b.0 == "right" {
            pairs.push((a.1, b.1))
          } else if a.0 == "right" && b.0 == "left" {
            pairs.push((b.1, a.1))
          } else {
            raise Abort(UnsupportedJoin)
          }
        }
        _ => raise Abort(UnsupportedJoin)
      }
    }
  } else {
    for name in part.using_columns {
      let left = join_field(
        [left_qualifier, name],
        left_qualifier,
        right_qualifier,
        left_fields,
        right_fields,
      )
      let right = join_field(
        [right_qualifier, name],
        left_qualifier,
        right_qualifier,
        left_fields,
        right_fields,
      )
      pairs.push((left.1, right.1))
    }
  }
  if pairs.is_empty() && part.kind != "cross" {
    raise Abort(UnsupportedJoin)
  }
  pairs
}

///|
fn join_values_rows(input : Input) -> Int raise Abort {
  guard input.source is GeneratedValues(step) else {
    raise Abort(UnsupportedJoin)
  }
  let step = match @wire.open_object(step) {
    Ok(value) => value
    Err(_) => raise Abort(InvalidContext)
  }
  let values = match @wire.lookup(step, "values") {
    Some(value) => value
    None => raise Abort(InvalidContext)
  }
  let values = match @wire.open_object(values) {
    Ok(value) => value
    Err(_) => raise Abort(InvalidContext)
  }
  let rows = match @wire.lookup(values, "rows") {
    Some(value) => value
    None => raise Abort(InvalidContext)
  }
  match @wire.elements(rows) {
    Ok(value) => value.length()
    Err(_) => raise Abort(InvalidContext)
  }
}

///|
// Preserve the existing Values-specific bound before the shared binder turns
// the original input into a StepReference. Unknown sources retain their own
// existing authored/default admission path.
fn values_join_output_bound(
  part : @query.JoinPart,
  left : Input,
  right : Input,
  limits : Limits,
) -> Int64 raise Abort {
  if part.max_output_rows is Some(_) {
    authored_join_bound(part, limits)
  } else {
    let left_rows = join_values_rows(left).to_int64()
    let right_rows = join_values_rows(right).to_int64()
    let factor = if part.kind == "inner" || part.kind == "cross" {
      right_rows
    } else if right_rows == 0L {
      1L
    } else {
      right_rows
    }
    let extra = if part.kind == "full" { right_rows } else { 0L }
    if extra > 9007199254740991L ||
      (factor != 0L && left_rows > (9007199254740991L - extra) / factor) {
      raise Abort(UnsupportedJoin)
    }
    let raw_bound = left_rows * factor + extra
    let bound = if raw_bound == 0L { 1L } else { raw_bound }
    if limits.max_join_output_rows < 1L || bound > limits.max_join_output_rows {
      raise Abort(UnsupportedJoin)
    }
    bound
  }
}

///|
fn join_seed_stage(
  construction : Construction,
  input : Input,
  fields : Array[String],
  stage_name : String,
  query : @query.Query,
  filter : @query.Expression?,
  max_work : Int,
) -> @builder.Node raise Abort {
  guard input.source is GeneratedValues(step) else {
    raise Abort(UnsupportedJoin)
  }
  let seed = match
    @builder.import_cursor(construction.builder, step, construction.generated) {
    Ok(value) => value
    Err(issue) => raise Abort(Construction(issue))
  }
  let steps = [seed]
  let mut result_from = input.name
  match filter {
    Some(expression) => {
      steps.push(
        construction.object([
          ("from", construction.text(result_from)),
          (
            "filter",
            append_expression(
              construction, expression, query, input, fields, max_work,
            ),
          ),
          ("as", construction.text("aql_join_prefiltered")),
        ]),
      )
      result_from = "aql_join_prefiltered"
    }
    None => ()
  }
  construction.object([
    ("id", construction.text(stage_name)),
    ("inputs", construction.object([])),
    ("steps", construction.array(steps)),
    (
      "results",
      construction.object([
        (
          stage_name,
          construction.object([
            ("from", construction.text(result_from)),
            (
              "fields",
              construction.array(fields.map(field => construction.text(field))),
            ),
          ]),
        ),
      ]),
    ),
  ])
}

///|
// Helper allocation follows expression preorder, independently of the
// parser's node storage order.
fn join_reference_paths(
  expression : @query.Expression,
) -> Array[Array[@query.NamePart]] {
  let paths : Array[Array[@query.NamePart]] = []
  let pending = [@query.expression_root(expression)]
  while pending.pop() is Some(index) {
    match @query.expression_node(expression, index).unwrap().kind {
      Reference(path) => paths.push(path)
      Parenthesized(child)
      | Unary(_, child)
      | Cast(child, _)
      | Interval(child, _)
      | Property(child, _) => pending.push(child)
      Binary(_, left, right) | ArrayOffset(left, right, _) => {
        pending.push(right)
        pending.push(left)
      }
      StructConstructor(fields) => {
        let mut next = fields.length() - 1
        while next >= 0 {
          pending.push(fields[next].1)
          next -= 1
        }
      }
      Call(_, args) | Predicate(_, args) | ArrayConstructor(args, _) => {
        let mut next = args.length() - 1
        while next >= 0 {
          pending.push(args[next])
          next -= 1
        }
      }
      SearchedCase(branches, otherwise) => {
        pending.push(otherwise)
        let mut next = branches.length() - 1
        while next >= 0 {
          pending.push(branches[next].1)
          pending.push(branches[next].0)
          next -= 1
        }
      }
      _ => ()
    }
  }
  paths
}

///|
// Both source-free and Stage Result joins use this projection boundary. A
// predicate sees matched rows before SELECT, while selected expressions are
// evaluated once and private inputs are removed from the published Result.
fn joined_projection(
  construction : Construction,
  projections : Array[@query.Projection],
  order_expressions : Array[(String, @query.Expression)],
  predicate : @query.Expression?,
  part : @query.JoinPart,
  left_qualifier : @query.NamePart,
  right_qualifier : @query.NamePart,
  left_fields : Array[String],
  right_fields : Array[String],
  max_work : Int,
  step_bindings? : Map[String, String] = Map([]),
) -> (
  Array[(String, @builder.Node)],
  Array[@builder.Node],
  Array[String],
  String,
) raise Abort {
  let select : Array[(String, @builder.Node)] = []
  let output : Array[String] = []
  let mut private_projection = predicate is Some(_) ||
    !order_expressions.is_empty()
  for projection in projections {
    guard projection.expression is Some(expression) &&
      projection.aggregate is None &&
      projection.analytic is None else {
      raise Abort(UnsupportedJoin)
    }
    let reference = match
      @query.expression_node(expression, @query.expression_root(expression)) {
      Some({ kind: Reference(path), .. }) => Some(path)
      _ => None
    }
    let name = match projection.name {
      Some(value) => value.value
      None =>
        match
          @query.expression_node(expression, @query.expression_root(expression)).unwrap().kind {
          Reference(path) => path.last().unwrap().value
          Property(_, name) => name.value
          _ => raise Abort(UnsupportedJoin)
        }
    }
    if output.any(field => ascii_upper(field) == ascii_upper(name)) {
      raise Abort(DuplicateOutput)
    }
    output.push(name)
    match reference {
      Some(path) => {
        let resolved = join_projection_receiver(
          path, part, left_qualifier, right_qualifier, left_fields, right_fields,
        )
        if resolved.2 == path.length() {
          select.push((name, construction.text(resolved.0 + "." + resolved.1)))
        } else {
          private_projection = true
        }
      }
      None => private_projection = true
    }
  }
  if output.is_empty() {
    raise Abort(UnsupportedJoin)
  }
  let tail : Array[@builder.Node] = []
  if !private_projection {
    return (
      select,
      tail,
      output,
      join_step_binding(step_bindings, "aql_join_output"),
    )
  }
  select.clear()
  let required : Array[(String, String)] = []
  for projection in projections {
    for path in join_reference_paths(projection.expression.unwrap()) {
      let receiver = join_projection_receiver(
        path, part, left_qualifier, right_qualifier, left_fields, right_fields,
      )
      let field = (receiver.0, receiver.1)
      if !required.contains(field) {
        required.push(field)
      }
    }
  }
  match predicate {
    Some(expression) =>
      for path in join_reference_paths(expression) {
        let receiver = join_projection_receiver(
          path, part, left_qualifier, right_qualifier, left_fields, right_fields,
        )
        let field = (receiver.0, receiver.1)
        if !required.contains(field) {
          required.push(field)
        }
      }
    None => ()
  }
  let aliases = output.map(name => (name, name))
  for (_, expression) in order_expressions {
    for path in join_reference_paths(expression) {
      // ORDER resolves aliases at each candidate receiver prefix. Retain an
      // input only if that prefix wins; never recover an alias-shadowed input.
      let mut length = path.length()
      while length > 0 {
        let prefix = path[:length].to_owned()
        if order_output_slot(prefix, aliases) is Some(_) {
          break
        }
        let field = Some(
          join_projection_field(
            prefix, part, left_qualifier, right_qualifier, left_fields, right_fields,
          ),
        ) catch {
          Abort(UnknownColumn) => None
          Abort(issue) => raise Abort(issue)
        }
        if field is Some(field) {
          if !required.contains(field) {
            required.push(field)
          }
          break
        }
        length -= 1
        if length == 0 {
          raise Abort(UnknownColumn)
        }
      }
    }
  }
  if required.is_empty() {
    if left_fields.is_empty() {
      raise Abort(UnsupportedJoin)
    }
    required.push(("left", left_fields[0]))
  }
  let reserved = output +
    order_expressions.map(pair => pair.0) +
    left_fields +
    right_fields
  let slots : Array[(String, String, String)] = []
  for field in required {
    let slot = pipe_physical_name(reserved, "aql_join_input_")
    reserved.push(slot)
    slots.push((field.0, field.1, slot))
    select.push((slot, construction.text(field.0 + "." + field.1)))
  }
  let resolve = fn(path : Array[@query.NamePart]) -> String? {
    let selected = Some(
      join_projection_field(
        path, part, left_qualifier, right_qualifier, left_fields, right_fields,
      ),
    ) catch {
      Abort(_) => None
    }
    match selected {
      Some(field) => {
        for slot in slots {
          if slot.0 == field.0 && slot.1 == field.1 {
            return Some(slot.2)
          }
        }
        None
      }
      None => None
    }
  }
  let mut from = join_step_binding(step_bindings, "aql_join_raw")
  match predicate {
    Some(expression) => {
      let filter = match
        @expression.append_with_properties(
          expression,
          resolve,
          construction.builder,
          max_work,
          resolve_parameter=construction.parameter_resolver(),
        ) {
        Ok(value) => value
        Err(error) => raise Abort(Expression(error))
      }
      tail.push(
        construction.object([
          ("from", construction.text(from)),
          ("filter", filter),
          (
            "as",
            construction.text(
              join_step_binding(step_bindings, "aql_join_filtered"),
            ),
          ),
        ]),
      )
      from = join_step_binding(step_bindings, "aql_join_filtered")
    }
    None => ()
  }
  let derivations : Array[(String, @builder.Node)] = []
  let final_select : Array[@builder.Node] = []
  let output_slots : Array[(String, String)] = []
  for index in 0..<projections.length() {
    let expression = projections[index].expression.unwrap()
    let name = output[index]
    let direct_slot = match
      @query.expression_node(expression, @query.expression_root(expression)) {
      Some({ kind: Reference(path), .. }) => resolve(path)
      _ => None
    }
    match direct_slot {
      Some(slot) => {
        final_select.push(
          construction.object([(name, construction.text(slot))]),
        )
        output_slots.push((name, slot))
      }
      _ => {
        let value = match
          @expression.append_with_properties(
            expression,
            resolve,
            construction.builder,
            max_work,
            resolve_parameter=construction.parameter_resolver(),
          ) {
          Ok(value) => value
          Err(error) => raise Abort(Expression(error))
        }
        derivations.push((name, value))
        final_select.push(construction.text(name))
        output_slots.push((name, name))
      }
    }
  }
  if !derivations.is_empty() {
    tail.push(
      construction.object([
        ("from", construction.text(from)),
        ("derive", construction.object(derivations)),
        (
          "as",
          construction.text(
            join_step_binding(step_bindings, "aql_join_derived"),
          ),
        ),
      ]),
    )
    from = join_step_binding(step_bindings, "aql_join_derived")
  }
  let order_derivations : Array[(String, @builder.Node)] = []
  for (name, expression) in order_expressions {
    let value = match
      @expression.append_with_properties(
        expression,
        path => {
          match order_output_slot(path, output_slots) {
            Some(slot) => Some(slot)
            None => resolve(path)
          }
        },
        construction.builder,
        max_work,
        resolve_parameter=construction.parameter_resolver(),
      ) {
      Ok(value) => value
      Err(error) => raise Abort(Expression(error))
    }
    order_derivations.push((name, value))
    final_select.push(construction.text(name))
    output.push(name)
  }
  if !order_derivations.is_empty() {
    tail.push(
      construction.object([
        ("from", construction.text(from)),
        ("derive", construction.object(order_derivations)),
        (
          "as",
          construction.text(
            join_step_binding(step_bindings, "aql_join_order_derived"),
          ),
        ),
      ]),
    )
    from = join_step_binding(step_bindings, "aql_join_order_derived")
  }
  tail.push(
    construction.object([
      ("from", construction.text(from)),
      ("select", construction.array(final_select)),
      (
        "as",
        construction.text(join_step_binding(step_bindings, "aql_join_output")),
      ),
    ]),
  )
  (select, tail, output, join_step_binding(step_bindings, "aql_join_raw"))
}

///|
// Final ORDER resolves a SELECT alias before an input name. A selected
// expression reuses its one computed slot; other expressions are carried in
// private slots until sorting finishes and never enter DISTINCT or Result.
fn join_order_projection(
  query : @query.Query,
  projections : Array[@query.Projection],
  distinct : Bool,
  select_index : Int,
  part : @query.JoinPart,
  left_qualifier : @query.NamePart,
  right_qualifier : @query.NamePart,
  left_fields : Array[String],
  right_fields : Array[String],
) -> (
  Array[@query.Projection],
  Array[String],
  Array[(String, String, String)],
  Array[(String, @query.Expression)],
  Int,
) raise Abort {
  let visible_names : Array[String] = []
  for projection in projections {
    let name = match projection.name {
      Some(name) => name.value
      None =>
        match projection.expression {
          Some(expression) =>
            match
              @query.expression_node(
                expression,
                @query.expression_root(expression),
              ).unwrap().kind {
              Reference(path) => path.last().unwrap().value
              Property(_, name) => name.value
              _ => raise Abort(UnsupportedJoin)
            }
          None => raise Abort(UnsupportedJoin)
        }
    }
    if visible_names.any(prior => ascii_upper(prior) == ascii_upper(name)) {
      raise Abort(DuplicateOutput)
    }
    visible_names.push(name)
  }
  let selected_expressions : Array[(@query.Expression, String)] = []
  let aliases : Array[(String, String)] = []
  let input_slot = fn(path : Array[@query.NamePart]) -> String? {
    let resolved = Some(
      join_projection_field(
        path, part, left_qualifier, right_qualifier, left_fields, right_fields,
      ),
    ) catch {
      Abort(_) => None
    }
    resolved.map(field => field.0 + "." + field.1)
  }
  for index in 0..<projections.length() {
    let expression = projections[index].expression.unwrap()
    selected_expressions.push((expression, visible_names[index]))
    let identity = match
      @query.expression_node(expression, @query.expression_root(expression)).unwrap().kind {
      Reference(path) =>
        input_slot(path).unwrap_or("projection:" + index.to_string())
      _ => "projection:" + index.to_string()
    }
    aliases.push((visible_names[index], identity))
  }
  let order_expressions : Array[(String, @query.Expression)] = []
  let order_fields : Array[(String, String, String)] = []
  let mut next = select_index + 1
  match @query.operation_at(query, next) {
    Some(Order(terms)) => {
      let reserved = visible_names + left_fields + right_fields
      for term in terms {
        let expression = term.expression
        let mut selected = order_ordinal_column(expression, visible_names)
        match
          @query.expression_node(expression, @query.expression_root(expression)).unwrap().kind {
          Reference(path) if path.length() == 1 =>
            for name in visible_names {
              if same_name(path[0], { value: name, quoted: false, }) {
                selected = Some(name)
              }
            }
          _ => ()
        }
        if selected is None {
          selected = reusable_order_expression(
            expression, selected_expressions, aliases, input_slot,
          )
        }
        if selected is None {
          if distinct {
            raise Abort(UnsupportedOrdering)
          }
          for (name, value) in order_expressions {
            if same_expression(expression, value) {
              selected = Some(name)
            }
          }
          if selected is None {
            let hidden = pipe_physical_name(reserved, "aql_join_sort_")
            reserved.push(hidden)
            order_expressions.push((hidden, expression))
            selected = Some(hidden)
          }
        }
        order_fields.push((selected.unwrap(), term.direction, term.nulls))
      }
      next += 1
    }
    _ => ()
  }
  (projections, visible_names, order_fields, order_expressions, next)
}

///|
fn join_continuation_context(
  query : @query.Query,
  limits : Limits,
  retained : Array[RetainedResult]?,
) -> (Limits, Array[RetainedResult])? {
  if retained is Some(results) {
    Some((limits, results))
  } else if !has_retained_result(query) {
    // A pure Pipe tail needs the existing lowering limits, not a RESULT tap.
    // A caller that cannot export retained Results keeps that refusal.
    Some((limits, []))
  } else {
    None
  }
}

///|
fn append_join_order_steps(
  construction : Construction,
  query : @query.Query,
  steps : Array[@builder.Node],
  order_fields : Array[(String, String, String)],
  visible_names : Array[String],
  projected_count : Int,
  initial_from : String,
  next_operation : Int,
  result_tail? : (Limits, Array[RetainedResult])? = None,
  step_bindings? : Map[String, String] = Map([]),
  prefix_steps? : Array[@builder.Node] = [],
  reserved_bindings? : Array[String] = [],
  checked_infer_prefix? : ((
    Array[@builder.Node],
    String,
    InferInputLabels,
    Array[(String, String)],
  ) -> InferPrefixProjection raise Abort)? = None,
  checked_nearest_prefix? : ((Array[@builder.Node]) -> @pipeline.CheckedPipeline raise Abort)? = None,
) -> String raise Abort {
  let mut result_from = initial_from
  if !order_fields.is_empty() {
    let order : Array[@builder.Node] = []
    for (field, direction, nulls) in order_fields {
      order.push(
        construction.object([
          ("field", construction.text(field)),
          ("dir", construction.text(direction)),
          ("nulls", construction.text(nulls)),
        ]),
      )
    }
    steps.push(
      construction.object([
        ("from", construction.text(result_from)),
        ("sort", construction.array(order)),
        (
          "as",
          construction.text(join_step_binding(step_bindings, "aql_join_sorted")),
        ),
      ]),
    )
    result_from = join_step_binding(step_bindings, "aql_join_sorted")
  }
  let mut next = next_operation
  match @query.operation_at(query, next) {
    Some(Limit(count, offset)) => {
      steps.push(
        construction.object([
          ("from", construction.text(result_from)),
          (
            "take",
            construction.object([
              ("count", lower_query_integer(construction, count)),
              ("offset", lower_query_integer(construction, offset)),
            ]),
          ),
          (
            "as",
            construction.text(
              join_step_binding(step_bindings, "aql_join_taken"),
            ),
          ),
        ]),
      )
      result_from = join_step_binding(step_bindings, "aql_join_taken")
      next += 1
    }
    _ => ()
  }
  if projected_count != visible_names.length() {
    steps.push(
      construction.object([
        ("from", construction.text(result_from)),
        (
          "select",
          construction.array(visible_names.map(name => construction.text(name))),
        ),
        (
          "as",
          construction.text(
            join_step_binding(step_bindings, "aql_join_visible"),
          ),
        ),
      ]),
    )
    result_from = join_step_binding(step_bindings, "aql_join_visible")
  }
  if next != @query.operation_count(query) {
    guard result_tail is Some((limits, retained)) else {
      raise Abort(UnsupportedJoin)
    }
    // The JOIN projection is already evaluated. Continue from its actual
    // output using the shared Pipe lowerer; do not recover operand ranges
    // or expand SELECT expressions a second time.
    let input : Input = {
      relation: @query.relation(query),
      name: result_from,
      source: StageResult("unused", "unused"),
      visible_fields: visible_names,
      graph_bindings: [],
    }
    let (tail, output) = compile_steps(
      construction,
      query,
      input,
      visible_names,
      limits.max_expression_work,
      limits,
      limits.max_collection_items,
      limits.max_collection_bytes,
      next,
      false,
      join_step_binding(step_bindings, "aql_join_result"),
      retained=Some(retained),
      projected_input=true,
      prefix_steps=prefix_steps + steps,
      reserved_bindings~,
      checked_infer_prefix~,
      checked_nearest_prefix~,
    )
    if output != visible_names {
      // Caller output is shared so that the public Result definition follows
      // the continuing Pipe's final columns, not the initial JOIN schema.
      visible_names.clear()
      visible_names.append(output)
    }
    steps.append(tail)
    result_from = join_step_binding(step_bindings, "aql_join_result")
  }
  result_from
}

///|
fn compile_join_query(
  query : @query.Query,
  context : Context,
  limits : Limits,
) -> Result[(@program.Program, @builder.Source), Issue] {
  if @query.join_part_count(query) == 1 {
    validate_join_using_names(@query.join_part_at(query, 0).unwrap()) catch {
      Abort(issue) => return Err(issue)
    }
  }
  if @query.join_part_count(query) != 1 ||
    @query.operation_count(query) < 1 ||
    context.captured_stage is Some(_) ||
    context.program_id == "" ||
    context.stage_id == "" ||
    context.stage_result == "" ||
    context.result_name == "" {
    return Err(UnsupportedJoin)
  }
  let document = @query.query_document(query)
  let generated = @origin.range(document, 0, 0, kind=Generated).unwrap()
  let builder = match @builder.create(document, limits.source) {
    Ok(value) => value
    Err(issue) => return Err(Construction(issue))
  }
  let parameter_names = query_parameter_names(
    context.parameter_declarations,
    limits.max_expression_work,
  ) catch {
    Abort(issue) => {
      @builder.discard(builder)
      return Err(issue)
    }
  }
  let construction : Construction = {
    builder,
    generated,
    model_tasks: context.model_tasks,
    parameter_names,
    infer_labels: query_has_omitted_infer(query),
    infer_budget: { remaining_work: limits.max_expression_work, },
  }
  try {
    let part = @query.join_part_at(query, 0).unwrap()
    // FULL uses the shared row scope, which preserves input identity premises
    // for the common checker. It cannot use this projection specialization.
    if part.kind == "full" {
      raise Abort(UnsupportedJoin)
    }
    let left = selected_input(query, context, limits)
    let right = selected_join_input(query, part, context, limits)
    let left_fields = columns(left)
    let right_fields = columns(right)
    if context.captured_stage is Some(_) {
      // Installed inputs stay in the original JOIN Stage. In particular a
      // correlated right Source must not be turned into a Direct capture
      // Stage before its checked resource/version keys exist. Common Program
      // checking still resolves and admits both acquisition declarations.
      guard left.source is Captured(left_declaration) &&
        right.source is Captured(right_declaration) &&
        left.name != right.name else {
        raise Abort(UnsupportedJoin)
      }
      let declarations = [
        (left.name, import_query_cursor(construction, left_declaration)),
        (right.name, import_query_cursor(construction, right_declaration)),
      ]
      let infer_budget = construction.infer_budget
      let retained : Array[RetainedResult] = []
      let (steps, output, from) = compile_join_steps(
        construction,
        query,
        @query.relation(query).last().unwrap(),
        left_fields,
        part.relation.last().unwrap(),
        right_fields,
        limits,
        retained=Some(retained),
        left_from=left.name,
        right_from=right.name,
        capture_left=true,
        checked_infer_prefix=Some((nodes, producer, visible, authored_aliases) => {
          infer_prefix_check(
            construction,
            query,
            context,
            [],
            declarations,
            nodes,
            producer,
            limits,
            infer_budget,
            visible,
            authored_aliases,
          )
        }),
      )
      let stage = construction.object([
        ("id", construction.text(context.stage_id)),
        ("inputs", construction.object(declarations)),
        ("steps", construction.array(steps)),
        (
          "results",
          retained_stage_results(
            construction,
            context.stage_result,
            construction.object([
              ("from", construction.text(from)),
              (
                "fields",
                construction.array(
                  output.map(field => construction.text(field)),
                ),
              ),
            ]),
            retained,
          ),
        ),
      ])
      let root = program_root(
        construction,
        context,
        [stage],
        result_exports=retained_result_exports(context, retained),
      )
      let source = match @builder.finish(builder, root) {
        Ok(value) => value
        Err(issue) => raise Abort(Construction(issue))
      }
      return admit_query_source(source, document, context, limits)
    }
    let left_qualifier = @query.relation_alias(query).unwrap_or(
      @query.relation(query).last().unwrap(),
    )
    let right_qualifier = part.source_alias.unwrap_or(
      part.relation.last().unwrap(),
    )
    if same_name(left_qualifier, right_qualifier) {
      raise Abort(AmbiguousRelation)
    }
    let keys = join_keys(
      part, left_qualifier, right_qualifier, left_fields, right_fields,
    )
    let predicate = match @query.operation_at(query, 0) {
      Some(Where(expression)) => Some(expression)
      _ => None
    }
    let select_index = if predicate is Some(_) { 1 } else { 0 }
    guard @query.operation_at(query, select_index)
      is Some(Select(projections, distinct)) else {
      raise Abort(UnsupportedJoin)
    }
    let (projected, visible_names, order_fields, order_expressions, next) = join_order_projection(
      query, projections, distinct, select_index, part, left_qualifier, right_qualifier,
      left_fields, right_fields,
    )
    let (select, computed_steps, output, joined) = joined_projection(
      construction,
      projected,
      order_expressions,
      predicate,
      part,
      left_qualifier,
      right_qualifier,
      left_fields,
      right_fields,
      limits.max_expression_work,
    )
    if distinct {
      computed_steps.push(
        construction.object([
          ("from", construction.text("aql_join_output")),
          (
            "distinct",
            construction.array(output.map(name => construction.text(name))),
          ),
          ("as", construction.text("aql_join_unique")),
        ]),
      )
    }
    let bound = values_join_output_bound(part, left, right, limits)
    let left_stage = "aql_join_left"
    let right_stage = "aql_join_right"
    let operation = if part.kind == "cross" {
      (
        "cross_join",
        construction.object([
          ("with", construction.text("r")),
          ("max_output_rows", construction.add(Number(bound.to_double()))),
          ("select", construction.object(select)),
        ]),
      )
    } else {
      (
        "join",
        construction.object([
          ("with", construction.text("r")),
          ("kind", construction.text(part.kind)),
          (
            "on",
            construction.array(
              keys.map(pair => {
                construction.object([
                  ("left", construction.text(pair.0)),
                  ("right", construction.text(pair.1)),
                ])
              }),
            ),
          ),
          ("max_output_rows", construction.add(Number(bound.to_double()))),
          ("select", construction.object(select)),
        ]),
      )
    }
    let declarations = [
      (
        "l",
        construction.object([
          (
            "result",
            construction.object([
              ("stage", construction.text(left_stage)),
              ("result", construction.text(left_stage)),
            ]),
          ),
        ]),
      ),
      (
        "r",
        construction.object([
          (
            "result",
            construction.object([
              ("stage", construction.text(right_stage)),
              ("result", construction.text(right_stage)),
            ]),
          ),
        ]),
      ),
    ]
    let prior_stages = [
      join_seed_stage(
        construction,
        left,
        left_fields,
        left_stage,
        query,
        part.pre_join_filter,
        limits.max_expression_work,
      ),
      join_seed_stage(
        construction,
        right,
        right_fields,
        right_stage,
        query,
        None,
        limits.max_expression_work,
      ),
    ]
    let initial = [
      construction.object([
        ("from", construction.text("l")),
        operation,
        ("as", construction.text(joined)),
      ]),
    ]
    let infer_budget = construction.infer_budget
    let retained : Array[RetainedResult] = []
    let result_from = append_join_order_steps(
      construction,
      query,
      computed_steps,
      order_fields,
      visible_names,
      output.length(),
      if distinct {
        "aql_join_unique"
      } else {
        "aql_join_output"
      },
      next,
      result_tail=Some((limits, retained)),
      prefix_steps=initial,
      checked_infer_prefix=Some((nodes, producer, visible, authored_aliases) => {
        infer_prefix_check(
          construction, query, context, prior_stages, declarations, nodes, producer,
          limits, infer_budget, visible, authored_aliases,
        )
      }),
    )
    let stage = construction.object([
      ("id", construction.text(context.stage_id)),
      ("inputs", construction.object(declarations)),
      ("steps", construction.array(initial + computed_steps)),
      (
        "results",
        retained_stage_results(
          construction,
          context.stage_result,
          construction.object([
            ("from", construction.text(result_from)),
            (
              "fields",
              construction.array(
                visible_names.map(name => construction.text(name)),
              ),
            ),
          ]),
          retained,
        ),
      ),
    ])
    let root = program_root(
      construction,
      context,
      prior_stages + [stage],
      result_exports=retained_result_exports(context, retained),
    )
    let source = match @builder.finish(builder, root) {
      Ok(value) => value
      Err(issue) => raise Abort(Construction(issue))
    }
    admit_query_source(source, document, context, limits)
  } catch {
    Abort(issue) => {
      @builder.discard(builder)
      Err(issue)
    }
  }
}

///|
fn authored_join_bound(
  part : @query.JoinPart,
  limits : Limits,
) -> Int64 raise Abort {
  let bound = part.max_output_rows.unwrap_or(limits.max_join_output_rows)
  if bound < 1L ||
    bound > 9007199254740991L ||
    bound > limits.max_join_output_rows {
    raise Abort(UnsupportedJoin)
  }
  bound
}

///|
/// Ordinary compilation retains only the admitted Program. Diagnostic source
/// annotations do not become part of its runtime retention or identity.
pub fn compile(
  query : @query.Query,
  context : Context,
  limits : Limits,
  table_writes? : Array[TableWriteBinding] = [],
  update_targets? : UpdateTargetPublication? = None,
  store_targets? : StoreTargetPublication? = None,
  command_targets? : CommandTargetPublication? = None,
) -> Result[@program.Program, Issue] {
  compile_with_source(
    query,
    context,
    limits,
    table_writes~,
    update_targets~,
    store_targets~,
    command_targets~,
  )
  .map(pair => pair.0)
  .map_err(issue_without_source)
}
