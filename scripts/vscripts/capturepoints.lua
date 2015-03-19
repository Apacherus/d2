require('timers')

if CPBase == nil then
	CPBase = class({})
	GameRules.CPBase = CPBase
end

CPBase.points = {}
CPBase.options = {
	captureCost = 300, -- вознаграждение за первый захват точки
	reCaptureCost = 100, -- вознаграждение за повторный захват точки
	msgTeamBad = "The Dire",
	msgTeamGood = "The Radiant",
	startLevel = 6, -- уровень героев при старте
	startGold = 1000,
	goldPerTick = 99999,
	goldTick = 1,
	XP = 1500, -- опыт который даётся за захват точки (распределяется между игроками, захватившими точку, в радиусе XPGainRadius от точки)
	XPGainRadius = 1000,
	captureSpeedBonus = 0
}

CPBase.teamOptions = {
	[DOTA_TEAM_GOODGUYS] = {
		
	},
	[DOTA_TEAM_BADGUYS] = {
		
	}
}



function CPBase:Init()

	ListenToGameEvent( "npc_spawned", 	Dynamic_Wrap( CPBase, "SetStartLevel" ), self )
	ListenToGameEvent( "entity_killed", 	Dynamic_Wrap( CPBase, "OnEntityKilled" ), self )
	self:RoshanSpawn()
	

	Convars:RegisterCommand( "cp_fake_capture_event_to_ui", function(name, point)
	    local cmdPlayer = Convars:GetCommandClient()
	    if cmdPlayer then 
	        return self:FireFakeCEToUI( tonumber(point), cmdPlayer:GetTeam()) 
	    end
	end, "", FCVAR_CHEAT )

	Convars:RegisterCommand( "cp_test", function(name)
	    local cmdPlayer = Convars:GetCommandClient()
	    ShowGenericPopupToPlayer(cmdPlayer, "awdawd", "84hf4ew9", "", "", DOTA_SHOWGENERICPOPUP_TINT_SCREEN) 
	end, "", FCVAR_CHEAT )

	Convars:RegisterCommand( "cp_ursa_test", function(name, point)
	    point = tonumber(point)
	    self.roshling:MoveToPositionAggressive(self:GetPoint(point).position)
	end, "", FCVAR_CHEAT )

	Convars:RegisterCommand("cp_debug_draw_points", function()self:DebugDrawPointsRadius()end, "", FCVAR_CHEAT)
	Convars:RegisterCommand("cp_debug_ui_draw_mesh", function() FireGameEvent("cp_debug_ui_draw_mesh", nil) end, "", FCVAR_CHEAT)

	Convars:RegisterCommand("cp_capture_point", function(name, id)
		local cmdPlayer = Convars:GetCommandClient()
		local point = CPBase:GetPoint(id)
		point.captured = 100
		point.team = cmdPlayer:GetTeam()
		point.capture_team = cmdPlayer:GetTeam()
		CPBase:CaptureEvent(point)
		end, "", FCVAR_CHEAT)

	GameRules:SetGoldPerTick(self.options.goldPerTick)
	GameRules:SetGoldTickTime(self.options.goldTick)
end

function CPBase:RoshanSpawn()
	local points = Entities:FindAllByClassname("trigger_hero")
	local position = 0
	for k,v in pairs(points) do
		if v:GetIntAttr("RoshanSpawn") then
			position = v:EyePosition() 
		end
	end

	self.roshan_bad = CreateUnitByName('npc_dota_neutral_polar_furbolg_ursa_warrior', position, true, nil, nil, DOTA_TEAM_NEUTRALS)
	self.roshan_bad:SetModelScale(3)


end

