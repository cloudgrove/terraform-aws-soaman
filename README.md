# About this repo
This repo is the backbone of every new project. Please take the time to understand its scaffolding.

```
├── Makefile         # Make commands such as test, build, push, and deploy
├── project.env      # Shell vars, such as `PROJECT_TYPE`, used by Makefile and scripts
├── README.md        # Information on this repo
├── .gitignore
├── .circleci
│   └── config.yml   # CircleCI config file
└── scripts
│   ├── prepare.sh   # Script for setting up the project with useful scripts
│   └── ...          # Other scripts as needed
└── src              # Project main source code
    └── ...
```

# Before you start developing
Please follow these steps as soon as the repo is created:

1. Go to `project.env` and specify the project type.

1. Add the necessary dependencies and package installations in `Dockerfile`.

1. Expand the `docker-compose` config to include other services (like Redis, Postgres, etc) and components (like mounted volumes, port mappings, etc) on which your code depends.

1. Know that `docker` is installed inside the `builder` Docker image in order to run (within the Docker container) integration tests that depend on containerized servers and datastores.
