# Security

Project-specific security surface for tandem code reviews. Fill in the sections below and keep this up to date as the stack evolves.

## Stack

<!-- What languages, frameworks, external services does this project use? -->

## Trust Boundaries

<!-- Where does untrusted input enter? User input, external APIs, file uploads, CLI args, env vars, etc. -->

## Checklist

Reviewers check these during REVIEW_CODE and QUALITY_REVIEW:

- [ ] No command injection (unquoted variables in bash, shell=True in python, exec in JS)
- [ ] No secrets in code, logs, or error messages
- [ ] Untrusted input validated at system boundaries
- [ ] File paths validated (no traversal)
- [ ] Dependencies pinned, no unvetted new deps
- [ ] No SQL injection, XSS, or SSRF (if applicable)
