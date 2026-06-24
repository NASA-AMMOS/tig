# TIG Adaptation Guide Design

**Date:** 2026-06-24  
**Status:** Design  
**Document Type:** Specification

## Overview

Create a comprehensive guide for building custom TIG (Terrain Intelligence Generator) image adaptations. The guide will help internal NASA/JPL teams and external researchers extend the opensource TIG image with mission-specific tools, proprietary binaries, or custom analysis pipelines.

## Goals

1. **Clear starting point:** Emphasize that all adaptations MUST start from the opensource base image
2. **Practical tutorial:** Provide step-by-step instructions anyone can follow
3. **Real examples:** Use the m20 adaptation as a reference implementation
4. **Best practices:** Cover image size optimization, testing, and documentation
5. **Tested instructions:** Verify all commands and examples work on MacOS and Linux

## Non-Goals

- Deep dive into Docker internals or advanced Docker features
- Comprehensive troubleshooting for all possible Docker/system issues
- Instructions for modifying the base opensource image itself
- Detailed registry/CI/CD workflows for automated distribution

## Target Audience

- **Primary:** Developers with basic Docker knowledge who need to add custom tools
- **Secondary:** Mission teams adapting TIG for specific rover pipelines
- **Tertiary:** External researchers extending TIG for novel analysis

**Assumed knowledge:**
- Basic Docker concepts (build, run, images, containers)
- Command line familiarity
- Understanding of their own tools/binaries they want to add

## Design

### Document Location

**File:** `docs/creating-adaptations.md`  
**Rationale:** Lives in main docs/ alongside getting-started.md and other user-facing documentation

### Content Structure

#### 1. Introduction

**Content:**
- What is a TIG adaptation (custom Docker image extending the base)
- Why create an adaptation (mission-specific tools, proprietary binaries, custom workflows)
- **Key principle (emphasized):** Always start FROM the opensource image - don't modify it
- What you'll learn in this guide

**Length:** ~3-4 paragraphs

#### 2. Prerequisites

**Content:**
- Base image requirement: Either pull `ghcr.io/nasa-ammos/tig/terrain-intelligence-generator:opensource` or build locally
- Docker/Podman installed and working
- Your custom tools/binaries ready to add
- Basic understanding of Dockerfiles

**Format:** Bulleted checklist with verification commands

#### 3. Quick Start Example

**Content:**
- Minimal working example (5-10 lines of Dockerfile)
- Shows the essential pattern: FROM base + add one tool
- Build and test commands
- **Purpose:** Give immediate success before diving into details

**Code example:**
```dockerfile
ARG BASE_IMAGE=terrain-intelligence-generator:opensource
FROM ${BASE_IMAGE}

COPY my_tool /usr/local/bin/my_tool
RUN chmod +x /usr/local/bin/my_tool
```

#### 4. Step-by-Step Tutorial

##### 4.1 Directory Setup

**Content:**
- Recommended structure (mirror m20 pattern):
  ```
  my-adaptation/
  ├── docker/
  │   ├── Dockerfile
  │   └── my_binary
  └── README.md
  ```
- Where to place different types of files (binaries, scripts, configs)

##### 4.2 Writing the Dockerfile

**Content (with emphasis on key principles):**

a. **Starting from the base (CRITICAL)**
   - `ARG BASE_IMAGE=terrain-intelligence-generator:opensource`
   - `FROM ${BASE_IMAGE}`
   - Why this pattern: flexibility, consistency, traceability
   - Show how to use a different base (e.g., from registry)

b. **Adding metadata**
   - LABEL for title, description, version, source
   - Example from m20 Dockerfile

c. **Installing dependencies**
   - Using dnf for system packages
   - Best practices for minimal size:
     - `--nogpgcheck --setopt=install_weak_deps=False --setopt=tsflags=nodocs`
     - Chain commands with `&&` to reduce layers
     - Clean up in same RUN: `dnf clean all && rm -rf /var/cache/dnf`
   - Multi-arch considerations (32-bit vs 64-bit libraries)

d. **Adding your tools**
   - COPY with proper ownership (`--chown=root:root`)
   - Setting permissions (`chmod +x`)
   - Where to place binaries: `${V2TOP}/mars/lib/x86-linux/` or `/usr/local/bin/`

e. **Creating VICAR wrapper scripts**
   - Why wrappers: Set VICAR environment (V2TOP, LD_LIBRARY_PATH, etc.)
   - Pattern from m20 m20filter wrapper
   - Handling VICAR exit codes (0-2 often mean success)

f. **Verification steps**
   - RUN commands to verify installation
   - Check binaries exist and are executable
   - Test library dependencies if applicable
   - Print helpful summary

##### 4.3 Image Size Optimization

**Content (NEW SECTION):**
- **Minimize layers:** Combine related RUN commands with `&&`
- **Clean up in same layer:** Remove caches/temp files before layer closes
- **Don't install unnecessary packages:** 
  - Use `--setopt=install_weak_deps=False`
  - Avoid docs with `--setopt=tsflags=nodocs`