function CPBase:RoshlingSpawn(team, position, owner)
	self.tristan = CreateUnitByName('npc_cp_tristan', position, true, owner, owner, team)

	self.tristan:MoveToPositionAggressive(self:GetPoint(1).position)
	self.tristan:SetControllableByPlayer(owner:GetPlayerID(), true)
	self.tristan:GetAbilityByIndex(0):SetLevel(1)
	self.tristan:GetAbilityByIndex(1):SetLevel(1)
	self.tristan:GetAbilityByIndex(2):SetLevel(1)
	self.tristan:GetAbilityByIndex(3):SetLevel(1)


	self.justin = CreateUnitByName('npc_cp_justin', position, true, owner, owner, team)

	self.justin:MoveToPositionAggressive(self:GetPoint(1).position)
	self.justin:SetControllableByPlayer(owner:GetPlayerID(), true)
	self.justin:GetAbilityByIndex(0):SetLevel(1)
	self.justin:GetAbilityByIndex(1):SetLevel(1)
	self.justin:GetAbilityByIndex(2):SetLevel(1)
	self.justin:GetAbilityByIndex(3):SetLevel(1)

end

function CPBase:OnEntityKilled(keys)
	local unit = EntIndexToHScript(keys.entindex_killed)
	local attacker = 0
	if unit:GetUnitName() == 'npc_dota_neutral_polar_furbolg_ursa_warrior' then 
		attacker = EntIndexToHScript(keys.entindex_attacker)
		self:RoshlingSpawn(attacker:GetTeam(), unit:EyePosition(), attacker, attacker)
	end
end

function CPBase:OnGameStartCheck()
	local nNewState = GameRules:State_Get()

	if nNewState == DOTA_GAMERULES_STATE_PRE_GAME then
		CPBase:FindPoints()
	end

	if nNewState == DOTA_GAMERULES_STATE_GAME_IN_PROGRESS then
		self:FireUnlockFirstPoint()
		self:FireUnlockSidePoints()
		CPBase:CheckPointsTimer()
	end
end

function CPBase:SetStartLevel(keys)
	local unit = EntIndexToHScript(keys.entindex)
	if unit:IsHero() and not unit:IsIllusion() then
		while unit:GetLevel() < self.options.startLevel do
			unit:AddExperience(100, false, false)
		end
	end
end

function CPBase:FindPoints()
	local points = Entities:FindAllByClassname("trigger_hero")

	for k,v in pairs(points) do
		if v:GetIntAttr("IsPoint") then
			CPBase.points[tablelength(CPBase.points)] = -- список всех точек
			{
			id = v:GetIntAttr("PointID"), -- id точки
			team = -1, -- команда захватившая точку, для незахваченных точек = -1
			captured = 0, -- захвачено (0-100)
			capture_team = -1, -- команда которая ЗАХВАТЫВАЕТ точку
			players = {team_0=0, team_1=0}, -- количество игроков на точке
			playersPreviews = {team_0=0, team_1=0}, -- количество игроков на точке при прошлой проверке (нужно для отслеживания изменения и вызова события обновления счетчика в UI)
			radius = v:GetIntAttr("CaptureRadius"), -- радиус нахождения игроков для захвата
			lockPoint = v:GetIntAttr("LockPoint"), -- точка, которая должна быть захвачена, для того чтобы ЭТА точка стала доступной для захвата
			locked = v:GetIntAttr("Locked"), -- точка заблокирована для захвата? (0 - доступна для захвата, 1 - заблокирована)
			position = v:EyePosition(), -- координаты (центра) точки
			teamsCaptureBefore = {team_0 = 0, team_1 = 0}, -- команды которые захватывали точку когда либо (0 - не захватывала, 1 - захватывала)
			isFinal = v:GetIntAttr("IsFinal"), -- последняя точка которую надо захватить
			tpsUnit = nil, -- ссылка на юнит npc_cf_tps_point_
			isLine = v:GetIntAttr("IsLine"), -- 0 или номер линии (1,2,3, ...) !!!!пока используем только 1!!!!
			lineNumber = v:GetIntAttr("LineNumber"), -- номер в линии
			lastCaptureTime = 0,
			type = v:GetIntAttr("Type") -- типы точек: bounty = 1, combat = 2, regen = 3, speed = 4 ||| combat is unreleased
			}
			if v:GetIntAttr("IsLine") ~= 0 and v:GetIntAttr("IsLine") ~= nil  then
				print("Add point to UI: "..v:GetIntAttr("PointID"))
				FireGameEvent('cp_point_add', {point = v:GetIntAttr("PointID")})
			else
				print("Add side point to UI: "..v:GetIntAttr("PointID"))
				FireGameEvent('cp_add_side_point', {point = v:GetIntAttr("PointID")})
			end
		end
	end
