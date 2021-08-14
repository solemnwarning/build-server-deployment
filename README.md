# build-server-deployment

## What is this?

This is a collection of scripts and Packer/Terraform definitions that build and deploy my various Buildkite CI build agents (except for Mac) on AWS.

The following machine images are deployed using Packer (one subdirectory for each):

* build-agent-debian - Debian-based Buildkite agent used for building Debian packages with git-buildpackage and running steps in normal Linux chroots.
* build-agent-fedora - Fedora-based Buildkite agent used for building RPM packages.
* build-agent-freebsd - FreeBSD-based Buildkite agent.
* build-agent-ipxtester - Debian-based Buildkite agent that runs the IPXWrapper test suite on bare-metal instances.
* build-agent-windows - Windows-based Buildkite agent with MinGW toolchains.

There is also:

* build-cluster-manager - Persistent Debian-based system that scales build agent instances up/down using [buildkite-spot-fleet-scaler](https://github.com/solemnwarning/buildkite-spot-fleet-scaler) and runs a HTTP cache used for installing build dependencies on the Debian/Fedora build agents.
* build-cluster-aws - Terraform configuration for deploying all of the above machines on AWS.
* workflow-templates - GitHub Actions Workflow templates to deploy everything above.
