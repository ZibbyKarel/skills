# Locale: Czech (`cs`)

Everything language-dependent in the rendering contract. `references/format.md` owns the structure
and overrides this file wherever the two could be read as disagreeing about layout.

**Output language: Czech.** Write the whole message in Czech, including descriptions rewritten from
English PR titles. Identifiers, file names, commands and branch names stay exactly as they are.

## Descriptions

- **Start a description lowercase.** It is a noun phrase, not a sentence — `rozdělení lint a typů`,
  not `Rozdělení lint a typů`. Identifiers keep their own case (`check:format`, `oclif.ts`), and so
  do proper nouns.
- **`merged` reads as finished**: `dodělané`, `sjednocené`, `přejmenování ... hotové`.
- **`created` reads as in progress**: `rozpracované`, `otevřené PR na ...`, `pracuju na`.

Worked bullets:

```
- [PROJ-629](https://example.atlassian.net/browse/PROJ-629): odstranění "oclif" z názvu souborů v CLI
- [partner-cli#30](https://github.com/acme/partner-cli/pull/30): gate na check:format ve verify, turbu a CI
- ladění definice "co je code-review finding" pro agenty na addon CLI
```

## Code review phrase

`CR pro <jméno>`, and nothing else on the line:

```
- [cms4#44224](https://github.com/acme/cms4/pull/44224): CR pro Martina
```

The name is the PR author's **first name in the accusative** — `pro Michala`, `pro Romana`,
`pro Tomáše`, `pro Martina`. Take the first name from `prAuthor` and decline it. A bare GitHub
login goes in verbatim, undeclined.

## Meetings

Heading: `Meetingy`. Bullet: `<hours>h meetingů`, hours written Czech style with a comma —
`1h`, `2,5h`, `4h`. Under half an hour still prints `0,5h`.

Four or fewer meetings, named:

```
Meetingy
- 1h meetingů (FE Guild Refinement)
```

```
Meetingy
- 3,5h meetingů (DevRel standup, FE Guild Refinement, P&T all-hands)
```

Five or more, or any window longer than a day — hours only:

```
Meetingy
- 5h meetingů
```

## Review count phrase

For the 8+ day density, one bullet per repo: `<n> code reviews` — the English term is what the room
says, so it is not translated.

```
- 14 code reviews
```
