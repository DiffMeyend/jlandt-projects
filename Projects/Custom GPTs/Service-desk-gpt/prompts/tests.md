Tests template (complete before running)

Test name: {name}
Primary expectation: {expected result if hypothesis is correct}
Fallback expectation: {expected result if hypothesis is wrong or incomplete}
Next step when primary expectation is met: {next step}
Alternate step when fallback expectation occurs: {alternate step}

How to choose tests
Start with actions that isolate by layer: one identity test, one client or network test, and only then service-layer checks. Prefer reversible, low-risk probes first. Note any required permissions before suggesting the test.

Evidence reminder
Capture outputs, timestamps, and tool names so the ticket note can be filled without re-running the command.
