# How to cut a plan into chunks

This is the granularity rule. There is deliberately **no size threshold** in it — no line cap, no
file count, no "half a day of work". Size is a symptom, not a criterion: a fifty-file rename is
trivial to review, and a three-file change to an authorization check is not. Cut on deliverables
and proofs instead, and the sizes come out reasonable on their own.

## The procedure

**1. Find the spine.** Read the whole plan and write down, in one sentence each, the *capabilities*
it delivers — the things that will be observably true afterwards and are not true now. Ignore the
plan's own section structure while you do this: sections are written to explain the work, not to be
shipped separately.

**1b. If nothing runs end to end yet, the first chunk is the skeleton.** When the plan introduces a
pipeline that doesn't exist — a new package, a new command, a new deployment path — chunk #1 is the
thinnest slice that goes all the way through it and is built, run and tested automatically, even if
it does something trivial. Everything else then depends on a path that is already proven. This is
the "walking skeleton"; skipping it means every later chunk carries the risk of the whole pipeline.

**2. Give each capability one chunk.** One chunk = one capability someone outside the change can
observe. Where a capability is too big to hold in one head, split it along the sequence in which it
becomes observable ("emits the artifact" → "serves it in dev" → "proves it in a browser"), never
along implementation layers.

**3. Name the proof, per chunk.** For each chunk write what demonstrates it works: a test that
fails before and passes after, a command whose output changes, a page that renders, a metric that
moves. **A chunk with no nameable proof is not a deliverable — it is a step, and it belongs inside
another chunk.** This single question eliminates most bad cuts.

**4. Collect the preconditions.** Work that must be true before several later chunks can be written
— a package that must exist, a contract that must be pinned, a fixture nobody has yet — is its own
chunk, and "everything the following chunks need in place" is a legitimate deliverable with a
legitimate proof (the later chunks compile and run against it). Scattering preconditions into the
chunks that need them produces several chunks each half-building the same foundation.

**5. Order by dependency, then hunt for parallelism.** Draw the graph. A straight chain is a
warning sign: it usually means the cut followed the plan's narrative order rather than real
dependencies. Ask of every edge "would this chunk actually fail to be written without that one?"
and delete the edges that only encode habit. Foundations before dependents, always — but only the
ones that are genuinely foundations.

Then flatten the graph into **waves**: wave 1 is every chunk with no dependency, wave 2 is every
chunk whose dependencies are all in wave 1, and so on. Waves are what make the ordering useful —
they say what can be worked at the same time, which is most of the value of doing this exercise at
all. Mark chunks that share a wave as parallel when you present the decomposition.

**6. Put the phase's proof in the chunk that closes it.** An end-to-end test filed as its own item
gets written against nothing. It belongs with the last behaviour it proves.

## The per-chunk checklist

Every chunk must answer all five:

1. **What is observably true after it that isn't now?** One sentence, no "and".
2. **What proves it?** Named, concrete, runnable.
3. **Can it land on its own** without a sibling chunk landing first? (If not, it has a dependency —
   record it. If it needs *two* siblings first, look again: it may be the wrong cut.)
   State the dependency as a contract, not a vibe: what this chunk **consumes** (the exact
   function, type, endpoint or config another chunk creates — with its signature where one exists)
   and what it **produces** for later chunks. A dependency written as "needs the auth work" is
   unusable at implementation time; "consumes `verifyToken(token): Claims` from chunk 2" is not.
4. **Can it be reviewed on its own** by someone who hasn't read the other chunks?
5. **Does it fit one subject?** Types and the code using them are one chunk. A rubric and the tool
   that publishes one of its numbers are one chunk. Two unrelated subjects are two chunks.

## Split it further when

- The acceptance criteria need an "and" between two unrelated subjects.
- The proof for one part cannot run until another part is finished.
- Half of it is mechanical (a rename, a move, a config sweep) and half is a behaviour change —
  those review at completely different speeds, and bundling them buries the risky half.
- You cannot say which single thing would have to be reverted if it turned out wrong.

## How to split a chunk that's still too big

Don't cut at an arbitrary point — cut along one of these axes, and pick the one that yields a slice
worth shipping on its own:

- **Spike** — the part that is research (an unknown to be measured or proven) becomes its own chunk,
  and the rest is planned once its answer is known. Do this when a chunk's real content is "we
  don't know yet".
- **Path** — one user path first, the alternates later (the happy path before the recovery path,
  card payment before vouchers).
- **Interface** — the primary surface first, the secondary ones later (the API before the admin UI,
  one platform before the second).
- **Data** — narrow the data scope (one entity type, one region, one currency) and widen it in a
  later chunk.
- **Rules** — relax a business rule for the first chunk and add it back in the next (no discount
  logic yet, no rate limiting yet), as long as the relaxed version is still shippable.

If none of the five yields a slice you'd ship, the chunk may be **too big for one plan** rather than
too big for one chunk: give it its own plan and its own decomposition (a sub-epic with children of
its own) rather than forcing a cut that produces two unreviewable halves.

## Don't split it when

- The two halves are one decision, and reviewing either alone means reviewing a fiction.
- The split exists only to hit a size number.
- One half would be dead code until the other lands.

