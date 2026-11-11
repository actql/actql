///|
test "mock installation inventory counts every retained link and preflight return site" {
  let held = original_model_mock_installation_retained_extent()
  let peak = original_model_mock_installation_construction_extent()
  // Independent site census, not counts obtained from either production quote.
  // Installation, seven Somes, unbound task None, invocation and provider.
  let retained_sites = [
    (1L, 8L, 2L),
    (7L, 7L, 7L),
    (1L, 0L, 1L),
    (1L, 1L, 1L),
    (1L, 2L, 0L),
  ]
  let mut h = 0L
  let mut r = 0L
  let mut w = 0L
  for (headers, references, words) in retained_sites {
    h += headers
    r += references
    w += words
  }
  assert_eq(held, { record_headers: h, reference_slots: r, scalar_words: w, })
  // Initial None alternatives; answer original check's Retired/Err,
  // ForeignOriginal/Err, Ok(Unit); constructor's ForeignOriginal/Err,
  // Answers/Err and Ok(original). Fixed alternatives deliberately co-count.
  for
    (headers, references, words) in [
      (2L, 0L, 2L),
      (2L, 1L, 2L),
      (2L, 1L, 2L),
      (1L, 0L, 2L),
      (2L, 1L, 2L),
      (2L, 2L, 2L),
      (1L, 1L, 1L),
    ] {
    h += headers
    r += references
    w += words
  }
  assert_eq(peak, { record_headers: h, reference_slots: r, scalar_words: w, })
  assert_true(peak.record_headers > held.record_headers)
  assert_true(peak.reference_slots > held.reference_slots)
  assert_true(peak.scalar_words > held.scalar_words)
}

///|
test "mock installation inventory composes at exact Int64 boundaries without wrapping" {
  let maximum = 9223372036854775807L
  for
    quote in [
      original_model_mock_installation_retained_extent(),
      original_model_mock_installation_construction_extent(),
    ] {
    let rest : @shape.CollectionConstructionExtent = {
      record_headers: maximum - quote.record_headers,
      reference_slots: maximum - quote.reference_slots,
      scalar_words: maximum - quote.scalar_words,
    }
    assert_eq(
      @shape.add_collection_construction_extents(rest, quote),
      Some({
        record_headers: maximum,
        reference_slots: maximum,
        scalar_words: maximum,
      }),
    )
    for
      short in [
        { ..rest, record_headers: rest.record_headers + 1L, },
        { ..rest, reference_slots: rest.reference_slots + 1L, },
        { ..rest, scalar_words: rest.scalar_words + 1L, },
      ] {
      assert_true(
        @shape.add_collection_construction_extents(short, quote) is None,
      )
    }
    assert_eq(
      @shape.scale_collection_construction_extent(quote, 0L),
      Some({ record_headers: 0L, reference_slots: 0L, scalar_words: 0L, }),
    )
    assert_eq(
      @shape.scale_collection_construction_extent(quote, 1L),
      Some(quote),
    )
    assert_true(@shape.scale_collection_construction_extent(quote, -1L) is None)
    assert_true(
      @shape.scale_collection_construction_extent(quote, maximum) is None,
    )
  }
}

///|
test "mock installation inventory describes borrowed originals without invoking or replacing them" {
  let source = mock_installation_test_original()
  let profile = source.profile.unwrap()
  let declaration = source.declaration.unwrap()
  let normalized = source.normalized.unwrap()
  let answers = source.answers.unwrap()
  let clock_calls = Ref(0)
  let now = () => {
    clock_calls.val += 1
    "2026-11-06T00:00:00.000Z"
  }
  original_model_mock_installation_construction_extent() |> ignore
  original_model_mock_installation_retained_extent() |> ignore
  let original = install_original_model_mock(
    profile, declaration, normalized, answers, now,
  ).unwrap()
  assert_true(physical_equal(original.original.unwrap(), original))
  assert_true(physical_equal(original.profile.unwrap(), profile))
  assert_true(physical_equal(original.declaration.unwrap(), declaration))
  assert_true(physical_equal(original.normalized.unwrap(), normalized))
  assert_true(physical_equal(original.answers.unwrap(), answers))
  assert_true(physical_equal(original.now.unwrap(), now))
  assert_true(original.task is None)
  assert_false(original.closing)
  assert_eq(original.users, 0)
  let provider = original.provider.unwrap()
  assert_eq(provider.provider_id, "mock")
  assert_true(
    provider.invocation is OriginalMock(owner) &&
    physical_equal(owner, original),
  )
  assert_eq(clock_calls.val, 0)
  assert_true(
    physical_equal(original_model_mock_provider(original).unwrap(), provider),
  )
  assert_eq(retire_original_model_mock(original), Ok(true))
  assert_eq(clock_calls.val, 0)
  assert_true(
    original.now is None &&
    original.original is None &&
    original.provider is None,
  )
  // Retiring this new wrapper does not retire any of its borrowed children.
  assert_true(original_model_mock_provider(source) is Ok(_))
  assert_eq(retire_original_model_mock(source), Ok(true))
  retire_model_mock_answers(answers, declaration).unwrap()
  assert_true(@environment.retire_model_mock_profile(profile))
}

///|
test "mock installation inventory preserves every original preflight refusal" {
  let source = mock_installation_test_original()
  let other = mock_installation_test_original()
  let profile = source.profile.unwrap()
  let declaration = source.declaration.unwrap()
  let normalized = source.normalized.unwrap()
  let answers = source.answers.unwrap()
  let other_profile = other.profile.unwrap()
  let other_declaration = other.declaration.unwrap()
  let other_answers = other.answers.unwrap()
  let calls = Ref(0)
  let now = () => {
    calls.val += 1
    "unused"
  }
  original_model_mock_installation_construction_extent() |> ignore
  assert_true(
    install_original_model_mock(
      other_profile, declaration, normalized, answers, now,
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    install_original_model_mock(
      profile, other_declaration, normalized, answers, now,
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    install_original_model_mock(
      profile, declaration, normalized, other_answers, now,
    )
    is Err(Answers(ForeignOriginal)),
  )
  assert_true(
    install_original_model_mock(
      profile,
      declaration,
      normalized,
      { ..answers, },
      now,
    )
    is Err(Answers(ForeignOriginal)),
  )
  retire_model_mock_answers(answers, declaration).unwrap()
  assert_true(
    install_original_model_mock(profile, declaration, normalized, answers, now)
    is Err(Answers(Retired)),
  )
  assert_true(@environment.retire_model_mock_profile(profile))
  assert_true(
    install_original_model_mock(profile, declaration, normalized, answers, now)
    is Err(ForeignOriginal),
  )
  assert_eq(calls.val, 0)
  assert_eq(retire_original_model_mock(source), Ok(true))
  assert_eq(retire_original_model_mock(other), Ok(true))
  retire_model_mock_answers(other_answers, other_declaration).unwrap()
  assert_true(@environment.retire_model_mock_profile(other_profile))
}
