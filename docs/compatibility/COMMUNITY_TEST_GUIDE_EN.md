# Community Compatibility Test Guide

[简体中文](COMMUNITY_TEST_GUIDE_ZH.md)

This guide corresponds to `testSuiteVersion: 2`. The goal is to check user-visible LanStash behavior for a version combination. It is not a private-API discovery process and does not require network captures or diagnostic logs. Version 1 reports remain valid but do not include desktop cloud-drive checks.

## Before testing

- Confirm that you own the NAS and account or have explicit authorization to test them.
- Record the LanStash version, client platform version, public NAS product model, complete DSM build, and relevant package versions.
- Do not record a serial number, device name, address, QuickConnect ID, or account name.
- Prefer a normal account that does not affect other users. Record `administrator` only when the normal product flow genuinely requires it.
- Use a new empty folder and a small disposable file for write tests. Never use real photos, documents, or backups.
- Select `skipped` whenever you are unsure whether an operation is safe.

## Result values

| Value | When to use it |
| --- | --- |
| `passed` | Every step completed and the result matched the UI |
| `failed` | The operation could not complete or produced a wrong result |
| `partial` | Only part of the flow worked or the outcome was inconsistent |
| `skipped` | The environment was unsuitable or you chose not to perform the test |
| `not-supported` | The environment explicitly reported that the capability is unavailable |

For `failed` and `partial`, also select one fixed failure category:

- `permission-denied`
- `operation-failed`
- `connection-failed`
- `unexpected-result`
- `app-crashed`
- `unknown`

Do not paste a raw error, log, path, or screenshot.

## macOS desktop cloud-drive tests

These capabilities apply only to macOS. iPhone, iPad, Android, and Windows
reports should record `not-supported`; regular file browsing cannot substitute
for a Finder cloud-drive result. Use a dedicated test folder containing no real
data. Adding and removing a mapping changes local Finder state but should not
modify NAS files.

### `desktop-drive.mount`: add and remove a mapping

Map the dedicated test folder, confirm that it appears in Finder with the
expected name, then remove it and confirm that the Finder entry disappears. Do
not record the mapping name or local path.

### `desktop-drive.browse`: browse a large folder

Open a folder with at least 1,000 synthetic items, scroll continuously, and
switch between subfolders. The list should remain responsive and should stop
loading after cancellation or navigation. Record only a size category for
10,000- or 100,000-item tests, never file names.

### `desktop-drive.download-resume`: interrupt and resume

Open a disposable large test file, interrupt the network or stop reading during
download, then open it again. The transfer should resume from existing progress
and the final content should match the NAS test file. Do not submit checksums or
file names.

### `desktop-drive.keep-offline`: local-copy lifecycle

Start keeping the test folder offline, observe progress, and cancel. Start again
and wait for completion, verify reading while disconnected, then release local
copies. An out-of-space state should explain what happened and the next action
without breaking other mappings.

### `desktop-drive.upgrade-restore`: upgrade recovery

Install the candidate over the previous public version without removing the
mapping first. After signing in again, confirm that the mapping, pause state,
and cache-location policy remain and browsing works. Recreating a deleted
mapping is not an upgrade-recovery result.

## Read-only and sign-in tests

### `connection.resolve`: discover and connect to the NAS

Open the sign-in flow with your normal connection method. Mark it passed when LanStash finds the expected NAS and identifies the intended target before credentials are submitted. Select only a connection category in the report; never enter an address or QuickConnect ID.

### `authentication.password`: password sign-in

Complete a normal sign-in with the test account. Never put the account, password, or raw error response in the report.

### `authentication.otp`: two-factor sign-in

Run this only when two-factor authentication is already enabled for the test account. Confirm that LanStash reaches the verification step and completes sign-in. Otherwise select `skipped`.

### `authentication.restore-session`: restore sign-in after reopening the app

After signing in, close and reopen the app normally. Confirm that it restores the session or asks you to sign in according to the current setting, without switching to the wrong account or NAS.

### `files.list-shares`: list shared folders

Open Files and confirm that shared folders available to the current account appear. Do not record their names.

### `files.browse`: browse folders

Open an authorized folder and navigate back. Confirm that the item list and navigation work. Do not record real folder or file names.

### `files.search`: search files

Search for a disposable item inside the dedicated test folder and confirm that the result opens. Do not include the search term in the report.

### `files.download`: download a file

Download a small non-sensitive test file and confirm that it completes and opens. Delete the local client copy after testing.

## Controlled write tests

Every test below is optional. Use only dedicated test items. Never use production data, the only copy of a file, or a shared working folder.

### `files.upload`: upload a test file

Upload a small non-sensitive test file and confirm that the complete item is visible on the NAS.

### `files.create-folder`: create a test folder

Create an empty folder under the test folder. Confirm that it remains visible after a refresh.

### `files.rename`: rename a test item

Rename the item created for testing. Confirm that the new name appears and the old name disappears.

### `files.copy-move`: copy or move a test item

Copy or move the disposable item between two test folders. Confirm that the target appears. For a move, also confirm that the source disappears.

### `files.recycle`: move a test item to the recycle bin

Run this only when the shared folder already has a recycle bin. Use a disposable item, confirm that LanStash asks before deletion, and confirm that the item leaves its original location. Select `not-supported` or `skipped` when no recycle bin is available; do not perform a permanent deletion.

### `files.restore`: restore a test item

Restore only the item produced by the previous test and confirm that it returns to the intended test folder. Never restore over a real file.

## Cleanup

- Remove test items through the normal UI after confirming that they are no longer needed.
- Do not permanently empty a recycle bin merely to complete this report.
- Delete local downloads and temporary test content.
- Before submitting, confirm again that the report contains no account, host, path, file name, log, or raw response.

If cleanup fails, do not repeat a dangerous operation. Stop testing and select the appropriate failure category.
