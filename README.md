# ECR Publish Action

[![CI](https://github.com/heronlabs/action-ecr-publish/actions/workflows/continuous-integration.yml/badge.svg)](https://github.com/heronlabs/action-ecr-publish/actions/workflows/continuous-integration.yml)

> Lint, build, and publish a Docker image to Amazon ECR.

Validates the Dockerfile with hadolint, builds the image, then (when an IAM role is supplied) authenticates to AWS via OIDC and pushes to your ECR repository. Omit the `AWS_*` inputs to lint and build only.

## Usage

```yaml
name: Publish to ECR

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
      - uses: actions/checkout@v6

      - uses: heronlabs/action-ecr-publish@v3
        with:
          AWS_ROLE_TO_ASSUME: arn:aws:iam::123456789012:role/github-ecr-push
          AWS_REGION: us-east-1
          AWS_ROLE_DURATION_SECONDS: 900
          AWS_REPOSITORY: 123456789012.dkr.ecr.us-east-1.amazonaws.com
          BUILD_NAME: my-app
          FILE_NAME: Dockerfile
          TAG_NAME: ${{ github.sha }}
```

### Private npm packages

Pass `NODE_AUTH_TOKEN` when the build installs private npm packages. The Dockerfile reads it as a BuildKit secret.

```yaml
      - uses: heronlabs/action-ecr-publish@v3
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

```dockerfile
# syntax=docker/dockerfile:1
FROM node:20-alpine

WORKDIR /app
COPY package*.json ./

RUN --mount=type=secret,id=NODE_AUTH_TOKEN \
    NPM_TOKEN=$(cat /run/secrets/NODE_AUTH_TOKEN) \
    npm ci --ignore-scripts

COPY . .
RUN npm run build

CMD ["node", "dist/main.js"]
```

## Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `BUILD_NAME` | Name for the Docker image | Yes | — |
| `FILE_NAME` | Path to the Dockerfile | Yes | — |
| `TAG_NAME` | Tag for the Docker image | Yes | — |
| `TAG_ALIAS` | Comma-separated alias tags to apply to the same image (e.g. `v1,v1.2`) | No | — |
| `AWS_ROLE_TO_ASSUME` | ARN of the IAM role to assume for ECR access | No\* | — |
| `AWS_REGION` | AWS region of the ECR repository | No\* | — |
| `AWS_ROLE_DURATION_SECONDS` | Duration in seconds for the assumed-role session | No\* | — |
| `AWS_REPOSITORY` | ECR repository URL (without image name) | No\* | — |
| `NODE_AUTH_TOKEN` | Token for private npm packages, passed as a Docker secret | No | — |

\* The image is always linted and built. The `AWS_*` inputs are consumed only when `AWS_ROLE_TO_ASSUME` is set (push to ECR); omit them to lint and build only, e.g. on pull requests.

## Outputs

This action produces no outputs.

## Permissions

```yaml
permissions:
  id-token: write
  contents: read
```

<details><summary>AWS IAM policy</summary>

Trust policy — allow the repository to assume the role via GitHub's OIDC provider:

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

Least-privilege permission policy — allow pushing images to ECR:

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

</details>

## Notes

- hadolint runs before the build; lint failures block the run.
- BuildKit is required for `NODE_AUTH_TOKEN`: the Dockerfile needs `# syntax=docker/dockerfile:1` and `--mount=type=secret`.
- The Docker build context is always the repository root (`.`).
- OIDC only — no long-lived access keys.
- `Could not assume role with OIDC`: check `id-token: write` is granted and the role trust policy matches the repository.
- `authorization token has expired` on large pushes: raise `AWS_ROLE_DURATION_SECONDS`.

## License

MIT
