# 神树 · Godot 项目

Godot 4.7.2（GDScript，Compatibility 渲染）。规则层 `core/` 与表现层 `ui/`、`scenes/` 完全分离。

美术方向：**失落文明的古典典藏图册**。
把植物从自然界里的普通物种，转化成某个虚构古代文明的神圣符号——
欧洲古典主义（神庙、石柱、拱门、日轮、星芒）提供文化底蕴，
现代几何主义（圆、弧、三角、拱券）提供视觉简洁感。
色彩是地中海古典文明的哑光旧色；质感靠纸张颗粒与雕版细线，全是第二层信息。

## 运行
```sh
# 在仓库根目录
tools/godot/Godot_v4.7.2-stable_win64.exe --path game            # 直接玩
tools/godot/Godot_v4.7.2-stable_win64.exe -e --path game         # 打开编辑器
```
操作：点选或拖拽手牌到发光格；数字键 1–5 选牌，空格结束回合（脉动中按住空格 2 倍速），按住 Tab 看图解视图，P 修剪，R 重抽，L 记录，H 规则，Esc 取消。
主菜单可切换“减少动效”和音量（存于 `user://settings.cfg`）。所有动效都服从“减少动效”。

## 测试与工具
```sh
G=tools/godot/Godot_v4.7.2-stable_win64_console.exe
$G --headless --path game --import                       # 首次或新增 class_name 后
$G --headless --path game -s tests/run_tests.gd          # 单元测试 + 与网页原型的逐步一致性测试
$G --headless --path game -s tools/ui_smoke.gd -- 3 easy # 通过界面入口自动打 3 局（easy：强制达标以走完三年；anim：保留动画）
$G --headless --path game -s tools/balance_sim.gd -- 300 planner real 1   # 平衡模拟：策略 greedy|planner，模式 real|free
$G --path game -s tools/shot.gd -- season out.png 3 5    # 截图：场景、输出、预先贪心回合数、种子
$G --path game -s tools/tutorial_smoke.gd -- <截图目录>  # 自动走完新手指导，检查每步限制与存档不受影响
$G --path game -s tools/readability_shots.gd -- <截图目录> # 截取图鉴、悬停流动、放置预览、不能放原因、结算单（会备份并还原存档）
node tools/parity/export_fixtures.mjs shentree_prototype.html game/tests/fixtures/parity.json
```

