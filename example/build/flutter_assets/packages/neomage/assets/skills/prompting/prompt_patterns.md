# Prompt Engineering Patterns

Advanced techniques to maximize LLM performance, reliability, and controllability in production.

- Few-shot learning: select examples by semantic similarity or diversity sampling; balance count with context window; include input-output pairs with edge cases
- Chain-of-thought: zero-shot ("Let's think step by step"), few-shot (with reasoning traces), self-consistency (sample multiple paths and vote)
- Prompt optimization: iterate rapidly, A/B test variations, measure accuracy/consistency/latency/token usage, reduce tokens without quality loss
- Template systems: variable interpolation, conditional sections, multi-turn conversation templates, role-based composition, modular components
- System prompt design: set behavior/constraints, define output format, establish role/expertise, include safety guidelines, provide context
- Instruction hierarchy: [System Context] -> [Task Instruction] -> [Examples] -> [Input Data] -> [Output Format]
- Progressive disclosure: start simple (direct instruction), add constraints, add reasoning steps, add examples -- only escalate complexity when needed
- Error recovery: include fallback instructions, request confidence scores, ask for alternative interpretations, specify how to indicate missing info
- Best practices: be specific, show don't tell (examples > descriptions), test extensively, iterate rapidly, version control prompts, document intent
- Common pitfalls: over-engineering simple tasks, example pollution (mismatched examples), context overflow, ambiguous instructions, ignoring edge cases
