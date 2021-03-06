local S = minetest.get_translator("hbhunger")

if minetest.settings:get_bool("enable_damage") then

hbhunger = {}
hbhunger.food = {}

-- HUD statbar values
hbhunger.hunger = {}
hbhunger.hunger_out = {}
-- Used for post-hunger-reset checks
hbhunger.did_starve = {}

-- Count number of poisonings a player has at once
hbhunger.poisonings = {}

-- HUD item ids
local hunger_hud = {}

hbhunger.HUD_TICK = 0.1

--Some hunger settings
hbhunger.exhaustion = {} -- Exhaustion is experimental!

hbhunger.HUNGER_TICK = 300 -- time in seconds after that 0.1 hunger point is taken
hbhunger.EXHAUST_DIG = 0  -- exhaustion increased this value after digged node
hbhunger.EXHAUST_PLACE = 0 -- exhaustion increased this value after placed
hbhunger.EXHAUST_MOVE = 0.20 -- exhaustion increased this value if player movement detected
hbhunger.EXHAUST_LVL = 25 -- at what exhaustion player satiation gets lowerd


--load custom settings
local set = io.open(minetest.get_modpath("hbhunger").."/hbhunger.conf", "r")
if set then
	dofile(minetest.get_modpath("hbhunger").."/hbhunger.conf")
	set:close()
end

local function custom_hud(player)
	hb.init_hudbar(player, "satiation", hbhunger.get_hunger_raw(player))
end

dofile(minetest.get_modpath("hbhunger").."/hunger.lua")

-- register satiation hudbar
hb.register_hudbar("satiation", 0xFFFFFF, S("Satiation"), { icon = "hbhunger_icon.png", bgicon = "hbhunger_bgicon.png",  bar = "hbhunger_bar.png" }, 20, 30, false, nil, { format_value = "%.1f", format_max_value = "%d" })

-- update hud elemtens if value has changed
local function update_hud(player)
	local name = player:get_player_name()
 --hunger
	local h_out = tonumber(hbhunger.hunger_out[name])
	local h = tonumber(hbhunger.hunger[name])
	if h_out ~= h then
		hbhunger.hunger_out[name] = h
		hb.change_hudbar(player, "satiation", h)
	end
end

hbhunger.get_hunger_raw = function(player)
	local inv = player:get_inventory()
	if not inv then return nil end
	local hgp = inv:get_stack("hunger", 1):get_count()
	if hgp == 0 then
		hgp = 21
		inv:set_stack("hunger", 1, ItemStack({name=":", count=hgp}))
	else
		hgp = hgp
	end
	return hgp-1
end

hbhunger.set_hunger_raw = function(player)
	local inv = player:get_inventory()
	local name = player:get_player_name()
	local value = hbhunger.hunger[name]
	if not inv  or not value then return nil end
	if value > 30 then value = 30 end
	if value < 0 then value = 0 end

	inv:set_stack("hunger", 1, ItemStack({name=":", count=value+1}))

	return true
end

minetest.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	local inv = player:get_inventory()
	inv:set_size("hunger",1)
	hbhunger.hunger[name] = hbhunger.get_hunger_raw(player)
	hbhunger.hunger_out[name] = hbhunger.hunger[name]
	hbhunger.exhaustion[name] = 0
	hbhunger.poisonings[name] = 0
	custom_hud(player)
	hbhunger.set_hunger_raw(player)
end)

minetest.register_on_respawnplayer(function(player)
	-- reset hunger (and save)
	local name = player:get_player_name()
        hbhunger.did_starve[name] = hbhunger.hunger[name] == 0
	hbhunger.hunger[name] = 5
	hbhunger.set_hunger_raw(player)
	hbhunger.exhaustion[name] = 0
end)

local main_timer = 0
local timer = 0
local timer2 = 0
minetest.register_globalstep(function(dtime)
	main_timer = main_timer + dtime
	timer = timer + dtime
	timer2 = timer2 + dtime
	if main_timer > hbhunger.HUD_TICK or timer > 4 or timer2 > hbhunger.HUNGER_TICK then
		if main_timer > hbhunger.HUD_TICK then
			main_timer = 0
		end
		for _,player in ipairs(minetest.get_connected_players()) do
			local name = player:get_player_name()
			local h = tonumber(hbhunger.hunger[name])
			local hp = player:get_hp()
			if timer > 4 then
				-- heal player by 1 hp if not dead and satiation is > 5 (of 30)
				-- or damage player by 5 hp if satiation is zero (of 30)
				local breath = player:get_breath()
				if h > 5 and hp > 0 and breath and breath > 0 then
					local hp_change = 1
					if h > 20 then
						hp_change = 3
	                                elseif h > 10 then
						hp_change = 2
	                                end
					player:set_hp(hp + hp_change)
				elseif h == 0 then
					if hp > 0 then
						player:set_hp(math.max(0, hp - 5))
					end
				end
			end
			-- lower satiation by 0.1 point after xx seconds
			if timer2 > hbhunger.HUNGER_TICK then
				if h > 0 and hp > 0 then
					h = h - 0.1
					h = math.max(h, 0)
					hbhunger.did_starve[name] = false
					hbhunger.hunger[name] = h
					hbhunger.set_hunger_raw(player)
				end
			end

			-- update all hud elements
			update_hud(player)

			local controls = player:get_player_control()
			-- Determine if the player is walking
			if controls.up or controls.down or controls.left or controls.right then
				hbhunger.handle_node_actions(nil, nil, player)
			end
		end
	end
	if timer > 4 then timer = 0 end
	if timer2 > hbhunger.HUNGER_TICK then timer2 = 0 end
end)

end

minetest.register_chatcommand(
   "hunger",
   {
      params = "[<target> [<hunger>]]",
      description = "Sets target's hunger to specified value. "
         .. "Default target is sender, default value is 0.0.",
      privs = { server = true },
      func = function(sender, params)
         local split_params = string.split(params, " ")

         local target = split_params[1] or sender
         local hunger = 0.0
         if split_params[2] then
            hunger = tonumber(split_params[2])
         end

         if not hunger then
            minetest.chat_send_player(sender, "New hunger must be a number.")
            return false
         end

         local player = minetest.get_player_by_name(target)
         if not player then
            minetest.chat_send_player(sender, "Player not found.")
            return false
         end

         local pname = player:get_player_name()
         hbhunger.hunger[pname] = hunger or 0.0
         hbhunger.set_hunger_raw(player)
      end
   }
)
