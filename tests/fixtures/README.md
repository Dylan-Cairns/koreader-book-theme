# Fixtures

The test suite uses in-memory EPUB structures built in `tests/unit/*_test.lua`. A fixture is a Lua table of archive paths to strings, wrapped by `Helpers.memory_reader` in `tests/helpers.lua`.

This keeps the parser/classifier tests independent of libarchive and Android. If a real malformed EPUB is needed later, add it as an encrypted/ignored file under `local/fixtures/` and copy only the minimal XML into a test.

Do not add copyrighted books to the repository.
