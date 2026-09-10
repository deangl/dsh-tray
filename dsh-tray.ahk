#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; -check: 只加载/解析脚本后立刻退出（不碰 dsh、不建托盘）。注意 #SingleInstance Force
;         是按“脚本文件名”匹配旧实例的，所以要在**副本**上跑，否则会顶掉正在运行的托盘实例。
if A_Args.Length and A_Args[1] = "-check"
    ExitApp
; -stop: 停止 dsh 后退出（用于脚本/命令行调用）
if A_Args.Length and A_Args[1] = "-stop" {
    StopDsh()
    ExitApp
}

; ===== 配置 =====
DSH_PORT   := 3080
DSH_HOST   := "127.0.0.1"
DSH_URL    := "http://" DSH_HOST ":" DSH_PORT
DSH_ARGS   := "--no-open --host " DSH_HOST " --port " DSH_PORT
ICON_ON    := A_ScriptDir "\assets\whale-blue.ico"
ICON_OFF   := A_ScriptDir "\assets\whale-gray.ico"
WIN_CONFIG := A_ScriptDir "\config.ini"
DSH_PROFILE := "web"   ; 热重启的目标 profile（对应 dsh --profile web）

; dsh 的浏览器认证（0.1.5 起）：每个进程随机生成一个 launch token，只有打开
; "dsh web: http://127.0.0.1:3080/?token=..." 这个 URL 才能换取签名 Cookie，
; 之后 30 天内裸地址也能直接进；否则根请求返回
; 401 "dsh web authentication required; reopen the URL printed by dsh web"。
; 托盘用隐藏窗口启动 dsh、看不到控制台，所以把 dsh 的 stdout/stderr 重定向到
; 下面的日志，再从中解析出那一行（dsh 文档钦定的 supervisor 做法）。
DSH_LOG       := A_Temp "\dsh-tray-web.log"
WEB_AUTH_URL  := ""      ; 最近一次捕获到的带 token 的登录 URL（空 = 未知）
WEB_URL_TICKS := 0       ; 等待 dsh 打印 URL 的计时（500ms/次）
WEB_URL_WAIT_TICKS := 60 ; 最多等 30s

; ===== 托盘图标与菜单 =====
A_IconTip := "DeepSeek Harness (dsh)"
TraySetIcon(ICON_OFF)
A_TrayMenu.Delete()
A_TrayMenu.Add("冷重启 dsh", ColdRestartItem)
A_TrayMenu.Add("热重启 dsh", HotRestartItem)
A_TrayMenu.Add("停止 dsh", StopItem)
A_TrayMenu.Add()
A_TrayMenu.Add("退出", ExitDsh)

OnMessage(0x404, TrayIconMsg)

; ===== 状态轮询 =====
SetTimer UpdateStatus, 2000

UpdateStatus() {
    static busy := false, isDshRunning := false
    if busy
        return
    busy := true
    try {
        running := IsRunning()
        if running != isDshRunning {
            isDshRunning := running
            TraySetIcon(running ? ICON_ON : ICON_OFF)
        }
    } finally {
        busy := false
    }
}

; ===== dsh 是否在运行（探测端口，纯 socket，不阻塞消息循环） =====
IsRunning() {
    static init := false, wsa := Buffer(400)
    if !init {
        init := DllCall("ws2_32\WSAStartup", "UShort", 0x0202, "Ptr", wsa) = 0
        if !init
            return false
    }
    sock := DllCall("ws2_32\socket", "Int", 2, "Int", 1, "Int", 6, "Ptr")
    if sock < 0
        return false
    sa := Buffer(16, 0)
    NumPut("UShort", 2, sa, 0)
    NumPut("UShort", DllCall("ws2_32\htons", "UShort", DSH_PORT), sa, 2)
    NumPut("UInt", ParseAddr(DSH_HOST), sa, 4)
    ok := DllCall("ws2_32\connect", "Ptr", sock, "Ptr", sa, "Int", 16) = 0
    DllCall("ws2_32\closesocket", "Ptr", sock)
    return ok
}

; 把 "a.b.c.d" 转成 sockaddr_in 需要的网络字节序地址值
ParseAddr(host) {
    parts := StrSplit(host, ".")
    addr := Integer(parts[4])
    addr := (addr << 8) | Integer(parts[3])
    addr := (addr << 8) | Integer(parts[2])
    addr := (addr << 8) | Integer(parts[1])
    return addr
}

; ===== 定位 dsh 命令 =====
; 返回可直接拼进 "cmd /c call ..." 的命令片段：可执行文件始终带引号
ResolveDshCmd() {
    static dsh := ""
    if dsh != ""
        return dsh
    for c in [
        A_AppData "\npm\dsh.cmd",
        EnvGet("LocalAppData") "\npm\dsh.cmd",
    ] {
        if FileExist(c) {
            dsh := '"' c '"'
            return dsh
        }
    }
    for n in ["npx.cmd", "npx"] {
        p := A_ProgramFiles "\nodejs\" n
        if FileExist(p) {
            dsh := '"' p '" -y @deepseek-ai/dsh'
            return dsh
        }
    }
    return "npx -y @deepseek-ai/dsh"
}

; ===== 启动 / 停止 =====
StartDsh() {
    global WEB_AUTH_URL, WEB_URL_TICKS, DSH_LOG
    if IsRunning()
        return
    WEB_AUTH_URL := ""
    WEB_URL_TICKS := 0
    try FileDelete DSH_LOG
    cmd := ResolveDshCmd()
    ; 走 cmd /c + call，才能把 dsh 的输出重定向进日志（AHK 的 Run 本身拿不到 stdout）
    launch := A_ComSpec ' /c call ' cmd ' web ' DSH_ARGS ' > "' DSH_LOG '" 2>&1'
    try {
        Run launch, , "Hide"
        SetTimer WatchWebUrl, 500
    } catch {
        TrayTip "无法启动 dsh", "命令: " launch, "Iconi"
    }
}

