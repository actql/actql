///|
// Exact submitted fixture sources and declarations are copied from authored
// fixtures; no product output supplies these tests or their independent rows.
// This checks public frontend admission/static bindings only, not Host I/O.

///|
test "WITH public expansion unpivot-multicolumn-data-from-exclude" {
  let declarations = @parameters.read_declarations(
    Some(
      from_unpivot_public_cursor(
        "{\"rows\":{\"type\":\"array\",\"nullable\":false,\"max_items\":3,\"items\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"jan_amount\":{\"type\":\"number\",\"nullable\":true},\"jan_note\":{\"type\":\"string\",\"nullable\":true},\"feb_amount\":{\"type\":\"number\",\"nullable\":true},\"feb_note\":{\"type\":\"string\",\"nullable\":true}}}}}",
      ),
    ),
    {
      max_parameters: 10,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    },
  ).unwrap()
  let context = {
    ..fixture_context(),
    inputs: [],
    parameter_declarations: Some(declarations),
  }
  let lowered = @frontend.lower(
    "WITH wide AS (SELECT item.id AS id,item.jan_amount AS jan_amount,item.jan_note AS jan_note,item.feb_amount AS feb_amount,item.feb_note AS feb_note FROM UNNEST(@rows) item) SELECT id,amount,note,month FROM wide UNPIVOT ((amount,note) FOR month IN ((jan_amount,jan_note) AS 'Jan',(feb_amount,feb_note) AS 'Feb')) ORDER BY id,month",
    Text,
    Some(context),
  ).unwrap()
  assert_true(lowered.program is Some(_))
}

///|
test "WITH public expansion unnest-scalar-star-data-binding" {
  let declarations = @parameters.read_declarations(
    Some(
      from_unpivot_public_cursor(
        "{\"items\":{\"type\":\"array\",\"nullable\":true,\"max_items\":3,\"items\":{\"type\":\"number\",\"nullable\":true}}}",
      ),
    ),
    {
      max_parameters: 10,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    },
  ).unwrap()
  let context = {
    ..fixture_context(),
    inputs: [],
    parameter_declarations: Some(declarations),
  }
  let lowered = @frontend.lower(
    "WITH expanded AS (FROM UNNEST(@items) element WITH OFFSET position |> SELECT *) FROM expanded |> ORDER BY position |> RESULT answer",
    Text,
    Some(context),
  ).unwrap()
  assert_true(lowered.program is Some(_))
}

///|
test "WITH public expansion unnest-struct-data-binding" {
  let declarations = @parameters.read_declarations(
    Some(
      from_unpivot_public_cursor(
        "{\"items\":{\"type\":\"array\",\"nullable\":true,\"max_items\":3,\"items\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"label\":{\"type\":\"string\",\"nullable\":true}}}}}",
      ),
    ),
    {
      max_parameters: 10,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    },
  ).unwrap()
  let context = {
    ..fixture_context(),
    inputs: [],
    parameter_declarations: Some(declarations),
  }
  let lowered = @frontend.lower(
    "WITH expanded AS (FROM UNNEST(@items) element WITH OFFSET position |> SELECT *) FROM expanded |> ORDER BY position |> RESULT answer",
    Text,
    Some(context),
  ).unwrap()
  assert_true(lowered.program is Some(_))
}

///|
test "WITH public expansion unnest-join-full" {
  let declarations = @parameters.read_declarations(
    Some(
      from_unpivot_public_cursor(
        "{\"items\":{\"type\":\"array\",\"nullable\":true,\"max_items\":3,\"items\":{\"type\":\"number\",\"nullable\":true}}}",
      ),
    ),
    {
      max_parameters: 10,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    },
  ).unwrap()
  let context = {
    ..fixture_context(),
    inputs: [],
    parameter_declarations: Some(declarations),
  }
  let lowered = @frontend.lower(
    "WITH keys AS (FROM (SELECT 2 AS key UNION ALL SELECT 3 AS key) keys_input |> ASSERT UNIQUE BY (key)) FROM UNNEST(@items) element WITH OFFSET position |> ASSERT UNIQUE BY (position) |> FULL JOIN keys k ON element = k.key MAX_OUTPUT_ROWS 10 |> SELECT element, position, k.key |> ORDER BY position NULLS LAST, k.key",
    Text,
    Some(context),
  ).unwrap()
  assert_true(lowered.program is Some(_))
}

