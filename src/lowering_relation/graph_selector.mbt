///|
fn emit_graph_selector(
  selector : @graph.CheckedSelector,
  predicate : Expression?,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  match @graph.selector_form(selector) {
    @graph.ExplicitIds => {
      @encode.key(out, "ids")
      @encode.begin_array(out)
      for index in 0..<@graph.selector_id_count(selector) {
        emit_wire_value(
          @graph.selector_id_at(selector, index).unwrap().value,
          out,
        )
      }
      @encode.end_array(out)
    }
    @graph.RelationIds(field~, ..) => {
      @encode.key(out, "input_port")
      @encode.number_value(out, 1.0)
      @encode.key(out, "id")
      @encode.string_value(out, @schema.reference_name(field))
    }
    @graph.PredicateNodes => {
      guard predicate is Some(expression) else {
        abort("missing prepared graph selector predicate")
      }
      @encode.key(out, "where")
      emit_expression(expression, out)
    }
  }
  @encode.end_object(out)
}
