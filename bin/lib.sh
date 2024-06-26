#!/usr/bin/env bash

set -o errexit

source .env

# Check dependencies
./bin/utils.sh check-dependencies

function pull-model {
	./bin/model.sh pull $MODEL_REPO $MODEL_FILE $MODELS_DIR_PATH
}

function push-model {
	./bin/model.sh push $MODEL_REPO $MODEL_FILE $MODELS_DIR_PATH models.json
}

function pull-runtime {
	./bin/runtime.sh pull $RUNTIME_ID $RUNTIME_CID $RUNTIMES_DIR_PATH
}

function push-engine {
	# TODO: for some reason, passing the build and run commands
	#  is not working -- they get interpreted as split commands in the shell.
	#   For now this function just sources the engine build and run commands itself.
	#    This is not as clean as it could be, but it works for now.
	# Build our engine within our runtime
	./bin/runtime.sh build-and-deploy-llm-engine \
		$RUNTIME_ID \
		$MODEL_REPO \
		$MODEL_FILE \
		models.json \
		$LLM_ENGINE_BUILDS_DIR_PATH \
		$LLM_ENGINE_REPO_URL \
		$LLM_ENGINE_REPO_VERSION
}

$1
