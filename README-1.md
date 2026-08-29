[🇮🇷 فارسی](README.fa.md)

# X-UI T2F

A management tool for **3x-ui** that applies a configurable **Traffic Factor** to users' traffic usage.

Each unit of **new traffic** consumed after the factor is enabled is multiplied by the selected factor (**1, 2, 3, or 4**) before being recorded in the panel.

## What does this script do?

- Automatically downloads the 3x-ui source code matching the installed version on the server. The version is detected from the installed binary and can also be entered manually if needed.
- Patches the user's traffic accounting function (`addClientTraffic`) so that new traffic is multiplied by the selected factor.
- Automatically creates backups before making changes.
- Automatically rolls back the changes if the build fails or the service does not start successfully.
- Provides an option to completely remove the traffic factor and restore the original state.
- Restoring the original state only replaces the binary and source code. The database and user data remain untouched.
- Displays the overall panel status, including the service, binary, source code, database, and current traffic factor.

## Important

The factor applies **only to new traffic**.

Previously recorded traffic is never multiplied again.

The script does **not automatically overwrite the panel database (`x-ui.db`)**. Users and inbounds remain untouched.

## Requirements

- A Linux server
- 3x-ui already installed

## Quick Install

```bash
bash <(curl -Ls https://raw.githubusercontent.com/iQfarid/XUI-T2F/main/farid-t2f.sh)
```

## Run

```bash
chmod +x farid-t2f.sh
sudo ./farid-t2f.sh
```

## ⚠️ Warning

This tool modifies how user traffic usage is calculated in 3x-ui by applying a traffic factor. It is intended for managing cases where the actual cost of traffic or data transfer differs from the raw traffic reported by the panel.

> Public use of this tool is not recommended without understanding how traffic accounting and billing are calculated.
