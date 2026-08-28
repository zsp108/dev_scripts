# env_init.sh Usage Guide

## Introduction
This script is used for one-click initialization of the developer's work environment. Core functionalities include:
1. **Workspace Configuration**: Automatically creates or configures a standard development workspace structure.
2. **Charset Configuration**: Unifies the system's default character set (typically UTF-8) to prevent terminal encoding issues.
3. **Network Proxy Configuration**: Automatically configures global terminal proxies to speed up dependency downloads in restricted network environments.

## Running Modes
The script supports different running modes controlled by the `mode` parameter:
- `env`: Only initializes the development environment (charset and Workspace).
- `proxy`: Only configures network proxy environment variables.
- `all`: Performs complete environment and proxy initialization (Default behavior).

## Usage Examples

### 1. Full Initialization (Default)
Run the script directly to configure both environment and proxies:
```bash
./scripts/env_init.sh
# Or explicitly state the mode
./scripts/env_init.sh all
```

### 2. Configure Environment Only
If you don't need proxies and just want to setup the base workspace:
```bash
./scripts/env_init.sh env
```

### 3. (Backward Compatible) Passing Proxy Address
The script also supports passing a proxy address directly to initialize the proxy:
```bash
./scripts/env_init.sh 127.0.0.1:10808
```

