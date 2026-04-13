# Prompt Engineering — Systematic Prompt Design

## Purpose

Design, test, and iterate on prompts that produce reliable, high-quality outputs from language models.

## Core Techniques

**1. Role Definition**: Set a clear persona with expertise, constraints, and output format expectations.

**2. Chain of Thought (CoT)**: Ask the model to "think step by step" for complex reasoning tasks. Reduces errors in math, logic, and multi-step problems.

**3. Few-Shot Examples**: Provide 2-5 input/output examples that demonstrate the desired pattern. Examples should cover edge cases.

**4. Output Formatting**: Specify exact format (JSON, markdown, bullet points). Use delimiters like ```json or XML tags to structure output.

**5. Constraint Injection**: Explicitly state what NOT to do. "Do not apologize", "Do not use placeholder text", "Always include error handling".

**6. Decomposition**: Break complex prompts into sequential steps. Each step builds on the previous output.

## Anti-Patterns

- Vague instructions ("make it better")
- Over-constraining (20+ rules that conflict)
- No examples for format-sensitive tasks
- Ignoring model temperature/sampling settings
- Not testing with adversarial inputs

## Evaluation

- Test with 10+ diverse inputs
- Check for consistency across runs
- Measure against success criteria
- A/B test prompt variations
