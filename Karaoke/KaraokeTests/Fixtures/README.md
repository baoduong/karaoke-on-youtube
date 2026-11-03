# Test Fixtures (T043)

Recorded upstream response fixtures so the test suite never touches the live network.
A test suite that depends on YouTube being up fails for the wrong reasons (tasks.md T043).

## Rules

- **No real song lyrics.** Use synthetic placeholder words only (e.g. "alpha", "bravo",
  "charlie"). This is a hard rule stated in the project contracts.
- **No real video IDs** that could be used to fetch live content. Use the synthetic IDs
  defined in each fixture file (format: `AAAAAAAAAAA` — 11 chars of `A`s or similar).
- **No API keys or credentials** in any fixture file.
- Fixtures are static snapshots. When the upstream contract changes, update the fixture
  and the test together.

## Contents

| File | Purpose |
|---|---|
| `synthetic-search-response.json` | Synthetic YouTube Data API v3 search response for parser tests |
| `synthetic-lyrics-lrclib.json` | Synthetic LRCLIB `/api/get` response for lyrics parser tests |

## Adding a fixture

1. Capture the real response shape (field names, types, nesting).
2. Replace all real content with synthetic placeholders.
3. Replace all real IDs with synthetic IDs.
4. Add a row to the table above.
