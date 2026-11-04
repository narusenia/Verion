# Verion — agent guide

Verion is a GPU renderer written in Rust for Blender / Cinema 4D / Maya. Its core is Art-Directable Physical Rendering: PBR path tracing with Stylized PBR / Hybrid NPR, plus AI-assisted acceleration. Personal research project; the licence is undecided (ADR-0004).

## Where things are

- Requirements: `docs/requirements/` (`REQ-{SCOPE}-{SEQ}`; start at `overview.md`)
- Specifications: `docs/specifications/` (`architecture.md` first; not written yet)
- Plans: `docs/implementation/roadmap.md`, then `docs/implementation/M{n}-*/README.md`
- Decisions: `docs/adr/`
- Early concepts (research hypotheses, not requirements): `docs/drafts/` (`draft_arch.md` is the original; the others are the GPU performance plan, the adaptive sampling plan and the Aerion real-time engine)
- Session handoffs: `docs/handoff/` (never at the repository root)

## Commands

- `mise run check` — the canonical verification (fmt + clippy + deny + test). CI and the pre-commit hook run the same tasks.
- `mise run fmt:fix` — apply formatting
- `mise run hooks:install` — install lefthook hooks

## Rules

- **Crate dependencies** follow `docs/specifications/architecture.md`. GPU-independent crates (scene, material, geometry) must not depend on a GPU API.
- **Backends**: Metal first, Vulkan second (ADR-0001). Shaders are written once in Slang (ADR-0002); fall back to native MSL only if the M1 spike fails.
- **Physical vs non-physical**: Reference mode must bypass Stylization and every AI approximation. Mark non-physical output in metadata.
- **Dependencies** must allow commercial redistribution. Check the terms before adding one, and run `mise run deny`.
- **No new tools or packages** without the maintainer asking for them.
- **Plan status** lives only in the table of each milestone `README.md`. Do not move files to express status.
- **Language**: requirements, plans and ADRs in Japanese; code, comments, commit messages and README in English.
- **Commits**: one logical unit per commit, single-line English message with a prefix (`feat:` `fix:` `refactor:` `docs:` `test:` `chore:` `perf:` `ci:`), no task IDs.
- **Docs consistency**: when finishing a piece of work, check whether it affects the requirements, specifications or plans under `docs/`, and if it does, ask the user whether to update them.
