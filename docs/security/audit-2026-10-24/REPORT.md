# Security audit — incomplete PC handoff

The user requested immediate publication to GitHub for continuation on their PC before independent candidate validation. This is a partial source-only review. **No confirmed security findings have been established.** No target code, malformed-file check, live endpoint, or real credential was executed by the audit.

Cloudflare security-audit skill, standard profile, scope: shared game/native frontends, runtime resources, selected scripts, CI, vendored stb and package manifest. No prior compatible audit ledger existed. The original source reference and per-file hashes are in run-metadata.json and source-manifest.json. That snapshot predates initialization of the requested GitHub repository.

Four reconnaissance assignments and three source hunters completed. The post-wave coverage critic identified one additional temp-output boundary. The separate final-clean critic and independent candidate/final-record verification have not run. The source-only execution policy requires a full OS sandbox with network denial, empty allowlisted environment, read-only source/tools, scratch-only writes and explicit resource limits; these controls were not established together, so dynamic checks were not run.

## Unvalidated proposals — not findings

- `TowerCore/save-geometry-validation-overflow`: imported geometry reaches arithmetic before complete endpoint/slot checks. Source unit: TowerSaveStore.read -> TowerState.validated -> FloorSpan.width/contains. Verify safe rejection with small dummy input inside the required sandbox.
- `TowerCore/save-daily-totals-int-conversion`: finite but nonrepresentable daily totals may reach an Int conversion at midnight. Source unit: save read -> validated -> simulation tick. Verify only acceptance/one-tick behavior using a dummy child process inside the required sandbox.
- `scripts/predictable-temp-image-write`: icon generation and native UI screenshots write predictable temporary paths; another local principal's ability to plant a redirecting link and the resulting write semantics remain unobserved. Validate only with scratch-local dummy identities/files. A dedicated coverage unit is deferred.

All three fingerprints remain linked to ledger candidates. Their proposals are in candidate-proposals.json; they are excluded from findings.json until independent verification. No severity is assigned. Source-visible concerns are not proof of exploitation, data loss, or code execution.

## Source patterns and hardening notes

Save switching validates before installing a replacement and preserves distinct UUID recovery files; unreadable autosave preservation failures block replacement. Demolition has a safe cancel default. C dialog callbacks use queue lifetime/refcounting and immediately copied paths. Download hashes and action commits are pinned; CI has read-only repository permissions and no visible secrets. Native resource and font inputs are currently bundled/installed, rather than untrusted downloads.

Potential hardening includes bounded save-file reads, complete numeric/cardinality validation, private per-run temporary output directories, explicit dialog request binding, handling a failed glyph allocation, and deliberate source-bundle/private-SDK exclusions. These are not independently confirmed vulnerabilities.

## Coverage

13 deterministic units: 9 source-covered, 3 source-candidate, and 1 deferred. None have dynamic audit evidence. Zero confirmed records. Generated app/media archives, hosted/installed environments, Windows loader behavior, actual Steam sessions, and external advisory queries were outside this pass. No claim of complete or clean security coverage is made.
