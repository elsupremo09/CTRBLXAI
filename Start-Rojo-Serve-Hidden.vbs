Option Explicit

' Starts Rojo in this project without showing a Command Prompt window.
Dim shell, command
Set shell = CreateObject("WScript.Shell")

command = "cmd.exe /d /c ""cd /d """"D:\AI\Projects\CTRBLXAI"""" && rojo serve"""
shell.Run command, 0, False