///|
test "WITH public expansion unnest-join-data" {
  let declarations = @parameters.read_declarations(
    Some(
      from_unpivot_public_cursor(
        "{\"objects\":{\"type\":\"array\",\"max_items\":4,\"items\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"code\":{\"type\":\"number\",\"nullable\":false},\"label\":{\"type\":\"string\",\"nullable\":true}}}}}",
      ),
    ),
    {
      max_parameters: 10,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    },
  ).unwrap()
  let context = {
    ..fixture_context(),
    inputs: [],
    parameter_declarations: Some(declarations),
  }
  let lowered = @frontend.lower(
    "WITH joined AS (FROM UNNEST(@objects) e WITH OFFSET position |> JOIN (SELECT 2 AS key) k ON e.code = k.key MAX_OUTPUT_ROWS 10 |> SELECT e.*, position, k.key |> ORDER BY position) FROM joined |> RESULT answer",
    Text,
    Some(context),
  ).unwrap()
  assert_true(lowered.program is Some(_))
}

///|
test "WITH public expansion correlated-unnest-data" {
  let declarations = @parameters.read_declarations(
    Some(
      from_unpivot_public_cursor(
        "{\"parents\":{\"type\":\"array\",\"max_items\":4,\"items\":{\"type\":\"object\",\"fields\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"items\":{\"type\":\"array\",\"nullable\":true,\"max_items\":3,\"items\":{\"type\":\"number\",\"nullable\":true}}}}}}",
      ),
    ),
    {
      max_parameters: 10,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    },
  ).unwrap()
  let context = {
    ..fixture_context(),
    inputs: [],
    parameter_declarations: Some(declarations),
  }
  let lowered = @frontend.lower(
    "WITH expanded AS (FROM UNNEST(@parents) p |> CROSS JOIN UNNEST(p.items) element WITH OFFSET position |> SELECT p.id, element, position |> ORDER BY p.id, position) FROM expanded |> RESULT answer",
    Text,
    Some(context),
  ).unwrap()
  assert_true(lowered.program is Some(_))
}

///|
test "WITH public expansion correlated-unnest-inner-data" {
  let declarations = @parameters.read_declarations(
    Some(
      from_unpivot_public_cursor(
        "{\"parents\":{\"type\":\"array\",\"max_items\":4,\"items\":{\"type\":\"object\",\"fields\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"items\":{\"type\":\"array\",\"nullable\":true,\"max_items\":3,\"items\":{\"type\":\"number\",\"nullable\":true}}}}}}",
      ),
    ),
    {
      max_parameters: 10,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    },
  ).unwrap()
  let context = {
    ..fixture_context(),
    inputs: [],
    parameter_declarations: Some(declarations),
  }
  let lowered = @frontend.lower(
    "WITH expanded AS (FROM UNNEST(@parents) p |> JOIN UNNEST(p.items) element WITH OFFSET position ON element = p.id |> SELECT p.id, element, position |> ORDER BY p.id, position) FROM expanded |> RESULT answer",
    Text,
    Some(context),
  ).unwrap()
  assert_true(lowered.program is Some(_))
}

///|
test "WITH public expansion correlated-unnest-star-data" {
  let declarations = @parameters.read_declarations(
    Some(
      from_unpivot_public_cursor(
        "{\"parents\":{\"type\":\"array\",\"max_items\":4,\"items\":{\"type\":\"object\",\"fields\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"items\":{\"type\":\"array\",\"nullable\":true,\"max_items\":3,\"items\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"code\":{\"type\":\"number\",\"nullable\":false},\"label\":{\"type\":\"string\",\"nullable\":true}}}}}}}}",
      ),
    ),
    {
      max_parameters: 10,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    },
  ).unwrap()
  let context = {
    ..fixture_context(),
    inputs: [],
    parameter_declarations: Some(declarations),
  }
  let lowered = @frontend.lower(
    "WITH expanded AS (FROM UNNEST(@parents) p |> CROSS JOIN UNNEST(p.items) e WITH OFFSET position |> SELECT p.id, e.*, position |> ORDER BY p.id, position) FROM expanded |> RESULT answer",
    Text,
    Some(context),
  ).unwrap()
  assert_true(lowered.program is Some(_))
}

