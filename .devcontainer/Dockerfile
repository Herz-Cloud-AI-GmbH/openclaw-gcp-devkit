FROM mcr.microsoft.com/vscode/devcontainers/base:bookworm

ARG APP_FOLDER
ARG TERRAFORM_VERSION=1.14.6

RUN apt-get update \
    #
    # Install common utilities
    && apt-get install -y make jq shellcheck unzip curl \
    #
    # Install gcloud CLI
    && apt-get install -y apt-transport-https ca-certificates gnupg \
    && curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list \
    && apt-get update \
    && apt-get install -y google-cloud-sdk \
    #
    # Install Terraform (detect arch at build time)
    && ARCH="$(dpkg --print-architecture)" \
    && curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${ARCH}.zip" -o /tmp/terraform.zip \
    && unzip /tmp/terraform.zip -d /usr/local/bin \
    && chmod +x /usr/local/bin/terraform \
    && rm /tmp/terraform.zip \
    #
    # Clean up
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR ${APP_FOLDER}
