#!/usr/bin/env bash

set -o errexit
set -o nounset

# Pull a model from the huggingface model hub
# $1: model repo - the name of the model repo
# $2: model file - the specific model file to pull
# $3: models dir path - the path to the directory where the models are stored
# - Pulls the model from huggingface to the models directory
#   if it is not already available. Path should
#    look like: ${MODELS_DIR_PATH}/${MODEL_REPO}/${MODEL_FILE}
function pull {
	local _MODEL_REPO=$1
	local _MODEL_FILE=$2
	local _MODELS_DIR_PATH=$3

	local MODEL_NAME=${_MODEL_REPO}/${_MODEL_FILE}
	local MODEL_DIR_PATH=${_MODELS_DIR_PATH}/${_MODEL_REPO}
	local MODEL_PATH=${MODEL_DIR_PATH}/${_MODEL_FILE}

	# Check of the model is already downloaded
	if [ -f ${MODEL_PATH} ]; then
		echo "Model already available at path: ${MODEL_PATH}"
		return
	fi
	echo "Pulling model: ${MODEL_NAME} ..."

	huggingface-cli download ${_MODEL_REPO} ${_MODEL_FILE} --local-dir ${MODEL_DIR_PATH} --local-dir-use-symlinks False
}

# Push a model to IPFS as a sqfs immutable file
# $1: model repo - the name of the model repo
# $2: model file - the specific model file to push
# $3: models dir path - the path to the directory where the models are stored
# $4: models json path - the path to the models json file
# - Makes the model into a sqfs file
# - Pushes the model to IPFS
# - Pins the model in Aleph
# - Records the cid of the squashed model + the item hash of the aleph storage message
#   in the models.json file
function push {
	local _MODEL_REPO=$1
	local _MODEL_FILE=$2
	local _MODELS_DIR_PATH=$3
	local _MODELS_JSON_PATH=$4

	local MODEL_NAME=${_MODEL_REPO}/${_MODEL_FILE}
	local MODEL_DIR_PATH=${_MODELS_DIR_PATH}/${_MODEL_REPO}
	local MODEL_PATH=${MODEL_DIR_PATH}/${_MODEL_FILE}

	set +e
	jq -e ".\"${MODEL_NAME}\"" ${_MODELS_JSON_PATH}
	if [ $? -eq 0 ]; then
		echo "Model already pushed"
		return
	fi
	set -e

	# Squash the model
	if [ ! -f ${MODEL_PATH}.sqfs ]; then
		set +e
		mksquashfs ${MODEL_PATH} ${MODEL_PATH}.sqfs
		set -e
	fi

	# Push the model and remove the local squashed model
	local MODEL_SQFS_CID=$(curl -X POST -F "file=@${MODEL_PATH}.sqfs" https://ipfs.aleph.cloud/api/v0/add | jq -r .Hash)
	# local MODEL_SQFS_CID=$(curl -X POST -F "file=@README.md" https://ipfs.aleph.cloud/api/v0/add | jq -r .Hash)
	rm ${MODEL_PATH}.sqfs
	echo "Model sqfs pushed to IPFS with CID: ${MODEL_SQFS_CID}"

	local MODEL_SQFS_ITEM_HASH=$(aleph file pin ${MODEL_SQFS_CID} | jq -r .item_hash)

	echo "Model sqfs stored in message with CID: ${MODEL_SQFS_STORE_CID}"

	# Record the cid of the model# Record the cid of the model
	jq --arg cid "$MODEL_SQFS_CID" --arg hash "$MODEL_SQFS_ITEM_HASH" '.["'"$MODEL_NAME"'"] += {"sqfs_cid": $cid, "sqfs_item_hash": $hash}' ${_MODELS_JSON_PATH} >${_MODELS_JSON_PATH}.tmp
	mv ${_MODELS_JSON_PATH}.tmp ${_MODELS_JSON_PATH}
}

$@
