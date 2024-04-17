#!/usr/bin/env bash

set -o errexit
set -o nounset

# Determine which container runtime to use
function container-runtime {
	if which podman >/dev/null 2>&1; then
		local _CONTAINER_RUNTIME=podman
	elif which docker >/dev/null 2>&1; then
		local _CONTAINER_RUNTIME=docker
	else
		echo "No container runtime found. Please install docker or podman."
		exit 1
	fi
	# Set the CONTAINER_RUNTIME variable
	echo $_CONTAINER_RUNTIME
}

function runtime-image-name {
	local _RUNTIME_ID=$1

	echo "$_RUNTIME_ID-aleph-build-env"
}

# Pull a runtime from Aleph and keep it locally
# $1: runtime ID
# $2: runtime cid
# $3: runtimes directory path
function pull {
	local _RUNTIME_ID=$1
	local _RUNTIME_CID=$2
	local _RUNTIMES_DIR_PATH=$3

	mkdir -p $_RUNTIMES_DIR_PATH
	# What container runtime we're using
	local CONTAINER_RUNTIME=$(container-runtime)
	# What we'll call the container we import from the runtime
	local RUNTIME_IMAGE_NAME=$(runtime-image-name $_RUNTIME_ID)
	# Where we'll save the squashed runtime
	local SQUASHED_RUNTIME_NAME="$_RUNTIME_ID-runtime.sqfs"
	local SQUASHED_RUNTIME_PATH="$_RUNTIMES_DIR_PATH/$SQUASHED_RUNTIME_NAME"
	# Where we'll save the unsquashed runtime
	local UNSQUASHED_RUNTIME_NAME="$_RUNTIME_ID-runtime"
	local UNSQUASHED_RUNTIME_PATH="$_RUNTIMES_DIR_PATH/$UNSQUASHED_RUNTIME_NAME"

	# First determine if we even need to pull the runtime

	# Check if we have an appropriately named image available
	if ${CONTAINER_RUNTIME} image ls | grep ${RUNTIME_IMAGE_NAME} >/dev/null; then
		echo "Runtime already available locally as image: $RUNTIME_IMAGE_NAME"
		return
	fi

	# Check if maybe we haven't built the image, but still have the squashed runtime
	# Kinda silly but we'll check anyway
	if [ -d "$UNSQUASHED_RUNTIME_PATH" ]; then
		echo "Runtime $_RUNTIME_ID already exists at $UNSQUASHED_RUNTIME_PATH"
	else
		echo "Pulling runtime $_RUNTIME_ID to $SQUASHED_RUNTIME_PATH ..."
		# TODO: I should be using the aleph CLI for this. For now, i just know the CID
		# RUNTIME_CID=$(aleph message get $_RUNTIME_ID | jq -r '.content.item_hash')
		curl https://ipfs.aleph.cloud/ipfs/$_RUNTIME_CID -o $SQUASHED_RUNTIME_PATH
		if [ $? -ne 0 ]; then
			echo "Failed to pull runtime $_RUNTIME_ID"
			exit 1
		fi
		echo "Unsquashing runtime $SQUASHED_RUNTIME_PATH to $UNSQUASHED_RUNTIME_PATH ..."
		# TODO: janky but it works. Would like to just unsquash to the right directory
		CURRENT_DIR=$(pwd)
		cd $_RUNTIMES_DIR_PATH
		set +e
		unsquashfs -ig $SQUASHED_RUNTIME_NAME
		set -e
		echo "Unsquash done"
		mv squashfs-root $UNSQUASHED_RUNTIME_NAME
		cd $CURRENT_DIR
	fi

	# Now we should have the squashed runtime available within the runtimes directory
	# Now we can proceed to unsquash the runtime and import it into a container
	echo "Importing runtime $UNSQUASHED_RUNTIME_PATH into container $RUNTIME_IMAGE_NAME ..."
	tar -C $UNSQUASHED_RUNTIME_PATH -c . | ${CONTAINER_RUNTIME} import - $RUNTIME_IMAGE_NAME

	# TODO: debatable whether we should keep the unsquashed runtimes here
	echo "Done pulling and importing runtime $_RUNTIME_ID"
}