; 轮询日志，抓取 dsh 启动时打印的登录 URL；抓到（或超时）就停表
WatchWebUrl() {
    global WEB_AUTH_URL, WEB_URL_TICKS
    WEB_URL_TICKS += 1
    url := ReadWebAuthUrl()
    if (url != "")
        WEB_AUTH_URL := url
    if (WEB_AUTH_URL != "" or WEB_URL_TICKS >= WEB_URL_WAIT_TICKS)
        SetTimer WatchWebUrl, 0
}

; 从 dsh 输出里取最后一次打印的 "dsh web: <url>"。
; (?s) 让 .* 跨越换行并贪婪匹配，因此热重启再次打印时拿到的是最新那条。
ReadWebAuthUrl() {
    global DSH_LOG
    try txt := FileRead(DSH_LOG, "CP0")
    catch
        return ""
    if RegExMatch(txt, "(?s).*dsh web:\s*(http://\S+)", &m)
        return m[1]
    return ""
}

StopDsh(*) {
    ps := A_ScriptDir "\tools\stop-dsh.ps1"
    try RunWait 'powershell -NoProfile -ExecutionPolicy Bypass -File "' ps '"', , "Hide"
}

; 解析要热重启的 profile 补丁文件。
; dsh 通过 watchUserPatches 用 Cordis HMR 监控该文件，内容一变即进程内事务性重放补丁（不重启进程），
; 因此“touch”它（原样写回，触发 mtime 变化）就能让 dsh 在进程内热重载。
DshProfilePatch() {
    home := EnvGet("DSH_HOME")
    if home = ""
        home := EnvGet("UserProfile") "\.dsh"
    return home "\profiles\" DSH_PROFILE "\cordis.patch.yml"
}

ColdRestartItem(*) {
    StopDsh()
    StartDsh()
}

HotRestartItem(*) {
    global WEB_URL_TICKS
    if !IsRunning()
        return
    patch := DshProfilePatch()
    try {
        content := FileRead(patch)
        f := FileOpen(patch, "w", "UTF-8")
        f.Write(content)
        f.Close()
    } catch {
        TrayTip "热重启失败", "无法写入: " patch, "Iconi"
        return
    }
    ; 热重载可能重建连接、重新分配 launch token 并再打印一行 URL，重新守一下日志
    WEB_URL_TICKS := 0
    SetTimer WatchWebUrl, 500
}

StopItem(*) {
    StopDsh()
}

ExitDsh(*) {
    ExitApp
}

; ===== 双击：用默认浏览器打开（Edge/Chrome 走 --app 模式） =====
TrayIconMsg(wParam, lParam, msg, hwnd) {
    if lParam = 0x0203
        OpenDshWeb()
}

OpenDshWeb() {
    global WEB_AUTH_URL
    ; 优先用带 token 的登录 URL：它会顺带刷新 30 天 Cookie；
    ; 拿不到时退回裸地址（Cookie 还在的话照样能进）
    url := WEB_AUTH_URL
    if (url = "")
        url := ReadWebAuthUrl()
    if (url = "") {
        url := DSH_URL
        TrayTip "dsh 登录 URL 未知", "浏览器若提示 authentication required，请用「冷重启 dsh」重建。", "Iconi"
    }
    progId := ""
    try progId := RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.html\UserChoice", "ProgId")
    if RegExMatch(progId, "i)MSEdge") {
        if (exe := FindBrowser("msedge.exe"))
            Run '"' exe '" --app="' url '"'
        else
            Run url
    } else if RegExMatch(progId, "i)Chrome") {
        if (exe := FindBrowser("chrome.exe"))
            Run '"' exe '" --app="' url '"'
        else
            Run url
    } else {
        Run url
    }
    PositionWindow()
}

; 读配置文件里的位置尺寸；读不到（缺文件/缺键/非法值）返回 false → 全屏
ReadWindowConfig(&x, &y, &w, &h) {
    try {
        x := IniRead(WIN_CONFIG, "window", "x", "")
        y := IniRead(WIN_CONFIG, "window", "y", "")
        w := IniRead(WIN_CONFIG, "window", "w", "")
        h := IniRead(WIN_CONFIG, "window", "h", "")
    } catch
        return false
    if !IsNumber(x) or !IsNumber(y) or !IsNumber(w) or !IsNumber(h)
        return false
    if x < 0 or y < 0 or w <= 0 or h <= 0
        return false
    return true
}

; 按配置移动/缩放已打开的浏览器窗口；配置读不到则最大化
PositionWindow() {
    SetTitleMatchMode 2
    if !WinWait("DeepSeek Harness", , 5)
        return
    hwnd := WinExist("DeepSeek Harness")
    if ReadWindowConfig(&x, &y, &w, &h)
        WinMove(x, y, w, h, hwnd)
    else
        WinMaximize(hwnd)
}

FindBrowser(exe) {
    try {
        p := RegRead("HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\" exe)
        if p != "" and FileExist(p)
            return p
    }
    for base in [A_ProgramFiles, A_ProgramFiles " (x86)"]
        for dir in ["Microsoft\Edge\Application", "Google\Chrome\Application"] {
            p := base "\" dir "\" exe
            if FileExist(p)
                return p
        }
    return ""
}

; ===== 启动时自动在后台运行 dsh web（已在运行则不重复启动） =====
if IsRunning()
    WEB_AUTH_URL := ReadWebAuthUrl()   ; 托盘重启：复用仍在跑的那个 dsh 打印过的登录 URL
else
    StartDsh()
UpdateStatus()
