# LanStash Community Compatibility Program

[简体中文](COMMUNITY_COMPATIBILITY_PROGRAM_ZH.md)

The Community Compatibility Program collects structured test results across NAS models, DSM builds, package versions, and client platforms. It helps users see whether their environment has been reported and helps maintainers prioritize combinations that need verification.

A community report is a voluntarily submitted observation. It is not a maintainer device-acceptance result and cannot replace private-API discovery evidence. Maintainer evidence remains in [`DSM_COMPATIBILITY_MATRIX.md`](DSM_COMPATIBILITY_MATRIX.md) and [`contracts/private-api/compatibility.json`](../../contracts/private-api/compatibility.json).

## How to participate

Most users should open the GitHub “社区兼容性报告 / Community compatibility report” form. Contributors familiar with GitHub may instead submit a structured report Pull Request based on [`example-report.json`](../../contracts/community-compatibility/examples/example-report.json).

The macOS app can prepare and preview a local
`community-compatibility-submission.schema.json` draft under Settings > General >
Community compatibility report. Export remains disabled until the user records every result and
confirms the privacy statement. A draft intentionally omits `reportId`, `sourceRef`, and
`reviewStatus`; only a maintainer may add those fields after checking the public source. The app
does not upload, submit, or persist the draft automatically.

Before submitting:

1. Use a released LanStash build without temporary debugging code.
2. Follow the [`Community Compatibility Test Guide`](COMMUNITY_TEST_GUIDE_EN.md).
3. Test only a NAS, account, and data you are authorized to use.
4. Perform write tests only on disposable items created specifically for testing.
5. Remove every real file name, path, account, host, and raw error response.

## Data collected

The public form produces `schemaVersion: 2` reports and collects:

- LanStash version, source commit (`unknown` or 7-40 hexadecimal characters in either case),
  client platform, and platform version.
- Public NAS product model and CPU architecture.
- DSM version, build, and update number.
- Versions of packages relevant to the test.
- Connection category, account-role category, and certificate category.
- Passed, failed, partial, skipped, or unsupported outcomes for registered capability IDs.
- For failed or partial results, only the allowlisted structured fields `stage`,
  `errorCategory`, `apiName`, `apiVersion`, `httpStatus`, `retryPerformed`, and
  `rawResponseIncluded: false`.
- The public source Issue or Pull Request number for review and deduplication; the structured data does not retain the contributor username.

`schemaVersion` describes the report data structure; it does not describe which checks were
performed. `testSuiteVersion` selects the capability checklist. Schema version 2 accepts
test-suite version 1 or 2 so existing 14-capability observations remain representable.

The capability registry uses `introducedInTestSuiteVersion` to identify the first test-suite
version that contains each capability. A report must list every capability introduced by its
selected version: 14 results for version 1 and 19 for version 2. Checks that were not performed
or are unsupported must be recorded explicitly as `skipped` or `not-supported`, not omitted.
The version 2 `desktop-drive.*` capabilities apply only to macOS; every other platform must
record them as `not-supported`.

A NAS product model is a public product identifier and may be submitted. Never submit:

- A serial number, device name, MAC address, IP address, domain, port, or QuickConnect ID.
- A username, password, OTP, SID, SynoToken, cookie, DID, or certificate content.
- A share name, volume name, file name, file path, chat content, or container environment variable.
- A log, screenshot, HAR or PCAP capture, raw DSM response, crash dump, or user file.

The public report does not accept log attachments or free-form failure diagnostics. Fields such
as `message`, `body`, `path`, `host`, and raw-error text are not part of the allowlist and must
not be submitted. `rawResponseIncluded` must always be `false`. If a failure needs further
investigation, use [`SECURITY.md`](../../SECURITY.md) to decide between a separate public bug
report and the private security channel.

## Review and evidence status

| Status | Meaning |
| --- | --- |
| `submitted` | The structured report has been submitted but not reviewed |
| `reviewed` | Format, version information, and privacy checks passed |
| `corroborated` | At least two different contributors reported matching results for the same version combination |
| `maintainer-verified` | A maintainer reproduced the result in a recorded environment |
| `disputed` | Reports for the same version combination conflict |
| `superseded` | A newer test for the same environment replaces this report |

Review confirms that the structure is reasonable and no obvious private data remains. It does not guarantee that a result is accurate or complete. The community matrix preserves counts and conflicts instead of allowing a majority result to hide failures.

