# Publish ECR Action

[![CI](https://github.com/heronlabs/action-ecr-publish/actions/workflows/ci.yml/badge.svg)](https://github.com/heronlabs/action-ecr-publish/actions/workflows/ci.yml)

A GitHub Action that builds, lints, and publishes Docker images to Amazon Elastic Container Registry (ECR).

This action automates the complete Docker-to-ECR workflow: it validates your Dockerfile with hadolint, builds the image, authenticates with AWS using OIDC, and pushes the image to your ECR repository. It eliminates the need to manage long-lived AWS credentials by using IAM role assumption.

## Requirements

### Permissions

Your workflow must include these permissions for OIDC authentication:

```yaml
permissions:
  id-token: write   # Required for AWS OIDC authentication
  contents: read    # Required for actions/checkout
```

### AWS IAM Role

You must configure an IAM role that:

1. Trusts GitHub's OIDC provider
2. Has permissions to push images to your ECR repository

Example trust policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:<OWNER>/<REPO>:*"
        }
      }
    }
  ]
}
```

Required IAM permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": "*"
    }
  ]
}
```

### Supported Runners

- `ubuntu-24.04` (recommended)
- `ubuntu-22.04`
- `ubuntu-latest`

### Dependencies

The action uses these tools (pre-installed on GitHub-hosted runners):

- Docker (with BuildKit support)
- Bash

Internal action dependencies:

- `aws-actions/configure-aws-credentials@v6`
- `aws-actions/amazon-ecr-login@v2`
- `hadolint/hadolint` (Docker image for Dockerfile linting)

## Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `BUILD_NAME` | Name for the Docker image | Yes | — |
| `FILE_NAME` | Path to the Dockerfile | Yes | — |
| `TAG_NAME` | Tag for the Docker image | Yes | — |
| `AWS_ROLE_TO_ASSUME` | ARN of the IAM role to assume for ECR access | No\* | — |
| `AWS_REGION` | AWS region where your ECR repository is located | No\* | — |
| `AWS_ROLE_DURATION_SECONDS` | Duration in seconds for the assumed role session | No\* | — |
| `AWS_REPOSITORY` | ECR repository URL (without image name) | No\* | — |
| `TAG_ALIAS` | Comma-separated alias tags to apply to the same image (e.g. `v1,v1.2`) | No | — |
| `NODE_AUTH_TOKEN` | GitHub token for private npm packages (passed as Docker secret) | No | — |

\* The image is **always** linted and built. The `AWS_*` inputs are only consumed when `AWS_ROLE_TO_ASSUME` is set: provide them to push to ECR, or omit them to lint + build only (e.g. on pull requests).

## Outputs

This action does not produce outputs.

## Usage

### Minimal Example

```yaml
name: Build and Push to ECR

on:
  push:
    branches: [main]

permissions:
  id-token: write
  contents: read

jobs:
  publish:
    runs-on: ubuntu-24.04
    steps:
      - name: Checkout
        uses: actions/checkout@v6

      - name: Build and Push to ECR
        uses: heronlabs/action-ecr-publish@v1
        with:
          AWS_ROLE_TO_ASSUME: arn:aws:iam::123456789012:role/github-ecr-push
          AWS_REGION: us-east-1
          AWS_ROLE_DURATION_SECONDS: 900
          AWS_REPOSITORY: 123456789012.dkr.ecr.us-east-1.amazonaws.com
          BUILD_NAME: my-app
          FILE_NAME: Dockerfile
          TAG_NAME: ${{ github.sha }}
```

### Advanced Example with Private npm Packages

Use `NODE_AUTH_TOKEN` when your Dockerfile needs to install private npm packages.

