# VICAR worker image for Airflow KubernetesPodOperator tasks.
# Base: Open source TIG VICAR execution environment (Oracle Linux 8, x86_64).
# Adds AWS CLI v2 so wrapper scripts can download/upload from MinIO (S3 API).
FROM ghcr.io/nasa-ammos/tig/terrain-intelligence-generator:opensource

USER root

# Install AWS CLI v2 (official bundle, no python dependency)
RUN curl -sSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
    && (command -v unzip >/dev/null 2>&1 || (microdnf install -y unzip || dnf install -y unzip || yum install -y unzip)) \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/awscliv2.zip /tmp/aws \
    && aws --version
