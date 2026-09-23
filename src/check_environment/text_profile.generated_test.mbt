// Generated synthetic integrity fixture; not an execution conformance claim.
///|
fn text_profile_fixture() -> String {
  "{\"numeric_law\":{\"N\":\"all_admitted_documents_including_empty\",\"average_length\":\"total_document_token_count / N\",\"df\":\"documents_containing_term\",\"document_length\":\"token_count_with_multiplicity\",\"duplicate_identities\":\"reject_before_scoring\",\"empty_corpus_or_all_empty_or_empty_query\":\"no_rows_without_division_by_zero\",\"fold\":\"left_fold_from_positive_zero_in_canonical_query_term_order\",\"identity_order\":\"canonical_UTF16\",\"idf\":\"ln(1 + ((N - df) + 0.5) / (df + 0.5))\",\"k\":\"positive_safe_integer\",\"logarithm\":\"correctly_rounded_ln_of_binary64_argument\",\"missing_term\":\"zero_without_division\",\"nonfinite_intermediate\":\"reject\",\"norm\":\"(1 - b) + (b * (document_length / average_length))\",\"order\":[\"query_id_ascending\",\"score_descending\",\"candidate_id_ascending\"],\"parameters\":{\"b\":\"finite_binary64_in_closed_0_1\",\"k1\":\"finite_positive_binary64\"},\"query_terms\":\"deduplicate_then_canonical_UTF16_order\",\"rank\":\"contiguous_one_based_after_per_query_top_k\",\"rounding\":\"binary64_nearest_ties_even_after_each_displayed_operation\",\"statistics_scope\":\"actual_admitted_corpus_only\",\"term_score\":\"idf * ((tf * (k1 + 1)) / (tf + (k1 * norm)))\",\"tf\":\"term_occurrences_in_document\",\"version\":\"actql-bm25-binary64/0.1\",\"zero_scores\":\"omit\"},\"numeric_vectors_bytes_cid\":\"sha256:02a2f7fbaaa613f74b59be435c362489a619ee1c2ab2100c270f2ab52fc30d4f\",\"tokenizer_law\":{\"category_matching\":\"Unicode_general_category_prefix\",\"char_bigram\":\"adjacent_scalar_pairs_per_run_or_singleton\",\"default_ignorable_removal\":false,\"host_locale_dictionary_stopwords_synonyms_stemming\":false,\"malformed_unicode\":\"reject\",\"normalization\":[\"NFKC\",\"full_default_case_fold_C_F\",\"NFC\"],\"other_scalars\":\"delimiter\",\"run_continue_categories\":[\"L\",\"N\",\"M\"],\"run_start_categories\":[\"L\",\"N\"],\"token_multiplicity\":\"preserve\",\"unicode_version\":\"16.0.0\",\"unicode_words\":\"maximal_runs\",\"version\":\"actql-text-rank-tokenizers/0.1\"},\"tokenizer_vectors_bytes_cid\":\"sha256:05943b0e8a5b5c62b756bf0d40286a579529bee57c920455f5a20eda0d7467a8\",\"unicode_source_sha256\":{\"CaseFolding.txt\":\"d83475f86bfd39ca096d0f9b33c659de9ce3f8bff09fc850a01214d710dd51fc\",\"CompositionExclusions.txt\":\"8c84687d2f1c3ee207df53f4d80dad82a69df64b58bcb87e3e45bc15ce74fe1d\",\"DerivedNormalizationProps.txt\":\"c3e68d9435743b3efac999c24d9f0095fa7446fcb7e40aa42e1cca72728465c0\",\"LICENSE.txt\":\"c011d6097bfbc8e936280addcf2e3e7d06ea2223ffd596973191b800a7035c32\",\"NormalizationTest.txt\":\"6a86baf64d1ccece3cf150ddb574066b7e2e730a7da9dc2af0016ca01e7d4b8b\",\"UnicodeData.txt\":\"7fb512e9793e490b3d6cd809337c0ff3f336c527b672fbde4b4359653a7900eb\"},\"unicode_version\":\"16.0.0\",\"version\":\"actql-text-rank-profile/0.1\"}"
}
///|
fn text_profile_fixture_cid() -> String { "sha256:1c414779dabddac36df1d55cb176f425c2423f4bbc63fa824bdde85d78bd2213" }
///|
fn text_profile_blobs() -> Array[(@lexical.Dependency, Bytes)] {
  [
    (@lexical.UnicodeData, @utf8.encode("UnicodeData")),
    (@lexical.CompositionExclusions, @utf8.encode("CompositionExclusions")),
    (@lexical.CaseFolding, @utf8.encode("CaseFolding")),
    (@lexical.DerivedNormalizationProps, @utf8.encode("DerivedNormalizationProps")),
    (@lexical.NormalizationTest, @utf8.encode("NormalizationTest")),
    (@lexical.License, @utf8.encode("License")),
    (@lexical.TokenizerVectors, @utf8.encode("TokenizerVectors")),
    (@lexical.NumericVectors, @utf8.encode("NumericVectors")),
  ]
}
