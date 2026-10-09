# 验证报告

更新日期：2026-10-09（补充 PR 评审修订验证）。当前版本：0.3.1（工程修复 + 发布 / 部署完善；T-SQL 双引号新增对 `SET QUOTED_IDENTIFIER OFF` 的支持，其余功能、支持范围与 0.3.0 一致）。

## 0.3.1 结果摘要

- 彻底修复 Visual Studio IDE 设计时（IntelliSense / 错误列表）对 `Microsoft.VisualStudio.*`（Shell、Utilities、Text、Threading 等）报“类型或命名空间不存在”的问题。
  - 真正根因：现代包工程此前用硬编码相对 HintPath 引用 VSSDK.BuildTools 包内部 `tools\vssdk` 与 `tools\vssdk\bin\lib` 下的 Shell、Interop、Threading、Validation、Utilities 等程序集，路径写死仓库本地 `.packages` 且依赖该包内部布局。命令行按仓库 `NuGet.Config` 还原到 `.packages` 时可编译，但 IDE 设计时在尚未还原完成、或把包还原到全局缓存等其它位置时，这些 HintPath 整体失效，相关命名空间集体报红。上一版仅补单个 Utilities 的 HintPath 未根治。
  - 修复方式（仅改工程，不改功能）：现代工程的 Visual Studio 引用全部改为官方 VSSDK 17 NuGet `PackageReference`（`Text.UI.Wpf 17.14.249`、`Shell.15.0 17.14.40264`、`Shell.Framework 17.14.40264`、`Threading 17.14.15`、`Imaging.Interop.14.0.DesignTime 17.14.40254`，均 `ExcludeAssets/PrivateAssets=runtime`），与 Legacy 工程的 VSSDK 15 正规包写法同构；Utilities、Interop、ComponentModelHost、Imaging 等由 Shell.15.0 的 NuGet 依赖闭包自动带入。同时删除全部 VSSDK.BuildTools 内部 HintPath 与写死 `.packages` 的 pkgdef 兜底 target；`VSSDK.BuildTools` 仅保留为打包工具。
- 工程级验证（本轮新增）：
  - 设计时构建（`DesignTimeBuild=true`）枚举 IDE 实际 `ReferencePath`：Shell / Shell.Framework / Utilities / Interop / Text.* / Threading / Validation 及 CreatePkgDef 反射所需的 ComponentModelHost / Imaging / RpcContracts / Telemetry 等共 21 个 Visual Studio 程序集全部来自正规 NuGet 包的 `lib` 目录，无一条 `tools\vssdk` 内部 HintPath；设计时与命令行引用集完全一致。
  - 将包还原到与仓库 `.packages` 完全无关的全新全局文件夹、删除 bin/obj 重新还原后再做设计时构建，21 个 Visual Studio 引用仍全部正确解析、关键程序集（Shell.15.0 / Utilities / Interop / Text.UI.Wpf / Threading / Shell.Framework）齐全，证明结果与 NuGet 包还原位置无关。
  - 移除 pkgdef 兜底 target 后，CreatePkgDef 仍正常完成、VSIX 正常生成，说明正规包闭包已提供 pkgdef 反射所需的全部宿主程序集。
