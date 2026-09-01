[🇮🇷 فارسی](README.md)

# X-UI T2F

A management tool for **3x-ui** that applies a configurable **Traffic Factor** to users' traffic usage.

Each unit of **new traffic** consumed after the factor is enabled is multiplied by the selected factor (**1, 2, 3, or 4**) before being recorded in the panel.

## What does this script do?

- Automatically downloads the 3x-ui source code matching the installed version on the server. The version is detected from the installed binary and can also be entered manually if needed.
- Patches the user's traffic accounting function (`addClientTraffic`) so that new traffic is multiplied by the selected factor.
- The factor can be applied to **all inbounds** or to **one or more specific inbounds** — the list of active inbounds (Tag, Port, Protocol) is read directly from the panel database and shown for selection.
- Automatically creates backups before making changes.
- Automatically rolls back the changes if the build fails or the service does not start successfully.
- Provides an option to completely remove the traffic factor and restore the original state. Restoring the original state only replaces the binary and source code — the database and user data remain untouched.
- Displays the overall panel status, including the service, binary, source code, database, current traffic factor, and selected inbound(s).

## Important

The factor applies **only to new traffic**.

Previously recorded traffic is never multiplied again.

The script does **not automatically overwrite the panel database (`x-ui.db`)**. Users and inbounds remain untouched.

## Requirements

- A Linux server
- 3x-ui already installed
- **Only 3x-ui versions up to v2.9.4 are supported.** Starting from v3.0.0, the internal code structure of the panel changed completely, and this script is not compatible with it.

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

This script **manipulates** users' actual traffic usage by the selected factor (2, 3, or 4) — meaning what is shown in the panel and to the user is higher than their actual usage.

If this panel is used to sell service to customers, using this tool **without clearly informing the customer** can be a misleading and unfair practice toward the end user — in effect, the volume they purchased will run out faster than what they actually consumed.

**Public use of this tool is not recommended**, unless you have a clear, disclosed reason for the usage (for example, accounting for protocol overhead on a specific plan that has been explained to the customer in advance). Responsibility for any use of this tool, including its consequences for end users, lies with whoever runs it.
