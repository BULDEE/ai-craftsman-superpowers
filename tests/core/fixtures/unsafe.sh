#!/usr/bin/env bash
# Fixture: deliberately in breach of SH001, which wants nounset declared.
# Used to prove a pack beyond symfony/react reaches the FileChanged hook.
#
# Do not name the missing options in this comment: the validator scans the whole
# file, so writing them here would satisfy the rule this fixture must violate.
echo "this script declares no safety options on purpose"