- 程序集版本统一（消除 MSB3277）：VSSDK 17.14 的 Shell / Utilities / Imaging / Threading 与 System.Text.Json 9.0 闭包要求 `Microsoft.Bcl.AsyncInterfaces 9.0.0`，工程此前显式钉 8.0.0，导致 NuGet 主引用 8.0.0 与宿主 PublicAssemblies / 传递包统一到的 9.0.0.0 冲突。已将显式引用对齐到 9.0.0（`ExcludeAssets=runtime`）；命令行 Rebuild（`/v:normal`）与 IDE 设计时构建均不再出现 MSB3277。该程序集仅为传递依赖、本扩展不直接引用，且不拷入 VSIX（运行时由 VS 2022 17.14 / SSMS 22 宿主提供 9.0.0.0），VSIX 仍为 8 个条目。
- Release 干净重建 0 错误；**143 项自动化测试全部通过（含 5 项 SET QUOTED_IDENTIFIER ON/OFF 用例）**；`Verify-Package.ps1` / `Verify-LegacyPackage.ps1` 均通过。现代 VSIX 仍为 8 个条目、不捆绑任何宿主 DLL；现代 `SmartInput.VisualStudio.dll` 经 PE / COR20 头核对为 AnyCPU (ILOnly)，绑定 VSSDK 17（Shell / Text / Utilities 等为 17.0.0.0，Threading 为 17.14.0.0）；Legacy 负载仍为 ILOnly / AnyCPU、引用程序集全部绑定 VSSDK 15。
- 已在“无 .NET SDK”条件下复现：从 PATH 移除 dotnet、清空 `MSBuildSDKsPath` / `DOTNET_ROOT`、清空各工程 bin/obj 后运行 `build.ps1 -Configuration Release`，Restore → 四工程构建 → 143 项测试 → 现代 VSIX 与 Legacy 负载双校验全部通过。
- 版本号统一为 0.3.1（现代 VSIX Identity、Legacy 清单与 pkgdef、两个程序集版本、`InstalledProductRegistration`、文档）。
- SSMS 22 已在 0.3.1 阶段完成首轮实机验证（2026-10-07，SSMS 22.10.12210.168 / x64 + 搜狗拼音）：部署、MEF 加载、菜单命令、状态栏、T-SQL 上下文识别，以及搜狗拼音的中英文**自动切换与手动 Shift 切换均通过**；微软拼音（未单独测）与 SSMS 18/19/20 仍待实测。详见下文“SSMS 22 实机验证记录”与 `MANUAL-TESTS.md`。
- PR 评审修订（2026-10-09）已在本机 Release 构建与脚本演练中验证：
  - `build.ps1 -Configuration Release` 干净跑通（VS 2026 MSBuild + NuGet 还原，未使用 dotnet / .NET SDK 命令）；**143 项测试 0 失败**，测试程序确为 `tests/SmartInput.Tests/bin/Release/SmartInput.Tests.exe`（Release 配置），已无“取目录中最新 exe”兜底；现代 VSIX（8 条目）与 Legacy 负载（AnyCPU / VSSDK 15）双校验通过。
  - `tools/Pack-Release.ps1` 生成 `artifacts/SmartInput-SSMS22.zip`（3 条目：VSIX、部署脚本、安装说明）与 `artifacts/SmartInput-SSMS-Legacy.zip`（6 条目：四个平铺文件、部署脚本、安装说明），条目齐全。
  - `Deploy-SSMS22.ps1 -WhatIf`（本机 D 盘自定义 SSMS 22 安装）实测：备份、删除私有注册表 / MEF 缓存、写信号、平铺扩展均只打印 `WhatIf:` 而不执行；运行前后 `privateregistry.bin`、`ComponentModelCache`、扩展目录与信号文件的大小 / 时间戳完全不变，也未创建备份目录；非管理员、SSMS 开启状态下即可演练。`Deploy-SSMS-Legacy.ps1 -WhatIf` 在未安装 18/19/20 时优雅退出（退出码 0）。
  - 将发布 zip 解压到临时目录、不传载荷路径运行部署脚本，确认同目录 VSIX / 平铺文件自动回退定位生效。

## 0.3.0 结果摘要

