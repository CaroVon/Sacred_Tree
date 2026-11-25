; 神树 Windows 安装包（Inno Setup 6）。由 tools/release/build_release.sh 调用：
;   ISCC /DAppVersion=0.1 /DSrcDir=<导出目录> /DOutDir=<产物目录> installer.iss
; 装到当前用户目录，不需要管理员权限；建桌面与开始菜单快捷方式，带卸载。

#ifndef AppVersion
  #define AppVersion "0.1"
#endif
#ifndef SrcDir
  #define SrcDir "..\..\..\dist\win"
#endif
#ifndef OutDir
  #define OutDir "..\..\..\dist"
#endif

[Setup]
AppId={{6B1E3C52-7F4A-4C1D-9E2B-5A8D3F0C7E11}
AppName=神树 Shen Shu
AppVersion={#AppVersion}
AppVerName=神树 Shen Shu v{#AppVersion}
DefaultDirName={localappdata}\Programs\ShenShu
DefaultGroupName=神树
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir={#OutDir}
OutputBaseFilename=ShenShu-{#AppVersion}-Setup
SetupIconFile=icon.ico
UninstallDisplayIcon={app}\icon.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "zh"; MessagesFile: "ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "快捷方式："

[Files]
Source: "{#SrcDir}\ShenShu.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SrcDir}\ShenShu.pck"; DestDir: "{app}"; Flags: ignoreversion
Source: "icon.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\神树"; Filename: "{app}\ShenShu.exe"; IconFilename: "{app}\icon.ico"
Name: "{group}\卸载神树"; Filename: "{uninstallexe}"
Name: "{userdesktop}\神树"; Filename: "{app}\ShenShu.exe"; IconFilename: "{app}\icon.ico"; Tasks: desktopicon

[Run]
Filename: "{app}\ShenShu.exe"; Description: "立即开始游戏"; Flags: nowait postinstall skipifsilent
