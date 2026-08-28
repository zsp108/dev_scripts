# codex_switch.sh Usage Guide

## Introduction
In development environments, it's often necessary to frequently switch between multiple Codex accounts or environmental configurations. This tool abstracts configurations into different "components", enabling seamless backups and one-click switching between multiple states like `auth.json` and `config.toml`.

## Usage Examples

### 1. Backup Current Configuration
Safely save the current state before manipulating configurations:
```bash
./scripts/tools/codex_switch.sh config backup
./scripts/tools/codex_switch.sh auth backup
```

### 2. Switch to a Specific Account/Profile
Assuming you have a backup config named `prod` (`config_prod.toml`):
```bash
./scripts/tools/codex_switch.sh config switch prod
```

### 3. Check Current Credentials Status
View which configuration's credentials are currently in use:
```bash
./scripts/tools/codex_switch.sh auth status
```