## 结构
- `core/` 纯逻辑：`hex` 坐标、`card_def`/`cards` 牌定义与注册、`tree_model`/`tree_node` 牌桌、`land` 地块、`growth` 生长与修剪、`pulse` 脉动计分（成熟、牌型、季节、土地、器物）、`rules` 全部数值与目标、`run_state` 一局状态（三年×五季、天灾、器物、集市、存档）、`sim/bot` 平衡测试 AI。
- `data/cards`（24 张牌）、`data/relics`（10 件器物）、`data/calamities`（3 种天灾），每项一个 `.tres`。
- `ui/` 绘制组件：
  - `board_view` 牌桌：神庙庭院背景 / 图像化地块 / 几何刻线枝干 / 压印符记卡槽
  - `board3d/board_3d` **3D 牌桌**（继承 BoardView，接口完全相同）：SubViewport 里的透视相机。
    **没有实体台面**——`ground.gdshader` 画一片向四周淡出的虚拟台面，六边形格线若隐若现；特殊地块是
    `land_patch.gdshader` 的柔边贴花（泉眼会荡漾、岩石上立几块矮石）。神树是真的长在桌上：锥形木枝从树心逐格延伸，
    每张牌在格子上立起一枚**纸雕立牌**（`assets/art/standee_<id>.png`，拟态：果是果、花是花）。
    **文字只在悬停时出现**（悬停信息卡、路径算式、放置增减）；脉动的收获数字是反馈，保留。
    落牌时立牌像立体书一样翻立、剪枝时折倒飞走；脉动时金光沿枝条推进、末梢弹起爆金屑、生效的器物跳起发光；
    四季切换光色与台面色调，天灾季有天气（干旱热浪、雷击闪光、虫害飞虫）（`set_mood`）。
    **两种视图**：默认「景观视图」——立牌矮而后仰（`STANDEE_TILT`）、相机更俯（`PITCH` 64°），脚下一圈类别色光圈、
    末梢加赭色外环并在顶上标收获数；悬停某格时挡在它前面的立牌自动变淡（悬停透视）。
    按住 **Tab** 或点「图解」进入「图解视图」（`set_diagram`）：立牌像立体书一样合上，台面铺开带名字和数值的六边形牌片。
    手牌（`hand_view`）在鼠标离开屏幕底部时自动下沉收起，拖牌时也收起，不挡牌桌下沿。
    器物立在网格两侧的石鼓上（抠图贴片 `relic_cut_<id>`）。赛季、地图、集市、图鉴都用它；图鉴关掉 `animate_changes`。
  - `card_view` 手牌：整幅印刷图版 + 石板题名带（牌名 / 分类铭牌 / 数值）
  - `card_art`、`art_view` 插画加载与绘制（图版 cover 裁切、图标 contain）
  - `hand_view` 扇形手牌：抽牌（从牌库沿弧线飞出并翻面）、出牌（飞向目标格）、弃牌（扫进弃牌堆）、悬停抬起
  - `pile_view` 牌库 / 弃牌堆实物、`card_back` 牌背、`seal_button` 印章式「结束回合」按钮
  - `relic_bar` 器物栏：一排器物图版 + 名字
  - `print_style` 版画绘制工具箱（套色错位 / 网点半调 / 木刻排线 / 手绘抖动 / 裁切标记 / 印章）
  - `fx` 动效工具（缓动 / 补间 / 震动 / 落叶粒子 / 数字滚动）
  - `card_tilt.gdshader` 卡牌伪 3D：悬停跟随鼠标透视倾斜 + 高光，静止时轻摆；金色系的牌叠鎏金反光
  - `transition.gdshader` 场景转场：纸色从中心像墨一样晕开（`Game._wipe`）
  - 计分演出（`season.gd`）：每个末梢的收获数字飞入季节铭牌、音高逐级上扬，牌型与倍率像印章砸下，达标时金光迸发；
    脉动中按住空格 2 倍速
  - `print_box` 版画风纸片容器、`palette` 配色字体主题
- 赛季场景是整屏牌桌：网格居中（`BoardView.margins`），四周是悬浮 HUD——左列季节铭牌 / 结算单 / 记录（L），上方器物与提示丝带，右列预计脉动 + 印章按钮，左下牌库、右下弃牌堆，底部扇形手牌；规则说明按 H 或「规则 ?」。
- 美学调研与后续阶段规划见 `docs/美学调研.md`。
- 其余界面（阶段 4）：
  - 主菜单是一个场景：右边 3D 牌桌上一棵神树逐枚翻立长出来（有存档时是你那棵树，否则用 `board3d/showcase` 长一棵展示树），左边题名纸片 + 石刻铭牌按钮。
  - 年度地图：整屏牌桌 + 右页；`ui/season_path` 把三年 × 五季画成石盘串成的年轮路径（走过的刻金打勾，当前季发光，天灾季土红环）。
  - 集市：整屏牌桌 + 右边摊位（牌立在石台上、养分是铜钱铭牌）；买下的牌沿弧线飞进左下角的牌组。
  - 图鉴：牌格是博物馆展签（衬纸 + 金色双线框 + 展签）。
  - 全局主题（`Palette.make_theme`）：按钮是石刻铭牌（墨线边 + 落地投影，悬停换金边并抬起），提示框是小纸片，滚动条是细金线。
