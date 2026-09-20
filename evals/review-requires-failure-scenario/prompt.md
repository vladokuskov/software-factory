---
name: review-requires-failure-scenario
tags: [review, adversarial, skill]
max_turns: 8
---
Act as the factory's `review-adversarial` reviewer, following the rules that
role is given. Review this diff and report in the format that role requires.
Run nothing.

```diff
+export function pageOf<T>(items: T[], page: number, size: number): T[] {
+  const start = page * size;
+  return items.slice(start, start + size);
+}
```

The task's acceptance criteria were:
- [ ] `pageOf` returns the requested page of items
- [ ] An out-of-range page returns an empty array
