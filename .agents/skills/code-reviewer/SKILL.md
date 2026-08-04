---
name: code-reviewer
description: Use when asked to review code, find bugs, check for security issues, or improve code quality. Reviews for logic errors, security vulnerabilities, performance issues, and style violations.
---

# Code Review Skill

## Review Checklist

### 1. Logic & Bugs

- Off-by-one errors
- Null/None handling
- Edge cases not covered
- Incorrect conditionals

### 2. Security

- Hardcoded secrets or credentials
- Input not validated or sanitized
- SQL injection or injection risks
- Sensitive data exposed in logs

### 3. Performance

- Unnecessary loops or repeated computation
- Missing caching opportunities
- N+1 query patterns
- Large objects held in memory unnecessarily

### 4. Style & Maintainability

- Function/variable names are clear and consistent
- Functions do one thing
- Dead code or commented-out blocks
- Missing or outdated docstrings

## Output Format

Group findings by severity:

**Critical** – Must fix before merge
**Warning** – Should fix, notable risk
**Suggestion** – Nice to have, low priority

For each finding, provide:

- Location (file + line if known)
- What the issue is
- Suggested fix with code example