///|
test "WITH public expansion joined-unnest-star-sql" {
  let declarations = @parameters.read_declarations(
    Some(
      from_unpivot_public_cursor(
        "{\"parents\":{\"type\":\"array\",\"max_items\":4,\"items\":{\"type\":\"object\",\"fields\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"items\":{\"type\":\"array\",\"nullable\":true,\"max_items\":3,\"items\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"code\":{\"type\":\"number\",\"nullable\":false},\"label\":{\"type\":\"string\",\"nullable\":true}}}}}}}}",
      ),
    ),
    {
      max_parameters: 10,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    },
  ).unwrap()
  let context = {
    ..fixture_context(),
    inputs: [],
    parameter_declarations: Some(declarations),
  }
  let lowered = @frontend.lower(
    "WITH parents AS (FROM UNNEST(@parents) p |> SELECT id, items) SELECT p.id, e.*, position FROM parents p JOIN (SELECT 1 AS key UNION ALL SELECT 2 AS key) k ON p.id = k.key MAX_OUTPUT_ROWS 4 CROSS JOIN UNNEST(p.items) e WITH OFFSET position ORDER BY p.id, position",
    Text,
    Some(context),
  ).unwrap()
  assert_true(lowered.program is Some(_))
}

///|
test "WITH public expansion joined-unnest-star-pipe" {
  let declarations = @parameters.read_declarations(
    Some(
      from_unpivot_public_cursor(
        "{\"parents\":{\"type\":\"array\",\"max_items\":4,\"items\":{\"type\":\"object\",\"fields\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"items\":{\"type\":\"array\",\"nullable\":true,\"max_items\":3,\"items\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"code\":{\"type\":\"number\",\"nullable\":false},\"label\":{\"type\":\"string\",\"nullable\":true}}}}}}}}",
      ),
    ),
    {
      max_parameters: 10,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    },
  ).unwrap()
  let context = {
    ..fixture_context(),
    inputs: [],
    parameter_declarations: Some(declarations),
  }
  let lowered = @frontend.lower(
    "WITH parents AS (FROM UNNEST(@parents) p |> SELECT id, items) FROM parents p |> JOIN (SELECT 1 AS key UNION ALL SELECT 2 AS key) k ON p.id = k.key MAX_OUTPUT_ROWS 4 |> CROSS JOIN UNNEST(p.items) e WITH OFFSET position |> SELECT p.id, e.*, position |> ORDER BY p.id, position",
    Text,
    Some(context),
  ).unwrap()
  assert_true(lowered.program is Some(_))
}

///|
test "WITH public expansion joined-unnest-star-quoted-parenthesized" {
  let declarations = @parameters.read_declarations(
    Some(
      from_unpivot_public_cursor(
        "{\"parents\":{\"type\":\"array\",\"max_items\":4,\"items\":{\"type\":\"object\",\"fields\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"items\":{\"type\":\"array\",\"nullable\":true,\"max_items\":3,\"items\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"code\":{\"type\":\"number\",\"nullable\":false},\"label\":{\"type\":\"string\",\"nullable\":true}}}}}}}}",
      ),
    ),
    {
      max_parameters: 10,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    },
  ).unwrap()
  let context = {
    ..fixture_context(),
    inputs: [],
    parameter_declarations: Some(declarations),
  }
  let lowered = @frontend.lower(
    "WITH parents AS (FROM UNNEST(@parents) p |> SELECT id, items) SELECT `p`.id, e.*, position FROM parents `p` JOIN (SELECT 1 AS key UNION ALL SELECT 2 AS key) k ON `p`.id = k.key MAX_OUTPUT_ROWS 4 CROSS JOIN UNNEST((`p`).`ITEMS`) e WITH OFFSET position ORDER BY `p`.id, position",
    Text,
    Some(context),
  ).unwrap()
  assert_true(lowered.program is Some(_))
}

