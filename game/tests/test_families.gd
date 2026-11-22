extends "res://tests/base_test.gd"
## 阶段 C：流派修饰器、共鸣、燃烧副作用。


func _t(parents: Array, facing: int) -> Growth.Target:
	var t := Growth.Target.new()
	t.parents.assign(parents)
	t.facing = facing
	return t


## 关掉成熟、牌型、共鸣的上下文（春季，树心 1）。
func _ctx(resonance := false) -> Pulse.Context:
	var c := Pulse.Context.for_season(1)
	c.maturity = false
	c.patterns = false
	c.resonance = resonance
	return c


func _bare_run(run_seed: int = 1) -> RunState:
	var s := RunState.create(run_seed)
	s.tree.land.clear()
	s.hand.clear()
	s.hand_fresh.clear()
	return s


## 树心两侧相邻的两张牌：(1,0) 与 (1,-1) 互相挨着。
func _pair(tree: TreeModel, a: StringName, b: StringName) -> void:
	Growth.place(tree, a, Hex.DIRS[0], _t([Vector2i.ZERO], 0))
	Growth.place(tree, b, Hex.DIRS[1], _t([Vector2i.ZERO], 1))


# ---------- 齿轮 ----------

func test_cog_adjacency() -> void:
	var cog := Cards.get_def(&"gear_cog")
	var tree := TreeModel.create(5)
	_pair(tree, &"gear_cog", &"gear_cog")
	var one := 1 + int(cog.value) + cog.adj_family_add
	check_eq(Pulse.resolve(tree, _ctx()).total, 2 * one)
	# 共鸣第 1 层（2 张）：联动加成 × GEAR_RES[1]
	var res := Pulse.resolve(tree, _ctx(true))
	check_eq(res.resonance.get(&"gear", 0), 1)
	check_eq(res.total, 2 * (1 + int(cog.value) + int(round(cog.adj_family_add * Pulse.GEAR_RES[1]))))

func test_cog_ignores_other_families() -> void:
	var tree := TreeModel.create(5)
	_pair(tree, &"gear_cog", &"stem")
	check_eq(Pulse.resolve(tree, _ctx()).total, (1 + 2) + (1 + 3))


