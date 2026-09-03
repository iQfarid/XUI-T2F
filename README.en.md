[🇮🇷 فارسی](README.md)

# X-UI T2F

A management tool for **3x-ui** that applies a configurable **Traffic Factor** to users' traffic usage.

Each unit of **new traffic** consumed after the factor is enabled is multiplied by the selected factor (**1, 2, 3, or 4**) before being recorded in the panel.

## What does this script do?

- Automatically downloads the 3x-ui source code matching the installed version on the server. The version is detected from the installed binary and can also be entered manually if needed.
- Patches the user's traffic accounting logic in `inbound.go` so that new traffic is multiplied by the selected factor.
- The factor can be applied to **all inbounds** or to **one or more specific inbounds** — the list of active inbounds (Tag, Port, Protocol) is read directly from the panel database and shown for selection.
- Automatically creates source and binary backups before making changes.
- Automatically rolls back the changes if the build fails or the service does not start successfully.
- Provides an option to completely remove the traffic factor and restore the original state. Restoring the original state only replaces the binary and source code — the database and user data remain completely untouched.
- Displays the overall panel status, including the service status, current traffic factor, and selected inbound(s).

## Important

- The factor applies **only to new traffic**.
- Previously recorded traffic is never multiplied again.
- The script **never touches or overwrites the panel database (`x-ui.db`)**. Users, inbounds, and usage histories remain fully intact.

## Requirements

- A Linux server
- 3x-ui already installed
- **Only 3x-ui versions up to v2.9.4 are supported.** Starting from v3.0.0, the internal code structure of the panel changed completely, and this script is not compatible with it.

## Quick Install

```bash
bash <(curl -Ls [https://raw.githubusercontent.com/iQfarid/XUI-T2F/main/farid-t2f.sh](https://raw.githubusercontent.com/iQfarid/XUI-T2F/main/farid-t2f.sh))
