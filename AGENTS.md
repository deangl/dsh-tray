# dsh-tray

Windows **AutoHotkey v2** tray app that manages the DeepSeek Harness (`dsh`) web service (`http://127.0.0.1:3080`). Single-file app: `dsh-tray.ahk` + `assets/` (tray icons) + `tools/` (helpers).

## Run / verify commands
- Launch: `"C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" dsh-tray.ahk`
- Parse/run check without starting the UI: `... dsh-tray.ahk -stop` (runs `StopDsh()` then exits; exit 0 = ok). There is **no `-check` arg** — passing it makes the script stay resident and `Start-Process -Wait` hangs.
- Stop dsh standalone: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/stop-dsh.ps1`
- Regenerate icons: `node tools/make-icons.mjs` (needs `sharp`; auto-resolves `SHARP_PATH`, `~/.dsh/profiles/node_modules`, `%APPDATA%\npm\node_modules`). Icons are committed; only rerun if the embedded whale SVG changes.

## Headless verification
- dsh running? Probe TCP `127.0.0.1:3080`, or: `Get-CimInstance Win32_Process -Filter "Name='node.exe'" | Where-Object { $_.CommandLine -match 'dsh' }`
- dsh cold start takes ~5-11 s before the port binds.

## Environment
- dsh = npm `@deepseek-ai/dsh`, globally installed as `%APPDATA%\npm\dsh.cmd` (shim → node → `...\node_modules\@deepseek-ai\dsh\lib\bin.js`). It runs as a **node.exe** process.
- Kill target: node.exe processes whose CommandLine matches `dsh[\\/]lib[\\/]bin\.js` or `@deepseek-ai[\\/]dsh`.
- AutoHotkey v2.0.19 at `C:\Program Files\AutoHotkey\v2\`.

## AHK v2 gotchas (hard-won; verify after any edit)
- **Keep `dsh-tray.ahk` UTF-8 with BOM** (first 3 bytes `EF BB BF`) — the Chinese menu labels depend on it. The `write` tool does not add a BOM; re-add via PowerShell after content edits.
- `A_Args.Has("x")` is **index-based**, not value membership. Use `A_Args.Length and A_Args[1] = "-stop"`.
- Do not name a variable `log` (collides with built-in `Log()`).
- In a function, assigning an undeclared name makes it **local**; reading a name that is assigned anywhere in the function fails ("This local variable has not been assigned") unless declared `global`. The status flag uses a function-local `static` for this reason.
- Never do blocking WinHTTP/COM from the status timer — it pumped the message loop and caused **intermittent tray-menu click loss**. `IsRunning()` uses a raw WinSock `connect` (fast, non-pumping).
- `inet_addr` returned a wrong value on this machine — the address comes from the manual dotted-quad parser `ParseAddr()`.
- Never `A_TrayMenu.Rename()` an item at runtime — it silently broke that item's click callback. Menu items are static.
- Terminating via `p.Terminate()` inside a WMI enumeration hung the script — killing is done by `tools/stop-dsh.ps1` (PowerShell CIM).

## Intentional behavior
- Startup does not relaunch dsh if port 3080 is already served; icon state refreshes via a 2 s `UpdateStatus` timer (also called once at startup).
- Exiting/reloading the tray app does **not** stop dsh — `StopDsh()` runs only via the 停止 dsh menu item, the 冷重启 dsh menu item, or the `-stop` CLI arg. So `#SingleInstance Force` reloads just take over the already-running service. Accepted.
- Tray menu is static: 冷重启 dsh / 热重启 dsh / 停止 dsh / 退出. 冷重启 = stop-then-start (runs `StopDsh()` then `StartDsh()`, full cold boot ~5-11 s). 热重启 = process-internal hot reload: `HotRestart()` rewrites the profile's `cordis.patch.yml` byte-for-byte (touch), which dsh's `watchUserPatches`/Cordis HMR picks up and reapplies in-process without restarting the node process — no-op if dsh isn't running. Profile patch path resolves from `$DSH_HOME` else `~/.dsh`, profile name = `DSH_PROFILE` (default `web`). Double-click opens the URL — Edge/Chrome get `--app` mode (default browser via `.html` UserChoice ProgId), anything else plain `Run`; the browser window is then moved/sized per `config.ini` `[window]` (x/y/w/h), or maximized if the config is missing/invalid.

## Layout
- `dsh-tray.ahk` — all logic; config constants at top (`DSH_PORT`, `DSH_HOST`, `ICON_ON`, `ICON_OFF`).
- `assets/whale-blue.ico` (running) / `whale-gray.ico` (stopped); `whale-black.ico` is a spare.
- `tools/stop-dsh.ps1`, `tools/make-icons.mjs`.