end

function CPBase:CheckPointsTimer()
	if GameRules.CPMain.options.finished == true then
		return false
	end
	CPBase:CheckPoints()
	Timers:CreateTimer(1, function() CPBase:CheckPointsTimer() end)
end

function CPBase:CheckPoints()
	local boc_good = 0 -- boots of capture bonus
	local boc_bad = 0 -- boots of capture bonus
	local boc_current_increase = 0
	for k,v in pairs(CPBase.points) do
		boc_good = 0
		boc_bad = 0
		boc_current_increase = 0
		if v.locked == 0 then
			local good = FindUnitsInRadius(DOTA_TEAM_GOODGUYS,
                              v.position,
                              nil,
                              v.radius,
                              DOTA_UNIT_TARGET_TEAM_FRIENDLY,
                              DOTA_UNIT_TARGET_HERO,
                              DOTA_UNIT_TARGET_FLAG_NONE,
                              FIND_ANY_ORDER,
                              false)
			for _,g in pairs(good) do
				if g:HasItemInInventory("item_cp_boots_of_capture") then
					for i = 0, 5, 1 do
						if g:GetItemInSlot(i) ~= nil and g:GetItemInSlot(i):GetAbilityName() == "item_cp_boots_of_capture" then
							if g:GetItemInSlot(i):GetPurchaser() == g then
								boc_current_increase = 1
							end
						end
					end
					boc_good = boc_good + boc_current_increase
					boc_current_increase = 0
				end
			end
			v.players.team_0 = tablelength(good) + boc_good
			local bad = FindUnitsInRadius(DOTA_TEAM_BADGUYS,
                              v.position,
                              nil,
                              v.radius,
                              DOTA_UNIT_TARGET_TEAM_FRIENDLY,
                              DOTA_UNIT_TARGET_HERO,
                              DOTA_UNIT_TARGET_FLAG_NONE,
                              FIND_ANY_ORDER,
                              false)
			for _,b in pairs(bad) do
				if b:HasItemInInventory("item_cp_boots_of_capture") then
					for i = 0, 5, 1 do
						if b:GetItemInSlot(i) ~= nil and b:GetItemInSlot(i):GetAbilityName() == "item_cp_boots_of_capture" then
							if b:GetItemInSlot(i):GetPurchaser() == b then
								boc_current_increase = 1
							end
						end
					end
					boc_bad = boc_bad + boc_current_increase
					boc_current_increase = 0
				end
			end
			v.players.team_1 = tablelength(bad) + boc_bad


			if v.players.team_0 ~= 0 and v.playersPreviews.team_0 ~= v.players.team_0 then
				print("A")
				self:FireSetCounterValue(v, v.players.team_0)
			end

			if v.players.team_1 ~= 0 and v.playersPreviews.team_1 ~= v.players.team_1 then
				print("B")
				self:FireSetCounterValue(v, v.players.team_1)
			end

			if v.players.team_0 == 0 and v.playersPreviews.team_0 ~= 0 then
				print("C")
				--вызываем событие установки счетчика в 0
				self:FireSetCounterValue(v, 0)
			end

			if v.players.team_1 == 0 and v.playersPreviews.team_1 ~= 0 then
				print("D")
				--вызываем событие установки счетчика в 0
				self:FireSetCounterValue(v, 0)
			end

			if (v.players.team_0 ~= 0 and v.players.team_1 ~= 0) and (v.playersPreviews.team_0 ~= v.players.team_0 or v.playersPreviews.team_1 ~= v.players.team_1) then
				print("E")
				self:FireSetCounterValue(v, 0)
			end


			if v.players.team_0 ~= 0 and v.players.team_1 == 0 then
				CPBase:CapturePoint(v, DOTA_TEAM_GOODGUYS, v.players.team_0)
				v.lastCaptureTime = GameRules:GetGameTime()
			elseif v.players.team_0 == 0 and v.players.team_1 ~= 0 then
				CPBase:CapturePoint(v, DOTA_TEAM_BADGUYS, v.players.team_1)
				v.lastCaptureTime = GameRules:GetGameTime()
			end

			v.playersPreviews.team_0 = v.players.team_0
			v.playersPreviews.team_1 = v.players.team_1

			-- система возврата точки (в том случае если захват был прерван точка автоматически вернётся под контроль удерживающей её точки даже если на ней не будет игроков этой команды)
			-- * включается через 10 секунд
			-- * только для лайновых точек	
			if v.players.team_0 == 0 and v.players.team_1 == 0 and v.isLine == 1 then

				if v.team ~= v.capture_team and v.captured > 0 and v.captured < 100 and v.lastCaptureTime+10 < GameRules:GetGameTime() then
					v.captured = v.captured - 5
					if v.captured <= 0 then
						if v.team == -1 then
							v.captured = 0
						else
							v.captured = 100
						end
						v.capture_team = v.team
					end
					self:FireSetCapturedValue(v)
				end

				if v.team == v.capture_team and v.captured > 0 and v.captured < 100 and v.lastCaptureTime+10 < GameRules:GetGameTime() then
					v.captured = v.captured + 5
					if v.captured >= 100 then
						v.captured = 100
					end
					self:FireSetCapturedValue(v)
				end

			end
		end
	end

