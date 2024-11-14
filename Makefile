include project.env
export


.PHONY: help prepare clean build test package push deploy launch inspect

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "Usage: make \033[36m<target>\033[0m\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

prepare: ## Prepare the project by downloading dependencies and common scripts
	@./scripts/prepare.sh

clean: ## Remove temporary files
	@./scripts/downloads/${BUILD_SCRIPTS_REPO_NAME}/src/cicd/${PROJECT_TYPE}/clean.sh

build: ## Build the repo's artifacts and image
	@./scripts/downloads/${BUILD_SCRIPTS_REPO_NAME}/src/cicd/${PROJECT_TYPE}/build.sh

test: ## Run tests
	@./scripts/downloads/${BUILD_SCRIPTS_REPO_NAME}/src/cicd/${PROJECT_TYPE}/test.sh

package: ## Package the code as an artifact and/or in a docker image
	@./scripts/downloads/${BUILD_SCRIPTS_REPO_NAME}/src/cicd/${PROJECT_TYPE}/package.sh

push: ## Push image to docker registry and artifacts to repository
	@./scripts/downloads/${BUILD_SCRIPTS_REPO_NAME}/src/cicd/${PROJECT_TYPE}/push.sh

deploy: ## Deploy artifacts/images/libraries
	@./scripts/downloads/${BUILD_SCRIPTS_REPO_NAME}/src/cicd/${PROJECT_TYPE}/deploy.sh

launch: ## Launch the app/service within a Docker container
	@./scripts/downloads/${BUILD_SCRIPTS_REPO_NAME}/src/cicd/${PROJECT_TYPE}/launch.sh

inspect: ## Enter the Docker container at the builder stage for inspection
	@./scripts/downloads/${BUILD_SCRIPTS_REPO_NAME}/src/cicd/${PROJECT_TYPE}/inspect.sh