Where a chunk is genuinely one subject but still large, say so in its description rather than
forcing a cut — an explicit "this is big and here is why it can't be split" is a better artifact
than two chunks nobody can review separately.

## Anti-patterns

- **Layer slicing.** "The schema", "the API", "the UI" as three chunks: none of them delivers
  anything, all three must land before anything is observable, and the review of each is a review
  of intent rather than behaviour.
- **The step masquerading as a deliverable.** "Investigate X", "refactor Y first", "write the
  tests" — steps of a chunk, not chunks.
- **The chunk that is only a size.** Cutting a capability at an arbitrary line means the seam falls
  wherever the counting stopped, which is exactly where nobody would choose to review it.
- **The twelve-item chain.** See step 5. Usually a decomposition that never questioned the plan's
  own narrative order.

## A worked example

Plan: *"Add multi-currency pricing to the checkout."*

| Chunk | Observably true afterwards | Proof | Depends on |
|---|---|---|---|
| 1 | Money is represented as an amount plus a currency everywhere internally, still single-currency in behaviour | Existing suite green after the type change; new unit tests on the money type | — |
| 2 | Exchange rates are fetched, cached and inspectable | A command prints today's rates; test against a recorded response | — |
| 3 | A product page shows a price in the visitor's currency | Test asserting a converted price renders; screenshot | 1, 2 |
| 4 | An order is stored with the currency it was placed in, and totals reconcile | Test placing an order in two currencies; reconciliation query | 1, 2 |
| 5 | The whole flow works against a real browser and a real rate feed | End-to-end test | 3, 4 |

Note the shape: 1 and 2 are independent and can run in parallel; 3 and 4 are also independent of
each other; only 5 needs both. Chunk 1 deliberately delivers *no* user-visible behaviour change —
it is a precondition chunk (step 4), and its proof is that everything else still works. Chunk 5
carries the phase's proof (step 6).

## This skill's own backlog, as a second example

The five chunks that built `zibby:plan-to-backlog` itself:

| # | Chunk | Why it is its own chunk |
|---|---|---|
| 1 | `todo.py`: `add --ref`, section headings, heading-safe numbering, tests | The only real logic in the plan. Proof is its own test file, no tracker involved. |
| 2 | `zibby:jira`: parent support, an overridable type proposal, pre-supplied research | A capability another chunk consumes; usable the moment it lands. |
| 3 | The `zibby:plan-to-backlog` skill itself | Needs 1 and 2 to exist. Bundling it with either means reviewing a skill and its dependency in one diff. |
| 4 | `zibby:todo-driven-development`: reuse an already-linked issue | A different skill, its own failure mode (an issue already closed), worth landing even if 3 changes shape. |
| 5 | Docs: README, manifests, reference checks | Deliberately last: it describes the other four, so writing it earlier means writing it twice. |

1 and 2 are parallel; 3 blocks on both; 4 and 5 follow.

## One caveat about branch strategy

This skill records order as tracker `Blocks` links only, and `zibby:todo-driven-development`
branches every item off the default branch. For chunks that are genuinely independent — which is
what the checklist above pushes you toward — that is correct. For a chain where a chunk builds on
the previous chunk's code, it means the later chunk gets implemented against a base that doesn't
contain its dependency yet. Stacking branches solves that and costs review complexity — and note that stacking orders
*merges*, not *reviews*: a reviewer can start on an upper chunk before the ones below it land. Name
the situation in the decomposition checkpoint and let the user decide; don't discover it at
implementation time.

## Where these rules come from

Not invented here. The procedure above is a synthesis of practice that predates this skill, and
these are worth reading directly when a decomposition gets hard:

- **INVEST** (Bill Wake) — a chunk should be Independent, Negotiable, Valuable, Estimable, Small,
  Testable. The checklist above is essentially Independent + Testable made concrete.
  <https://agilealliance.org/glossary/invest/>
- **SPIDR** (Mike Cohn) — the five splitting axes above.
  <https://www.mountaingoatsoftware.com/agile/five-simple-but-powerful-ways-to-split-user-stories>
- **The story-splitting flowchart** (Richard Lawrence / Humanizing Work) — a decision tree for
  finding the next vertical slice, used live with a team.
  <https://www.humanizingwork.com/story-splitting-q-and-a/>
- **Walking skeleton** (Alistair Cockburn; Freeman & Pryce, *Growing Object-Oriented Software*) —
  step 1b above. <https://distilledpatterns.org/patterns/walking-skeleton/>
- **Wave execution over a dependency graph** — the shape used by spec-driven tooling such as GitHub
  spec-kit (which marks parallelizable tasks `[P]` and orders foundations before dependents) and
  Kiro's spec workflow (which executes tasks in dependency waves).
  <https://github.com/github/spec-kit>, <https://kiro.dev/docs/specs/>
- **Consumes/Produces contracts between tasks** — from the `superpowers` plugin's `writing-plans`
  skill, which also sizes a task by whether it fits one test cycle rather than by its diff.
  <https://github.com/obra/superpowers>
- **Stacked-change review discipline** — merges are ordered, reviews need not be.
  <https://graphite.com/docs/best-practices-for-reviewing-stacks>
