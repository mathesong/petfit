# Use rocker/shiny-verse as base image (includes Shiny + tidyverse)
FROM rocker/shiny-verse:latest

# Arguments for user configuration
ARG USER_ID=1000
ARG GROUP_ID=1000
ARG USER_NAME=petfit

# Install system dependencies
RUN apt-get update && apt-get install -y \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libgit2-dev \
    && rm -rf /var/lib/apt/lists/*

# Create user and group with specified IDs
RUN if ! getent group ${GROUP_ID}; then groupadd -g ${GROUP_ID} ${USER_NAME}; fi && \
    if ! getent passwd ${USER_ID}; then useradd -u ${USER_ID} -g ${GROUP_ID} -m -s /bin/bash ${USER_NAME}; fi

# Install additional R packages required by petfit (and its kinfitr dependency)
RUN install2.r --error --skipinstalled \
    optparse \
    remotes \
    && rm -rf /tmp/downloaded_packages/ /tmp/*.rds

# Install kinfitr from GitHub (petfit dependency)
RUN R -e "remotes::install_github('mathesong/kinfitr', dependencies = TRUE)"

# Create app directory
WORKDIR /app

# Copy the petfit app package files
COPY . /app/

# Install the petfit package
RUN R -e "devtools::install('.', dependencies = TRUE)"

# Copy Docker-specific scripts
COPY docker/run_petfit.R /app/
RUN chmod +x /app/run_petfit.R

# Change ownership of app directory to non-root user (use UID:GID to handle existing users)
RUN chown -R ${USER_ID}:${GROUP_ID} /app

# Create data directory and set permissions
RUN mkdir -p /data && chown -R ${USER_ID}:${GROUP_ID} /data

# Switch to non-root user
USER ${USER_ID}:${GROUP_ID}

# Expose port 3838 for Shiny apps
EXPOSE 3838

# Set the entry point
ENTRYPOINT ["/app/run_petfit.R"]
