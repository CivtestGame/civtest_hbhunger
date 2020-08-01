-- Keep these for backwards compatibility
function hbhunger.save_hunger(player)
	hbhunger.set_hunger_raw(player)
end
function hbhunger.load_hunger(player)
	hbhunger.get_hunger_raw(player)
end

-- wrapper for minetest.item_eat (this way we make sure other mods can't break this one)
local org_eat = core.do_item_eat
core.do_item_eat = function(hp_change, replace_with_item, itemstack, user, pointed_thing)
	local old_itemstack = itemstack
	itemstack = hbhunger.eat(hp_change, replace_with_item, itemstack, user, pointed_thing)
	for _, callback in pairs(core.registered_on_item_eats) do
		local result = callback(hp_change, replace_with_item, itemstack, user, pointed_thing, old_itemstack)
		if result then
			return result
		end
	end
	return itemstack
end

-- food functions
local food = hbhunger.food

function hbhunger.register_food(name, hunger_change, replace_with_item, poison, heal, sound, saturation_limit)
	food[name] = {}
	food[name].saturation = hunger_change	-- hunger points added
	food[name].replace = replace_with_item	-- what item is given back after eating
	food[name].poison = poison				-- time its poisoning
	food[name].healing = heal				-- amount of HP
	food[name].sound = sound				-- special sound that is played when eating
	food[name].saturation_limit = saturation_limit
end

-- Register all stated foods as a food=1
minetest.register_on_mods_loaded(function()
      for k,v in pairs(food) do
         local def = minetest.registered_items[k]
         if def then
            local groups = (def.groups and table.copy(def.groups)) or {}
            groups.food = groups.food or 1
            minetest.override_item(k, { groups = groups })
         end
      end
end)

function hbhunger.eat(hp_change, replace_with_item, itemstack, user, pointed_thing)
	local item = itemstack:get_name()
	local def = food[item]
	if not def then
		def = {}
		if type(hp_change) ~= "number" then
			hp_change = 1
			core.log("error", "Wrong on_use() definition for item '" .. item .. "'")
		end
		def.saturation = hp_change * 1.3
		def.replace = replace_with_item
	end
	local func = hbhunger.item_eat(def.saturation, def.replace, def.poison, def.healing, def.sound, def.saturation_limit)
	return func(itemstack, user, pointed_thing)
end

-- Poison player
local function poison_player(tick, time, time_left, player)
	-- First check if player is still there
	if not player:is_player() then
		return
	end
	time_left = time_left + tick
	if time_left < time then
		minetest.after(tick, poison_player, tick, time, time_left, player)
	else
		hbhunger.poisonings[player:get_player_name()] = hbhunger.poisonings[player:get_player_name()] - 1
		if hbhunger.poisonings[player:get_player_name()] <= 0 then
			-- Reset HUD bar color
			hb.change_hudbar(player, "health", nil, nil, "hudbars_icon_health.png", nil, "hudbars_bar_health.png")
		end
	end
	if player:get_hp()-1 > 0 then
		player:set_hp(player:get_hp()-1)
	end

end

local function is_plural(str)
   local len = str:len()
   return str:sub(len, len) == "s"
end

local function to_plural(str)
   if not is_plural(str) then
         local len = str:len()
         local last = str:sub(len, len)
         if last == "y" then
            return str:sub(0, len - 1) .. "ies"
         else
            return str .. "s"
         end
   end
   return str
end

function hbhunger.item_eat(hunger_change, replace_with_item, poison, heal, sound, sat_limit)
	return function(itemstack, user, pointed_thing)
		if itemstack:peek_item() ~= nil and user ~= nil then
			local name = user:get_player_name()
			local h = tonumber(hbhunger.hunger[name])
			local hp = user:get_hp()
			if h == nil or hp == nil then
				return
			end

			if h >= 30 then
				minetest.chat_send_player(
					name, "Player food satiation limit reached!"
				)
				return itemstack
			end
			-- Saturation
			if h < 30 and hunger_change then
				if sat_limit then
					if h < sat_limit and (h + hunger_change) > sat_limit then
						h = sat_limit
					elseif h >= sat_limit then
						local description = to_plural(itemstack:get_definition().description)
						minetest.chat_send_player(
							name, "You can't eat any more " .. description
								.. ". They have a satiation limit of " .. tostring(sat_limit) .. "."
						)
						return itemstack
					else
						h = h + hunger_change
					end
				else
					h = h + hunger_change
				end

				if h > 30 then h = 30 end
				hbhunger.hunger[name] = h
				hbhunger.set_hunger_raw(user)
			end
			-- Healing
			if hp < 20 and heal then
				hp = hp + heal
				if hp > 20 then hp = 20 end
				user:set_hp(hp)
			end
			-- Poison
			if poison then
				-- Set poison bar
				hb.change_hudbar(user, "health", nil, nil, "hbhunger_icon_health_poison.png", nil, "hbhunger_bar_health_poison.png")
				hbhunger.poisonings[name] = hbhunger.poisonings[name] + 1
				poison_player(1, poison, 0, user)
			end

			minetest.sound_play(
				{name = sound or "hbhunger_eat_generic",
				gain = 1},
				{object=user,
				max_hear_distance = 16,
				pitch = 1 + math.random(-10, 10)*0.005,}
			)

			itemstack:take_item()
			if itemstack:get_count() == 0 then
				itemstack:add_item(replace_with_item)
			else
                                local leftover = player_api.give_item(user, replace_with_item)
				if leftover and not leftover:is_empty() then
					minetest.add_item(user:getpos(), replace_with_item)
				end
			end
		end
		return itemstack
	end
end

if minetest.get_modpath("default") ~= nil then
	hbhunger.register_food("default:apple", 2)
end
if minetest.get_modpath("flowers") ~= nil then
	hbhunger.register_food("flowers:mushroom_brown", 1)
	hbhunger.register_food("flowers:mushroom_red", 1, "", 3)
end
if minetest.get_modpath("farming") ~= nil then
	hbhunger.register_food("farming:bread", 4)
end

if minetest.get_modpath("mobs") ~= nil then
	if mobs.mod ~= nil and mobs.mod == "redo" then
		hbhunger.register_food("mobs:cheese", 4)
		hbhunger.register_food("mobs:meat", 8)
		hbhunger.register_food("mobs:meat_raw", 4)
		hbhunger.register_food("mobs:rat_cooked", 4)
		hbhunger.register_food("mobs:honey", 2)
		hbhunger.register_food("mobs:pork_raw", 3, "", 3)
		hbhunger.register_food("mobs:pork_cooked", 8)
		hbhunger.register_food("mobs:chicken_cooked", 6)
		hbhunger.register_food("mobs:chicken_raw", 2, "", 3)
		hbhunger.register_food("mobs:chicken_egg_fried", 2)
		if minetest.get_modpath("bucket") then
			hbhunger.register_food("mobs:bucket_milk", 3, "bucket:bucket_empty")
		end
	else
		hbhunger.register_food("mobs:meat", 6)
		hbhunger.register_food("mobs:meat_raw", 3)
		hbhunger.register_food("mobs:rat_cooked", 5)
	end
end

if minetest.get_modpath("moretrees") ~= nil then
	hbhunger.register_food("moretrees:coconut_milk", 1)
	hbhunger.register_food("moretrees:raw_coconut", 2)
	hbhunger.register_food("moretrees:acorn_muffin", 3)
	hbhunger.register_food("moretrees:spruce_nuts", 1)
	hbhunger.register_food("moretrees:pine_nuts", 1)
	hbhunger.register_food("moretrees:fir_nuts", 1)
end

if minetest.get_modpath("dwarves") ~= nil then
	hbhunger.register_food("dwarves:beer", 2)
	hbhunger.register_food("dwarves:apple_cider", 1)
	hbhunger.register_food("dwarves:midus", 2)
	hbhunger.register_food("dwarves:tequila", 2)
	hbhunger.register_food("dwarves:tequila_with_lime", 2)
	hbhunger.register_food("dwarves:sake", 2)
end

if minetest.get_modpath("animalmaterials") ~= nil then
	hbhunger.register_food("animalmaterials:milk", 2)
	hbhunger.register_food("animalmaterials:meat_raw", 3)
	hbhunger.register_food("animalmaterials:meat_pork", 3)
	hbhunger.register_food("animalmaterials:meat_beef", 3)
	hbhunger.register_food("animalmaterials:meat_chicken", 3)
	hbhunger.register_food("animalmaterials:meat_lamb", 3)
	hbhunger.register_food("animalmaterials:meat_venison", 3)
	hbhunger.register_food("animalmaterials:meat_undead", 3, "", 3)
	hbhunger.register_food("animalmaterials:meat_toxic", 3, "", 5)
	hbhunger.register_food("animalmaterials:meat_ostrich", 3)
	hbhunger.register_food("animalmaterials:fish_bluewhite", 2)
	hbhunger.register_food("animalmaterials:fish_clownfish", 2)
end

if minetest.get_modpath("fishing") ~= nil then
	hbhunger.register_food("fishing:fish_raw", 2)
	hbhunger.register_food("fishing:fish_cooked", 5)
	hbhunger.register_food("fishing:sushi", 6)
	hbhunger.register_food("fishing:shark", 4)
	hbhunger.register_food("fishing:shark_cooked", 8)
	hbhunger.register_food("fishing:pike", 4)
	hbhunger.register_food("fishing:pike_cooked", 8)
end

if minetest.get_modpath("glooptest") ~= nil then
	hbhunger.register_food("glooptest:kalite_lump", 1)
end

if minetest.get_modpath("bushes") ~= nil then
	hbhunger.register_food("bushes:sugar", 1)
	hbhunger.register_food("bushes:strawberry", 2)
	hbhunger.register_food("bushes:berry_pie_raw", 3)
	hbhunger.register_food("bushes:berry_pie_cooked", 4)
	hbhunger.register_food("bushes:basket_pies", 15)
end

if minetest.get_modpath("bushes_classic") then
	-- bushes_classic mod, as found in the plantlife modpack
	local berries = {
	    "strawberry",
		"blackberry",
		"blueberry",
		"raspberry",
		"gooseberry",
		"mixed_berry"}
	for _, berry in ipairs(berries) do
		if berry ~= "mixed_berry" then
			hbhunger.register_food("bushes:"..berry, 1)
		end
		hbhunger.register_food("bushes:"..berry.."_pie_raw", 2)
		hbhunger.register_food("bushes:"..berry.."_pie_cooked", 5)
		hbhunger.register_food("bushes:basket_"..berry, 15)
	end
end

if minetest.get_modpath("mushroom") ~= nil then
	hbhunger.register_food("mushroom:brown", 1)
	hbhunger.register_food("mushroom:red", 1, "", 3)
	-- mushroom potions: red = strong poison, brown = light restorative
	if minetest.get_modpath("vessels") then
		hbhunger.register_food("mushroom:brown_essence", 1, "vessels:glass_bottle", nil, 4)
		hbhunger.register_food("mushroom:poison", 1, "vessels:glass_bottle", 10)
	end
end

if minetest.get_modpath("docfarming") ~= nil then
	hbhunger.register_food("docfarming:carrot", 3)
	hbhunger.register_food("docfarming:cucumber", 2)
	hbhunger.register_food("docfarming:corn", 3)
	hbhunger.register_food("docfarming:potato", 4)
	hbhunger.register_food("docfarming:bakedpotato", 5)
	hbhunger.register_food("docfarming:raspberry", 3)
end

if minetest.get_modpath("farming_plus") ~= nil then
	hbhunger.register_food("farming_plus:carrot_item", 3)
	hbhunger.register_food("farming_plus:banana", 2)
	hbhunger.register_food("farming_plus:orange_item", 2)
	hbhunger.register_food("farming:pumpkin_bread", 4)
	hbhunger.register_food("farming_plus:strawberry_item", 2)
	hbhunger.register_food("farming_plus:tomato_item", 2)
	hbhunger.register_food("farming_plus:potato_item", 4)
	hbhunger.register_food("farming_plus:rhubarb_item", 2)
end

if minetest.get_modpath("mtfoods") ~= nil then
	hbhunger.register_food("mtfoods:dandelion_milk", 1)
	hbhunger.register_food("mtfoods:sugar", 1)
	hbhunger.register_food("mtfoods:short_bread", 4)
	hbhunger.register_food("mtfoods:cream", 1)
	hbhunger.register_food("mtfoods:chocolate", 2)
	hbhunger.register_food("mtfoods:cupcake", 2)
	hbhunger.register_food("mtfoods:strawberry_shortcake", 2)
	hbhunger.register_food("mtfoods:cake", 3)
	hbhunger.register_food("mtfoods:chocolate_cake", 3)
	hbhunger.register_food("mtfoods:carrot_cake", 3)
	hbhunger.register_food("mtfoods:pie_crust", 3)
	hbhunger.register_food("mtfoods:apple_pie", 3)
	hbhunger.register_food("mtfoods:rhubarb_pie", 2)
	hbhunger.register_food("mtfoods:banana_pie", 3)
	hbhunger.register_food("mtfoods:pumpkin_pie", 3)
	hbhunger.register_food("mtfoods:cookies", 2)
	hbhunger.register_food("mtfoods:mlt_burger", 5)
	hbhunger.register_food("mtfoods:potato_slices", 2)
	hbhunger.register_food("mtfoods:potato_chips", 3)
	--mtfoods:medicine
	hbhunger.register_food("mtfoods:casserole", 3)
	hbhunger.register_food("mtfoods:glass_flute", 2)
	hbhunger.register_food("mtfoods:orange_juice", 2)
	hbhunger.register_food("mtfoods:apple_juice", 2)
	hbhunger.register_food("mtfoods:apple_cider", 2)
	hbhunger.register_food("mtfoods:cider_rack", 2)
end

if minetest.get_modpath("fruit") ~= nil then
	hbhunger.register_food("fruit:apple", 2)
	hbhunger.register_food("fruit:pear", 2)
	hbhunger.register_food("fruit:bananna", 3)
	hbhunger.register_food("fruit:orange", 2)
end

if minetest.get_modpath("mush45") ~= nil then
	hbhunger.register_food("mush45:meal", 4)
end

if minetest.get_modpath("seaplants") ~= nil then
	hbhunger.register_food("seaplants:kelpgreen", 1)
	hbhunger.register_food("seaplants:kelpbrown", 1)
	hbhunger.register_food("seaplants:seagrassgreen", 1)
	hbhunger.register_food("seaplants:seagrassred", 1)
	hbhunger.register_food("seaplants:seasaladmix", 6)
	hbhunger.register_food("seaplants:kelpgreensalad", 1)
	hbhunger.register_food("seaplants:kelpbrownsalad", 1)
	hbhunger.register_food("seaplants:seagrassgreensalad", 1)
	hbhunger.register_food("seaplants:seagrassgreensalad", 1)
end

if minetest.get_modpath("mobfcooking") ~= nil then
	hbhunger.register_food("mobfcooking:cooked_pork", 6)
	hbhunger.register_food("mobfcooking:cooked_ostrich", 6)
	hbhunger.register_food("mobfcooking:cooked_beef", 6)
	hbhunger.register_food("mobfcooking:cooked_chicken", 6)
	hbhunger.register_food("mobfcooking:cooked_lamb", 6)
	hbhunger.register_food("mobfcooking:cooked_venison", 6)
	hbhunger.register_food("mobfcooking:cooked_fish", 6)
end

if minetest.get_modpath("creatures") ~= nil then
	hbhunger.register_food("creatures:meat", 6)
	hbhunger.register_food("creatures:flesh", 3)
	hbhunger.register_food("creatures:rotten_flesh", 3, "", 3)
end

if minetest.get_modpath("ethereal") then
   hbhunger.register_food("ethereal:strawberry", 1)
   hbhunger.register_food("ethereal:banana", 4)
   hbhunger.register_food("ethereal:pine_nuts", 1)
   hbhunger.register_food("ethereal:bamboo_sprout", 0, "", 3)
   hbhunger.register_food("ethereal:fern_tubers", 1)
   hbhunger.register_food("ethereal:banana_bread", 7)
   hbhunger.register_food("ethereal:mushroom_plant", 2)
   hbhunger.register_food("ethereal:coconut_slice", 2)
   hbhunger.register_food("ethereal:golden_apple", 4, "", nil, 10)
   hbhunger.register_food("ethereal:wild_onion_plant", 2)
   hbhunger.register_food("ethereal:mushroom_soup", 4, "ethereal:bowl")
   hbhunger.register_food("ethereal:mushroom_soup_cooked", 6, "ethereal:bowl")
   hbhunger.register_food("ethereal:hearty_stew", 6, "ethereal:bowl", 3)
   hbhunger.register_food("ethereal:hearty_stew_cooked", 10, "ethereal:bowl")
   if minetest.get_modpath("bucket") then
  	hbhunger.register_food("ethereal:bucket_cactus", 2, "bucket:bucket_empty")
   end
   hbhunger.register_food("ethereal:fish_raw", 2)
   hbhunger.register_food("ethereal:fish_cooked", 5)
   hbhunger.register_food("ethereal:seaweed", 1)
   hbhunger.register_food("ethereal:yellowleaves", 1, "", nil, 1)
   hbhunger.register_food("ethereal:sashimi", 4)
   hbhunger.register_food("ethereal:orange", 2)
end

if minetest.get_modpath("farming") and farming.mod == "redo" then
   hbhunger.register_food("farming:bread", 6)
   hbhunger.register_food("farming:potato", 1)
   hbhunger.register_food("farming:baked_potato", 6)
   hbhunger.register_food("farming:cucumber", 4)
   hbhunger.register_food("farming:tomato", 4)
   hbhunger.register_food("farming:carrot", 3)
   hbhunger.register_food("farming:carrot_gold", 6, "", nil, 8)
   hbhunger.register_food("farming:corn", 3)
   hbhunger.register_food("farming:corn_cob", 5)
   hbhunger.register_food("farming:melon_slice", 2)
   hbhunger.register_food("farming:pumpkin_slice", 1)
   hbhunger.register_food("farming:pumpkin_bread", 9)
   hbhunger.register_food("farming:coffee_cup", 2, "farming:drinking_cup")
   hbhunger.register_food("farming:coffee_cup_hot", 3, "farming:drinking_cup", nil, 2)
   hbhunger.register_food("farming:cookie", 2)
   hbhunger.register_food("farming:chocolate_dark", 3)
   hbhunger.register_food("farming:donut", 4)
   hbhunger.register_food("farming:donut_chocolate", 6)
   hbhunger.register_food("farming:donut_apple", 6)
   hbhunger.register_food("farming:raspberries", 1)
   hbhunger.register_food("farming:blueberries", 1)
   hbhunger.register_food("farming:muffin_blueberry", 4)
   if minetest.get_modpath("vessels") then
	hbhunger.register_food("farming:smoothie_raspberry", 2, "vessels:drinking_glass")
   end
   hbhunger.register_food("farming:rhubarb", 1)
   hbhunger.register_food("farming:rhubarb_pie", 6)
   hbhunger.register_food("farming:beans", 1)
end

if minetest.get_modpath("kpgmobs") ~= nil then
	hbhunger.register_food("kpgmobs:uley", 3)
	hbhunger.register_food("kpgmobs:meat", 6)
	hbhunger.register_food("kpgmobs:rat_cooked", 5)
	hbhunger.register_food("kpgmobs:med_cooked", 4)
  	if minetest.get_modpath("bucket") then
	   hbhunger.register_food("kpgmobs:bucket_milk", 4, "bucket:bucket_empty")
	end
end

if minetest.get_modpath("jkfarming") ~= nil then
	hbhunger.register_food("jkfarming:carrot", 3)
	hbhunger.register_food("jkfarming:corn", 3)
	hbhunger.register_food("jkfarming:melon_part", 2)
	hbhunger.register_food("jkfarming:cake", 3)
end

if minetest.get_modpath("jkanimals") ~= nil then
	hbhunger.register_food("jkanimals:meat", 6)
end

if minetest.get_modpath("jkwine") ~= nil then
	hbhunger.register_food("jkwine:grapes", 2)
	hbhunger.register_food("jkwine:winebottle", 1)
end

if minetest.get_modpath("cooking") ~= nil then
	hbhunger.register_food("cooking:meat_beef_cooked", 4)
	hbhunger.register_food("cooking:fish_bluewhite_cooked", 3)
	hbhunger.register_food("cooking:fish_clownfish_cooked", 1)
	hbhunger.register_food("cooking:meat_chicken_cooked", 2)
	hbhunger.register_food("cooking:meat_cooked", 2)
	hbhunger.register_food("cooking:meat_pork_cooked", 3)
	hbhunger.register_food("cooking:meat_toxic_cooked", -3)
	hbhunger.register_food("cooking:meat_venison_cooked", 3)
	hbhunger.register_food("cooking:meat_undead_cooked", 1)
end

-- ferns mod of plantlife_modpack
if minetest.get_modpath("ferns") ~= nil then
	hbhunger.register_food("ferns:fiddlehead", 1, "", 1)
	hbhunger.register_food("ferns:fiddlehead_roasted", 3)
	hbhunger.register_food("ferns:ferntuber_roasted", 3)
	hbhunger.register_food("ferns:horsetail_01", 1)
end

if minetest.get_modpath("pizza") ~= nil then
	hbhunger.register_food("pizza:pizza", 30, "", nil, 30)
	hbhunger.register_food("pizza:pizzaslice", 5, "", nil, 5)
end

if minetest.get_modpath("nssm") then
	hbhunger.register_food("nssm:werewolf_leg", 3)
	hbhunger.register_food("nssm:heron_leg", 2)
	hbhunger.register_food("nssm:chichibios_heron_leg", 4)
	hbhunger.register_food("nssm:crocodile_tail", 3)
	hbhunger.register_food("nssm:duck_legs", 1)
	hbhunger.register_food("nssm:ant_leg", 1)
	hbhunger.register_food("nssm:spider_leg", 1)
	hbhunger.register_food("nssm:tentacle", 2)
	hbhunger.register_food("nssm:worm_flesh", 2, "", 2) -- poisonous
	hbhunger.register_food("nssm:amphibian_heart", 1)
	hbhunger.register_food("nssm:raw_scrausics_wing", 1)
	-- superfoods
	hbhunger.register_food("nssm:phoenix_nuggets", 20, "", nil, 20)
	hbhunger.register_food("nssm:phoenix_tear", 20, "", nil, 20)
end

if minetest.get_modpath("farming")
   and farming.mod == "civfarm"
   and minetest.get_modpath("bucket")
   and minetest.get_modpath("mobs")
   and mobs.mod
   and mobs.mod == "redo"
then

   -- poor (0-5), poisonous
   hbhunger.register_food("flowers:mushroom_red", 0.5, nil, 25, nil, nil, 5)
   hbhunger.register_food(      "farming:potato", 2,   nil, 40, nil, nil, 5)
   hbhunger.register_food(       "mobs:pork_raw", 2,   nil, 40, nil, nil, 5)
   hbhunger.register_food(    "mobs:chicken_raw", 2,   nil, 40, nil, nil, 5)
   hbhunger.register_food(       "mobs:meat_raw", 2,   nil, 40, nil, nil, 5)
   hbhunger.register_food(     "mobs:mutton_raw", 2,   nil, 40, nil, nil, 5)
   hbhunger.register_food(     "mobs:rabbit_raw", 2,   nil, 40, nil, nil, 5)
   -- adequate (6-10)
   hbhunger.register_food("flowers:mushroom_brown", 1,   nil, nil, nil, nil, 10)
   hbhunger.register_food(   "default:blueberries", 0.5, nil, nil, nil, nil, 10)
   hbhunger.register_food(         "default:apple", 1,   nil, nil, nil, nil, 10)
   hbhunger.register_food(         "farming:agave", 1.5, nil, nil, nil, nil, 10)
   hbhunger.register_food(       "farming:sorghum", 1.5, nil, nil, nil, nil, 10)
   hbhunger.register_food(          "farming:corn", 1.5, nil, nil, nil, nil, 10)
   hbhunger.register_food(        "farming:tomato", 1.5, nil, nil, nil, nil, 10)
   hbhunger.register_food(         "farming:grape", 1.5, nil, nil, nil, nil, 10)
   hbhunger.register_food(       "farming:lettuce", 1.5, nil, nil, nil, nil, 10)
   hbhunger.register_food(          "farming:beet", 1.5, nil, nil, nil, nil, 10)
   hbhunger.register_food(       "mobs:rat_cooked", 2,   nil, nil, nil, nil, 10)
   hbhunger.register_food(         "default:bacon", 2,   nil, nil, nil, nil, 10)
   hbhunger.register_food(            "mobs:honey", 1,   nil, nil, nil, nil, 10)
   hbhunger.register_food(          "farming:tofu", 1.0, nil, nil, nil, nil, 10)
   hbhunger.register_food(       "farming:noodles", 1.0, nil, nil, nil, nil, 10)
   -- good (11-20)
   hbhunger.register_food(   "farming:smoked_tofu", 2.0, nil, nil, nil, nil, 12)
   hbhunger.register_food(    "farming:fried_tofu", 2.0, nil, nil, nil, nil, 12)
   hbhunger.register_food(  "farming:baked_potato", 3, nil, nil, nil, nil, 15)
   hbhunger.register_food(   "farming:cooked_rice", 3, nil, nil, nil, nil, 15)
   hbhunger.register_food(         "farming:bread", 4, nil, nil, nil, nil, 15)
   hbhunger.register_food(    "farming:bread_corn", 4, nil, nil, nil, nil, 15)
   hbhunger.register_food( "farming:bread_sorghum", 4, nil, nil, nil, nil, 15)
   hbhunger.register_food(         "farming:fries", 4, nil, nil, nil, nil, 15)
   hbhunger.register_food(          "farming:soup", 4, nil, nil, nil, nil, 18)
   hbhunger.register_food(  "farming:garden_salad", 5, nil, nil, nil, nil, 18)
   hbhunger.register_food( "farming:grain_salad", 5.5, nil, nil, nil, nil, 18)
   hbhunger.register_food(      "mobs:pork_cooked", 3, nil, nil, nil, nil, 15)
   hbhunger.register_food(   "mobs:chicken_cooked", 3, nil, nil, nil, nil, 15)
   hbhunger.register_food(    "mobs:rabbit_cooked", 3, nil, nil, nil, nil, 15)
   hbhunger.register_food(    "mobs:mutton_cooked", 3, nil, nil, nil, nil, 15)
   hbhunger.register_food("mobs:chicken_egg_fried", 3, nil, nil, nil, nil, 15)
   hbhunger.register_food(             "mobs:meat", 3, nil, nil, nil, nil, 15)
   hbhunger.register_food(      "default:pie_meat", 6, nil, nil, nil, nil, 20)
   hbhunger.register_food("farming:sandwich_veg", 5.5, nil, nil, nil, nil, 20)
   hbhunger.register_food(     "default:pie_berry", 3.5, nil, nil, nil, nil, 17)
   hbhunger.register_food(  "default:pie_mushroom", 4.5, nil, nil, nil, nil, 18)
   hbhunger.register_food("mobs:bucket_milk", 3, "bucket:bucket_empty", nil, nil, nil, 15)
   hbhunger.register_food("mobs:butter", 2, nil, nil, nil, nil, 20)
   hbhunger.register_food("mobs:cheese", 4, nil, nil, nil, nil, 20)
   -- very good (21-25)
   hbhunger.register_food(     "farming:risotto", 6.0, nil, nil, nil, nil, 22)
   hbhunger.register_food(    "farming:stir_fry", 7.0, nil, nil, nil, nil, 25)
   hbhunger.register_food(   "farming:spaghetti", 6.0, nil, nil, nil, nil, 25)
   hbhunger.register_food(      "farming:burger", 6.5, nil, nil, nil, nil, 25)
   hbhunger.register_food(         "farming:blt", 7.0, nil, nil, nil, nil, 25)
   hbhunger.register_food(     "farming:crumble", 5.5, nil, nil, nil, nil, 25)
   hbhunger.register_food( "farming:soup_hearty", 6.5, nil, nil, nil, nil, 25)
   hbhunger.register_food("farming:ploughmans_simple", 6.0, nil, nil, nil, nil, 25)
   hbhunger.register_food( "farming:buddha_bowl", 6.0, nil, nil, nil, nil, 25)
   -- excellent (25+)
   hbhunger.register_food("farming:spaghetti_meat", 8.0, nil, nil, nil, nil, 30)
   hbhunger.register_food("farming:burger_fries", 9.0, nil, nil, nil, nil, 30)
   hbhunger.register_food("farming:pie_luxurious", 8.5, nil, nil, nil, nil, 30)
   hbhunger.register_food("farming:ploughmans", 7.5, nil, nil, nil, nil, 30)
end

-- player-action based hunger changes
function hbhunger.handle_node_actions(pos, oldnode, player, ext)
	-- is_fake_player comes from the pipeworks, we are not interested in those
	if not player or not player:is_player() or player.is_fake_player == true then
		return
	end
	local name = player:get_player_name()
	local exhaus = hbhunger.exhaustion[name]
	if exhaus == nil then return end
	local new = hbhunger.EXHAUST_PLACE
	-- placenode event
	if not ext then
		new = hbhunger.EXHAUST_DIG
	end
	-- assume its send by main timer when movement detected
	if not pos and not oldnode then
		new = hbhunger.EXHAUST_MOVE
	end
	exhaus = exhaus + new
	if exhaus > hbhunger.EXHAUST_LVL then
		exhaus = 0
		local h = tonumber(hbhunger.hunger[name])
		h = h - 0.1
		if h < 0 then h = 0 end
		hbhunger.hunger[name] = h
		hbhunger.set_hunger_raw(player)
	end
	hbhunger.exhaustion[name] = exhaus
end

minetest.register_on_placenode(hbhunger.handle_node_actions)
minetest.register_on_dignode(hbhunger.handle_node_actions)
