///|
// One closed private input feeds one ordinary store Effect. Sparse fields must
// not pass through a hidden Named Result or be filled with NULL.
fn lower_table_effect(
  construction : Construction,
  clause : @query.TableEffectClause,
  binding : TableWriteBinding,
  input_name : String,
) -> @builder.Node raise Abort {
  let expected = match binding.action {
    Create => construction.add(@builder.Null)
    Replace(uuid, generation) =>
      construction.object([
        ("table_uuid", construction.text(uuid)),
        ("generation_cid", construction.text(generation)),
      ])
  }
  let selected = match binding.action {
    Create => "create"
    Replace(_, _) => "replace"
  }
  // This script has one terminal query. Its generated operation name belongs
  // to that fixed Program definition, not the Table name or a source location.
  let name = clause.name.map(part => part.value).unwrap_or("aql_table_effect")
  construction.object([
    (
      name,
      construction.object([
        (
          "store",
          construction.object([
            ("target", construction.text(binding.target_ref)),
            ("mapping", construction.text(binding.mapping_ref)),
            (
              "from",
              construction.object([
                ("table_input", construction.text(input_name)),
              ]),
            ),
            (
              "table_write",
              construction.object([
                (
                  "intent",
                  construction.text(
                    if clause.allow_replace {
                      "create_or_replace"
                    } else {
                      "create"
                    },
                  ),
                ),
                ("action", construction.text(selected)),
                ("expected_table", expected),
                ("mapping_cid", construction.text(binding.mapping_cid)),
                ("capability_cid", construction.text(binding.capability_cid)),
                (
                  "installation_binding_cid",
                  construction.text(binding.installation_binding_cid),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    ),
  ])
}
