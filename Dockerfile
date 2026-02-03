# GoDavao Development Dockerfile
# This Dockerfile sets up a containerized development environment for Flutter

# Stage 1: Base Flutter image
FROM cirrusci/flutter:3.24.0-stable AS base

# Set working directory
WORKDIR /app

# Install system dependencies
RUN sudo apt-get update && sudo apt-get install -y \
    git \
    curl \
    wget \
    unzip \
    xz-utils \
    zip \
    libglu1-mesa \
    && sudo rm -rf /var/lib/apt/lists/*

# Stage 2: Development environment
FROM base AS development

# Copy pubspec files
COPY pubspec.yaml pubspec.lock ./

# Pre-fetch dependencies (creates a cached layer)
RUN flutter pub get

# Copy the entire project
COPY . .

# Expose ports for development
# 8080: Flutter web dev server
# 3000: Optional API proxy/mocking server
EXPOSE 8080 3000

# Set environment variables
ENV FLUTTER_WEB_DEBUG_PORT=8080
ENV FLUTTER_WEB_HOSTNAME=0.0.0.0

# Default command: start development server
CMD ["flutter", "run", "--web-port=8080", "--web-hostname", "0.0.0.0"]

# Stage 3: Build for production web
FROM base AS web-build

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .

# Build the web application
RUN flutter build web --release

# Use nginx to serve the web app
FROM nginx:alpine AS web-production

# Copy the built web app from the previous stage
COPY --from=web-build /app/build/web /usr/share/nginx/html

# Copy nginx configuration
COPY docker/nginx.conf /etc/nginx/nginx.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]

# Stage 4: Android build environment
FROM base AS android-build

# Install Android SDK and build tools
RUN sudo apt-get update && sudo apt-get install -y \
    openjdk-17-jdk \
    android-tools-adb \
    && sudo rm -rf /var/lib/apt/lists/*

# Set JAVA_HOME
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .

# Accept Android licenses (for CI/CD)
RUN yes | flutter doctor --android-licenses

# Build APK
RUN flutter build apk --release

# Output the APK
VOLUME ["/app/build/app/outputs/flutter-apk"]

# Stage 5: Testing environment
FROM base AS test

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .

# Run tests with coverage
RUN flutter test --coverage

# Default command for test container
CMD ["flutter", "test"]
