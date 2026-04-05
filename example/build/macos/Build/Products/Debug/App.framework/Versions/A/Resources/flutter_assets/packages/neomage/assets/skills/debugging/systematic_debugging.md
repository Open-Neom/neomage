# Systematic Debugging — Root Cause Analysis

## Purpose

Find and fix bugs efficiently through structured investigation rather than random changes.

## Debug Process

### 1. Reproduce
- Get exact steps to reproduce
- Identify: always happens? intermittent? environment-specific?
- Create minimal reproduction case

### 2. Isolate
- Binary search: comment out half the code, does it still fail?
- Check recent changes: `git log`, `git bisect`
- Isolate variables: input data, environment, timing

### 3. Hypothesize
- Form 2-3 hypotheses about the root cause
- Rank by likelihood
- Design a test for the most likely hypothesis

### 4. Verify
- Add targeted logging/breakpoints
- Test hypothesis with controlled experiment
- If wrong, move to next hypothesis

### 5. Fix
- Fix the root cause, not the symptom
- Add a regression test
- Check for similar patterns elsewhere in the codebase

### 6. Document
- What was the bug?
- What caused it?
- How was it fixed?
- How to prevent similar bugs?

## Common Bug Categories

| Category | Symptoms | Investigation |
|----------|----------|--------------|
| Null reference | Crash, NPE | Check optional chains, null assertions |
| Race condition | Intermittent, timing-dependent | Add logging with timestamps, check async flows |
| State mutation | Stale UI, wrong values | Trace state changes, check immutability |
| Off-by-one | Wrong counts, missing items | Check loop bounds, index math |
| Type coercion | Silent wrong values | Check type conversions, JSON parsing |

## Tools

- **Dart**: `dart analyze`, DevTools, Observatory
- **Flutter**: Widget inspector, Performance overlay, `debugPrint`
- **Git**: `git bisect`, `git log -p`, `git blame`
- **General**: Rubber duck debugging, sleep on it, explain to someone else
