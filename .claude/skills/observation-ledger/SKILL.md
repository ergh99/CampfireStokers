---
name: observation-ledger
description: Use when running an iterative empirical research/test cycle - repeated rounds of propose a test, someone reports a real-world result, decide the next test from it (in-client API probing, debugging-by-experiment, any investigation where "what actually happened" can only be learned by asking someone to go observe it). Prevents hallucinated or drifted findings by maintaining an append-only, verbatim ledger instead of reconstructing a summary from memory at the end.
---

# Observation Ledger

## When to use this

Any task shaped like: propose a test -> the user (or a tool) reports a
real-world result -> decide the next test based on that result ->
repeat many times. Probing an API inside a running application,
debugging by experiment, and checking behavior on hardware or in a
live environment all have this shape.

Two outcomes are common with this kind of investigation:

- **It works** when each round's commands and results are appended to
  a log as they come in. The final summary is built by quoting that
  log, not by recalling the conversation.
- **It fails** when a long investigation (twenty or so rounds) isn't
  written down until the end. A "confirmed facts" summary built from
  conversational memory picks up claims that were never observed,
  merges rounds that differed, and drops contradictions. The person
  who ran the tests then has to correct it line by line, or can't
  trust any of it.

The difference is not how complex the investigation is. It's whether a
ledger existed and was appended to as each result landed.

## The rule

**Never produce a "summary of findings" by reconstructing from
conversation history. Maintain a ledger file and append to it after
every single reported result, before deciding the next step.** The
ledger is the source of truth. A later summary only ever quotes from it
- it is never assembled from memory, no matter how recent or vivid that
memory feels.

## Setting up the ledger

One file per investigation. Match whatever convention the project
already uses for this kind of artifact; if there is none, use a
Markdown file beside the project's other docs, e.g.
`docs/<topic>-findings.md`. Create it with a
one-line header - what's being investigated, the date - before running
the first test. If a ledger for this exact investigation already
exists, keep appending to that one; don't start a second.

## Entry format

Append this immediately after each result is reported, before anything
else - before reasoning about what it means, before proposing the next
test:

```
### Round N: <short label for what was tested>
Action taken (verbatim): <the exact command/step - copy it, don't paraphrase>
Observed result (verbatim): "<quote the report exactly as given>"
```

Add a third field only when there's something to say beyond the raw
observation, and keep it visibly, structurally separate:

```
Interpretation (not observed - reasoning only): <the inference, explicitly marked as inference>
```

### Example

```
### Round 7: retry the request with the cache cleared first
Action taken (verbatim): clear-cache --all && fetch-report --id 4412
Observed result (verbatim): "cache cleared, then the same timeout after 30s"
Interpretation (not observed - reasoning only): a cold cache still
  times out, which rules out a stale cache entry as the sole cause -
  contradicts the theory from Round 4.
```

### Hard rules for the format

- **"Observed result" is a quote, not a paraphrase.** Shorten with
  ellipses if needed, but never substitute a synonym, never "clean up"
  phrasing, never merge two separate observations into one sentence.
- **Interpretation never hides inside the Observed field.** "The request
  succeeded because the cache was warm" is an interpretation wearing an
  observation's clothes - "the cache was warm" was never itself
  observed, it was inferred from the outcome. Put inferences in their own field, or leave them out.
- **Write the entry before designing the next test.** If a next test is
  being designed and the previous round's entry isn't written yet,
  stop and write it first. Batching several rounds into one write-up
  later is exactly the failure mode this skill exists to prevent.
- **Re-read the ledger before restating anything from it.** Even with
  the ledger open, it's possible to misremember or conflate two rounds
  while reasoning out loud. The written entry is authoritative over any
  restated version of it, including a restatement made moments ago in
  the same conversation.

## Writing the final summary

Read the ledger top to bottom. Every claim in the summary must trace to
a specific round's Observed field - if a claim can't be pointed at a
specific entry, it doesn't go in the summary; say it's unconfirmed
instead of filling the gap with a plausible-sounding guess. Where the
ledger shows contradictory or inconclusive results across rounds, say
so explicitly rather than quietly resolving the contradiction with an
inference - an unresolved contradiction is itself a fact worth keeping,
and smoothing it over is how these summaries go wrong.
