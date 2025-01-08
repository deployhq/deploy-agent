# Deploy Agent Client

This gem allows you to configure a secure proxy through which DeployHQ can forward connections.

## Installation

You'll need Ruby installed on your system. We've tested on 2.7.8 and later.
```
gem install deploy-agent
```

## Usage

Setup agent in a new host
```
$ deploy-agent setup
```

Run agent in foreground
```
$ deploy-agent run
```

Start agent in background
```
$ deploy-agent start
```

## Release

This project uses [Google's release-please](https://github.com/googleapis/release-please) action which automates CHANGELOG generation, the creation of GitHub releases, and version bumps.

**Commit messages are important!**

`release-please` assumes that you are following the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) specification. 
This means that your commit messages should be structured in a way that release-please can determine the type of change that has been made.
Please refer to the ["How should I write my commits"](https://github.com/googleapis/release-please?tab=readme-ov-file#how-should-i-write-my-commits) documentation.
