---
name: debugging-discipline
description: "Systematic root-cause debugging on any failure — reproduce first (as a failing test where possible), read the whole log first-error-first, one falsifiable hypothesis at a time, fix the cause not the symptom, remove all instrumentation before commit. Includes the Unity annex: Editor.log/Player.log, adb logcat, IL2CPP stack traces, domain-reload and fake-null traps. Use whenever a test fails unexpectedly, a bug is reported, or observed behavior contradicts expectations."
---

# Debugging Discipline

`engineering-philosophy` says *Investigate, Don't Mask*; this skill is the procedure. Debugging is hypothesis testing, not code roulette: every change you make while debugging is an experiment with a stated prediction, and experiments that fail get reverted, not stacked.

## The loop

1. **Reproduce.** Build the smallest deterministic repro. For logic bugs that is a failing EditMode test ([[running-tdd-cycles]] — the repro *becomes* the regression test and stays after the fix). If you cannot reproduce it, you are not debugging yet — gather evidence until you can.
2. **Evidence.** Read the **whole** log, not the last line. Note the exact message, the first frame of the stack that is project code, and what changed since it last worked (`git log`/`git diff` against the last known-good state).
3. **Hypothesis.** State one falsifiable cause *before* touching code: "X is null here because Y runs before Z." If you can't state it, go back to evidence.
4. **Experiment.** The smallest probe that can prove the hypothesis wrong: an assertion, one log line at a boundary, a bisect step. Change **one variable per experiment**.
5. **Fix the cause.** No defensive `try/catch`, null guard, retry, or `Thread.Sleep` to make the symptom disappear — that's masking, and the bug ships.
6. **Verify.** The repro test passes; the full suite is green ([[unity-testing]] headless run for Unity projects).
7. **Clean up.** Remove every temporary log/probe; keep the regression test. The diff a reviewer sees contains the fix and the test, nothing else.

## Evidence rules

- **First error wins.** Compile errors, exceptions, and import failures cascade; everything after the first is usually noise. Fix #1, re-run, re-read.
- **Verify the report.** Reproduce what the user described before trusting the framing — the reported symptom and the actual defect often differ.
- **Diff against known-good.** "It worked yesterday" is a bisect invitation: `git bisect run <test command>` with the repro test finds the commit mechanically.
- Bisection also applies to data (halve the input) and code paths (disable half the pipeline) when history doesn't localize it.

## Instrumentation rules

- Prefix every temporary log with one greppable marker (e.g. `[DBG]`) so cleanup is a single search — and grep for it before committing.
- A failed experiment is **reverted immediately**. Two stacked failed hypotheses produce a state nobody understands.
- Repeated printf-cycles on the same spot mean the probe is wrong — assert the invariant instead of eyeballing values.

## When stuck

After ~3 failed hypotheses: stop, write down what is known / what is ruled out / what evidence is missing, widen instrumentation to the system boundaries (inputs in, outputs out), and if the missing evidence only the user can produce (device, repro steps, save file) — ask for it with a specific request. Don't loop silently.

## Unity annex

- **Log locations** per OS and the grep patterns that matter: [unity-testing/reference/unity-logs.md](../unity-testing/reference/unity-logs.md). Batchmode runs log wherever `-logFile` pointed; the Console mirrors into `Editor.log`.
- **Device logs:** Android — `adb logcat -s Unity`; iOS — Xcode devices console. A crash with no managed stack on IL2CPP needs the build's symbols (keep `symbols.zip` / use a development build while diagnosing).
- **"Works in editor, broken in build":** managed stripping (`link.xml`/`[Preserve]`), `#if UNITY_EDITOR` paths, Addressables content out of date — the [[unity-build]] failure list is the checklist.
- **"Works on first play only":** static state surviving disabled domain reload — reset via `[RuntimeInitializeOnLoadMethod]` ([[unity-conventions]]).
- **`NullReferenceException` on a destroyed object:** Unity's fake-null means the object existed and was destroyed — that's a lifetime bug: a tween, subscription, or async continuation outliving its owner. The lifecycle rules in [[unity-dotween]], [[unity-unirx]], and [[unity-unitask]] are the usual suspects, in that order.
- **Time-dependent bugs:** check `Time.timeScale`, scaled-vs-unscaled delay types, and `FixedUpdate`-vs-`Update` ordering before blaming logic.
- **In ecslite projects:** a value that "doesn't change" is almost always a struct copy without `ref`, and behavior differing between builds is DEBUG-vs-RELEASE sanitize checks — [[ecslite-conventions]] both times.

## Anti-patterns

- Shotgun debugging — changing several things, seeing green, not knowing which change mattered.
- Guarding the symptom (`if (x != null)`) instead of finding why `x` is null.
- Adding a retry/sleep to make a flaky test pass — the flake is the bug.
- Modifying the test until it passes ([[running-tdd-cycles]]: go back to RED instead).
- Leaving `Debug.Log`/`[DBG]` probes in the committed diff.
- Closing with "cannot reproduce" while the user can — that means your evidence is incomplete, not that the bug is gone.
- Debugging in RELEASE / with sanitize checks off, then being surprised nothing throws.

## Verification checklist

- [ ] A deterministic repro existed before the fix; for logic bugs it is now a committed regression test.
- [ ] The fix addresses the stated root cause, not the symptom; no new defensive catch/guard masks it.
- [ ] Each experiment tested one hypothesis; failed experiments were reverted.
- [ ] All temporary instrumentation removed (grep for the `[DBG]` marker is clean).
- [ ] Full test suite green after the fix.
- [ ] If the bug was build/platform-specific, verified on that path ([[unity-build]] / device log), not just in-editor.