- MSBuild 17.14 / .NET Framework 4.8 Release 构建成功，解决方案包含 `SmartInput.Core`、`SmartInput.VisualStudio`（现代包）、`SmartInput.Ssms.Legacy`（32 位包）、`SmartInput.Tests` 四个工程。
- `SmartInput.Tests.exe`：**138 项测试通过，0 项失败**（在 0.2.1 的 104 项基础上新增 34 项 T-SQL 用例）。覆盖 C/C++、C#、T-SQL 三语言的语法边界、手动覆盖状态机、Profile 匹配、随机文本鲁棒性（三语言逐位置查询）、性能样本和光标绘制 / 生命周期测试。
- T-SQL 用例覆盖：`--` 行注释、可嵌套 `/* */` 块注释、单引号字符串（`N''`、`''` 转义、跨行）、空 / 英文 / 仅 emoji 字符串、`[括号]` 与 `"双引号"` 标识符、字符串 / 括号内部定界符不误判、负数单减号、扩展区汉字等。
- 性能样本：520,000 字符扫描约 8ms；扫描加 100,000 次位置查询约 12ms。此为核心算法样本，不代表宿主实际输入延迟。
- 现代 VSIX 检查通过（`tools/Verify-Package.ps1`）：目标含 Visual Studio `[17.14,)` / amd64 与 SSMS `Microsoft.VisualStudio.Ssms [21.0,23.0)` / amd64；MEF 入口、VS Package 入口、菜单资源、`工具 > 选项 > Smart Input > 常规` 设置页、程序集版本与依赖隔离均正确；安装包不捆绑宿主 DLL。
- Legacy 负载检查通过（`tools/Verify-LegacyPackage.ps1`）：
  - 输出含 `SmartInput.VisualStudio.dll`、`SmartInput.Core.dll`、`SmartInput.VisualStudio.pkgdef`、`extension.vsixmanifest`。
  - 两个 DLL 均为 **ILOnly / AnyCPU**，可被 32 位 SSMS 进程加载。
  - `SmartInput.VisualStudio.dll` 引用的 `Microsoft.VisualStudio.*` 程序集强名称版本全部为 **15.x**（Text.Data/Logic/UI/UI.Wpf、CoreUtility、Shell.15.0、Shell.Framework 为 15.0.0.0，Threading 为 15.8.0.0），不含 16/17 绑定。
  - 手写 pkgdef 含 Package 注册、`CodeBase` 与 NoSolution 自动加载项；v1 清单含 `<IsolatedShell>ssms</IsolatedShell>`、`MefComponent` 与 `VsPackage`。
- 部署脚本 `Deploy-SSMS22.ps1` / `Deploy-SSMS-Legacy.ps1` 的路径、文件清单与缓存清理逻辑对照参考实现（mourier/sql-pilot）编写，并通过静态检查；脚本支持 `-WhatIf` 与 `-Uninstall`。

## SSMS 22 实机验证记录（0.3.1，2026-10-07）

环境：Windows 11、SSMS 22.10.12210.168（stable，x64，基于 VS 2026 Shell，自定义安装于 D 盘）、本地 SQL Server 17.0 默认实例、Windows 身份验证连接、活动输入法为搜狗拼音（微软拼音已安装，但本轮未作为活动输入法测试）。

部署与加载（通过）：

- 以管理员 PowerShell 运行 `tools\Deploy-SSMS22.ps1 -SsmsIdeDir '<IDE 目录>'`，6 个文件平铺到 `Common7\IDE\Extensions\SmartInput`，私有注册表与 MEF 缓存被清理；`Ssms.exe -log` 的 `ActivityLog.xml` 记录了 `smartinput.visualstudio.pkgdef` 扫描，扩展被 MEF 成功加载，全程无崩溃。
- `工具` 菜单出现 `Smart Input: 暂停/恢复自动切换` 命令；新建查询后 T-SQL 编辑器左下角出现 `Smart Input` 状态条。

上下文识别与交互（通过）：

- 光标在普通代码 / 空行 / `SELECT` 行显示“自动 · 英文 · 代码”；在 `/* … */` 块注释内显示“自动 · 中文 · 注释”；存在文本选区时显示“选区中，暂不切换”。
- 手动按 Shift 进入“手动覆盖 · 中/英文”，与推荐态不符时输入光标变为配置的提示色；移动到其它文本区域后手动覆盖自动解除、恢复“自动”。暂停 / 恢复命令可用。

物理输入法自动 / 手动切换（搜狗拼音：通过）：

