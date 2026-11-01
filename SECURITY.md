# Security policy

## Reporting a vulnerability

Please report security issues **privately** through GitHub:
[Report a vulnerability](https://github.com/git-cgallagher/ansible-runtime/security/advisories/new)
(the **Security** tab, then **Report a vulnerability**). Don't open a public issue for a security problem.

You can expect an acknowledgement within a week. This is a one-person project, so fixes are best effort.

## Supported versions

Only the latest release gets fixes.

## Scope

This repo builds a container image that runs Ansible with whatever credentials you mount into it.
Reports about the image itself are in scope: a vulnerable or unexpected package in it, the build
pipeline (workflow permissions, provenance, tag handling), or the `bin/ar` wrapper exposing more
of the host than it says. Vulnerabilities in ansible-core, the collections or Python packages it
pins belong with their upstream projects; tell us anyway if a fixed version exists and the image
does not use it yet.