end

function CPBase:CapturePoint(point, team, count)


	print("POINT ID "..point.id.." PLAYERS: GOOD "..point.players.team_0.." BAD "..point.players.team_1.." TEAM "..point.team.." CAPTURE TEAM "..point.capture_team.." CAPTURED "..point.captured)

	if point.team == team and point.captured == 100 then -- точка уже захвачена этой командой
		return true
	end

	if point.isFinal == 1 then -- точка которую нужно захватить чтобы выиграть, проверяем чтобы все предыдущие точки были захвачены
		for k,v in pairs(CPBase.points) do
			if v.isLine == 1 and v.id ~= point.id then
				if v.team ~= team then
					print("Cannot capture the point because one or more previews points is not captured!")
					return false -- одна (или несколько) предыдущих точек не захвачено
				end
			end
		end
	end

	local speedUp = self.options.captureSpeedBonus -- debug cheat
	local speed = 1
	if point.isLine == 1 then
		speed = 3 - point.id
	end
	local captureValue = count + speed + speedUp



	if point.locked == 0 then -- по идее проверка не нужна т.к. есть выше, убрать??

		if point.isLine == 1 and point.lockPoint ~= -1 then
			local lockPoint = CPBase:GetPoint(point.lockPoint)
			if lockPoint.team ~= team then
				return false
			end
		end
		
		if point.team == -1 and point.capture_team == -1 then
			point.capture_team = team
		end


		if point.capture_team ~= team then
			if point.captured > 0 then
				point.captured = point.captured - captureValue
			end
			if point.captured <= 0 then
				point.captured = 0
				point.capture_team = team
				if point.team ~= team and point.team ~= -1 then
					point.team = -1
					self:FireSetCapturedState(point)
					self:FireSetLockedState(point)
					if point.tpsUnit ~= nil then
						point.tpsUnit:Kill(nil, nil)
						point.tpsUnit = nil
					end
				end
			end
		end

		if point.team ~= team and point.capture_team == team then
			if point.captured < 100 then
				point.captured = point.captured + captureValue
			end
			if point.captured >= 100 then
				point.captured = 100
				point.team = team
				self:CaptureEvent(point)
			end
		end

		if point.team == team and point.capture_team == team and point.captured < 100 then
			point.captured = point.captured + captureValue
			if point.captured > 100 then
				point.captured = 100
			end
		end


	end

	--self:FireSetCounterValue(point, count)
	--if point.isLine == 1 then
		self:FireSetCaptureTeam(point)
		self:FireSetCapturedValue(point)
	--end