- 用物理键盘实测：鼠标在普通代码区与 `/* … */` 注释区（及含汉字字符串）之间移动时，搜狗拼音随上下文自动切换——代码区直接上屏英文，注释区可输入中文；移动光标即自动切换，无需额外按键。
- 手动按 Shift 的手动覆盖同样正常：进入与推荐态不符的输入态时显示提示色光标，移动到其它区域后自动恢复自动模式；暂停 / 恢复、选区与组词期间不切换等行为均符合预期，未出现“状态条正确但输入法不跟随”的情况。

仍待实测：

- SSMS 22 + **微软拼音**的自动切换未单独实测（本轮活动输入法为搜狗拼音；微软拼音走 WPF 原生 TSF 通道、不模拟按键，预期同样可用，欢迎反馈）。
- SSMS 18 / 19 / 20（32 位 Legacy 包）：本机未安装，加载、ContentType 运行时名称与输入法切换均未实测。
- SSMS 22 除深色主题 / 当前 DPI 外的其它主题、显示缩放组合。

## 0.3.0 尚未覆盖的验证（重要）

- **构建机未安装任何版本 SSMS**，以下内容**未经实机验证**，需在装有 SSMS 的机器上按 `MANUAL-TESTS.md` 确认：
  - SSMS 22 与 SSMS 18/19/20 是否成功发现并加载扩展（pkgdef 扫描、MEF 组合、私有注册表缓存重建）。
  - SSMS 查询编辑器 ContentType 的运行时实际名称（已用精确 `SQL` + 按类型名含 “SQL” 兜底双保险降低风险，但仍需实测）。
  - SSMS 宿主内微软拼音 / 搜狗拼音的状态读取与切换表现。
  - 选项页、状态栏在 SSMS 各版本中的显示。
- 现代包在 Visual Studio 中的 C/C++、C# 行为延续 0.2.1；新增的 T-SQL 路径在 Visual Studio SQL 编辑器中也建议实测。
- SSMS 18/19/20 Legacy 包不编译菜单资源，因此不提供“工具”菜单命令，预期通过状态栏按钮暂停 / 恢复；该差异未在实机确认。
- 部署脚本未在真实 SSMS 目录上执行过（构建机无该目录），仅做了逻辑与路径静态核对。

## 0.2.1 实机验证记录（历史，沿用）

0.2.1 Release VSIX SHA256：`7A0679D76B1865B1590A3B2F7D31CD3C622A4005F95A556884EC3436F038E65D`

- MSBuild 17.14 / .NET Framework 4.8 Release 构建成功，无警告、无错误；当时 104 项自动化测试通过。
- 只读 COM 互操作检查通过：x64 `TF_INPUTPROCESSORPROFILE` 布局为 88 字节；搜狗 16.8.0.4914 已注册为 TIP `{E7EA138E-69F8-11D7-A6EA-00065B844310}`，Profile `{E7EA138F-69F8-11D7-A6EA-00065B844311}`。
- 独立 WPF 探针验证搜狗 `On + Alphanumeric` 读取与 `Off` / `On + Native` 写入、进程结束后恢复；生产程序集工厂探针正确选中 `SogouInputMethod`；探针均未激活输入法或修改默认设置。
- 针对搜狗在 Visual Studio 2026 中状态栏与实际输出不一致的问题，0.2.1 增加 IMM32 状态读取并在确认失败时最多模拟一次已配置 `Shift`；微软拼音不走模拟按键路径。用户反馈环境完成回归，未复现原问题。

### 平台与输入法（0.2.1 实机）

| 环境 | 结果 |
| --- | --- |
| Windows 10 x64 / Visual Studio 2022 / 微软拼音 | 已通过 |
| Windows 11 x64 / Visual Studio 2022 17.14.21 / 微软拼音 | 已通过 |
| Windows 11 x64 / Visual Studio 2022 17.14.21 / 搜狗拼音 16.8.0.4914 | 已通过 |
| Windows 11 x64 / Visual Studio 2026 / 微软拼音 | 已通过 |
| 微软拼音与搜狗拼音共存 | 已通过；只控制当前活动 Profile |
| 主题、DPI、插入/覆盖、多视图和快速切换 | 已通过 |

