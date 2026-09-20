---
name: review-requires-failure-scenario
tags: [review, adversarial]
max_turns: 8
---
Act as the factory's adversarial reviewer. Review this diff and report your
findings in the format your role requires.

```diff
+export function pageOf<T>(items: T[], page: number, size: number): T[] {
+  const start = page * size;
+  return items.slice(start, start + size);
+}
```

The acceptance criteria for the task were:
- [ ] `pageOf` returns the requested page of items
- [ ] An out-of-range page returns an empty array
