# Locale: English (`en`)

Everything language-dependent in the rendering contract. `references/format.md` owns the structure
and overrides this file wherever the two could be read as disagreeing about layout.

**Output language: English.** Write the whole message in English, including descriptions rewritten
from Jira summaries written in another language. Identifiers, file names, commands and branch names
stay exactly as they are.

## Descriptions

- **Start a description lowercase.** It is a noun phrase, not a sentence — `split of lint and
  types`, not `Split of lint and types`. Identifiers keep their own case (`check:format`,
  `oclif.ts`), and so do proper nouns.
- **`merged` reads as finished**: `dropped "oclif" from the CLI file names`, `rename done`.
- **`created` reads as in progress**: `work in progress on ...`, `PR open for ...`.

Worked bullets:

```
- [PROJ-629](https://example.atlassian.net/browse/PROJ-629): dropped "oclif" from the CLI file names
- [partner-cli#30](https://github.com/acme/partner-cli/pull/30): check:format gate in verify, turbo and CI
- pinning down what counts as a code-review finding for the addon CLI agents
```

## Code review phrase

`CR for <name>`, and nothing else on the line:

```
- [cms4#44224](https://github.com/acme/cms4/pull/44224): CR for Martin
```

The name is the PR author's **first name**, taken from `prAuthor` and used as it is written. A bare
GitHub login goes in verbatim.

## Meetings

Heading: `Meetings`. Bullet: `<hours>h of meetings`, hours written with a decimal point —
`1h`, `2.5h`, `4h`. Under half an hour still prints `0.5h`.

Four or fewer meetings, named:

```
Meetings
- 1h of meetings (FE Guild Refinement)
```

```
Meetings
- 3.5h of meetings (DevRel standup, FE Guild Refinement, P&T all-hands)
```

Five or more, or any window longer than a day — hours only:

```
Meetings
- 5h of meetings
```

## Review count phrase

For the 8+ day density, one bullet per repo: `<n> code reviews`.

```
- 14 code reviews
```