实机验证覆盖 C++ / C# 代码、注释、字符串、插值字符串、候选窗、Escape、手动覆盖、连续输入、切换文档和失焦场景。

## 版本历史

- 0.3.1：工程修复版，功能与 0.3.0 一致；现代工程的 Visual Studio 引用全部改为官方 VSSDK 17 NuGet `PackageReference`（删除写死 `.packages` 的 VSSDK.BuildTools 内部 HintPath），从根本上消除 IDE 设计时命名空间报红，并验证与 NuGet 包还原位置无关；另将 `Microsoft.Bcl.AsyncInterfaces` 对齐到 VSSDK 17.14 闭包 / 宿主要求的 9.0.0，消除 MSB3277；138 项测试与双包校验仍通过。另于 2026-10-07 完成 SSMS 22 首轮实机：部署、加载、菜单、状态栏、T-SQL 上下文识别，以及搜狗拼音自动 / 手动切换均通过；微软拼音（未单独测）与 SSMS 18/19/20 待实测。2026-10-09 另按 PR 评审意见完成：发布两个 SSMS 安装载荷 zip（新增 `tools/Pack-Release.ps1`）、部署脚本 `-WhatIf` 全只读且删除私有注册表前自动备份、Release 测试改回 `Release|x86` 并使用精确路径（去除“最新 exe”兜底）、T-SQL 双引号支持 `SET QUOTED_IDENTIFIER OFF`（自动化测试由 138 增至 143 项）。
- 0.3.0：新增 Transact-SQL 词法与 SSMS 18/19/20/22 双包支持；138 项自动化测试与双包结构校验通过；SSMS 实机验证待补。
- 0.2.1：修复搜狗输入法实际输入态与状态栏不一致，以及状态确认失败后无法自动恢复的问题。
- 0.2.0：加入搜狗拼音适配，并完成当前支持范围内的平台和实机验证。
- 0.1.0：验证基本微软拼音中英文切换、候选词、组词期间暂停、手动覆盖和连续输入保持。
- 0.1.1：将手动覆盖光标改为独立 WPF 装饰层，解决原生光标颜色无法稳定改变的问题。
- 0.1.5：加入正式设置页、状态栏设置、工具菜单暂停/恢复命令和增强版 VSIX 校验。

## 已知限制

- 现代包仅声明 amd64，不承诺 SSMS 22 的 ARM64 原生扩展（x64 / x64 仿真环境可用）。
- 微软拼音旧版兼容模式不属于当前支持范围。
- 后台词法分析器不是完整编译器；C++ 预处理器复杂分支/拼接、C# 插值格式段、T-SQL 宿主专有方言和不完整语法可能存在识别偏差。
- 编译、模拟宿主、COM 检查和离屏绘制测试不能替代所有宿主版本及显示缩放组合的实机验证。SSMS 22 已完成首轮实机（部署、加载、识别，以及搜狗拼音自动 / 手动切换均通过）；SSMS 22 + 微软拼音以及 SSMS 18/19/20 仍需在真实环境补测。
- 搜狗拼音 Shift 兜底在 32 位 / 64 位进程的 Win32 结构体布局沿用既有实现；在 Visual Studio 与 SSMS 22（WPF 编辑器）中均已实测，自动与手动切换正常。微软拼音在 SSMS 22 尚未单独实测，欢迎反馈。
- Windows 的输入态可能受“每个应用窗口使用不同输入法”等系统选项影响；扩展不能保证离开宿主后系统完全不会继承原输入态。

后续版本继续按 `MANUAL-TESTS.md` 执行回归验证。扩展不会修改默认输入法、微软拼音兼容设置、宿主工作负载或日常配置。
