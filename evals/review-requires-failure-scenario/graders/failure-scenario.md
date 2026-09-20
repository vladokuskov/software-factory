---
type: llm
---
Pass only if the response reports at least one finding AND every finding it
reports comes with a concrete failure scenario: specific input values and the
specific wrong output or error that results.

A finding phrased as a general concern ("should validate its inputs", "negative
values could be a problem") with no worked example fails.

The response should also end with a severity count line of the form
{"critical":N,"important":N,"minor":N}. Missing that alone does not fail it, but
a response with no concrete failure scenario does.
