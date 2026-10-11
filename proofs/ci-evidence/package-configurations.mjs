// A reviewed finite input policy, not a general package-language parser.
// At this revision these literal options contain only native stubs, native
// linker settings and native/not-native file predicates. For the pinned Moon
// JS execution path they select bound source files but cannot run a native
// linker/stub compiler. All package/source bytes and memberships remain inputs.
// The current import/custody split is reviewed in
// docs/reviews/2026-10-10-session-package-configuration-review.md and
// docs/reviews/2026-10-11-session-local-import-configuration-review.md.
// Changes to this table, the toolchain or any configuration force fresh work.
// Unknown options and other targets require separate review; matching a digest
// is configuration identity, not a proof of compiler or OS correctness.
export const packageConfigurationReview = Object.freeze({
  revision: 'aae65b850faa3a6d02247c40f8270c8b5bd2d62c',
  target: 'js',
  toolchainDigest: '8a3a1396f02ba4d5d780382960d1bcf95ccc8d6b97c3da446c0899b98874819a',
  moonRevision: '94521db',
  rule: 'literal-native-options-with-bound-source-membership',
});

export const reviewedPackageConfigurations = Object.freeze({
  'src/native_values_integration/moon.pkg': '183fdeb054a5901ffc1e00e44478f46441143ddea98cac2ba5ab71b3726b585e',
  'src/connectors/duckdb/adapters/native/moon.pkg': '7283cc7667b9293a7132672ce9edf375901ffb35eb02e25af9eb9eba55a1e89d',
  'src/platform_native/filesystem/moon.pkg': 'cf42efdf2f6fb6285a1a099fca4c71e9f149a9fa940d05d5f42a3b0b47a60651',
  'src/platform_native/http_client/moon.pkg': 'f2def56166ae8d5566441f011296f2f8ec9a93167d18f405f1894e4871267a08',
  'src/platform_native/https_server/moon.pkg': '880ad74137ab58e0f92f43465f9bc2bcd096eb2b29461b9f93d68883ed5d22bd',
  'src/platform_native/publication_store/moon.pkg': '33e845904153ce5ffccf03d014623b7f39b9923e308d090070ed4be2f5487373',
  'src/platform_native/remote_client/moon.pkg': '51a482218b9c119e403bbcc8ecb486c2e75627fc0f02c9be6e3e231f33abd8e7',
  'src/platform_native/remote_journal/moon.pkg': 'fabd84150e34e03d1aa4cb8de6a1a0fdc044eecf76ba080d4de54ba82f26e4be',
  'src/platform_native/remote_standard_host/moon.pkg': '14c80ec28c7c4f706f8aa55c2a73fa0c2f3023c4f91d4cb016094d0170b04f87',
  'src/platform_native/remote_transfer_client/moon.pkg': 'b026d1ada91a1f113c33df63fae999c0a05e197b2b50b0d29d9e7258d830baeb',
  'src/platform_native/remote_transfer_journal/moon.pkg': 'da01cf66f62a1632dce894f19a8d781d3b8c7f4d822aaf71e3e1cb1d07556ffd',
  'src/platform_native/retained_task_file/moon.pkg': 'e3050859982bfa2a176e04f44c08dcf073be7405e42be6f0af81f51a680347de',
  'src/platform_native/runtime_bundle/moon.pkg': 'a853c9fd5ca1ae9c3ca8744b48efaf1ffbc41c13d7c2b5fa67989d3b9950e9cc',
  'src/platform_native/signature/moon.pkg': '4b3e2bfdf20da7bbdd9dd04667eabaa8d804c3467c589cd7eea54e57fd39beaf',
  'src/platform_native/sqlite/moon.pkg': '05340cbc4e922feb361cd58cc8da0cec23671f76eacaaf28aafdfba682ec049d',
  'src/query_integration/moon.pkg': '386b2001819b39580db802f96d0daf0bf0e43453d404b4330a11aac60bcf8cc3',
});

export function reviewedPackageConfiguration({path, digest, target, toolchainDigest}) {
  return target === packageConfigurationReview.target &&
    toolchainDigest === packageConfigurationReview.toolchainDigest &&
    Object.hasOwn(reviewedPackageConfigurations, path) && reviewedPackageConfigurations[path] === digest;
}
