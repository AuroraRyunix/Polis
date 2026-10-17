# The plugin's tests run inside the OpenPairings suite (see
# docs/openpairings-integration.md): the core's test/test_helper.exs has
# already started ExUnit and the SQL sandbox by the time this one is
# loaded. Mix still wants one per test directory.