end






function CPBase:CaptureEvent(point)
	local cost = 0
	local team = 0
	if point.team == DOTA_TEAM_GOODGUYS then
		if point.teamsCaptureBefore.team_0 == 1 then
			cost = CPBase.options.reCaptureCost
		else
			cost = CPBase.options.captureCost
			self:XPGain(point)
		end
		team = DOTA_TEAM_GOODGUYS
		point.teamsCaptureBefore.team_0 = 1
	else
		if point.teamsCaptureBefore.team_1 == 1 then
			cost = CPBase.options.reCaptureCost
		else
			cost = CPBase.options.captureCost
			self:XPGain(point)
		end
		team = DOTA_TEAM_BADGUYS
		point.teamsCaptureBefore.team_1 = 1
	end

	local players = FindUnitsInRadius(team,
                              Vector(0, 0, 0),
                              nil,
                              FIND_UNITS_EVERYWHERE,
                              DOTA_UNIT_TARGET_TEAM_FRIENDLY,
                              DOTA_UNIT_TARGET_HERO,
                              DOTA_UNIT_TARGET_FLAG_NONE,
                              FIND_ANY_ORDER,
                              false)

	for _,unit in pairs(players) do
		unit:ModifyGold(cost, true, 0)
	end

	local unit = point.team == DOTA_TEAM_GOODGUYS and "npc_cf_tps_point_good" or "npc_cf_tps_point_bad"

	if point.tpsUnit ~= nil then
		point.tpsUnit:Kill(nil, nil)
		point.tpsUnit = nil
	end

	point.tpsUnit = CreateUnitByName(unit, point.position, false, nil, nil, point.team)

	if point.type == 1 then -- bounty point
		point.tpsUnit:AddAbility("cp_point_ability_bounty")
		point.tpsUnit:GetAbilityByIndex(0):SetLevel(1)
	end

	if point.type == 3 then -- regen point
		point.tpsUnit:AddAbility("cp_point_ability_regen")
		point.tpsUnit:GetAbilityByIndex(0):SetLevel(1)
	end

	if point.type == 4 then -- speed point
		point.tpsUnit:AddAbility("cp_point_ability_speed")
		point.tpsUnit:GetAbilityByIndex(0):SetLevel(1)
	end

	

	EmitGlobalSound("compendium_levelup")

	if point.team == DOTA_TEAM_GOODGUYS then
		CPBase:Message("#cp_point_captured_radiant", 0)
	else
		CPBase:Message("#cp_point_captured_dire", 0)
	end

	--if point.isLine == 1 then
		self:FireSetCapturedState(point)
		self:FireSetLockedState(point)
	--end

	if point.isFinal == 1 then
		CPBase:Win(team)
	end

	

end

function CPBase:PlayerEnterPoint(point, player)
end

function CPBase:PlayerLeavePoint(point, player)
end

function CPBase:BountyTick(team, stop)
	if stop == nil then
		stop = false
	end

	if stop == true then
		return false
	end

	local count = self.teamOptions[team].bountyCount
	local goldAmount = count * self.options.goldPerTickBounty

	local players = GetPlayers(team)
	for k,v in pairs(players) do
		v:ModifyGold(goldAmount, true, 0)
	end
	Timers:CreateTimer(self.options.bountyTick, function() CPBase:BountyTick(team) end)