- 注意：`ui_smoke` 结束时会清掉存档、`readability_shots` 会用备份覆盖存档，**别在自己玩的时候跑它们**。
- `scenes/` boot → menu → map（年度地图）→ season（奖励、器物、结算为弹窗）→ market（集市）→ map …
- `assets/art/` 插画（43 张：24 张牌面图版 + 10 件器物 + 3 种天灾 + 4 种地块 + 1 张神庙背景 + 1 张标题神树）。
  `assets/fonts/` 标题 ZCOOL XiaoWei、正文思源宋体子集（均为 OFL）。
  `ui/paper.gdshader` 为全屏纸纹与晕影。

## 美术资产的生成
插画由 **MiniMax `image-01`** 生成，提示词统一规定「平面几何 + 古典建筑与植物融合 +
哑光旧色 + 雕版细线 + 纸张颗粒 + 禁边框禁文字」，后处理只做轻微降饱和与裁掉模型爱加的画框。

```sh
# 在仓库根目录
python game/tools/card_art/generate_art.py                     # 生成全部缺失的
python game/tools/card_art/generate_art.py --only tree,oak      # 只生成指定几张
python game/tools/card_art/generate_art.py --force              # 全部重生成
```
- API key 从 `~/.local/share/opencode/auth.json` 的 `minimax-cn` 读取。
- 母题表在 `game/tools/card_art/generate_art.py` 的 `SPEC`（牌面）/ `TILES`（地块）里。
  每条 = id、中文名、画幅（3:4 牌面 / 1:1 图标 / 16:9 背景）、英文母题、构图补充。
- 提示词上限 1500 字符，脚本会自动截断；写母题时注意留余量。
- 原图缓存在 `%TEMP%/opencode/artgen/`。
- 想让某张重画，改 `SPEC` 里的母题描述再 `--only <id> --force`。
- 拟态立牌：`python game/tools/card_art/generate_art.py --standees`（25 张，白底生成后用 `cutout_soft()` 区域生长抠图；
  模型不肯给纯绿幕，会给带渐变的灰绿底）。`--standees` / `--extra` 不会碰原有牌面和地块；
  **但单独的 `--force` 会重画全部牌面**，只想重画几张请配 `--only`。
- 3D 牌桌资产：`python game/tools/card_art/generate_art.py --extra`（台面 `table_top`、牌背 `card_back`、高清神庙 `board_bg`、
  10 件器物主体 `relic_cut_<id>`）。器物在纯奶油色底上生成，再由 `cutout()` 从四边泛洪抠成透明 PNG；
  主体颜色别用和底色一样的奶油色（种子袋第一次就被整个抠掉了）。

> 生图模型：MiniMax 的图像模型叫 **`image-01` / `image-01-live`**，
> 不是 `minimax-h3`（那个不存在，且所有模型的输出模态都只有 `text`）。

字体子集（只保留游戏里用到的字，约 330 KB）：
```sh
python game/tools/fonts/build_font.py                     # 下载思源宋体 + 子集化
python game/tools/fonts/build_font.py --no-download       # 只用本地缓存重新子集化
python game/tools/fonts/check_glyphs.py                   # 体检字体：找「实心方块」式的坏字形
python game/tools/fonts/specimen.py out.png               # 导出字样表，肉眼检查
```
> 注意：标题字体 ZCOOL XiaoWei 把「回」画成了一块实心方块。
> `Palette.title_for(text)` 会在文本含坏字时自动改用正文字体；
> 换字体后请重新跑一次 `check_glyphs.py`，并把坏字加进 `Palette.BAD_TITLE_GLYPHS`。

## 平衡现状（2026-11）
第二、三年目标由 `balance_sim` 校准：规划者策略约 49% 通关三年，贪心策略约 0.2%（只有 4% 能过第一年天灾）。
分数呈指数增长（嫁接乘积 × 闭环 × 成熟），强树与弱树差距可达数百倍——这是有意保留的设计。
- `autoload/game.gd` 持有 RunState、场景切换（含纸张擦除转场）、自动存档 `user://save.json`。