The optional formal-report `supersedes` field is maintained manually. A new report explicitly
points to older report IDs it replaces, and each target must be marked `superseded`. The relationship
is never inferred from a model, date, or result and never appears in an app submission draft.
Validation blocks dangling links, self-reference, cycles, reversed dates, and superseded reports
without a successor; other suspicious relationships and same-environment evidence remain warnings
for maintainer review.

## Source data and generation

Machine-readable data lives in:

```text
contracts/community-compatibility/
├── capabilities.json
└── reports/*.json
```

Run:

```bash
python3 tools/community-compatibility/validate.py
python3 tools/community-compatibility/validate_submission.py <draft.json>
python3 tools/community-compatibility/generate.py
```

This generates:

- [`COMMUNITY_COMPATIBILITY_MATRIX_ZH.md`](COMMUNITY_COMPATIBILITY_MATRIX_ZH.md)
- [`COMMUNITY_COMPATIBILITY_MATRIX_EN.md`](COMMUNITY_COMPATIBILITY_MATRIX_EN.md)

Do not edit generated files directly. CI checks report structure, privacy rules, capability IDs, and generated output.

## Version-scoped conclusions

A compatibility combination includes at least:

```text
NAS model + CPU architecture + DSM build/update + client platform + LanStash version
```

Package capabilities also require the relevant package version. A passing combination does not imply compatibility with another model, DSM build, client platform, or package version. Submit a new report after upgrading DSM, a package, or LanStash; do not overwrite history.

## Maintainer workflow

When enabling the program, a repository administrator should create the `compatibility-report` and `needs-review` labels on GitHub. Missing labels do not hide the form, but GitHub will not apply them automatically.

1. Check the Issue or Pull Request for prohibited data.
2. If the report cannot be made safe, close it and ask for a new submission. Do not repeat sensitive content in a comment.
3. For content already represented as a submission JSON, run the read-only candidate helper. It
   allocates the next `cc-NNNNNN` after the highest existing ID and never reuses a gap:

   ```bash
   python3 tools/community-compatibility/prepare_candidate.py \
     --submission /path/to/submission.json \
     --source-ref issue-123 \
     --submitted-at 2026-08-04 \
     --confirm-privacy-reviewed \
     --format diff
   ```

4. Review the candidate report and bilingual matrix diff written to standard output, then apply
   the required changes explicitly. The helper does not write the repository, run Git, access the
   network, or parse an entire Issue, comment thread, or attachment.
5. Set the evidence status supported by the review.
6. Run validation and matrix generation.
7. Commit only the structured report, generated matrices, and necessary documentation; never retain raw attachments.

Do not merge or copy suspected credentials or real user data to another system.

## Phase 2 roadmap

Phase 2 continues to use the structured-data contract established in Phase 1. Expansion should happen only when real report volume, maintenance cost, or user demand demonstrates a need.

1. A read-only maintainer helper now converts a manually reviewed submission JSON into a candidate
   report, allocates its report ID, validates capability IDs, and renders a candidate report plus
   bilingual matrix diff. It deliberately does not parse a whole Issue body because free text may
   contain private data.
2. Formal-report relationship and evidence auditing now blocks duplicate identities and invalid
   supersession graphs, while matching environments, conflicting results, and review-status
   mismatches produce warnings. These findings help maintainers assign `corroborated`, `disputed`,
   and `superseded`; the tool never changes a conclusion automatically.
3. Add versioned test suites for Photos, Chat, Download Station, Container Manager, Virtual Machine Manager, and Storage Manager while keeping older reports readable.
4. When the Markdown matrix becomes demonstrably hard to use, generate a static filtering page from the same reviewed JSON. It may filter by NAS model, DSM build, platform, LanStash version, package, and result, but must not introduce a separate user database.
5. Design a local “compatibility diagnostic summary” exporter across all five clients. It must use an allowlist, show a local preview before export, require explicit confirmation, exclude log bodies by default, and include matching English, Simplified Chinese, and accessibility coverage.
6. Define anonymous statistical methods, report-expiration rules, test-suite migration notes, and periodic review. Report counts must not be presented as device market share or an overall success rate.

Phase 2 explicitly excludes:

- Automatic telemetry, background uploads, or collection without user consent.
- Arbitrary logs, HAR or PCAP captures, screenshots, crash dumps, or raw DSM responses.
- A bot bypassing manual privacy review to merge a report or write to the default branch.
- Automatically enabling an internal write API because a community report passed.

Phase 2 should begin only after the real Phase 1 workflow is stable, the Schema evolution policy has been exercised, privacy-incident ownership is clear, and enough reports exist to show that automation will reduce actual maintenance cost.