# Build an LLM engine using the specified runtime
# $1: runtime CID
# $2: LLM engine repo URL
# $3: LLM engine repo version
# $4: LLM engine build command
# $5: LLM engine run command
# $6: LLM engine builds directory path
# - Pulls the correct repo locally
# - Compiles the LLM engine using the runtime
# - Saves the resulting binary to the specified directory. It should be named
#   according to the repo name and the runtime CID:
#    ${LLM_ENGINE_BUILDS_DIR_PATH}/${RUNTIME_CID}/${LLM_ENGINE_REPO_NAME}
function build-and-deploy-llm-engine {
	local _RUNTIME_ID=$1
	local _MODEL_REPO=$2
	local _MODEL_FILE=$3
	local _MODEL_JSON_PATH=$4
	local _LLM_ENGINE_BUILDS_DIR_PATH=$5
	local _LLM_ENGINE_REPO_URL=$6
	local _LLM_ENGINE_REPO_VERSION=$7
	local _LLM_ENGINE_BUILD_COMMAND=$8
	local _LLM_ENGINE_RUN_COMMAND=$9

	# TODO: I should probably also name this according to repo version
	#  but for now this is fine

	repo_name="${_LLM_ENGINE_REPO_URL##*/}"
	local LLM_ENGINE_REPO_NAME="${repo_name%.*}"
	local LLM_ENGINE_BUILD_PATH="$_LLM_ENGINE_BUILDS_DIR_PATH/$_RUNTIME_ID/$LLM_ENGINE_REPO_NAME"
	local CONTAINER_RUNTIME=$(container-runtime)
	local RUNTIME_IMAGE_NAME=$(runtime-image-name $_RUNTIME_ID)
	local MODEL_NAME=${_MODEL_REPO}/$_MODEL_FILE}

	echo "Building LLM engine $_LLM_ENGINE_REPO_URL using runtime $_RUNTIME_ID ..."

	# If the repo is not already cloned, clone it
	if [ ! -d "$LLM_ENGINE_BUILD_PATH/llm-engine" ]; then
		git clone $_LLM_ENGINE_REPO_URL $LLM_ENGINE_BUILD_PATH/llm-engine
	fi
	# Pull the LLM engine repo
	CURRENT_DIR=$(pwd)
	cd $LLM_ENGINE_BUILD_PATH/llm-engine
	git checkout $_LLM_ENGINE_REPO_VERSION
	cd $CURRENT_DIR

	# Write out a build script to the repo
	echo "#!/bin/bash" >$LLM_ENGINE_BUILD_PATH/build.sh
	echo "apt update && apt install build-essential -y" >>$LLM_ENGINE_BUILD_PATH/build.sh
	echo "cd /opt/llm-engine" >>$LLM_ENGINE_BUILD_PATH/build.sh
	echo "$_LLM_ENGINE_BUILD_COMMAND" >>$LLM_ENGINE_BUILD_PATH/build.sh
	chmod u+x $LLM_ENGINE_BUILD_PATH/build.sh

	${CONTAINER_RUNTIME} run \
		-v ${LLM_ENGINE_BUILD_PATH}:/opt/ \
		--rm -t \
		--env SHELL=/bin/bash \
		$RUNTIME_IMAGE_NAME "/opt/build.sh"

	# Kinda janky, but we know llama cpp has extra files we don't need
	#  We should probably just know where the binary we need is, and copy it
	#   but this works for now
	rm -rf $LLM_ENGINE_BUILD_PATH/llm-engine/models

	echo "Deploying llm engine on aleph ..."

	# Write out a run script to the repo
	# TODO: This is a bit janky, but it works for now
	echo "#!/bin/bash" >$LLM_ENGINE_BUILD_PATH/llm-engine/entrypoint.sh
	echo "$_LLM_ENGINE_RUN_COMMAND /models/$_MODEL_FILE" >>$LLM_ENGINE_BUILD_PATH/llm-engine/entrypoint.sh
	chmod u+x $LLM_ENGINE_BUILD_PATH/llm-engine/entrypoint.sh

	# Get the item hash of the model by its name
	set +e
	MODEL_ITEM_HASH=jq ".\"${MODEL_NAME}\".sqfs_item_hash" $_MODEL_JSON_PATH
	set -e
	if [ -z "$MODEL_ITEM_HASH" ]; then
		echo "Error: Model item hash not found"
		exit 1
	fi

	# TODO: better configuration for vcpu and ram
	aleph program upload $LLM_ENGINE_BUILD_PATH/llm-engine entrypoint.sh \
		--runtime=$_RUNTIME_ID --memory=8192 --vcpus=8 --timeout-seconds=300 \
		--immutable-volume ref=$MODEL_ITEM_HASH,use_latest=true,mount=/models

}

$@
