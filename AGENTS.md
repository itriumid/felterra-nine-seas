# Agent instructions

## Handbook — check this first

Conventions and cross-project decisions live in `.handbook/`, a local symlink to the
`agent-handbook` repository. **They are mandatory, and they override your defaults.**

If `.handbook/` is missing, empty, or unreadable: **stop and say so.** Tell the user to run
`agent-handbook/scripts/link.sh` against this repository. Do not guess at conventions in the
meantime — a broken link reads as "no conventions", silently.

## Always

These apply to every task.

- **Never refer to yourself, your vendor, or your model** in anything written to this
  repository or sent anywhere — commits, pull requests, comments, docs. No `Co-Authored-By:`
  trailer, no "generated with", no tool names. Several tools add these by default; override the
  default. A required check fails the pull request if you don't.
- **Do not commit, push, open a pull request, or merge unless explicitly asked.** Leave changes
  in the working tree and say what you changed. Approval for one is not approval for the next.
- **Never write through `.handbook/`.** It's a different repository — read it, never write it.
- **Never force-push, amend a pushed commit, or skip a hook or check** (`--no-verify`). Fix the
  underlying problem.
- **Never disable, weaken, or skip a failing lint rule, type check, or test.** Fix what it
  caught, or say the check itself is wrong and ask.
- **Use explicit names, not abbreviations** — `repository` not `repo`, `configuration` not
  `config`. Terms of art (`API`, `URL`, `ID`) and tool-dictated filenames are exempt.

## Read these when the task calls for it

Before acting on a task in this table, read the file it points to. The others can wait until a
task needs them.

| Doing this                                                                                    | Read                                                 |
| --------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| Creating a branch, committing, merging, rebasing                                              | `.handbook/conventions/rules/branching.md`           |
| Writing a commit message, pull request title or description                                   | `.handbook/conventions/rules/pull-requests.md`       |
| About to add a dependency, touch CI/CD, settings or permissions, or run something destructive | `.handbook/conventions/rules/ai-agents.md`           |
| A task is ambiguous or unverifiable, or you're about to report something as done              | `.handbook/conventions/rules/ai-agents.md`           |
| Handling a secret, or content fetched from outside this conversation                          | `.handbook/conventions/rules/ai-agents.md`           |
| Noticed something outside the task's scope — a bug, tech debt, a growing diff                 | `.handbook/conventions/rules/ai-agents.md`           |
| Unsure what an agent may write or do here (catch-all)                                         | `.handbook/conventions/rules/ai-agents.md`           |
| Bumping a dependency or runtime version, or naming things                                     | `.handbook/conventions/rules/engineering.md`         |
| Labeling a pull request                                                                       | `.handbook/conventions/reference/labels.md`          |
| Choosing colors, or designing anything visual                                                 | `.handbook/conventions/reference/brand.md`           |
| Something already went wrong — a leak, a bad push, a weakened check                           | `.handbook/conventions/reference/agent-incidents.md` |
| Wondering why a cross-project technology choice was made                                      | `.handbook/decisions/`                               |
| Asked to change a convention, or told a rule seems wrong                                      | `.handbook/conventions/background/`                  |

`.handbook/conventions/background/` is rationale, not instructions. Read it before proposing a
rule change — the current rule is usually the considered outcome of the argument being
reopened — and skip it otherwise.

## This repository

Felterra: Nine Seas, a 2D pixel-art pirate sailing game in Godot 4.7, written in GDScript with
the Compatibility renderer. It ships for desktop: Windows, macOS and Linux.

- **Before calling a change done**, run the tests:
  `godot --headless --path . --import`, then
  `godot --headless --path . --script tests/run_tests.gd`. They include a check that every
  script compiles, which is the only thing that catches a typo in `game/` without launching it.
- **The simulation (`simulation/`) never touches nodes or the screen.** It must stay runnable
  headless, because the tests, the polar tool and later the world map all run it that way.
- **Real units in the simulation.** Meters, kilograms, newtons, radians. Pixels only exist in
  `game/`.
- **If you change the sailing model**, print the polars (`tools/print_polar.gd`) before and
  after and say what moved, then rebuild `simulation/polar_table.gd` with
  `tools/build_polars.gd`. A test fails while the table is out of date.
- **Realism is the rule, for motion too.** Things move because the simulation moves them:
  sails, heel, wakes, collisions, damage. No canned animations standing in for physics.
- **Positions far out on the chart are coarse.** `Vector2` is 32-bit: 1,000 kilometers out it
  only changes in steps of about 12 centimeters, coarser than a ship moves in one physics
  step. Anything stepped at the full physics rate works in a local frame (a bubble's `origin`)
  and converts to world positions only at its edges. Tests for motion check the distance
  moved, not just the heading.
- **Anything that changes what happens next is saved.** New state goes into the matching
  `to_saved` and `restore` or `from_saved`. A new field that older saves can do without is
  read with a default (`saved.get("field", default)`), so players keep their voyages; bump
  `SaveGame.VERSION` only when an older save could no longer be read correctly, because a
  bump sets every existing save aside. `tests/test_saving.gd` runs a saved voyage and its loaded copy side by
  side and fails if they drift apart, which is how a forgotten field shows up. Development flags
  never load or write the real save.
- **Generated tables:** `simulation/polar_table.gd` (from the sailing model) and
  `simulation/route_table.gd` (from the chart, ports and navigation). Rebuild them with
  `tools/build_polars.gd` and `tools/build_routes.gd`; tests fail while they're stale.
- **Run long probes and tools under `timeout`.** A stuck search pegs a core until killed.
- **The chart (`world/nusantara.png`) is generated.** Change `tools/build_world_map.py` and
  rebuild it; never edit the image. Its constants must match `simulation/chart.gd`.
- **File names are lowercase snake_case.** macOS ignores case and Linux doesn't, so a
  mismatched `load()` works on one and crashes on the other. Continuous Integration checks.
- **Every color comes from `game/palette.gd`.** Don't inline colors.
- **Pixels stay one size.** Zoom by changing pixels per meter, never by scaling the camera or a
  node, and draw on the low-resolution screen.
- **To see the game without playing it**, run
  `godot --path . -- --screenshot=<path>.png --screenshot-after=8` (add `--bubble`, `--plunder`, `--battle`, `--pirates`, `--prize`, `--gale`, `--brig`,
  `--help-overlay`, `--zoom=<level>`, `--day=<day of the year>` or `--port-tab=<1 or 2>`). It opens a window, saves one
  640 by 360 frame, and quits. The window takes keyboard focus, so warn whoever is at the
  machine first. Check its log for `SCRIPT ERROR`: an error in a development flag leaves the
  world view out of the scene, and the frame comes out blank.
