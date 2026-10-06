///|
/// Keep operation Parameters in the ordinary take slots. Their declarations,
/// bound values, integer domain and stable input order are checked by the
/// existing Program owners, not inferred or evaluated by the Frontend.
fn lower_query_integer(
  construction : Construction,
  value : @query.QueryInteger,
) -> @builder.Node raise Abort {
  match value {
    Integer(value) => construction.add(Number(value.to_double()))
    BoundParameter(name) =>
      construction.object([("$param", construction.text(name))])
  }
}