- **Use .dockerignore:** Exclude files not needed in the image
- **Consider multi-stage builds:** If you need build tools but not in final image
- **Check what you're adding:** Use `docker history` to see layer sizes
- **Example comparison:** Show before/after sizes when applying these practices

##### 4.4 Building Your Adaptation

**Content:**
- Basic build command: `docker build -t my-adaptation:latest .`
- With base image override: `docker build --build-arg BASE_IMAGE=... -t my-adaptation:latest .`
- Platform considerations for MacOS ARM: `--platform linux/amd64`
- Expected build time (depends on what you add, typically <5 min for small adaptations)
- Checking image size: `docker images my-adaptation`

##### 4.5 Testing Your Adaptation

**Content:**
- Running the container interactively: `docker run -it --rm my-adaptation bash`
- Verifying tools in PATH: `which my_tool`
- Testing tool execution: Run with `--help` or simple test command
- Testing with workspace mounted: `-v $(pwd)/workspace:/workspace`
- Integration testing: Run with actual data if available
- Smoke test checklist (bulleted)

#### 5. Real-World Example: M20 Adaptation

**Content:**
- Overview of what m20 adds (m20filter, 32-bit libraries)
- Annotated walkthrough of key Dockerfile sections:
  - 32-bit library installation block
  - m20filter binary copy
  - Wrapper script generation
  - Verification steps
- Link to full source: `terrain-intelligence-generator-m20/docker/Dockerfile`
- Link to m20 README for usage documentation

**Format:** Code blocks with explanatory callouts

#### 6. Documenting Your Adaptation

**Content:**
- What to include in your README (based on m20 template):
  - Title and brief description
  - What's added (tools, libraries, capabilities)
  - Prerequisites (base image)
  - Building instructions
  - Usage examples
  - Notes about proprietary/internal components
  - License information
- README template provided (can copy/modify)
- Importance of inline Dockerfile comments

#### 7. Common Scenarios

**Content (brief patterns for each):**
- Adding a simple 64-bit binary
- Adding a 32-bit binary (requires 32-bit libraries)
- Installing Python packages
- Adding custom calibration files
- Setting environment variables
- Mounting data at runtime vs baking into image

**Format:** Pattern name + Dockerfile snippet + when to use

#### 8. Distribution

**Content (brief, not comprehensive):**
- Tagging conventions: `my-org/tig-adaptation:version`
- Exporting image: `docker save`
- Pushing to registry: `docker push` (quick example)
- Where to host: Docker Hub, GitHub Container Registry, internal registry
- Link to Docker documentation for details

**Length:** ~1 paragraph + example commands

#### 9. Troubleshooting

**Content:**
- **Platform/architecture issues**
  - Building on ARM (Mac M1/M2) for x86: Use `--platform linux/amd64`
  - QEMU emulation warnings (expected, safe to ignore)
- **Missing library dependencies**
  - `ldd` to check binary dependencies
  - `ldconfig -p` to check installed libraries
  - Installing -devel vs runtime packages
- **Binary not found / permission denied**
  - Check COPY destination path
  - Verify chmod +x
  - Check wrapper script PATH variable
- **VICAR environment not set**
  - Ensure wrapper scripts set V2TOP, LD_LIBRARY_PATH
  - Source VICAR environment if running tools manually
- **Image size bloat**
  - Check `docker history` for large layers
  - Review optimization section
  - Consider what's really needed

**Format:** Problem → Solution pattern

### Testing Plan

After writing the guide, verify instructions work by:

1. **Follow quick start example**
   - Create minimal adaptation with a dummy binary
   - Build successfully
   - Run and verify tool is accessible

2. **Follow full tutorial**
   - Create a more complete adaptation (could be a simple Python script)
   - Apply size optimization practices
   - Build and measure size
   - Test all verification steps work

3. **Verify m20 reference**
   - Ensure all references to m20 code are accurate
   - Check that annotated examples match actual m20 Dockerfile

4. **Cross-check commands**
   - All Docker commands tested on MacOS (primary development environment)
   - Note any Linux-specific differences in troubleshooting section

5. **Review documentation**
   - Check all internal links work
   - Verify code blocks are properly formatted
   - Ensure no placeholders or TODOs remain

### Success Criteria

- [ ] Guide is complete and committed to `docs/creating-adaptations.md`
- [ ] Quick start example builds successfully
- [ ] All code examples are tested and working
- [ ] Image size optimization section included with practical tips
- [ ] M20 adaptation properly referenced and explained
- [ ] Troubleshooting covers common issues from experience
- [ ] Testing plan executed and any issues fixed
- [ ] User can follow the guide without prior adaptation experience

## Open Questions

None - design is complete pending user approval.

## References

- Existing m20 adaptation: `terrain-intelligence-generator-m20/docker/Dockerfile`
- M20 README: `terrain-intelligence-generator-m20/README.md`
- Getting started guide: `docs/getting-started.md`
- Docker best practices: https://docs.docker.com/develop/dev-best-practices/
