#!/usr/bin/env bash
printf 'FOREMAN GATE — IDEA DETECTION: If the user'\''s message describes a gap, problem, desired user behaviour, or feature request, you MUST: (1) run `gh issue list --state open --search "<keywords>"` to check for duplicates, (2) if no duplicate exists, trigger grill-with-docs automatically before responding. Do not skip this gate.\n'
