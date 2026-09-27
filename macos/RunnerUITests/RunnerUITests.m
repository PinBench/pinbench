@import XCTest;
@import patrol;
@import ObjectiveC.runtime;

// Patrol's macOS test runner. The PATROL_INTEGRATION_TEST_MACOS_RUNNER macro
// dynamically registers one XCTest case per `patrolTest(...)` found in the
// Dart `integration_test/` suite, so this file never needs to change as tests
// are added. It is the native entry point invoked by `patrol test` /
// `patrol develop`.
PATROL_INTEGRATION_TEST_MACOS_RUNNER(RunnerUITests)