end

function CPBase:FireSetCounterValue(point, counter)

	print("Fire set counter value, point "..point.id.." counter "..counter)

	local playersBad = GetPlayers(DOTA_TEAM_BADGUYS)
	local playersGood = GetPlayers(DOTA_TEAM_GOODGUYS)
	local side = 'side'
	if point.isLine ~= 0 then
		side = 'line'
	end

	for k,v in pairs(playersBad) do
		FireGameEvent("cp_set_players_counter", {player = v:GetPlayerID(), point = point.id, value = counter, type = side}) 
	end

	for k,v in pairs(playersGood) do
		FireGameEvent("cp_set_players_counter", {player = v:GetPlayerID(), point = point.id, value = counter, type = side}) 
	end

end


function CPBase:FireSetCaptureTeam(point)

	local players_bad = GetPlayers(DOTA_TEAM_BADGUYS)
	local players_good = GetPlayers(DOTA_TEAM_GOODGUYS)

	local badTeam = 0
	local goodTeam = 0

	if point.capture_team == DOTA_TEAM_GOODGUYS then
		badTeam = 'enemy'
		goodTeam = 'allies'
	else
		badTeam = 'allies'
		goodTeam = 'enemy'
	end

	local side = 'side'
	if point.isLine ~= 0 then
		side = 'line'
	end

	for k,v in pairs(players_bad) do 
		FireGameEvent('cp_set_capture_team', {player = v:GetPlayerID(), point = point.id, team = badTeam, type = side});
	end

	for k,v in pairs(players_good) do 
		FireGameEvent('cp_set_capture_team', {player = v:GetPlayerID(), point = point.id, team = goodTeam, type = side});
	end

end


function CPBase:FireSetCapturedValue(point)

	local players_bad = GetPlayers(DOTA_TEAM_BADGUYS)
	local players_good = GetPlayers(DOTA_TEAM_GOODGUYS)

	local side = 'side'
	if point.isLine ~= 0 then
		side = 'line'
	end

	for k,v in pairs(players_bad) do 
		FireGameEvent('cp_set_captured_value', {player = v:GetPlayerID(), point = point.id, value = point.captured, type = side});
	end

	for k,v in pairs(players_good) do 
		FireGameEvent('cp_set_captured_value', {player = v:GetPlayerID(), point = point.id, value = point.captured, type = side});
	end
end


function CPBase:FireSetCapturedState(point)

	local players_bad = GetPlayers(DOTA_TEAM_BADGUYS)
	local players_good = GetPlayers(DOTA_TEAM_GOODGUYS)

	local stateBad = ''
	local stateGood

	local side = 'side'
	if point.isLine ~= 0 then
		side = 'line'
	end

	if point.team == DOTA_TEAM_GOODGUYS then
		stateBad = 'enemy'
		stateGood = 'allies'
	elseif point.team == DOTA_TEAM_BADGUYS then
		stateBad = 'allies'
		stateGood = 'enemy'
	else
		stateBad = 'none'
		stateGood = 'none'
	end

	for k,v in pairs(players_bad) do 
		FireGameEvent('cp_set_captured_state', {player = v:GetPlayerID() , point = point.id, state = stateBad, type = side});
	end

	for k,v in pairs(players_good) do 
		FireGameEvent('cp_set_captured_state', {player = v:GetPlayerID() , point = point.id, state = stateGood, type = side});
	end
end

