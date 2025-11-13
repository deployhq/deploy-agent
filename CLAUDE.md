# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Deploy Agent is a Ruby gem that creates a secure proxy allowing DeployHQ to forward connections to protected servers. It establishes a TLS connection to DeployHQ's servers and proxies connections to allowed destinations based on an IP/network allowlist.

## Development Commands

**Install dependencies:**
```bash
bundle install
```

**Run all tests:**
```bash
bundle exec rspec
```

**Run linter:**
```bash
bundle exec rubocop
```

**Run both tests and linter:**
```bash
bundle exec rake
```

**Build gem locally:**
```bash
gem build deploy-agent.gemspec
```

**Install gem locally for testing:**
```bash
gem install ./deploy-agent-*.gem
```

**Test agent commands:**
```bash
deploy-agent setup    # Configure agent with certificate and access list
deploy-agent run      # Run in foreground
deploy-agent start    # Start as background daemon
deploy-agent stop     # Stop background daemon
deploy-agent status   # Check daemon status
deploy-agent accesslist  # View allowed destinations
```

## Architecture

### Core Components

The agent uses an event-driven, non-blocking I/O architecture with NIO4r for socket multiplexing:

**DeployAgent::Agent** (`lib/deploy_agent/agent.rb`)
- Main event loop using NIO::Selector and Timers::Group
- Manages lifecycle of server and destination connections
- Handles retries and error recovery
- Configures logging (STDOUT or file-based when backgrounded)

**DeployAgent::ServerConnection** (`lib/deploy_agent/server_connection.rb`)
- Maintains secure TLS connection to DeployHQ's control server (port 7777)
- Uses mutual TLS authentication with client certificates
- Processes binary protocol packets (connection requests, data transfer, keepalive, shutdown)
- Enforces destination access control via allowlist
- Manages multiple concurrent destination connections by ID

**DeployAgent::DestinationConnection** (`lib/deploy_agent/destination_connection.rb`)
- Handles non-blocking connections to backend servers (the actual deployment targets)
- Implements asynchronous connect with status tracking (:connecting, :connected)
- Bidirectional data proxying between DeployHQ and destination
- Reports connection status and errors back to ServerConnection

**DeployAgent::CLI** (`lib/deploy_agent/cli.rb`)
- Command-line interface using OptionParser
- Daemon process management (start/stop/restart/status)
- PID file management at `~/.deploy/agent.pid`

**DeployAgent::ConfigurationGenerator** (`lib/deploy_agent/configuration_generator.rb`)
- Interactive setup wizard for initial configuration
- Generates certificate via DeployHQ API
- Creates access list file with allowed destinations

### Binary Protocol

ServerConnection implements a length-prefixed binary protocol:
- Packet format: 2-byte length (network byte order) + packet data
- Packet types identified by first byte: connection request (1), connection response (2), close (3), data (4), shutdown (5), reconnect (6), keepalive (7)
- Connection IDs (2-byte unsigned) track multiple simultaneous proxied connections

### Configuration Files

All configuration stored in `~/.deploy/`:
- `agent.crt` - Client certificate for TLS authentication
- `agent.key` - Private key for client certificate
- `agent.access` - Newline-separated list of allowed IPs/networks (CIDR format)
- `agent.pid` - Process ID when running as daemon
- `agent.log` - Log file when running as daemon

### Security Model

- Mutual TLS: Both agent and server authenticate with certificates
- CA verification: Agent verifies server certificate against bundled `ca.crt`
- Allowlist enforcement: Only connections to explicitly permitted destinations are allowed
- IP/CIDR matching: Supports individual IPs and network ranges in access list

## Release Process

This project uses [release-please](https://github.com/googleapis/release-please) for automated releases. Follow [Conventional Commits](https://www.conventionalcommits.org/) specification for all commits:

- `fix:` patches (1.0.x)
- `feat:` minor versions (1.x.0)
- `!` or `BREAKING CHANGE:` major versions (x.0.0)

Example commit messages:
```text
fix: Prevent connection leak on destination timeout
feat: Add support for IPv6 destinations
feat!: Change default server port to 7778
```

## Code Style

Ruby 2.7+ syntax required. RuboCop configured with:
- Single quotes for strings
- Frozen string literals enabled
- Symbol arrays with brackets
- Empty lines around class bodies
- No documentation requirement (Style/Documentation disabled)
- `lib/` directory excluded from most metrics