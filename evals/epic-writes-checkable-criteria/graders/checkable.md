---
type: llm
---
Pass only if EVERY criterion listed is checkable without reading the diff: each
one names an observable input and an observable output, or an observable state
change.

Concretely, these pass: "`notes rm n1` prints `removed n1`", "`notes rm n9`
prints `no such note: n9` and exits 0", "a removed note no longer appears in
`notes list`".

These fail: "handles errors properly", "works correctly", "is well tested",
"follows existing patterns", "the code is clean". Any single criterion of that
shape fails the whole response.

The response must also cover at least one failure or edge case, not only the
happy path.
