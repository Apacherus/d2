require('timers')
require("functions")
require("capturepoints")
--require("arena")




if CPMain == nil then
	CPMain = class({})
	GameRules.CPMain = CPMain
	CPMain.isPaused = false
	CPMain.gameTime = 0
end

CPMain.options = {
	preGameTime = 1,
	finished = false,
	version = {
		major = 0,
		minor = 1,
		type = 'a'
	}
}

function Precache( context )


end



function Activate()
	print("Capture Points addon init started")
	print("© Apacherus 2015")
	print("Thanks Valve Software for contribution")
	print("Version: "..CPMain:Version())
	
	CPMain:Init()	
end



function CPMain:Init()

	GameRules:SetPreGameTime(CPMain.options.preGameTime)
	
	ListenToGameEvent("game_rules_state_change", 	Dynamic_Wrap( CPMain, "OnGameRulesStateChange" ), CPMain )
	Convars:RegisterCommand('player_say', function(...)
    local arg = {...}
    table.remove(arg,1)
    local sayType = arg[1]
    table.remove(arg,1)

    local cmdPlayer = Convars:GetCommandClient()
    keys = {}
    keys.ply = cmdPlayer
    keys.text = table.concat(arg, " ")

    if (sayType == 4) then
      -- Student messages
      self:OnPlayerSay(keys)
    elseif (sayType == 3) then
      -- Coach messages
      self:OnPlayerSay(keys)
    elseif (sayType == 2) then
      -- Team only
      -- Call your player_say function here like
      self:OnPlayerSay(keys)
    else
      -- All chat
      -- Call your player_say function here like
      self:OnPlayerSay(keys)
    end
  	end, 'player say', 0)

		
	CPBase:Init()

	GameRules:GetGameModeEntity():SetHUDVisible(10, false) -- hide fortification button

	Convars:RegisterCommand( "cp_msg", function(name, x)
		if x == nill then
			x = ''
		end
	    ShowGenericPopup("Popup Title", "Popup Text "..x, "", "", DOTA_SHOWGENERICPOPUP_TINT_SCREEN)
	end, "", 0 )


end

function CPMain:Version()
	return CPMain.options.version.major.."."..CPMain.options.version.minor..CPMain.options.version.type
end



function CPMain:OnGameRulesStateChange()
	local nNewState = GameRules:State_Get()

	if nNewState == DOTA_GAMERULES_STATE_PRE_GAME then
		GameRules:SendCustomMessage("#cp_welcome_msg", DOTA_TEAM_NOTEAM, 0)
		GameRules:SendCustomMessage("#cp_help_hint", DOTA_TEAM_NOTEAM, 0)
	end

	CPBase:OnGameStartCheck()
end

function CPMain:OnPlayerSay(args)
	if args.text == '-help' or args.text == '-?' then
		self:Help(args.ply:GetPlayerID()+1)
	end
end

function CPMain:Help(playerid)
	UTIL_MessageText(playerid, "\n \n \n \n \n", 255, 255, 255, 255)
	UTIL_MessageText(playerid, "#cp_help_line1", 255, 255, 255, 255)
	UTIL_MessageText(playerid, "#cp_help_line2", 255, 255, 255, 255)
	UTIL_MessageText(playerid, "#cp_help_line3", 255, 255, 255, 255)
	UTIL_MessageText(playerid, "#cp_help_line4", 255, 255, 255, 255)
	UTIL_MessageText(playerid, "#cp_help_line5", 255, 255, 255, 255)

	Timers:CreateTimer(30, function() UTIL_ResetMessageText(playerid) end)
end


function CPMain:CheckPause()
	if self.gameTime == GameRules:GetGameTime() and self.isPaused == false then
		self.isPaused = true
		FireGameEvent("cp_game_pause", {state = true})
	end

	if self.gameTime ~= GameRules:GetGameTime() and self.isPaused == true then
		self.isPaused = false
		FireGameEvent("cp_game_pause", {state = false})
	end

	self.gameTime = GameRules:GetGameTime()

	return 1
end