```yaml
name: Build and Push to ECR

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  id-token: write
  contents: read

jobs:
  publish:
    runs-on: ubuntu-24.04
    steps:
      - name: Checkout
        uses: actions/checkout@v6

      - name: Build and Push to ECR
        uses: heronlabs/action-ecr-publish@v1
        with:
          AWS_ROLE_TO_ASSUME: ${{ secrets.AWS_ROLE_ARN }}
          AWS_REGION: ${{ vars.AWS_REGION }}
          AWS_ROLE_DURATION_SECONDS: 1800
          AWS_REPOSITORY: ${{ secrets.ECR_REPOSITORY }}
          BUILD_NAME: my-app
          FILE_NAME: docker/Dockerfile.prod
          TAG_NAME: ${{ github.ref_name }}-${{ github.sha }}
          NODE_AUTH_TOKEN: ${{ secrets.NPM_TOKEN }}
```

Your Dockerfile must use BuildKit secrets to access `NODE_AUTH_TOKEN`:

```dockerfile
# syntax=docker/dockerfile:1
FROM node:20-alpine

WORKDIR /app
COPY package*.json ./

# Access the secret during npm install
RUN --mount=type=secret,id=NODE_AUTH_TOKEN \
    NPM_TOKEN=$(cat /run/secrets/NODE_AUTH_TOKEN) \
    npm ci --ignore-scripts

COPY . .
RUN npm run build

CMD ["node", "dist/main.js"]
```

### Example with Semantic Versioning Tags

```yaml
name: Release to ECR

on:
  release:
    types: [published]

permissions:
  id-token: write
  contents: read

jobs:
  publish:
    runs-on: ubuntu-24.04
    steps:
      - name: Checkout
        uses: actions/checkout@v6

      - name: Build and Push to ECR
        uses: heronlabs/action-ecr-publish@v1
        with:
          AWS_ROLE_TO_ASSUME: ${{ secrets.AWS_ROLE_ARN }}
          AWS_REGION: us-east-1
          AWS_ROLE_DURATION_SECONDS: 900
          AWS_REPOSITORY: 123456789012.dkr.ecr.us-east-1.amazonaws.com
          BUILD_NAME: my-app
          FILE_NAME: Dockerfile
          TAG_NAME: ${{ github.event.release.tag_name }}
```

## Important Notes

- **Dockerfile linting**: The action runs [hadolint](https://github.com/hadolint/hadolint) before building. The workflow fails if linting errors are found.
- **BuildKit required**: When using `NODE_AUTH_TOKEN`, your Dockerfile must use BuildKit syntax (`# syntax=docker/dockerfile:1`) and `--mount=type=secret`.
- **OIDC only**: This action uses OIDC for AWS authentication. Long-lived access keys are not supported.
- **Role session name**: The session is named `action-ecr-publish-session` for CloudTrail auditing.
- **Build context**: The Docker build context is the repository root (`.`).

## Common Errors

### `Error: Could not assume role with OIDC`

**Cause**: The IAM role trust policy does not allow GitHub Actions to assume it.

**Solution**: Verify your trust policy includes the correct GitHub OIDC provider and repository conditions. Check that `id-token: write` permission is set.

### `Error: denied: Your authorization token has expired`

**Cause**: The role session expired before the image push completed.

**Solution**: Increase `AWS_ROLE_DURATION_SECONDS`. For large images, use 1800 (30 minutes) or higher.

### Hadolint fails with `DL3008` or similar

**Cause**: Your Dockerfile has linting violations.

**Solution**: Review [hadolint rules](https://github.com/hadolint/hadolint#rules) and fix the reported issues. Common fixes:
- `DL3008`: Pin apt package versions
- `DL3018`: Pin apk package versions

### `failed to solve: failed to compute cache key: failed to calculate checksum`

**Cause**: A file referenced in `COPY` or `ADD` doesn't exist.

**Solution**: Verify all paths in your Dockerfile exist relative to the repository root.

### `npm ERR! 404 Not Found` when using NODE_AUTH_TOKEN

**Cause**: The secret is not properly mounted or the token is invalid.

**Solution**: Ensure your Dockerfile uses `--mount=type=secret,id=NODE_AUTH_TOKEN` and the `.npmrc` is configured to use the token.

## License

MIT
