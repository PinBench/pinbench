# Security policy

## Reporting a vulnerability

**Please do not open a public issue.**

Use GitHub's private vulnerability reporting: go to the **Security** tab →
**Report a vulnerability**. It is private to the maintainers, and it gives us a
place to work with you on a fix before anything is public.

Please include:

- What the issue is and roughly how bad you think it is
- Steps to reproduce, ideally with a `.cdl` file or a `curl` command
- Which component — the app, the compile service, or the hosted infrastructure
- Anything you already know about a fix

**What to expect:** an acknowledgement within a few days, and an honest estimate
of the timeline once we understand the report. This is a small project, so
please assume good faith rather than indifference if a reply is slow. We are
happy to credit you in the advisory unless you would rather stay anonymous.

Please give us reasonable time to ship a fix before disclosing publicly.

## Scope

### In scope

- **The compile service** ([`PinBench/compile-service`](https://github.com/PinBench/compile-service)) — this is the most interesting
  target and we know it. It accepts untrusted source and runs a compiler on it.
  Sandbox escapes, resource exhaustion that survives the documented limits,
  bypasses of the rate limiter or origin allow-list, and anything that reads
  files outside a request's temp directory are all in scope.
- **The app** — anything that lets a `.cdl` file or a sketch reach outside the
  workspace, execute host code, or exfiltrate data.
- **Cloud data access** — in the hosted builds, any path that reads or writes
  another user's projects, or widens your own access to a project you do not
  own.

### Not vulnerabilities

Please do not report these — they are deliberate, documented decisions:

- **Firebase API keys inside the hosted builds.** Firebase client keys are
  public by design. They identify a project; they do not authorise anything.
  (A build from this repository has no Firebase configuration at all.)
- **`COMPILE_API_TOKEN` being readable in the web bundle.** It ships in the
  JavaScript, and that is understood. It deters casual scripted abuse; the rate
  limiter and concurrency caps are the actual protection, and they apply to
  every caller regardless of token.
- **Anything against a self-hosted deployment you configured permissively.** The
  compile service ships with safe defaults and warns loudly at startup when
  `ALLOWED_ORIGINS` or `COMPILE_API_TOKEN` is unset. Running it wide open on the
  public internet is a configuration choice, not a vulnerability in this code.
- Missing hardening headers on the marketing site, or reports that consist only
  of an automated scanner's output with no demonstrated impact.

## Running it yourself, safely

If you self-host the compile service, read
[the compile-service README § Security](https://github.com/PinBench/compile-service#-security). The short
version: it cannot sandbox itself. Run it unprivileged, with a read-only root, a
tmpfs `/tmp`, dropped capabilities, memory and PID limits, and no outbound
network — the AVR toolchain is baked into the image, so it never needs any.

## Supported versions

This project is pre-1.0. Only `main` is supported; fixes land there and are not
backported.
