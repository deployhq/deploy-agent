# Deploy Agent

A secure proxy that allows [DeployHQ](https://www.deployhq.com/) to forward connections to servers behind firewalls. The agent establishes an outbound TLS connection to DeployHQ's servers and proxies deployment traffic to allowed destinations based on an IP/network allowlist.

## How It Works

```text
┌──────────┐       TLS (port 7777)       ┌─────────────┐        ┌─────────────────┐
│ DeployHQ │ ◄──────────────────────────► │ Deploy Agent │ ──────► │ Your Server(s)  │
└──────────┘   mutual authentication     └─────────────┘  proxy  └─────────────────┘
                                          (behind firewall)
```

The agent connects **outbound** to DeployHQ, so no inbound firewall rules are needed. Connections to destination servers are restricted to an explicit allowlist of IPs and networks.

## Requirements

- Ruby 2.7 or later
- Outbound HTTPS access to `api.deployhq.com` (port 443) for initial setup
- Outbound TCP access to `agent.deployhq.com` (port 7777) for agent operation

## Installation

```bash
gem install deploy-agent
```

## Quick Start

### 1. Configure the agent

Run the interactive setup wizard. This generates a TLS client certificate and creates an access list:

```bash
deploy-agent setup
```

You'll be prompted for:
- **Agent name** — a label to identify this agent in your DeployHQ account
- **Allowed IPs** — destination servers the agent can connect to (localhost is included by default)

At the end, you'll receive a **claim code** to associate this agent with your DeployHQ account under **Settings > Agents**.

### 2. Start the agent

Run as a background daemon:

```bash
deploy-agent start
```

Or run in the foreground (useful for debugging):

```bash
deploy-agent run
```

Use `-v` for verbose logging:

```bash
deploy-agent run -v
```

### 3. Link to your DeployHQ account

Go to **Settings > Agents** in your DeployHQ account and enter the claim code from the setup step.

## Commands

| Command | Description |
|---|---|
| `deploy-agent setup` | Interactive setup wizard (certificate + access list) |
| `deploy-agent start` | Start the agent as a background daemon |
| `deploy-agent stop` | Stop the background daemon |
| `deploy-agent restart` | Restart the background daemon |
| `deploy-agent run` | Run in the foreground |
| `deploy-agent status` | Check if the agent is running |
| `deploy-agent accesslist` | Display the current allowed destinations |
| `deploy-agent version` | Show the installed version |

All commands accept `-v` / `--verbose` for debug logging.

## Configuration

All configuration is stored in `~/.deploy/`:

| File | Purpose |
|---|---|
| `agent.crt` | Client certificate for TLS authentication |
| `agent.key` | Private key for the client certificate |
| `agent.access` | Allowlist of IPs/networks (one per line, CIDR supported) |
| `agent.pid` | PID file when running as a daemon |
| `agent.log` | Log file when running as a daemon |

### Editing the access list

To allow the agent to connect to additional servers, edit `~/.deploy/agent.access`:

```text
# Allow deployments to localhost
127.0.0.1
::1

# Application servers
10.0.1.0/24
192.168.1.50
```

Lines starting with `#` are comments. Each entry can be an individual IP address or a CIDR network range.

## Troubleshooting

**Agent won't start — "not configured"**
Run `deploy-agent setup` first to generate the certificate and access list.

**Connection refused / timeouts**
Ensure outbound TCP port 7777 is open to `agent.deployhq.com`.

**Destination connection denied**
The target server IP must be listed in `~/.deploy/agent.access`. Run `deploy-agent accesslist` to verify, and edit the file to add missing entries.

**Debug logging**
Run `deploy-agent run -v` in the foreground to see detailed connection logs.

## Development

```bash
bundle install
bundle exec rspec       # Run tests
bundle exec rubocop     # Run linter
bundle exec rake        # Run both
```

## Release

This project uses [release-please](https://github.com/googleapis/release-please) for automated releases. Follow the [Conventional Commits](https://www.conventionalcommits.org/) specification for all commit messages:

- `fix:` — patch release (e.g. 1.4.1)
- `feat:` — minor release (e.g. 1.5.0)
- `feat!:` or `BREAKING CHANGE:` — major release (e.g. 2.0.0)

When commits land on `master`, release-please creates a release PR. Merging that PR automatically publishes the gem to [RubyGems](https://rubygems.org/gems/deploy-agent).

## License

See [deployhq.com](https://www.deployhq.com/) for license details.
