# 1. Deploy with plain rsync, without host key checks

Date: 2026-10-20

## Context

Deploy v2.0.0 uploads through `easingthemes/ssh-deploy@main`, a third-party action on a floating branch that receives the deploy SSH key. It copied the whole checkout, so `pipeline.json` (with the SSH host, port and user) ended up publicly readable on 8 of 9 live sites. It also connects with `StrictHostKeyChecking=no`, so it never checks that it is talking to the real server.

Checking host keys was tried for v2.1.0, first as a required `host_key` in `pipeline.json`, then as a shared organization list. Both made setting up a project harder, and easy setup is the main reason this pipeline exists.

## Decision

v2.1.0 drops the action and calls `rsync` and `ssh` directly, both of which come with GitHub's Ubuntu runners. The release is assembled in a separate folder with a fixed exclude list before anything is uploaded. Every other third-party action is pinned to a commit SHA.

The server's host key is deliberately not checked, the same as in v2.0.0. `pipeline.json` keeps the same fields as v2.0.0.

## Consequences

- No third-party code handles the SSH key.
- Moving a project from v2.0.0 to v2.1.0 needs no change to `pipeline.json`.
- If the IP or DNS name of a server ever points at another machine, a deploy uploads the release there and reports success. The SSH key itself can't be reused against the real server. Revisit this decision if a project ever needs that guarantee.
- Rsync options are now ours to maintain. They live in one step of the workflow and are covered by `test/run.sh`.