function CPBase:FireSetLockedState(point)

	local players_bad = GetPlayers(DOTA_TEAM_BADGUYS)
	local players_good = GetPlayers(DOTA_TEAM_GOODGUYS)
	local playersLock = 0
	local playersUnlock = 0
	local stateLock = true
	local stateUnlock = false

	if point.team == DOTA_TEAM_GOODGUYS then
		playersLock = players_bad
		playersUnlock = players_good
	elseif point.team == DOTA_TEAM_BADGUYS then
		playersLock = players_good
		playersUnlock = players_bad
	else
		playersLock = players_good
		playersUnlock = players_bad
		stateLock = true
		stateUnlock = true
	end

	local side = 'side'
	if point.isLine ~= 0 then
		side = 'line'
	end

	for k,v in pairs(self.points) do
		if v.id > point.id and v.isLine >= 1 then
			for k1,v1 in pairs(playersLock) do
				FireGameEvent('cp_set_locked_state', {player = v1:GetPlayerID() , point = v.id, state = stateLock, type = side});
			end

			if v.id == point.id+1 or v.team == point.team then
				for k2,v2 in pairs(playersUnlock) do
					FireGameEvent('cp_set_locked_state', {player = v2:GetPlayerID() , point = v.id, state = stateUnlock, type = side});
					if v.team == point.team then
						FireGameEvent('cp_set_locked_state', {player = v2:GetPlayerID() , point = v.id+1, state = stateUnlock, type = side});
					end
				end
			end
		end
	end

	
end

function CPBase:DebugDrawPointsRadius()
	for k,point in pairs(self.points) do
		DebugDrawCircle(point.position, Vector(255, 0, 0), 1, point.radius, false, 1000)
		DebugDrawCircle(point.position, Vector(170, 50, 200), 1, 20, false, 1000)
		DebugDrawCircle(point.position, Vector(0, 255, 0), 1, self.options.XPGainRadius, false, 1000)
	end
end

function CPBase:XPGain(point)
	local players = GetPlayers(point.team, point.position, 1000)
	local count = tablelength(players)
	
	if count == 0 then
		print("No heroes at xp-gain radius!")
		return false
	end
	local xpPerPlayer = self.options.XP/count

	print("Gain XP to team "..point.team.." xpp "..xpPerPlayer)
	for k,v in pairs(players) do
		v:AddExperience(xpPerPlayer, false, false)
	end
end


function CPBase:FireUnlockFirstPoint()

	local players_bad = GetPlayers(DOTA_TEAM_BADGUYS)
	local players_good = GetPlayers(DOTA_TEAM_GOODGUYS)


	for k,v in pairs(players_bad) do 
		FireGameEvent('cp_set_locked_state', {player = v:GetPlayerID() , point = 1, state = false});
	end

	for k,v in pairs(players_good) do 
		FireGameEvent('cp_set_locked_state', {player = v:GetPlayerID() , point = 1, state = false});
	end

end

function CPBase:FireUnlockSidePoints()

	local players_bad = GetPlayers(DOTA_TEAM_BADGUYS)
	local players_good = GetPlayers(DOTA_TEAM_GOODGUYS)


	for k,v in pairs(players_bad) do 
		FireGameEvent('cp_set_locked_state', {player = v:GetPlayerID() , point = 50, state = false, type = 'side'});
		FireGameEvent('cp_set_locked_state', {player = v:GetPlayerID() , point = 60, state = false, type = 'side'});
	end

	for k,v in pairs(players_good) do 
		FireGameEvent('cp_set_locked_state', {player = v:GetPlayerID() , point = 50, state = false, type = 'side'});
		FireGameEvent('cp_set_locked_state', {player = v:GetPlayerID() , point = 60, state = false, type = 'side'});
	end

end


function CPBase:GetPoint(id)

	id = tonumber(id)

	for k,v in pairs(CPBase.points) do
		if v.id == id then

			return v
		end
	end
end

function CPBase:Message(msg, team)
	 GameRules:SendCustomMessage(msg, team, 0)
end

function CPBase:Win(team)
	GameRules:SetSafeToLeave(true)
    GameRules:MakeTeamLose(team==DOTA_TEAM_BADGUYS and DOTA_TEAM_BADGUYS or DOTA_TEAM_GOODGUYS)
    GameRules:SetGameWinner(team)
    GameRules.CPMain.options.finished = true
    FireGameEvent('cp_hide_ui', nil);
end