///|
test "WITH public expansion joined-unnest-star-original-range" {
  let declarations = @parameters.read_declarations(
    Some(
      from_unpivot_public_cursor(
        "{\"parents\":{\"type\":\"array\",\"max_items\":4,\"items\":{\"type\":\"object\",\"fields\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"items\":{\"type\":\"array\",\"nullable\":true,\"max_items\":3,\"items\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"code\":{\"type\":\"number\",\"nullable\":false},\"label\":{\"type\":\"string\",\"nullable\":true}}}}}}}}",
      ),
    ),
    {
      max_parameters: 10,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    },
  ).unwrap()
  let context = {
    ..fixture_context(),
    inputs: [],
    parameter_declarations: Some(declarations),
  }
  let lowered = @frontend.lower(
    "WITH parents AS (FROM UNNEST(@parents) p |> SELECT id, items) FROM parents p |> JOIN (SELECT 1 AS key UNION ALL SELECT 2 AS key) k ON p.id = k.key MAX_OUTPUT_ROWS 4 |> SET items = [9] |> CROSS JOIN UNNEST(p.items) e WITH OFFSET position |> SELECT p.id, e.*, position |> ORDER BY p.id, position",
    Text,
    Some(context),
  ).unwrap()
  assert_true(lowered.program is Some(_))
}

///|
test "WITH public expansion joined-unnest-star-current-column" {
  let declarations = @parameters.read_declarations(
    Some(
      from_unpivot_public_cursor(
        "{\"parents\":{\"type\":\"array\",\"max_items\":4,\"items\":{\"type\":\"object\",\"fields\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"items\":{\"type\":\"array\",\"nullable\":true,\"max_items\":3,\"items\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"code\":{\"type\":\"number\",\"nullable\":false},\"label\":{\"type\":\"string\",\"nullable\":true}}}}}}}}",
      ),
    ),
    {
      max_parameters: 10,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    },
  ).unwrap()
  let context = {
    ..fixture_context(),
    inputs: [],
    parameter_declarations: Some(declarations),
  }
  let lowered = @frontend.lower(
    "WITH parents AS (FROM UNNEST(@parents) p |> SELECT id, items) FROM parents p |> JOIN (SELECT 1 AS key UNION ALL SELECT 2 AS key) k ON p.id = k.key MAX_OUTPUT_ROWS 4 |> SET items = [9] |> CROSS JOIN UNNEST(items) e WITH OFFSET position |> SELECT * |> ORDER BY id, position",
    Text,
    Some(context),
  ).unwrap()
  assert_true(lowered.program is Some(_))
}

