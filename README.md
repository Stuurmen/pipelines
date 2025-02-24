# Pipelines

A repository that contains multiple reusable workflows that can be used in GitHub Actions.

## Deploy v2.0.0
Automatically deploys a project to a staging or a production environment based on a provided config file.

### GitHub Secret

A GitHub Secret that will store the SSH key used to connect to the server. 

When using this in an organization that runs multiple projects on the same server, you only need to create this secret once as a GitHub organization secret. It can then be used across all repository's with access, and it will be able to deploy all those repository's to different locations on that same server.

**Steps:**
1. Generate an SSH private key that will give you access to your server.
2. Create a new GitHub organization/repository secret with a recognizable name such as `DEPLOYMENT_SSH_PRIVATE_KEY`.
3. Paste your SSH private key as the value of the GitHub Secret.


### GitHub Action

The action that runs every time you push to a given branch. This will deploy the repository.

**Steps:**
1. Create a new workflow under the path `.github/workflows/YOUR_WORKFLOW_NAME`.
2. Paste the following content in your workflow file.
```yaml
# Workflow name
name: YOUR_WORKFLOW_NAME

# Events that trigger the workflow
on:
  push:
    branches: [ 
      main, 
      dev 
    ]
  workflow_dispatch: # Triggered manually 

# Jobs to run
jobs:

  # Deploy
  deploy:
    uses: Stuurmen/pipelines/.github/workflows/deploy-v2.0.0.yml@main
    secrets:
      ssh_private_key: ${{ secrets.DEPLOYMENT_SSH_PRIVATE_KEY }}
```

3. Replace any placeholders with real data, and verify that the GitHub secret name below matches the name of your own GitHub secret.
```yaml
name: Pipeline

on:
  push:
    branches: [ 
      main, 
      dev 
    ]
  workflow_dispatch:

jobs:
  deploy:
    uses: Stuurmen/pipelines/.github/workflows/deploy-v2.0.0.yml@main
    secrets:
      ssh_private_key: ${{ secrets.DEPLOYMENT_SSH_PRIVATE_KEY }}
```


### Pipeline config file

A configuration file that indicates what should be deployed, and where it should be deployed.

**Steps:**
1. Create a config file with the name `pipeline.json` at the root of your project.
2. Paste the following file content.

```json
{
  "production": {
    "branch": "PRODUCTION_BRANCH_NAME",
    "host": "PRODUCTION_SSH_IP_ADDRESS",
    "port": "PRODUCTION_SSH_PORT",
    "username": "PRODUCTION_SSH_USERNAME",
    "path": "REMOTE_PATH_TO_DEPLOY_TO",
    "node_version": "NODE_VERSION",
  },
  "staging": {
    "branch": "STAGING_BRANCH_NAME",
    "host": "STAGING_SSH_IP_ADDRESS",
    "port": "STAGING_SSH_PORT",
    "username": "STAGING_SSH_USERNAME",
    "path": "REMOTE_PATH_TO_DEPLOY_TO",
    "node_version": "NODE_VERSION",
  },
  "source": {
    "path": "PATH_TO_DIST"
  }
}
```
3. Replace the values in the configuration file with real data. An example can be found below.

```json
{
  "production": {
    "branch": "main",
    "host": "12.34.567.890",
    "port": "12345",
    "username": "admin",
    "path": "./",
    "node_version": "20"
  },
  "staging": {
    "branch": "dev",
    "host": "12.34.567.890",
    "port": "67890",
    "username": "admin",
    "path": "./",
    "node_version": "20"
  },
  "source": {
    "path": "dist/"
  }
}
```