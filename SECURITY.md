# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in RackStack, please report it responsibly.

**Do NOT open a public GitHub issue for security vulnerabilities.**

Instead, email: **security@abider.org**

Include:
- Description of the vulnerability
- Steps to reproduce
- Affected version(s)
- Impact assessment (if known)

You should receive a response within 48 hours. We'll work with you to understand the issue and coordinate a fix before any public disclosure.

## Scope

RackStack runs with Administrator privileges on Windows Server. Security issues of particular concern include:

- Command injection via user input or `defaults.json` fields
- Credential exposure in logs, exports, or error messages
- Privilege escalation beyond intended Administrator scope
- Unsafe file operations (path traversal, symlink attacks)
- Secrets leaking into git history or exported configurations

## defaults.json

The `defaults.json` file may contain sensitive data (Cloudflare Access credentials, KMS keys). It is gitignored by default and should never be committed to public repositories. The `defaults.example.json` file contains only placeholder values.

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.x     | Yes       |
| < 1.0   | No        |