func test_link_multiplies_by_adjacent() -> void:
	var tree := TreeModel.create(5)
	Growth.place(tree, &"stem", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	Growth.place(tree, &"gear_link", Hex.DIRS[1] * 2, _t([Hex.DIRS[1]], 1))
	# 联动齿轮 (2,-2) 挨着一张齿轮牌：铆钉 (2,-1)，从茎 (1,-1) 朝方向 0 长出
	var rv := Vector2i(2, -1)
	Growth.place(tree, &"gear_rivet", rv, _t([Hex.DIRS[1]], 0))
	check(Hex.distance(rv, Hex.DIRS[1] * 2) == 1, "rivet next to link")
	var res := Pulse.resolve(tree, _ctx())
	check_eq(res.out[Hex.DIRS[1] * 2], int(floor(4 * (1.0 + Cards.get_def(&"gear_link").adj_family_mul))))

func test_hub_grafts_gear_cards() -> void:
	var cog := Cards.get_def(&"gear_cog")
	var hub := Cards.get_def(&"gear_hub")
	var tree := TreeModel.create(5)
	_pair(tree, &"gear_cog", &"gear_cog")
	var tg := Growth.targets_for(tree, &"gear_hub", _ctx())
	var cell := Vector2i(2, -1)
	check(tg.has(cell), "hub fits next to two gears")
	check(not Growth.targets_for(tree, &"vine", _ctx()).is_empty(), "vine still uses tips")
	Growth.place(tree, &"gear_hub", cell, tg[cell])
	# 枢纽本身也是齿轮牌：每张齿轮挨着另一张齿轮和枢纽；枢纽 = 两者之和 × value × 父牌数
	var each := 1 + int(cog.value) + cog.adj_family_add * 2
	check_eq(Pulse.resolve(tree, _ctx()).total, int(floor(each * 2 * hub.value)) * 2)
	var tree2 := TreeModel.create(5)
	_pair(tree2, &"stem", &"stem")
	check(not Growth.targets_for(tree2, &"gear_hub", _ctx()).has(cell), "hub needs gear cards")
	check(Growth.why_not(tree2, &"gear_hub", cell, _ctx()).contains("齿轮"), "explains the family")

func test_rivet_is_tough() -> void:
	var s := _bare_run()
	Growth.place(s.tree, &"gear_rivet", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	Growth.place(s.tree, &"stem", Hex.DIRS[3], _t([Vector2i.ZERO], 3))
	check_eq(s.wither(3), [Hex.DIRS[3]] as Array[Vector2i])


func test_shaft_copies_best_neighbor() -> void:
	var tree := TreeModel.create(5)
	# 茎 4 在 (1,-1)，传动轴接在树心另一侧但挨着茎
	Growth.place(tree, &"stem", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	Growth.place(tree, &"gear_shaft", Hex.DIRS[0], _t([Vector2i.ZERO], 0))
	check_eq(Pulse.resolve(tree, _ctx()).out[Hex.DIRS[0]], 4)


func test_escapement_multiplies_adjacent_tips() -> void:
	var tree := TreeModel.create(5)
	_pair(tree, &"stem", &"gear_escape")
	var m := 1.0 + Cards.get_def(&"gear_escape").aura_tip_mul
	check_eq(Pulse.resolve(tree, _ctx()).contrib[Hex.DIRS[0]], int(floor(4 * m)))

func test_core_counts_family() -> void:
	var cog := Cards.get_def(&"gear_cog")
	var tree := TreeModel.create(5)
	Growth.place(tree, &"gear_cog", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	Growth.place(tree, &"gear_core", Hex.DIRS[1] * 2, _t([Hex.DIRS[1]], 1))
	var res := Pulse.resolve(tree, _ctx())
	var c: int = res.out[Hex.DIRS[1]]
	check_eq(c, 1 + int(cog.value) + cog.adj_family_add)
	check_eq(res.total, int(floor(c * (1.0 + Cards.get_def(&"gear_core").family_count_mul * 2))))

# ---------- 熔炉 ----------

func test_burning_feeds_heat() -> void:
	var s := _bare_run()
	var coal := Cards.get_def(&"forge_coal")
	Growth.place(s.tree, &"forge_coal", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	Growth.place(s.tree, &"stem", Hex.DIRS[3], _t([Vector2i.ZERO], 3))
	s.prune(Hex.DIRS[1])
	check_eq(s.heat, 1 + coal.heat_on_burn)
	check_eq(s.burned_total, 1)
	s.wither(1)
	check_eq(s.heat, 1 + coal.heat_on_burn + 1, "withering is fuel too")
	check_eq(s.burned_total, 2)

func test_furnace_scales_with_heat() -> void:
	var s := _bare_run()
	Growth.place(s.tree, &"stem", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	Growth.place(s.tree, &"forge_furnace", Hex.DIRS[1] * 2, _t([Hex.DIRS[1]], 1))
	s.heat = 10
	check_eq(s.preview().total, int(floor(4 * (1.0 + Cards.get_def(&"forge_furnace").heat_mul * 10))))
	check(s.tree.at(Hex.DIRS[1] * 2).is_tough(), "furnace is fireproof")

func test_ember_doubles_next_pulse() -> void:
	var s := _bare_run()
	Growth.place(s.tree, &"forge_ember", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	Growth.place(s.tree, &"stem", Hex.DIRS[3], _t([Vector2i.ZERO], 3))
	s.prune(Hex.DIRS[1])
	check_eq(s.preview().total, 4 * 2)
	s.end_turn()
	check_eq(s.next_total_mult, 1.0, "consumed by the pulse")


func test_altar_burns_weakest_tip() -> void:
	var s := _bare_run()
	Growth.place(s.tree, &"forge_altar", Hex.DIRS[0], _t([Vector2i.ZERO], 0))
	Growth.place(s.tree, &"stem", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	Growth.place(s.tree, &"gear_rivet", Hex.DIRS[5], _t([Vector2i.ZERO], 5))
	s.end_turn()
	check(not s.tree.has(Hex.DIRS[1]), "stem burned")
	check(s.tree.has(Hex.DIRS[5]), "tough rivet spared")
	check(s.discard.has(&"stem"), "to discard")
	check_eq(s.burned_total, 1)


func test_bellows_ash_anvil() -> void:
	var s := _bare_run()
	Growth.place(s.tree, &"forge_bellows", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	s.end_turn()
	check_eq(s.heat, Cards.get_def(&"forge_bellows").pulse_heat)
	var tree := TreeModel.create(5)
	Growth.place(tree, &"forge_ash", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	var c := _ctx()
	c.burned_total = 7
	check_eq(Pulse.resolve(tree, c).total, 1 + int(Cards.get_def(&"forge_ash").burned_add * 7))
	var a := Growth.place(tree, &"forge_anvil", Hex.DIRS[3], _t([Vector2i.ZERO], 3))
	var cm := _ctx()
	cm.maturity = true
	a.age = 2
	check_eq(Pulse.resolve(tree, cm).out[Hex.DIRS[3]], int(floor(1 * 1.5)))
	a.age = 99
	check_eq(Cards.get_def(&"forge_anvil").current_value(99), 1.0)

func test_forge_resonance_adds_heat_per_burn() -> void:
	var s := _bare_run()
	Growth.place(s.tree, &"forge_coal", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	Growth.place(s.tree, &"forge_kindle", Hex.DIRS[3], _t([Vector2i.ZERO], 3))
	# 2 张熔炉牌 → 共鸣第 1 层：每燃烧一张火候再 +1
	s.prune(Hex.DIRS[3])
	check_eq(s.heat, 1 + Cards.get_def(&"forge_kindle").heat_on_burn + 1)

# ---------- 数据完整性 ----------

func test_new_cards_have_family_and_keywords() -> void:
	for id in Cards.all_ids():
		var d := Cards.get_def(id)
		if d.family.is_empty():
			continue
		check(not d.keywords.is_empty(), "%s has keywords" % id)
		for f in d.family:
			check(CardDef.FAMILY_NAMES.has(f), "%s family %s known" % [id, f])
		for k in d.keywords:
			check(CardDef.KEYWORD_NAMES.has(k), "%s keyword %s known" % [id, k])
		check(Palette.card_color(d.color_key) != Palette.INK, "%s has a color" % id)


func test_save_roundtrip_heat() -> void:
	var s := _bare_run()
	s.heat = 12
	s.burned_total = 3
	s.next_total_mult = 2.0
	var s2 := RunState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	check_eq(s2.heat, 12)
	check_eq(s2.burned_total, 3)
	check_eq(s2.next_total_mult, 2.0)


# ---------- 星辰 ----------

func test_star_timing() -> void:
	var sand := Cards.get_def(&"star_sand")
	var tree := TreeModel.create(5)
	Growth.place(tree, &"star_sand", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	Growth.place(tree, &"star_moon", Hex.DIRS[1] * 2, _t([Hex.DIRS[1]], 1))
	var c := _ctx()
	c.turn = 3
	c.turns_total = 5
	check_eq(Pulse.resolve(tree, c).total, (1 + int(sand.turn_add * 3)) * 3)
	var t2 := TreeModel.create(5)
	Growth.place(t2, &"star_meteor", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	var met := Cards.get_def(&"star_meteor")
	c.turn = 5
	check_eq(Pulse.resolve(t2, c).total, int((1 + met.value) * met.last_turn_mult))
	c.turn = 4
	check_eq(Pulse.resolve(t2, c).total, int(1 + met.value))

func test_star_chart_and_line() -> void:
	var add := int(Cards.get_def(&"star_sand").turn_add)
	var tree := TreeModel.create(5)
	var prev := Vector2i.ZERO
	for i in 3:
		var k := prev + Hex.DIRS[1]
		Growth.place(tree, &"star_sand", k, _t([prev], 1))
		prev = k
	var c := _ctx()
	c.patterns = true
	c.turn = 1
	var res := Pulse.resolve(tree, c)
	check(res.patterns.any(func(p): return p.id == &"line"), "连星 formed")
	var v := 1
	for i in 3:
		v = (v + add) * 2
	check_eq(res.total, v)
	Growth.place(tree, &"star_chart", Hex.DIRS[3], _t([Vector2i.ZERO], 3))
	var res2 := Pulse.resolve(tree, c)
	check(is_equal_approx(res2.total_mult, 1.0 + Cards.get_def(&"star_chart").star_total_mult * 4), "chart multiplier")

# ---------- 商会 ----------

func test_coin_sap_effects() -> void:
	var s := _bare_run()
	Growth.place(s.tree, &"coin_bank", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	Growth.place(s.tree, &"coin_copper", Hex.DIRS[1] * 2, _t([Hex.DIRS[1]], 1))
	s.sap = 10
	var bank := Cards.get_def(&"coin_bank")
	check_eq(s.preview().total, 1 + int(bank.sap_add * 10) + int(Cards.get_def(&"coin_copper").value))
	s.end_turn()
	check(s.sap >= 11, "copper produced sap")

func test_contract_needs_sap() -> void:
	var s := _bare_run()
	var con := Cards.get_def(&"coin_contract")
	Growth.place(s.tree, &"coin_contract", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	s.sap = con.pulse_cost - 1
	check_eq(s.preview().total, 0)
	s.sap = 5
	check_eq(s.preview().total, int(con.value))
	s.end_turn()
	check_eq(s.sap, 5 - con.pulse_cost, "paid")

func test_caravan_costs_to_play() -> void:
	var s := _bare_run()
	s.hand.append(&"coin_caravan")
	s.hand_fresh.append(false)
	s.sap = 2
	check(s.targets_for_hand(0).is_empty(), "too poor")
	s.sap = 5
	var tg := s.targets_for_hand(0)
	check(s.place(0, tg.keys()[0]), "placed")
	check_eq(s.sap, 2)


func test_ledger_and_horn() -> void:
	var tree := TreeModel.create(5)
	Growth.place(tree, &"coin_ledger", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	Growth.place(tree, &"coin_horn", Hex.DIRS[1] * 2, _t([Hex.DIRS[1]], 1))
	var c := _ctx()
	c.spent = 20
	c.relic_count = 2
	check_eq(Pulse.resolve(tree, c).total, (1 + int(Cards.get_def(&"coin_ledger").spent_add * 20)) * 3)

# ---------- 镜像 ----------

func test_mirror_pairs_and_echo() -> void:
	var tree := TreeModel.create(5)
	Growth.place(tree, &"stem", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	Growth.place(tree, &"mirror_echo", Hex.DIRS[4], _t([Vector2i.ZERO], 4))
	var res := Pulse.resolve(tree, _ctx())
	check_eq(res.contrib[Hex.DIRS[4]], 1 + int(Cards.get_def(&"mirror_echo").value))
	var fr := Cards.get_def(&"mirror_frame")
	var t2 := TreeModel.create(5)
	Growth.place(t2, &"mirror_frame", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	Growth.place(t2, &"mirror_frame", Hex.DIRS[4], _t([Vector2i.ZERO], 4))
	var r2 := Pulse.resolve(t2, _ctx(true))
	check_eq(r2.pairs, 1)
	check_eq(r2.raw_total, 2 * int(floor((1 + fr.value) * fr.mirror_same_mult)))
	check_eq(r2.resonance.get(&"mirror", 0), 1)
	check(is_equal_approx(r2.total_mult, 1.0 + Pulse.MIRROR_RES[1]), "mirror resonance")

func test_phantom_is_wild() -> void:
	var tree := TreeModel.create(5)
	Growth.place(tree, &"gear_cog", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	Growth.place(tree, &"mirror_phantom", Hex.DIRS[3], _t([Vector2i.ZERO], 3))
	var counts := Pulse.family_counts(tree)
	check_eq(counts.get(&"gear", 0), 2, "phantom tops gear up to 2")
	check_eq(counts.get(&"mirror", 0), 1)


# ---------- 封印 ----------

func test_seal_stores_and_releases() -> void:
	var s := _bare_run()
	Growth.place(s.tree, &"stem", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	Growth.place(s.tree, &"seal_box", Hex.DIRS[0], _t([Vector2i.ZERO], 0))
	var res := s.preview()
	check_eq(res.total, 1, "stem harvest sealed; only the box itself (1) scores")
	check_eq(res.stored_total, 4)
	s.end_turn()
	s.end_turn()
	var box := s.tree.at(Hex.DIRS[0])
	check_eq(box.stored, 8)
	check_eq(box.sealed, 2)
	var rate := Cards.get_def(&"seal_box").seal_rate
	check_eq(s.pending_release(), int(floor(8 * (1.0 + rate * 2))))
	var before := s.score
	var got := s.release_seals()
	check_eq(s.score, before + got)
	check_eq(box.stored, 0)

func test_seal_released_at_season_end_counts_for_target() -> void:
	var s := _bare_run()
	Growth.place(s.tree, &"seal_wax", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	for i in Rules.turns(1):
		if s.phase == RunState.Phase.DISCARD:
			while s.phase == RunState.Phase.DISCARD:
				s.discard_card(0)
		s.end_turn()
	# 5 次封存，每次 4，释放 20×(1+2.5) = 70 ≥ 50
	check_eq(s.phase, RunState.Phase.REWARD)


func test_ward_protects_neighbors() -> void:
	var s := _bare_run()
	Growth.place(s.tree, &"seal_ward", Hex.DIRS[0], _t([Vector2i.ZERO], 0))
	Growth.place(s.tree, &"stem", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	Growth.place(s.tree, &"stem", Hex.DIRS[3], _t([Vector2i.ZERO], 3))
	var gone := s.wither(3)
	check(not gone.has(Hex.DIRS[1]), "stem next to ward spared")
	check(gone.has(Hex.DIRS[3]), "far stem withers")


# ---------- 桥牌 ----------

func test_bridges_count_for_both_families() -> void:
	var tree := TreeModel.create(5)
	Growth.place(tree, &"bridge_bell", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	var counts := Pulse.family_counts(tree)
	check_eq(counts.get(&"gear", 0), 1)
	check_eq(counts.get(&"star", 0), 1)


func test_mint_pays_on_burn() -> void:
	var s := _bare_run()
	Growth.place(s.tree, &"bridge_mint", Hex.DIRS[0], _t([Vector2i.ZERO], 0))
	Growth.place(s.tree, &"stem", Hex.DIRS[3], _t([Vector2i.ZERO], 3))
	s.prune(Hex.DIRS[3])
	check_eq(s.sap, 1 + 1, "prune value 1 + mint 1")


# ---------- 器物 / 年轮 / 土地 / 天灾 ----------

func test_badge_lowers_resonance() -> void:
	var s := _bare_run()
	Growth.place(s.tree, &"gear_cog", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	check(not s.preview().resonance.has(&"gear"), "one gear: no resonance")
	s.relics.append(&"badge_gear")
	check_eq(s.preview().resonance.get(&"gear", 0), 1)
	check_eq(s.res_tier(&"gear"), 1)


func test_hourglass_and_almanac() -> void:
	var s := _bare_run()
	var t0 := s.turns_this_season()
	s.relics.append(&"hourglass")
	check_eq(s.turns_this_season(), t0 + 1)
	s.season = Rules.CALAMITY_STAGE
	check_eq(s.turns_this_season(), Rules.CALAMITY_TURNS, "not in calamity")
	var tg := s.target()
	s.relics.append(&"almanac")
	check_eq(s.target(), int(tg * 0.8))


func test_scales_discount_services() -> void:
	var s := _bare_run()
	check_eq(s.service_price(Rules.REMOVE_CARD_PRICE), Rules.REMOVE_CARD_PRICE)
	s.relics.append(&"scales")
	check_eq(s.service_price(Rules.REMOVE_CARD_PRICE), Rules.REMOVE_CARD_PRICE - 1)
	check_eq(s.service_price(1), 1)


func test_new_marks() -> void:
	var s := _bare_run()
	var a := Growth.place(s.tree, &"stem", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	a.marks.append(&"echo")
	check_eq(s.preview().total, 8)
	a.marks.append(&"gilded")
	a.marks.append(&"fireproof")
	check_eq(s.prune(a.key), 2)
	check_eq(s.heat, 1 + 3)


func test_new_lands() -> void:
	var tree := TreeModel.create(5)
	tree.land[Hex.DIRS[1]] = Land.Type.ORE
	tree.land[Hex.DIRS[3]] = Land.Type.GOLDSAND
	Growth.place(tree, &"gear_rivet", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	Growth.place(tree, &"stem", Hex.DIRS[3], _t([Vector2i.ZERO], 3))
	var res := Pulse.resolve(tree, _ctx())
	check_eq(res.out[Hex.DIRS[1]], 1 + 1 + 4)
	check_eq(res.sap_gain, 1)


func test_new_calamities() -> void:
	var s := _bare_run()
	s.season = Rules.CALAMITY_STAGE
	s.calamity = &"drought"
	Growth.place(s.tree, &"star_sand", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	s.calamity = &"eclipse"
	var dim: int = s.preview().contrib[Hex.DIRS[1]]
	var c := s.ctx()
	c.eclipse = false
	var full: int = Pulse.resolve(s.tree, c).contrib[Hex.DIRS[1]]
	check(dim < full and dim >= int(full * Pulse.ECLIPSE_MULT) - 1, "eclipse dims star cards (%d vs %d)" % [dim, full])
	s.calamity = &"wildfire"
	s.end_turn()
	check_eq(s.tree.size(), 1, "wildfire burned the only tip")
	check_eq(s.burned_total, 1)


func test_removed_seal_spills_store() -> void:
	var s := _bare_run()
	Growth.place(s.tree, &"seal_wax", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	s.end_turn()
	var held := s.tree.at(Hex.DIRS[1]).stored
	check(held > 0, "stored something")
	var before := s.score
	s.prune(Hex.DIRS[1])
	check_eq(s.score, before + held, "released at x1 when pruned")


func test_descriptions_have_no_placeholders() -> void:
	for id in Cards.all_ids():
		var d := Cards.get_def(id)
		check(not d.desc.contains("{") and not d.desc.contains("}"), "%s desc filled" % id)
	for f in [&"gear", &"forge", &"star", &"coin", &"mirror", &"seal"]:
		var t := Pulse.resonance_desc(f)
		check(t != "" and not t.contains("%s"), "%s resonance text: %s" % [f, t])
