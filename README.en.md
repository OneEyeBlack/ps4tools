# PS4Tools

**[Português](README.md) | English (current)**

<p align="center">
  <img src="components/icons8-playstation-windows-11-color/icons8-playstation-100.png" alt="PS4Tools icon" width="96">
</p>

<p align="center"><strong>Windows tool for managing, backing up and synchronizing saves and trophies between PS4 consoles.</strong></p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-Windows-0078D4?style=flat-square" alt="Windows">
  <img src="https://img.shields.io/badge/language-Delphi-EE1F35?style=flat-square" alt="Delphi">
  <img src="https://img.shields.io/badge/network-FTP%3A2121-2ea44f?style=flat-square" alt="FTP port 2121">
</p>

> PS4Tools is intended for PS4 consoles with FTP access enabled. It is not a jailbreak, does not replace GoldHEN and still requires compatible payloads/tools on the console.

![PS4Tools workflow](images/ps4tools-workflow.svg)

## What it is

PS4Tools is a Delphi desktop utility that simplifies tasks that would normally require manually browsing PS4 files. It connects to consoles over the local network, discovers users and games, and lets you work selectively with the data you choose.

The application includes Portuguese, English, Spanish, German, French, Russian and Japanese translations. Long-running operations run in the background while the log and progress are displayed.

## Main features

### Saves

- list users available on the PS4;
- load saves for the selected user;
- synchronize selected saves between two PS4 consoles;
- copy saves between different users on the same console;
- export decrypted saves to a local folder;
- import local backups into a PS4 user;
- delete selected saves;
- choose exactly which games to process.

### Trophies

- load each user's title list and trophy progress;
- copy selected titles between users/consoles;
- back up trophy state;
- restore a backup;
- delete selected titles;
- sort titles alphabetically.

Trophy operations work with the user's `trophy_local.db` database. Always create a backup before making changes.

### Save synchronization modes

| Mode | When to use it | How it works |
|---|---|---|
| **Manual** | When you want to control the import through Apollo | Copies encrypted saves to Apollo's Fake USB on the destination PS4. Apollo must then import/sign the saves and copy them to the HDD. |
| **Automatic — same PS4** | To copy between two users on the same console | Uses the payload to mount/decrypt the source save, copy its contents to the destination user, and unmount it so the PS4 can re-encrypt it. |
| **Automatic — two PS4s** | To transfer saves between different consoles | Creates a decrypted backup on the PC and uses **PS4 Save Agent** on the destination console to recreate/re-encrypt the save for the selected user. |

## Requirements

- Windows 10 or later;
- PC and PS4 on the same local network;
- PS4 FTP enabled and accessible on port `2121`;
- GoldHEN or a compatible environment for payload execution when using automatic mode;
- Apollo Save Tool for manual mode;
- **PS4 Save Agent** installed on the destination PS4 for automatic transfers between consoles;
- Account ID activated for the users involved when automatic mode requests it;
- your own backups and authorization to modify the consoles' data.

## Download and run

Download the Windows package from the GitHub Releases page and extract it while preserving the folder structure. The distributed executable is:

```text
PS4Tools/PS4Tools.exe
```

Run `PS4Tools.exe` as a normal user. Keep the components and payloads distributed with the package in their expected folders. The application stores IP, language and synchronization-mode preferences locally.

## How to use — saves

1. Start FTP on the PS4(s) and confirm that the PC can reach the IP address(es).
2. Open PS4Tools and enter the source and destination IP addresses. For same-console operations, enter the same IP in both fields.
3. Click **Load users**.
4. Select the source and destination users. On the same PS4, they must be different users.
5. Load the source user's saves and check the games you want.
6. Choose **Automatic** or **Manual**.
7. Click **Start synchronization**, review the confirmation and wait for the log to report completion.
8. In manual mode, open Apollo on the destination PS4, import/sign the saves from Fake USB and copy them to the HDD.

### Exporting and importing a save

In the **Saves** tab, load the desired user's games, select the items and click **Export save**. The decrypted backup is stored in the `Saves descriptografados` folder next to the executable. To restore it, click **Import save**, choose the backup folder and select the destination user.

## How to use — trophies

1. Open the **Trophies** tab.
2. Enter the IP addresses and load the users.
3. Select a user on each side and click **Load trophies**.
4. Check the desired titles.
5. Use **Backup** before editing, then choose **Copy**, **Delete**, **Sort** or **Restore** as needed.

## PS4 Save Agent

The repository includes the payload and base source under `tools/ps4-save-agent`. The binary expected by the application is:

```text
payloads/ps4-save-agent.elf
```

On the PS4, the Agent must be available at `/data/payloads/ps4-save-agent.elf` and is normally started from GoldHEN's payload menu. It exposes a local HTTP API on port `8084` for decrypted export, import and synchronization operations.

> The payload depends on a compatible PS4 SDK and internal system functions such as PFS mounting. The PC cannot perform these steps by itself. See [`tools/ps4-save-agent/README.md`](tools/ps4-save-agent/README.md) for the API and build specification.

## Safety recommendations

- Back up before importing, deleting, copying trophies or synchronizing saves.
- Do not power off the PS4, stop FTP or close the application during an operation.
- Do not use saves from unknown sources or incompatible game/system versions.
- Double-check IP addresses and users: a destination operation may replace existing data.
- Use this tool only with consoles and data you own or are authorized to modify.

## Project structure

```text
PS4Tools.dpr                 Main Delphi project
sources/                     Interface and operation source code
components/                  Components and auxiliary payloads
payloads/                    PS4 Save Agent payloads and logs
tools/ps4-save-agent/        Agent source code and documentation
images/                      Documentation icons and images
```

## Development

This is a Delphi VCL application. To compile it, open `PS4Tools.dproj` in a compatible RAD Studio/Delphi version, verify the configured Indy and SQLite dependencies, and build for Windows. The current project configuration outputs the executable to `Win32/Debug/PS4Tools/`.

## Status

The desktop application includes FTP, save, trophy, backup and translation workflows. **PS4 Save Agent** is a separate component that depends on PS4-specific code being compiled and executed; validate the payload in your environment before using automatic synchronization between consoles.

## License

No license file was found in this repository. Before redistributing or incorporating the project into another product, confirm the rights for the code, third-party components and included assets.
