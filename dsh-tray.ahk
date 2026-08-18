#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

if A_Args.Length and A_Args[1] = "-stop" {
    StopDsh()
    ExitApp
}

; ===== 配置 =====
DSH_PORT   := 3080
DSH_HOST   := "127.0.0.1"
DSH_URL    := "http://" DSH_HOST ":" DSH_PORT
DSH_ARGS   := "--host " DSH_HOST " --port " DSH_PORT
ICON_ON    := A_ScriptDir "\assets\whale-blue.ico"
ICON_OFF   := A_ScriptDir "\assets\whale-gray.ico"

; ===== 托盘图标与菜单 =====
A_IconTip := "DeepSeek Harness (dsh)"
TraySetIcon(ICON_OFF)
A_TrayMenu.Delete()
A_TrayMenu.Add("启动 dsh", StartItem)
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
ResolveDshCmd() {
    static dsh := ""
    if dsh != ""
        return dsh
    for c in [
        A_AppData "\npm\dsh.cmd",
        EnvGet("LocalAppData") "\npm\dsh.cmd",
    ] {
        if FileExist(c) {
            dsh := c
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
    if IsRunning()
        return
    cmd := ResolveDshCmd()
    launch := cmd " web " DSH_ARGS
    try {
        Run launch, , "Hide"
    } catch {
        TrayTip "无法启动 dsh", "命令: " launch, "Iconi"
    }
}

StopDsh(*) {
    ps := A_ScriptDir "\tools\stop-dsh.ps1"
    try RunWait 'powershell -NoProfile -ExecutionPolicy Bypass -File "' ps '"', , "Hide"
}
OnExit StopDsh

StartItem(*) {
    StartDsh()
}

StopItem(*) {
    StopDsh()
}

ExitDsh(*) {
    StopDsh()
    ExitApp
}

; ===== 双击：用默认浏览器打开（Edge/Chrome 走 --app 模式） =====
TrayIconMsg(wParam, lParam, msg, hwnd) {
    if lParam = 0x0203
        OpenDshWeb()
}

OpenDshWeb() {
    progId := ""
    try progId := RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.html\UserChoice", "ProgId")
    if RegExMatch(progId, "i)MSEdge") {
        if (exe := FindBrowser("msedge.exe"))
            Run '"' exe '" --app="' DSH_URL '"'
        else
            Run DSH_URL
    } else if RegExMatch(progId, "i)Chrome") {
        if (exe := FindBrowser("chrome.exe"))
            Run '"' exe '" --app="' DSH_URL '"'
        else
            Run DSH_URL
    } else {
        Run DSH_URL
    }
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
StartDsh()
UpdateStatus()