///|
test "WITH public expansion joined-unnest-star-acquired-data" {
  let declarations = @parameters.read_declarations(
    Some(
      from_unpivot_public_cursor(
        "{\"parents\":{\"type\":\"array\",\"max_items\":4,\"items\":{\"type\":\"object\",\"fields\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"items\":{\"type\":\"array\",\"nullable\":true,\"max_items\":3,\"items\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"code\":{\"type\":\"number\",\"nullable\":false},\"label\":{\"type\":\"string\",\"nullable\":true}}}}}}}}",
      ),
    ),
    {
      max_parameters: 10,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    },
  ).unwrap()
  // Prefix typing for correlated object star needs the admitted Catalog.
  // Reuse its numeric id contract under this query's records binding. The
  // Catalog's unused payload field is not a public Source/schema assertion.
  let captured = source_member_context(captured=true)
  let context = {
    ..captured,
    input_schemas: [("records", captured.input_schemas[0].1)],
    inputs: [{
      ..captured.inputs[0],
      relation: [{ value: "records", quoted: false, }],
      name: "records",
    }],
    parameter_declarations: Some(declarations),
  }
  let lowered = match @frontend.lower(
    "WITH parents AS (FROM UNNEST(@parents) p |> SELECT id, items), expanded AS (FROM parents p |> JOIN records r ON p.id = r.id MAX_OUTPUT_ROWS 4 |> CROSS JOIN UNNEST(p.items) e WITH OFFSET position |> SELECT p.id, e.*, position |> ORDER BY p.id, position) FROM expanded |> RESULT answer",
    Text,
    Some(context),
  ) {
    Ok(value) => value
    Err(QueryLowering(BindingPreparation(MissingSourceCatalog(_)))) =>
      fail("captured source needs its real admitted Catalog")
    Err(QueryLowering(BindingPreparation(LocalProgram(Pipeline(_, issue))))) =>
      fail("common binding Pipeline: " + @debug.to_string(issue.kind))
    Err(QueryLowering(InvalidContext)) => fail("InvalidContext")
    Err(QueryLowering(UnsupportedJoin)) => fail("UnsupportedJoin")
    Err(QueryLowering(UnknownColumn)) => fail("UnknownColumn")
    Err(QueryLowering(UnresolvedRelation(_))) => fail("UnresolvedRelation")
    Err(QueryLowering(BindingPreparation(SourceProgram(Program(Pipeline(_, issue)))))) =>
      fail("Catalog pipeline: " + @debug.to_string(issue.kind))
    Err(QueryLowering(BindingPreparation(SourceProgram(Program(Order(_, _)))))) =>
      fail("Catalog output Order")
    Err(QueryLowering(BindingPreparation(SourceProgram(_)))) =>
      fail("another SourceProgram cause")
    Err(QueryLowering(BindingPreparation(SourceRegistration(_)))) =>
      fail("SourceRegistration")
    Err(QueryLowering(BindingPreparation(SourceDeclarations(_)))) =>
      fail("SourceDeclarations")
    Err(QueryLowering(BindingPreparation(_))) => fail("another binding preparation cause")
    Err(QuerySyntax(_)) => fail("QuerySyntax")
    Err(QueryLowering(issue)) => {
      match issue {
        UnsupportedProjection => fail("UnsupportedProjection")
        UnsupportedCte => fail("UnsupportedCte")
        UnsupportedOrdering => fail("UnsupportedOrdering")
        Construction(_) => fail("Construction")
        Expression(_) => fail("Expression")
        ExpressionTyping(_) => fail("ExpressionTyping")
        Admission(_) => fail("Admission")
        InvalidQuery => fail("InvalidQuery")
        UnknownRelation => fail("UnknownRelation")
        AmbiguousRelation => fail("AmbiguousRelation")
        _ => fail("another QueryLowering cause")
      }
    }
    Err(_) => fail("another frontend selection cause")
  }
  assert_true(lowered.program is Some(_))
}

///|
test "WITH public expansion correlated-unnest-retained-data-set-star" {
  let declarations = @parameters.read_declarations(
    Some(
      from_unpivot_public_cursor(
        "{\"parents\":{\"type\":\"array\",\"max_items\":4,\"items\":{\"type\":\"object\",\"fields\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"items\":{\"type\":\"array\",\"nullable\":true,\"max_items\":3,\"items\":{\"type\":\"number\",\"nullable\":true}}}}}}",
      ),
    ),
    {
      max_parameters: 10,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    },
  ).unwrap()
  let context = {
    ..fixture_context(),
    inputs: [],
    parameter_declarations: Some(declarations),
  }
  let lowered = @frontend.lower(
    "WITH expanded AS (FROM UNNEST(@parents) p |> SELECT id, items |> UNION ALL (FROM UNNEST(@parents) p |> SELECT id, items) |> CROSS JOIN UNNEST(items) element WITH OFFSET position |> SELECT * EXCEPT (items) |> ORDER BY id, position) FROM expanded |> RESULT answer",
    Text,
    Some(context),
  ).unwrap()
  assert_true(lowered.program is Some(_))
}
