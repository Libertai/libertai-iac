#!/usr/bin/env bash

set -o errexit

source .env

# Check dependencies
./bin/utils.sh check-dependencies

# Pull our model
./bin/model.sh pull $MODEL_REPO $MODEL_FILE $MODELS_DIR_PATH

# Push our packaged model to Aleph
./bin/model.sh push $MODEL_REPO $MODEL_FILE $MODELS_DIR_PATH models.json

# Pull our base runtime image
./bin/runtime.sh pull $RUNTIME_CID $RUNTIMES_DIR_PATH

# Build our engine within our runtime
./bin/runtime.sh build-and-deploy-llm-engine \
	$RUNTIME_ID \
	$RUNTIME_CID \
	$MODEL_REPO \
	$MODELS_FILE \
	models.json \
	$LLM_ENGINE_BUILDS_DIR_PATH \
	$LLM_ENGINE_REPO_URL \
	$LLM_ENGINE_REPO_VERSION \
	"$LLM_ENGINE_BUILD_COMMAND"
