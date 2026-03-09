#!/bin/sh
set -e

# Why this entrypoint exists:
#
# By default Docker containers run as root (uid 0). Claude Code refuses to run
# with --dangerously-skip-permissions when the calling process is root, because
# root already has unrestricted access to the system and skipping all permission
# prompts on top of that would be too dangerous. It exits with code 1.
#
# The "node" user (uid 1000) already exists in the node:* base images and is
# the conventional non-root user for Node containers.
#
# The challenge: mounted volumes (Railway, Docker bind-mounts, etc.) arrive
# owned by root. If we simply put "USER node" in the Dockerfile the server
# would hit "Permission denied" when trying to write to /paperclip.
#
# Solution — two-step privilege drop:
#
#   Container starts (root)
#     └─ this entrypoint (still root)
#          ├─ chown -R node:node /paperclip   ← fix volume ownership
#          └─ exec gosu node <server>
#                  └─ server runs as node (uid 1000)
#                       └─ claude spawns as node ✓
#                            └─ --dangerously-skip-permissions accepted ✓
#
# "gosu" is like "su" but designed for containers: it does a real exec() so
# the server becomes PID 1 running as "node", not a child of a root shell.

# Fix ownership of the data volume so the node user can write to it.
if [ -d "/paperclip" ]; then
  chown -R node:node /paperclip 2>/dev/null || true
fi

# Drop root and exec the server as the node user.
exec gosu node "$@"
