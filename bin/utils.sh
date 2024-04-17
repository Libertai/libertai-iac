#!/usr/bin/env bash

set -o errexit
set -o nounset

# Check if required dependencies are installed
# - huggingface-cli
# - git
# - docker or podman
# - jq
# - curl
# - aleph
# - mksquashfs
# - unsquashfs
function check-dependencies {
	if ! command -v huggingface-cli &>/dev/null; then
		echo "huggingface-cli could not be found"
		exit 1
	fi
	if ! command -v git &>/dev/null; then
		echo "git could not be found"
		exit 1
	fi
	if ! command -v jq &>/dev/null; then
		echo "jq could not be found"
		exit 1
	fi
	if ! command -v curl &>/dev/null; then
		echo "curl could not be found"
		exit 1
	fi
	if ! command -v aleph &>/dev/null; then
		echo "aleph could not be found"
		exit 1
	fi
	if ! command -v unsquashfs &>/dev/null; then
		echo "squashfs could not be found"
		exit 1
	fi
	if ! command -v mksquashfs &>/dev/null; then
		echo "mksquashfs could not be found"
		exit 1
	fi
	if ! command -v docker &>/dev/null && ! command -v podman &>/dev/null; then
		echo "docker or podman could not be found"
		exit 1
	fi
}

$1
